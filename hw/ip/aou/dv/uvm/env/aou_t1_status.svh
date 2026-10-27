// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Interrupt and activation-status watcher (aou_irq_if, config_db key "irq").
// Every rising edge of an error interrupt is a UVM_ERROR "<INT name>: ...",
// which the expectation registry demotes when a test declared it.
// INT_ACTIVATE_START / INT_DEACTIVATE_START belong to normal activation and
// are only counted, as is INT_EARLY_WDT_ERR, which aou_t1_wdt_chk judges.
// INT_FDI_LINK_DOWN (the FDI link lost while AoU was ACTIVATE, ENABLED or
// DEACTIVATE) is an error interrupt a link-event test declares; on its rise
// the DUT must also report DISABLED within LINK_DOWN_DISABLE_CYCLES without
// any handshake (T1-L48, AoU v0.8 8.3.3 ERROR -> DISABLED).
// An orderly deactivation ends in DISABLED only once both DeactivateAcks have
// crossed (AOU-R37, AoU v0.8 8.4 DEACTIVATE). The DUT may report DISABLED
// only after the remote die has sent its DeactivateAck: when the DUT turns
// DISABLED while the remote die, in DEACTIVATE, has sent its DeactivateReq and
// received the DUT's DeactivateAck but not sent its own Ack, and no LinkReset
// request, link loss or reset explains it within ABORT_CYCLES, the DUT went
// DISABLED early. An error abort needs no handshake and is invisible with a
// LinkReset cause masked (AOU_INTERRUPT_MASK, from the register mirror), so
// the check is off while any is. It judges legal traffic only: after the
// remote die sent an injected DeactivateAck in ENABLED, which no compliant
// peer sends and the spec does not define, the DUT may legitimately take that
// Ack as the remote die's, so the check stands down for the next deactivation
// (until the remote die reaches DISABLED, or a reset).
// Cost: one comparison per DISABLED entry.
// Coverage (cg_stray_dack) records how the DUT handled such a stray
// DeactivateAck. Acceptable is either that the stray is absorbed and the link
// keeps working, or that it ends in a reported error (LinkReset or interrupt)
// followed by the documented recovery; no hang, no silent corruption or
// misdelivery, no unreported divergence from the peer (the scoreboard and the
// remote die's own checks still judge that). The bins tell which the DUT does:
// flagged_on_arrival (INT_REQ_LINKRESET or INT_FDI_LINK_DOWN rises while the
// remote die is still ENABLED, the detect option of AoU v0.8 8.3.3),
// error_at_deact (it rises during the next deactivation, or within
// REACT_CYCLES of its end: the remote die DISABLED with nothing left to send),
// ignored (neither). The window closes there, so a later error the test
// provokes is not counted; a reset before then, or a LinkReset cause masked,
// records nothing. Cost: a few comparisons per cycle while a window is open.
typedef class aou_t1_l1_pump_seq;

class aou_t1_status extends uvm_component;
  `uvm_component_utils(aou_t1_status)

  localparam int N_INT = 8;
  localparam int unsigned LINK_DOWN_DISABLE_CYCLES = 8;
  localparam int unsigned ABORT_CYCLES = 4;
  // Cycles after the remote die's TX toward the DUT empties within which the
  // DUT must have reacted to the last activation message it received.
  localparam int unsigned REACT_CYCLES = 64;

  virtual aou_irq_if vif;
  aou_l3_model       model;       // the remote die, for AOU-R37 (null: not checked)
  aou_core           rm;          // register mirror, for AOU-R37's mask condition
  aou_t1_l1_pump_seq pump;        // L3 -> L1 flits, for remote_tx_idle() (null: none)
  bit                checks_en = 1'b1;
  int unsigned       rises[string];
  bit                enabled;     // O_AOU_ACTIVATE_ST_ENABLED, sampled
  bit                disabled;    // O_AOU_ACTIVATE_ST_DISABLED, sampled
  int unsigned       n_enabled;   // entries into ENABLED, so a waiter that samples
  int unsigned       n_disabled;  // the level late still sees a short visit
  uvm_event          state_ev;
  bit                act_ok;      // result of wait_act_state()
  uvm_event          act_start_ev;    // INT_ACTIVATE_START rose
  uvm_event          deact_start_ev;  // INT_DEACTIVATE_START rose
  uvm_event          mi0_id_mismatch_ev;  // INT_MI0_ID_MISMATCH rose
  uvm_event          link_down_ev;    // INT_FDI_LINK_DOWN rose

  protected bit          stray_open;      // a stray DeactivateAck awaits its outcome
  protected bit          stray_prev;      // model.lnk.stray_dack_enabled last cycle
  protected int unsigned stray_lr0, stray_ld0, stray_idle;
  int unsigned s_outcome;
  covergroup cg_stray_dack;
    cp_outcome: coverpoint s_outcome {
      `AOU_T1_STRAY_FC_OUTCOME(AOU_FC_CG)
    }
  endgroup
  aou_fc_group fc_stray_dack;

  function new(string name, uvm_component parent);
    aou_fc_db db;
    aou_fc_point p;
    bit fresh;
    super.new(name, parent);
    cg_stray_dack = new();
    db = aou_fc_db::get();
    fc_stray_dack = db.group("env.cg_stray_dack", fresh);
    if (fresh) begin
      p = fc_stray_dack.cp("cp_outcome"); `AOU_T1_STRAY_FC_OUTCOME(AOU_FC_REG)
    end
    state_ev = new("state_ev");
    act_start_ev = new("act_start_ev");
    deact_start_ev = new("deact_start_ev");
    mi0_id_mismatch_ev = new("mi0_id_mismatch_ev");
    link_down_ev = new("link_down_ev");
  endfunction

  static function string int_name(int unsigned i);
    case (i)
      0: return "INT_REQ_LINKRESET";
      1: return "INT_SI0_ID_MISMATCH";
      2: return "INT_MI0_ID_MISMATCH";
      3: return "INT_EARLY_RESP_ERR";
      4: return "INT_ACTIVATE_START";
      5: return "INT_DEACTIVATE_START";
      6: return "INT_FDI_LINK_DOWN";
      default: return "INT_EARLY_WDT_ERR";
    endcase
  endfunction

  static function bit is_error(int unsigned i);
    return i < 4 || i == 6;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual aou_irq_if)::get(this, "", "irq", vif))
      `uvm_fatal(get_type_name(), "no aou_irq_if under config_db key irq")
    for (int unsigned i = 0; i < N_INT; i++) rises[int_name(i)] = 0;
  endfunction

  function bit [N_INT-1:0] sample();
    return {vif.mon_cb.int_early_wdt_err, vif.mon_cb.int_fdi_link_down,
            vif.mon_cb.int_deactivate_start, vif.mon_cb.int_activate_start,
            vif.mon_cb.int_early_resp_err, vif.mon_cb.int_mi0_id_mismatch,
            vif.mon_cb.int_si0_id_mismatch, vif.mon_cb.int_req_linkreset};
  endfunction

  // The DUT disables itself on a link loss: ACTIVATE_STATE_DISABLED within
  // LINK_DOWN_DISABLE_CYCLES of INT_FDI_LINK_DOWN, and no activation message
  // in between (the link is down, so none can be exchanged).
  task check_link_down_disable();
    int unsigned n = 0;
    while (vif.mon_cb.act_st_disabled !== 1'b1) begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) return;
      if (++n >= LINK_DOWN_DISABLE_CYCLES) begin
        `uvm_error(get_type_name(), $sformatf(
                   "T1-L48: not DISABLED within %0d cycles of INT_FDI_LINK_DOWN", n))
        return;
      end
    end
  endtask

  // AOU-R37 at a DISABLED entry: the remote die's view at that moment, judged
  // after ABORT_CYCLES so an error abort (which needs no handshake) is excused.
  task check_deact_handshake();
    aou_link_ctrl l;
    int unsigned lr0, ld0;
    if (model == null || model.lnk == null) return;
    l = model.lnk;
    if (l.stray_dack_enabled || linkreset_masked()) return;
    aou_rule_log::check("AOU-R37", get_type_name());
    if (!(l.state == AOU_LS_DEACTIVATE && l.dreq_sent && l.dack_rcvd && !l.dack_sent)) return;
    lr0 = rises["INT_REQ_LINKRESET"];
    ld0 = rises["INT_FDI_LINK_DOWN"];
    repeat (ABORT_CYCLES) begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) return;
    end
    if (rises["INT_REQ_LINKRESET"] != lr0 || rises["INT_FDI_LINK_DOWN"] != ld0 ||
        l.state == AOU_LS_ERROR)
      return;
    aou_rule_log::fire("AOU-R37", get_type_name());
    `uvm_error(get_type_name(), {"AOU-R37: DUT DISABLED before the remote die sent its ",
                                 "DeactivateAck (no error or link loss)"})
  endtask

  protected function bit linkreset_masked();
    uvm_reg_field f[$];
    if (rm == null) return 1'b1;
    f = '{rm.aou_interrupt_mask.int_req_linkreset_msgcredit_timeout_mask,
          rm.aou_interrupt_mask.int_req_linkreset_invalid_actmsg_mask,
          rm.aou_interrupt_mask.int_req_linkreset_deact_ack_mask,
          rm.aou_interrupt_mask.int_req_linkreset_act_ack_mask,
          rm.aou_interrupt_mask.int_fdi_link_down_mask};
    foreach (f[i]) if (f[i].get_mirrored_value() != 0) return 1'b1;
    return 1'b0;
  endfunction

  // The remote die has nothing more for the DUT: no activation message or
  // other work queued, and no flit still being driven on the FDI.
  function bit remote_tx_idle();
    if (model == null || model.lnk == null) return 1'b1;
    return model.lnk.out_q.size() == 0 && !model.pk.has_work() &&
           (pump == null || !pump.busy);
  endfunction

  // cg_stray_dack outcome (AOU_T1_STRAY_FC_OUTCOME): 0 ignored,
  // 1 flagged_on_arrival, 2 error_at_deact.
  protected function void judge_stray(int unsigned outcome);
    string nm[3] = '{"ignored", "flagged on arrival", "error at the next deactivation"};
    stray_open = 1'b0;
    if (linkreset_masked()) return;
    s_outcome = outcome;
    cg_stray_dack.sample();
    fc_stray_dack.sample(int'(outcome));
    `uvm_info(get_type_name(), {"injected DeactivateAck in ENABLED: ", nm[outcome]}, UVM_LOW)
  endfunction

  protected function void track_stray();
    bit now;
    if (model == null || model.lnk == null) return;
    now = model.lnk.stray_dack_enabled;
    if (now && !stray_prev) begin
      stray_open = 1'b1;
      stray_lr0 = rises["INT_REQ_LINKRESET"];
      stray_ld0 = rises["INT_FDI_LINK_DOWN"];
      stray_idle = 0;
    end
    stray_prev = now;
    if (!stray_open) return;
    if (rises["INT_REQ_LINKRESET"] != stray_lr0 || rises["INT_FDI_LINK_DOWN"] != stray_ld0)
      judge_stray(model.lnk.state == AOU_LS_ENABLED ? 1 : 2);
    else if (model.lnk.state == AOU_LS_DISABLED && remote_tx_idle()) begin
      if (++stray_idle >= REACT_CYCLES) judge_stray(0);
    end else
      stray_idle = 0;
  endfunction

  task run_phase(uvm_phase phase);
    bit [N_INT-1:0] prev = '0;
    forever begin
      bit [N_INT-1:0] cur;
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) begin
        prev = '0;
        continue;
      end
      if (vif.mon_cb.act_st_enabled !== enabled || vif.mon_cb.act_st_disabled !== disabled) begin
        if (vif.mon_cb.act_st_enabled === 1'b1 && !enabled) n_enabled++;
        if (vif.mon_cb.act_st_disabled === 1'b1 && !disabled) begin
          n_disabled++;
          fork
            check_deact_handshake();
          join_none
        end
        enabled = vif.mon_cb.act_st_enabled === 1'b1;
        disabled = vif.mon_cb.act_st_disabled === 1'b1;
        state_ev.trigger();
      end
      cur = sample();
      for (int unsigned i = 0; i < N_INT; i++) begin
        if (cur[i] && !prev[i]) begin
          rises[int_name(i)]++;
          if (i == 4) act_start_ev.trigger();
          if (i == 5) deact_start_ev.trigger();
          if (i == 2) mi0_id_mismatch_ev.trigger();
          if (i == 6) begin
            link_down_ev.trigger();
            fork
              check_link_down_disable();
            join_none
          end
          if (is_error(i) && checks_en)
            `uvm_error(get_type_name(), $sformatf("%s: interrupt asserted", int_name(i)))
          else
            `uvm_info(get_type_name(), $sformatf("%s asserted", int_name(i)), UVM_MEDIUM)
        end
      end
      prev = cur;
      track_stray();
    end
  endtask

  // Waits until the DUT reports ENABLED (en=1) or DISABLED (en=0); act_ok = 0
  // on time-out.
  task wait_act_state(bit en, int unsigned timeout);
    int unsigned n = 0;
    act_ok = 1'b1;
    while ((en ? enabled : disabled) != 1'b1) begin
      @(vif.mon_cb);
      if (++n >= timeout) begin
        act_ok = 1'b0;
        return;
      end
    end
  endtask

  function void reset_flush();
    enabled = 1'b0;
    disabled = 1'b0;
    stray_open = 1'b0;
  endfunction

  function void report_phase(uvm_phase phase);
    string s = "";
    super.report_phase(phase);
    foreach (rises[k]) s = {s, $sformatf(" %s=%0d", k, rises[k])};
    `uvm_info(get_type_name(), {"interrupt rises:", s}, UVM_LOW)
  endfunction
endclass
