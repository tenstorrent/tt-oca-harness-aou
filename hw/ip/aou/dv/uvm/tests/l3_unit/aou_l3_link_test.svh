// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link controller, two models back to back without time. Legal sequences:
// one-sided and simultaneous activation, deactivation from either side,
// re-activation with fresh credits. Illegal ones, each with its rule: an
// out-of-sequence Ack or Req (AOU-R40), a reserved opcode (AOU-R3), credits
// before ActivateAck (AOU-R29), credited traffic in DISABLED (AOU-R26), a
// DeactivateReq with requests unanswered (AOU-R33, with the requests that
// crossed our own DeactivateReq counted apart), a request after DeactivateReq
// (AOU-R34), credits after the DUT's DeactivateAck (AOU-R26, v0.8 8.4: request
// credits are permitted, response credits and any credit in a later DISABLED
// flit are not), and v0.8's ERROR state with its recovery.
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
    act_alone_v08();
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
    expect_true(chk.count("AOU-R26") == 1, "a response credit after the DeactivateAck is AOU-R26");
    void'(exchange(a, b));
    both(a, b, AOU_LS_DISABLED, "A's deactivation completes");
    b_to_a(a, b, 'h0001, 1'b1);
    expect_true(chk.count("AOU-R26") == 2, "a request credit in a later DISABLED flit is AOU-R26");
    chk.clear_counts();
    // B deactivates; its DeactivateAck completes the teardown, and the flit
    // carrying it may still carry request credits.
    pair(a, b);
    a.lnk.request_activate();
    void'(exchange(a, b));
    chk.clear_counts();
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    b_to_a(a, b);
    a_to_b(a, b);
    a_to_b(a, b);
    expect_true(a.lnk.dreq_sent && b.lnk.dreq_rcvd, "A's DeactivateReq is out");
    b_to_a(a, b, 'h0201);
    expect_true(a.lnk.state == AOU_LS_DISABLED, "B's DeactivateAck takes A to DISABLED");
    expect_true(chk.count("AOU-R26") == 1,
                "in the completing Ack's flit: WREQ credit permitted, RDATA credit AOU-R26");
    chk.unexpect_rule("AOU-R26");
    chk.clear_counts();
  endfunction

  // v0.8 4.4 under the v0.7 wire format: another message in the flit of an
  // Activation message is AOU-R6 (the DUT's DeactivateReq with a WriteResp)
  // when the receiver holds its peer to v0.8 (v0p8, +v0p8 in the T1 bench), and
  // legal under v0.7.1 otherwise.
  function void act_alone_v08();
    act_alone_case(1'b0);
    act_alone_case(1'b1);
  endfunction

  function void act_alone_case(bit v0p8);
    aou_l3_model a, b;
    aou_msg_wresp x = aou_msg_wresp::type_id::create("x");
    aou_granule_t g[$];
    aou_flit f;
    pair(a, b);
    a.cfg.v0p8 = v0p8;
    a.lnk.request_activate();
    void'(exchange(a, b));
    chk.clear_counts();
    if (v0p8) chk.expect_rule("AOU-R6");
    b.lnk.request_deactivate();
    b.maybe_release_deact();
    f = b.pk.build();
    b.post_tx(f);
    x.to_granules(g);
    f.g[1] = g[0];
    f.msg_start[1] = 1'b1;
    a.rx_flit(copy_flit(f));
    if (v0p8)
      expect_true(chk.count("AOU-R6") == 1,
                  "v0.8: a WriteResp in the DeactivateReq's flit is AOU-R6");
    else
      expect_true(chk.count("AOU-R6") == 0,
                  "v0.7.1: a WriteResp may share the DeactivateReq's flit");
    if (v0p8) chk.unexpect_rule("AOU-R6");
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
