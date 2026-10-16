// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die sends ReadReqs beyond the RREQ credit the DUT advertised
// (inject("no_credit"); plan 9.5). AoU 6.1 forbids it; neither the spec nor
// the MAS says what the receiver does (BUGS/030). Interim expectation:
//   - the testbench's checkers see the violation on the wire (AOU-R16);
//   - the DUT raises no interrupt and no LinkReset (the MAS lists no credit
//     overflow error) and stays ENABLED;
//   - every ReadReq within the credit is answered with correct data
//     (scoreboard); one beyond it is either answered correctly or dropped,
//     never answered wrongly or twice;
//   - after software's LinkReset recovery (MAS 7.3.6), which ends any read
//     still waiting, traffic completes both ways.
// The M port's ARREADY is held low meanwhile and the reads go out without an
// outstanding limit (the test lifts it), so the DUT fills whatever it buffers
// behind its RX credit and stops returning credit; the reads sent while the
// remote die holds no credit are the violations (AOU-R16, one per read).
// Knobs: +extra=<ReadReqs beyond the credit> (default 1..8).
class aou_credit_violation_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_credit_violation_vseq)

  int unsigned wait_max = 20000;
  int unsigned stall = 6000;
  int unsigned buffered = 48;   // reads the DUT may hold beyond its RX buffer

  function new(string name = "aou_credit_violation_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned extra = arg_range("extra", 1, 8);
    int unsigned n = 0;
    int unsigned left;
    aou_core rm = p_sequencer.regs;
    int unsigned sent_without;
    // Two-PHY builds have no AOU_FDI_CHECKER, the only checker of the remote
    // die's own credit use; the remote die's count of sends without credit
    // stands in for it there.
    if (cfg.fdi_chk_en) expect_event("AOU-R16", 1, 0);
    link_up();
    sw_activate();
    check_traffic(num_txns);
    drain();
    // The next AR handshake starts the stall.
    cfg.m_sub_cfg[0].timing.ar_ready.set_fixed(stall);
    run_one(1'b1, 0, mk(1'b1, 0, AOU_AXI_RD, 10'h1, 64'h0000_0050_0001_0000));
    cfg.m_sub_cfg[0].timing.ar_ready.set_range(0, 6);
    begin
      // inject() counts three granules per ReadReq; ask for enough reads to
      // exceed the credit by `extra` whatever a ReadReq takes.
      aou_msg_rreq q = aou_msg_rreq::type_id::create("q");
      int unsigned cred = env.l3.model.crd.tx_cred[0][AOU_CC_RREQ];
      int unsigned want = cred / q.num_granules() + buffered + extra;
      `uvm_info(get_type_name(), $sformatf("RREQ credit %0d granules, %0d per ReadReq: %0d reads",
                                           cred, q.num_granules(), want), UVM_LOW)
      inject("no_credit", int'(want) - int'(cred / 3));
    end
    while (env.rmgr.outstanding() == 0 && n++ < 100) wait_cycles(1);
    n = 0;
    while (env.rmgr.outstanding() != 0 && n++ < wait_max) wait_cycles(1);
    left = env.rmgr.outstanding();
    sent_without = cfg.fdi_chk_en ? env.expects.count("AOU-R16") : env.l3.model.crd.tx_underflows;
    `uvm_info(get_type_name(), $sformatf("%0d ReadReqs unanswered after %0d cycles", left, n),
              UVM_LOW)
    if (left > sent_without)
      `uvm_error(get_type_name(), $sformatf(
          "T1-E13: %0d reads unanswered, only %0d were sent without credit (BUGS/030)", left,
          sent_without))
    check_field(rm.aou_init.activate_state_enabled, 1, "T1-E13", "after the credit violation");
    check_field(rm.lp_linkreset.invalid_actmsg_err, 0, "T1-E13", "after the credit violation");
    check_field(rm.lp_linkreset.msgcredit_err, 0, "T1-E13", "after the credit violation");
    if (left != 0) begin
      env.sw_isr.wait_idle();
      recover();
    end
    check_traffic(num_txns);
    sw_deactivate();
  endtask
endclass
