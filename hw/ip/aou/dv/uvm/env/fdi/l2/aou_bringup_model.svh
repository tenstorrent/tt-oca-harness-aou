// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reference model of the DUT's FDI bringup controller, from the integrator
// guide (§3.14-3.16 encodings and pins, §6.6.2 sequence, §6.6.3
// transitions) and UCIe r1.1 §8.2-8.3 where the guide is silent (LinkError
// from any state, the clk/rx_active handshakes). step() runs once per clock
// with that clock's samples: it first checks the DUT outputs against the
// prediction from the current state, then advances the state.
//
// pl_state_sts, lp_state_req and O_FDI_FSM_STATE carry UCIe values. In
// Retrain the protocol layer must not request Retrain, and the Adapter leaves
// a Retrain entered from Active only after a NOP->Active transition on
// lp_state_req (UCIe r1.1 §8.3.3.4 and rule 1). NOP may be held as long as the
// protocol layer likes, so in Retrain the model accepts NOP, and Active once
// NOP has been seen in this Retrain.
//
// lp_linkerror (FDI-M07): a LinkError the protocol layer raises itself
// (O_AOU_REQ_LINKRESET or I_SW_LINKERROR_INJECT) must reach the Adapter on
// lp_linkerror (r1.1 Table 8-2), which moves to LinkError and stays there while
// it is 1; it is "the quickest path for error containment", so it must rise within ref_slack of LINKERROR entry and hold
// until the Adapter reports LinkError (or the FSM leaves LINKERROR). After
// that either value is accepted, and outside LINKERROR it must be low.
//
// The link is taken down and restarted by software on the UCIe controller,
// never by this IP (integrator guide §6.6.2 "After a link-down"):
//  - an AoU deactivation leaves the FDI link alone: the FSM stays ACTIVE and
//    O_FDI_LINK_UP stays 1;
//  - LinkError holds the link down until software has applied
//    AOU_CON0.AOU_SW_RESET (guide §6.6.3, MAS §7.3.6): a LinkError can
//    interrupt a flit in either direction and only that reset clears the
//    DUT's data-path position. So BRG_LINKERROR leaves for BRG_RESET only
//    once the Adapter reports Reset and a software reset has been seen since
//    the LinkError began (either order), and requests nothing meanwhile (NOP;
//    the Adapter leaves LinkError on its own, §8.3.3.7);
//  - LinkReset or Disabled from the Adapter (BRG_LINKDOWN)
//    means Link Status Down (Table 8-2): O_FDI_LINK_UP=0, O_FDI_FSM_STATE
//    follows pl_state_sts, lp_state_req=NOP and lp_wake_req=0 until the
//    Adapter reports Reset;
//  - in BRG_RESET the request is NOP whatever the state was entered from:
//    the training trigger after a link-down (§8.3.3.8) is software's or the
//    remote die's, and the FSM leaves Reset as after a cold reset, on
//    pl_inband_pres and then an activation request or pl_clk_req.
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
  local bit          prev_rx_sts;  // the DUT's lp_rx_active_sts last cycle
  local bit          le_by_req;    // LINKERROR entered on the protocol layer's request
  local bit          le_seen;      // the Adapter has reported LinkError since
  local bit          le_raised;    // lp_linkerror has been high since
  local bit          le_fell;      // ... and has fallen before the Adapter reported LinkError
  local bit          le_sw_reset;  // a software reset has been seen since LINKERROR entry
  local bit          rt_nop_seen;  // NOP on lp_state_req since Retrain entry
  local bit          ld_disabled;  // BRG_LINKDOWN: the Adapter last reported Disabled
  local int unsigned miss[7];

  function new(string name = "aou_bringup_model");
    super.new(name);
  endfunction

  function aou_lsm_req_e pred_req();
    case (st)
      BRG_REQ_ACTIVE, BRG_ACTIVE: return LSM_REQ_ACTIVE;
      BRG_L1, BRG_L1_CLK_WAKE:    return LSM_REQ_L1;
      default:                    return LSM_REQ_NOP;
    endcase
  endfunction

  function bit pred_wake_req();
    return st inside {BRG_WAKE_ASSERT, BRG_WAKE_WAIT_ACK, BRG_REQ_ACTIVE, BRG_ACTIVE, BRG_RETRAIN};
  endfunction

  function aou_lsm_state_e pred_fsm();
    case (st)
      BRG_ACTIVE:              return LSM_ACTIVE;
      BRG_LINKERROR:           return LSM_LINKERROR;
      BRG_RETRAIN:             return LSM_RETRAIN;
      BRG_L1, BRG_L1_CLK_WAKE: return LSM_L1;
      BRG_LINKDOWN:            return ld_disabled ? LSM_DISABLED : LSM_LINKRESET;
      default:                 return LSM_RESET;
    endcase
  endfunction

  // Why the prediction holds, for the link-down states.
  local function string why();
    case (st)
      BRG_LINKERROR: return {" (held down after a LinkError until AOU_SW_RESET, requesting ",
                             "nothing: the restart is software's; guide 6.6.2-6.6.3, MAS 7.3.6)"};
      BRG_LINKDOWN:  return {" (Adapter in LinkReset/Disabled: Link Status is Down and the IP ",
                             "requests nothing; UCIe r1.1 Table 8-2, guide 6.6.2)"};
      default:       return "";
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
      `uvm_error(get_type_name(), $sformatf("%s: %s mismatch in %s: %s", rule, what, st.name(),
                                            detail))
  endfunction

  // A protocol-layer LinkError that ends (the Adapter reports LinkError, the
  // FSM leaves LINKERROR, or the test ends) without lp_linkerror ever high.
  local function void check_linkerror_raised();
    if (st != BRG_LINKERROR || !le_by_req || le_seen) return;
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
    bit rx_sts_exp;
    logic [3:0] fsm_code;
    aou_brg_state_e nxt;
    if (!o.rst_n) begin
      st = BRG_RESET;
      foreach (miss[i]) miss[i] = 0;
      prev_clk_req = 1'b0;
      prev_rx_req = 1'b0;
      prev_rx_sts = 1'b0;
      le_by_req = 1'b0;
      le_seen = 1'b0;
      le_raised = 1'b0;
      le_fell = 1'b0;
      le_sw_reset = 1'b0;
      rt_nop_seen = 1'b0;
      ld_disabled = 1'b0;
      return;
    end

    fsm_code = sts_code(pred_fsm(), ok);
    if (st == BRG_RETRAIN) begin
      if (o.lp_state_req == req_code(LSM_REQ_NOP)) rt_nop_seen = 1'b1;
      cmp(0, "FDI-M01", "lp_state_req", o.lp_state_req == req_code(LSM_REQ_NOP) ||
          (rt_nop_seen && o.lp_state_req == req_code(LSM_REQ_ACTIVE)),
          $sformatf("DUT 0x%0h, expected LSM_REQ_NOP, or LSM_REQ_ACTIVE after NOP",
                    o.lp_state_req));
    end else begin
      cmp(0, "FDI-M01", "lp_state_req", o.lp_state_req == req_code(pred_req()),
          $sformatf("DUT 0x%0h, expected %s%s", o.lp_state_req, pred_req().name(), why()));
    end
    cmp(1, "FDI-M02", "lp_wake_req", o.wake_req == pred_wake_req(),
        $sformatf("DUT %0b%s", o.wake_req, why()));
    cmp(2, "FDI-M03", "lp_clk_ack", o.clk_ack == prev_clk_req, $sformatf("DUT %0b", o.clk_ack));
    // lp_rx_active_sts rises on pl_rx_active_req outside Reset/LinkError and,
    // once high, falls only after the request has (UCIe r1.1 8.2.7), whatever
    // the state. A drop while the request is still high is wrong in the cycle
    // it happens: no ref_slack allowance, since a one-cycle glitch would hide
    // under it, and FDI-R28 in the monitor only catches late drops.
    rx_sts_exp = prev_rx_req && (prev_rx_sts || !(st inside {BRG_RESET, BRG_LINKERROR}));
    if (prev_rx_sts && prev_rx_req && !o.rx_active_sts) begin
      if (cfg.checks_en) n_cmp["FDI-M04"] = n_cmp.exists("FDI-M04") ? n_cmp["FDI-M04"] + 1 : 1;
      mismatch("FDI-M04", "lp_rx_active_sts",
               "DUT 0, fell while pl_rx_active_req is still high (UCIe r1.1 8.2.7)");
    end else begin
      cmp(3, "FDI-M04", "lp_rx_active_sts", o.rx_active_sts == rx_sts_exp,
          $sformatf("DUT %0b, expected %0b", o.rx_active_sts, rx_sts_exp));
    end
    cmp(4, "FDI-M05", "O_FDI_FSM_STATE", o.fsm_state == fsm_code,
        $sformatf("DUT 0x%0h, expected 0x%0h (%s)", o.fsm_state, fsm_code, pred_fsm().name()));
    cmp(5, "FDI-M06", "O_FDI_LINK_UP", o.link_up == (st == BRG_ACTIVE),
        $sformatf("DUT %0b%s", o.link_up, why()));
    if (st != BRG_LINKERROR) begin
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
    // The DUT registers the software reset it sees in LINKERROR and leaves on
    // the registered flag, so the reset counts from the next clock.
    if (st == BRG_LINKERROR && o.sw_reset) le_sw_reset = 1'b1;
    if (nxt == BRG_LINKERROR && st != BRG_LINKERROR) begin
      le_by_req = o.sts != LSM_LINKERROR;
      le_seen = 1'b0;
      le_raised = 1'b0;
      le_fell = 1'b0;
      le_sw_reset = 1'b0;
    end
    if (nxt == BRG_LINKERROR && o.sts == LSM_LINKERROR) le_seen = 1'b1;
    if (nxt == BRG_RETRAIN && st != BRG_RETRAIN) rt_nop_seen = 1'b0;
    if (o.sts inside {LSM_LINKRESET, LSM_DISABLED}) ld_disabled = o.sts == LSM_DISABLED;
    if (nxt != st) begin
      `uvm_info(get_type_name(), $sformatf("%s -> %s", st.name(), nxt.name()), UVM_MEDIUM)
      if (cov != null) cov.sample_brg(st, nxt);
    end
    st = nxt;
    prev_clk_req = o.clk_req;
    prev_rx_req = o.rx_active_req;
    prev_rx_sts = o.rx_active_sts;
  endfunction

  local function aou_brg_state_e next_state(aou_lsm_obs o);
    bit pl_reset = o.sts == LSM_RESET;
    bit pl_active = o.sts == LSM_ACTIVE;
    bit pl_linkerror = o.sts == LSM_LINKERROR;
    bit activate = o.sw_activate || o.int_activate;
    bit linkerror_req = o.req_linkreset || o.sw_linkerror;
    bit pl_linkdown = o.sts inside {LSM_LINKRESET, LSM_DISABLED};
    if (pl_linkerror && st != BRG_LINKERROR) return BRG_LINKERROR;
    if (pl_linkdown && !(st inside {BRG_LINKERROR, BRG_LINKDOWN}) &&
        !(st inside {BRG_ACTIVE, BRG_RETRAIN} && linkerror_req))
      return BRG_LINKDOWN;
    case (st)
      BRG_RESET:         if (pl_reset && o.inband_pres) return BRG_WAIT_PRESENCE;
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
        if (o.sts == LSM_RETRAIN) return BRG_RETRAIN;
        if (o.sts == LSM_L1) return BRG_L1;
        if (pl_reset) return BRG_RESET;
      end
      BRG_LINKERROR:     if (pl_reset && le_sw_reset) return BRG_RESET;
      BRG_RETRAIN:       begin
        if (linkerror_req) return BRG_LINKERROR;
        if (pl_active) return BRG_ACTIVE;
      end
      BRG_LINKDOWN:      if (pl_reset) return BRG_RESET;
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
