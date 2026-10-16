// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI ID mismatch on both sides, on every RP (plan 9.9-9.12, 19.7, 19.8;
// MAS software-operation 7.2.2, interrupts-errors 4).
//
// mgr: with nothing outstanding, the local subordinate on RP r's M port
// returns a B, then a one-beat R, whose ID matches no request. The DUT must
// take it (interim, BUGS/029: accept and drop it), set ERROR_INFO_RPr
// SPLIT_BID/RID_MISMATCH_ERR with the ID in the INFO field and raise
// INT_MI0_ID_MISMATCH.
// sub: the remote die sends a WriteResp, then a ReadData, for no request of
// RP r. With the subordinate checker enabled (AXI_SLV_ID_MISMATCH_ERR_RPr bit
// 22, which the RDL calls reserved: BUGS/003 interim) the DUT must keep it off
// the S port, set AXI_SLV_BID/RID_MISMATCH_ERR with the ID and raise
// INT_SI0_ID_MISMATCH. With it disabled (+slv_en=0) nothing is recorded (MAS
// 7.2.2) and the response must still stay off the S port.
// With +mask=1 the interrupt mask is set first: the status bit is still set
// but the interrupt stays low until the mask is cleared (interim, BUGS/029:
// interrupt = status & ~mask). Write 1 clears the error, its INFO and the
// interrupt. Traffic must complete afterwards.
// The orphan stays on the M port until taken (AXI4 forbids withdrawing it);
// when the DUT does not take it, or lets an unrequested response through to
// the S port, the test reports that and pulses I_RESETN/I_PRESETN, the only
// legal way to end it, before going on.
// +detect_only=1 (M port only) is a bug-avoiding variant for BUGS/029: after
// the orphan it checks the status, INFO, interrupt and mask, then ends the
// scenario with a hard reset instead of the write-1 clear and more traffic.
// It does not check that the DUT takes the orphan within accept_wait cycles,
// which is the 029 interim expectation itself, so it is weaker than the
// default run and never replaces it (coverage-closure decision D8).
// Knobs: +side=all|mgr|sub +kind=all|b|r +mask=0|1 +slv_en=0|1 +detect_only=0|1.
class aou_id_mismatch_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_id_mismatch_vseq)

  bit masked;
  bit slv_en;
  bit detect_only;
  string side;
  bit ok_last;      // the last check_and_clear() saw what it expected
  int unsigned accept_wait = 500;

  function new(string name = "aou_id_mismatch_vseq");
    super.new(name);
  endfunction

  task body();
    string kind = arg_str("kind", "all");
    side = arg_str("side", "all");
    masked = arg_int("mask", 0) != 0;
    slv_en = arg_int("slv_en", 1) != 0;
    detect_only = arg_int("detect_only", 0) != 0;
    if (side inside {"all", "mgr"}) begin
      expect_event("INT_MI0_ID_MISMATCH", 1, 0);
      // Only once the DUT takes the orphan.
      expect_event("AXI-R07", 0, cfg.n_rp);
      expect_event("AXI-R08", 0, cfg.n_rp);
    end
    if (side inside {"all", "sub"} && slv_en) expect_event("INT_SI0_ID_MISMATCH", 1, 0);
    link_up();
    sw_activate();
    check_traffic(num_txns);
    setup_regs(side);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      for (int k = 0; k < 2; k++) begin
        bit rd = k[0];
        if (kind != "all" && kind != (rd ? "r" : "b")) continue;
        if (side inside {"all", "mgr"}) mgr_one(r, rd);
        if (side inside {"all", "sub"}) begin
          sub_one(r, rd);
          if (!ok_last) contain(side);
        end
      end
      check_traffic(num_txns);
    end
    sw_deactivate();
  endtask

  task setup_regs(string which);
    if (masked) begin
      wr(p_sequencer.regs.aou_interrupt_mask.int_mi0_id_mismatch_mask, 1);
      wr(p_sequencer.regs.aou_interrupt_mask.int_si0_id_mismatch_mask, 1);
    end
    if (which inside {"all", "sub"} && slv_en)
      for (int unsigned r = 0; r < cfg.n_rp; r++)
        raw_write(p_sequencer.regs.get_reg_by_name($sformatf("axi_slv_id_mismatch_err_rp%0d", r)),
                  32'h0040_0000);
  endtask

  // Ends a scenario the DUT did not handle with a core and APB reset, then
  // brings the link back and programs the registers again.
  task contain(string which);
    `uvm_info(get_type_name(), "containing: I_RESETN and I_PRESETN, then re-activation", UVM_LOW)
    hard_reset(AOU_T1_RST_BOTH);
    setup_regs(which);
  endtask

  // Status, INFO and interrupt after one mismatch, then the mask (if set) and
  // the write-1 clear.
  task check_and_clear(string what, uvm_reg_field err, uvm_reg_field other, uvm_reg_field info,
                       uvm_reg_field mask, string irq, bit [9:0] id, bit expect_set);
    uvm_reg_data_t v;
    rd(err, v);
    ok_last = v == uvm_reg_data_t'(expect_set);
    check_field(err, uvm_reg_data_t'(expect_set), "T1-E04", what);
    check_field(other, 0, "T1-E04", {what, ": only one kind provoked"});
    check_field(info, expect_set ? uvm_reg_data_t'(id) : 0, "T1-E04", {what, ": captured ID"});
    check_pin(irq, expect_set && !masked, "T1-E06", what);
    if (!expect_set) return;
    if (masked) begin
      wr(mask, 0);
      check_pin(irq, 1'b1, "T1-E07", {what, ": mask cleared with the error pending (BUGS/029)"});
      wr(mask, 1);
      check_pin(irq, 1'b0, "T1-E06", {what, ": masked again"});
    end
    wr(err, 1);
    check_field(err, 0, "REG-R04", {what, ": after write-1-to-clear"});
    check_field(info, 0, "T1-E04", {what, ": INFO clears with the error"});
    check_pin(irq, 1'b0, "T1-E06", {what, ": after write-1-to-clear"});
  endtask

  task mgr_one(int unsigned rp, bit rd);
    aou_axi_sub_driver drv = env.m_sub[rp].drv;
    bit [9:0] id = 10'($urandom_range(10'h3FF));
    int unsigned taken = drv.n_orphan_taken;
    int unsigned n = 0;
    string what = $sformatf("RP%0d M-port %s with ID %0h", rp, rd ? "R" : "B", id);
    drain();
    `uvm_info(get_type_name(), {"orphan ", what}, UVM_LOW)
    drv.orphan_hold = 32'hFFFF_FFFF;
    drv.inject_orphan(rd, id, AOU_AXI_OKAY);
    if (detect_only) begin
      detect_then_reset(what, rp, rd, id);
      return;
    end
    while (drv.n_orphan_taken == taken && n++ < accept_wait) wait_cycles(1);
    if (drv.n_orphan_taken == taken)
      `uvm_error(get_type_name(), $sformatf("T1-E05: %s not accepted in %0d cycles (BUGS/029)",
                                            what, accept_wait))
    check_and_clear(what,
                    rpf("error_info", rp, rd ? "split_rid_mismatch_err" : "split_bid_mismatch_err"),
                    rpf("error_info", rp, rd ? "split_bid_mismatch_err" : "split_rid_mismatch_err"),
                    rpf("error_info", rp,
                        rd ? "split_rid_mismatch_info" : "split_bid_mismatch_info"),
                    p_sequencer.regs.aou_interrupt_mask.int_mi0_id_mismatch_mask,
                    "INT_MI0_ID_MISMATCH", id, 1'b1);
    if (drv.n_orphan_taken == taken) contain(side);
  endtask

  // +detect_only: status, INFO, interrupt and mask after the orphan, no
  // acceptance deadline and no write-1 clear, then a hard reset.
  task detect_then_reset(string what, int unsigned rp, bit rd, bit [9:0] id);
    uvm_reg_field err = rpf("error_info", rp,
                            rd ? "split_rid_mismatch_err" : "split_bid_mismatch_err");
    uvm_reg_field mask = p_sequencer.regs.aou_interrupt_mask.int_mi0_id_mismatch_mask;
    wait_cycles(accept_wait);
    check_field(err, 1, "T1-E04", what);
    check_field(rpf("error_info", rp, rd ? "split_bid_mismatch_err" : "split_rid_mismatch_err"),
                0, "T1-E04", {what, ": only one kind provoked"});
    check_field(rpf("error_info", rp, rd ? "split_rid_mismatch_info" : "split_bid_mismatch_info"),
                uvm_reg_data_t'(id), "T1-E04", {what, ": captured ID"});
    check_pin("INT_MI0_ID_MISMATCH", !masked, "T1-E06", what);
    if (masked) begin
      wr(mask, 0);
      check_pin("INT_MI0_ID_MISMATCH", 1'b1, "T1-E07",
                {what, ": mask cleared with the error pending"});
      wr(mask, 1);
      check_pin("INT_MI0_ID_MISMATCH", 1'b0, "T1-E06", {what, ": masked again"});
    end
    contain(side);
  endtask

  task sub_one(int unsigned rp, bit is_rd);
    bit [9:0] id = 10'($urandom_range(10'h3FF));
    string what = $sformatf("RP%0d remote %s with ID %0h", rp,
                            is_rd ? "ReadData" : "WriteResp", id);
    drain();
    `uvm_info(get_type_name(), {"unrequested ", what}, UVM_LOW)
    if (is_rd) begin
      aou_msg_rdata m = aou_msg_rdata::type_id::create("bogus_r");
      m.rp = env.l3.cfg.dest_rp[rp];
      m.id = id;
      m.resp = AOU_AXI_OKAY;
      m.last = 1'b1;
      m.dlength = aou_t1_remote_mgr_driver::dl_of(cfg.remote_bytes);
      env.l3.send(m);
    end else begin
      aou_msg_wresp m = aou_msg_wresp::type_id::create("bogus_b");
      m.rp = env.l3.cfg.dest_rp[rp];
      m.id = id;
      m.resp = AOU_AXI_OKAY;
      env.l3.send(m);
    end
    env.l3.model.kick();
    wait_cycles(300);
    check_and_clear(what,
        rpf("axi_slv_id_mismatch_err", rp,
            is_rd ? "axi_slv_rid_mismatch_err" : "axi_slv_bid_mismatch_err"),
        rpf("axi_slv_id_mismatch_err", rp,
            is_rd ? "axi_slv_bid_mismatch_err" : "axi_slv_rid_mismatch_err"),
        rpf("axi_slv_id_mismatch_err", rp,
            is_rd ? "axi_slv_rid_mismatch_info" : "axi_slv_bid_mismatch_info"),
        p_sequencer.regs.aou_interrupt_mask.int_si0_id_mismatch_mask,
        "INT_SI0_ID_MISMATCH", id, slv_en);
    // Nothing is outstanding, so the S side reports complete (MAS 7.1); a
    // DUT that counts the unrequested response would never deactivate.
    drain();
    begin
      uvm_reg_data_t v;
      this.rd(p_sequencer.regs.aou_init.slv_tr_complete, v);
      if (v != 1) begin
        ok_last = 1'b0;
        `uvm_error(get_type_name(), $sformatf(
            "T1-E15: SLV_TR_COMPLETE is 0 with nothing outstanding after the %s (BUGS/029)", what))
      end
    end
  endtask
endclass
