// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Forced deactivation through AOU_CON0.DEACTIVATE_FORCE (plan 2.7; MAS
// software-operation 7.1). The force is an implementation-defined escape hatch
// for a deactivation that is not completing: nothing is promised after it and
// software resets the device. Each loop activates, carries traffic (drained,
// or with +busy=1 still in flight), writes DEACTIVATE_FORCE and waits for the
// DUT's DeactivateReq, which aou_t1_force_deact_chk times against the write
// (T1-L52). The remote die does not answer it, as when the deactivation is not
// completing, so the two dies exchange nothing after the force. The loop then
// ends with the reset software would apply (sw_reset(): the Adapter's
// LinkReset, AOU_SW_RESET, the link back up) instead of checking anything the
// DUT does after the force. After the last loop both dies activate again and
// traffic must pass.
// Knobs: +loops +who=apb|remote|both|rand +order=dut|remote|simul|rand
// +busy=0|1 (default -1: random per loop) +T1_TXN=<per RP and direction>.
class aou_link_force_deact_vseq extends aou_link_act_deact_vseq;
  `uvm_object_utils(aou_link_force_deact_vseq)

  // Core cycles to wait for the checker's verdict; it times the DeactivateReq
  // itself, this only keeps a missing verdict from hanging the test.
  localparam int unsigned VERDICT_WAIT = 20000;

  function new(string name = "aou_link_force_deact_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned loops = arg_range("loops", 2, 4);
    aou_t1_who_e who = who_of(arg_str("who", "rand"));
    aou_t1_order_e order = order_of(arg_str("order", "rand"));
    int busy_arg = arg_int("busy", -1);
    int unsigned n = num_txns;
    bit keep_deact = cfg.l3_cfg.auto_deactivate;
    bit keep_ack = cfg.l3_cfg.auto_deact_ack;
    bit active = 1'b0;
    link_up();
    check_state(1'b0);
    for (int unsigned i = 0; i < loops; i++) begin
      bit busy = (busy_arg >= 0) ? 1'(busy_arg) : 1'($urandom_range(1));
      `uvm_info(get_type_name(), $sformatf("loop %0d/%0d: busy=%0b", i + 1, loops, busy),
                UVM_LOW)
      if (!active) sw_activate(who, order);
      active = 1'b0;
      check_state(1'b1);
      if (busy) begin
        traffic_nb(AOU_T1_BOTH_DIRS, (n + 1) / 2, aou_t1_traffic_cfg::named("short"));
        wait_cycles($urandom_range(400, 20));
      end else begin
        traffic(AOU_T1_BOTH_DIRS, n);
        drain();
      end
      force_deactivate();
      sw_reset(null, 1'b0);
      cfg.l3_cfg.auto_deactivate = keep_deact;
      cfg.l3_cfg.auto_deact_ack = keep_ack;
      // The reset aborted what was in flight; the traffic sequences still
      // have requests to issue, which need an activated link to finish.
      if (busy) begin
        sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
        active = 1'b1;
        wait_traffic();
      end
    end
    if (!active) sw_activate(who, order);
    check_traffic(n);
  endtask

  // DEACTIVATE_FORCE from software, then the checker's verdict on the
  // DeactivateReq it owes.
  task force_deactivate();
    aou_reg_activation_seq s = aou_reg_activation_seq::type_id::create("force");
    int unsigned n0 = env.force_chk.resolved();
    int unsigned k = 0;
    `uvm_info(get_type_name(), "DEACTIVATE_FORCE", UVM_LOW)
    cfg.l3_cfg.auto_deactivate = 1'b0;
    cfg.l3_cfg.auto_deact_ack = 1'b0;
    prep_reg(s);
    s.op = AOU_REG_FORCE_DEACTIVATE;
    s.wait_done = 1'b0;
    s.start(null);
    while (env.force_chk.resolved() == n0 && k++ < VERDICT_WAIT) wait_cycles(1);
    if (env.force_chk.resolved() == n0)
      `uvm_error(get_type_name(), $sformatf(
          "no verdict on a forced DeactivateReq %0d cycles after DEACTIVATE_FORCE", VERDICT_WAIT))
  endtask
endclass
