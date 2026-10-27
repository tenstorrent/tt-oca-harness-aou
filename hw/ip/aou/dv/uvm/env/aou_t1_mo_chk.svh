// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// M-port outstanding limit, always on (MAS software-operation 7.2.2 and 3.6.2;
// integration guide M_RD_MO_CNT/M_WR_MO_CNT, which the top builds AOU_TOP with
// from AOU_T1_M_MO_CNT, 32 by default). The pending-ID tables hold one entry per remote request, from
// the first sub-burst's AR/AW handshake until the last sub-burst's RLAST or B,
// so the limit is on requests in service, not on M-port bursts: a request the
// splitter divides (MAX_AxBURSTLEN) puts up to ceil(beats / (MAX + 1)) bursts
// on the port under one entry. When the tables are full the DUT holds the
// first sub-burst of the next request, which is back-pressure, never an error.
// FEAT-R22: per RP, at most rd_mo read and wr_mo write requests are in
// service at the M port.
//
// Requests come from the remote die's ReadReq/WriteReq messages (L3
// ap_tx_msg, seen as the message enters a flit, before the DUT can act on
// it): RP, ID and the size-aligned byte range. An M-port AR/AW belongs to the
// oldest request of its RP, direction and ID whose range it overlaps and
// that is not yet fully issued; the splitter issues one request's sub-bursts
// in order and requests of one ID in order, so that request is the right one
// whatever the sub-burst lengths, alignment or width conversion. The first
// burst matched puts the request in service; the B or last R of its last
// burst (bursts are answered in order per ID) takes it out. A burst that
// matches no request counts as a request of its own rather than being
// dropped. A request the DUT answers without putting it on the M port leaves
// the list on its WriteResp/ReadData (L3 ap_rx_msg); one the DUT never
// answers leaves when a later request of the same ID starts. The DUT's
// table allocates at its internal AR/AW handshake and frees when the
// response has passed its register slices, so it runs a few cycles ahead of
// this count and never behind it (checked against r_arcnt/r_awcnt of
// AOU_SPLIT_RD/WR_PENDING_INFO while this checker was written). cg_mo
// records how full each table got (bin full: the limit was reached, plan
// 9.20). A bus reset or AOU_SW_RESET clears everything.
`uvm_analysis_imp_decl(_mo_dut)

class aou_t1_mo_chk extends uvm_component;
  `uvm_component_utils(aou_t1_mo_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_mo_chk)        rem_msg_imp;   // L3 ap_tx_msg
  uvm_analysis_imp_mo_dut #(aou_msg, aou_t1_mo_chk) dut_msg_imp;   // L3 ap_rx_msg

  aou_axi_vif_t vif[];
  aou_l3_cfg    l3_cfg;    // dest_rp: the remote die's plane -> the DUT's RP, for the responses
  int unsigned  rd_mo = AOU_T1_M_MO_CNT;
  int unsigned  wr_mo = AOU_T1_M_MO_CNT;

  typedef struct {
    int unsigned     seq;
    bit [9:0]        id;
    bit [64:0]       lo;               // size-aligned first byte
    bit [64:0]       hi;               // one past the last byte (65 bits: the map's top)
    bit [64:0]       issued;           // one past the last byte put on the M port
    bit              started;          // holds a table entry
    int unsigned     pend;             // bursts issued and not yet answered
  } req_t;

  typedef struct {
    int unsigned     seq;
    bit [9:0]        id;
  } burst_t;

  protected req_t        reqs[][2][$];     // [rp][0 write, 1 read], arrival order
  protected burst_t      bursts[][2][$];   // M-port bursts outstanding, issue order
  protected bit [9:0]    served[][2][$];   // IDs of requests done at the M port, response pending
  protected int unsigned insvc[][2];
  protected int unsigned peak[][2];        // requests
  protected int unsigned peak_bursts[][2];
  protected int unsigned n_over[][2];
  protected int unsigned n_unmatched[][2]; // bursts no request claimed
  protected int unsigned n_stray[][2];     // B/last R with no burst outstanding
  protected int unsigned seq_next;
  protected bit [1:0]    cv_dir;
  protected int unsigned cv_occ;
  protected aou_fc_group fc_mo;

  covergroup cg_mo;
    cp_dir: coverpoint cv_dir {
      `AOU_T1_MO_FC_DIR(AOU_FC_CG)
    }
    cp_occ: coverpoint cv_occ {
      `AOU_T1_MO_FC_OCC(AOU_FC_CG)
    }
    x_mo: cross cp_dir, cp_occ;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rem_msg_imp = new("rem_msg_imp", this);
    dut_msg_imp = new("dut_msg_imp", this);
    cg_mo = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_mo = db.group("t1.mo_cg", fresh);
    if (fresh) begin
      p = fc_mo.cp("cp_dir"); `AOU_T1_MO_FC_DIR(AOU_FC_REG)
      p = fc_mo.cp("cp_occ"); `AOU_T1_MO_FC_OCC(AOU_FC_REG)
      void'(fc_mo.add_cross("x_mo", "cp_dir cp_occ"));
    end
  endfunction

  static function string kind(int d);
    if (d == 0) return "writes";
    return "reads";
  endfunction

  function int unsigned limit(int d);
    return d == 0 ? wr_mo : rd_mo;
  endfunction

  function void clear();
    foreach (reqs[r, d]) clear_rp(r, d);
  endfunction

  protected function void clear_rp(int unsigned r, int d);
    reqs[r][d].delete();
    bursts[r][d].delete();
    served[r][d].delete();
    insvc[r][d] = 0;
  endfunction

  static function bit [64:0] align_down(bit [63:0] a, bit [2:0] size);
    bit [63:0] mask = (64'd1 << size) - 64'd1;
    return {1'b0, a & ~mask};
  endfunction

  // The DUT's RP behind the RP field of a message it sent: that field is the
  // remote die's plane (the DUT's DEST_RP), whose inverse the remote die holds.
  protected function int unsigned dut_rp(bit [1:0] wire_rp);
    if (l3_cfg == null) return int'(wire_rp);
    return int'(l3_cfg.dest_rp[wire_rp]);
  endfunction

  // A remote request message: its byte range is what the M port must cover.
  // A message the remote die corrupts on purpose (raw granules, a length
  // change) is not a request the DUT can parse; a bit flip may land anywhere,
  // so the message is kept with the fields the remote die meant.
  function void write(aou_msg m);
    aou_msg_req rq;
    req_t q;
    int d;
    if (reqs.size() == 0 || int'(m.rp) >= reqs.size()) return;
    if (!(m.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ}) || !$cast(rq, m)) return;
    if (m.raw_g.size() > 0 || m.len_adj != 0) return;
    d = (m.msg_type == AOU_MT_WREQ) ? 0 : 1;
    q.seq = seq_next++;
    q.id = rq.id;
    q.lo = align_down(rq.addr, rq.size);
    q.hi = q.lo + ((65'(rq.len) + 65'd1) << rq.size);
    q.issued = q.lo;
    q.started = 1'b0;
    q.pend = 0;
    reqs[m.rp][d].push_back(q);
  endfunction

  // A DUT response message. The response of a request the M port served
  // follows its last B or R (served[] holds those, in order per ID). Any
  // other response answers the oldest request of its ID; when the DUT never
  // put that request on the M port, it is done and leaves the list.
  function void write_mo_dut(aou_msg m);
    aou_msg_wresp w;
    aou_msg_rdata rd;
    bit [9:0] id;
    int unsigned r;
    int d;
    if (reqs.size() == 0) return;
    r = dut_rp(m.rp);
    if (r >= reqs.size()) return;
    if (m.msg_type == AOU_MT_WRESP && $cast(w, m)) begin
      d = 0;
      id = w.id;
    end else if (m.msg_type == AOU_MT_RDATA && $cast(rd, m) && rd.last) begin
      d = 1;
      id = rd.id;
    end else return;
    for (int i = 0; i < served[r][d].size(); i++) begin
      if (served[r][d][i] == id) begin
        served[r][d].delete(i);
        return;
      end
    end
    for (int i = 0; i < reqs[r][d].size(); i++) begin
      if (reqs[r][d][i].id == id) begin
        if (!reqs[r][d][i].started) reqs[r][d].delete(i);
        return;
      end
    end
  endfunction

  protected function void entered(int unsigned r, int d);
    insvc[r][d]++;
    if (insvc[r][d] > peak[r][d]) peak[r][d] = insvc[r][d];
    cv_dir = 2'(d);
    cv_occ = insvc[r][d];
    cg_mo.sample();
    fc_mo.sample(d, int'(insvc[r][d]));
    aou_rule_pkg::aou_rule_log::check("FEAT-R22", get_type_name());
    if (insvc[r][d] > limit(d) && n_over[r][d]++ == 0) begin
      aou_rule_pkg::aou_rule_log::fire("FEAT-R22", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R22: RP%0d M port has %0d %s in service, limit %0d", r, insvc[r][d],
          kind(d), limit(d)))
    end
  endfunction

  // An AR or AW handshake on RP r.
  protected function void issued(int unsigned r, int d, bit [9:0] id, bit [63:0] addr,
                                 bit [7:0] len, bit [2:0] size);
    bit [64:0] blo = align_down(addr, size);
    bit [64:0] bhi = blo + ((65'(len) + 65'd1) << size);
    burst_t b;
    int k = -1;
    for (int i = 0; i < reqs[r][d].size(); i++) begin
      if (reqs[r][d][i].id == id && reqs[r][d][i].issued < reqs[r][d][i].hi &&
          blo < reqs[r][d][i].hi && bhi > reqs[r][d][i].lo) begin
        k = i;
        break;
      end
    end
    if (k < 0) begin
      req_t q;
      n_unmatched[r][d]++;
      q.seq = seq_next++;
      q.id = id;
      q.lo = blo;
      q.hi = bhi;
      q.issued = blo;
      q.started = 1'b0;
      q.pend = 0;
      reqs[r][d].push_back(q);
      k = reqs[r][d].size() - 1;
    end
    if (!reqs[r][d][k].started) begin
      reqs[r][d][k].started = 1'b1;
      entered(r, d);
      // Older requests of this ID the DUT never issued are not coming.
      for (int i = k - 1; i >= 0; i--) begin
        if (reqs[r][d][i].id == id && !reqs[r][d][i].started) begin
          reqs[r][d].delete(i);
          k--;
        end
      end
    end
    if (bhi > reqs[r][d][k].issued) reqs[r][d][k].issued = bhi;
    reqs[r][d][k].pend++;
    b.seq = reqs[r][d][k].seq;
    b.id = id;
    bursts[r][d].push_back(b);
    if (bursts[r][d].size() > peak_bursts[r][d]) peak_bursts[r][d] = bursts[r][d].size();
  endfunction

  // A B or last-R handshake on RP r: answers the oldest burst of that ID.
  protected function void completed(int unsigned r, int d, bit [9:0] id);
    int unsigned seq;
    int k = -1;
    for (int i = 0; i < bursts[r][d].size(); i++) begin
      if (bursts[r][d][i].id == id) begin
        k = i;
        break;
      end
    end
    if (k < 0) begin
      n_stray[r][d]++;
      return;
    end
    seq = bursts[r][d][k].seq;
    bursts[r][d].delete(k);
    for (int i = 0; i < reqs[r][d].size(); i++) begin
      if (reqs[r][d][i].seq == seq) begin
        if (reqs[r][d][i].pend > 0) reqs[r][d][i].pend--;
        if (reqs[r][d][i].pend == 0 && reqs[r][d][i].issued >= reqs[r][d][i].hi) begin
          served[r][d].push_back(id);
          reqs[r][d].delete(i);
          if (insvc[r][d] > 0) insvc[r][d]--;
        end
        return;
      end
    end
  endfunction

  task watch(int unsigned r);
    forever begin
      @(vif[r].mon_cb);
      if (vif[r].mon_cb.resetn !== 1'b1) begin
        clear_rp(r, 0);
        clear_rp(r, 1);
        continue;
      end
      if (vif[r].mon_cb.bvalid === 1'b1 && vif[r].mon_cb.bready === 1'b1)
        completed(r, 0, 10'(vif[r].mon_cb.bid));
      if (vif[r].mon_cb.rvalid === 1'b1 && vif[r].mon_cb.rready === 1'b1 &&
          vif[r].mon_cb.rlast === 1'b1)
        completed(r, 1, 10'(vif[r].mon_cb.rid));
      if (vif[r].mon_cb.awvalid === 1'b1 && vif[r].mon_cb.awready === 1'b1)
        issued(r, 0, 10'(vif[r].mon_cb.awid), 64'(vif[r].mon_cb.awaddr),
               8'(vif[r].mon_cb.awlen), vif[r].mon_cb.awsize);
      if (vif[r].mon_cb.arvalid === 1'b1 && vif[r].mon_cb.arready === 1'b1)
        issued(r, 1, 10'(vif[r].mon_cb.arid), 64'(vif[r].mon_cb.araddr),
               8'(vif[r].mon_cb.arlen), vif[r].mon_cb.arsize);
    end
  endtask

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    reqs = new[vif.size()];
    bursts = new[vif.size()];
    served = new[vif.size()];
    insvc = new[vif.size()];
    peak = new[vif.size()];
    peak_bursts = new[vif.size()];
    n_over = new[vif.size()];
    n_unmatched = new[vif.size()];
    n_stray = new[vif.size()];
  endfunction

  task run_phase(uvm_phase phase);
    foreach (vif[r]) begin
      fork
        automatic int unsigned rr = r;
        watch(rr);
      join_none
    end
  endtask

  function void report_phase(uvm_phase phase);
    foreach (peak[r])
      `uvm_info(get_type_name(), $sformatf(
          {"RP%0d M port: at most %0d of %0d writes and %0d of %0d reads in service ",
           "(%0d write and %0d read bursts outstanding; %0d/%0d bursts matched no request, ",
           "%0d/%0d responses no burst)"}, r,
          peak[r][0], wr_mo, peak[r][1], rd_mo, peak_bursts[r][0], peak_bursts[r][1],
          n_unmatched[r][0], n_unmatched[r][1], n_stray[r][0], n_stray[r][1]), UVM_LOW)
  endfunction
endclass
