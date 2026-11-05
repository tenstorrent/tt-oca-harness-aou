// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Profile exchange in the ActivateReq (AoU v0.8 Ch. 11; MAS software-operation
// 7.1 PROFILE_CFG_RPn / PROFILE_RMT_RPn). Both dies announce a ProfileID/Rev/Opt
// per RP; nothing is negotiated and nothing acts on the values. The DUT
// implements the Basic Profile only: PROFILE_CFG_RPn are read-only 0/0/0 and
// its ActivateReq carries 0 for every RP (AOU-R12 in aou_unpacker). What is
// checked here is the DUT's side of the exchange as software sees it.
//   (a) PROFILE_CFG_RP0-3 read 0 and ignore a write of all ones (T1-L56); the
//       remote die takes random profiles for all four RPs; activation by a
//       random initiator; then PROFILE_RMT_RP0-3 read back: the remote die's
//       fields for the RPs it has, 0 for the others, RCVD 1 (T1-L53).
//   (b) Deactivation; PROFILE_RMT_RPn still hold the first values (T1-L54);
//       the remote reprogrammed and PROFILE_CFG_RPn written again (ignored);
//       re-activation; PROFILE_RMT_RPn hold the new values.
//   (c) The remote die changes its profile again and sends an ActivateReq
//       while the link is ENABLED: the DUT flags it (INVALID_ACTMSG_ERR, a
//       LinkReset request) and PROFILE_RMT_RPn keep the stored values
//       (T1-L54). Software recovers with AOU_SW_RESET, after which all eight
//       registers read 0 (T1-L54, T1-L56): the DUT's next ActivateReq is the
//       Basic Profile as always (AOU-R12) and PROFILE_RMT_RPn take the remote
//       die's latest values.
// Every ActivateReq is four granules, the other Activation messages one
// (T1-L55, aou_unpacker / AOU_FDI_CHECKER). Knobs: +loops=N (default 1) runs
// (a)+(b) N times before (c); +skip_reset=1 ends after (b).
class aou_act_profile_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_act_profile_vseq)

  bit [4:0]  rmt_id[AOU_RP_MAX];     // the remote die's current configuration
  bit [4:0]  rmt_rev[AOU_RP_MAX];
  bit [15:0] rmt_opt[AOU_RP_MAX];
  bit [4:0]  stored_id[AOU_RP_MAX];  // what PROFILE_RMT_RPn must hold now
  bit [4:0]  stored_rev[AOU_RP_MAX];
  bit [15:0] stored_opt[AOU_RP_MAX];
  bit        stored_rcvd;

  function new(string name = "aou_act_profile_vseq");
    super.new(name);
  endfunction

  task body();
    int loops = arg_int("loops", 1);
    bit skip_reset = arg_int("skip_reset", 0) != 0;
    link_up();
    check_rmt("T1-L54", "after reset, before any activation");
    check_cfg("T1-L56", "after reset");
    for (int i = 0; i < loops; i++) begin
      if (i > 0) begin
        sw_deactivate(AOU_T1_BY_RANDOM);
        check_rmt("T1-L54", "DISABLED again before the next round: the stored profile is kept");
      end
      exchange_once();         // (a)
      hold_and_change();       // (b)
    end
    if (!skip_reset) stale_req_and_reset();   // (c)
    sw_deactivate(AOU_T1_BY_RANDOM);
  endtask

  // Random fields on the remote die for every RP; a write to the DUT's
  // read-only PROFILE_CFG_RPn, which must change nothing.
  task program_remote(string why);
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      rmt_id[r] = 5'($urandom);
      rmt_rev[r] = 5'($urandom);
      rmt_opt[r] = 16'($urandom);
      // Some RPs keep the Basic Profile, so zero fields are seen beside
      // non-zero ones.
      if ($urandom_range(3) == 0) {rmt_id[r], rmt_rev[r], rmt_opt[r]} = '0;
      remote_profile(r, rmt_id[r], rmt_rev[r], rmt_opt[r]);
      `uvm_info(get_type_name(), $sformatf(
                "%s: RP%0d remote %0d/%0d/0x%04h%s", why, r, rmt_id[r], rmt_rev[r], rmt_opt[r],
                (r < cfg.l3_cfg.rp_count) ? "" : " (RP absent on the remote)"), UVM_LOW)
    end
    write_cfg_ignored("T1-L56", why);
  endtask

  // The remote die's ActivateReq the DUT accepts next stores these.
  function void expect_stored();
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      stored_id[r] = (r < cfg.l3_cfg.rp_count) ? rmt_id[r] : '0;
      stored_rev[r] = (r < cfg.l3_cfg.rp_count) ? rmt_rev[r] : '0;
      stored_opt[r] = (r < cfg.l3_cfg.rp_count) ? rmt_opt[r] : '0;
    end
    stored_rcvd = 1'b1;
  endfunction

  function void expect_cleared();
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      stored_id[r] = '0;
      stored_rev[r] = '0;
      stored_opt[r] = '0;
    end
    stored_rcvd = 1'b0;
  endfunction

  // PROFILE_RMT_RP0-3 against stored_*.
  task check_rmt(string rule, string why);
    aou_core rm = p_sequencer.regs;
    aou_rule_log::check(rule, get_type_name());
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      uvm_reg rg = rm.get_reg_by_name($sformatf("profile_rmt_rp%0d", r));
      check_field(rg.get_field_by_name("profile_id"), uvm_reg_data_t'(stored_id[r]), rule, why);
      check_field(rg.get_field_by_name("profile_rev"), uvm_reg_data_t'(stored_rev[r]), rule,
                  why);
      check_field(rg.get_field_by_name("profile_opt"), uvm_reg_data_t'(stored_opt[r]), rule,
                  why);
      check_field(rg.get_field_by_name("rcvd"), uvm_reg_data_t'(stored_rcvd), rule, why);
    end
  endtask

  // PROFILE_CFG_RP0-3 read 0: the Basic Profile, the only one the DUT has.
  task check_cfg(string rule, string why);
    aou_core rm = p_sequencer.regs;
    aou_rule_log::check(rule, get_type_name());
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      uvm_reg rg = rm.get_reg_by_name($sformatf("profile_cfg_rp%0d", r));
      check_field(rg.get_field_by_name("profile_id"), 0, rule, why);
      check_field(rg.get_field_by_name("profile_rev"), 0, rule, why);
      check_field(rg.get_field_by_name("profile_opt"), 0, rule, why);
    end
  endtask

  // Writes random non-zero values to PROFILE_CFG_RP0-3 (read-only) and reads
  // 0 back.
  task write_cfg_ignored(string rule, string why);
    aou_core rm = p_sequencer.regs;
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      uvm_reg rg = rm.get_reg_by_name($sformatf("profile_cfg_rp%0d", r));
      wr(rg.get_field_by_name("profile_id"), $urandom_range(1, 31));
      wr(rg.get_field_by_name("profile_rev"), $urandom_range(1, 31));
      wr(rg.get_field_by_name("profile_opt"), $urandom_range(1, 65535));
    end
    check_cfg(rule, {why, ": PROFILE_CFG_RPn written, read-only"});
  endtask

  // (a)
  task exchange_once();
    program_remote("(a) programming the remote");
    sw_activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    expect_stored();
    check_rmt("T1-L53", "ENABLED, after the remote die's ActivateReq");
    check_cfg("T1-L56", "ENABLED");
    check_traffic(num_txns);
  endtask

  // (b)
  task hold_and_change();
    sw_deactivate(AOU_T1_BY_RANDOM);
    check_rmt("T1-L54", "DISABLED after a deactivation: the stored profile is kept");
    program_remote("(b) reprogramming the remote while DISABLED");
    check_rmt("T1-L54", "PROFILE_CFG_RPn written: PROFILE_RMT_RPn unaffected");
    sw_activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    expect_stored();
    check_rmt("T1-L53", "ENABLED again, after the second ActivateReq");
    check_traffic(num_txns);
  endtask

  // (c)
  task stale_req_and_reset();
    aou_core rm = p_sequencer.regs;
    aou_l3_act_inject_seq s = aou_l3_act_inject_seq::type_id::create("inj");
    int unsigned irq0 = irq_rises("INT_REQ_LINKRESET");
    // The remote die's configuration moves on; the stale ActivateReq carries
    // the new values (aou_l3_model::send fills them in), which must not land
    // in the registers.
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      rmt_id[r] = ~rmt_id[r];
      rmt_rev[r] = 5'($urandom);
      rmt_opt[r] = ~rmt_opt[r];
      remote_profile(r, rmt_id[r], rmt_rev[r], rmt_opt[r]);
    end
    // The injected ActivateReq is out of sequence by the spec: AOU_FDI_CHECKER
    // reports it, as does the model should the DUT answer it (T1-L15 below).
    expect_event("AOU-R40", 0, 0);
    expect_event("INT_REQ_LINKRESET", 1, 1);
    // Software services the LinkReset, not activation interrupts, until the
    // recovery (recover() turns the ISR back on).
    env.sw_isr.wait_idle();
    env.sw_isr.enable = 1'b0;
    s.op = AOU_ACT_REQ;
    s.start(p_sequencer.l3_sqr);
    wait_cycles(1000);
    check_linkreset_status("invalid_actmsg_err", int'(AOU_ACT_REQ));
    if (cfg.l3_cfg.chk.count("AOU-R40", "aou_l3_model") != 0)
      `uvm_error(get_type_name(), "T1-L15: the DUT answered an ActivateReq received in ENABLED")
    check_rmt("T1-L54", "after an ActivateReq rejected in ENABLED");
    clear_linkreset_status(rm.lp_linkreset.invalid_actmsg_err);
    // MAS 7.3.6 recovery: link down, AOU_SW_RESET, link up; no reactivation
    // yet, so the cleared registers can be read first.
    recover(null, 1'b0);
    expect_cleared();
    check_rmt("T1-L54", "after AOU_SW_RESET");
    check_cfg("T1-L56", "after AOU_SW_RESET");
    // The DUT announces the Basic Profile (AOU-R12), the remote die its latest
    // configuration.
    sw_activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    expect_stored();
    check_rmt("T1-L53", "ENABLED after the recovery");
    check_traffic(num_txns);
  endtask
endclass
