// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Every multi-granule message at every start granule, through the packer and
// back through the unpacker: a message that does not fit continues at G0 of
// the next flit with MsgStart clear there (4.4), and reassembles unchanged.
// A WriteResp follows each one, so the test also covers a message ending
// exactly at G47 and a continuation followed by a new message.
class aou_l3_crossflit_test extends aou_l3_unit_base_test;
  `uvm_component_utils(aou_l3_crossflit_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    for (int unsigned k = 0; k < NKIND; k++) begin
      if (k == 11 || k == 12) continue;   // WriteResp and Activation are 1 granule
      for (int unsigned s = 0; s < AOU_GRANULES; s++) one(k, s);
    end
    expect_true(chk.total() == 0, "no rule findings on legal layouts");
    phase.drop_objection(this);
  endtask

  function aou_l3_model enabled_model(string name);
    aou_l3_cfg c = mk_cfg(name);
    aou_l3_model m;
    c.cov_en = 1'b1;
    c.pol.credit_only_flits = 1'b0;
    m = mk_model(name, c);
    m.lnk.state = AOU_LS_ENABLED;
    foreach (m.crd.tx_cred[r, cc]) m.crd.tx_cred[r][cc] = 1000;
    return m;
  endfunction

  function void one(int unsigned k, int unsigned s);
    aou_l3_model tx = enabled_model("tx");
    aou_unpacker rx = aou_unpacker::type_id::create("rx");
    aou_msg m = rand_msg(k);
    aou_msg tail = rand_msg(11);
    aou_flit f[$];
    aou_flit fo[$];
    aou_msg got[$];
    int unsigned len = m.num_granules();
    string tag = $sformatf("%s at G%0d", m.kind(), s);
    rx.cfg = tx.cfg;
    rx.chk = chk;
    tx.cfg.pol.start_granule = int'(s);
    tx.send(m);
    tx.send(tail);
    while (tx.pk.has_work() && f.size() < 4) begin
      aou_flit x = tx.pk.build();
      tx.post_tx(x);
      fo.push_back(x);
      f.push_back(copy_flit(x));
      tx.cfg.pol.start_granule = -1;
    end
    foreach (f[i]) begin
      rx.unpack(f[i]);
      foreach (rx.done[j]) got.push_back(rx.done[j]);
    end
    expect_true(f[0].msg_start[s] == 1'b1, {tag, ": MsgStart set at its start"});
    expect_true(got.size() == 2, $sformatf("%s: %0d messages back", tag, got.size()));
    if (got.size() == 2) begin
      expect_true(m.compare(got[0]), {tag, ": reassembled unchanged"});
      expect_true(tail.compare(got[1]), {tag, ": following message unchanged"});
      expect_true(got[0].start_granule == int'(s), {tag, ": start granule"});
    end
    if (s + len > AOU_GRANULES) begin
      expect_true(fo.size() >= 2 && fo[1].carry_in == s + len - AOU_GRANULES,
                  {tag, ": continuation length in the next flit"});
      expect_true(f.size() >= 2 && f[1].msg_start[0] == 1'b0, {tag, ": no MsgStart at G0"});
      expect_true(got.size() > 0 && got[0].span_flits == 2, {tag, ": marked as spanning"});
    end else begin
      expect_true(fo[0].carry_in == 0 && got.size() > 0 && got[0].span_flits == 1,
                  {tag, ": fits in one flit"});
    end
  endfunction
endclass
