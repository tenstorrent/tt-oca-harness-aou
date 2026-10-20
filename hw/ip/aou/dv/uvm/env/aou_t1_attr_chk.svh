// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI request attributes and exclusive responses across the link, and FLEX,
// in every T1 test (cfg.attr_chk_en). WriteReq and ReadReq carry AxLOCK,
// AxCACHE, AxPROT and AxQOS (AoU 5.3; Basic Profile Table 31), responses carry
// EXOKAY, and FLEX is USER[15:0] (5.2), which this DUT does not have.
//
// A request seen at the far side (the remote model for local requests, the M
// port for remote ones) is matched to the requester's transaction by RP,
// direction, ID and address: its start lies inside that transaction's bytes,
// and same-ID pieces are taken in far-side order until they cover it.
// RPs are compared as the DUT's local RPs: a request on the wire carries the
// receiver's RP, so the remote model's view (its plane, the wire RP of DUT
// requests) maps back through the remote die's DEST_RP map
// (l3_cfg.dest_rp, the inverse of the DUT's).
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
// DP-R09: the size of each WriteReq the DUT sends is at least the AWSIZE of
//   the S-port write it came from (a writer may raise the size, never lower it),
//   matched by RP, ID and address as above.
class aou_t1_attr_chk extends uvm_component;
  `uvm_component_utils(aou_t1_attr_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) loc_fifo;   // S-port managers (near, L2R)
  uvm_tlm_analysis_fifo #(aou_axi_txn) far_fifo;   // remote model executions (far, L2R)
  uvm_tlm_analysis_fifo #(aou_axi_txn) rmt_fifo;   // remote managers (near, R2L)
  uvm_tlm_analysis_fifo #(aou_axi_txn) sub_fifo;   // M-port subordinates (far, R2L)
  uvm_tlm_analysis_fifo #(aou_msg)     dut_fifo;   // DUT -> remote die

  aou_t1_xfer_cov cov;
  aou_l3_cfg      l3_cfg;   // dest_rp: the remote die's plane -> the DUT's RP

  protected aou_axi_txn far_q[2][string][$];    // [path 0 L2R, 1 R2L][rp/dir/id]
  protected aou_axi_txn near_q[2][string][$];   // completed, nothing matched yet
  int unsigned n_match[2];
  int unsigned n_excl_cmp[2];
  int unsigned n_flex_chk;
  int unsigned n_wsize_chk;

  protected aou_msg_wreq wreq_q[string][$];   // DUT WriteReqs not yet matched
  protected aou_axi_txn  aw_q[string][$];     // S-port writes not yet matched

  function new(string name, uvm_component parent);
    super.new(name, parent);
    loc_fifo = new("loc_fifo", this);
    far_fifo = new("far_fifo", this);
    rmt_fifo = new("rmt_fifo", this);
    sub_fifo = new("sub_fifo", this);
    dut_fifo = new("dut_fifo", this);
  endfunction

  // The DUT's local RP for remote plane / wire RP x.
  function int local_rp(int x);
    if (l3_cfg == null || x < 0 || x > 3) return x;
    return int'(l3_cfg.dest_rp[x]);
  endfunction

  // t's key; remote-side txns (L2R far: wire RP; R2L near: remote plane) map
  // back to the DUT's RP.
  function string key(aou_axi_txn t, bit remote_side);
    return $sformatf("%0d/%0d/%0h", remote_side ? local_rp(t.rp) : t.rp, t.dir, t.id);
  endfunction

  static function string path_name(int p);
    return (p == 0) ? "local->remote" : "remote->local";
  endfunction

  // With wide set, the window starts at n's 128-byte container: a remote die
  // may send a narrow write as a WriteReq of its bus size (up to 128 bytes),
  // which starts there, and the M-port bursts the DUT makes of it may too.
  static function bit inside_of(aou_axi_txn n, bit [63:0] a, bit wide = 1'b0);
    bit [63:0] base = n.addr & ~(64'(n.beat_bytes()) - 64'd1);
    bit [63:0] lo = wide ? (n.addr & ~64'd127) : base;
    // Offsets, so a burst ending at 2^64 - 1 does not wrap.
    return a >= lo && (a - lo) < (base - lo) + 64'(n.beats() * n.beat_bytes());
  endfunction

  // A reset dropped every transaction in flight.
  function void reset_flush();
    flush();
    foreach (far_q[p]) far_q[p].delete();
    foreach (near_q[p]) near_q[p].delete();
    wreq_q.delete();
    aw_q.delete();
  endfunction

  static function string wkey(int rp, bit [9:0] id);
    return $sformatf("%0d/%0h", rp, id);
  endfunction

  function void cmp_wsize(aou_axi_txn n, aou_msg_wreq w);
    n_wsize_chk++;
    aou_rule_log::check("DP-R09", get_type_name());
    if (w.size < n.size) begin
      aou_rule_log::fire("DP-R09", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
                 "DP-R09: DUT WriteReq of size %0d for an S-port write of AWSIZE %0d: %s", w.size,
                 n.size, n.convert2string()))
    end
  endfunction

  // An S-port write against the DUT WriteReqs of its RP and ID.
  function void take_aw(aou_axi_txn n);
    string k = wkey(n.rp, n.id);
    aou_msg_wreq rest[$];
    bit hit = 1'b0;
    if (wreq_q.exists(k)) begin
      foreach (wreq_q[k][i]) begin
        if (inside_of(n, wreq_q[k][i].addr)) begin
          cmp_wsize(n, wreq_q[k][i]);
          hit = 1'b1;
        end else rest.push_back(wreq_q[k][i]);
      end
      wreq_q[k] = rest;
    end
    if (!hit) aw_q[k].push_back(n);
  endfunction

  function void take_wreq(aou_msg_wreq w);
    string k = wkey(local_rp(int'(w.rp)), w.id);
    if (aw_q.exists(k)) begin
      foreach (aw_q[k][i]) begin
        if (inside_of(aw_q[k][i], w.addr)) begin
          cmp_wsize(aw_q[k][i], w);
          aw_q[k].delete(i);
          return;
        end
      end
    end
    wreq_q[k].push_back(w);
  endfunction

  function void take_far(int p, aou_axi_txn f);
    string k = key(f, p == 0);
    if (f.aborted) return;
    if (near_q[p].exists(k)) begin
      foreach (near_q[p][k][i]) begin
        if (inside_of(near_q[p][k][i], f.addr, p == 1)) begin
          matched(p, near_q[p][k][i], f, 1'b1);
          near_q[p][k].delete(i);
          return;
        end
      end
    end
    far_q[p][k].push_back(f);
  endfunction

  // Bytes from the start address to the end of the last beat; split or resized
  // pieces of one transaction add up to it.
  static function longint unsigned span(aou_axi_txn t);
    return longint'(t.beats()) * t.beat_bytes() -
           longint'(t.addr & (64'(t.beat_bytes()) - 64'd1));
  endfunction

  // A later same-ID request can start inside an earlier one's bytes and reach
  // the far side before the earlier response gets back, so pieces (queued in
  // far-side order) are taken oldest first only until they cover n.
  function void take_near(int p, aou_axi_txn n);
    string k = key(n, p == 1);
    aou_axi_txn got[$];
    aou_axi_txn rest[$];
    longint unsigned have = 0;
    if (n.aborted || n.reset_outstanding) return;
    if (p == 0 && n.dir == AOU_AXI_WR) take_aw(n);
    if (far_q[p].exists(k)) begin
      foreach (far_q[p][k][i]) begin
        if (have < span(n) && inside_of(n, far_q[p][k][i].addr, p == 1)) begin
          got.push_back(far_q[p][k][i]);
          have += span(far_q[p][k][i]);
        end else rest.push_back(far_q[p][k][i]);
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
    aou_msg_wreq w;
    if (m.msg_type == AOU_MT_WREQ && $cast(w, m)) take_wreq(w);
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
    int unsigned w_left[2];
    foreach (far_q[p]) foreach (far_q[p][k]) left[p][0] += far_q[p][k].size();
    foreach (near_q[p]) foreach (near_q[p][k]) left[p][1] += near_q[p][k].size();
    foreach (wreq_q[k]) w_left[0] += wreq_q[k].size();
    foreach (aw_q[k]) w_left[1] += aw_q[k].size();
    `uvm_info(get_type_name(), $sformatf(
              {"matched L2R/R2L %0d/%0d, exclusive responses compared %0d/%0d, unmatched far ",
               "%0d/%0d requester %0d/%0d; DUT AXI messages with FLEX checked %0d; WriteReq ",
               "sizes checked %0d, unmatched WriteReq %0d S-port write %0d"}, n_match[0],
              n_match[1], n_excl_cmp[0], n_excl_cmp[1], left[0][0], left[1][0], left[0][1],
              left[1][1], n_flex_chk, n_wsize_chk, w_left[0], w_left[1]), UVM_LOW)
  endfunction
endclass
