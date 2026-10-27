// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test followed by random Adapter-initiated link events
// (Retrain, L1, LinkError, LinkReset, clk_req wake, a Retrain that ends in
// LinkError, LinkReset or Disabled, and a LinkReset or Disabled that escalates
// to LinkError) with flits between them,
// a random pl_trdy policy and random stand-alone stalls. pl_clk_req is held
// through bringup so the DUT leaves WAIT_PRESENCE on it after the Adapter's
// restart from LinkError/LinkReset.
class aou_fdi_t1_link_stress_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_link_stress_test)

  int unsigned n_events = 10;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.clk_req_hold_bringup = 1'b1;
    foreach (env.fdi_cfg[p]) begin
      env.fdi_cfg[p].trdy_policy = aou_fdi_trdy_e'($urandom_range(3));
      env.fdi_cfg[p].stall_pct = 2;
      `uvm_info(get_type_name(), env.fdi_cfg[p].convert2string(), UVM_LOW)
    end
  endfunction

  task link_events();
    for (int unsigned i = 0; i < n_events; i++) begin
      aou_lsm_event_seq ev;
      case ($urandom_range(6))
        0: ev = aou_lsm_retrain_seq::type_id::create("ev");
        1: ev = aou_lsm_l1_seq::type_id::create("ev");
        2: ev = aou_lsm_linkerror_seq::type_id::create("ev");
        3: ev = aou_lsm_reset_seq::type_id::create("ev");
        4: ev = aou_lsm_clk_wake_seq::type_id::create("ev");
        5: begin
          aou_lsm_state_e ends[3] = '{LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED};
          ev = aou_lsm_retrain_seq::type_id::create("ev");
          ev.ev_to = ends[$urandom_range(2)];
        end
        default: begin
          ev = aou_lsm_event_seq::type_id::create("ev");
          ev.ev_kind = ($urandom_range(1) != 0) ? LSM_EV_DISABLED : LSM_EV_LINK_RESET;
          ev.ev_to = LSM_LINKERROR;
        end
      endcase
      `uvm_info(get_type_name(), $sformatf("event %0d: %s%s", i, ev.ev_kind.name(),
                ev.ev_to == LSM_UNKNOWN ? "" : {" ending in ", ev.ev_to.name()}), UVM_LOW)
      fork
        ev.start(env.lsm.sqr);
        send_flits($urandom_range(6, 1), 40);
      join
      wait_link_up(ev.ev_kind.name());
    end
  endtask
endclass
