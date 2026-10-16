// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Repeated activation and deactivation with traffic in between (port of
// ucie_axi_fdi_aou_flits_test, extended). Each loop activates from the DUT,
// the remote die or both (randomized order and gap, simultaneous included),
// carries traffic, and deactivates from either side under a CREDIT_MANAGE
// value, either idle or with transactions still in flight (MAS §7.3.6:
// requests the deactivation caught are answered after a re-activation).
// The AOU_INIT status bits are read back at every step.
// Knobs: +loops +who=apb|remote|both|rand +order=dut|remote|simul|rand
// +deact_who=... +credit_manage=0|1 (-1 random per loop) +busy=0|1 (-1 random)
// +T1_TXN=<per RP and direction> +force=0|1.
// +early_act=1 (plan 1.11; MAS 7.3.2): every activation is software's
// ACTIVATE_START written while the FDI link is down (at power-on, then after
// an Adapter LinkReset). The register reads back 1 with the DUT still DISABLED
// until the link comes up (T1-L43); the activation must then start on its own
// (T1-V02/T1-V03), and the bit clears itself once ENABLED (T1-L09). The test
// keeps the Adapter from bringing the link up after reset.
class aou_link_act_deact_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_link_act_deact_vseq)

  bit force_dflt;

  function new(string name = "aou_link_act_deact_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned loops = arg_range("loops", 3, 6);
    aou_t1_who_e who = who_of(arg_str("who", "rand"));
    aou_t1_order_e order = order_of(arg_str("order", "rand"));
    aou_t1_who_e deact_who = who_of(arg_str("deact_who", force_dflt ? "apb" : "rand"));
    int cm_arg = arg_int("credit_manage", -1);
    int busy_arg = arg_int("busy", force_dflt ? 0 : -1);
    bit forced = 1'(arg_int("force", force_dflt));
    bit early = 1'(arg_int("early_act", 0));
    int unsigned n = num_txns;
    if (early) env.rst.wait_released();
    else link_up();
    check_state(1'b0);
    for (int unsigned i = 0; i < loops; i++) begin
      int cm = (cm_arg >= 0) ? cm_arg : $urandom_range(1);
      bit busy = (busy_arg >= 0) ? 1'(busy_arg) : 1'($urandom_range(1));
      `uvm_info(get_type_name(), $sformatf("loop %0d/%0d: credit_manage=%0d busy=%0b forced=%0b",
                                           i + 1, loops, cm, busy, forced), UVM_LOW)
      if (early) early_activate();
      else sw_activate(who, order);
      check_state(1'b1);
      if (busy) begin
        busy_deactivate(forced ? AOU_T1_BY_APB : deact_who, forced, cm, n);
      end else begin
        traffic(AOU_T1_BOTH_DIRS, n);
        drain();
        sw_deactivate(forced ? AOU_T1_BY_APB : deact_who, forced, cm);
      end
      check_state(1'b0);
    end
    // A clean restart after the last deactivation, with credits advertised
    // afresh (the model checks the new initial CrdtGrant, AOU-R24).
    sw_activate(who, order);
    check_traffic(n);
  endtask

  // ACTIVATE_START while the FDI link is down: held, nothing happens until the
  // Adapter brings the link up, then the DUT activates without further help.
  task early_activate();
    aou_core rm = p_sequencer.regs;
    // After a deactivation the DUT may have dropped the link already (BUGS/011)
    // while the Adapter is still Active: the Adapter resets it either way.
    if (env.lsm.drv.state != LSM_RESET) begin
      bit keep = cfg.lsm_cfg.rebringup_after_down;
      cfg.lsm_cfg.rebringup_after_down = 1'b0;
      link_event(LSM_EV_LINK_RESET);
      cfg.lsm_cfg.rebringup_after_down = keep;
    end
    env.sw_isr.wait_idle();
    wait_cycles($urandom_range(200, 10));
    if (link_is_up())
      `uvm_error(get_type_name(), "T1-L43: FDI link still Active; the test needs it down")
    `uvm_info(get_type_name(), "ACTIVATE_START with the FDI link down", UVM_LOW)
    dut_activate(AOU_T1_BY_APB);
    check_field(rm.aou_init.activate_start, 1, "T1-L43", "set before link-up, held until ENABLED");
    wait_cycles($urandom_range(2000, 50));
    check_field(rm.aou_init.activate_state_disabled, 1, "T1-L43", "no activation before link-up");
    link_event(LSM_EV_BRINGUP);
    env.l3.model.kick();
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok)
      `uvm_error(get_type_name(), $sformatf(
          "T1-V02: remote (L3) not ENABLED after link-up with ACTIVATE_START set: %s",
          env.l3.model.lnk.state.name()))
    if (!env.status.act_ok)
      `uvm_error(get_type_name(), "T1-V03: DUT not ENABLED after link-up with ACTIVATE_START set")
  endtask

  // Deactivates with traffic in flight. With CREDIT_MANAGE=0 only the local
  // side issues: the MAS forbids responses after the DUT's DeactivateReq, so
  // a remote request caught by it could never complete (BUGS/009).
  task busy_deactivate(aou_t1_who_e who, bit forced, int cm, int unsigned n);
    aou_t1_dir_e dir = (cm != 0) ? AOU_T1_BOTH_DIRS : AOU_T1_L2R;
    int unsigned k = 0;
    traffic_nb(dir, (n + 1) / 2, aou_t1_traffic_cfg::named("short"));
    wait_cycles($urandom_range(400, 20));
    sw_deactivate(who, forced, cm);
    while (pending() && k++ < 4) begin
      `uvm_info(get_type_name(), "transactions pending after deactivation: activating again",
                UVM_LOW)
      sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
      wait_traffic();
      drain();
      sw_deactivate(AOU_T1_BY_APB, 1'b0, cm);
    end
    if (pending())
      `uvm_error(get_type_name(), "T1-L07: transactions still pending after 4 re-activations")
  endtask

  function bit pending();
    string why;
    return n_traffic != 0 || env.outstanding(why) != 0;
  endfunction

  // AOU_INIT after activation (en=1) or deactivation (en=0): the state bits,
  // the self-cleared start bits (RDL), and bus-clean status once disabled.
  task check_state(bit en);
    aou_core rm = p_sequencer.regs;
    check_field(rm.aou_init.activate_state_enabled, uvm_reg_data_t'(en), "T1-L08",
                "activation state");
    check_field(rm.aou_init.activate_state_disabled, uvm_reg_data_t'(!en), "T1-L08",
                "activation state");
    check_field(rm.aou_init.activate_start, 0, "T1-L09", "self-clears when enabled");
    check_field(rm.aou_init.deactivate_start, 0, "T1-L09", "self-clears when disabled");
    if (!en) begin
      check_field(rm.aou_init.mst_tr_complete, 1, "T1-L10", "nothing pending once disabled");
      check_field(rm.aou_init.slv_tr_complete, 1, "T1-L10", "nothing pending once disabled");
    end
  endtask
endclass
