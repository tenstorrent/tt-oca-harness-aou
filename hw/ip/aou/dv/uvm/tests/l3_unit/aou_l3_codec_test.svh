// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Encodings without time: granule counts for every type and DLENGTH, pack /
// unpack round trips, credit encoding, the Format 6 flit byte map, and a
// cross-check of every encoder against PR 80's independent aou_pkg.
class aou_l3_codec_test extends aou_l3_unit_base_test;
  `uvm_component_utils(aou_l3_codec_test)

  int unsigned iters = 200;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    void'($value$plusargs("L3_ITERS=%d", iters));
    test_lengths();
    test_roundtrip(AOU_SPEC_V07);
    test_roundtrip(AOU_SPEC_V08);
    test_credit_enc();
    test_flit_map();
    test_pr80();
    phase.drop_objection(this);
  endtask

  function void test_lengths();
    int unsigned w[3] = '{8, 15, 30};
    int unsigned wf[3] = '{7, 14, 27};
    int unsigned r[3] = '{8, 14, 27};
    for (int unsigned dl = 0; dl < 3; dl++) begin
      expect_true(aou_data_len(AOU_MT_WDATA, 2'(dl)) == w[dl], $sformatf("W%0d length", dl));
      expect_true(aou_data_len(AOU_MT_WDATAF, 2'(dl)) == wf[dl], $sformatf("WF%0d length", dl));
      expect_true(aou_data_len(AOU_MT_RDATA, 2'(dl)) == r[dl], $sformatf("R%0d length", dl));
    end
    expect_true(aou_data_len(AOU_MT_WDATA, 2'b11) == 0, "DLENGTH 11 has no length");
    for (int unsigned k = 0; k < NKIND; k++) begin
      aou_msg m = rand_msg(k);
      expect_true(m.num_granules() == kind_len(k),
                  $sformatf("%s is %0d granules, expected %0d", m.kind(), m.num_granules(),
                            kind_len(k)));
    end
    begin
      aou_msg_act a = aou_msg_act::type_id::create("a");
      a.op = AOU_ACT_REQ;
      a.spec_rev = AOU_SPEC_V08;
      expect_true(a.num_granules() == 4, "v0.8 ActivateReq is 4 granules");
      a.op = AOU_ACT_ACK;
      expect_true(a.num_granules() == 1, "v0.8 ActivateAck is 1 granule");
      a.spec_rev = AOU_SPEC_V07;
      a.op = AOU_ACT_REQ;
      expect_true(a.num_granules() == 1, "v0.7 ActivateReq is 1 granule");
    end
  endfunction

  function void test_roundtrip(aou_spec_rev_e rev);
    for (int unsigned k = 0; k < NKIND; k++) begin
      for (int unsigned i = 0; i < iters; i++) begin
        aou_msg m = rand_msg(k, rev);
        aou_msg d;
        aou_granule_t g[$];
        m.to_granules(g);
        d = aou_msg_codec::decode(g, rev);
        expect_true(d.get_type_name() == m.get_type_name() || (k <= 1),
                    $sformatf("%s decoded as %s", m.kind(), d.get_type_name()));
        expect_true(m.compare(d), $sformatf("%s round trip: %s vs %s", m.kind(),
                                            m.convert2string(), d.convert2string()));
        expect_true(m.convert2string() == d.convert2string(),
                    $sformatf("%s fields: %s vs %s", m.kind(), m.convert2string(),
                              d.convert2string()));
        expect_true(d.rsvd_nonzero() == "", $sformatf("%s reserved bits", m.kind()));
        check_payload(m, d);
      end
    end
  endfunction

  // Payload the string form does not show in full.
  function void check_payload(aou_msg m, aou_msg d);
    aou_msg_wdata wm, wd;
    aou_msg_rdata rm, rd;
    if ($cast(wm, m) && $cast(wd, d)) begin
      int unsigned n = aou_dl_bits(wm.dlength);
      for (int unsigned b = 0; b < n; b++) begin
        if (wm.data[b] != wd.data[b]) begin
          expect_true(0, $sformatf("%s data bit %0d", m.kind(), b));
          break;
        end
      end
      for (int unsigned b = 0; b < n / 8; b++) begin
        if ((wm.full() ? 1'b1 : wm.strb[b]) != wd.strb[b]) begin
          expect_true(0, $sformatf("%s strobe bit %0d", m.kind(), b));
          break;
        end
      end
    end
    if ($cast(rm, m) && $cast(rd, d)) begin
      int unsigned n = aou_dl_bits(rm.dlength);
      for (int unsigned b = 0; b < n; b++) begin
        if (rm.data[b] != rd.data[b]) begin
          expect_true(0, $sformatf("%s data bit %0d", m.kind(), b));
          break;
        end
      end
    end
  endfunction

  function void test_credit_enc();
    int unsigned legal[8] = '{0, 1, 4, 8, 16, 32, 64, 128};
    foreach (legal[i]) begin
      expect_true(aou_cred_dec3(aou_cred_enc_floor(AOU_CC_WREQ, legal[i])) == legal[i],
                  $sformatf("encode %0d", legal[i]));
      expect_true(aou_cred_legal3(legal[i]), $sformatf("%0d legal", legal[i]));
      expect_true(aou_cred_legal2(legal[i]) == (i < 4), $sformatf("%0d legal for WRESP", legal[i]));
      expect_true(int'(aou_pkg::credit_dec3(3'(i))) == legal[i], "PR 80 credit_dec3");
      expect_true(aou_pkg::credit_enc3(legal[i]) == aou_cred_enc_floor(AOU_CC_WREQ, legal[i]),
                  "PR 80 credit_enc3");
    end
    expect_true(!aou_cred_legal3(5) && !aou_cred_legal3(129) && !aou_cred_legal2(16),
                "illegal credit values are rejected, not fatal");
    expect_true(aou_cred_floor(AOU_CC_WREQ, 100) == 64, "floor 100 -> 64");
    expect_true(aou_cred_floor(AOU_CC_WRESP, 100) == 8, "WRESP floor 100 -> 8");
    expect_true(aou_cred_floor(AOU_CC_WDATA, 3) == 1, "floor 3 -> 1");
    expect_true(aou_cred_floor(AOU_CC_WDATA, 1000) == 128, "floor 1000 -> 128");
  endfunction

  function void test_flit_map();
    for (int unsigned i = 0; i < iters; i++) begin
      aou_flit f = aou_flit::type_id::create("f");
      aou_flit r = aou_flit::type_id::create("r");
      aou_flit_vec_t v;
      foreach (f.g[k]) f.g[k] = {8'($urandom), $urandom};
      f.msg_start = {16'($urandom), $urandom};
      f.msg_credit = 16'($urandom);
      f.fdid = 2'($urandom);
      v = f.to_vec();
      r.from_vec(v);
      expect_true(r.g == f.g && r.msg_start == f.msg_start && r.msg_credit == f.msg_credit &&
                  r.fdid == f.fdid, "flit vector round trip");
      expect_true(v[8*2 +: 8] == f.g[0][39:32] && v[8*6 +: 8] == f.g[0][7:0], "G0 at bytes 2-6");
      expect_true(v[8*66 +: 8] == f.g[12][39:32], "G12 at byte 66");
      expect_true(v[8*130 +: 8] == f.g[24][39:32], "G24 at byte 130");
      expect_true(v[8*194 +: 8] == f.g[36][39:32], "G36 at byte 194");
      expect_true(v[8*253 +: 8] == f.g[47][7:0], "G47 ends at byte 253");
      expect_true(v[8*62 +: 8] == {f.msg_start[3:0], 2'b00, f.fdid}, "PH B0 at byte 62");
      expect_true({v[8*129 +: 8], v[8*128 +: 8]} == f.msg_credit, "MsgCredit at 128-129");
      expect_true(v[8*193 +: 8] == f.msg_start[47:40], "PH B9 at byte 193");
      expect_true(v[7:6] == 2'b11, "flit header Protocol Identifier is not NOP");
    end
  endfunction

  // PR 80's aou_pkg was verified field by field against the RTL structs; it
  // shares no code with these classes.
  function void test_pr80();
    for (int unsigned i = 0; i < iters; i++) begin
      for (int unsigned k = 0; k < NKIND; k++) begin
        aou_msg m = rand_msg(k);
        aou_granule_t g[$];
        logic [39:0] p[aou_pkg::NUM_GRANULES];
        m.flex = '0;
        m.to_granules(g);
        if (!pr80_pack(m, p)) continue;
        foreach (g[j]) begin
          if (g[j] !== p[j]) begin
            expect_true(0, $sformatf("%s granule %0d: %010h, PR 80 %010h", m.kind(), j, g[j],
                                     p[j]));
            break;
          end
        end
      end
      check_pr80_flit();
    end
  endfunction

  function bit pr80_pack(aou_msg m, output logic [39:0] p[aou_pkg::NUM_GRANULES]);
    aou_msg_req rq;
    aou_msg_wdata w;
    aou_msg_rdata r;
    aou_msg_wresp b;
    aou_msg_act a;
    aou_msg_crdtgrant c;
    foreach (p[i]) p[i] = '0;
    if ($cast(rq, m)) begin
      logic [2:0][39:0] g3;
      aou_pkg::pack_req(g3, aou_pkg::msgtype_e'(rq.msg_type), rq.rp, rq.lock, rq.id, rq.size,
                        rq.prot, rq.len, rq.cache, rq.qos, rq.addr);
      for (int i = 0; i < 3; i++) p[i] = g3[i];
    end else if ($cast(w, m)) begin
      if (w.full()) aou_pkg::pack_writedatafull(p, w.rp, w.data, w.dlength);
      else aou_pkg::pack_writedata(p, w.rp, w.data, w.strb, w.dlength);
    end else if ($cast(r, m)) begin
      aou_pkg::pack_readdata(p, r.rp, r.id, r.resp, r.last, r.data, r.dlength);
    end else if ($cast(b, m)) begin
      logic [39:0] g1;
      aou_pkg::pack_writeresp(g1, b.rp, b.id, b.resp);
      p[0] = g1;
    end else if ($cast(a, m)) begin
      logic [39:0] g1;
      aou_pkg::pack_activation(g1, aou_pkg::activationop_e'(a.op), a.property_req);
      p[0] = g1;
    end else if ($cast(c, m)) begin
      logic [1:0][39:0] g2;
      aou_pkg::pack_crdtgrant(g2,
          c.get_cred(0, AOU_CC_WREQ), c.get_cred(1, AOU_CC_WREQ), c.get_cred(2, AOU_CC_WREQ),
          c.get_cred(3, AOU_CC_WREQ), c.get_cred(0, AOU_CC_RREQ), c.get_cred(1, AOU_CC_RREQ),
          c.get_cred(2, AOU_CC_RREQ), c.get_cred(3, AOU_CC_RREQ), c.get_cred(0, AOU_CC_WDATA),
          c.get_cred(1, AOU_CC_WDATA), c.get_cred(2, AOU_CC_WDATA), c.get_cred(3, AOU_CC_WDATA),
          c.get_cred(0, AOU_CC_RDATA), c.get_cred(1, AOU_CC_RDATA), c.get_cred(2, AOU_CC_RDATA),
          c.get_cred(3, AOU_CC_RDATA), c.get_cred(0, AOU_CC_WRESP), c.get_cred(1, AOU_CC_WRESP),
          c.get_cred(2, AOU_CC_WRESP), c.get_cred(3, AOU_CC_WRESP));
      p[0] = g2[0];
      p[1] = g2[1];
    end else begin
      return 1'b0;
    end
    return 1'b1;
  endfunction

  function void check_pr80_flit();
    aou_flit f = aou_flit::type_id::create("f");
    logic [7:0] pf[aou_pkg::FLIT_BYTES];
    logic [39:0] gd[aou_pkg::NUM_GRANULES];
    aou_flit_vec_t v;
    foreach (f.g[k]) begin
      f.g[k] = {8'($urandom), $urandom};
      gd[k] = f.g[k];
    end
    f.msg_start = {16'($urandom), $urandom};
    f.msg_credit = 16'($urandom);
    f.fdid = 2'($urandom);
    f.fh[0] = 8'h00;
    aou_pkg::flit_clear(pf);
    aou_pkg::flit_put_granules(pf, 0, aou_pkg::NUM_GRANULES, gd);
    aou_pkg::flit_put_header(pf, f.fdid, f.msg_start, f.msg_credit);
    v = f.to_vec();
    for (int i = 0; i < AOU_FLIT_BYTES; i++) begin
      if (v[8*i +: 8] !== pf[i]) begin
        expect_true(0, $sformatf("flit byte %0d: %02h, PR 80 %02h", i, v[8*i +: 8], pf[i]));
        break;
      end
    end
  endfunction
endclass
