// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credit manager scenarios (spec chapter 6): zero credit holds a message
// until a grant covers every granule; over-grant saturates; header MsgCredit
// and CrdtGrant in one flit add up; return policies; encode-down of large
// returns; RP round robin; and an overflow by the peer is AOU-R16.
class aou_l3_credit_test extends aou_l3_unit_base_test;
  `uvm_component_utils(aou_l3_credit_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    zero_credit();
    saturation();
    hdr_plus_grant();
    overflow();
    return_policies();
    encode_down();
    phase.drop_objection(this);
  endtask

  function aou_l3_model enabled(string name, aou_l3_cfg c = null);
    aou_l3_model m;
    if (c == null) c = mk_cfg(name);
    m = mk_model(name, c);
    m.lnk.state = AOU_LS_ENABLED;
    {m.lnk.req_sent, m.lnk.req_rcvd, m.lnk.ack_sent, m.lnk.ack_rcvd} = 4'hF;
    return m;
  endfunction

  function void zero_credit();
    aou_l3_cfg c = mk_cfg("zc");
    aou_l3_model m;
    aou_msg_wreq w = aou_msg_wreq::type_id::create("w");
    aou_flit f;
    c.pol.credit_only_flits = 1'b0;
    m = enabled("zc", c);
    m.crd.reset_link();
    foreach (m.crd.rx_pending[r, k]) m.crd.rx_pending[r][k] = 0;
    w.rp = 2;
    m.send(w);
    expect_true(!m.pk.has_work(), "no credit: WriteReq held");
    void'(m.crd.tx_grant(2, AOU_CC_WREQ, 1));
    expect_true(!m.pk.has_work(), "1 of 3 credits: still held (no partial messages)");
    void'(m.crd.tx_grant(1, AOU_CC_WREQ, 8));
    expect_true(!m.pk.has_work(), "credit on another RP does not help");
    void'(m.crd.tx_grant(2, AOU_CC_WREQ, 4));
    expect_true(m.pk.has_work(), "5 credits: WriteReq goes");
    f = m.pk.build();
    m.post_tx(f);
    expect_true(f.msgs.size() == 1 && f.msg_start == 48'h1, "WriteReq placed at G0");
    expect_true(m.crd.tx_cred[2][AOU_CC_WREQ] == 2, "3 credits consumed at the start");
    expect_true(m.crd.tx_cred[1][AOU_CC_WREQ] == 8, "RP1 untouched");
  endfunction

  function void saturation();
    aou_l3_cfg c = mk_cfg("sat");
    aou_l3_model m;
    c.tx_cred_max = 100;
    m = enabled("sat", c);
    expect_true(!m.crd.tx_grant(0, AOU_CC_WDATA, 64), "64 of 100 fits");
    expect_true(m.crd.tx_grant(0, AOU_CC_WDATA, 64), "128 of 100 saturates");
    expect_true(m.crd.tx_cred[0][AOU_CC_WDATA] == 100, "counter held at its maximum");
    expect_true(m.crd.tx_saturations == 1, "one saturation counted");
    m.crd.tx_consume(0, AOU_CC_WDATA, 30);
    expect_true(m.crd.tx_cred[0][AOU_CC_WDATA] == 70, "counting resumes below the maximum");
  endfunction

  // Header MsgCredit RP1 WREQ=4 and CrdtGrant RP1 WREQ=8 in one flit grant 12.
  function void hdr_plus_grant();
    aou_l3_model m = enabled("hg");
    aou_msg_crdtgrant g = aou_msg_crdtgrant::type_id::create("g");
    aou_flit f = aou_flit::type_id::create("f");
    aou_granule_t gg[$];
    m.grant_epoch = int'(m.lnk.epoch);   // not the initial grant (AOU-R24)
    g.set_cred(1, AOU_CC_WREQ, 8);
    g.set_cred(3, AOU_CC_WRESP, 4);
    g.to_granules(gg);
    f.g[5] = gg[0];
    f.g[6] = gg[1];
    f.msg_start[5] = 1'b1;
    f.msg_credit = {2'd1, 2'b00, 3'd0, 3'd0, 3'd0, 3'd2};
    m.rx_flit(copy_flit(f));
    expect_true(m.crd.tx_cred[1][AOU_CC_WREQ] == 12, "header and CrdtGrant credits add up");
    expect_true(m.crd.tx_cred[3][AOU_CC_WRESP] == 4, "CrdtGrant RP3 WRESP");
    expect_true(m.crd.tx_cred[0][AOU_CC_WREQ] == 0, "RP0 untouched");
  endfunction

  // The peer starts more granules than we advertised.
  function void overflow();
    aou_l3_model m = enabled("of");
    aou_flit f = aou_flit::type_id::create("f");
    aou_msg_wresp b = aou_msg_wresp::type_id::create("b");
    aou_granule_t gg[$];
    m.crd.reset_link();
    m.crd.rx_outstanding[0][AOU_CC_WRESP] = 2;
    b.to_granules(gg);
    for (int i = 0; i < 3; i++) begin
      f.g[i] = gg[0];
      f.msg_start[i] = 1'b1;
    end
    chk.expect_rule("AOU-R16");
    m.rx_flit(copy_flit(f));
    chk.unexpect_rule("AOU-R16");
    expect_true(chk.count("AOU-R16") == 1, "third WriteResp overflows our 2 credits (AOU-R16)");
    expect_true(m.crd.rx_overflows == 1, "overflow counted");
    expect_true(m.rx_msgs == 3, "all three still delivered");
  endfunction

  function void return_policies();
    aou_l3_cfg c = mk_cfg("rp");
    aou_l3_model m;
    c.ret_policy = '{AOU_RET_IMMEDIATE, AOU_RET_ON_CONSUME, AOU_RET_DELAYED, AOU_RET_WITHHELD,
                     AOU_RET_ON_CONSUME};
    c.ret_delay = 3;
    m = enabled("rp", c);
    foreach (m.crd.rx_pending[r, k]) begin
      m.crd.rx_pending[r][k] = 0;
      m.crd.rx_outstanding[r][k] = 100;
    end
    void'(m.crd.rx_receive(0, AOU_CC_WREQ, 3));
    expect_true(m.crd.rx_pending[0][AOU_CC_WREQ] == 3, "immediate: free on receipt");
    void'(m.crd.rx_receive(0, AOU_CC_RREQ, 3));
    expect_true(m.crd.rx_pending[0][AOU_CC_RREQ] == 0, "on-consume: held while buffered");
    m.crd.rx_consume(0, AOU_CC_RREQ, 3);
    expect_true(m.crd.rx_pending[0][AOU_CC_RREQ] == 3, "on-consume: freed when dequeued");
    void'(m.crd.rx_receive(0, AOU_CC_WDATA, 8));
    m.crd.rx_consume(0, AOU_CC_WDATA, 8);
    void'(m.crd.tick());
    void'(m.crd.tick());
    expect_true(m.crd.rx_pending[0][AOU_CC_WDATA] == 0, "delayed: not yet after 2 ticks");
    void'(m.crd.tick());
    expect_true(m.crd.rx_pending[0][AOU_CC_WDATA] == 8, "delayed: returned after 3 ticks");
    void'(m.crd.rx_receive(0, AOU_CC_RDATA, 14));
    m.crd.rx_consume(0, AOU_CC_RDATA, 14);
    expect_true(m.crd.rx_pending[0][AOU_CC_RDATA] == 0 &&
                m.crd.rx_withheld[0][AOU_CC_RDATA] == 14, "withheld: kept back");
    m.release_withheld();
    expect_true(m.crd.rx_pending[0][AOU_CC_RDATA] == 14, "withheld: released on request");
    expect_true(m.crd.rx_occupancy[0][AOU_CC_WREQ] == 0 && m.crd.rx_occupancy[0][AOU_CC_RREQ] == 0,
                "buffer empty again");
  endfunction

  // Large returns go out as the largest encodable values, RPs in turn.
  function void encode_down();
    aou_l3_model m = enabled("ed");
    bit [15:0] mc;
    int unsigned r;
    int unsigned n[AOU_CC_NUM];
    aou_msg_crdtgrant g = aou_msg_crdtgrant::type_id::create("g");
    foreach (m.crd.rx_pending[rr, k]) m.crd.rx_pending[rr][k] = 0;
    m.crd.rx_pending[0][AOU_CC_WREQ] = 100;
    m.crd.rx_pending[2][AOU_CC_WRESP] = 20;
    expect_true(m.crd.take_hdr(mc), "header return 1");
    aou_credit_mgr::hdr_decode(mc, r, n);
    expect_true(r == 0 && n[AOU_CC_WREQ] == 64, "RP0 WREQ 100 -> 64 first");
    expect_true(m.crd.take_hdr(mc), "header return 2");
    aou_credit_mgr::hdr_decode(mc, r, n);
    expect_true(r == 2 && n[AOU_CC_WRESP] == 8, "then RP2 WRESP 20 -> 8 (2-bit field)");
    expect_true(m.crd.take_hdr(mc), "header return 3");
    aou_credit_mgr::hdr_decode(mc, r, n);
    expect_true(r == 0 && n[AOU_CC_WREQ] == 32, "round robin back to RP0: 36 -> 32");
    expect_true(m.crd.take_grant(g), "CrdtGrant carries the rest");
    expect_true(g.get_cred(0, AOU_CC_WREQ) == 4 && g.get_cred(2, AOU_CC_WRESP) == 8,
                "CrdtGrant RP0 WREQ 4, RP2 WRESP 8");
    expect_true(m.crd.rx_pending[2][AOU_CC_WRESP] == 4, "4 WRESP credits still pending");
    expect_true(m.crd.rx_outstanding[0][AOU_CC_WREQ] == 100, "all 100 advertised");
  endfunction
endclass
