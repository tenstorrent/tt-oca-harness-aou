// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI ID mismatch on both sides, on every RP (plan 9.9-9.12, 19.7, 19.8;
// MAS software-operation 7.2.2, interrupts-errors 4).
//
// The stimulus is illegal on purpose: AXI4 forbids a response with nothing
// outstanding, and the AoU spec defines no reaction to one from the remote
// die. Only what MAS 7.2.2 defines is checked: detection and reporting
// (status, captured ID, interrupt, mask, write-1 clear). How the DUT handles
// the stray response itself (taking or holding it, counting it) is undefined
// and not checked; a scenario it leaves unrecoverable ends with a hard reset.
// mgr: with nothing outstanding, the local subordinate on RP r's M port
// returns a B, then a one-beat R, whose ID matches no request. The DUT must
// set ERROR_INFO_RPr SPLIT_BID/RID_MISMATCH_ERR with the ID in the INFO field
// and raise INT_MI0_ID_MISMATCH. While the error is set the DUT blocks TX
// credited traffic (owners' containment, 937a8a8/#26); software clears it with
// write 1, which releases the block. The orphan stays on the M port until
// taken (AXI4 forbids withdrawing it): when the DUT takes it, the error is
// cleared and traffic goes on; when it doesn't, the error would re-set after
// every clear, so the status is checked without the clear and the scenario
// ends with I_RESETN/I_PRESETN, the only legal way to end it.
// sub: the remote die sends a WriteResp, then a ReadData, for no request of
// RP r. AXI_SLV_ID_MISMATCH_EN is set while the activation FSM is still
// DISABLED (MAS 7.2.2). With the checker enabled the DUT keeps the stray
// response off the S port, sets AXI_SLV_BID/RID_MISMATCH_ERR with the ID and
// raises INT_SI0_ID_MISMATCH. With the checker disabled nothing is detected:
// the stray response goes out on the S port, where the bench's manager
// rejects it as a response with nothing outstanding, and SLV_TR_COMPLETE
// stays low afterwards. The owners have not defined that handling, so there
// is no +slv_en=0 scenario in the lists.
// With +mask=1 the interrupt mask is set first: the status bit is still set
// but the interrupt stays low until the mask is cleared (interrupt = status &
// ~mask: the mask only suppresses the interrupt signal, MAS 7.2.2). Write 1
// clears the error, its INFO and the interrupt.
// +detect_only=1 (M port only): after the orphan it checks the status, INFO,
// interrupt and mask, then always ends the scenario with a hard reset instead
// of the write-1 clear and more traffic.
// Before the write-1 clear (or the reset) that ends an M-port mismatch, traffic
// is started and left +blk_hold cycles (default 1000) with the error still set,
// so aou_t1_crd_block_chk (T1-E20) sees credited messages waiting on the block;
// they complete after the clear, or end with the reset. Before a clear the
// orphan has been taken and traffic runs both ways; before a reset the orphan
// may still be presented, so only the local managers issue. +blk_txns (default 8 per RP and direction,
// 0: none) sets the amount.
// Knobs: +side=all|mgr|sub +kind=all|b|r +mask=0|1 +slv_en=0|1 +detect_only=0|1
// +blk_hold=<cycles> +blk_txns=<n>.
class aou_id_mismatch_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_id_mismatch_vseq)

  bit masked;
  bit slv_en;
  bit detect_only;
  string side;
  bit ok_last;      // the last check_and_clear() saw what it expected
  int unsigned accept_wait = 500;
  // Traffic left waiting on the M-port mismatch block before its clear.
  protected bit load_before_clear;

  function new(string name = "aou_id_mismatch_vseq");
    super.new(name);
  endfunction

  task body();
    string kind = arg_str("kind", "all");
    side = arg_str("side", "all");
    masked = arg_int("mask", 0) != 0;
    slv_en = arg_int("slv_en", 1) != 0;
    detect_only = arg_int("detect_only", 0) != 0;
    // This test checks and clears the status itself.
    env.sw_isr.service_id_mismatch = 1'b0;
    if (side inside {"all", "mgr"}) begin
      expect_event("INT_MI0_ID_MISMATCH", 1, 0);
      // Only once the DUT takes the orphan.
      expect_event("AXI-R07", 0, cfg.n_rp);
      expect_event("AXI-R08", 0, cfg.n_rp);
    end
    if (side inside {"all", "sub"} && slv_en) expect_event("INT_SI0_ID_MISMATCH", 1, 0);
    link_up();
    // MAS 7.2.2: program the checker while DISABLED, before any AXI traffic.
    if (side inside {"all", "sub"} && slv_en) enable_slv_id_check();
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
  endtask

  // Ends a scenario the DUT did not handle with a core and APB reset, then
  // brings the link back. The checker enable is written while DISABLED,
  // before activation (MAS 7.2.2).
  task contain(string which);
    `uvm_info(get_type_name(), "containing: I_RESETN and I_PRESETN, then re-activation", UVM_LOW)
    hard_reset(AOU_T1_RST_BOTH, 1'b0);
    link_up();
    if (which inside {"all", "sub"} && slv_en) enable_slv_id_check();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
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
      check_pin(irq, 1'b1, "T1-E07", {what, ": mask cleared with the error pending"});
      wr(mask, 1);
      check_pin(irq, 1'b0, "T1-E06", {what, ": masked again"});
    end
    if (load_before_clear) load_blocked(AOU_T1_BOTH_DIRS);
    wr(err, 1);
    if (load_before_clear) wait_traffic();
    check_field(err, 0, "REG-R04", {what, ": after write-1-to-clear"});
    check_field(info, 0, "T1-E04", {what, ": INFO clears with the error"});
    check_pin(irq, 1'b0, "T1-E06", {what, ": after write-1-to-clear"});
  endtask

  // Traffic left waiting +blk_hold cycles on the M-port mismatch block; the
  // caller ends the block (write-1 clear or reset) and waits for it. While the
  // orphan may still be on an M port only the local managers issue, so no M
  // port has a real response in flight if the DUT takes the orphan late.
  task load_blocked(aou_t1_dir_e dir);
    int unsigned n = arg_int("blk_txns", 8);
    if (n == 0) return;
    traffic_nb(dir, n, aou_t1_traffic_cfg::named("short"));
    wait_cycles(arg_int("blk_hold", 1000));
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
    // Taking the orphan is not required (undefined handling of an illegal
    // response); without it the status re-sets after every clear.
    if (drv.n_orphan_taken == taken) begin
      `uvm_info(get_type_name(), $sformatf(
                "%s still presented after %0d cycles; checking detection only", what,
                accept_wait), UVM_LOW)
      detect_then_reset(what, rp, rd, id);
      return;
    end
    load_before_clear = 1'b1;
    check_and_clear(what,
                    rpf("error_info", rp, rd ? "split_rid_mismatch_err" : "split_bid_mismatch_err"),
                    rpf("error_info", rp, rd ? "split_bid_mismatch_err" : "split_rid_mismatch_err"),
                    rpf("error_info", rp,
                        rd ? "split_rid_mismatch_info" : "split_bid_mismatch_info"),
                    p_sequencer.regs.aou_interrupt_mask.int_mi0_id_mismatch_mask,
                    "INT_MI0_ID_MISMATCH", id, 1'b1);
    load_before_clear = 1'b0;
  endtask

  // Status, INFO, interrupt and mask after the orphan, no write-1 clear, then
  // a hard reset (+detect_only, or an orphan the DUT did not take).
  task detect_then_reset(string what, int unsigned rp, bit rd, bit [9:0] id);
    uvm_reg_field err = rpf("error_info", rp,
                            rd ? "split_rid_mismatch_err" : "split_bid_mismatch_err");
    uvm_reg_field mask = p_sequencer.regs.aou_interrupt_mask.int_mi0_id_mismatch_mask;
    if (detect_only) wait_cycles(accept_wait);
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
    load_blocked(AOU_T1_L2R);
    contain(side);
    wait_traffic();
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
    // Whether the DUT counts the unrequested response is undefined; if
    // SLV_TR_COMPLETE no longer reads 1 it could not deactivate, so the
    // scenario ends with a hard reset instead (not checked).
    drain();
    begin
      uvm_reg_data_t v;
      this.rd(p_sequencer.regs.aou_init.slv_tr_complete, v);
      if (v != 1) begin
        ok_last = 1'b0;
        `uvm_info(get_type_name(), $sformatf(
            "SLV_TR_COMPLETE is 0 after the %s; ending the scenario with a reset", what),
            UVM_LOW)
      end
    end
  endtask
endclass
