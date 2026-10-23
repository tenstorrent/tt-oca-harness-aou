// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die deactivates and re-activates at once: its ActivateReq follows
// its own DeactivateAck by one flit, which AoU 8.4 allows (DISABLED may send
// ActivateReq). The DUT reaches DISABLED a couple of cycles after that Ack, so
// the Req must find it DISABLED, not DEACTIVATE (no INVALID_ACTMSG). The FDI
// link stays Active across the deactivation (a deactivation never takes it
// down; the bringup model holds BRG_ACTIVE), so the Req raises
// INT_ACTIVATE_START and software activates the DUT again from there.
// Knobs: +rounds=N (default 2..4) +T1_TXN.
class aou_remote_react_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_remote_react_vseq)

  function new(string name = "aou_remote_react_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned rounds = arg_range("rounds", 2, 4);
    link_up();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    for (int unsigned i = 0; i < rounds; i++) begin
      `uvm_info(get_type_name(), $sformatf("round %0d/%0d: remote deactivates, then re-activates",
                                           i + 1, rounds), UVM_LOW)
      check_traffic(num_txns);
      react_round();
    end
    check_traffic(num_txns);
  endtask

  task react_round();
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
    while (!reacted && n < cfg.act_timeout) begin
      wait_cycles(1);
      n++;
    end
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    env.sw_isr.hold_requests(1'b0);
    if (!link_is_up())
      `uvm_error(get_type_name(), "T1-L04: the FDI link left Active on a remote deactivation")
    if (env.status.rises["INT_ACTIVATE_START"] == int_act)
      `uvm_error(get_type_name(), "T1-L05: no INT_ACTIVATE_START after the remote ActivateReq")
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(),
                 $sformatf("T1-L04: not ENABLED after the remote re-activated (remote %s, DUT %0b)",
                           env.l3.model.lnk.state.name(), env.status.act_ok))
    env.sw_isr.wait_idle();
  endtask
endclass
