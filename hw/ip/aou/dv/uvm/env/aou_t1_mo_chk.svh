// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// M-port outstanding limit, always on (MAS software-operation 7.2.2 and 3.6.2;
// integration guide M_RD_MO_CNT/M_WR_MO_CNT, default 32 and not overridden by
// the bench). The pending-ID tables hold one entry per remote request, from
// the first sub-burst's AR/AW handshake until the last sub-burst's RLAST or B,
// so the limit is on requests in service, not on M-port bursts: a request the
// splitter divides (MAX_AxBURSTLEN) puts up to ceil(beats / (MAX + 1)) bursts
// on the port under one entry. When the tables are full the DUT holds the
// first sub-burst of the next request, which is back-pressure, never an error.
// FEAT-R22: per RP, at most rd_mo read and wr_mo write requests are in
// service at the M port.
//
// Requests are rebuilt from the M port alone: a burst continues the request
// before it when it has the same ID, starts where that burst ended and that
// burst was a full MAX_AxBURSTLEN + 1 beats (an RP's limit comes from the
// register mirror); otherwise it starts a request. A request whose last burst
// was full stays open for one more burst until the next AR/AW of that RP shows
// whether it continues it. The grouping can only merge too much (a new request
// that happens to follow the previous one in address and ID under a full
// burst; with the AXI aggregator on, any contiguous same-ID burst), so the
// count is never above the true one and the check never fires falsely. cg_mo records how full each table got (bin full: the limit was
// reached, plan 9.20). A bus reset or AOU_SW_RESET clears the count.
class aou_t1_mo_chk extends uvm_component;
  `uvm_component_utils(aou_t1_mo_chk)

  aou_axi_vif_t vif[];
  aou_core      rm;                    // register mirror, for the per-RP split limits
  int unsigned  rd_mo = 32;
  int unsigned  wr_mo = 32;

  typedef struct {
    bit [15:0]       id;
    bit [63:0]       next_addr;        // where the next sub-burst would start
    bit              open;             // last burst was full: one more may follow
    int unsigned     pend;             // sub-bursts issued and not yet answered
  } req_t;

  protected req_t        reqs[][2][$];   // [rp][0 write, 1 read], issue order
  protected int unsigned bursts[][2];    // M-port bursts outstanding, for the report
  protected int unsigned peak[][2];      // requests
  protected int unsigned peak_bursts[][2];
  protected int unsigned n_over[][2];
  protected uvm_reg_field lim_fld[][2];
  protected uvm_reg_field agg_fld[];
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
    foreach (reqs[r, d]) reqs[r][d].delete();
    foreach (bursts[r, d]) bursts[r][d] = 0;
  endfunction

  // MAX_AxBURSTLEN of RP r from the register mirror (reset 15; an illegal
  // write is stored as 0xF, which the mirror's callback reproduces).
  protected function int unsigned max_len(int unsigned r, int d);
    uvm_reg rg;
    if (lim_fld[r][d] == null) begin
      if (rm == null) return 15;
      rg = rm.get_reg_by_name($sformatf("axi_split_tr_rp%0d", r));
      if (rg == null) return 15;
      lim_fld[r][d] = rg.get_field_by_name(d == 0 ? "max_awburstlen" : "max_arburstlen");
      if (lim_fld[r][d] == null) return 15;
    end
    return int'(lim_fld[r][d].get_mirrored_value());
  endfunction

  // AOU_CON0.RPn_AXI_AGGREGATOR_EN from the mirror. With the aggregator on,
  // M-port bursts are recombined beats and their length says nothing about
  // the split, so any contiguous same-ID burst may continue a request.
  protected function bit agg_en(int unsigned r);
    uvm_reg rg;
    uvm_reg_field f;
    if (agg_fld[r] == null) begin
      if (rm == null) return 1'b0;
      rg = rm.get_reg_by_name("aou_con0");
      if (rg == null) return 1'b0;
      agg_fld[r] = rg.get_field_by_name($sformatf("rp%0d_axi_aggregator_en", r));
      if (agg_fld[r] == null) return 1'b0;
    end
    return agg_fld[r].get_mirrored_value() != 0;
  endfunction

  // An AR or AW handshake on RP r.
  protected function void issued(int unsigned r, int d, bit [15:0] id, bit [63:0] addr,
                                 bit [7:0] len, bit [2:0] size, bit [1:0] burst);
    bit full = (burst == 2'b01) && ((int'(len) == int'(max_len(r, d))) || agg_en(r));
    bit [63:0] nxt = addr + ((64'(len) + 1) << size);
    int cont = -1;
    bursts[r][d]++;
    if (bursts[r][d] > peak_bursts[r][d]) peak_bursts[r][d] = bursts[r][d];
    // The most recent open request this burst continues, if any.
    for (int i = reqs[r][d].size() - 1; i >= 0; i--) begin
      if (reqs[r][d][i].open && reqs[r][d][i].id == id && reqs[r][d][i].next_addr == addr) begin
        cont = i;
        break;
      end
    end
    // Every other request that was only waiting for this handshake is complete.
    for (int i = reqs[r][d].size() - 1; i >= 0; i--) begin
      if (i != cont && reqs[r][d][i].open && reqs[r][d][i].pend == 0) begin
        reqs[r][d].delete(i);
        if (cont > i) cont--;
      end
    end
    if (cont >= 0) begin
      reqs[r][d][cont].pend++;
      reqs[r][d][cont].next_addr = nxt;
      reqs[r][d][cont].open = full;
      return;
    end
    begin
      req_t q;
      q.id = id;
      q.next_addr = nxt;
      q.open = full;
      q.pend = 1;
      reqs[r][d].push_back(q);
    end
    if (reqs[r][d].size() > peak[r][d]) peak[r][d] = reqs[r][d].size();
    cv_dir = 2'(d);
    cv_occ = reqs[r][d].size();
    cg_mo.sample();
    fc_mo.sample(d, int'(reqs[r][d].size()));
    aou_rule_pkg::aou_rule_log::check("FEAT-R22", get_type_name());
    if (reqs[r][d].size() > limit(d) && n_over[r][d]++ == 0) begin
      aou_rule_pkg::aou_rule_log::fire("FEAT-R22", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R22: RP%0d M port has %0d %s in service, limit %0d", r, reqs[r][d].size(),
          kind(d), limit(d)))
    end
  endfunction

  // A B or last-R handshake on RP r: answers the oldest sub-burst of that ID.
  protected function void completed(int unsigned r, int d, bit [15:0] id);
    if (bursts[r][d] > 0) bursts[r][d]--;
    foreach (reqs[r][d][i]) begin
      if (reqs[r][d][i].id == id && reqs[r][d][i].pend > 0) begin
        reqs[r][d][i].pend--;
        if (reqs[r][d][i].pend == 0 && !reqs[r][d][i].open) reqs[r][d].delete(i);
        return;
      end
    end
  endfunction

  task watch(int unsigned r);
    forever begin
      @(vif[r].mon_cb);
      if (vif[r].mon_cb.resetn !== 1'b1) begin
        reqs[r][0].delete();
        reqs[r][1].delete();
        bursts[r][0] = 0;
        bursts[r][1] = 0;
        continue;
      end
      if (vif[r].mon_cb.bvalid === 1'b1 && vif[r].mon_cb.bready === 1'b1)
        completed(r, 0, 16'(vif[r].mon_cb.bid));
      if (vif[r].mon_cb.rvalid === 1'b1 && vif[r].mon_cb.rready === 1'b1 &&
          vif[r].mon_cb.rlast === 1'b1)
        completed(r, 1, 16'(vif[r].mon_cb.rid));
      if (vif[r].mon_cb.awvalid === 1'b1 && vif[r].mon_cb.awready === 1'b1)
        issued(r, 0, 16'(vif[r].mon_cb.awid), 64'(vif[r].mon_cb.awaddr),
               8'(vif[r].mon_cb.awlen), vif[r].mon_cb.awsize, vif[r].mon_cb.awburst);
      if (vif[r].mon_cb.arvalid === 1'b1 && vif[r].mon_cb.arready === 1'b1)
        issued(r, 1, 16'(vif[r].mon_cb.arid), 64'(vif[r].mon_cb.araddr),
               8'(vif[r].mon_cb.arlen), vif[r].mon_cb.arsize, vif[r].mon_cb.arburst);
    end
  endtask

  task run_phase(uvm_phase phase);
    reqs = new[vif.size()];
    bursts = new[vif.size()];
    peak = new[vif.size()];
    peak_bursts = new[vif.size()];
    n_over = new[vif.size()];
    lim_fld = new[vif.size()];
    agg_fld = new[vif.size()];
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
           "(%0d write and %0d read bursts outstanding)"}, r,
          peak[r][0], wr_mo, peak[r][1], rd_mo, peak_bursts[r][0], peak_bursts[r][1]), UVM_LOW)
  endfunction
endclass
