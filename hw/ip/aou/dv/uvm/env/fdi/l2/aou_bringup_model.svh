// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reference model of the DUT's FDI bringup controller, from the integrator
// guide (§3.14-3.16 encodings and pins, §6.6.2 sequence, §6.6.3
// transitions) and UCIe r1.1 §8.2-8.3 where the guide is silent (LinkError
// from any state, the clk/rx_active handshakes). step() runs once per clock
// with that clock's samples: it first checks the DUT outputs against the
// prediction from the current state, then advances the state.
//
// With fdi_enc=SPEC, pl_state_sts is decoded with UCIe values and the
// predicted lp_state_req/O_FDI_FSM_STATE use UCIe values. In Retrain the
// protocol layer must not request Retrain, and the Adapter leaves a Retrain
// entered from Active only after a NOP->Active transition on lp_state_req
// (UCIe r1.1 §8.3.3.4 and rule 1). NOP may be held as long as the protocol
// layer likes, so in Retrain the model accepts NOP, and Active once NOP has
// been seen in this Retrain.
//
// lp_linkerror (FDI-M07) follows UCIe whenever the DUT has the port
// (cfg.dut_lp_linkerror), in either encoding. A LinkError the protocol layer
// raises itself (O_AOU_REQ_LINKRESET or I_SW_LINKERROR_INJECT) must reach the
// Adapter on lp_linkerror (r1.1 Table 8-2), which moves to LinkError and
// stays there while it is 1; it is "the quickest path for error
// containment", so it must rise within ref_slack of LINKERROR entry and hold
// until the Adapter reports LinkError (or the FSM leaves LINKERROR). After
// that either value is accepted, and outside LINKERROR it must be low
// (BUGS/002). Without the port the bench ties it low: fdi_enc=SPEC still
// expects UCIe (the BUGS/002 check), fdi_enc=RTL keeps the interim
// expectation of low.
//
// Link-down exits with fdi_enc=SPEC (BUGS/001 item 4). NOP is ignored in
// Active, LinkReset, Disabled and LinkError (r1.1 Table 8-3), and nothing
// takes Active to Reset, so:
//  - LINKERROR requests Active once the Adapter has reported LinkError
//    (lp_linkerror is then low): LinkError->Reset needs Active with
//    lp_linkerror=0 (§8.3.3.7), and the guide's LINKERROR restarts by itself.
//  - DEACTIVATE takes the link down with LinkReset (Disabled is accepted
//    too, §8.3.3.8) and waits for the Adapter to report it, or Reset.
//  - LinkReset or Disabled from the Adapter (BRG_LINKDOWN) means Link
//    Status Down (Table 8-2): O_FDI_LINK_UP=0, O_FDI_FSM_STATE follows
//    pl_state_sts, lp_state_req=Active with lp_wake_req=1 to return to Reset
//    (§8.3.3.5/8.3.3.6; r3.0 wake handshake rules: leaving a clock-gated
//    state); Reset then goes through UNWAKE_WAIT.
// Requesting Active at once (rather than holding the link down until
// software acts) is the interim expectation; the spec allows either, see
// BUGS/001 (fix status, item 4).
// After LinkError/LinkReset/Disabled -> Reset the lower layers train again
// only on a NOP->Active transition (§8.3.3.8, BUGS/038), and the protocol
// layer may return to NOP afterwards. So in BRG_RESET entered from
// BRG_LINKERROR or BRG_UNWAKE_WAIT the model accepts NOP, or Active once NOP
// has been seen; the L2 driver checks that the trigger comes (FDI-R51). The
// trigger leaves Reset, so it needs the wake handshake (§8.2.3.1): either
// lp_wake_req is accepted until the trigger's Active has been seen (or
// pl_inband_pres rose with pl_wake_ack high, so the Active is skipped), and
// after that lp_wake_req must fall again (FDI-M02) while pl_wake_ack does.
// The model stays in BRG_RESET while that handshake runs, and an Active with
// pl_inband_pres already 1 is kept as the Reset->Active request
// (BRG_REQ_ACTIVE, §8.3.3.1 rule 1).
// After a deliberate teardown (DEACTIVATE, or a Disabled the Adapter
// reported: a software Link Disable) the trigger waits for an activation
// request (I_SW_ACTIVATE_START or INT_ACTIVATE_START) seen since the
// teardown began (UCIe r3.0 10.3.3.8 lets the
// protocol layer hold it back). Until then BRG_RESET predicts NOP and
// lp_wake_req=0 (FDI-M01/M02).
//
// Any other output that differs from the prediction for more than ref_slack
// cycles is an error (FDI-M01..M07). Where the guide is silent the interim
// expectations are listed in BUGS/011.
class aou_bringup_model extends uvm_object;
  `uvm_object_utils(aou_bringup_model)

  aou_lsm_cfg     cfg;
  aou_lsm_cov     cov;
  aou_brg_state_e st = BRG_RESET;
  int unsigned    n_mismatch;

  local bit          prev_clk_req;
  local bit          prev_rx_req;
  local bit          le_by_req;    // LINKERROR entered on the protocol layer's request
  local bit          le_seen;      // the Adapter has reported LinkError since
  local bit          le_raised;    // lp_linkerror has been high since
  local bit          le_fell;      // ... and has fallen before the Adapter reported LinkError
  local bit          rt_nop_seen;  // NOP on lp_state_req since Retrain entry
  local bit          rst_down;     // BRG_RESET entered after a link-down (fdi_enc=SPEC)
  local bit          rst_nop_seen; // NOP on lp_state_req since then
  local bit          rst_trig_done; // ... and the trigger's Active (or presence) since
  local bit          ld_disabled;  // BRG_LINKDOWN: the Adapter last reported Disabled
  local bit          ld_deliberate; // the link-down in progress is a deliberate teardown
  local bit          ld_act;       // ... and an activation request has come since
  local bit          rst_hold;     // BRG_RESET after it: trigger held for an activation request
  local int unsigned miss[7];

  function new(string name = "aou_bringup_model");
    super.new(name);
  endfunction

  local function bit spec();
    return cfg.fdi_enc == AOU_FDI_ENC_SPEC;
  endfunction

  function aou_lsm_req_e pred_req();
    case (st)
      BRG_REQ_ACTIVE, BRG_ACTIVE: return LSM_REQ_ACTIVE;
      BRG_RETRAIN:                return spec() ? LSM_REQ_NOP : LSM_REQ_RETRAIN;
      BRG_L1, BRG_L1_CLK_WAKE:    return LSM_REQ_L1;
      BRG_LINKERROR:              return spec() && le_seen ? LSM_REQ_ACTIVE : LSM_REQ_NOP;
      BRG_DEACTIVATE:             return spec() ? LSM_REQ_LINKRESET : LSM_REQ_NOP;
      BRG_LINKDOWN:               return LSM_REQ_ACTIVE;
      default:                    return LSM_REQ_NOP;
    endcase
  endfunction

  function bit pred_wake_req();
    return st inside {BRG_WAKE_ASSERT, BRG_WAKE_WAIT_ACK, BRG_REQ_ACTIVE, BRG_ACTIVE, BRG_RETRAIN,
                      BRG_LINKDOWN};
  endfunction

  function aou_lsm_state_e pred_fsm();
    case (st)
      BRG_ACTIVE, BRG_DEACTIVATE: return LSM_ACTIVE;
      BRG_LINKERROR:              return LSM_LINKERROR;
      BRG_RETRAIN:                return LSM_RETRAIN;
      BRG_L1, BRG_L1_CLK_WAKE:    return LSM_L1;
      BRG_LINKDOWN:               return ld_disabled ? LSM_DISABLED : LSM_LINKRESET;
      default:                    return LSM_RESET;
    endcase
  endfunction

  // Why the prediction holds, for the states BUGS/001 item 4 is about.
  local function string why();
    case (st)
      BRG_LINKERROR: return {" (Adapter reported LinkError: LinkError->Reset needs Active with ",
                             "lp_linkerror=0, NOP is ignored; UCIe r1.1 8.3.3.7, Table 8-3)"};
      BRG_DEACTIVATE: return {" (teardown from Active: NOP is ignored there, request LinkReset ",
                              "or Disabled; UCIe r1.1 Table 8-3, 8.3.3.8)"};
      BRG_LINKDOWN: return {" (Adapter in LinkReset/Disabled: Link Status is Down, Active ",
                            "returns it to Reset; UCIe r1.1 Table 8-2, 8.3.3.5-6)"};
      default: return "";
    endcase
  endfunction

  // Comparisons and mismatches per FDI-M rule, for the ledger (the L2 monitor
  // flushes them).
  int unsigned    n_cmp[string];
  int unsigned    n_bad[string];

  local function void cmp(int unsigned idx, string rule, string what, bit ok, string detail);
    if (cfg.checks_en) n_cmp[rule] = n_cmp.exists(rule) ? n_cmp[rule] + 1 : 1;
    if (ok) begin
      miss[idx] = 0;
      return;
    end
    miss[idx]++;
    if (miss[idx] == cfg.ref_slack + 1) mismatch(rule, what, detail);
  endfunction

  local function void mismatch(string rule, string what, string detail);
    n_mismatch++;
    if (cfg.checks_en) n_bad[rule] = n_bad.exists(rule) ? n_bad[rule] + 1 : 1;
    if (cfg.checks_en)
      `uvm_error(get_type_name(), $sformatf("%s: %s mismatch in %s (fdi_enc=%s): %s",
                                            rule, what, st.name(), cfg.fdi_enc.name(), detail))
  endfunction

  local function bit linkerror_per_spec();
    return cfg.dut_lp_linkerror || cfg.fdi_enc == AOU_FDI_ENC_SPEC;
  endfunction

  // A protocol-layer LinkError that ends (the Adapter reports LinkError, the
  // FSM leaves LINKERROR, or the test ends) without lp_linkerror ever high.
  local function void check_linkerror_raised();
    if (!linkerror_per_spec() || st != BRG_LINKERROR || !le_by_req || le_seen) return;
    if (cfg.checks_en) n_cmp["FDI-M07"] = n_cmp.exists("FDI-M07") ? n_cmp["FDI-M07"] + 1 : 1;
    if (!le_raised)
      mismatch("FDI-M07", "lp_linkerror",
               "DUT 0, never raised in this protocol-layer LinkError");
  endfunction

  function void final_check();
    check_linkerror_raised();
  endfunction

  function void step(aou_lsm_obs o);
    bit ok;
    bit activate;
    bit ld_act_n;
    logic [3:0] fsm_code;
    aou_brg_state_e nxt;
    if (!o.rst_n) begin
      st = BRG_RESET;
      foreach (miss[i]) miss[i] = 0;
      prev_clk_req = 1'b0;
      prev_rx_req = 1'b0;
      le_by_req = 1'b0;
      le_seen = 1'b0;
      le_raised = 1'b0;
      le_fell = 1'b0;
      rt_nop_seen = 1'b0;
      rst_down = 1'b0;
      rst_nop_seen = 1'b0;
      rst_trig_done = 1'b0;
      ld_disabled = 1'b0;
      ld_deliberate = 1'b0;
      ld_act = 1'b0;
      rst_hold = 1'b0;
      return;
    end

    fsm_code = sts_code(pred_fsm(), cfg.fdi_enc, ok);
    if (st == BRG_RETRAIN && cfg.fdi_enc == AOU_FDI_ENC_SPEC) begin
      if (o.lp_state_req == req_code(LSM_REQ_NOP, cfg.fdi_enc)) rt_nop_seen = 1'b1;
      cmp(0, "FDI-M01", "lp_state_req", o.lp_state_req == req_code(LSM_REQ_NOP, cfg.fdi_enc) ||
          (rt_nop_seen && o.lp_state_req == req_code(LSM_REQ_ACTIVE, cfg.fdi_enc)),
          $sformatf("DUT 0x%0h, expected LSM_REQ_NOP, or LSM_REQ_ACTIVE after NOP",
                    o.lp_state_req));
    end else if (st == BRG_RESET && rst_down && rst_hold) begin
      cmp(0, "FDI-M01", "lp_state_req", o.lp_state_req == req_code(LSM_REQ_NOP, cfg.fdi_enc),
          $sformatf({"DUT 0x%0h, expected LSM_REQ_NOP (deliberate link-down: the training ",
                     "trigger waits for an activation request, UCIe r3.0 10.3.3.8)"},
                    o.lp_state_req));
    end else if (st == BRG_RESET && rst_down) begin
      if (o.lp_state_req == req_code(LSM_REQ_NOP, cfg.fdi_enc)) rst_nop_seen = 1'b1;
      cmp(0, "FDI-M01", "lp_state_req", o.lp_state_req == req_code(LSM_REQ_NOP, cfg.fdi_enc) ||
          (rst_nop_seen && o.lp_state_req == req_code(LSM_REQ_ACTIVE, cfg.fdi_enc)),
          $sformatf({"DUT 0x%0h, expected LSM_REQ_NOP, or LSM_REQ_ACTIVE after NOP (training ",
                     "trigger after a link-down, UCIe r1.1 8.3.3.8)"}, o.lp_state_req));
    end else if (st == BRG_DEACTIVATE && spec()) begin
      cmp(0, "FDI-M01", "lp_state_req", o.req inside {LSM_REQ_LINKRESET, LSM_REQ_DISABLED},
          $sformatf("DUT 0x%0h, expected LSM_REQ_LINKRESET or LSM_REQ_DISABLED%s",
                    o.lp_state_req, why()));
    end else begin
      cmp(0, "FDI-M01", "lp_state_req", o.lp_state_req == req_code(pred_req(), cfg.fdi_enc),
          $sformatf("DUT 0x%0h, expected %s%s", o.lp_state_req, pred_req().name(), why()));
    end
    // Leaving Active needs no wake handshake, so DEACTIVATE may hold either
    // value; LINKDOWN needs it (pred_wake_req).
    // The training trigger after a link-down needs the wake handshake, but
    // only until its Active.
    if ((st == BRG_DEACTIVATE && spec()) ||
        (st == BRG_RESET && rst_down && !rst_hold && !rst_trig_done))
      miss[1] = 0;
    else if (st == BRG_RESET && rst_down)
      cmp(1, "FDI-M02", "lp_wake_req", !o.wake_req,
          $sformatf({"DUT %0b, expected 0 %s (UCIe r1.1 8.3.3.8)"}, o.wake_req,
                    rst_hold ? "while the training trigger waits for an activation request"
                             : "once the training trigger after a link-down has been given"));
    else cmp(1, "FDI-M02", "lp_wake_req", o.wake_req == pred_wake_req(),
             $sformatf("DUT %0b%s", o.wake_req, why()));
    cmp(2, "FDI-M03", "lp_clk_ack", o.clk_ack == prev_clk_req, $sformatf("DUT %0b", o.clk_ack));
    cmp(3, "FDI-M04", "lp_rx_active_sts",
        o.rx_active_sts == (prev_rx_req && !(st inside {BRG_RESET, BRG_LINKERROR})),
        $sformatf("DUT %0b", o.rx_active_sts));
    cmp(4, "FDI-M05", "O_FDI_FSM_STATE", o.fsm_state == fsm_code,
        $sformatf("DUT 0x%0h, expected 0x%0h (%s)", o.fsm_state, fsm_code, pred_fsm().name()));
    cmp(5, "FDI-M06", "O_FDI_LINK_UP", o.link_up == (st == BRG_ACTIVE),
        $sformatf("DUT %0b%s", o.link_up, why()));
    if (!linkerror_per_spec()) begin
      cmp(6, "FDI-M07", "lp_linkerror", (st == BRG_LINKERROR && le_seen) || !o.linkerror,
          $sformatf("DUT %0b", o.linkerror));
    end else if (st != BRG_LINKERROR) begin
      cmp(6, "FDI-M07", "lp_linkerror", !o.linkerror, $sformatf("DUT %0b", o.linkerror));
    end else if (le_by_req && !le_seen) begin
      // Rises within ref_slack of LINKERROR entry; once high it holds until
      // the Adapter reports LinkError (the Adapter LSM follows RDI there).
      if (!le_raised) begin
        cmp(6, "FDI-M07", "lp_linkerror", o.linkerror,
            {"DUT 0, not raised within ref_slack of this protocol-layer LinkError ",
             "(UCIe r1.1 Table 8-2)"});
      end else if (!o.linkerror && !le_fell) begin
        if (cfg.checks_en) n_cmp["FDI-M07"] = n_cmp.exists("FDI-M07") ? n_cmp["FDI-M07"] + 1 : 1;
        mismatch("FDI-M07", "lp_linkerror",
                 "DUT 0, fell before the Adapter reported LinkError (UCIe r1.1 Table 8-2)");
        le_fell = 1'b1;
      end
    end else begin
      miss[6] = 0;
    end
    if (st == BRG_LINKERROR && o.linkerror) le_raised = 1'b1;

    nxt = next_state(o);
    if (nxt != BRG_LINKERROR || o.sts == LSM_LINKERROR) check_linkerror_raised();
    if (nxt == BRG_LINKERROR && st != BRG_LINKERROR) begin
      le_by_req = o.sts != LSM_LINKERROR;
      le_seen = 1'b0;
      le_raised = 1'b0;
      le_fell = 1'b0;
    end
    if (nxt == BRG_LINKERROR && o.sts == LSM_LINKERROR) le_seen = 1'b1;
    if (nxt == BRG_RETRAIN && st != BRG_RETRAIN) rt_nop_seen = 1'b0;
    if (nxt != BRG_RESET) rst_down = 1'b0;
    else if (st != BRG_RESET) rst_down = spec() && st inside {BRG_LINKERROR, BRG_UNWAKE_WAIT};
    if (nxt == BRG_RESET && st != BRG_RESET) rst_nop_seen = 1'b0;
    // Deliberate teardowns (the guide's restart rule).
    activate = o.sw_activate || o.int_activate;
    ld_act_n = ld_deliberate && (ld_act || activate);
    if (nxt != BRG_RESET) rst_hold = 1'b0;
    else if (st != BRG_RESET)
      rst_hold = spec() && st == BRG_UNWAKE_WAIT && ld_deliberate && !ld_act && !activate;
    else if (activate) rst_hold = 1'b0;
    if (nxt == BRG_LINKERROR || (st == BRG_RESET && nxt != BRG_RESET) ||
        (nxt == BRG_LINKDOWN && !(st inside {BRG_LINKDOWN, BRG_DEACTIVATE}) &&
         o.sts != LSM_DISABLED))
      ld_deliberate = 1'b0;
    else if (nxt == BRG_DEACTIVATE || (spec() && o.sts == LSM_DISABLED)) ld_deliberate = 1'b1;
    ld_act = ld_act_n;
    if (st == BRG_RESET && rst_down &&
        ((rst_nop_seen && o.lp_state_req == req_code(LSM_REQ_ACTIVE, cfg.fdi_enc)) ||
         (o.wake_ack && o.inband_pres)))
      rst_trig_done = 1'b1;
    if (nxt != BRG_RESET || st != BRG_RESET) rst_trig_done = 1'b0;
    if (o.sts inside {LSM_LINKRESET, LSM_DISABLED}) ld_disabled = o.sts == LSM_DISABLED;
    if (nxt != st) begin
      `uvm_info(get_type_name(), $sformatf("%s -> %s", st.name(), nxt.name()), UVM_MEDIUM)
      if (cov != null) cov.sample_brg(st, nxt);
    end
    st = nxt;
    prev_clk_req = o.clk_req;
    prev_rx_req = o.rx_active_req;
  endfunction

  local function aou_brg_state_e next_state(aou_lsm_obs o);
    bit pl_reset = o.sts == LSM_RESET;
    bit pl_active = o.sts == LSM_ACTIVE;
    bit pl_linkerror = o.sts == LSM_LINKERROR;
    bit activate = o.sw_activate || o.int_activate;
    bit deactivate = o.sw_deactivate || o.int_deactivate;
    bit linkerror_req = o.req_linkreset || o.sw_linkerror;
    bit pl_linkdown = spec() && o.sts inside {LSM_LINKRESET, LSM_DISABLED};
    if (pl_linkerror && st != BRG_LINKERROR) return BRG_LINKERROR;
    if (pl_linkdown && !(st inside {BRG_LINKERROR, BRG_LINKDOWN}) &&
        !(st == BRG_ACTIVE && linkerror_req))
      return BRG_LINKDOWN;
    case (st)
      BRG_RESET:         begin
        if (rst_down && rst_nop_seen && pl_reset && o.inband_pres &&
            o.lp_state_req == req_code(LSM_REQ_ACTIVE, cfg.fdi_enc))
          return BRG_REQ_ACTIVE;
        if (rst_down && (o.wake_req || o.wake_ack)) return BRG_RESET;
        if (pl_reset && o.inband_pres) return BRG_WAIT_PRESENCE;
      end
      BRG_WAIT_PRESENCE: begin
        if (activate || o.clk_req) return BRG_WAKE_ASSERT;
        if (!o.inband_pres) return BRG_RESET;
      end
      BRG_WAKE_ASSERT:   return BRG_WAKE_WAIT_ACK;
      BRG_WAKE_WAIT_ACK: begin
        if (o.wake_ack) return BRG_REQ_ACTIVE;
        if (!o.inband_pres && pl_reset) return BRG_RESET;
      end
      BRG_REQ_ACTIVE:    begin
        if (pl_active && o.rx_active_req) return BRG_ACTIVE;
        if (!o.inband_pres && pl_reset) return BRG_RESET;
      end
      BRG_ACTIVE:        begin
        if (linkerror_req) return BRG_LINKERROR;
        if (o.sts == LSM_RETRAIN || o.sw_retrain) return BRG_RETRAIN;
        if (deactivate && o.act_st_disabled) return BRG_DEACTIVATE;
        if (o.sts == LSM_L1) return BRG_L1;
        if (pl_reset) return BRG_RESET;
      end
      BRG_LINKERROR:     if (pl_reset) return BRG_RESET;
      BRG_RETRAIN:       if (pl_active) return BRG_ACTIVE;
      BRG_DEACTIVATE:    if (!spec() || pl_reset) return BRG_UNWAKE_WAIT;
      BRG_LINKDOWN:      if (pl_reset) return BRG_UNWAKE_WAIT;
      BRG_UNWAKE_WAIT:   if (!o.wake_ack && pl_reset) return BRG_RESET;
      BRG_L1:            begin
        if (o.clk_req) return BRG_L1_CLK_WAKE;
        if (activate) return BRG_WAKE_ASSERT;
        if (pl_reset) return BRG_RESET;
      end
      BRG_L1_CLK_WAKE:   return BRG_WAKE_ASSERT;
      default:           return BRG_RESET;
    endcase
    return st;
  endfunction
endclass
