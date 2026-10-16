// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Flit layouts in both directions, rebuilt from where each message travelled
// (L3 ap_rx_msg: sent by the DUT; ap_tx_msg: sent to the DUT), plus FDI
// back-to-back runs from the L1 monitor. A test lists what its stimulus must
// have produced in `req` ("<TX|RX>:<key>" or "<TX|RX>:<key>>=<n>"); check_phase
// fails it (DP-R01) when a layout never occurred, since the test would then
// prove nothing. Keys, counted per flit unless noted:
//   span_<W|F|R><g>  a WriteData/WriteDataFull/ReadData of g granules spans flits (per message)
//   span_wdata       a WriteData or WriteDataFull of any size spans flits (per message)
//   single           exactly one MsgStart, no continuation
//   single_off       the same, starting after G0
//   mixed_bubble     WriteReq, ReadReq and WriteResp start here, with an empty
//                    granule between two messages
//   full             all 48 granules carry messages and none spans out (ends at G47)
//   wresp_max        most WriteResp starting in one flit (a maximum)
//   multi_rp         AXI messages of at least two RPs start here
//   misc2_half       at least two Misc messages start in one half
//   act, crdt        Activation / CrdtGrant messages (per message)
//   prof             AXI messages with a nonzero PROF (per message)
//   b2b_run          longest run of flits with no idle cycle before or inside (a maximum)
class aou_pack_stats extends uvm_component;
  `uvm_component_utils(aou_pack_stats)

  uvm_tlm_analysis_fifo #(aou_msg) dut_fifo;   // DUT -> model (TX)
  uvm_tlm_analysis_fifo #(aou_msg) tb_fifo;    // model -> DUT (RX)
  uvm_analysis_imp_l1tx #(aou_flit_item, aou_pack_stats) l1_tx_imp;
  uvm_analysis_imp_l1rx #(aou_flit_item, aou_pack_stats) l1_rx_imp;

  string       req[$];
  int unsigned cnt[2][string];
  protected aou_msg msgs[2][int][$];   // by start flit
  protected int unsigned run[2];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dut_fifo = new("dut_fifo", this);
    tb_fifo  = new("tb_fifo", this);
    l1_tx_imp = new("l1_tx_imp", this);
    l1_rx_imp = new("l1_rx_imp", this);
  endfunction

  static function string dname(int d);
    return d == 0 ? "TX" : "RX";
  endfunction

  function void bump(int d, string key, int unsigned n = 1);
    if (cnt[d].exists(key)) cnt[d][key] += n;
    else cnt[d][key] = n;
  endfunction

  function void keep_max(int d, string key, int unsigned v);
    if (!cnt[d].exists(key) || cnt[d][key] < v) cnt[d][key] = v;
  endfunction

  function void l1(aou_flit_item f, int d);
    if (f.gap_before == 0 && f.n_stall_cycles == 0) run[d]++;
    else run[d] = 1;
    keep_max(d, "b2b_run", run[d]);
  endfunction

  function void write_l1tx(aou_flit_item f);
    l1(f, 0);
  endfunction

  function void write_l1rx(aou_flit_item f);
    l1(f, 1);
  endfunction

  function void take(aou_msg m, int d);
    aou_msg_crdtgrant g;
    aou_msg_act a;
    if (m.start_flit < 0) return;
    msgs[d][m.start_flit].push_back(m);
    if (m.span_flits > 1 && m.msg_type inside {AOU_MT_WDATA, AOU_MT_WDATAF, AOU_MT_RDATA}) begin
      string t = m.msg_type == AOU_MT_WDATA ? "W" : m.msg_type == AOU_MT_WDATAF ? "F" : "R";
      bump(d, $sformatf("span_%s%0d", t, m.num_granules()));
      if (m.msg_type != AOU_MT_RDATA) bump(d, "span_wdata");
    end
    if ($cast(a, m)) bump(d, "act");
    if ($cast(g, m)) bump(d, "crdt");
    if (m.cred_class() != AOU_CC_NONE && m.flex[11:0] != 0) bump(d, "prof");
  endfunction

  task run_phase(uvm_phase phase);
    aou_msg m;
    fork
      forever begin dut_fifo.get(m); take(m, 0); end
      forever begin tb_fifo.get(m); take(m, 1); end
    join
  endtask

  // Per-flit layout keys once every message is in.
  function void layouts(int d);
    bit [47:0] occ[int];
    bit        spans_out[int];
    foreach (msgs[d][f]) begin
      foreach (msgs[d][f][i]) begin
        aou_msg m = msgs[d][f][i];
        int unsigned n = m.num_granules();
        for (int unsigned k = 0; k < n; k++) begin
          int unsigned gg = m.start_granule + k;
          int ff = f + int'(gg / AOU_GRANULES);
          if (!occ.exists(ff)) occ[ff] = '0;
          occ[ff][gg % AOU_GRANULES] = 1'b1;
          if (ff != f) spans_out[f] = 1'b1;
        end
      end
    end
    foreach (msgs[d][f]) begin
      aou_msg q[$] = msgs[d][f];
      bit has_wreq, has_rreq, has_wresp;
      int unsigned n_wresp = 0;
      int unsigned misc_h[2] = '{0, 0};
      int rp0 = -1;
      bit multi = 1'b0;
      int lo = AOU_GRANULES, hi = -1;
      bit carry = 1'b0;
      foreach (q[i]) begin
        int sg = q[i].start_granule;
        if (q[i].msg_type == AOU_MT_WREQ) has_wreq = 1'b1;
        if (q[i].msg_type == AOU_MT_RREQ) has_rreq = 1'b1;
        if (q[i].msg_type == AOU_MT_WRESP) begin has_wresp = 1'b1; n_wresp++; end
        if (q[i].msg_type == AOU_MT_MISC) misc_h[sg / AOU_HALF_G]++;
        if (q[i].cred_class() != AOU_CC_NONE) begin
          if (rp0 < 0) rp0 = int'(q[i].rp);
          else if (rp0 != int'(q[i].rp)) multi = 1'b1;
        end
        if (sg < lo) lo = sg;
        if (sg + int'(q[i].num_granules()) - 1 > hi) hi = sg + int'(q[i].num_granules()) - 1;
      end
      if (msgs[d].exists(f - 1)) foreach (msgs[d][f-1][i])
        if (msgs[d][f-1][i].start_granule + msgs[d][f-1][i].num_granules() > AOU_GRANULES)
          carry = 1'b1;
      if (q.size() == 1 && !carry) begin
        bump(d, "single");
        if (q[0].start_granule > 0) bump(d, "single_off");
      end
      if (has_wreq && has_rreq && has_wresp) begin
        bit hole = 1'b0;
        if (hi >= AOU_GRANULES) hi = AOU_GRANULES - 1;
        for (int k = lo; k <= hi; k++) if (!occ[f][k]) hole = 1'b1;
        if (hole) bump(d, "mixed_bubble");
      end
      if (occ[f] == '1 && !spans_out.exists(f)) bump(d, "full");
      keep_max(d, "wresp_max", n_wresp);
      if (multi) bump(d, "multi_rp");
      if (misc_h[0] >= 2 || misc_h[1] >= 2) bump(d, "misc2_half");
    end
  endfunction

  function void check_phase(uvm_phase phase);
    aou_msg m;
    while (dut_fifo.try_get(m)) take(m, 0);
    while (tb_fifo.try_get(m)) take(m, 1);
    layouts(0);
    layouts(1);
    foreach (req[i]) begin
      string r = req[i];
      int d = (r.substr(0, 1) == "TX") ? 0 : 1;
      string key = r.substr(3, r.len() - 1);
      int unsigned need = 1;
      int unsigned have;
      for (int k = 0; k + 1 < key.len(); k++) begin
        if (key.substr(k, k + 1) == ">=") begin
          need = key.substr(k + 2, key.len() - 1).atoi();
          key = key.substr(0, k - 1);
          break;
        end
      end
      have = cnt[d].exists(key) ? cnt[d][key] : 0;
      if (have < need)
        `uvm_error(get_type_name(), $sformatf("DP-R01: DUT %s: %s is %0d, scenario needs %0d",
                                              dname(d), key, have, need))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    for (int d = 0; d < 2; d++) begin
      string s = "";
      foreach (cnt[d][k]) s = {s, $sformatf(" %s=%0d", k, cnt[d][k])};
      `uvm_info(get_type_name(), {"DUT ", dname(d), ":", s}, UVM_LOW)
    end
  endfunction
endclass
