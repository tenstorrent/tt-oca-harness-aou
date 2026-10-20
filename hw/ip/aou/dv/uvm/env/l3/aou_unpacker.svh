// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Flits -> messages, with cross-flit reassembly and the framing and encoding
// rules that one flit stream can be judged by (AOU-R1, R3..R14). One instance
// checks the DUT's flits; a second self-checks the model's own stimulus.
// Per flit it publishes the complete messages (done[], wire order) and the
// first granule of every message that starts in it (st_g0[]/st_pos[]), since
// credits are consumed at a message's start (6.1).
class aou_unpacker extends uvm_object;
  `uvm_object_utils(aou_unpacker)

  aou_l3_cfg      cfg;
  aou_l3_rule_chk chk;
  aou_l3_dir_e    dir = AOU_L3_RX;

  aou_granule_t   carry_g[$];
  int unsigned    carry_need;
  int             carry_flit;
  int             carry_pos;
  int unsigned    flits;

  aou_msg         done[$];
  aou_granule_t   st_g0[$];
  int unsigned    st_pos[$];
  int unsigned    st_len[$];

  function new(string name = "aou_unpacker");
    super.new(name);
  endfunction

  function string who();
    return (dir == AOU_L3_RX) ? "DUT->remote" : "remote->DUT";
  endfunction

  // Checks are counted on the DUT's stream only; the self-check of our own
  // stimulus still reports what it finds.
  // RP count of the die that sent the flit: its credits may name any of its RPs.
  function int unsigned sender_rp_count();
    return (dir == AOU_L3_RX) ? cfg.peer_count() : cfg.rp_count;
  endfunction

  function void ledger_chk(string rule);
    if (dir == AOU_L3_RX) aou_rule_log::check(rule, get_type_name());
  endfunction

  function void viol(string rule, aou_flit f, int g, string msg);
    chk.violation(rule, get_type_name(),
                  $sformatf("%s flit#%0d G%0d: %s", who(), f.seq, g, msg));
  endfunction

  function void reset();
    carry_g.delete();
    carry_need = 0;
  endfunction

  function void finish(aou_flit f, aou_granule_t g[$], int sflit, int spos, int unsigned nflits);
    aou_msg m = aou_msg_codec::decode(g, cfg.spec_rev);
    string r;
    aou_msg_crdtgrant cg;
    aou_msg_act a;
    m.dir = dir;
    m.start_flit = sflit;
    m.start_granule = spos;
    m.span_flits = nflits;
    r = m.rsvd_nonzero();
    ledger_chk("AOU-R11");
    if (r != "") viol("AOU-R11", f, spos, $sformatf("%s: %s non-zero", m.kind(), r));
    if (m.cred_class() != AOU_CC_NONE) ledger_chk("AOU-R14");
    if (m.cred_class() != AOU_CC_NONE && int'(m.rp) >= cfg.eff_rp_count())
      viol("AOU-R14", f, spos, $sformatf("%s names RP%0d of %0d", m.kind(), m.rp,
                                         cfg.eff_rp_count()));
    if ($cast(cg, m) && cg.unsupported_rp_nonzero(sender_rp_count()))
      viol("AOU-R11", f, spos, $sformatf("CrdtGrant grants an RP >= %0d", sender_rp_count()));
    if ($cast(a, m) && cfg.spec_rev == AOU_SPEC_V08) ledger_chk("AOU-R12");
    if ($cast(a, m) && a.profile_nonzero())
      viol("AOU-R12", f, spos, "ActivateReq profile fields non-zero under the Basic Profile");
    done.push_back(m);
  endfunction

  function void unpack(aou_flit f);
    int unsigned g = 0;
    int unsigned acts[$];
    int unsigned misc_half[2];
    bit [3:0] act_ops[$];
    done.delete();
    st_g0.delete();
    st_pos.delete();
    st_len.delete();
    flits++;

    ledger_chk("AOU-R1");
    if (f.hdr_rsvd != 0)
      viol("AOU-R1", f, 0, $sformatf("protocol header RsvdZero bits %04h", f.hdr_rsvd));
    ledger_chk("AOU-R9");
    if (f.fdid != cfg.fdid)
      viol("AOU-R9", f, 0, $sformatf("FDId %0d, expected %0d", f.fdid, cfg.fdid));
    // The RP field is bound in every header, including one that advertises
    // nothing, which names RP0 (MAS 3.9).
    ledger_chk("AOU-R14");
    if (int'(f.msg_credit[15:14]) >= sender_rp_count())
      viol("AOU-R14", f, 0, $sformatf("MsgCredit names RP%0d of %0d", f.msg_credit[15:14],
                                      sender_rp_count()));
    else if (f.msg_credit[13:0] == 0 && f.msg_credit[15:14] != 0)
      viol("AOU-R14", f, 0, $sformatf("MsgCredit advertising nothing names RP%0d, not RP0",
                                      f.msg_credit[15:14]));

    if (carry_g.size() > 0) begin
      int unsigned owed = carry_need - carry_g.size();
      bit bad = 1'b0;
      ledger_chk("AOU-R5");
      for (int unsigned i = 0; i < owed; i++) begin
        if (f.msg_start[i]) begin
          viol("AOU-R5", f, i, $sformatf("MsgStart inside the %0d-granule continuation", owed));
          bad = 1'b1;
          g = i;
          break;
        end
      end
      if (!bad) begin
        for (int unsigned i = 0; i < owed; i++) carry_g.push_back(f.g[i]);
        finish(f, carry_g, carry_flit, carry_pos, 2);
        g = owed;
      end
      carry_g.delete();
    end

    while (g < AOU_GRANULES) begin
      int unsigned len;
      bit cut = 1'b0;
      if (!f.msg_start[g]) begin
        g++;
        continue;
      end
      len = aou_msg_len(f.g[g], cfg.spec_rev);
      ledger_chk("AOU-R3");
      ledger_chk("AOU-R4");
      if (f.g[g][39:36] == AOU_MT_MISC) begin
        if (f.g[g][35:33] == AOU_MISCOP_ACT) begin
          acts.push_back(g);
          act_ops.push_back(f.g[g][32:29]);
        end else begin
          misc_half[g / AOU_HALF_G]++;
        end
      end
      if (len == 0) begin
        viol("AOU-R3", f, g, $sformatf("undefined encoding, first granule %010h", f.g[g]));
        g++;
        continue;
      end
      st_g0.push_back(f.g[g]);
      st_pos.push_back(g);
      st_len.push_back(len);
      for (int unsigned k = g + 1; k < g + len && k < AOU_GRANULES; k++) begin
        if (f.msg_start[k]) begin
          viol("AOU-R4", f, k, $sformatf("MsgStart inside the message started at G%0d", g));
          void'(st_g0.pop_back());
          void'(st_pos.pop_back());
          void'(st_len.pop_back());
          g = k;
          cut = 1'b1;
          break;
        end
      end
      if (cut) continue;
      if (g + len <= AOU_GRANULES) begin
        aou_granule_t mg[$];
        for (int unsigned k = 0; k < len; k++) mg.push_back(f.g[g+k]);
        finish(f, mg, f.seq, g, 1);
        g += len;
      end else begin
        for (int unsigned k = g; k < AOU_GRANULES; k++) carry_g.push_back(f.g[k]);
        carry_need = len;
        carry_flit = f.seq;
        carry_pos = g;
        g = AOU_GRANULES;
      end
    end

    // Activation placement (4.4) and the per-PL Req/Ack split (9.2).
    if (acts.size() > 0) begin
      ledger_chk("AOU-R6");
      ledger_chk("AOU-R8");
    end
    foreach (acts[i]) begin
      if (acts[i] != 0) viol("AOU-R6", f, acts[i], "Activation message not at G0");
    end
    if (acts.size() > 1) begin
      bit req = 1'b0, ack = 1'b0;
      foreach (act_ops[i]) begin
        if (act_ops[i] == AOU_ACT_REQ) req = 1'b1;
        if (act_ops[i] == AOU_ACT_ACK) ack = 1'b1;
      end
      viol((req && ack) ? "AOU-R8" : "AOU-R6", f, acts[1],
           $sformatf("%0d Activation messages in one flit", acts.size()));
    end
    // v0.8 4.4 placement, independent of the wire format (spec_rev): the
    // Activation alone in its flit, at most 2 other Misc per half-flit. Always
    // on our own flits; on the DUT's only with cfg.v0p8 (+v0p8) or the v0.8
    // wire format, since the DUT implements v0.7.1's rule.
    if (dir == AOU_L3_TX || cfg.spec_rev == AOU_SPEC_V08 || cfg.v0p8) begin
      ledger_chk("AOU-R7");
      if (acts.size() > 0 && f.num_starts() > acts.size()) begin
        string k = "";
        foreach (done[j]) k = {k, " ", done[j].kind()};
        if (carry_need != 0) k = {k, " (+1 continuing)"};
        viol("AOU-R6", f, acts[0], {"Activation message shares its flit:", k});
      end
      foreach (misc_half[h]) begin
        if (misc_half[h] > 2)
          viol("AOU-R7", f, h * AOU_HALF_G, $sformatf("%0d Misc messages in half %0d",
                                                     misc_half[h], h));
      end
    end
  endfunction
endclass
