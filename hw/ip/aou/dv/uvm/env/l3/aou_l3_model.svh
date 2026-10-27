// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die's protocol layer without any component plumbing, so unit
// tests can drive it directly and two instances can talk to each other.
// rx_flit() takes a DUT flit; get_tx_flit() blocks until a flit to the DUT
// is ready. Decoded DUT messages queue on rx_q; consumers dequeue them with
// consume(), which frees their granules in the modelled RX buffer.
class aou_l3_model extends uvm_object;
  `uvm_object_utils(aou_l3_model)

  aou_l3_cfg      cfg;
  aou_l3_rule_chk chk;
  aou_credit_mgr  crd;
  aou_link_ctrl   lnk;
  aou_packer      pk;
  aou_unpacker    rx_unp;
  aou_unpacker    tx_unp;
  aou_l3_cov      cov;

  uvm_event       work_ev;
  int unsigned    work_gen;
  aou_msg         rx_q[$];
  uvm_event       rx_ev;
  aou_msg         tx_sent_q[$];      // messages placed in flits, for ap_tx_msg
  aou_flit        tx_flit_q[$];      // flits built, for ap_tx_flit

  // Outstanding requests are indexed by our plane. Messages we send carry the
  // DUT's plane (dest_rp[our plane], MAS 3.10.2); messages the DUT sends carry
  // ours, since the DUT's DEST_RP is the inverse map.
  // Requests we issued and still await a response for, per RP.
  int unsigned    our_wr_out[AOU_RP_MAX];
  int unsigned    our_rd_out[AOU_RP_MAX];
  // ARSIZE of our ReadReqs per (RP, ID), for AOU-R13.
  bit [2:0]       our_rd_size[int][$];
  // DUT requests we still owe a response for, per RP (AOU-R33).
  int unsigned    dut_wr_out[AOU_RP_MAX];
  int unsigned    dut_rd_out[AOU_RP_MAX];
  // Of those, the ones received once our DeactivateReq was queued and before
  // the DUT's: the DUT may still send requests then (8.4), and must wait for
  // their answers before its DeactivateReq. Counted apart so an AOU-R33
  // report says which kind it was. Responses come off these first, so they
  // never include a request we had before that point.
  int unsigned    dut_wr_late[AOU_RP_MAX];
  int unsigned    dut_rd_late[AOU_RP_MAX];

  int unsigned    tx_flits;
  int unsigned    rx_flits;
  int unsigned    rx_msgs;
  int unsigned    tx_msgs;
  int             grant_epoch = -1;  // lnk.epoch of the DUT's last CrdtGrant
  // The flit being received carries the DUT's DeactivateAck (peer_adv_ok).
  bit             dut_dack_flit;
  string          name_tag = "remote";

  function new(string name = "aou_l3_model");
    super.new(name);
    work_ev = new("work_ev");
    rx_ev = new("rx_ev");
  endfunction

  function void build(aou_l3_cfg c);
    cfg = c;
    chk = c.chk;
    crd = aou_credit_mgr::type_id::create("crd");
    lnk = aou_link_ctrl::type_id::create("lnk");
    pk = aou_packer::type_id::create("pk");
    rx_unp = aou_unpacker::type_id::create("rx_unp");
    tx_unp = aou_unpacker::type_id::create("tx_unp");
    if (c.cov_en) cov = aou_l3_cov::type_id::create("cov");
    crd.cfg = c;
    lnk.cfg = c;
    lnk.crd = crd;
    lnk.cov = cov;
    pk.cfg = c;
    pk.crd = crd;
    pk.lnk = lnk;
    rx_unp.cfg = c;
    rx_unp.chk = chk;
    rx_unp.dir = AOU_L3_RX;
    tx_unp.cfg = c;
    tx_unp.chk = chk;
    tx_unp.dir = AOU_L3_TX;
    crd.reset_link();
  endfunction

  function void ledger_chk(string rule);
    aou_rule_log::check(rule, get_type_name());
  endfunction

  function void viol(string rule, string msg);
    chk.violation(rule, get_type_name(), $sformatf("[%s] %s", name_tag, msg));
  endfunction

  function void kick();
    work_gen++;
    work_ev.trigger();
  endfunction

  // ---- API -------------------------------------------------------------
  function void send(aou_msg m);
    aou_msg_act a;
    if ($cast(a, m)) a.spec_rev = cfg.spec_rev;
    pk.push(m);
    kick();
  endfunction

  function void consume(aou_msg m);
    aou_cred_class_e c = m.cred_class();
    if (c != AOU_CC_NONE) crd.rx_consume(int'(m.rp), c, m.num_granules());
    kick();
  endfunction

  function void release_withheld();
    crd.release_withheld();
    kick();
  endfunction

  task activate();
    lnk.request_activate();
    kick();
    lnk.wait_state(AOU_LS_ENABLED);
  endtask

  task deactivate();
    lnk.request_deactivate();
    maybe_release_deact();
    lnk.wait_state(AOU_LS_DISABLED);
  endtask

  // Back to DISABLED with nothing in flight: the link was reset under us (or
  // ERROR recovery). Queued messages, the modelled RX buffer, request
  // tracking and credits are all dropped.
  function void recover();
    pk.flush();
    if (cov != null) cov.reset_wr_order();
    pk.carry_g.delete();
    tx_sent_q.delete();
    tx_flit_q.delete();
    rx_q.delete();
    our_rd_size.delete();
    foreach (our_wr_out[r]) begin
      our_wr_out[r] = 0;
      our_rd_out[r] = 0;
      dut_wr_out[r] = 0;
      dut_rd_out[r] = 0;
      dut_wr_late[r] = 0;
      dut_rd_late[r] = 0;
    end
    foreach (crd.rx_occupancy[r, c]) crd.rx_occupancy[r][c] = 0;
    lnk.recover();
    rx_unp.reset();
    tx_unp.reset();
    kick();
  endfunction

  function int unsigned our_requests_outstanding();
    int unsigned n = pk.queued_msgs();
    foreach (our_wr_out[r]) n += our_wr_out[r] + our_rd_out[r];
    return n;
  endfunction

  // Our DeactivateReq is queued or sent and the DUT's has not arrived.
  function bit deact_committed();
    return (lnk.dreq_sent || lnk.queued(AOU_DEACT_REQ)) && !lnk.dreq_rcvd;
  endfunction

  function void maybe_release_deact();
    if (lnk.want_deact &&
        (cfg.deact_own_open ? pk.queued_msgs() == 0 : our_requests_outstanding() == 0)) begin
      lnk.release_deact();
      kick();
    end
  endfunction

  // ---- TX --------------------------------------------------------------
  task get_tx_flit(output aou_flit f);
    forever begin
      int unsigned g = work_gen;
      if (pk.has_work()) begin
        f = pk.build();
        post_tx(f);
        return;
      end
      while (g == work_gen) work_ev.wait_trigger();
    end
  endtask

  function void post_tx(aou_flit f);
    tx_flits++;
    tx_unp.unpack(f);
    foreach (f.msgs[i]) begin
      aou_msg m = f.msgs[i];
      aou_msg_act a;
      // Each Req we send is a request the DUT must answer (checked at the end).
      if ($cast(a, m) && a.op == AOU_ACT_REQ) ledger_chk("AOU-R28");
      if ($cast(a, m) && a.op == AOU_DEACT_REQ) ledger_chk("AOU-R36");
      tx_msgs++;
      tx_sent_q.push_back(m);
      track_tx(m);
      if (cov != null) begin
        cov.sample_msg(m);
        cov.sample_tx_write(m);
        if (m.cred_class() != AOU_CC_NONE)
          cov.sample_credit(aou_l3_cov::EV_CONSUME, m.cred_class(), AOU_L3_TX);
        if (m.cred_class() != AOU_CC_NONE && m.ignore_credits)
          cov.sample_credit(aou_l3_cov::EV_INJ_OVERFLOW, m.cred_class(), AOU_L3_TX);
      end
    end
    if (cov != null) begin
      cov.sample_flit(f, misc_in_half(f, 0), misc_in_half(f, 1));
      sample_grants(f, AOU_L3_TX);
      sample_overgrant();
      if (pk.credit_stalls != 0) begin
        foreach (pk.q[i]) begin
          if (pk.q[i].size() > 0 && !pk.eligible(pk.q[i][0]))
            cov.sample_credit(aou_l3_cov::EV_ZERO_STALL, pk.q[i][0].cred_class(), AOU_L3_TX);
        end
      end
    end
    tx_flit_q.push_back(f);
    void'(crd.tick());
    maybe_release_deact();
  endfunction

  // Our plane p with cfg.dest_rp[p] == wire_rp (identity when none matches).
  function int unsigned our_plane(bit [1:0] wire_rp);
    int unsigned plane = {30'd0, wire_rp};
    for (int p = AOU_RP_MAX - 1; p >= 0; p--) if (cfg.dest_rp[p] == wire_rp) plane = p;
    return plane;
  endfunction

  function void track_tx(aou_msg m);
    aou_msg_req rq;
    aou_msg_rdata rd;
    int unsigned p = our_plane(m.rp);
    case (m.msg_type)
      AOU_MT_WREQ: our_wr_out[p]++;
      AOU_MT_RREQ: begin
        our_rd_out[p]++;
        if ($cast(rq, m)) our_rd_size[int'(p) * 1024 + int'(rq.id)].push_back(rq.size);
      end
      AOU_MT_WRESP: begin
        if (dut_wr_out[p] > 0) dut_wr_out[p]--;
        if (dut_wr_late[p] > 0) dut_wr_late[p]--;
      end
      AOU_MT_RDATA: begin
        if ($cast(rd, m) && rd.last) begin
          if (dut_rd_out[p] > 0) dut_rd_out[p]--;
          if (dut_rd_late[p] > 0) dut_rd_late[p]--;
        end
      end
      default: ;
    endcase
  endfunction

  static function int unsigned misc_in_half(aou_flit f, int unsigned h);
    int unsigned n = 0;
    foreach (f.msgs[i]) begin
      if (f.msgs[i].is_misc() && f.msgs[i].start_flit == int'(f.seq) &&
          f.msgs[i].start_granule / AOU_HALF_G == int'(h)) n++;
    end
    return n;
  endfunction

  // Credit we advertised beyond our buffer: an over-grant the DUT must absorb.
  bit overgrant_seen[AOU_RP_MAX][AOU_CC_NUM];
  function void sample_overgrant();
    for (int unsigned r = 0; r < cfg.rp_count; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        bit over = crd.rx_outstanding[r][c] > cfg.rx_depth[c];
        if (over && !overgrant_seen[r][c])
          cov.sample_credit(aou_l3_cov::EV_DUT_SATURATE, aou_cred_class_e'(c), AOU_L3_TX);
        overgrant_seen[r][c] = over;
      end
    end
  endfunction

  function void sample_grants(aou_flit f, aou_l3_dir_e dir);
    int unsigned hr;
    int unsigned hn[AOU_CC_NUM];
    bit has_grant = 1'b0;
    aou_msg_crdtgrant cg;
    aou_credit_mgr::hdr_decode(f.msg_credit, hr, hn);
    foreach (f.msgs[i]) begin
      if ($cast(cg, f.msgs[i])) begin
        has_grant = 1'b1;
        for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
          if (cg.enc[0][c] != 0)
            cov.sample_credit(aou_l3_cov::EV_CRDT_GRANT, aou_cred_class_e'(c), dir);
          if (cg.enc[hr][c] != 0 && hn[c] != 0)
            cov.sample_credit(aou_l3_cov::EV_BOTH, aou_cred_class_e'(c), dir);
        end
      end
    end
    for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
      if (hn[c] != 0) cov.sample_credit(aou_l3_cov::EV_HDR_GRANT, aou_cred_class_e'(c), dir);
    end
  endfunction

  // ---- RX --------------------------------------------------------------
  function void rx_flit(aou_flit f);
    aou_msg_act a;
    aou_msg_crdtgrant cg;
    f.dir = AOU_L3_RX;
    f.seq = rx_flits++;
    if (lnk.state == AOU_LS_ERROR) return;   // ERROR ignores everything (v0.8)
    rx_unp.unpack(f);
    f.msgs = rx_unp.done;

    // 1. Activation messages: at G0, so before everything else in the flit.
    dut_dack_flit = 1'b0;
    foreach (rx_unp.done[i]) begin
      if ($cast(a, rx_unp.done[i])) rx_act(a);
    end
    // 2. Credits: header MsgCredit and any CrdtGrant add up (6.4).
    if (f.msg_credit != 0) rx_hdr_credit(f.msg_credit);
    foreach (rx_unp.done[i]) begin
      if ($cast(cg, rx_unp.done[i])) rx_grant(cg);
    end
    // 3. Credited messages starting here consume credit at their start (6.1).
    foreach (rx_unp.st_g0[i]) rx_start(rx_unp.st_g0[i], rx_unp.st_pos[i], rx_unp.st_len[i], f);
    // 4. Deliver complete messages.
    foreach (rx_unp.done[i]) rx_deliver(rx_unp.done[i]);
    if (cov != null) begin
      cov.sample_flit(f, misc_in_half(f, 0), misc_in_half(f, 1));
      sample_grants(f, AOU_L3_RX);
    end
    void'(crd.tick());
    lnk.tick_dack_hold();
    maybe_release_deact();
    kick();
  endfunction

  function void rx_act(aou_msg_act a);
    if (a.op > 4'd3) return;
    ledger_chk("AOU-R40");
    // The DeactivateReq DEACTIVATE_FORCE sends skips this condition by design
    // (MAS software-operation 7.1); it is recognised by the RTL's PropertyReq
    // mark inside the force window.
    if (a.op == AOU_DEACT_REQ && cfg.chk_deact_quiesce &&
        !(a.forced_deact_mark() && cfg.force_deact_window())) begin
      ledger_chk("AOU-R33");
      for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
        if (dut_wr_out[r] != 0 || dut_rd_out[r] != 0) begin
          string s = $sformatf("DeactivateReq: %0d write(s), %0d read(s) on RP%0d unanswered",
                               dut_wr_out[r], dut_rd_out[r], r);
          if (dut_wr_late[r] != 0 || dut_rd_late[r] != 0)
            s = {s, $sformatf(" (%0d write(s), %0d read(s) received after our DeactivateReq)",
                              dut_wr_late[r], dut_rd_late[r])};
          viol("AOU-R33", s);
        end
      end
    end
    if (a.op == AOU_DEACT_REQ) begin
      foreach (dut_wr_late[r]) begin
        dut_wr_late[r] = 0;
        dut_rd_late[r] = 0;
      end
    end
    if (!lnk.on_rcvd(a))
      viol("AOU-R40", $sformatf("DUT %s while %s", a.kind(), lnk.state.name()));
    else if (a.op == AOU_DEACT_ACK)
      dut_dack_flit = 1'b1;
  endfunction

  // Credits may come from the DUT after its ActivateAck and until DISABLED
  // (8.4), of every class: request credits after its DeactivateAck (8.4), and
  // response credits too, which fund the answers to the DUT's own open
  // requests (MAS 7.3.1; v0.8 is silent on them). WriteData counts as a
  // request class (interim: 8.4 does not say). A flit's credits are consumed
  // with the flit (MAS 7.3.1), so the flit carrying the DeactivateAck that
  // completes the teardown may still carry them; they are discarded.
  static function bit req_class(aou_cred_class_e c);
    return c inside {AOU_CC_WREQ, AOU_CC_RREQ, AOU_CC_WDATA};
  endfunction

  function bit peer_adv_ok(aou_cred_class_e c, output string why);
    why = "";
    if (lnk.state == AOU_LS_DISABLED) begin
      if (!dut_dack_flit) why = "in DISABLED";
    end else if (!lnk.ack_rcvd) why = "before its ActivateAck";
    return why == "";
  endfunction

  // A permitted credit that funds our counters: request credits after the
  // DUT's DeactivateAck are useless to us (our DeactivateReq preceded it).
  // None funds in DISABLED: the flit whose DeactivateAck completed the
  // teardown is handled after the counters were reset, and its credits would
  // otherwise carry into the next activation.
  function bit peer_adv_funds(aou_cred_class_e c);
    if (lnk.state == AOU_LS_DISABLED) return 1'b0;
    return !(req_class(c) && (lnk.dack_rcvd || dut_dack_flit));
  endfunction

  function void rx_hdr_credit(bit [15:0] mc);
    int unsigned r;
    int unsigned n[AOU_CC_NUM];
    string why;
    aou_credit_mgr::hdr_decode(mc, r, n);
    if (r >= cfg.eff_rp_count()) return;   // beyond the DUT's count: AOU-R14 (unpacker)
    foreach (n[c]) begin
      if (n[c] != 0) begin
        ledger_chk("AOU-R26");
        ledger_chk("AOU-R29");
        if (!peer_adv_ok(aou_cred_class_e'(c), why)) begin
          viol(why == "before its ActivateAck" ? "AOU-R29" : "AOU-R26",
               $sformatf("DUT MsgCredit %s RP%0d=%0d %s", aou_cc_name(aou_cred_class_e'(c)), r,
                         n[c], why));
        end else if (peer_adv_funds(aou_cred_class_e'(c))) begin
          rx_tx_grant(r, aou_cred_class_e'(c), n[c]);
        end
      end
    end
  endfunction

  function void rx_grant(aou_msg_crdtgrant g);
    string why;
    bit first = grant_epoch != int'(lnk.epoch) && lnk.ack_rcvd;
    if (lnk.ack_rcvd) grant_epoch = lnk.epoch;
    for (int unsigned r = 0; r < cfg.eff_rp_count(); r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        int unsigned n = g.get_cred(r, aou_cred_class_e'(c));
        if (first) ledger_chk("AOU-R24");
        if (n != 0) begin
          ledger_chk("AOU-R26");
          ledger_chk("AOU-R29");
        end
        if (first && n == 0)
          viol("AOU-R24", $sformatf("DUT initial CrdtGrant has no %s credit for RP%0d",
                                    aou_cc_name(aou_cred_class_e'(c)), r));
        if (n != 0) begin
          if (!peer_adv_ok(aou_cred_class_e'(c), why))
            viol(why == "before its ActivateAck" ? "AOU-R29" : "AOU-R26",
                 $sformatf("DUT CrdtGrant %s RP%0d=%0d %s", aou_cc_name(aou_cred_class_e'(c)),
                           r, n, why));
          else if (peer_adv_funds(aou_cred_class_e'(c)))
            rx_tx_grant(r, aou_cred_class_e'(c), n);
        end
      end
    end
  endfunction

  // T1-C40: the DUT never holds out more credit than its RX FIFO has room for.
  function void rx_tx_grant(int unsigned r, aou_cred_class_e c, int unsigned n);
    int unsigned mx = cfg.dut_max_cred[r][c];
    if (crd.tx_grant(r, c, n) && cov != null)
      cov.sample_credit(aou_l3_cov::EV_SATURATE, c, AOU_L3_RX);
    if (mx == 0) return;
    ledger_chk("T1-C40");
    if (crd.tx_cred[r][c] > mx)
      viol("T1-C40", $sformatf("DUT advertised %0d %s credits on RP%0d, MAS 3.9 maximum %0d",
                               crd.tx_cred[r][c], aou_cc_name(c), r, mx));
  endfunction

  localparam int unsigned DUT_STALL_TICKS = 8;
  function void rx_start(aou_granule_t g0, int unsigned pos, int unsigned len, aou_flit f);
    bit [3:0] mt = g0[39:36];
    bit [1:0] r = g0[35:34];
    aou_cred_class_e c = aou_cred_class_of(mt);
    bit open;
    int unsigned have;
    if (c == AOU_CC_NONE || int'(r) >= cfg.eff_rp_count()) return;
    open = lnk.req_rcvd && lnk.ack_sent && lnk.state != AOU_LS_DISABLED;
    ledger_chk("AOU-R16");
    ledger_chk("AOU-R26");
    ledger_chk("AOU-R30");
    if (c inside {AOU_CC_WREQ, AOU_CC_RREQ}) ledger_chk("AOU-R34");
    if (!open) begin
      viol(lnk.state == AOU_LS_DISABLED ? "AOU-R26" : "AOU-R30",
           $sformatf("DUT %s at flit#%0d G%0d while %s (its ActivateReq %0s, our Ack %0s)",
                     aou_cc_name(c), f.seq, pos, lnk.state.name(),
                     lnk.req_rcvd ? "seen" : "not seen", lnk.ack_sent ? "sent" : "not sent"));
    end else if (c inside {AOU_CC_WREQ, AOU_CC_RREQ} && lnk.dreq_rcvd) begin
      viol("AOU-R34", $sformatf("DUT %s at flit#%0d G%0d after its DeactivateReq",
                                aou_cc_name(c), f.seq, pos));
    end
    // A DUT message within a few flits of the grant that ended its zero
    // credit: the DUT was waiting for that credit.
    if (crd.rx_starved[r][c]) begin
      if (cov != null && crd.tick_now - crd.rx_starved_tick[r][c] <= DUT_STALL_TICKS)
        cov.sample_credit(aou_l3_cov::EV_DUT_ZERO_STALL, c, AOU_L3_RX);
      crd.rx_starved[r][c] = 1'b0;
    end
    // rx_receive() floors the counter at zero on an overflow.
    have = crd.rx_outstanding[r][c];
    if (!crd.rx_receive(int'(r), c, len)) begin
      viol("AOU-R16", $sformatf("DUT %s on RP%0d at flit#%0d G%0d needs %0d credits, has %0d",
                                aou_cc_name(c), r, f.seq, pos, len, have));
      if (cov != null) cov.sample_credit(aou_l3_cov::EV_OVERFLOW, c, AOU_L3_RX);
    end else if (cov != null) begin
      cov.sample_credit(aou_l3_cov::EV_CONSUME, c, AOU_L3_RX);
    end
  endfunction

  function void rx_deliver(aou_msg m);
    aou_msg_rdata rd;
    rx_msgs++;
    if (cov != null) cov.sample_msg(m);
    begin
      case (m.msg_type)
        AOU_MT_WREQ: begin
          dut_wr_out[m.rp]++;
          if (deact_committed()) dut_wr_late[m.rp]++;
        end
        AOU_MT_RREQ: begin
          dut_rd_out[m.rp]++;
          if (deact_committed()) dut_rd_late[m.rp]++;
        end
        AOU_MT_WRESP: if (our_wr_out[m.rp] > 0) our_wr_out[m.rp]--;
        AOU_MT_RDATA: if ($cast(rd, m)) rx_rdata(rd);
        default: ;
      endcase
    end
    rx_q.push_back(m);
    rx_ev.trigger();
  endfunction

  // ReadData DLENGTH matches the ARSIZE of the ReadReq it answers (5.7).
  function void rx_rdata(aou_msg_rdata rd);
    int key = int'(rd.rp) * 1024 + int'(rd.id);
    if (our_rd_size.exists(key) && our_rd_size[key].size() > 0) begin
      bit [1:0] exp = aou_dl_for_size(our_rd_size[key][0]);
      ledger_chk("AOU-R13");
      if (rd.dlength != exp)
        viol("AOU-R13", $sformatf("DUT ReadData%0d for RP%0d ID %0h, ARSIZE %0d needs ReadData%0d",
                                  aou_dl_bits(rd.dlength), rd.rp, rd.id, our_rd_size[key][0],
                                  aou_dl_bits(exp)));
      if (rd.last) void'(our_rd_size[key].pop_front());
    end
    if (rd.last && our_rd_out[rd.rp] > 0) our_rd_out[rd.rp]--;
  endfunction

  // AOU-R31 once nothing is outstanding: the DUT has had cred_return_cycles to
  // return every credit; ready is 0 while the check does not apply.
  function bit cred_return_ready();
    return cfg.chk_cred_return && lnk.state == AOU_LS_ENABLED &&
           our_requests_outstanding() == 0 && rx_q.size() == 0;
  endfunction

  function void check_cred_return(int unsigned waited);
    string why;
    ledger_chk("AOU-R31");
    if (crd.tx_short(why) != 0)
      viol("AOU-R31", $sformatf("credits not returned %0d cycles after quiescence:%s", waited,
                                why));
    // T1-C40: and that is all the credit the RX FIFO allows (MAS 3.9).
    for (int unsigned r = 0; r < cfg.rp_count; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        if (cfg.dut_max_cred[r][c] == 0) continue;
        ledger_chk("T1-C40");
        if (crd.tx_full[r][c] != cfg.dut_max_cred[r][c])
          viol("T1-C40", $sformatf("DUT advertised %0d %s credits on RP%0d when quiescent, %s %0d",
                                   crd.tx_full[r][c], aou_cc_name(aou_cred_class_e'(c)), r,
                                   "MAS 3.9 gives", cfg.dut_max_cred[r][c]));
      end
    end
  endfunction

  // End-of-test checks: handshakes the DUT left unanswered.
  function void check_end();
    if (!cfg.chk_end_state) return;
    if (lnk.req_sent && !lnk.ack_rcvd && lnk.state == AOU_LS_ACTIVATE)
      viol("AOU-R28", "DUT never answered our ActivateReq");
    if (lnk.dreq_sent && !lnk.dack_rcvd && lnk.state == AOU_LS_DEACTIVATE)
      viol("AOU-R36", "DUT never answered our DeactivateReq");
    if (lnk.enabled_cnt > 0 && grant_epoch < 0)
      viol("AOU-R24", "DUT sent no CrdtGrant after its ActivateAck");
  endfunction
endclass
