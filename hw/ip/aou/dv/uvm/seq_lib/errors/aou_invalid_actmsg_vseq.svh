// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Activation messages in the wrong state (ports of
// ucie_axi_fdi_invalid_msgs_test and _en2dis_test, extended to every state
// and opcode). The DUT is held in DISABLED, ACTIVATE (its ActivateReq not
// answered), ENABLED or DEACTIVATE (its DeactivateReq not answered), and the
// remote die sends one opcode regardless of state. MAS §7.2.3 says which
// opcodes are invalid in each state; for those the DUT sets
// INVALID_ACTMSG_ERR, captures the opcode in INVALID_ACTMSG_INFO, raises
// INT_REQ_LINKRESET (unless masked, BUGS/014) and answers neither an
// invalid ActivateReq nor an invalid ActivateAck: AoU v0.8 8.3.3 makes the
// out-of-step Req/Ack an error and 8.4 transmits nothing in that state
// Software then recovers (LinkReset, AOU_SW_RESET,
// re-activation) and traffic must work.
// The remaining opcodes (an ActivateAck in DISABLED, a DeactivateAck in
// ENABLED) are ones MAS §7.2.3 does not list as invalid but AoU v0.8 8.3.3
// calls out of step: no compliant peer sends them, and what the DUT does
// with one is not defined. Either ending is accepted and neither is
// expected: the stray is absorbed and the link keeps working, or it ends in a
// reported error (LinkReset or interrupt) followed by the documented recovery
// (AOU_SW_RESET, re-activation), after which traffic must complete. What
// still fails (T1-L16) is a hang, silent corruption or misdelivery (the
// scoreboard), an unreported divergence from the peer, or the DUT answering
// the stray. For a DeactivateAck in ENABLED env.status records which ending
// happened (cg_stray_dack).
// +reps and the pl_trdy knobs keep the DUT's TX stage busy when the invalid
// ActivateReq arrives, where an Ack queued by mistake would still go out.
// After a permitted opcode the follow-up deactivation is started by the DUT
// (+followup=dut, the default) or by the remote die (+followup=remote). The
// remote die then sends its DeactivateReq before its DeactivateAck, so a DUT
// that kept a stray DeactivateAck from ENABLED reaches DISABLED before the
// real Ack, which then arrives as an invalid message and requests LinkReset:
// one of the accepted endings.
// Knobs: +state=disabled|activate|enabled|deactivate|all +op=act_req|act_ack|
// deact_req|deact_ack|all +mask=0|1 +reps=N (each case N times, default 1)
// +followup=dut|remote +T1_TXN.
class aou_invalid_actmsg_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_invalid_actmsg_vseq)

  typedef enum {ST_DISABLED, ST_ACTIVATE, ST_ENABLED, ST_DEACTIVATE} st_e;

  bit                mask;
  aou_t1_feature_cfg reprog;   // what software programs again after AOU_SW_RESET
  bit                race_lr;  // race_state() ended on a LinkReset
  bit                lr_seen;  // result of linkreset_seen()
  bit                remote_deact;  // +followup=remote

  function new(string name = "aou_invalid_actmsg_vseq");
    super.new(name);
  endfunction

  static function string op_name(bit [3:0] op);
    case (op)
      AOU_ACT_REQ:   return "act_req";
      AOU_ACT_ACK:   return "act_ack";
      AOU_DEACT_REQ: return "deact_req";
      default:       return "deact_ack";
    endcase
  endfunction

  // MAS §7.2.3: DISABLED/ACTIVATE take only Activate*, ENABLED/DEACTIVATE
  // only Deactivate*.
  static function bit invalid(st_e s, bit [3:0] op);
    return (s inside {ST_DISABLED, ST_ACTIVATE}) ? op inside {AOU_DEACT_REQ, AOU_DEACT_ACK}
                                                 : op inside {AOU_ACT_REQ, AOU_ACT_ACK};
  endfunction

  // Opcodes that are part of a normal handshake in that state, not tested.
  static function bit normal(st_e s, bit [3:0] op);
    return (s == ST_DISABLED && op == AOU_ACT_REQ) ||
           (s == ST_ACTIVATE && op inside {AOU_ACT_REQ, AOU_ACT_ACK}) ||
           (s == ST_ENABLED && op == AOU_DEACT_REQ) ||
           (s == ST_DEACTIVATE && op inside {AOU_DEACT_REQ, AOU_DEACT_ACK});
  endfunction

  task body();
    string st_arg = arg_str("state", "all");
    string op_arg = arg_str("op", "all");
    st_e states[$];
    bit [3:0] ops[$];
    int unsigned n_invalid = 0;
    int unsigned n_permitted = 0;
    int unsigned reps = arg_int("reps", 1);
    mask = 1'(arg_int("mask", 0));
    begin
      string fu = arg_str("followup", "dut");
      if (!(fu inside {"dut", "remote"}))
        `uvm_fatal(get_type_name(), {"+followup must be dut or remote, not ", fu})
      remote_deact = (fu == "remote");
    end
    for (int s = ST_DISABLED; s <= ST_DEACTIVATE; s++) begin
      string nm = (s == ST_DISABLED) ? "disabled" : (s == ST_ACTIVATE) ? "activate" :
                  (s == ST_ENABLED) ? "enabled" : "deactivate";
      if (st_arg == "all" || st_arg == nm) states.push_back(st_e'(s));
    end
    for (int o = 0; o < 4; o++)
      if (op_arg == "all" || op_arg == op_name(4'(o))) ops.push_back(4'(o));
    if (states.size() == 0 || ops.size() == 0)
      `uvm_fatal(get_type_name(), {"nothing to run for +state=", st_arg, " +op=", op_arg})
    foreach (states[i]) foreach (ops[j]) begin
      if (normal(states[i], ops[j])) continue;
      if (invalid(states[i], ops[j])) n_invalid += reps;
      else n_permitted += reps;
    end
    // A permitted opcode may end in LinkReset, which software recovers from;
    // the interrupt itself is then not an error.
    if (!mask && n_invalid + n_permitted != 0)
      expect_event("INT_REQ_LINKRESET", n_invalid, n_invalid + n_permitted);
    // The injected opcode is out of sequence by the spec; AOU_FDI_CHECKER
    // reports it, and the model reports the DUT's answer to it. The model's
    // count is checked exactly per case below.
    expect_event("AOU-R40", 0, 0);
    reprog = aou_t1_feature_cfg::type_id::create("reprog");
    if (mask) reprog.mask_invalid_actmsg = 1;
    program_cfg(reprog);
    link_up();
    foreach (states[i]) foreach (ops[j]) begin
      if (normal(states[i], ops[j])) continue;
      repeat (reps) run_case(states[i], ops[j]);
    end
  endtask

  function int unsigned model_r40();
    return cfg.l3_cfg.chk.count("AOU-R40", "aou_l3_model");
  endfunction

  // Brings the DUT to state s with the remote die holding back its answer.
  task enter(st_e s);
    aou_l3_cfg c = cfg.l3_cfg;
    case (s)
      ST_ACTIVATE: begin
        c.auto_ack = 1'b0;
        c.auto_activate = 1'b0;
        ensure_link();
        dut_activate(AOU_T1_BY_APB);
        wait_l3(AOU_LS_ACTIVATE, cfg.act_timeout);
        if (!l3_ok) `uvm_error(get_type_name(), "T1-L13: no ActivateReq from the DUT")
      end
      ST_ENABLED: sw_activate();
      ST_DEACTIVATE: begin
        aou_reg_activation_seq d = aou_reg_activation_seq::type_id::create("d");
        sw_activate();
        traffic(AOU_T1_BOTH_DIRS, num_txns);
        drain();
        c.auto_deact_ack = 1'b0;
        c.auto_deactivate = 1'b0;
        prep_reg(d);
        d.op = AOU_REG_DEACTIVATE;
        d.wait_done = 1'b0;
        d.start(null);
        wait_l3(AOU_LS_DEACTIVATE, cfg.act_timeout);
        if (!l3_ok) `uvm_error(get_type_name(), "T1-L13: no DeactivateReq from the DUT")
      end
      default: ;
    endcase
  endtask

  task restore_l3();
    aou_l3_cfg c = cfg.l3_cfg;
    c.auto_ack = 1'b1;
    c.auto_activate = 1'b1;
    c.auto_deact_ack = 1'b1;
    c.auto_deactivate = 1'b1;
  endtask

  task run_case(st_e s, bit [3:0] op);
    int unsigned r40;
    int unsigned le0;
    int unsigned ia0;
    int unsigned irq0 = irq_rises("INT_REQ_LINKRESET");
    bit bad = invalid(s, op);
    `uvm_info(get_type_name(), $sformatf("case: %s in %s (%s)", op_name(op), s.name(),
                                         bad ? "invalid" : "permitted by the MAS"), UVM_LOW)
    enter(s);
    r40 = model_r40();
    le0 = env.lsm.drv.n_le_react;
    // During a LinkReset condition software services the LinkReset, not
    // activation interrupts (the env ISR would wait for an ENABLED that the
    // reset ends); recover() turns the ISR back on.
    // Software first finishes servicing the activation it was handling.
    env.sw_isr.wait_idle();
    if (bad) env.sw_isr.enable = 1'b0;
    ia0 = irq_rises("INT_ACTIVATE_START");
    inject(op_name(op));
    wait_cycles(1000);
    if (bad) begin
      int unsigned acks = model_r40() - r40;
      // MAS §7.2.3/§7.3.5: a late ActivateReq requests LinkReset, "not this
      // interrupt", and does not start a second handshake.
      if (op == AOU_ACT_REQ && irq_rises("INT_ACTIVATE_START") != ia0)
        `uvm_error(get_type_name(), $sformatf(
                   "T1-L25: INT_ACTIVATE_START on an invalid ActivateReq in %s", s.name()))
      check_linkreset_status("invalid_actmsg_err", int'(op));
      if (!mask && irq_rises("INT_REQ_LINKRESET") == irq0)
        `uvm_error(get_type_name(), "T1-L14: no INT_REQ_LINKRESET for an invalid opcode")
      // Neither an invalid ActivateReq nor an invalid ActivateAck is answered
      // (AoU v0.8 8.3.3/8.4: error, nothing transmitted). Neither the MAS
      // nor the spec says whether an invalid DeactivateReq is, so at most one
      // DeactivateAck is accepted.
      case (op)
        AOU_ACT_REQ:
          if (acks != 0)
            `uvm_error(get_type_name(), $sformatf(
                       "T1-L15: %0d answers to an invalid ActivateReq, expected none%s", acks,
                       env.lsm.drv.n_le_react != le0 ?
                       " (the Adapter entered LinkError on lp_linkerror)" : ""))
        AOU_DEACT_REQ:
          if (acks > 1)
            `uvm_error(get_type_name(), $sformatf(
                       "T1-L15: %0d answers to an invalid DeactivateReq", acks))
        default:
          if (acks != 0)
            `uvm_error(get_type_name(), $sformatf(
                       "T1-L15: %0d answers to an invalid %s, expected none", acks, op_name(op)))
      endcase
      clear_linkreset_status(p_sequencer.regs.lp_linkreset.invalid_actmsg_err);
      restore_l3();
      recover(reprog);
      check_traffic(num_txns);
      sw_deactivate(AOU_T1_BY_APB);
    end else begin
      // Not invalid by the MAS but out of step by the spec: no answer to it,
      // and either a reported error at once, which software recovers from,
      // or the link still activates, carries traffic and deactivates.
      linkreset_seen(irq0);
      if (model_r40() != r40)
        `uvm_error(get_type_name(), $sformatf("T1-L16: the DUT answered a %s in %s",
                                              op_name(op), s.name()))
      restore_l3();
      if (lr_seen) begin
        `uvm_info(get_type_name(), $sformatf(
                  "%s in %s: the DUT requested LinkReset; recovering", op_name(op), s.name()),
                  UVM_LOW)
        recover_linkreset();
      end else begin
        followup(s, op);
      end
    end
  endtask

  // After a permitted opcode the DUT did not flag at once: activation (from
  // DISABLED), traffic and deactivation, each raced against
  // INT_REQ_LINKRESET. A LinkReset here is the DUT reacting late to the
  // stray, an accepted ending; software then recovers.
  task followup(st_e s, bit [3:0] op);
    int unsigned irq0 = irq_rises("INT_REQ_LINKRESET");
    if (s == ST_DISABLED) begin
      ensure_link();
      dut_activate(AOU_T1_BY_APB);
      race_state(1'b1, irq0);
      if (race_lr) begin
        late_linkreset(s, op);
        return;
      end
    end
    check_traffic(num_txns);
    if (remote_deact) begin
      // The local software answers INT_DEACTIVATE_START (env.sw_isr).
      env.l3.model.lnk.request_deactivate();
      env.l3.model.maybe_release_deact();
      env.l3.model.kick();
    end else begin
      aou_reg_activation_seq d = aou_reg_activation_seq::type_id::create("d");
      prep_reg(d);
      d.op = AOU_REG_DEACTIVATE;
      d.wait_done = 1'b0;
      d.start(null);
    end
    race_state(1'b0, irq0);
    // A LinkReset may also follow DISABLED (after a DeactivateAck in
    // ENABLED, the remote die's own DeactivateAck arriving after the DUT
    // disabled early). Once the remote die has nothing left to send the DUT,
    // give the DUT the status watcher's reaction time, so software recovers
    // from such a LinkReset before the test ends.
    if (!race_lr) begin
      int unsigned n = 0;
      while (!env.status.remote_tx_idle() && n++ < cfg.act_timeout) wait_cycles(1);
      wait_cycles(aou_t1_status::REACT_CYCLES + 1);
      linkreset_seen(irq0);
      race_lr = lr_seen;
    end
    if (race_lr) late_linkreset(s, op);
    else ensure_link();
  endtask

  task late_linkreset(st_e s, bit [3:0] op);
    `uvm_info(get_type_name(), $sformatf(
              "LinkReset after a %s in %s, which no compliant peer sends; recovering",
              op_name(op), s.name()), UVM_LOW)
    recover_linkreset();
  endtask

  // Software's answer to a LinkReset request: clear the cause, recover, and
  // the link must carry traffic and deactivate again.
  task recover_linkreset();
    clear_linkreset_status(p_sequencer.regs.lp_linkreset.invalid_actmsg_err);
    recover(reprog);
    check_traffic(num_txns);
    sw_deactivate(AOU_T1_BY_APB);
  endtask

  // INT_REQ_LINKRESET rose past irq0, or, with the source masked, the sticky
  // INVALID_ACTMSG_ERR bit is set.
  task linkreset_seen(int unsigned irq0);
    uvm_reg_data_t v;
    lr_seen = irq_rises("INT_REQ_LINKRESET") > irq0;
    if (lr_seen || !mask) return;
    rd(p_sequencer.regs.lp_linkreset.invalid_actmsg_err, v);
    lr_seen = v == 1;
  endtask

  // Waits until both sides report ENABLED (en=1) or DISABLED, or until
  // INT_REQ_LINKRESET rises past irq0 (race_lr=1).
  task race_state(bit en, int unsigned irq0);
    aou_link_state_e want = en ? AOU_LS_ENABLED : AOU_LS_DISABLED;
    int unsigned n = 0;
    race_lr = 1'b0;
    while (n++ < cfg.act_timeout) begin
      if (irq_rises("INT_REQ_LINKRESET") > irq0) begin
        race_lr = 1'b1;
        return;
      end
      if (l3_state() == want && (en ? env.status.enabled : env.status.disabled)) return;
      wait_cycles(1);
    end
    // With the source masked the LinkReset shows only in the sticky bit.
    begin
      uvm_reg_data_t v;
      rd(p_sequencer.regs.lp_linkreset.invalid_actmsg_err, v);
      if (v == 1) begin
        race_lr = 1'b1;
        return;
      end
    end
    `uvm_error(get_type_name(), $sformatf("T1-L16: %s not reached on both sides",
                                          en ? "ENABLED" : "DISABLED"))
  endtask
endclass
