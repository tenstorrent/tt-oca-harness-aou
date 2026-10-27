// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Adapter-initiated FDI link events while AoU is ENABLED and traffic runs.
// The expectations follow MAS 7.3.6 and 7.3.7:
//   retrain, clk_wake  transparent: AoU stays ENABLED, no interrupt, every
//                      transaction completes with correct data;
//   l1                 software deactivates first (MAS §7.3.6), the adapter
//                      enters and leaves L1 (clk_req wake, Retrain, Active),
//                      and the link activates again;
//   linkerror,         the link is lost mid-traffic; INT_REQ_LINKRESET may
//   link_reset,        rise; software resets AOU_CORE while the link is down,
//   inband_drop,       brings it up and activates again. In-flight
//   disabled           transactions are aborted by the reset (an M-port ID
//                      mismatch interrupt is tolerated); all later traffic
//                      must complete. Disabled is Adapter-initiated.
//   sw_disable         software deactivates AoU (the FDI link stays Active:
//                      the bringup model holds BRG_ACTIVE) and then disables
//                      the link on the UCIe controller (Adapter Disabled).
//                      Local traffic queued while the link is down raises
//                      INT_ACTIVATE_START; the DUT must request nothing of
//                      the link until software restarts it (the model's NOP
//                      in LINKDOWN and RESET), and the activation then runs
//                      on the interrupt once the link is up.
//   l1_act             software deactivates, the adapter enters L1, and
//                      software writes ACTIVATE_START while the link is in
//                      L1: the link stays in L1 (the write wakes nothing),
//                      the handshake starts and its ActivateReq waits; the
//                      Adapter's PM exit (clk_req, Retrain, Active) lets the
//                      activation complete (T1-L50).
//   retrain_act        software deactivates and writes ACTIVATE_START while
//                      the Adapter holds the link in Retrain: the handshake
//                      completes once the link is Active again (T1-L50).
//   l1_traffic         software deactivates (ACTIVATE_START clear), the
//                      adapter enters L1, and local AXI traffic arrives: its
//                      INT_ACTIVATE_START is an activation request in L1, so
//                      the DUT wakes the link itself (lp_wake_req; UCIe r1.1
//                      8.2.9, integrator guide 6.6), the Adapter answers with
//                      Retrain and Active, and the activation runs on the
//                      interrupt; the traffic then completes.
// A link loss with AoU in use (linkerror, link_reset, inband_drop, disabled)
// raises INT_FDI_LINK_DOWN once and the DUT disables itself (T1-L48/L49,
// aou_base_test_seq); with +link_down_mask=1 the pin stays low and the
// sticky bit is checked instead.
// Knobs: +event=retrain|clk_wake|l1|linkerror|link_reset|inband_drop|disabled|
// sw_disable|l1_act|retrain_act|l1_traffic|rand (rand never picks disabled,
// sw_disable, l1_act, retrain_act or l1_traffic) +link_down_mask +loops +T1_TXN.
class aou_link_event_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_link_event_vseq)

  int unsigned n_down;

  function new(string name = "aou_link_event_vseq");
    super.new(name);
  endfunction

  task body();
    string evs[6] = '{"retrain", "clk_wake", "l1", "linkerror", "link_reset", "inband_drop"};
    int unsigned loops = arg_range("loops", 2, 4);
    string arg = arg_str("event", "rand");
    link_up();
    if (arg_int("link_down_mask", 0) != 0) begin
      aou_t1_feature_cfg f = aou_t1_feature_cfg::type_id::create("f");
      f.mask_fdi_link_down = 1;
      link_down_masked = 1'b1;
      program_cfg(f);
    end
    sw_activate();
    for (int unsigned i = 0; i < loops; i++) begin
      string ev = (arg == "rand") ? evs[$urandom_range(5)] : arg;
      `uvm_info(get_type_name(), $sformatf("event %0d/%0d: %s", i + 1, loops, ev), UVM_LOW)
      case (ev)
        "retrain", "clk_wake": transparent(ev == "retrain" ? LSM_EV_RETRAIN : LSM_EV_CLK_WAKE);
        "l1": l1_cycle();
        "linkerror": link_down(LSM_EV_LINKERROR, 1'b0);
        "link_reset": link_down(LSM_EV_LINK_RESET, 1'b0);
        "inband_drop": link_down(LSM_EV_LINK_RESET, 1'b1);
        "disabled": link_down(LSM_EV_DISABLED, 1'b0);
        "sw_disable": sw_disable();
        "l1_act": l1_act();
        "retrain_act": retrain_act();
        "l1_traffic": l1_traffic();
        default: `uvm_fatal(get_type_name(), {"unknown link event ", ev})
      endcase
    end
    check_traffic(num_txns);
    sw_deactivate();
  endtask

  task transparent(aou_lsm_ev_e ev);
    traffic_nb(AOU_T1_BOTH_DIRS, num_txns);
    wait_cycles($urandom_range(500, 20));
    link_event(ev);
    wait_traffic();
    drain();
    check_field(p_sequencer.regs.aou_init.activate_state_enabled, 1, "T1-L19",
                {ev.name(), " is transparent to AoU (MAS 7.3.7)"});
  endtask

  task l1_cycle();
    check_traffic(num_txns);
    sw_deactivate();
    link_event(LSM_EV_L1_ENTRY);
    wait_cycles($urandom_range(400, 20));
    link_event(LSM_EV_L1_EXIT);
    sw_activate();
  endtask

  task sw_disable();
    bit keep = cfg.lsm_cfg.rebringup_after_down;
    check_traffic(num_txns);
    sw_deactivate(AOU_T1_BY_APB);
    if (!link_is_up())
      `uvm_error(get_type_name(), "T1-L04: the FDI link left Active on an AoU deactivation")
    // Software's Link Disable on the UCIe controller. Both dies are cleanly
    // DISABLED, so no system reset is due (D18) and the Adapter alone brings
    // the link back, after its software restart delay.
    cfg.lsm_cfg.rebringup_after_down = 1'b0;
    link_event(LSM_EV_DISABLED);
    cfg.lsm_cfg.rebringup_after_down = keep;
    traffic_nb(AOU_T1_L2R, num_txns);
    wait_cycles($urandom_range(200, 20));
    link_event(LSM_EV_BRINGUP);
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(), "T1-L04: not ENABLED again after the link restart")
    wait_traffic();
    drain();
  endtask

  // Waits for ENABLED on both sides after an ACTIVATE_START written with
  // the link in L1 or Retrain (T1-L50).
  task wait_enabled(string how);
    env.l3.model.kick();
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(), {"T1-L50: not ENABLED after ACTIVATE_START ", how})
    if (!link_is_up())
      `uvm_error(get_type_name(), {"T1-L50: FDI link not Active after ACTIVATE_START ", how})
  endtask

  // ACTIVATE_START written with the link in L1. Writing it does not wake the
  // link (the bring-up controller wakes on pl_clk_req, I_SW_ACTIVATE_START or
  // INT_ACTIVATE_START, and the write clears the latter's condition), so the
  // handshake starts at once (I_INT_FSM_IN_ACTIVE is 1), the ActivateReq waits
  // in the TX path, and the activation completes when the Adapter exits L1.
  task l1_act();
    check_traffic(num_txns);
    sw_deactivate();
    link_event(LSM_EV_L1_ENTRY);
    wait_cycles($urandom_range(400, 20));
    `uvm_info(get_type_name(), "ACTIVATE_START with the link in L1", UVM_LOW)
    dut_activate(AOU_T1_BY_APB);
    wait_cycles($urandom_range(400, 50));
    if (env.lsm.drv.state != LSM_L1)
      `uvm_error(get_type_name(), $sformatf("T1-L50: FDI link %s after ACTIVATE_START in L1",
                 env.lsm.drv.state.name()))
    if (env.status.enabled)
      `uvm_error(get_type_name(), "T1-L50: ENABLED with the link in L1 (no flit can have crossed)")
    link_event(LSM_EV_L1_EXIT);
    wait_enabled("in L1");
  endtask

  task retrain_act();
    int unsigned n = 0;
    check_traffic(num_txns);
    sw_deactivate();
    fork
      link_event(LSM_EV_RETRAIN, 3000);
      begin
        while (env.lsm.drv.state != LSM_RETRAIN && ++n < cfg.link_timeout) @(env.lsm_vif.mon_cb);
        wait_cycles($urandom_range(200, 10));
        `uvm_info(get_type_name(), "ACTIVATE_START with the link in Retrain", UVM_LOW)
        dut_activate(AOU_T1_BY_APB);
      end
    join
    wait_enabled("in Retrain");
  endtask

  task l1_traffic();
    check_traffic(num_txns);
    sw_deactivate(AOU_T1_BY_APB);
    link_event(LSM_EV_L1_ENTRY);
    wait_cycles($urandom_range(400, 20));
    `uvm_info(get_type_name(), "local traffic with the link in L1", UVM_LOW)
    traffic_nb(AOU_T1_L2R, num_txns);
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(), "T1-L50: not ENABLED after local traffic in L1")
    if (!link_is_up())
      `uvm_error(get_type_name(), "T1-L50: FDI link not Active after local traffic in L1")
    wait_traffic();
    drain();
  endtask

  task link_down(aou_lsm_ev_e ev, bit inband_drop);
    n_down++;
    expect_event("INT_REQ_LINKRESET", 0, n_down);
    // The reset after a link loss drops the local M ports' transactions
    // (MAS 7.3.6), so a beat the subordinate still presents answers no
    // request and reads as an ID mismatch (MAS 7.2.2). Software clears the error
    // each time (aou_t1_sw_isr, MAS 7.2.2), so every orphan beat left on an M
    // port can raise it again: no upper bound.
    expect_event("INT_MI0_ID_MISMATCH", 0, 0);
    traffic_nb(AOU_T1_BOTH_DIRS, num_txns);
    wait_cycles($urandom_range(500, 20));
    // last_prog carries the interrupt mask (+link_down_mask) across the reset.
    recover(last_prog, 1'b1, ev, inband_drop);
    wait_traffic();
    drain();
  endtask
endclass
