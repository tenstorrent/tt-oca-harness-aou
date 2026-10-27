// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One error injected by model B (the remote die) after legal traffic, chosen
// by +L3_INJECT. Each must be caught under the expected rule by the
// receiving model A and by AOU_FDI_CHECKER, and, where the error is
// structural, by B's own stimulus self-check:
//   bad_type   reserved MSGTYPE           AOU-R3  (A, B self-check, checker)
//   rsvd       WriteResp RsvdZero set     AOU-R11 (A, B self-check, checker)
//   no_credit  WriteResps beyond credit   AOU-R16 (A, checker)
//   act_seq    ActivateAck in ENABLED     AOU-R40 (A, checker)
//   msgstart   MsgStart inside a message  AOU-R4  (A, B self-check, checker)
//   fdid       wrong FDId                 AOU-R9  (A, B self-check, checker)
//   act_place  Activation not at G0       AOU-R6  (A, B self-check, checker)
//   overgrant  credit beyond any buffer   saturation in A, AOU-R21 (checker)
//   req_after_dreq  WriteReq after B's own DeactivateReq
//                                         AOU-R30 (checker), AOU-R34 (A)
//   crd_in_disabled  ReadData credit once the teardown has completed
//                                         AOU-R29 (checker), AOU-R26 (A)
// The last two keep the deactivation windows honest: ReadData/WriteResp may
// follow one's own DeactivateReq and every credit one's own DeactivateAck
// (v0.8 8.4, MAS 7.3.1), but requests stop at the DeactivateReq and credits
// at DISABLED.
class aou_l3_inject_test extends aou_l3_unit_env_test;
  `uvm_component_utils(aou_l3_inject_test)

  string       inject = "bad_type";
  string       rule;
  bit          self_check;
  bit          rx_check;
  string       also[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("L3_INJECT=%s", inject));
    rx_check = 1'b1;
    case (inject)
      "bad_type":  begin rule = "AOU-R3";  self_check = 1'b1; end
      "rsvd":      begin rule = "AOU-R11"; self_check = 1'b1; end
      "no_credit": begin rule = "AOU-R16"; end
      "act_seq":   begin rule = "AOU-R40"; end
      "msgstart":  begin rule = "AOU-R4";  self_check = 1'b1; end
      "fdid":      begin rule = "AOU-R9";  self_check = 1'b1; end
      "act_place": begin
        rule = "AOU-R6";
        self_check = 1'b1;
        also.push_back("AOU-R40");
      end
      "overgrant": begin
        rule = "AOU-R21";
        rx_check = 1'b0;
      end
      "req_after_dreq": begin
        rule = "AOU-R30";
        rx_check = 1'b0;
        also.push_back("AOU-R34");
      end
      "crd_in_disabled": begin
        rule = "AOU-R29";
        rx_check = 1'b0;
        also.push_back("AOU-R26");
      end
      default: `uvm_fatal(get_type_name(), {"unknown +L3_INJECT=", inject})
    endcase
    chk.expect_rule(rule);
    foreach (also[i]) chk.expect_rule(also[i]);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    bring_up();
    traffic();
    idle(100);
    do_inject();
    idle(400);
    phase.drop_objection(this);
  endtask

  task do_inject();
    case (inject)
      "bad_type": begin
        aou_l3_bad_type_seq s = aou_l3_bad_type_seq::type_id::create("s");
        s.start(b.sqr);
      end
      "rsvd": begin
        aou_l3_rsvd_seq s = aou_l3_rsvd_seq::type_id::create("s");
        s.start(b.sqr);
      end
      "no_credit": begin
        aou_l3_no_credit_seq s = aou_l3_no_credit_seq::type_id::create("s");
        s.n = 40;
        s.start(b.sqr);
      end
      "act_seq": begin
        aou_l3_act_inject_seq s = aou_l3_act_inject_seq::type_id::create("s");
        s.op = AOU_ACT_ACK;
        s.start(b.sqr);
      end
      "msgstart": begin
        aou_msg_wreq w = aou_msg_wreq::type_id::create("w");
        // G1 of this WriteReq decodes as a legal WriteResp once MsgStart[11]
        // is forced, so only the framing rule fires.
        w.len = 8'h50;
        w.addr = 64'h0000_0000_0000_1000;
        b.cfg.pol.start_granule = 10;
        b.model.pk.inj_flip_start = 11;
        b.send(w);
        idle(40);
        b.cfg.pol.start_granule = -1;
      end
      "fdid": begin
        b.model.pk.inj_fdid = 1;
        b.model.pk.inj_empty = 1'b1;
        b.model.kick();
      end
      "act_place": begin
        aou_msg_raw r = aou_msg_raw::type_id::create("r");
        aou_granule_t g[$];
        g.push_back({4'h0, 3'b010, 4'(AOU_ACT_REQ), 29'h0});
        r.set_granules(g);
        b.cfg.pol.start_granule = 5;
        b.send(r);
        idle(40);
        b.cfg.pol.start_granule = -1;
      end
      "req_after_dreq": begin
        aou_msg_wreq w = aou_msg_wreq::type_id::create("w");
        w.ignore_state = 1'b1;
        b.model.lnk.queue_op(AOU_DEACT_REQ);
        b.model.kick();
        wait (b.model.lnk.dreq_sent);
        b.send(w);
      end
      "crd_in_disabled": begin
        a.model.lnk.request_deactivate();
        a.model.maybe_release_deact();
        a.model.kick();
        wait (a.model.lnk.state == AOU_LS_DISABLED && b.model.lnk.state == AOU_LS_DISABLED);
        idle(20);
        // RP0 RDATA=1 in an otherwise empty flit ({RP, WRESP, RDATA, ...}).
        b.model.pk.inj_msg_credit = 'h0200;
        b.model.pk.inj_empty = 1'b1;
        b.model.kick();
      end
      default: begin
        aou_l3_overgrant_seq s = aou_l3_overgrant_seq::type_id::create("s");
        s.cls = AOU_CC_RDATA;
        s.n = 3000;
        s.start(b.sqr);
      end
    endcase
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    expect_true(chk.count(rule, "aou_fdi_chk_adapter") > 0,
                $sformatf("AOU_FDI_CHECKER reports %s for %s", rule, inject));
    foreach (also[i])
      expect_true(chk.count(also[i]) > 0, $sformatf("receiving model reports %s for %s",
                                                     also[i], inject));
    if (rx_check)
      expect_true(chk.count(rule, "aou_unpacker") + chk.count(rule, "aou_l3_model") > 0,
                  $sformatf("receiving model reports %s for %s", rule, inject));
    if (self_check)
      expect_true(chk.count(rule, "aou_unpacker") >= 2,
                  $sformatf("B's self-check and A both report %s", rule));
    if (inject == "overgrant")
      expect_true(a.model.crd.tx_saturations > 0, "A's credit counter saturates");
    expect_true(chk.total() == chk.count(rule) + also_count(),
                $sformatf("only the injected rule fires (%s)", chk.summary()));
  endfunction

  function int unsigned also_count();
    int unsigned n = 0;
    foreach (also[i]) n += chk.count(also[i]);
    return n;
  endfunction
endclass
