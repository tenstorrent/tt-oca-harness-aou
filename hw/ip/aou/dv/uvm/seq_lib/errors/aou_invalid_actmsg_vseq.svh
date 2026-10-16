// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Activation messages in the wrong state (ports of
// ucie_axi_fdi_invalid_msgs_test and _en2dis_test, extended to every state
// and opcode). The DUT is held in DISABLED, ACTIVATE (its ActivateReq not
// answered), ENABLED or DEACTIVATE (its DeactivateReq not answered), and the
// remote die sends one opcode regardless of state. MAS §7.2.3 says which
// opcodes are invalid in each state; for those the DUT sets
// INVALID_ACTMSG_ERR, captures the opcode in INVALID_ACTMSG_INFO, raises
// INT_REQ_LINKRESET (unless masked, BUGS/014) and acknowledges an invalid
// ActivateReq but not an invalid ActivateAck (#78/#79). Software then
// recovers (LinkReset, AOU_SW_RESET, re-activation) and traffic must work.
// Opcodes the MAS permits but the spec calls inconsistent (BUGS/013) must
// not raise LinkReset, and the link must still work afterwards.
// The Ack to an invalid ActivateReq must be on FDI before lp_linkerror rises
// (T1-L30, aou_t1_act_chk, for every ActivateReq in every test); +reps and
// the pl_trdy knobs give it Acks that can still sit in the DUT's TX stage.
// Knobs: +state=disabled|activate|enabled|deactivate|all +op=act_req|act_ack|
// deact_req|deact_ack|all +mask=0|1 +reps=N (each case N times, default 1)
// +T1_TXN.
class aou_invalid_actmsg_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_invalid_actmsg_vseq)

  typedef enum {ST_DISABLED, ST_ACTIVATE, ST_ENABLED, ST_DEACTIVATE} st_e;

  bit                mask;
  aou_t1_feature_cfg reprog;   // what software programs again after AOU_SW_RESET
  bit                race_lr;  // race_state() ended on a LinkReset

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
    // A permitted opcode that still ends in LinkReset is reported as T1-L16
    // and recovered from; the interrupt itself is then not a second error.
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
      // An invalid ActivateReq is still acknowledged; an invalid ActivateAck
      // is not (MAS §7.2.3). Whether an invalid DeactivateReq is: BUGS/013.
      case (op)
        AOU_ACT_REQ:
          if (acks != 1)
            `uvm_error(get_type_name(), $sformatf(
                       "T1-L15: %0d answers to an invalid ActivateReq, expected 1%s", acks,
                       env.lsm.drv.n_le_react != le0 ?
                       " (the Adapter entered LinkError on lp_linkerror first)" : ""))
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
      // Permitted by the MAS (BUGS/013): no LinkReset and no answer, and
      // the link still activates, carries traffic and deactivates.
      aou_core rm = p_sequencer.regs;
      check_field(rm.lp_linkreset.invalid_actmsg_err, 0, "T1-L16", "permitted by the MAS");
      if (model_r40() != r40)
        `uvm_error(get_type_name(), $sformatf("T1-L16: the DUT answered a %s in %s",
                                              op_name(op), s.name()))
      restore_l3();
      followup(s, op);
    end
  endtask

  // After a permitted opcode: activation (from DISABLED), traffic and
  // deactivation, each raced against INT_REQ_LINKRESET. A LinkReset here is
  // the DUT reacting late to the opcode it accepted (BUGS/013); software
  // then recovers.
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
    begin
      aou_reg_activation_seq d = aou_reg_activation_seq::type_id::create("d");
      prep_reg(d);
      d.op = AOU_REG_DEACTIVATE;
      d.wait_done = 1'b0;
      d.start(null);
    end
    race_state(1'b0, irq0);
    if (race_lr) late_linkreset(s, op);
    else ensure_link();
  endtask

  task late_linkreset(st_e s, bit [3:0] op);
    `uvm_error(get_type_name(), $sformatf(
               "T1-L16: LinkReset after a %s in %s that the MAS permits (BUGS/013)",
               op_name(op), s.name()))
    clear_linkreset_status(p_sequencer.regs.lp_linkreset.invalid_actmsg_err);
    recover(reprog);
    check_traffic(num_txns);
    sw_deactivate(AOU_T1_BY_APB);
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
