// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Shared base of the link, error and lifecycle virtual sequences: plusarg
// knobs, register reads and writes as software does them, the LinkReset
// status checks and the recovery the MAS prescribes (§7.2.3, §7.3.6).
class aou_link_base_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_link_base_vseq)

  int unsigned poll_max = 400;
  bit          poll_ok;     // result of poll()

  function new(string name = "aou_link_base_vseq");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------
  // Knobs: +name=value on the command line, else the default.
  // ---------------------------------------------------------------------
  function string arg_str(string name, string dflt);
    string v;
    if ($value$plusargs({name, "=%s"}, v)) return v;
    return dflt;
  endfunction

  function int arg_int(string name, int dflt);
    int v;
    if ($value$plusargs({name, "=%d"}, v)) return v;
    return dflt;
  endfunction

  // A value in [lo, hi] unless +name fixes it.
  function int arg_range(string name, int lo, int hi);
    return arg_int(name, $urandom_range(hi, lo));
  endfunction

  function aou_t1_who_e who_of(string s);
    case (s)
      "apb":    return AOU_T1_BY_APB;
      "pin":    return AOU_T1_BY_PIN;
      "remote": return AOU_T1_BY_REMOTE;
      "both":   return AOU_T1_BY_BOTH;
      "rand":   return AOU_T1_BY_RANDOM;
      default:  `uvm_fatal(get_type_name(), {"unknown initiator ", s})
    endcase
    return AOU_T1_BY_RANDOM;
  endfunction

  function aou_t1_order_e order_of(string s);
    case (s)
      "dut":    return AOU_T1_DUT_FIRST;
      "remote": return AOU_T1_REMOTE_FIRST;
      "simul":  return AOU_T1_SIMULTANEOUS;
      "rand":   return AOU_T1_ORDER_RANDOM;
      default:  `uvm_fatal(get_type_name(), {"unknown order ", s})
    endcase
    return AOU_T1_ORDER_RANDOM;
  endfunction

  function aou_t1_dir_e dir_of(string s);
    case (s)
      "l2r":  return AOU_T1_L2R;
      "r2l":  return AOU_T1_R2L;
      "both": return AOU_T1_BOTH_DIRS;
      default: `uvm_fatal(get_type_name(), {"unknown direction ", s})
    endcase
    return AOU_T1_BOTH_DIRS;
  endfunction

  function aou_cred_class_e class_of(string s);
    case (s)
      "wreq":  return AOU_CC_WREQ;
      "rreq":  return AOU_CC_RREQ;
      "wdata": return AOU_CC_WDATA;
      "rdata": return AOU_CC_RDATA;
      "wresp": return AOU_CC_WRESP;
      default: `uvm_fatal(get_type_name(), {"unknown credit class ", s})
    endcase
    return AOU_CC_WREQ;
  endfunction

  // ---------------------------------------------------------------------
  // Registers, as software sees them
  // ---------------------------------------------------------------------
  task rd(uvm_reg_field f, output uvm_reg_data_t v);
    aou_reg_base_seq s = aou_reg_base_seq::type_id::create("s");
    prep_reg(s);
    s.rd_field(f, v);
  endtask

  // Writes v to f; other stored fields keep their mirrored values and W1C
  // and self-clearing fields are written 0.
  task wr(uvm_reg_field f, int v);
    aou_reg_base_seq s = aou_reg_base_seq::type_id::create("s");
    prep_reg(s);
    s.want(f, v);
    s.commit();
  endtask

  task check_field(uvm_reg_field f, uvm_reg_data_t exp, string rule, string why = "");
    uvm_reg_data_t got;
    rd(f, got);
    if (got != exp)
      `uvm_error(get_type_name(), $sformatf("%s: %s read 0x%0h, expected 0x%0h%s", rule,
                                            f.get_full_name(), got, exp,
                                            why == "" ? "" : {" (", why, ")"}))
  endtask

  // Polls f until it reads exp; poll_ok = 0 after poll_max reads.
  task poll(uvm_reg_field f, uvm_reg_data_t exp);
    uvm_reg_data_t v;
    poll_ok = 1'b0;
    repeat (poll_max) begin
      rd(f, v);
      if (v == exp) begin
        poll_ok = 1'b1;
        return;
      end
    end
  endtask

  // ---------------------------------------------------------------------
  // Remote die (L3) shortcuts
  // ---------------------------------------------------------------------
  function aou_link_state_e l3_state();
    return env.l3.model.lnk.state;
  endfunction

  // Interrupt rises seen by the status watcher so far.
  function int unsigned irq_rises(string name);
    return env.status.rises.exists(name) ? env.status.rises[name] : 0;
  endfunction

  // ---------------------------------------------------------------------
  // Activation and deactivation, checking the interrupts software relies on
  // ---------------------------------------------------------------------
  // A remote-initiated activation (deactivation) must reach software as
  // INT_ACTIVATE_START (INT_DEACTIVATE_START, MAS §7.3.5); the env's software
  // ISR answers it. Other initiators use the base task unchanged.
  task sw_activate(aou_t1_who_e who = AOU_T1_BY_RANDOM,
                   aou_t1_order_e order = AOU_T1_ORDER_RANDOM);
    int unsigned base_cnt = irq_rises("INT_ACTIVATE_START");
    // Still set from an earlier cause, the sticky interrupt cannot rise
    // again; and the software ISR may already have activated the link.
    bit pending = env.status.vif.mon_cb.int_activate_start === 1'b1 ||
                  (env.status.enabled && l3_state() == AOU_LS_ENABLED);
    who = pick_who(who);
    activate(who, order);
    if (who == AOU_T1_BY_REMOTE && !pending && irq_rises("INT_ACTIVATE_START") == base_cnt)
      `uvm_error(get_type_name(), "T1-L05: no INT_ACTIVATE_START after a remote ActivateReq")
  endtask

  task sw_deactivate(aou_t1_who_e who = AOU_T1_BY_RANDOM, bit forced = 1'b0);
    int unsigned base_cnt = irq_rises("INT_DEACTIVATE_START");
    who = pick_who(who);
    deactivate(who, forced);
    if (who == AOU_T1_BY_REMOTE && irq_rises("INT_DEACTIVATE_START") == base_cnt)
      `uvm_error(get_type_name(), "T1-L06: no INT_DEACTIVATE_START after a remote DeactivateReq")
  endtask

  // The link before an activation the test starts by hand. A deactivation
  // leaves the FDI link Active (the bringup model checks that); a link an
  // earlier event left down is brought back by the adapter.
  task ensure_link();
    if (link_is_up()) return;
    `uvm_info(get_type_name(), "link down before activation: adapter LinkReset", UVM_LOW)
    relink();
  endtask

  // ---------------------------------------------------------------------
  // LinkReset reporting (MAS §7.2.3) and recovery (§7.3.6)
  // ---------------------------------------------------------------------
  // Polls the LP_LINKRESET sticky bit `err` and checks every other source
  // stayed clear; info >= 0 is the expected INVALID_ACTMSG_INFO.
  task check_linkreset_status(string err, int info = -1);
    aou_core rm = p_sequencer.regs;
    uvm_reg_field bits[string];
    bits["act_ack_err"] = rm.lp_linkreset.act_ack_err;
    bits["deact_ack_err"] = rm.lp_linkreset.deact_ack_err;
    bits["invalid_actmsg_err"] = rm.lp_linkreset.invalid_actmsg_err;
    bits["msgcredit_err"] = rm.lp_linkreset.msgcredit_err;
    if (!bits.exists(err)) `uvm_fatal(get_type_name(), {"unknown LinkReset source ", err})
    poll(bits[err], 1);
    if (!poll_ok)
      `uvm_error(get_type_name(), $sformatf("T1-L01: LP_LINKRESET.%s not set after %0d reads",
                                            err, poll_max))
    foreach (bits[k])
      if (k != err) check_field(bits[k], 0, "T1-L02", {"only ", err, " was provoked"});
    if (info >= 0)
      check_field(rm.lp_linkreset.invalid_actmsg_info, uvm_reg_data_t'(info), "T1-L03",
                  "the offending ACTIVATIONOP");
  endtask

  // Clears a W1C LP_LINKRESET bit and checks it reads 0.
  task clear_linkreset_status(uvm_reg_field f);
    wr(f, 1);
    check_field(f, 0, "REG-R04", "after write-1-to-clear");
  endtask

  // Software's LinkReset handling (MAS §7.3.6): the adapter takes the link
  // down (`down`: LinkError, its answer to the DUT's LinkReset request, or
  // LinkReset; pl_inband_pres may also drop meanwhile); sw_reset() then
  // resets AOU_CORE while the link is in Reset, brings the link back and
  // software reprograms (the reset cleared every SFR) and activates again. Passing through
  // Reset also starts a new epoch in AOU_FDI_CHECKER, which has no other way
  // to learn that both sides forgot their activation state.
  task recover(aou_t1_feature_cfg reprogram = null, bit reactivate = 1'b1,
               aou_lsm_ev_e down = LSM_EV_LINKERROR, bit inband_drop = 1'b0);
    bit keep = cfg.lsm_cfg.rebringup_after_down;
    cfg.lsm_cfg.rebringup_after_down = 1'b0;
    link_event(down);
    if (inband_drop) link_event(LSM_EV_INBAND_DROP);
    cfg.lsm_cfg.rebringup_after_down = keep;
    sw_reset(reprogram, 1'b0);
    if (!link_is_up()) `uvm_error(get_type_name(), "T1-L04: FDI link not Active after recovery")
    // Software handles activation interrupts again once AOU_CORE is reset.
    env.sw_isr.enable = 1'b1;
    if (reactivate) sw_activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
  endtask

  // Traffic both ways that must complete with correct data.
  task check_traffic(int unsigned n = 20);
    traffic(AOU_T1_BOTH_DIRS, n);
    drain();
  endtask
endclass
