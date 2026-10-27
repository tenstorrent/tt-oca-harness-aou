// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Messages -> flits for the model's TX direction (spec 4.4, 6). Per flit:
//   1. the continuation of a message that spans from the previous flit, at G0;
//   2. an Activation message, only at G0 and at most one per flit;
//   3. returned credits: the initial CrdtGrant after our ActivateAck, then
//      header MsgCredit and/or CrdtGrant per the policy;
//   4. credited messages whose class has credit for every granule (consumed
//      at the start) and whose class the link state allows, oldest first or
//      in random order across (RP, class) queues, never reordered within one;
//      a WriteReq the policy picked for wdata_first waits while its own
//      WriteData goes ahead of it (held()).
// The policy object shapes the layout; injection fields corrupt one flit.
class aou_packer extends uvm_object;
  `uvm_object_utils(aou_packer)

  localparam int NQ = AOU_RP_MAX * AOU_CC_NUM;

  aou_l3_cfg     cfg;
  aou_credit_mgr crd;
  aou_link_ctrl  lnk;

  aou_msg        q[NQ][$];
  int unsigned   qs[NQ][$];
  aou_msg        misc_q[$];
  int unsigned   misc_s[$];
  int unsigned   submit_cnt;
  // WriteData first (pol.wdata_first_pct): per q[] entry, how many of a
  // WriteReq's own WriteData messages go before it (0: none). Per RP, the
  // WriteData messages placed and the ones the placed WriteReqs account for;
  // AXI4 has no write interleaving, so the excess is the head WriteReq's own.
  int unsigned   wf_tgt[NQ][$];
  int unsigned   wd_placed[AOU_RP_MAX];
  int unsigned   wd_owed[AOU_RP_MAX];

  aou_granule_t  carry_g[$];
  aou_msg        carry_msg;
  int unsigned   flit_cnt;
  int unsigned   credit_stalls;

  // One-shot injections applied to the next flit built.
  int            inj_flip_start = -1;   // invert MsgStart[k]
  int            inj_fdid = -1;
  int            inj_msg_credit = -1;   // raw 16-bit MsgCredit
  int            inj_hdr_rsvd = -1;     // protocol-header RsvdZero bits (AOU-R1)
  bit            inj_empty;             // an empty flit even with a carry pending

  function new(string name = "aou_packer");
    super.new(name);
  endfunction

  function void push(aou_msg m);
    aou_msg_act a;
    if ($cast(a, m)) begin
      lnk.out_q.push_back(a);
      return;
    end
    if (m.cred_class() == AOU_CC_NONE) begin
      misc_q.push_back(m);
      misc_s.push_back(submit_cnt++);
    end else begin
      int unsigned i = int'(m.rp) * AOU_CC_NUM + m.cred_class();
      q[i].push_back(m);
      qs[i].push_back(submit_cnt++);
      wf_tgt[i].push_back(wdata_first_tgt(m));
    end
  endfunction

  // How many of WriteReq m's WriteData messages the policy sends before it.
  function int unsigned wdata_first_tgt(aou_msg m);
    aou_msg_req r;
    int unsigned beats;
    if (m.msg_type != AOU_MT_WREQ || cfg.pol.wdata_first_pct == 0 || m.ignore_state ||
        m.ignore_credits || !$cast(r, m))
      return 0;
    if ($urandom_range(99) >= cfg.pol.wdata_first_pct) return 0;
    beats = int'(r.len) + 1;
    if (cfg.pol.wdata_first_beats == 0) return $urandom_range(1, beats);
    return (cfg.pol.wdata_first_beats < beats) ? cfg.pol.wdata_first_beats : beats;
  endfunction

  // q[i]'s head is a WriteReq waiting for its own WriteData to go first:
  // fewer than its target have been placed and the RP's next WriteData can go
  // now. Once that data can't go (no WDATA credit, nothing queued) the
  // WriteReq goes, so the order never waits on credit the DUT returns only
  // after the WriteReq has arrived (its RX W FIFO holds the early data).
  // A WriteReq on an RP of pol.hold_wreq_rps is held whatever its data does.
  function bit held(int i);
    int unsigned rp;
    int unsigned d;
    int unsigned own;
    rp = i / AOU_CC_NUM;
    if (i % AOU_CC_NUM == int'(AOU_CC_WREQ) && cfg.pol.hold_wreq_rps[rp]) return 1'b1;
    if (wf_tgt[i].size() == 0 || wf_tgt[i][0] == 0) return 1'b0;
    d = rp * AOU_CC_NUM + int'(AOU_CC_WDATA);
    own = (wd_placed[rp] > wd_owed[rp]) ? wd_placed[rp] - wd_owed[rp] : 0;
    return own < wf_tgt[i][0] && q[d].size() > 0 && eligible(q[d][0]);
  endfunction

  function int unsigned queued_msgs();
    int unsigned n = misc_q.size();
    foreach (q[i]) n += q[i].size();
    return n;
  endfunction

  function void flush();
    foreach (q[i]) begin
      q[i].delete();
      qs[i].delete();
      wf_tgt[i].delete();
    end
    foreach (wd_placed[r]) begin
      wd_placed[r] = 0;
      wd_owed[r] = 0;
    end
    misc_q.delete();
    misc_s.delete();
  endfunction

  function bit eligible(aou_msg m);
    aou_cred_class_e c = m.cred_class();
    if (m.cred_class() == AOU_CC_NONE)
      return m.ignore_state || !(lnk.state inside {AOU_LS_DISABLED, AOU_LS_ERROR});
    if (!m.ignore_state && !lnk.can_send(c)) return 1'b0;
    if (cfg.pol.hold_credited) return 1'b0;
    return m.ignore_credits || crd.tx_can(int'(m.rp), c, m.num_granules());
  endfunction

  function bit adv_any();
    return lnk.can_advertise(1'b0) || lnk.can_advertise(1'b1);
  endfunction

  // Whether build() has anything to put in a flit.
  function bit has_work();
    if (inj_empty) return 1'b1;
    // ERROR transmits nothing (v0.8 8.3.3).
    if (lnk.state == AOU_LS_ERROR) return 1'b0;
    if (carry_g.size() > 0 || lnk.out_q.size() > 0) return 1'b1;
    if (lnk.grant_due && adv_any() &&
        crd.rx_has_pending(lnk.can_advertise(1'b0), lnk.can_advertise(1'b1))) return 1'b1;
    if (cfg.pol.credit_only_flits &&
        crd.rx_has_pending(lnk.can_advertise(1'b0), lnk.can_advertise(1'b1))) return 1'b1;
    if (misc_q.size() > 0 && eligible(misc_q[0])) return 1'b1;
    foreach (q[i]) if (q[i].size() > 0 && eligible(q[i][0]) && !held(i)) return 1'b1;
    return 1'b0;
  endfunction

  // The eligible queue head (q[] index, NQ for misc_q) with the most granules
  // that still fit in `room`, or -1.
  function int pick_fit(int unsigned misc_half_cnt, int unsigned room);
    int best = -1;
    int unsigned best_len;
    foreach (q[i]) begin
      if (q[i].size() > 0 && eligible(q[i][0]) && !held(i) && q[i][0].num_granules() <= room &&
          (best < 0 || q[i][0].num_granules() > best_len)) begin
        best = i;
        best_len = q[i][0].num_granules();
      end
    end
    if (misc_q.size() > 0 && eligible(misc_q[0]) && misc_half_cnt < cfg.pol.misc_per_half_max &&
        misc_q[0].num_granules() <= room && (best < 0 || misc_q[0].num_granules() > best_len))
      best = NQ;
    return best;
  endfunction

  // Index of the next message to place: a q[] index, NQ for misc_q, or -1.
  function int pick(int unsigned misc_half_cnt);
    int cand[$];
    int unsigned best_s;
    int best = -1;
    foreach (q[i]) begin
      if (q[i].size() > 0) begin
        if (eligible(q[i][0])) begin
          if (!held(i)) cand.push_back(i);
        end else if (lnk.can_send(q[i][0].cred_class()) && !cfg.pol.hold_credited) credit_stalls++;
      end
    end
    if (misc_q.size() > 0 && eligible(misc_q[0]) && misc_half_cnt < cfg.pol.misc_per_half_max)
      cand.push_back(NQ);
    if (cand.size() == 0) return -1;
    if (cfg.pol.random_order) return cand[$urandom_range(0, cand.size() - 1)];
    foreach (cand[k]) begin
      int unsigned s = (cand[k] == NQ) ? misc_s[0] : qs[cand[k]][0];
      if (best < 0 || s < best_s) begin
        best = cand[k];
        best_s = s;
      end
    end
    return best;
  endfunction

  // Place m at granule gp; what does not fit becomes the carry.
  function void place(aou_flit f, aou_msg m, int unsigned gp);
    aou_granule_t g[$];
    aou_cred_class_e c = m.cred_class();
    m.dir = AOU_L3_TX;
    if (c != AOU_CC_NONE && cfg.pol.prof_pct != 0 && $urandom_range(99) < cfg.pol.prof_pct)
      m.flex[11:0] = 12'($urandom());
    m.to_granules(g);
    f.msg_start[gp] = 1'b1;
    foreach (g[i]) begin
      if (gp + i < AOU_GRANULES) f.g[gp+i] = g[i];
      else carry_g.push_back(g[i]);
    end
    m.start_flit = f.seq;
    m.start_granule = gp;
    m.span_flits = (carry_g.size() > 0) ? 2 : 1;
    if (carry_g.size() > 0) carry_msg = m;
    if (c != AOU_CC_NONE) crd.tx_consume(int'(m.rp), c, g.size());
    count_write(m);
    f.msgs.push_back(m);
  endfunction

  function void count_write(aou_msg m);
    aou_msg_req r;
    if (m.msg_type inside {AOU_MT_WDATA, AOU_MT_WDATAF}) wd_placed[m.rp]++;
    else if (m.msg_type == AOU_MT_WREQ && $cast(r, m)) wd_owed[m.rp] += int'(r.len) + 1;
  endfunction

  function aou_msg_crdtgrant mk_grant();
    aou_msg_crdtgrant g = aou_msg_crdtgrant::type_id::create("g");
    if (!crd.take_grant(g, lnk.can_advertise(1'b0), lnk.can_advertise(1'b1))) return null;
    return g;
  endfunction

  function aou_flit build();
    aou_flit f = aou_flit::type_id::create("f");
    int unsigned gp;
    int unsigned nmsgs;
    int unsigned misc_half[2];
    bit alone;
    bit first_new = 1'b1;
    aou_cred_method_e meth = cfg.pol.cred_method;
    f.seq = flit_cnt++;
    f.dir = AOU_L3_TX;
    f.fdid = cfg.fdid;
    f.fh[0] = cfg.fh_byte0;

    if (inj_empty || (carry_g.size() == 0 && cfg.pol.empty_flit_pct != 0 &&
                      $urandom_range(0, 99) < cfg.pol.empty_flit_pct)) begin
      inj_empty = 1'b0;
      apply_inj(f);
      return f;
    end

    if (carry_g.size() > 0) begin
      foreach (carry_g[i]) f.g[i] = carry_g[i];
      f.carry_in = carry_g.size();
      gp = carry_g.size();
      carry_g.delete();
      carry_msg = null;
    end

    if (gp == 0 && lnk.out_q.size() > 0 && lnk.state != AOU_LS_ERROR &&
        !(cfg.act_req_after_grant && lnk.grant_due && adv_any())) begin
      aou_msg_act a = lnk.out_q.pop_front();
      place(f, a, 0);
      lnk.on_sent(a);
      gp = a.num_granules();
      nmsgs++;
      alone = 1'b1;   // v0.8 4.4: nothing else in an Activation's flit
    end

    if (meth == AOU_CRM_MIXED) meth = aou_cred_method_e'($urandom_range(0, 2));
    if (adv_any() && !alone && lnk.grant_due && gp + 2 <= AOU_GRANULES) begin
      aou_msg_crdtgrant g = mk_grant();
      lnk.grant_due = 1'b0;
      if (g != null) begin
        place(f, g, gp);
        gp += 2;
        nmsgs++;
        misc_half[(gp - 2) / AOU_HALF_G]++;
      end
    end
    if (adv_any() && !lnk.grant_due) begin
      bit [15:0] mc;
      if (meth != AOU_CRM_GRANT &&
          crd.take_hdr(mc, lnk.can_advertise(1'b0), lnk.can_advertise(1'b1)))
        f.msg_credit = mc;
      if ((meth == AOU_CRM_GRANT || (cfg.pol.cred_method == AOU_CRM_MIXED &&
                                     $urandom_range(0, 3) == 0)) &&
          !alone && carry_g.size() == 0 && gp < AOU_GRANULES &&
          misc_half[gp / AOU_HALF_G] < cfg.pol.misc_per_half_max) begin
        aou_msg_crdtgrant g = mk_grant();
        if (g != null) begin
          misc_half[gp / AOU_HALF_G]++;
          place(f, g, gp);
          gp += 2;
          nmsgs++;
        end
      end
    end

    while (!alone && gp < AOU_GRANULES && carry_g.size() == 0) begin
      int idx;
      aou_msg m;
      int unsigned len;
      int unsigned sg = gp;
      if (cfg.pol.max_msgs_per_flit != 0 && nmsgs >= cfg.pol.max_msgs_per_flit) break;
      if (cfg.pol.hole_pct != 0 && $urandom_range(0, 99) < cfg.pol.hole_pct)
        sg += $urandom_range(1, cfg.pol.max_hole);
      if (first_new && cfg.pol.start_granule >= 0 && sg <= cfg.pol.start_granule)
        sg = cfg.pol.start_granule;
      if (sg >= AOU_GRANULES) break;
      idx = pick(misc_half[sg / AOU_HALF_G]);
      if (idx < 0) break;
      m = (idx == NQ) ? misc_q[0] : q[idx][0];
      len = m.num_granules();
      if (cfg.pol.best_fit && sg + len > AOU_GRANULES) begin
        int alt = pick_fit(misc_half[sg / AOU_HALF_G], AOU_GRANULES - sg);
        if (alt >= 0) begin
          idx = alt;
          m = (idx == NQ) ? misc_q[0] : q[idx][0];
          len = m.num_granules();
        end
      end
      if (cfg.pol.split_at > 0 && len > cfg.pol.split_at &&
          sg <= AOU_GRANULES - cfg.pol.split_at)
        sg = AOU_GRANULES - cfg.pol.split_at;
      if (!cfg.pol.allow_span && sg + len > AOU_GRANULES) break;
      if (idx == NQ) begin
        void'(misc_q.pop_front());
        void'(misc_s.pop_front());
        misc_half[sg / AOU_HALF_G]++;
      end else begin
        void'(q[idx].pop_front());
        void'(qs[idx].pop_front());
        void'(wf_tgt[idx].pop_front());
      end
      place(f, m, sg);
      gp = sg + len;
      nmsgs++;
      first_new = 1'b0;
    end
    for (int unsigned z = 0; z < cfg.pol.zero_grants; z++) begin
      aou_msg_crdtgrant zg;
      // A CrdtGrant, even an empty one, only once we may advertise (AOU-R29).
      if (alone || !adv_any() || lnk.grant_due || carry_g.size() > 0 || gp + 2 > AOU_GRANULES ||
          misc_half[gp / AOU_HALF_G] >= cfg.pol.misc_per_half_max) break;
      zg = aou_msg_crdtgrant::type_id::create("zg");
      misc_half[gp / AOU_HALF_G]++;
      place(f, zg, gp);
      gp += 2;
    end
    apply_inj(f);
    return f;
  endfunction

  function void apply_inj(aou_flit f);
    if (inj_flip_start >= 0) begin
      f.msg_start[inj_flip_start] = ~f.msg_start[inj_flip_start];
      inj_flip_start = -1;
    end
    if (inj_fdid >= 0) begin
      f.fdid = 2'(inj_fdid);
      inj_fdid = -1;
    end
    if (inj_hdr_rsvd >= 0) begin
      f.hdr_rsvd = 14'(inj_hdr_rsvd);
      inj_hdr_rsvd = -1;
    end
    if (inj_msg_credit >= 0) begin
      f.msg_credit = 16'(inj_msg_credit);
      inj_msg_credit = -1;
    end
  endfunction
endclass
