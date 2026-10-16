// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// R/B response error debug FIFO and its debug window (MAS software-operation
// 7.2.4), checked in every test from what the env observes.
//
// Model: per RP a FIFO of `depth` entries. A remote-die transaction that
// completes with an error the DUT got from its own M port (a B or R error on
// that M port with the same ID inside the transaction's bytes) pushes one
// entry {ID, ADDR aligned down to the request size, RESP} (BUGS/028 interim
// layout; one entry per remote request, BUGS/041), at the time of its first
// M-port error. A push into a full FIFO is dropped. Errors the DUT makes up
// itself never reach the M port and push nothing. Errors whose M-port
// responses are within order_cycles of each other may enter in either order:
// the MAS orders nothing between B and R errors close together, and the DUT's
// B and R capture paths differ in latency.
//
// A remote access is a debug-window access when its address equals RP r's
// {DEBUG_UPPER_ADDR, DEBUG_LOWER_ADDR} and RPr_ERROR_INFO_ACCESS_EN is set
// (register mirror). Reads and pops (writes) of any length within 4 KB:
//   T1-E03  every RRESP of a read and the BRESP of a pop is OKAY;
//   T1-E19  every RP-wide lane of every read beat equals the head entry:
//           remote beats at least as wide as the RP hold whole RP beats, so
//           every lane equals lane 0 of beat 0; narrower remote beats are
//           slices of RP beats, so beat k equals beat k mod (RP / remote);
//   T1-E02  the head, {ID, ADDR, RESP} in the low 76 bits of beat 0, is the
//           predicted head (any entry of a group pushed together). Not judged
//           while an M-port error the model has not placed yet is older than
//           the read, or after a drop the model could not order.
// A pop removes the entry the last read returned, or the head.
class aou_t1_dbg_fifo_chk extends uvm_component;
  `uvm_component_utils(aou_t1_dbg_fifo_chk)

  uvm_analysis_imp_dbg_mport #(aou_axi_txn, aou_t1_dbg_fifo_chk)  mport_imp;
  uvm_analysis_imp_dbg_remote #(aou_axi_txn, aou_t1_dbg_fifo_chk) remote_imp;

  aou_t1_env_cfg cfg;
  aou_core       rm;
  aou_axi_vif_t  clk_vif;
  int unsigned   depth = 4;
  int unsigned   order_cycles = 32;

  typedef struct packed {
    bit [9:0]  id;
    bit [63:0] addr;
    bit [3:0]  resp_ok;   // RESP values the entry may hold
    bit [63:0] cyc;
  } ent_t;

  // An M-port error not yet matched to its remote transaction.
  typedef struct packed {
    bit [9:0]  id;
    bit [63:0] lo;
    bit [63:0] hi;
    bit [63:0] cyc;
    bit [63:0] t;
  } merr_t;

  int unsigned n_push;
  int unsigned n_drop;
  int unsigned n_read;
  int unsigned n_pop;

  protected ent_t            q[AOU_RP_MAX][$];
  protected merr_t           merr[AOU_RP_MAX][$];
  protected bit              unsure[AOU_RP_MAX];
  protected int              read_idx[AOU_RP_MAX];
  protected longint unsigned cycle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    mport_imp = new("mport_imp", this);
    remote_imp = new("remote_imp", this);
    foreach (read_idx[r]) read_idx[r] = -1;
  endfunction

  task run_phase(uvm_phase phase);
    if (clk_vif == null) return;
    forever begin
      @(clk_vif.mon_cb);
      cycle++;
    end
  endtask

  // Reset contract: a core or software reset empties every FIFO.
  function void reset_flush();
    foreach (q[r]) begin
      q[r].delete();
      merr[r].delete();
      unsure[r] = 1'b0;
      read_idx[r] = -1;
    end
  endfunction

  static function bit is_err(bit [1:0] resp);
    return resp inside {AOU_AXI_SLVERR, AOU_AXI_DECERR};
  endfunction

  // Error RESP values of t's beats (bit v: some beat answered v).
  static function bit [3:0] err_mask(aou_axi_txn t);
    bit [3:0] m = '0;
    if (t.dir == AOU_AXI_WR) begin
      if (is_err(t.bresp)) m[t.bresp] = 1'b1;
    end else begin
      foreach (t.rresp[k]) if (is_err(t.rresp[k])) m[t.rresp[k]] = 1'b1;
    end
    return m;
  endfunction

  static function bit [63:0] lo_of(aou_axi_txn t);
    return t.addr & ~((64'd1 << t.size) - 64'd1);
  endfunction

  static function bit [63:0] hi_of(aou_axi_txn t);
    return lo_of(t) + (64'(t.len) + 64'd1) * (64'd1 << t.size) - 64'd1;
  endfunction

  function bit [63:0] window_of(int unsigned r, output bit en);
    uvm_reg_field f;
    uvm_reg       up;
    uvm_reg       lo;
    en = 1'b0;
    if (rm == null) return '0;
    f = rm.aou_con0.get_field_by_name($sformatf("rp%0d_error_info_access_en", r));
    up = rm.get_reg_by_name($sformatf("axi_error_info0_rp%0d", r));
    lo = rm.get_reg_by_name($sformatf("axi_error_info1_rp%0d", r));
    if (f == null || up == null || lo == null) return '0;
    en = f.get_mirrored_value() != 0;
    return {32'(up.get_field_by_name("debug_upper_addr").get_mirrored_value()),
            32'(lo.get_field_by_name("debug_lower_addr").get_mirrored_value())};
  endfunction

  // The DUT RP a remote plane's requests land on (MAS 3.10.2).
  function int unsigned dut_rp(int unsigned plane);
    return (plane < AOU_RP_MAX) ? int'(cfg.l3_cfg.dest_rp[plane]) : plane;
  endfunction

  function void write_dbg_mport(aou_axi_txn t);
    merr_t e;
    if (t.aborted || err_mask(t) == '0 || t.rp >= AOU_RP_MAX) return;
    e.id = t.id;
    e.lo = lo_of(t);
    e.hi = hi_of(t);
    e.cyc = cycle;
    e.t = 64'($time);
    merr[t.rp].push_back(e);
  endfunction

  function void write_dbg_remote(aou_axi_txn t);
    int unsigned r;
    bit en;
    bit [63:0] w;
    if (t.aborted) return;
    r = dut_rp(t.rp);
    if (r >= cfg.n_rp) return;
    w = window_of(r, en);
    if (en && t.addr == w) begin
      if (t.dir == AOU_AXI_RD) dbg_read(r, t);
      else dbg_pop(r, t);
    end else if (err_mask(t) != '0) begin
      place(r, t);
    end
  endfunction

  // t completed with an error: push its entry if the error came from the M port.
  protected function void place(int unsigned r, aou_axi_txn t);
    bit [63:0] lo = lo_of(t);
    bit [63:0] hi = hi_of(t);
    bit        hit = 1'b0;
    ent_t      e;
    int        pos;
    for (int i = 0; i < merr[r].size(); i++) begin
      if (merr[r][i].id != t.id || merr[r][i].hi < lo || merr[r][i].lo > hi) continue;
      if (!hit || merr[r][i].cyc < e.cyc) e.cyc = merr[r][i].cyc;
      hit = 1'b1;
      merr[r].delete(i);
      i--;
    end
    if (!hit) return;
    e.id = t.id;
    e.addr = lo;
    e.resp_ok = err_mask(t);
    n_push++;
    if (q[r].size() >= depth) begin
      n_drop++;
      // A drop at the order boundary leaves which entry was kept unknown.
      if (e.cyc <= q[r][q[r].size() - 1].cyc + 64'(order_cycles)) unsure[r] = 1'b1;
      `uvm_info(get_type_name(), $sformatf("RP%0d FIFO full: id=%0h addr=%0h dropped", r, e.id,
                                           e.addr), UVM_MEDIUM)
      return;
    end
    pos = q[r].size();
    while (pos > 0 && q[r][pos - 1].cyc > e.cyc) pos--;
    q[r].insert(pos, e);
    `uvm_info(get_type_name(), $sformatf("RP%0d FIFO push: id=%0h addr=%0h resp=%b (%0d held)", r,
                                         e.id, e.addr, e.resp_ok, q[r].size()), UVM_MEDIUM)
  endfunction

  protected function void dbg_read(int unsigned r, aou_axi_txn t);
    n_read++;
    aou_rule_log::check("T1-E03", get_type_name());
    foreach (t.rresp[k]) begin
      if (t.rresp[k] != AOU_AXI_OKAY) begin
        aou_rule_log::fire("T1-E03", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            "T1-E03: RP%0d debug FIFO read RRESP %0d (beat %0d of %0d)", r, t.rresp[k], k,
            t.rresp.size()))
        break;
      end
    end
    check_lanes(r, t);
    check_head(r, t);
  endfunction

  protected function void dbg_pop(int unsigned r, aou_axi_txn t);
    n_pop++;
    aou_rule_log::check("T1-E03", get_type_name());
    if (t.bresp != AOU_AXI_OKAY) begin
      aou_rule_log::fire("T1-E03", get_type_name());
      `uvm_error(get_type_name(), $sformatf("T1-E03: RP%0d debug FIFO pop BRESP %0d", r, t.bresp))
    end
    if (q[r].size() != 0) q[r].delete((read_idx[r] >= 0 && read_idx[r] < q[r].size()) ?
                                      read_idx[r] : 0);
    read_idx[r] = -1;
  endfunction

  // T1-E19 on a debug read t of RP r.
  protected function void check_lanes(int unsigned r, aou_axi_txn t);
    int unsigned rw = t.data_bytes;
    int unsigned pw = cfg.rp_bytes[r];
    int unsigned bad = 0;
    int unsigned total = 0;
    int unsigned bk = 0;
    int unsigned bl = 0;
    if (t.data.size() == 0) return;
    for (int unsigned k = 0; k < t.data.size(); k++) begin
      if (rw >= pw) begin
        for (int unsigned l = 0; l < rw / pw; l++) begin
          bit diff = 1'b0;
          total++;
          for (int unsigned b = 0; b < pw; b++)
            if (t.data[k][8*(l*pw+b) +: 8] != t.data[0][8*b +: 8]) diff = 1'b1;
          if (diff && bad++ == 0) begin
            bk = k;
            bl = l;
          end
        end
      end else if (k >= pw / rw) begin
        bit diff = 1'b0;
        total++;
        for (int unsigned b = 0; b < rw; b++)
          if (t.data[k][8*b +: 8] != t.data[k % (pw / rw)][8*b +: 8]) diff = 1'b1;
        if (diff && bad++ == 0) bk = k;
      end
    end
    aou_rule_log::check("T1-E19", get_type_name());
    if (bad != 0) begin
      aou_rule_log::fire("T1-E19", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"T1-E19: RP%0d debug FIFO read: %0d of %0d RP-wide lanes differ from the head entry ",
           "(first: beat %0d lane %0d; %0d beats of %0d bytes, %0d-byte RP)"},
          r, bad, total, bk, bl, t.data.size(), rw, pw))
    end
  endfunction

  // T1-E02: beat 0 holds the predicted head (or an entry pushed with it).
  protected function void check_head(int unsigned r, aou_axi_txn t);
    bit [1023:0] d;
    bit [9:0]    id;
    bit [63:0]   addr;
    bit [1:0]    resp;
    int unsigned grp = 1;
    string       exp = "";
    read_idx[r] = -1;
    if (t.data.size() == 0 || q[r].size() == 0 || unsure[r]) return;
    for (int i = 0; i < merr[r].size(); i++) if (merr[r][i].t < 64'(t.t_addr)) return;
    d = t.data[0];
    resp = d[1:0];
    addr = d[65:2];
    id = d[75:66];
    while (grp < q[r].size() && q[r][grp].cyc <= q[r][grp - 1].cyc + 64'(order_cycles)) grp++;
    aou_rule_log::check("T1-E02", get_type_name());
    for (int unsigned i = 0; i < grp; i++) begin
      if (q[r][i].id == id && q[r][i].addr == addr && q[r][i].resp_ok[resp]) begin
        read_idx[r] = i;
        return;
      end
      exp = {exp, i == 0 ? "" : " or ", $sformatf("id=%0h addr=%0h resp %b", q[r][i].id,
                                                    q[r][i].addr, q[r][i].resp_ok)};
    end
    aou_rule_log::fire("T1-E02", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
        "T1-E02: RP%0d FIFO head id=%0h addr=%0h resp=%0d, expected %s (%0d entries held)", r, id,
        addr, resp, exp, q[r].size()))
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned left = 0;
    foreach (merr[r]) left += merr[r].size();
    if (n_push + n_read + n_pop != 0)
      `uvm_info(get_type_name(), $sformatf(
          "debug FIFO: %0d pushes (%0d dropped), %0d reads, %0d pops; %0d M-port errors unplaced",
          n_push, n_drop, n_read, n_pop, left), UVM_LOW)
  endfunction
endclass
