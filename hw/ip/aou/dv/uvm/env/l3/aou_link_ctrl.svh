// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The AoU interface state machine of the remote die (spec chapter 8):
// DISABLED, ACTIVATE, ENABLED, DEACTIVATE, and ERROR for v0.8. State follows
// from eight events, each Req/Ack sent or received:
//   DISABLED -> ACTIVATE   on ActivateReq sent or received
//   ACTIVATE -> ENABLED    once both ActivateReq and both ActivateAck crossed
//   ENABLED  -> DEACTIVATE on DeactivateReq sent or received
//   DEACTIVATE -> DISABLED once both DeactivateReq and both DeactivateAck crossed
// Received opcodes are judged against the state (AOU-R40); waiters block on
// state_ev, never on a flag.
class aou_link_ctrl extends uvm_object;
  `uvm_object_utils(aou_link_ctrl)

  aou_l3_cfg       cfg;
  aou_credit_mgr   crd;
  aou_l3_cov       cov;

  aou_link_state_e state = AOU_LS_DISABLED;
  aou_link_state_e prev_state = AOU_LS_DISABLED;
  bit req_sent, req_rcvd, ack_sent, ack_rcvd;
  bit dreq_sent, dreq_rcvd, dack_sent, dack_rcvd;
  int unsigned dack_hold;       // received flits left before our DeactivateAck
  bit grant_due;       // initial CrdtGrant owed after our ActivateAck
  bit want_deact;      // DeactivateReq wanted once our requests complete
  int unsigned enabled_cnt;
  int unsigned epoch;           // activation epochs, bumped on every return to DISABLED
  int unsigned illegal_rcvd;
  bit          link_lost;       // set_state() is returning to DISABLED after a link loss
  // We sent an injected DeactivateAck in ENABLED. No compliant peer sends one
  // and the spec does not say what the DUT does with it, so the check that
  // the DUT waits for our real DeactivateAck (AOU-R37) stands down for the
  // next deactivation: cleared when we next reach DISABLED, or on a reset.
  bit          stray_dack_enabled;
  aou_msg_act out_q[$];
  uvm_event   state_ev;

  function new(string name = "aou_link_ctrl");
    super.new(name);
    state_ev = new("state_ev");
  endfunction

  function aou_msg_act mk(bit [3:0] op, bit prop = 1'b0);
    aou_msg_act m = aou_msg_act::type_id::create(aou_msg_act::op_name(op));
    m.op = op;
    m.property_req = prop;
    m.spec_rev = cfg.spec_rev;
    return m;
  endfunction

  function bit queued(bit [3:0] op);
    foreach (out_q[i]) if (out_q[i].op == op) return 1'b1;
    return 1'b0;
  endfunction

  function void queue_op(bit [3:0] op);
    if (!queued(op)) out_q.push_back(mk(op));
  endfunction

  function void request_activate();
    if (state == AOU_LS_ERROR) return;
    if (!req_sent) queue_op(AOU_ACT_REQ);
  endfunction

  function void request_deactivate();
    want_deact = 1'b1;
  endfunction

  // Called by the model once our own requests have completed (8.4).
  function void release_deact();
    if (want_deact && !dreq_sent && state inside {AOU_LS_ENABLED, AOU_LS_DEACTIVATE} &&
        !queued(AOU_DEACT_REQ))
      out_q.push_back(mk(AOU_DEACT_REQ, cfg.deact_prop));
  endfunction

  // Credited messages of class c may be sent now.
  function bit can_send(aou_cred_class_e c);
    bit open;
    if (state inside {AOU_LS_DISABLED, AOU_LS_ERROR}) return 1'b0;
    open = cfg.send_after_ack_rcvd ? (req_sent && ack_rcvd) :
                                     (state inside {AOU_LS_ENABLED, AOU_LS_DEACTIVATE});
    if (c inside {AOU_CC_WREQ, AOU_CC_RREQ} && dreq_sent) return 1'b0;
    return open;
  endfunction

  // Credits may be advertised now: after our ActivateAck (8.4), as the DUT does
  // (MAS 7.3.1). Request credits stop at our DeactivateAck; response credits
  // fund the answers to our own open requests and stop at our DeactivateReq,
  // after which none is open. Later ones could reach a peer already DISABLED:
  // the final DeactivateAck answers our DeactivateReq, and we learn of DISABLED
  // only when it arrives.
  function bit can_advertise(bit rsp_class);
    if (state inside {AOU_LS_DISABLED, AOU_LS_ERROR} || !ack_sent) return 1'b0;
    return rsp_class ? !dreq_sent : !dack_sent;
  endfunction

  // An activation message of ours went out in a flit.
  function void on_sent(aou_msg_act m);
    // An injected message bypasses the state machine but is still covered,
    // judged as the peer would judge it.
    if (m.ignore_state) begin
      bit legal = legal_sent(m.op);
      if (cov != null) cov.sample_act_op(m.op, AOU_L3_TX, legal);
      if (!legal && m.op == AOU_DEACT_ACK && state == AOU_LS_ENABLED) stray_dack_enabled = 1'b1;
      return;
    end
    case (m.op)
      AOU_ACT_REQ:   req_sent = 1'b1;
      AOU_ACT_ACK: begin
        ack_sent = 1'b1;
        grant_due = cfg.initial_grant;
      end
      AOU_DEACT_REQ: dreq_sent = 1'b1;
      AOU_DEACT_ACK: dack_sent = 1'b1;
      default: ;
    endcase
    if (cov != null) cov.sample_act_op(m.op, AOU_L3_TX, 1'b1);
    update_state();
  endfunction

  // Whether the peer may receive op from us now (legal_rcvd from its side).
  function bit legal_sent(bit [3:0] op);
    case (op)
      AOU_ACT_REQ:   return state inside {AOU_LS_DISABLED, AOU_LS_ACTIVATE} && !req_sent;
      AOU_ACT_ACK:   return state == AOU_LS_ACTIVATE && req_rcvd && !ack_sent;
      AOU_DEACT_REQ: return state inside {AOU_LS_ENABLED, AOU_LS_DEACTIVATE} && !dreq_sent;
      AOU_DEACT_ACK: return state == AOU_LS_DEACTIVATE && dreq_rcvd && !dack_sent;
      default:       return 1'b0;
    endcase
  endfunction

  function bit legal_rcvd(bit [3:0] op);
    case (op)
      AOU_ACT_REQ:   return state inside {AOU_LS_DISABLED, AOU_LS_ACTIVATE} && !req_rcvd;
      AOU_ACT_ACK:   return state == AOU_LS_ACTIVATE && req_sent && !ack_rcvd;
      AOU_DEACT_REQ: return state inside {AOU_LS_ENABLED, AOU_LS_DEACTIVATE} && !dreq_rcvd;
      AOU_DEACT_ACK: return state == AOU_LS_DEACTIVATE && dreq_sent && !dack_rcvd;
      default:       return 1'b0;
    endcase
  endfunction

  // An activation message from the peer. Returns 0 when it was out of
  // sequence; the caller reports AOU-R40.
  function bit on_rcvd(aou_msg_act m);
    bit legal;
    if (state == AOU_LS_ERROR) return 1'b1;   // ERROR ignores everything received
    legal = legal_rcvd(m.op);
    if (cov != null) cov.sample_act_op(m.op, AOU_L3_RX, legal);
    if (!legal) begin
      illegal_rcvd++;
      if (cfg.spec_rev == AOU_SPEC_V08 && cfg.error_state_en) begin
        enter_error();
      end else if (m.op == AOU_ACT_REQ && cfg.auto_ack) begin
        // MAS 7.2.3: a late ActivateReq is still acknowledged.
        out_q.push_back(mk(AOU_ACT_ACK));
      end
      return 1'b0;
    end
    case (m.op)
      AOU_ACT_REQ: begin
        req_rcvd = 1'b1;
        if (cfg.ack_first && cfg.auto_ack) queue_op(AOU_ACT_ACK);
        if (cfg.auto_activate && !req_sent) queue_op(AOU_ACT_REQ);
        if (!cfg.ack_first && cfg.auto_ack) queue_op(AOU_ACT_ACK);
      end
      AOU_ACT_ACK:   ack_rcvd = 1'b1;
      AOU_DEACT_REQ: begin
        dreq_rcvd = 1'b1;
        if (cfg.deact_ack_hold != 0) dack_hold = cfg.deact_ack_hold;
        else answer_deact_req();
      end
      AOU_DEACT_ACK: dack_rcvd = 1'b1;
      default: ;
    endcase
    update_state();
    return 1'b1;
  endfunction

  function void answer_deact_req();
    if (cfg.auto_deactivate) want_deact = 1'b1;
    if (cfg.auto_deact_ack) queue_op(AOU_DEACT_ACK);
  endfunction

  // One received flit of a held DeactivateAck (cfg.deact_ack_hold).
  function void tick_dack_hold();
    if (dack_hold == 0 || state != AOU_LS_DEACTIVATE) return;
    if (--dack_hold == 0) answer_deact_req();
  endfunction

  function void update_state();
    aou_link_state_e ns = state;
    case (state)
      AOU_LS_DISABLED:   if (req_sent || req_rcvd) ns = AOU_LS_ACTIVATE;
      AOU_LS_ACTIVATE:   if (req_sent && req_rcvd && ack_sent && ack_rcvd) ns = AOU_LS_ENABLED;
      AOU_LS_ENABLED:    if (dreq_sent || dreq_rcvd) ns = AOU_LS_DEACTIVATE;
      AOU_LS_DEACTIVATE: if (dreq_sent && dreq_rcvd && dack_sent && dack_rcvd) ns = AOU_LS_DISABLED;
      default: ;
    endcase
    if (ns == state) return;
    if (ns == AOU_LS_DISABLED) clear_events();
    set_state(ns);
    update_state();
  endfunction

  function void clear_events();
    {req_sent, req_rcvd, ack_sent, ack_rcvd} = 4'b0;
    {dreq_sent, dreq_rcvd, dack_sent, dack_rcvd} = 4'b0;
    grant_due = 1'b0;
    want_deact = 1'b0;
    dack_hold = 0;
    stray_dack_enabled = 1'b0;
    epoch++;
    crd.reset_link();
  endfunction

  function void set_state(aou_link_state_e ns);
    if (ns == state) return;
    prev_state = state;
    state = ns;
    if (ns == AOU_LS_ENABLED) enabled_cnt++;
    if (cov != null) cov.sample_fsm(prev_state, state, link_lost);
    `uvm_info(get_type_name(), $sformatf("%s -> %s", prev_state.name(), state.name()), UVM_MEDIUM)
    state_ev.trigger();
  endfunction

  function void enter_error();
    out_q.delete();
    set_state(AOU_LS_ERROR);
  endfunction

  // ERROR -> DISABLED (v0.8 8.3.3: an implementation-defined recovery).
  function void recover();
    out_q.delete();
    clear_events();
    link_lost = state != AOU_LS_ERROR;
    set_state(AOU_LS_DISABLED);
    link_lost = 1'b0;
  endfunction

  task wait_state(aou_link_state_e s);
    while (state != s) state_ev.wait_trigger();
  endtask
endclass
