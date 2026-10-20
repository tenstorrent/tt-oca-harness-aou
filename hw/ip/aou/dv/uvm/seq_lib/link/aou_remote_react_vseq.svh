// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die deactivates and re-activates at once: its ActivateReq follows
// its own DeactivateAck by one flit, which AoU 8.4 allows (DISABLED may send
// ActivateReq). The DUT reaches DISABLED a couple of cycles after that Ack, so
// the Req must find it DISABLED, not DEACTIVATE (no INVALID_ACTMSG).
// A remote-initiated deactivation also takes the DUT's FDI link down
// too: the DUT requests LinkReset once DISABLED. That is a deliberate
// teardown, so the DUT holds the training trigger until an activation request
// (UCIe r3.0 10.3.3.8). When the remote's ActivateReq reaches the DUT before the link is
// down, it gives that request (INT_ACTIVATE_START): the Adapter's software
// pulse is then off, so the trigger must come from the DUT itself (FDI-R51).
// When the teardown closes the mainband first, nothing local asks for the
// link and software restarts it (the Adapter's sw_restart_delay pulse).
// Either way the activation exchange straddles the FDI reset, so the system
// model resets both dies while the link is down (cfg.sysrst_on_linkdown,
// relink()): the remote's Req and any answer the DUT queued are void, both
// dies come back DISABLED, the test activates them again, and an answer from
// before the reset that still goes out is an illegal message to the checkers
// (AOU-R40).
// Knobs: +rounds=N (default 2..4) +T1_TXN.
class aou_remote_react_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_remote_react_vseq)

  function new(string name = "aou_remote_react_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned rounds = arg_range("rounds", 2, 4);
    int unsigned keep = cfg.lsm_cfg.sw_restart_delay;
    link_up();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    for (int unsigned i = 0; i < rounds; i++) begin
      `uvm_info(get_type_name(), $sformatf("round %0d/%0d: remote deactivates, then re-activates",
                                           i + 1, rounds), UVM_LOW)
      check_traffic(num_txns);
      react_round(keep);
    end
    check_traffic(num_txns);
  endtask

  task react_round(int unsigned keep);
    int unsigned n;
    bit reacted = 1'b0;
    int unsigned int_act = env.status.rises["INT_ACTIVATE_START"];
    fork
      begin
        while (env.l3.model.lnk.state != AOU_LS_DEACTIVATE)
          env.l3.model.lnk.state_ev.wait_trigger();
        while (env.l3.model.lnk.state != AOU_LS_DISABLED)
          env.l3.model.lnk.state_ev.wait_trigger();
        env.l3.model.lnk.request_activate();
        env.l3.model.kick();
        reacted = 1'b1;
      end
    join_none
    env.l3.model.lnk.request_deactivate();
    env.l3.model.maybe_release_deact();
    env.l3.model.kick();
    // Wait for the remote's ActivateReq, then for the DUT's FDI teardown (or,
    // should the link stay up, for ENABLED).
    while (!reacted && n < cfg.act_timeout) begin
      wait_cycles(1);
      n++;
    end
    while (!(env.l3.model.lnk.state == AOU_LS_ENABLED && env.status.enabled) &&
           !(env.lsm.drv.state == LSM_RESET && !link_is_up())) begin
      wait_cycles(1);
      if (++n >= cfg.act_timeout) break;
    end
    if (!link_is_up()) begin
      bit rcvd = env.status.rises["INT_ACTIVATE_START"] != int_act;
      `uvm_info(get_type_name(),
                rcvd ? "link down after the remote ActivateReq: the DUT restarts it" :
                       "link down before the remote ActivateReq: software restarts it", UVM_LOW)
      if (rcvd) cfg.lsm_cfg.sw_restart_delay = 0;
      relink();
      cfg.lsm_cfg.sw_restart_delay = keep;
      if (sysrst_done) begin
        if (!env.status.disabled || env.l3.model.lnk.state != AOU_LS_DISABLED)
          `uvm_error(get_type_name(),
                     $sformatf("T1-L04: not DISABLED after the system reset (remote %s)",
                               env.l3.model.lnk.state.name()))
        sw_activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
      end
    end
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    env.sw_isr.hold_requests(1'b0);
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(),
                 $sformatf("T1-L04: not ENABLED after the remote re-activated (remote %s, DUT %0b)",
                           env.l3.model.lnk.state.name(), env.status.act_ok))
    env.sw_isr.wait_idle();
  endtask
endclass
