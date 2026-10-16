// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI request attributes and exclusive responses across the link, and FLEX,
// in every T1 test (cfg.attr_chk_en). WriteReq and ReadReq carry AxLOCK,
// AxCACHE, AxPROT and AxQOS (AoU 5.3; Basic Profile Table 31), responses carry
// EXOKAY, and FLEX is USER[15:0] (5.2), which this DUT does not have.
//
// A request seen at the far side (the remote model for local requests, the M
// port for remote ones) is matched to the requester's transaction by RP,
// direction, ID and address: its start lies inside that transaction's bytes.
// Whichever side completes first waits for the other: normally the far side,
// but a write answered early completes at the S port first. A requester
// transaction that never matches (reset, a response the DUT made up) or a far
// request that never matches is only counted; other checkers own those.
// DP-R05: the remote die decodes the AxLOCK/AxCACHE/AxPROT/AxQOS the S port got.
// DP-R06: the M port presents the AxLOCK/AxCACHE/AxPROT/AxQOS the remote die sent.
// DP-R07: an exclusive transaction's BRESP/RRESP at the requester is the far
//   subordinate's (EXOKAY or OKAY; AXI4 A7.2: only the subordinate's monitor
//   can decide), when the DUT neither split nor merged it.
// DP-R08: FLEX is 0 in every AXI message the DUT sends (no USER ports).
class aou_t1_attr_chk extends uvm_component;
  `uvm_component_utils(aou_t1_attr_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) loc_fifo;   // S-port managers (near, L2R)
  uvm_tlm_analysis_fifo #(aou_axi_txn) far_fifo;   // remote model executions (far, L2R)
  uvm_tlm_analysis_fifo #(aou_axi_txn) rmt_fifo;   // remote managers (near, R2L)
  uvm_tlm_analysis_fifo #(aou_axi_txn) sub_fifo;   // M-port subordinates (far, R2L)
  uvm_tlm_analysis_fifo #(aou_msg)     dut_fifo;   // DUT -> remote die

  aou_t1_xfer_cov cov;

  protected aou_axi_txn far_q[2][string][$];    // [path 0 L2R, 1 R2L][rp/dir/id]
  protected aou_axi_txn near_q[2][string][$];   // completed, nothing matched yet
  int unsigned n_match[2];
  int unsigned n_excl_cmp[2];
  int unsigned n_flex_chk;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    loc_fifo = new("loc_fifo", this);
    far_fifo = new("far_fifo", this);
    rmt_fifo = new("rmt_fifo", this);
    sub_fifo = new("sub_fifo", this);
    dut_fifo = new("dut_fifo", this);
  endfunction

  static function string key(aou_axi_txn t);
    return $sformatf("%0d/%0d/%0h", t.rp, t.dir, t.id);
  endfunction

  static function string path_name(int p);
    return (p == 0) ? "local->remote" : "remote->local";
  endfunction

  static function bit inside_of(aou_axi_txn n, bit [63:0] a);
    bit [63:0] lo = n.addr & ~(64'(n.beat_bytes()) - 64'd1);
    // Offsets, so a burst ending at 2^64 - 1 does not wrap.
    return a >= lo && (a - lo) < 64'(n.beats() * n.beat_bytes());
  endfunction

  // A reset dropped every transaction in flight.
  function void reset_flush();
    flush();
    foreach (far_q[p]) far_q[p].delete();
    foreach (near_q[p]) near_q[p].delete();
  endfunction

  function void take_far(int p, aou_axi_txn f);
    string k = key(f);
    if (f.aborted) return;
    if (near_q[p].exists(k)) begin
      foreach (near_q[p][k][i]) begin
        if (inside_of(near_q[p][k][i], f.addr)) begin
          matched(p, near_q[p][k][i], f, 1'b1);
          near_q[p][k].delete(i);
          return;
        end
      end
    end
    far_q[p][k].push_back(f);
  endfunction

  function void take_near(int p, aou_axi_txn n);
    string k = key(n);
    aou_axi_txn got[$];
    aou_axi_txn rest[$];
    if (n.aborted || n.reset_outstanding) return;
    if (far_q[p].exists(k)) begin
      foreach (far_q[p][k][i]) begin
        if (inside_of(n, far_q[p][k][i].addr)) got.push_back(far_q[p][k][i]);
        else rest.push_back(far_q[p][k][i]);
      end
      far_q[p][k] = rest;
    end
    if (got.size() == 0) begin
      near_q[p][k].push_back(n);
      return;
    end
    foreach (got[i]) matched(p, n, got[i], got.size() == 1);
  endfunction

  function void matched(int p, aou_axi_txn n, aou_axi_txn f, bit one);
    string rule = (p == 0) ? "DP-R05" : "DP-R06";
    n_match[p]++;
    aou_rule_log::check(rule, get_type_name());
    if (f.lock != n.lock || f.cache != n.cache || f.prot != n.prot || f.qos != n.qos) begin
      aou_rule_log::fire(rule, get_type_name());
      `uvm_error(get_type_name(), $sformatf(
                 {"%s: %s: far side got lock=%0b cache=%0h prot=%0h qos=%0h, the requester ",
                  "sent lock=%0b cache=%0h prot=%0h qos=%0h: %s"}, rule, path_name(p), f.lock,
                 f.cache, f.prot, f.qos, n.lock, n.cache, n.prot, n.qos, n.convert2string()))
    end
    if (cov != null) cov.sample_attr(p, f);
    if (one && n.lock) check_excl(p, n, f);
  endfunction

  function void check_excl(int p, aou_axi_txn n, aou_axi_txn f);
    bit bad = 1'b0;
    string what;
    n_excl_cmp[p]++;
    aou_rule_log::check("DP-R07", get_type_name());
    if (n.dir == AOU_AXI_WR) begin
      bad = (n.bresp != f.bresp);
      what = $sformatf("BRESP %0d", n.bresp);
      if (cov != null) cov.sample_excl(p, 0, f.bresp);
    end else begin
      if (n.rresp.size() != f.rresp.size()) return;
      foreach (n.rresp[i]) if (n.rresp[i] != f.rresp[i]) bad = 1'b1;
      what = $sformatf("RRESP %p", n.rresp);
      if (cov != null && f.rresp.size() > 0) cov.sample_excl(p, 1, f.rresp[0]);
    end
    if (bad) begin
      aou_rule_log::fire("DP-R07", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
                 "DP-R07: %s: exclusive %s at the requester, the subordinate answered %s: %s",
                 path_name(p), what, (n.dir == AOU_AXI_WR) ? $sformatf("BRESP %0d", f.bresp) :
                 $sformatf("RRESP %p", f.rresp), n.convert2string()))
    end
  endfunction

  function void take_dut(aou_msg m);
    if (!(m.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ, AOU_MT_WDATA, AOU_MT_RDATA, AOU_MT_WRESP,
                             AOU_MT_WDATAF}))
      return;
    n_flex_chk++;
    aou_rule_log::check("DP-R08", get_type_name());
    if (m.flex != 16'h0) begin
      aou_rule_log::fire("DP-R08", get_type_name());
      `uvm_error(get_type_name(), $sformatf("DP-R08: DUT %s on RP%0d carries FLEX %04h, expected 0",
                                            aou_msg_type_e'(m.msg_type), m.rp, m.flex))
    end
  endfunction

  function void flush();
    aou_axi_txn t;
    aou_msg m;
    while (far_fifo.try_get(t)) take_far(0, t);
    while (sub_fifo.try_get(t)) take_far(1, t);
    while (loc_fifo.try_get(t)) take_near(0, t);
    while (rmt_fifo.try_get(t)) take_near(1, t);
    while (dut_fifo.try_get(m)) take_dut(m);
  endfunction

  // Far pieces are taken before each requester completion, so a piece that
  // arrived first is always queued when its requester looks for it.
  task run_phase(uvm_phase phase);
    aou_msg m;
    aou_axi_txn t;
    aou_axi_txn u;
    aou_axi_txn v;
    aou_axi_txn w;
    fork
      forever begin dut_fifo.get(m); take_dut(m); end
      forever begin far_fifo.get(u); take_far(0, u); end
      forever begin sub_fifo.get(w); take_far(1, w); end
      forever begin
        loc_fifo.get(t);
        while (far_fifo.try_get(u)) take_far(0, u);
        take_near(0, t);
      end
      forever begin
        rmt_fifo.get(v);
        while (sub_fifo.try_get(w)) take_far(1, w);
        take_near(1, v);
      end
    join
  endtask

  function void check_phase(uvm_phase phase);
    flush();
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned left[2][2];
    foreach (far_q[p]) foreach (far_q[p][k]) left[p][0] += far_q[p][k].size();
    foreach (near_q[p]) foreach (near_q[p][k]) left[p][1] += near_q[p][k].size();
    `uvm_info(get_type_name(), $sformatf(
              {"matched L2R/R2L %0d/%0d, exclusive responses compared %0d/%0d, unmatched far ",
               "%0d/%0d requester %0d/%0d; DUT AXI messages with FLEX checked %0d"}, n_match[0],
              n_match[1], n_excl_cmp[0], n_excl_cmp[1], left[0][0], left[1][0], left[0][1],
              left[1][1], n_flex_chk), UVM_LOW)
  endfunction
endclass
