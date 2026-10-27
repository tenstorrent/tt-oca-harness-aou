// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Directed check of the scoreboard's reset rule, with no bus: transactions are
// fed to the scoreboard directly. A reset_outstanding write is lost or landed
// whatever its response, and the bytes it addresses may then hold their old
// value or the write's, until a checked write; a reset_outstanding read may
// end with SLVERR beats (MAS 7.3.6 defines no response for it); anything else is still an error.
// Each step expects an exact set of errors.
class aou_axi_sb_reset_test extends uvm_test;
  `uvm_component_utils(aou_axi_sb_reset_test)

  localparam bit [63:0] BASE = 64'h0000_0002_0000_0000;

  aou_scoreboard           sb;
  aou_mem                  rmem;
  aou_mem                  lmem;
  aou_axi_selftest_catcher catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rmem = aou_mem::type_id::create("rmem");
    lmem = aou_mem::type_id::create("lmem");
    sb = aou_scoreboard::type_id::create("sb", this);
    sb.remote_mem = rmem;
    sb.local_mem = lmem;
    catcher = aou_axi_selftest_catcher::type_id::create("catcher");
    uvm_report_cb::add(null, catcher);
  endfunction

  // One 64-byte beat per line, full strobes for writes.
  protected function aou_axi_txn mk(aou_axi_dir_e dir, bit [63:0] addr, int unsigned beats = 1);
    aou_axi_txn t = aou_axi_txn::type_id::create("t");
    t.dir = dir;
    t.addr = addr;
    t.len = 8'(beats - 1);
    t.size = 3'd6;
    t.burst = AOU_AXI_INCR;
    if (dir == AOU_AXI_WR) begin
      t.fill_wdata(AOU_AXI_STRB_FULL);
    end else begin
      t.data = new[beats];
      t.rresp = new[beats];
      foreach (t.data[i])
        for (int unsigned l = 0; l < 64; l++)
          t.data[i][8*l +: 8] = rmem.read_byte(t.beat_base(i) + 64'(l));
    end
    return t;
  endfunction

  protected function void expect_rules(string step, int unsigned s01, int unsigned s02,
                                       int unsigned s03, int unsigned s04, int unsigned s05);
    int unsigned want[string];
    want["AXI-S01"] = s01;
    want["AXI-S02"] = s02;
    want["AXI-S03"] = s03;
    want["AXI-S04"] = s04;
    want["AXI-S05"] = s05;
    foreach (want[r]) begin
      int unsigned got = catcher.by_rule.exists(r) ? catcher.by_rule[r] : 0;
      if (got != want[r])
        `uvm_error(get_type_name(), $sformatf("%s: %0d %s errors, expected %0d", step, got, r,
                                              want[r]))
    end
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_txn w;
    aou_axi_txn r;
    bit [7:0] old_b;
    bit [7:0] new_b;
    bit [7:0] third;
    phase.raise_objection(this);

    // Outstanding at the request, ended with SLVERR: aborted, bytes unknown.
    w = mk(AOU_AXI_WR, BASE);
    w.reset_outstanding = 1'b1;
    w.bresp = AOU_AXI_SLVERR;
    sb.write_local_mgr(w);
    old_b = rmem.read_byte(BASE);
    new_b = w.data[0][7:0];
    third = 8'(old_b + 1) == new_b ? 8'(old_b + 2) : 8'(old_b + 1);
    // A later read may see the old value, or the new one.
    sb.write_local_mgr(mk(AOU_AXI_RD, BASE));
    rmem.write_byte(BASE, new_b);
    sb.write_local_mgr(mk(AOU_AXI_RD, BASE));
    expect_rules("SLVERR write outstanding at the request", 0, 0, 0, 0, 0);
    // Neither value: an error.
    rmem.write_byte(BASE, third);
    sb.write_local_mgr(mk(AOU_AXI_RD, BASE));
    expect_rules("third value in an unknown byte", 0, 0, 0, 1, 0);
    // A checked write defines the bytes again.
    w = mk(AOU_AXI_WR, BASE);
    w.bresp = AOU_AXI_OKAY;
    rmem.write_txn(w);
    sb.write_local_mgr(w);
    rmem.write_byte(BASE, w.data[0][7:0] + 8'd1);
    sb.write_local_mgr(mk(AOU_AXI_RD, BASE));
    rmem.write_byte(BASE, w.data[0][7:0]);
    expect_rules("rewritten byte is checked again", 0, 0, 0, 2, 0);

    // SLVERR on a transaction issued after the reset stays an error.
    w = mk(AOU_AXI_WR, BASE + 64'h100);
    w.bresp = AOU_AXI_SLVERR;
    rmem.write_txn(w);
    sb.write_local_mgr(w);
    expect_rules("SLVERR write after the reset", 1, 0, 0, 2, 0);

    // A read outstanding at the request: OKAY beats are checked, SLVERR beats
    // are not; issued later, SLVERR is an error.
    r = mk(AOU_AXI_RD, BASE + 64'h200, 2);
    r.reset_outstanding = 1'b1;
    r.rresp[1] = AOU_AXI_SLVERR;
    sb.write_local_mgr(r);
    expect_rules("SLVERR read outstanding at the request", 1, 0, 0, 2, 0);
    r = mk(AOU_AXI_RD, BASE + 64'h200, 2);
    r.reset_outstanding = 1'b1;
    r.rresp[1] = AOU_AXI_SLVERR;
    r.data[0][7:0] = r.data[0][7:0] + 8'd1;
    sb.write_local_mgr(r);
    expect_rules("bad OKAY beat of an outstanding read", 1, 0, 0, 3, 0);
    r = mk(AOU_AXI_RD, BASE + 64'h200, 2);
    r.rresp[1] = AOU_AXI_SLVERR;
    sb.write_local_mgr(r);
    expect_rules("SLVERR read after the reset", 1, 0, 1, 3, 0);
    // DECERR is not what a reset may return.
    r = mk(AOU_AXI_RD, BASE + 64'h200);
    r.reset_outstanding = 1'b1;
    r.rresp[0] = AOU_AXI_DECERR;
    sb.write_local_mgr(r);
    expect_rules("DECERR read outstanding at the request", 1, 0, 2, 3, 0);

    // Outstanding at the request and ended OKAY (an early response, 7.2.5):
    // lost or landed, so the memory may hold either value.
    w = mk(AOU_AXI_WR, BASE + 64'h300);
    w.reset_outstanding = 1'b1;
    w.bresp = AOU_AXI_OKAY;
    rmem.write_txn(w);
    sb.write_local_mgr(w);
    sb.write_local_mgr(mk(AOU_AXI_RD, BASE + 64'h300));
    w = mk(AOU_AXI_WR, BASE + 64'h340);
    w.reset_outstanding = 1'b1;
    w.bresp = AOU_AXI_OKAY;
    sb.write_local_mgr(w);
    sb.write_local_mgr(mk(AOU_AXI_RD, BASE + 64'h340));
    rmem.write_txn(w);
    expect_rules("OKAY write outstanding at the request", 1, 0, 2, 3, 0);

    // End of test: one unknown byte holds a third value (AXI-S05 per byte and
    // a summary); its neighbour holds the new value.
    w = mk(AOU_AXI_WR, BASE + 64'h400);
    w.reset_outstanding = 1'b1;
    w.bresp = AOU_AXI_SLVERR;
    sb.write_local_mgr(w);
    rmem.write_byte(BASE + 64'h401, w.data[0][15:8]);
    old_b = rmem.read_byte(BASE + 64'h400);
    third = 8'(old_b + 1) == w.data[0][7:0] ? 8'(old_b + 2) : 8'(old_b + 1);
    rmem.write_byte(BASE + 64'h400, third);

    // A remote-die write the env aborted (reset_flush): the local memory may
    // keep the old value or take the new one.
    w = mk(AOU_AXI_WR, BASE + 64'h500);
    w.local_side = 1'b0;
    sb.abort(w);
    lmem.write_byte(BASE + 64'h500, w.data[0][7:0]);
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    expect_rules("end of test", 1, 0, 2, 3, 2);
    if (sb.n_reset_err != 6 || sb.n_aborted != 1)
      `uvm_error(get_type_name(), $sformatf(
          "%0d on the bus at AOU_SW_RESET, %0d aborted; expected 6, 1", sb.n_reset_err,
          sb.n_aborted))
  endfunction
endclass
