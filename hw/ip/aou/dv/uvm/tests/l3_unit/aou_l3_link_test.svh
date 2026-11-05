// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link controller, two models back to back without time. Legal sequences:
// one-sided and simultaneous activation, deactivation from either side,
// re-activation with fresh credits. Illegal ones, each with its rule: an
// out-of-sequence Ack or Req (AOU-R40), a reserved opcode (AOU-R3), credits
// before ActivateAck (AOU-R29), credited traffic in DISABLED (AOU-R26), a
// DeactivateReq with requests unanswered (AOU-R33, with the requests that
// crossed our own DeactivateReq counted apart), a request after DeactivateReq
// (AOU-R34), credits after the DUT's DeactivateAck (AOU-R26: credits of every
// class are permitted until DISABLED, v0.8 8.4 and MAS 7.3.1, including those
// in the flit whose Ack completes the teardown; any credit in a later
// DISABLED flit is not, unless our own Ack completed the teardown: the DUT is
// DISABLED only once that Ack reaches it, v0.8 8.2, so its credits are
// tolerated and dropped until its next Activation message), request credits
// we advertise after our own DeactivateAck and that cross the final one
// (late_adv), the DUT's narrower MAS 7.3.1 credit windows (T1-C45: request
// credits stop with its DeactivateAck's flit, response credits with its
// DeactivateReq's), and v0.8's ERROR state with its recovery.
class aou_l3_link_test extends aou_l3_unit_base_test;
  `uvm_component_utils(aou_l3_link_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    legal_v07();
    simultaneous();
    illegal_ops();
    early_credit_and_traffic();
    deact_rules();
    deact_crossing();
    deact_credit_rules();
    late_credits();
    deact_window_rules();
    act_share_rules();
    error_v08();
    phase.drop_objection(this);
  endtask

  function void pair(output aou_l3_model a, output aou_l3_model b,
                     input aou_spec_rev_e rev = AOU_SPEC_V07);
    a = mk_model("A", mk_cfg("A", rev));
    b = mk_model("B", mk_cfg("B", rev));
  endfunction

  function void both(aou_l3_model a, aou_l3_model b, aou_link_state_e s, string what);
    expect_true(a.lnk.state == s && b.lnk.state == s,
                $sformatf("%s: A %s, B %s, expected %s", what, a.lnk.state.name(),
                          b.lnk.state.name(), s.name()));
  endfunction

  function void legal_v07();
    aou_l3_model a, b;
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "A activates");
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 64 && a.crd.tx_cred[3][AOU_CC_WDATA] == 256,
                "A holds B's full advertisement");
    expect_true(b.crd.tx_cred[2][AOU_CC_RDATA] == 256 && b.crd.tx_cred[1][AOU_CC_WRESP] == 32,
                "B holds A's full advertisement");
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "B deactivates");
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 0, "credits discarded in DISABLED");
    expect_true(a.lnk.epoch == 1 && b.lnk.epoch == 1, "one epoch completed");
    b.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "re-activation");
    expect_true(b.crd.tx_cred[1][AOU_CC_WREQ] == 64, "fresh credits after re-activation");
    a.lnk.request_deactivate();
    a.maybe_release_deact();
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "A deactivates");
    a.check_end();
    b.check_end();
    expect_true(chk.total() == 0, "legal sequences raise no finding");
  endfunction

  function void simultaneous();
    aou_l3_model a, b;
    pair(a, b);
    a.cfg.ack_first = 1'b1;
    a.lnk.request_activate();
    b.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "both activate at once");
    a.lnk.request_deactivate();
    b.lnk.request_deactivate();
    a.maybe_release_deact();
    b.maybe_release_deact();
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "both deactivate at once");
    expect_true(chk.total() == 0, "simultaneous sequences raise no finding");
  endfunction

  function aou_msg_act inj(bit [3:0] op);
    aou_msg_act m = aou_msg_act::type_id::create("m");
    m.op = op;
    m.ignore_state = 1'b1;
    return m;
  endfunction

  function void illegal_ops();
    aou_l3_model a, b;
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    chk.expect_rule("AOU-R40");
    chk.expect_rule("AOU-R3");
    chk.clear_counts();
    a.send(inj(AOU_ACT_ACK));
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R40") == 1, "ActivateAck in ENABLED is AOU-R40");
    expect_true(b.lnk.state == AOU_LS_ENABLED, "v0.7: B stays ENABLED");
    chk.clear_counts();
    a.send(inj(AOU_ACT_REQ));
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R40") == 2,
                "late ActivateReq is AOU-R40 at B, and B's Ack is AOU-R40 at A");
    chk.clear_counts();
    a.send(inj(AOU_DEACT_ACK));
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R40") == 1, "unsolicited DeactivateAck is AOU-R40");
    chk.clear_counts();
    a.send(inj(4'd9));
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R3") == 2, "reserved ACTIVATIONOP: AOU-R3 at A's self-check and B");
    expect_true(chk.count("AOU-R40") == 0, "a reserved opcode is not a sequencing finding");
    both(a, b, AOU_LS_ENABLED, "illegal messages move neither state");
    chk.unexpect_rule("AOU-R40");
    chk.unexpect_rule("AOU-R3");
    chk.clear_counts();
  endfunction

  function void early_credit_and_traffic();
    aou_l3_model a, b;
    aou_msg_wreq w = aou_msg_wreq::type_id::create("w");
    pair(a, b);
    chk.expect_rule("AOU-R26");
    chk.expect_rule("AOU-R29");
    chk.expect_rule("AOU-R16");
    w.ignore_state = 1'b1;
    w.ignore_credits = 1'b1;
    a.send(w);
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R26") == 1, "credited message in DISABLED is AOU-R26");
    expect_true(chk.count("AOU-R16") == 1, "and it has no credit (AOU-R16)");
    chk.clear_counts();
    a.lnk.request_activate();
    a.pk.inj_msg_credit = 1;
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R29") == 1, "credit in the ActivateReq flit is AOU-R29");
    both(a, b, AOU_LS_ENABLED, "activation still completes");
    chk.unexpect_rule("AOU-R26");
    chk.unexpect_rule("AOU-R29");
    chk.unexpect_rule("AOU-R16");
    chk.clear_counts();
  endfunction

  function void deact_rules();
    aou_l3_model a, b;
    aou_msg_wreq w = aou_msg_wreq::type_id::create("w");
    aou_msg_rreq r = aou_msg_rreq::type_id::create("r");
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    a.send(w);
    void'(exchange(a, b));
    expect_true(b.dut_wr_out[0] == 1, "B owes A a write response");
    chk.expect_rule("AOU-R33");
    chk.expect_rule("AOU-R34");
    a.lnk.queue_op(AOU_DEACT_REQ);
    r.ignore_state = 1'b1;
    a.send(r);
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R33") == 1, "DeactivateReq with a write unanswered is AOU-R33");
    expect_true(chk.count("AOU-R34") == 1, "ReadReq after DeactivateReq is AOU-R34");
    chk.unexpect_rule("AOU-R33");
    chk.unexpect_rule("AOU-R34");
    chk.clear_counts();
  endfunction

  // B's DeactivateReq and A's second write cross on the link: B already had
  // the first write when it sent DeactivateReq, the second arrives after.
  function void deact_crossing();
    aou_l3_model a, b;
    aou_msg_wreq w0 = aou_msg_wreq::type_id::create("w0");
    aou_msg_wreq w1 = aou_msg_wreq::type_id::create("w1");
    aou_flit f;
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    a.send(w0);
    void'(exchange(a, b));
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    f = b.pk.build();
    b.post_tx(f);
    expect_true(b.lnk.dreq_sent, "B's DeactivateReq is out");
    a.send(w1);
    f = a.pk.build();
    a.post_tx(f);
    b.rx_flit(copy_flit(f));
    expect_true(b.dut_wr_out[0] == 2 && b.dut_wr_late[0] == 1,
                $sformatf("B owes 2 writes, 1 received after its DeactivateReq (%0d, %0d)",
                          b.dut_wr_out[0], b.dut_wr_late[0]));
    chk.expect_rule("AOU-R33");
    chk.clear_counts();
    a.lnk.queue_op(AOU_DEACT_REQ);
    f = a.pk.build();
    a.post_tx(f);
    b.rx_flit(copy_flit(f));
    expect_true(chk.count("AOU-R33") == 1, "DeactivateReq with a crossing write is AOU-R33");
    expect_true(b.dut_wr_late[0] == 0, "the DUT's DeactivateReq closes the crossing window");
    chk.unexpect_rule("AOU-R33");
    chk.clear_counts();
  endfunction

  // One flit from B to A, with B's header MsgCredit replaced by mc (-1: as built).
  function void b_to_a(aou_l3_model a, aou_l3_model b, int mc = -1, bit empty = 1'b0);
    aou_flit f;
    b.pk.inj_msg_credit = mc;
    b.pk.inj_empty = empty;
    f = b.pk.build();
    b.post_tx(f);
    a.rx_flit(copy_flit(f));
  endfunction

  function void a_to_b(aou_l3_model a, aou_l3_model b);
    aou_flit f = a.pk.build();
    a.post_tx(f);
    b.rx_flit(copy_flit(f));
  endfunction

  // A judges B (the DUT side). MsgCredit RP0: WREQ=1 is 16'h0001, RDATA=1 is
  // 16'h0200 ({RP, WRESP, RDATA, WDATA, RREQ, WREQ}).
  function void deact_credit_rules();
    aou_l3_model a, b;
    int unsigned fresh_rdata;
    // A deactivates; B's DeactivateAck leaves both in DEACTIVATE.
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    chk.clear_counts();
    chk.expect_rule("AOU-R26");
    a.lnk.request_deactivate();
    a.maybe_release_deact();
    a_to_b(a, b);
    b_to_a(a, b, 'h0001);
    expect_true(b.lnk.dack_sent && a.lnk.dack_rcvd, "B's DeactivateAck is out");
    expect_true(chk.count("AOU-R26") == 0,
                "a request credit in the DeactivateAck's flit is permitted");
    b_to_a(a, b, 'h0001);
    expect_true(chk.count("AOU-R26") == 0, "a request credit after the DeactivateAck is permitted");
    b_to_a(a, b, 'h0200);
    expect_true(chk.count("AOU-R26") == 0,
                "a response credit after the DeactivateAck is permitted (MAS 7.3.1)");
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "A's deactivation completes");
    // A's DeactivateAck completed the teardown, so B was DISABLED only once it
    // arrived (8.2), and nothing in B's flits tells A when that was.
    b_to_a(a, b, 'h0001, 1'b1);
    expect_true(chk.count("AOU-R26") == 0,
                "a credit after our final DeactivateAck is tolerated: it may have crossed it");
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 0, "and it funds nothing");
    // B's next ActivateReq shows it has left DEACTIVATE.
    chk.expect_rule("AOU-R29");
    b.lnk.request_activate();
    b_to_a(a, b);
    expect_true(!a.lnk.peer_late, "B's ActivateReq ends the tolerance");
    b_to_a(a, b, 'h0001, 1'b1);
    expect_true(chk.count("AOU-R29") == 1, "a credit after it, before B's ActivateAck, is AOU-R29");
    chk.unexpect_rule("AOU-R29");
    chk.clear_counts();
    // B deactivates; its DeactivateAck completes the teardown, and the flit
    // carrying it may still carry credits of any class: they are consumed
    // with the flit and discarded.
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    fresh_rdata = a.crd.tx_cred[0][AOU_CC_RDATA];
    chk.clear_counts();
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    b_to_a(a, b);
    a_to_b(a, b);
    a_to_b(a, b);
    expect_true(a.lnk.dreq_sent && b.lnk.dreq_rcvd, "A's DeactivateReq is out");
    b_to_a(a, b, 'h0201);
    expect_true(a.lnk.state == AOU_LS_DISABLED, "B's DeactivateAck takes A to DISABLED");
    expect_true(chk.count("AOU-R26") == 0,
                "in the completing Ack's flit: WREQ and RDATA credits permitted");
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 0 && a.crd.tx_cred[0][AOU_CC_RDATA] == 0,
                "the completing Ack's flit credits are discarded, not counted");
    b_to_a(a, b, 'h0200, 1'b1);
    expect_true(chk.count("AOU-R26") == 1, "a response credit in a later DISABLED flit is AOU-R26");
    chk.unexpect_rule("AOU-R26");
    chk.clear_counts();
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "re-activation after the completing Ack's credits");
    expect_true(a.crd.tx_cred[0][AOU_CC_RDATA] == fresh_rdata,
                $sformatf("fresh RDATA balance after re-activation: %0d, expected %0d",
                          a.crd.tx_cred[0][AOU_CC_RDATA], fresh_rdata));
  endfunction

  // A holds B to the DUT's MAS 7.3.1 windows (T1-C45), which the unit models
  // otherwise do not apply to each other. MsgCredit RP0: WREQ=1 is 16'h0001,
  // RDATA=1 is 16'h0200.
  function void deact_window_rules();
    aou_l3_model a, b;
    pair(a, b);
    a.cfg.chk_deact_crd_window = 1'b1;
    a.lnk.request_activate();
    void'(exchange(a, b));
    chk.clear_counts();
    chk.expect_rule("T1-C45");
    // A deactivates first: B's request credits end with its DeactivateAck's
    // flit; its response credits go on until its own DeactivateReq.
    a.lnk.request_deactivate();
    a.maybe_release_deact();
    a_to_b(a, b);
    b_to_a(a, b, 'h0001);
    expect_true(b.lnk.dack_sent && a.lnk.dack_rcvd, "B's DeactivateAck is out");
    expect_true(chk.count("T1-C45") == 0,
                "a request credit in the DeactivateAck's flit is permitted");
    b_to_a(a, b, 'h0200);
    expect_true(chk.count("T1-C45") == 0,
                "a response credit after the DeactivateAck, before B's DeactivateReq, is fine");
    b_to_a(a, b, 'h0001);
    expect_true(chk.count("T1-C45") == 1,
                "a request credit after the DeactivateAck is T1-C45");
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "A's deactivation completes");
    // Re-activation: B's fresh CrdtGrant is no finding.
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "re-activation after the request-window case");
    expect_true(chk.count("T1-C45") == 1, "the re-activation's credits are no finding");
    // B deactivates first: its response credits end with its DeactivateReq's
    // flit; its request credits go on until its DeactivateAck.
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    b_to_a(a, b, 'h0200);
    expect_true(b.lnk.dreq_sent && a.lnk.dreq_rcvd, "B's DeactivateReq is out");
    expect_true(chk.count("T1-C45") == 1,
                "a header response credit in the DeactivateReq's flit is permitted");
    b_to_a(a, b, 'h0001);
    expect_true(chk.count("T1-C45") == 1,
                "a request credit after B's DeactivateReq, before its DeactivateAck, is permitted");
    b_to_a(a, b, 'h0200);
    expect_true(chk.count("T1-C45") == 2, "a response credit after the DeactivateReq is T1-C45");
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "B's deactivation completes");
    chk.unexpect_rule("T1-C45");
    expect_true(chk.total() == chk.count("T1-C45"),
                $sformatf("no other finding (%s)", chk.summary()));
    chk.clear_counts();
  endfunction

  // B advertises request credits until it is DISABLED (late_adv), and the
  // credit it held back (late_adv_hold) follows its DeactivateReq. A answers
  // that Req with the final DeactivateAck before B's credit flits reach it:
  // they cross on the link. A neither reports nor counts them, and after the
  // next activation holds B's fresh advertisement alone.
  function void late_credits();
    aou_l3_model a, b;
    aou_l3_cfg cb = mk_cfg("B");
    aou_flit q[$];
    aou_flit f;
    int dreq_at = -1;
    int unsigned late = 0;
    int unsigned fresh_wreq;
    cb.late_adv_hold = 31;
    a = mk_model("A", mk_cfg("A"));
    b = mk_model("B", cb);
    chk.clear_counts();
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "activation with B holding credit back");
    fresh_wreq = a.crd.tx_cred[0][AOU_CC_WREQ];
    expect_true(fresh_wreq == 64 - 31,
                $sformatf("B advertised its WriteReq depth less the held credit: %0d", fresh_wreq));
    a.lnk.request_deactivate();
    a.maybe_release_deact();
    a_to_b(a, b);
    expect_true(a.lnk.dreq_sent && b.lnk.dreq_rcvd, "A's DeactivateReq is out");
    // B's Ack, its Req and its late credit, none delivered yet.
    for (int unsigned n = 0; n < 60 && b.pk.has_work(); n++) begin
      f = b.pk.build();
      b.post_tx(f);
      if (dreq_at < 0 && f.msg_start[0] && f.g[0][39:36] == AOU_MT_MISC &&
          f.g[0][35:33] == AOU_MISCOP_ACT && f.g[0][32:29] == AOU_DEACT_REQ)
        dreq_at = q.size();
      q.push_back(f);
    end
    expect_true(b.lnk.dack_sent && b.lnk.dreq_sent && b.lnk.state == AOU_LS_DEACTIVATE,
                "B sent its Ack and Req and is still in DEACTIVATE");
    expect_true(dreq_at >= 0 && q.size() > dreq_at + 1,
                $sformatf("credit-only flits follow B's DeactivateReq (%0d flits, Req at %0d)",
                          q.size(), dreq_at));
    for (int i = 0; i <= dreq_at; i++) a.rx_flit(copy_flit(q[i]));
    // A's final DeactivateAck: A is DISABLED; B is not until it arrives.
    f = a.pk.build();
    a.post_tx(f);
    expect_true(a.lnk.state == AOU_LS_DISABLED && a.lnk.peer_late,
                "A's DeactivateAck completes the teardown on A's side");
    for (int i = dreq_at + 1; i < q.size(); i++) begin
      if (q[i].msg_credit[2:0] != 0) late++;
      a.rx_flit(copy_flit(q[i]));
    end
    expect_true(late > 0, "B's late flits carry WriteReq credit");
    expect_true(chk.total() == 0,
                $sformatf("credits crossing the final DeactivateAck are no finding (%s)",
                          chk.summary()));
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 0, "A counts none of them");
    b.rx_flit(copy_flit(f));
    both(a, b, AOU_LS_DISABLED, "B reaches DISABLED on A's Ack");
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "re-activation after the late credits");
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == fresh_wreq,
                $sformatf("A holds B's fresh WriteReq advertisement alone: %0d, expected %0d",
                          a.crd.tx_cred[0][AOU_CC_WREQ], fresh_wreq));
    expect_true(chk.total() == 0, "the re-activation raises no finding");
    // With late_adv off, B's request credits stop at its own DeactivateAck.
    cb.late_adv = 1'b0;
    a.lnk.request_deactivate();
    a.maybe_release_deact();
    a_to_b(a, b);
    f = b.pk.build();
    b.post_tx(f);
    expect_true(b.lnk.dack_sent && !b.lnk.can_advertise(1'b0),
                "late_adv off: no request credit after B's own DeactivateAck");
    a.rx_flit(copy_flit(f));
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "deactivation with late_adv off");
    chk.clear_counts();
  endfunction

  // 4.4 under the v0.7 wire format, as the v0.9 draft words it: an Activation
  // message shares its flit only with one CrdtGrant after an ActivateReq/Ack
  // or with responses after a DeactivateReq. Anything else beside it is
  // AOU-R6 when the receiver holds its peer to the draft (v0p9draft,
  // +v0p9draft in the T1 bench), and legal under v0.7.1 otherwise. The
  // Ack+CrdtGrant and DeactivateReq+response layouts are what the DUT sends
  // on every activation and deactivation; the model packs them too
  // (act_share_pct), and the grant beside its ActivateReq when its Ack went
  // first without it (ack_first).
  function void act_share_rules();
    act_share_case(1'b0);
    act_share_case(1'b1);
  endfunction

  // exchange() until B builds a flit whose G0 starts the Activation message
  // `op`: that flit, built and posted but not yet received by A.
  function aou_flit next_act_flit(aou_l3_model a, aou_l3_model b, bit [3:0] op);
    for (int unsigned n = 0; n < 40 && (a.pk.has_work() || b.pk.has_work()); n++) begin
      aou_flit f;
      if (a.pk.has_work()) begin
        f = a.pk.build();
        a.post_tx(f);
        b.rx_flit(copy_flit(f));
      end
      if (b.pk.has_work()) begin
        f = b.pk.build();
        b.post_tx(f);
        if (f.msg_start[0] && f.g[0][39:36] == AOU_MT_MISC && f.g[0][35:33] == AOU_MISCOP_ACT &&
            f.g[0][32:29] == op)
          return f;
        a.rx_flit(copy_flit(f));
      end
    end
    return null;
  endfunction

  function void act_share_case(bit draft);
    aou_l3_model a, b;
    aou_msg_wresp x = aou_msg_wresp::type_id::create("x");
    aou_msg_crdtgrant zg = aou_msg_crdtgrant::type_id::create("zg");
    aou_granule_t g[$], gg[$];
    aou_flit f;
    int unsigned shared = 0;
    string tag = draft ? "v0.9 draft" : "v0.7.1";
    pair(a, b);
    a.cfg.v0p9draft = draft;
    b.cfg.v0p9draft = draft;
    chk.clear_counts();

    // The initial CrdtGrant beside the ActivateAck: legal under both.
    b.cfg.pol.act_share_pct = 100;
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, {tag, ": activation with the CrdtGrant beside B's Ack"});
    foreach (b.tx_flit_q[i]) if (aou_l3_cov::act_layout(b.tx_flit_q[i]) == 3) shared++;
    expect_true(shared == 1, {tag, ": B packed its initial CrdtGrant beside its ActivateAck"});
    expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 64,
                {tag, ": A holds the credit granted beside the Ack"});
    expect_true(chk.total() == 0,
                {tag, ": one CrdtGrant beside the ActivateAck raises no finding"});
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, {tag, ": deactivation after the shared Ack"});
    expect_true(chk.total() == 0, {tag, ": the deactivation raises no finding"});

    if (draft) chk.expect_rule("AOU-R6");
    zg.to_granules(gg);
    x.to_granules(g);

    // A second CrdtGrant (an empty one) behind the initial one beside the
    // ActivateAck: one too many under the draft.
    a.lnk.request_activate();
    f = next_act_flit(a, b, AOU_ACT_ACK);
    expect_true(f != null, {tag, ": B's ActivateAck flit"});
    if (f != null) begin
      expect_true(aou_l3_cov::act_layout(f) == 3, {tag, ": B's ActivateAck with its CrdtGrant"});
      f.g[3] = gg[0]; f.g[4] = gg[1]; f.msg_start[3] = 1'b1;
      chk.clear_counts();
      a.rx_flit(copy_flit(f));
      expect_true(chk.count("AOU-R6") == (draft ? 1 : 0),
                  {tag, ": two CrdtGrants beside the ActivateAck",
                   draft ? " are AOU-R6" : " pass"});
    end
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, {tag, ": activation completes"});

    // From here B packs its Activation messages alone and the test adds the company.
    b.cfg.pol.act_share_pct = 0;

    // A WriteResp beside the DeactivateReq: legal under both.
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    f = next_act_flit(a, b, AOU_DEACT_REQ);
    expect_true(f != null, {tag, ": B's DeactivateReq flit"});
    if (f != null) begin
      f.g[1] = g[0]; f.msg_start[1] = 1'b1;
      chk.clear_counts();
      a.rx_flit(copy_flit(f));
      expect_true(chk.count("AOU-R6") == 0,
                  {tag, ": a WriteResp may share the DeactivateReq's flit"});
    end
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, {tag, ": deactivation completes"});

    // A CrdtGrant beside the DeactivateReq: only responses may follow it under the draft.
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, {tag, ": re-activation"});
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    f = next_act_flit(a, b, AOU_DEACT_REQ);
    expect_true(f != null, {tag, ": B's second DeactivateReq flit"});
    if (f != null) begin
      f.g[1] = gg[0]; f.g[2] = gg[1]; f.msg_start[1] = 1'b1;
      chk.clear_counts();
      a.rx_flit(copy_flit(f));
      expect_true(chk.count("AOU-R6") == (draft ? 1 : 0),
                  {tag, ": a CrdtGrant beside the DeactivateReq",
                   draft ? " is AOU-R6" : " passes"});
    end
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, {tag, ": deactivation completes again"});

    // B acks first; its Ack goes alone and its initial CrdtGrant rides with its
    // ActivateReq instead: legal under both, and A takes the credit from it.
    b.cfg.ack_first = 1'b1;
    b.cfg.pol.act_share_pct = 0;
    a.lnk.request_activate();
    f = next_act_flit(a, b, AOU_ACT_ACK);
    expect_true(f != null, {tag, ": B's ActivateAck flit, acking first"});
    if (f != null) begin
      expect_true(aou_l3_cov::act_layout(f) == 2, {tag, ": B's ActivateAck alone"});
      a.rx_flit(copy_flit(f));
    end
    b.cfg.pol.act_share_pct = 100;
    f = next_act_flit(a, b, AOU_ACT_REQ);
    expect_true(f != null, {tag, ": B's ActivateReq flit after its Ack"});
    if (f != null) begin
      expect_true(aou_l3_cov::act_layout(f) == 1, {tag, ": B's ActivateReq with its CrdtGrant"});
      chk.clear_counts();
      a.rx_flit(copy_flit(f));
      expect_true(chk.count("AOU-R6") == 0,
                  {tag, ": one CrdtGrant may share the ActivateReq's flit"});
      expect_true(a.crd.tx_cred[0][AOU_CC_WREQ] == 64,
                  {tag, ": A holds the credit granted beside the Req"});
    end
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, {tag, ": activation with the grant beside B's Req"});
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, {tag, ": deactivation after the shared Req"});

    // A second CrdtGrant (an empty one) behind that one: one too many under the draft.
    b.cfg.pol.act_share_pct = 0;
    a.lnk.request_activate();
    f = next_act_flit(a, b, AOU_ACT_ACK);
    if (f != null) a.rx_flit(copy_flit(f));
    b.cfg.pol.act_share_pct = 100;
    f = next_act_flit(a, b, AOU_ACT_REQ);
    expect_true(f != null, {tag, ": B's second ActivateReq flit after its Ack"});
    if (f != null) begin
      int unsigned gp = AOU_GRANULES;
      for (int unsigned p = 1; p < AOU_GRANULES; p++) if (f.msg_start[p]) gp = p + 2;
      expect_true(aou_l3_cov::act_layout(f) == 1 && gp + 2 <= AOU_GRANULES,
                  {tag, ": B's ActivateReq with its CrdtGrant, room behind it"});
      f.g[gp] = gg[0]; f.g[gp + 1] = gg[1]; f.msg_start[gp] = 1'b1;
      chk.clear_counts();
      a.rx_flit(copy_flit(f));
      expect_true(chk.count("AOU-R6") == (draft ? 1 : 0),
                  {tag, ": two CrdtGrants beside the ActivateReq",
                   draft ? " are AOU-R6" : " pass"});
    end
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, {tag, ": activation completes after the second grant"});
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, {tag, ": deactivation after the second grant"});
    b.cfg.ack_first = 1'b0;
    b.cfg.pol.act_share_pct = 0;

    // A WriteResp beside the DeactivateAck: nothing may follow it under the draft.
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, {tag, ": re-activation for A's deactivation"});
    a.lnk.request_deactivate();
    a.maybe_release_deact();
    f = next_act_flit(a, b, AOU_DEACT_ACK);
    expect_true(f != null, {tag, ": B's DeactivateAck flit"});
    if (f != null) begin
      f.g[1] = g[0]; f.msg_start[1] = 1'b1;
      chk.clear_counts();
      a.rx_flit(copy_flit(f));
      expect_true(chk.count("AOU-R6") == (draft ? 1 : 0),
                  {tag, ": a WriteResp beside the DeactivateAck",
                   draft ? " is AOU-R6" : " passes"});
    end
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, {tag, ": A's deactivation completes"});
    if (draft) chk.unexpect_rule("AOU-R6");
    chk.clear_counts();
  endfunction

  function void error_v08();
    aou_l3_model a, b;
    aou_msg_wresp x = aou_msg_wresp::type_id::create("x");
    pair(a, b, AOU_SPEC_V08);
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "v0.8 activation (4-granule ActivateReq, alone in its flit)");
    expect_true(chk.total() == 0, "v0.8 activation raises no finding");
    chk.expect_rule("AOU-R40");
    a.send(inj(AOU_ACT_ACK));
    void'(exchange(a, b));
    expect_true(b.lnk.state == AOU_LS_ERROR, "v0.8: out-of-sequence Ack moves B to ERROR");
    b.send(x);
    expect_true(!b.pk.has_work(), "ERROR transmits nothing");
    a.send(inj(AOU_DEACT_ACK));
    void'(exchange(a, b));
    expect_true(chk.count("AOU-R40") == 1, "ERROR ignores what it receives");
    b.recover();
    a.recover();
    both(a, b, AOU_LS_DISABLED, "ERROR -> DISABLED by recovery");
    b.pk.flush();
    a.lnk.request_activate();
    void'(exchange(a, b));
    both(a, b, AOU_LS_ENABLED, "re-activation after ERROR");
    chk.unexpect_rule("AOU-R40");
  endfunction
endclass
