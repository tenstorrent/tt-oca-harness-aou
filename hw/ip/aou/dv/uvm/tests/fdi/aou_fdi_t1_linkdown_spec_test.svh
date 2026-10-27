// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test with UCIe state encodings and every way the link goes
// down. The DUT never takes the link down except on an error, and never
// restarts it: software does both on the UCIe controller (integrator guide
// §6.6.2 "After a link-down"), which the Adapter model plays after
// sw_restart_delay cycles in Reset. So:
// 1. a software Link Disable with the AoU core still deactivated: the
//    Adapter reports Disabled (Link Status Down, Table 8-2: O_FDI_LINK_UP
//    drops, O_FDI_FSM_STATE follows), the DUT requests nothing (NOP,
//    lp_wake_req low), then Reset and the Adapter's bringup;
// 2. Adapter-initiated LinkReset, then Disabled, with AoU activated: the
//    same, with flits around them;
// 3. a Retrain that ends in LinkReset, and one that ends in Disabled, instead
//    of Active (UCIe r3.0 Figure 10-19: both may follow any state but
//    LinkError);
// 4. I_SW_LINKERROR_INJECT: lp_linkerror, the Adapter enters LinkError and
//    holds it while lp_linkerror is 1 (FDI-R49), then leaves on its own;
//    the DUT holds the link down until AOU_SW_RESET (the base test's
//    software) and requests nothing;
// 5. a Retrain that ends in LinkError, and LinkReset and Disabled escalating
//    to LinkError after the pl_clk_req handshake (UCIe r3.0 §10.2.3.2 rule
//    6). The DUT holds each down until AOU_SW_RESET; software writes it only
//    after the interrupt check below, and the Adapter trains again once it
//    has.
// Every link-down that finds the AoU core out of DISABLED (here: ACTIVATE,
// its ActivateReq never answered) raises INT_FDI_LINK_DOWN and the core
// disables itself; one that finds it DISABLED (1.) raises nothing (T1-L51).
// This test's software clears the sticky bit with write 1, as the MAS
// handler does; the ACTIVATE_START it never cleared re-activates the core
// once the link is up again, so each later link-down finds it in ACTIVATE.
// The bringup model checks the DUT side throughout.
class aou_fdi_t1_linkdown_spec_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_linkdown_spec_test)

  int unsigned down_wait = 2000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.req_timeout = 2000;
    // The Adapter's bringup after a link-down holds pl_clk_req, so the DUT
    // leaves WAIT_PRESENCE on it (no software activation pulse is needed).
    env.lsm_cfg.clk_req_hold_bringup = 1'b1;
  endfunction

  local task adapter_event(aou_lsm_ev_e kind, aou_lsm_state_e to = LSM_UNKNOWN);
    aou_lsm_event_seq s = aou_lsm_event_seq::type_id::create("ev");
    bit in_use = lsm_vif.mon_cb.act_st_disabled !== 1'b1;
    string what = to == LSM_UNKNOWN ? kind.name() : {kind.name(), " ending in ", to.name()};
    s.ev_kind = kind;
    s.ev_to = to;
    `uvm_info(get_type_name(), {"Adapter event ", what}, UVM_LOW)
    s.start(env.lsm.sqr);
    check_link_down_irq(in_use, what);
  endtask

  // An Adapter event that ends in `to` instead of its usual end, then the
  // link back up. A LinkError holds the DUT down until AOU_SW_RESET, which
  // also clears the interrupt: sw_reset_hold keeps it back until
  // adapter_event() has checked the interrupt, and the Adapter trains again
  // only after that.
  local task down_event(aou_lsm_ev_e kind, aou_lsm_state_e to);
    bit le = to == LSM_LINKERROR;
    if (le) begin
      sw_reset_hold = 1'b1;
      env.lsm_cfg.rebringup_after_down = 1'b0;
    end
    adapter_event(kind, to);
    if (le) begin
      sw_reset_hold = 1'b0;
      env.lsm_cfg.rebringup_after_down = 1'b1;
      adapter_event(LSM_EV_BRINGUP);
    end
    wait_link_up({kind.name(), " ending in ", to.name()});
  endtask

  // INT_FDI_LINK_DOWN after a link-down: set iff the core was in use, the
  // core DISABLED; software clears it with write 1 and the pin falls.
  local task check_link_down_irq(bit in_use, string what);
    if ((lsm_vif.mon_cb.int_fdi_link_down === 1'b1) != in_use)
      `uvm_error(get_type_name(), $sformatf("T1-L51: INT_FDI_LINK_DOWN %0b after %s, core %s",
                 lsm_vif.mon_cb.int_fdi_link_down, what, in_use ? "in use" : "DISABLED"))
    if (in_use && lsm_vif.mon_cb.act_st_disabled !== 1'b1)
      `uvm_error(get_type_name(), {"T1-L51: the core did not disable itself after ", what})
    if (lsm_vif.mon_cb.int_fdi_link_down === 1'b1) begin
      // Bit 12 set, ACTIVATE_START (bit 0) kept at the 1 this test's software wrote.
      `uvm_info(get_type_name(), "INT_FDI_LINK_DOWN: write 1 to clear", UVM_LOW)
      apb_write(32'h0000_0008, 32'h0000_1001);
      repeat (4) @(lsm_vif.mon_cb);
      if (lsm_vif.mon_cb.int_fdi_link_down !== 1'b0)
        `uvm_error(get_type_name(), "T1-L51: INT_FDI_LINK_DOWN still set after write 1 to clear")
    end
  endtask

  // Waits up to `max` cycles until the Adapter is (in = 1) or is not
  // (in = 0) in state `s`; ok = 0 on time-out.
  local task wait_adapter(aou_lsm_state_e s, bit in, int unsigned max, output bit ok);
    int unsigned n;
    ok = 1'b1;
    while ((env.lsm.drv.state == s) != in) begin
      @(lsm_vif.mon_cb);
      if (++n == max) begin
        ok = 1'b0;
        return;
      end
    end
  endtask

  // A software Link Disable before the APB activation: the Adapter enters
  // Disabled and comes back by itself. The DUT must follow it (BRG_LINKDOWN
  // in the model, FDI-M05/M06) and request nothing (FDI-M01/M02); a model
  // that never reaches BRG_LINKDOWN checked nothing, which is an error.
  task pre_activate();
    bit down_seen;
    bit watching = 1'b1;
    fork
      while (watching) begin
        if (env.lsm.mon.model.st == BRG_LINKDOWN) down_seen = 1'b1;
        @(lsm_vif.mon_cb);
      end
    join_none
    adapter_event(LSM_EV_DISABLED);
    wait_link_up("software Link Disable");
    watching = 1'b0;
    if (!down_seen)
      `uvm_error(get_type_name(), "the model never reached BRG_LINKDOWN in the Adapter's Disabled")
  endtask

  task link_events();
    bit ok;
    bit in_use;
    adapter_event(LSM_EV_LINK_RESET);
    wait_link_up("LinkReset");
    send_flits(4, 25);
    adapter_event(LSM_EV_DISABLED);
    wait_link_up("Disabled");
    send_flits(4, 25);
    down_event(LSM_EV_RETRAIN, LSM_LINKRESET);
    send_flits(2, 25);
    down_event(LSM_EV_RETRAIN, LSM_DISABLED);
    send_flits(2, 25);
    // The Adapter reacts to lp_linkerror by itself (react_linkerror_en); the
    // event afterwards only runs the bringup.
    `uvm_info(get_type_name(), "pulsing I_SW_LINKERROR_INJECT", UVM_LOW)
    in_use = lsm_vif.mon_cb.act_st_disabled !== 1'b1;
    env.lsm.drv.pulse_sw(LSM_SW_LINKERROR, 2);
    // The software LinkError is a link loss too: the controller enters
    // LINKERROR on the pulse and the interrupt a few cycles later. The check
    // (and its write 1 to clear) comes before the base test's AOU_SW_RESET,
    // which clears the registers: sw_reset_hold keeps that write back until
    // the check is done, whatever +sw_reset_delay_max draws.
    sw_reset_hold = 1'b1;
    for (int n = 0; n < 8 && lsm_vif.mon_cb.int_fdi_link_down !== 1'b1; n++) @(lsm_vif.mon_cb);
    check_link_down_irq(in_use, "I_SW_LINKERROR_INJECT");
    sw_reset_hold = 1'b0;
    wait_adapter(LSM_ACTIVE, 1'b0, down_wait, ok);
    adapter_event(LSM_EV_LINKERROR);
    wait_link_up("LinkError recovery");
    send_flits(2, 25);
    down_event(LSM_EV_RETRAIN, LSM_LINKERROR);
    send_flits(2, 25);
    down_event(LSM_EV_LINK_RESET, LSM_LINKERROR);
    send_flits(2, 25);
    down_event(LSM_EV_DISABLED, LSM_LINKERROR);
  endtask
endclass
