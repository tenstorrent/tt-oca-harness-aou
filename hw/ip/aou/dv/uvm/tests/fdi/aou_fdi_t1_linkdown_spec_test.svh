// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test with UCIe state encodings and every way the link goes
// down (BUGS/001 item 4). NOP is ignored outside Reset (r1.1 Table 8-3), so:
// 1. teardown: I_SW_DEACTIVATE_START with the AoU core deactivated; the DUT
//    requests LinkReset or Disabled, the Adapter goes there and returns to
//    Reset on the DUT's Active request (§8.3.3.5/8.3.3.6); then bringup,
//    whose training trigger the DUT holds until software pulses
//    I_SW_ACTIVATE_START (the Adapter model does it);
// 2. Adapter-initiated LinkReset, then Disabled: Link Status Down
//    (Table 8-2), so O_FDI_LINK_UP drops; Reset and bringup follow (the
//    DUT restarts by itself after the LinkReset, and after the Disabled, a
//    software Link Disable, only on I_SW_ACTIVATE_START);
// 3. I_SW_LINKERROR_INJECT: lp_linkerror, the Adapter enters LinkError and
//    leaves it only on Active with lp_linkerror=0 (§8.3.3.7, FDI-R49).
// The bringup model checks the DUT side throughout.
class aou_fdi_t1_linkdown_spec_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_linkdown_spec_test)

  int unsigned down_wait = 2000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.fdi_enc = AOU_FDI_ENC_SPEC;
    env.lsm_cfg.req_timeout = 2000;
    // The DUT restarts by itself after an unplanned link-down, and on
    // I_SW_ACTIVATE_START after a deliberate one.
    env.lsm_cfg.clk_req_hold_bringup = 1'b1;
  endfunction

  local task adapter_event(aou_lsm_ev_e kind);
    aou_lsm_event_seq s = aou_lsm_event_seq::type_id::create("ev");
    s.ev_kind = kind;
    `uvm_info(get_type_name(), {"Adapter event ", kind.name()}, UVM_LOW)
    s.start(env.lsm.sqr);
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

  // Teardown needs I_AOU_ACTIVATE_ST_DISABLED, so it runs before the APB
  // activation. The Adapter answers a LinkReset/Disabled request and returns
  // to Reset on Active. A DUT that requests nothing is reported by the model
  // (FDI-M01 in BRG_DEACTIVATE); the Adapter then resets the link itself, as
  // a test does after a deactivation. If the model never reaches
  // BRG_DEACTIVATE the step checked nothing, which is an error.
  task pre_activate();
    bit ok;
    bit deact_seen;
    bit watching = 1'b1;
    fork
      while (watching) begin
        if (env.lsm.mon.model.st == BRG_DEACTIVATE) deact_seen = 1'b1;
        @(lsm_vif.mon_cb);
      end
    join_none
    `uvm_info(get_type_name(), "teardown: pulsing I_SW_DEACTIVATE_START", UVM_LOW)
    env.lsm.drv.pulse_sw(LSM_SW_DEACTIVATE, 2);
    wait_adapter(LSM_ACTIVE, 1'b0, down_wait, ok);
    if (ok) wait_adapter(LSM_RESET, 1'b1, 2 * env.lsm_cfg.req_timeout + 1000, ok);
    watching = 1'b0;
    if (!deact_seen)
      `uvm_error(get_type_name(),
                 "teardown: the model never reached BRG_DEACTIVATE after I_SW_DEACTIVATE_START")
    if (!ok) `uvm_info(get_type_name(), "teardown: no link-down request answered", UVM_LOW)
    adapter_event(ok ? LSM_EV_BRINGUP : LSM_EV_LINK_RESET);
    wait_link_up("teardown");
  endtask

  task link_events();
    bit ok;
    adapter_event(LSM_EV_LINK_RESET);
    wait_link_up("LinkReset");
    send_flits(4, 25);
    adapter_event(LSM_EV_DISABLED);
    wait_link_up("Disabled");
    send_flits(4, 25);
    `uvm_info(get_type_name(), "pulsing I_SW_LINKERROR_INJECT", UVM_LOW)
    env.lsm.drv.pulse_sw(LSM_SW_LINKERROR, 2);
    wait_adapter(LSM_ACTIVE, 1'b0, down_wait, ok);
    adapter_event(LSM_EV_LINKERROR);
    wait_link_up("LinkError recovery");
  endtask
endclass
