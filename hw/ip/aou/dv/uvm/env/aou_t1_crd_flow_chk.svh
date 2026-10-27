// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credit flow on the DUT's TX side, in every test (AoU v0.7 chapter 6: credit
// is per RP and class; MAS 3.9).
//
// Per local RP x and credit class c the checker tracks whether the DUT has
// work of class c for x at its TX input, from the AXI pins:
//   WREQ   an S-port AW accepted and not yet sent as a WriteReq (matched by
//          ID), its write data accepted or presented; or an AW and W presented
//          while x has no write in flight (no outstanding limit can apply). A
//          write answered early is still in flight: with EARLY_BRESP_EN set it
//          holds an early-table entry until the remote die's actual B, and
//          with the table full the DUT takes no AW (MAS 3.7.5);
//   RREQ   an S-port AR accepted and not yet sent as a ReadReq; or an AR
//          presented while x has no read in flight;
//   WDATA  S-port W presented and not accepted, owed to a write whose
//          WriteReq has been sent: the S port takes W in AW order, so the
//          beats owed to the writes already sent come before those of any
//          later AW still waiting to be sent, which do not count;
//   RDATA  M-port R presented and not accepted; or an M-port read complete
//          (RLAST accepted, no other M-port read of that ID open) whose last
//          ReadData has not been sent;
//   WRESP  M-port B presented and not accepted; or an M-port B accepted, no
//          other M-port write of that ID open, whose WriteResp has not been
//          sent.
// A message the DUT sends ends every pending entry of its ID, the queues
// restart whenever the link closes, and an M-port response counts only for a
// request issued since the link last closed, so a request split into several
// M-port bursts, a response the DUT drops or an orphan beat after a reset
// never counts as work.
// Write work counts only while no other RP's manager is behind with write
// data it owes, since the S ports share one AW/W path that may wait for it.
// x has credit for c when the remote die has advertised at least the largest
// message of c (L3 credit manager, on wire RP DEST_RP[x]); a write also needs
// WDATA credit. x is eligible for c when it has both work and credit, starved
// when it has messages of some class queued (an accepted or presented AW, or
// write data presented, counts without the conditions above) and no credit
// for them.
//
// While the link is open (ENABLED, no deactivation under way, lp_linkerror
// low), counted on the cycles the Adapter takes a beat (PHY Active, pl_trdy
// high) and the DUT has sent no message of another class for busy_cycles, a
// class stalls while some RP is eligible for it and the DUT sends no message
// of the class on any RP:
//   T1-C01 (independent per-RP progress): the stall reaches block_cycles
//          while another RP is starved. One RP without credit must not hold
//          back the others (tenstorrent/tt-oca-harness-aou#97).
//   T1-C02 (work conservation): the stall reaches idle_cycles.
// Each is reported once per stall. The bounds come from the env config
// (crd_block_cycles, crd_idle_cycles); report_phase prints the longest stall
// seen, the margin to tune them by.
//
// Neither notices one RP starving while the same class keeps flowing on the
// others, so each RP and class also has its own wait:
//   T1-C43 (per-RP forward progress): no RP's messages of a class starve while
//          the RP holds credit for them and is next in that class's order.
//          The wait of RP x for class c counts the cycles the Adapter takes a
//          beat on an open link (as above), no AXI port holds the DUT back,
//          and x is eligible for c and at the head of c's order:
//            WDATA  write data follows the order in which the DUT granted the
//                   writes' requests, on a W path the RPs share (MAS 3.2.1):
//                   every WriteReq the DUT sent before x's oldest write still
//                   owing data, on any RP, has had all its WriteData sent. The
//                   DUT's own WriteReq order on the wire is taken as the grant
//                   order.
//            WREQ   no write the DUT has sent, on any RP, still owes WriteData.
//                   Taken from the RTL (PR #98): the S-port aligner lets open
//                   bursts go ahead of a new AW and sends an AW together with
//                   its first W beat, so a WriteReq waits for the data of every
//                   earlier write. MAS 3.2.1 says only that W follows the
//                   granted AW order.
//            others no documented order between RPs; eligibility alone.
//          The DUT is held back when, on any RP, one of its M-port AW, W or AR
//          channels or its S-port R or B channel has VALID high and READY low.
//          Sustained backpressure is a stress case in which the DUT must stay
//          correct, not fast, so those cycles do not count. This also covers a
//          remote request the DUT splits into several M-port bursts: between
//          pieces no M-port transaction of the ID is open, so its response
//          looks owed while the next piece's AW or AR waits for READY. The
//          same holds while an M-port ID mismatch is reported and not cleared:
//          the DUT then holds all credited traffic on purpose (PR #26, see
//          aou_t1_crd_block_chk). Any other cycle pauses the wait; a message of class c the DUT sends on
//          x's wire RP, a reset, DISABLED or a new activation restarts it.
//          A wait that reaches
//          starve_cycles (env cfg crd_starve_cycles) is reported once. The wait
//          covers sharing the TX with the other RPs and classes; the bound
//          catches an RP that is passed over, not slow service.
typedef class aou_t1_crd_block_chk;
typedef class aou_t1_early_tbl_chk;

class aou_t1_crd_flow_chk extends uvm_component;
  `uvm_component_utils(aou_t1_crd_flow_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_crd_flow_chk) rx_msg_imp;

  aou_t1_env_cfg  cfg;
  aou_l3_model    model;
  aou_core        rm;
  aou_axi_vif_t   s_vif[];
  aou_axi_vif_t   m_vif[];
  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[AOU_T1_N_PHY];
  virtual aou_fdi_lsm_if lsm_vif;
  aou_t1_crd_block_chk blk;   // the ID-mismatch hold; null: none
  aou_t1_early_tbl_chk early; // early-table occupancy; null: none
  bit             enable = 1'b1;
  int unsigned    block_cycles = 256;
  int unsigned    idle_cycles = 4096;
  int unsigned    starve_cycles = 500;
  // Two flits on the narrowest (32-byte) FDI path.
  int unsigned    busy_cycles = 16;

  // Sampled values of cg_crd.
  int unsigned s_cls, s_ev;

  covergroup cg_crd;
    cp_cls: coverpoint s_cls {
      `AOU_T1_CRD_FC_CLS(AOU_FC_CG)
    }
    cp_ev: coverpoint s_ev {
      `AOU_T1_CRD_FC_EV(AOU_FC_CG)
    }
    x_cls_ev: cross cp_cls, cp_ev;
  endgroup
  aou_fc_group fc_crd;

  int unsigned longest[AOU_CC_NUM];
  int unsigned n_c01;
  int unsigned n_c02;
  int unsigned n_c43;
  // Longest per-RP wait per class (T1-C43) and the local RP that had it.
  int unsigned longest_rp_wait[AOU_CC_NUM];
  int unsigned longest_rp[AOU_CC_NUM];
  time         longest_at[AOU_CC_NUM];

  // S-port requests accepted and not yet sent, then sent and not yet answered.
  protected bit [9:0]    aw_pend[AOU_RP_MAX][$];
  protected bit [9:0]    ar_pend[AOU_RP_MAX][$];
  protected bit [9:0]    aw_sent[AOU_RP_MAX][$];
  protected bit [9:0]    ar_sent[AOU_RP_MAX][$];
  // M-port responses accepted and not yet sent as WriteResp / last ReadData,
  // and M-port writes and reads open per ID.
  protected bit [9:0]    b_pend[AOU_RP_MAX][$];
  protected bit [9:0]    r_pend[AOU_RP_MAX][$];
  protected int unsigned m_wr_out[AOU_RP_MAX][1024];
  protected int unsigned m_rd_out[AOU_RP_MAX][1024];
  protected int unsigned wr_fly[AOU_RP_MAX];
  protected int unsigned rd_fly[AOU_RP_MAX];
  protected int unsigned w_need[AOU_RP_MAX];
  protected int unsigned w_got[AOU_RP_MAX];
  // Beats of each AW in aw_pend, and their sum: w_need less pend_beats is the
  // data of the accepted writes no longer waiting to be sent (sent, answered,
  // or forgotten when the link closed).
  protected int unsigned aw_pend_beats[AOU_RP_MAX][$];
  protected int unsigned pend_beats[AOU_RP_MAX];
  protected bit          sent[AOU_CC_NUM];
  protected longint unsigned cyc;
  protected longint unsigned last_msg[AOU_CC_NUM];
  protected int unsigned stall[AOU_CC_NUM];
  protected bit          rep[AOU_CC_NUM];
  protected bit          was_starved[AOU_RP_MAX][AOU_CC_NUM];
  protected bit          was_beside[AOU_RP_MAX][AOU_CC_NUM];
  // T1-C43: each RP's wait per class and whether it was reported.
  protected int unsigned rp_wait[AOU_RP_MAX][AOU_CC_NUM];
  protected bit          rp_rep[AOU_RP_MAX][AOU_CC_NUM];
  // The writes the DUT has sent whose WriteData is still owed, in the order
  // of their WriteReqs on the wire: wire RP and beats owed. Bounded by the
  // writes the DUT has outstanding.
  protected int unsigned w_ord_rp[$];
  protected int unsigned w_ord_owed[$];
  protected int unsigned epoch;

  function new(string name, uvm_component parent);
    aou_fc_db db;
    aou_fc_point p;
    bit fresh;
    super.new(name, parent);
    rx_msg_imp = new("rx_msg_imp", this);
    cg_crd = new();
    db = aou_fc_db::get();
    fc_crd = db.group("env.cg_crd_flow", fresh);
    if (fresh) begin
      p = fc_crd.cp("cp_cls"); `AOU_T1_CRD_FC_CLS(AOU_FC_REG)
      p = fc_crd.cp("cp_ev"); `AOU_T1_CRD_FC_EV(AOU_FC_REG)
      void'(fc_crd.add_cross("x_cls_ev", "cp_cls cp_ev"));
    end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    block_cycles = cfg.crd_block_cycles;
    idle_cycles = cfg.crd_idle_cycles;
    void'($value$plusargs("crd_block_cycles=%d", block_cycles));
    void'($value$plusargs("crd_idle_cycles=%d", idle_cycles));
    starve_cycles = cfg.crd_starve_cycles;
    void'($value$plusargs("crd_starve_cycles=%d", starve_cycles));
  endfunction

  // The wire RP local RP x's messages carry (DEST_RP, register mirror).
  function int unsigned wire_of(int unsigned x);
    uvm_reg_field f;
    if (rm == null) return x;
    f = rm.dest_rp.get_field_by_name($sformatf("rp%0d_dest", x));
    return (f == null) ? x : int'(f.get_mirrored_value());
  endfunction

  // Granules of the largest message of class c the DUT can send for x.
  function int unsigned need(int unsigned x, aou_cred_class_e c);
    int unsigned rb = 32;
    case (c)
      AOU_CC_WREQ, AOU_CC_RREQ: return 3;
      AOU_CC_WRESP: return 1;
      AOU_CC_WDATA: return cfg.rp_bytes[x] <= 32 ? 8 : cfg.rp_bytes[x] <= 64 ? 15 : 30;
      default: begin
        for (int unsigned r = 0; r < cfg.n_rp; r++)
          if (cfg.remote_bytes_of(r) > rb) rb = cfg.remote_bytes_of(r);
        return rb <= 32 ? 8 : rb <= 64 ? 14 : 27;
      end
    endcase
  endfunction

  function bit cred(int unsigned x, aou_cred_class_e c);
    return model.crd.rx_outstanding[wire_of(x)][c] >= need(x, c);
  endfunction

  function bit work(int unsigned x, aou_cred_class_e c);
    case (c)
      AOU_CC_WREQ:
        return others_w_ok(x) &&
               ((aw_pend[x].size() != 0 &&
                 (w_got[x] >= w_need[x] || s_vif[x].mon_cb.wvalid === 1'b1)) ||
                (s_vif[x].mon_cb.awvalid === 1'b1 && s_vif[x].mon_cb.awready !== 1'b1 &&
                 s_vif[x].mon_cb.wvalid === 1'b1 && wr_fly[x] == 0 &&
                 (early == null || early.held(x) == 0)));
      AOU_CC_RREQ:
        return ar_pend[x].size() != 0 ||
               (s_vif[x].mon_cb.arvalid === 1'b1 && s_vif[x].mon_cb.arready !== 1'b1 &&
                rd_fly[x] == 0);
      // The presented beat belongs to a write already sent while the beats
      // of the sent writes are not all taken; a later AW waiting to be sent
      // (it leaves with its first beat, see the header) does not stop them.
      AOU_CC_WDATA:
        return s_vif[x].mon_cb.wvalid === 1'b1 && s_vif[x].mon_cb.wready !== 1'b1 &&
               w_need[x] - pend_beats[x] > w_got[x] && others_w_ok(x);
      AOU_CC_RDATA:
        return (m_vif[x].mon_cb.rvalid === 1'b1 && m_vif[x].mon_cb.rready !== 1'b1) ||
               owed(x, 1'b1);
      default:
        return (m_vif[x].mon_cb.bvalid === 1'b1 && m_vif[x].mon_cb.bready !== 1'b1) ||
               owed(x, 1'b0);
    endcase
  endfunction

  // x has messages of class c queued, whether or not they could leave now:
  // write data presented for an accepted AW counts even before its WriteReq.
  function bit queued(int unsigned x, aou_cred_class_e c);
    if (c == AOU_CC_WDATA)
      return s_vif[x].mon_cb.wvalid === 1'b1 && s_vif[x].mon_cb.wready !== 1'b1 &&
             w_need[x] > w_got[x];
    if (c == AOU_CC_WREQ)
      return aw_pend[x].size() != 0 ||
             (s_vif[x].mon_cb.awvalid === 1'b1 && s_vif[x].mon_cb.awready !== 1'b1);
    return work(x, c);
  endfunction

  // No other RP has accepted a write whose data its manager is not presenting:
  // the S ports share one AW/W path, which may wait for a slow manager.
  function bit others_w_ok(int unsigned x);
    for (int unsigned y = 0; y < cfg.n_rp; y++)
      if (y != x && w_need[y] > w_got[y] && s_vif[y].mon_cb.wvalid !== 1'b1) return 1'b0;
    return 1'b1;
  endfunction

  // Some pending ReadData (rd) or WriteResp of x has no M-port transaction of
  // its ID open any more.
  function bit owed(int unsigned x, bit rd);
    if (rd) begin
      foreach (r_pend[x][i]) if (m_rd_out[x][r_pend[x][i]] == 0) return 1'b1;
    end else begin
      foreach (b_pend[x][i]) if (m_wr_out[x][b_pend[x][i]] == 0) return 1'b1;
    end
    return 1'b0;
  endfunction

  function bit eligible(int unsigned x, aou_cred_class_e c);
    if (!work(x, c) || !cred(x, c)) return 1'b0;
    return c != AOU_CC_WREQ || cred(x, AOU_CC_WDATA);
  endfunction

  // x is next in c's order (T1-C43). Write data: x's oldest write still owing
  // data is the oldest the DUT has sent. A WriteReq: no write the DUT has sent
  // still owes data (from the RTL's aligner, see the header).
  function bit at_head(int unsigned x, aou_cred_class_e c);
    if (c == AOU_CC_WREQ) return w_ord_rp.size() == 0;
    if (c != AOU_CC_WDATA) return 1'b1;
    return w_ord_rp.size() != 0 && w_ord_rp[0] == wire_of(x);
  endfunction

  // Some AXI port holds the DUT back on this edge: an M-port AW, W or AR, or an
  // S-port R or B, the DUT presents and the other side does not take.
  function bit held_back();
    for (int unsigned x = 0; x < cfg.n_rp; x++) begin
      if (m_vif[x].mon_cb.awvalid === 1'b1 && m_vif[x].mon_cb.awready !== 1'b1 ||
          m_vif[x].mon_cb.wvalid === 1'b1 && m_vif[x].mon_cb.wready !== 1'b1 ||
          m_vif[x].mon_cb.arvalid === 1'b1 && m_vif[x].mon_cb.arready !== 1'b1 ||
          s_vif[x].mon_cb.rvalid === 1'b1 && s_vif[x].mon_cb.rready !== 1'b1 ||
          s_vif[x].mon_cb.bvalid === 1'b1 && s_vif[x].mon_cb.bready !== 1'b1)
        return 1'b1;
    end
    return 1'b0;
  endfunction

  // x has work of some class it has no credit for; names it in why.
  function bit starved(int unsigned x, output string why);
    why = "";
    for (int c = 0; c < AOU_CC_NUM; c++) begin
      if (queued(x, aou_cred_class_e'(c)) && !cred(x, aou_cred_class_e'(c))) begin
        why = $sformatf("RP%0d has %s queued without credit (%0d of %0d granules)", x,
                        aou_cc_name(aou_cred_class_e'(c)),
                        model.crd.rx_outstanding[wire_of(x)][c], need(x, aou_cred_class_e'(c)));
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  function void write(aou_msg m);
    aou_msg_req   q;
    aou_msg_wresp b;
    aou_msg_rdata d;
    aou_cred_class_e c = m.cred_class();
    if (c == AOU_CC_NONE) return;
    sent[c] = 1'b1;
    last_msg[c] = cyc;
    if (model != null) link_check();
    w_order(m);
    for (int unsigned x = 0; x < cfg.n_rp; x++) begin
      if (wire_of(x) != int'(m.rp)) continue;
      rp_wait[x][c] = 0;
      rp_rep[x][c] = 1'b0;
      if ($cast(q, m)) begin
        if (c == AOU_CC_WREQ && drop_aw(x, q.id)) begin
          aw_sent[x].push_back(q.id);
          return;
        end
        if (c == AOU_CC_RREQ && drop_id(ar_pend[x], q.id)) begin
          ar_sent[x].push_back(q.id);
          return;
        end
      end else if ($cast(b, m)) begin
        drop_all(b_pend[x], b.id);
      end else if ($cast(d, m) && d.last) begin
        drop_all(r_pend[x], d.id);
      end
    end
  endfunction

  // The W order: a WriteReq joins it, each WriteData pays one beat of the
  // oldest write still owing data on its RP (DP-R10 checks there is one).
  protected function void w_order(aou_msg m);
    aou_msg_req q;
    if (m.msg_type == AOU_MT_WREQ && $cast(q, m)) begin
      w_ord_rp.push_back(int'(m.rp));
      w_ord_owed.push_back(int'(q.len) + 1);
      return;
    end
    if (m.cred_class() != AOU_CC_WDATA) return;
    for (int i = 0; i < w_ord_rp.size(); i++) begin
      if (w_ord_rp[i] != int'(m.rp)) continue;
      w_ord_owed[i]--;
      if (w_ord_owed[i] == 0) begin
        w_ord_rp.delete(i);
        w_ord_owed.delete(i);
      end
      return;
    end
  endfunction

  // Every per-RP wait and the W order restart.
  protected function void forget_waits();
    w_ord_rp.delete();
    w_ord_owed.delete();
    foreach (rp_wait[x, c]) begin
      rp_wait[x][c] = 0;
      rp_rep[x][c] = 1'b0;
    end
  endfunction

  // DISABLED or a new activation ends every open write and every wait. Called
  // from both the message path and the sampling loop, whichever sees it first.
  protected function void link_check();
    if (model.lnk.epoch == epoch && model.lnk.state != AOU_LS_DISABLED) return;
    forget_waits();
    epoch = model.lnk.epoch;
  endfunction

  static function void drop_all(ref bit [9:0] ids[$], input bit [9:0] id);
    for (int i = ids.size() - 1; i >= 0; i--) if (ids[i] == id) ids.delete(i);
  endfunction

  protected function void forget_m(int unsigned x);
    foreach (m_wr_out[x][i]) begin
      m_wr_out[x][i] = 0;
      m_rd_out[x][i] = 0;
    end
  endfunction

  protected function void forget(int unsigned x);
    aw_pend[x].delete();
    aw_pend_beats[x].delete();
    pend_beats[x] = 0;
    ar_pend[x].delete();
    aw_sent[x].delete();
    ar_sent[x].delete();
    b_pend[x].delete();
    r_pend[x].delete();
  endfunction

  // Drops x's oldest AW of this ID waiting to be sent, with its beats.
  protected function bit drop_aw(int unsigned x, bit [9:0] id);
    foreach (aw_pend[x][i]) begin
      if (aw_pend[x][i] == id) begin
        pend_beats[x] -= aw_pend_beats[x][i];
        aw_pend[x].delete(i);
        aw_pend_beats[x].delete(i);
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  static function bit drop_id(ref bit [9:0] ids[$], input bit [9:0] id);
    foreach (ids[i]) begin
      if (ids[i] == id) begin
        ids.delete(i);
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  // Reset contract: every transaction the AXI ports had is gone.
  function void reset_flush();
    for (int unsigned x = 0; x < AOU_RP_MAX; x++) begin
      forget(x);
      forget_m(x);
      wr_fly[x] = 0;
      rd_fly[x] = 0;
      w_need[x] = 0;
      w_got[x] = 0;
    end
    foreach (stall[c]) begin
      stall[c] = 0;
      rep[c] = 1'b0;
    end
    forget_waits();
  endfunction

  // The handshakes of local RP x on this edge.
  protected function void track(int unsigned x);
    if (s_vif[x].mon_cb.resetn !== 1'b1) begin
      forget(x);
      wr_fly[x] = 0;
      rd_fly[x] = 0;
      w_need[x] = 0;
      w_got[x] = 0;
      return;
    end
    if (s_vif[x].mon_cb.awvalid === 1'b1 && s_vif[x].mon_cb.awready === 1'b1) begin
      aw_pend[x].push_back(s_vif[x].mon_cb.awid);
      aw_pend_beats[x].push_back(int'(s_vif[x].mon_cb.awlen) + 1);
      pend_beats[x] += int'(s_vif[x].mon_cb.awlen) + 1;
      wr_fly[x]++;
      w_need[x] += int'(s_vif[x].mon_cb.awlen) + 1;
    end
    if (s_vif[x].mon_cb.wvalid === 1'b1 && s_vif[x].mon_cb.wready === 1'b1) w_got[x]++;
    if (s_vif[x].mon_cb.bvalid === 1'b1 && s_vif[x].mon_cb.bready === 1'b1) begin
      if (!drop_id(aw_sent[x], s_vif[x].mon_cb.bid))
        void'(drop_aw(x, s_vif[x].mon_cb.bid));
      if (wr_fly[x] > 0) wr_fly[x]--;
    end
    if (s_vif[x].mon_cb.arvalid === 1'b1 && s_vif[x].mon_cb.arready === 1'b1) begin
      ar_pend[x].push_back(s_vif[x].mon_cb.arid);
      rd_fly[x]++;
    end
    if (s_vif[x].mon_cb.rvalid === 1'b1 && s_vif[x].mon_cb.rready === 1'b1 &&
        s_vif[x].mon_cb.rlast === 1'b1) begin
      if (!drop_id(ar_sent[x], s_vif[x].mon_cb.rid))
        void'(drop_id(ar_pend[x], s_vif[x].mon_cb.rid));
      if (rd_fly[x] > 0) rd_fly[x]--;
    end
    track_m(x);
  endfunction

  // The M-port handshakes of local RP x on this edge.
  protected function void track_m(int unsigned x);
    if (m_vif[x].mon_cb.resetn !== 1'b1) return;
    if (m_vif[x].mon_cb.awvalid === 1'b1 && m_vif[x].mon_cb.awready === 1'b1)
      m_wr_out[x][m_vif[x].mon_cb.awid]++;
    // A response counts only for a request issued while the link was open: an
    // orphan beat left over from before a reset owes nothing.
    if (m_vif[x].mon_cb.bvalid === 1'b1 && m_vif[x].mon_cb.bready === 1'b1 &&
        m_wr_out[x][m_vif[x].mon_cb.bid] > 0) begin
      m_wr_out[x][m_vif[x].mon_cb.bid]--;
      b_pend[x].push_back(m_vif[x].mon_cb.bid);
    end
    if (m_vif[x].mon_cb.arvalid === 1'b1 && m_vif[x].mon_cb.arready === 1'b1)
      m_rd_out[x][m_vif[x].mon_cb.arid]++;
    if (m_vif[x].mon_cb.rvalid === 1'b1 && m_vif[x].mon_cb.rready === 1'b1 &&
        m_vif[x].mon_cb.rlast === 1'b1 && m_rd_out[x][m_vif[x].mon_cb.rid] > 0) begin
      m_rd_out[x][m_vif[x].mon_cb.rid]--;
      r_pend[x].push_back(m_vif[x].mon_cb.rid);
    end
  endfunction

  // The link lets the DUT send credited messages: ENABLED, no deactivation
  // under way, lp_linkerror low.
  protected function bit link_open();
    if (model.lnk.state != AOU_LS_ENABLED || model.lnk.dreq_sent || model.lnk.dreq_rcvd ||
        model.lnk.want_deact)
      return 1'b0;
    return lsm_vif == null || lsm_vif.mon_cb.lp_linkerror !== 1'b1;
  endfunction

  // The Adapter takes a beat on this edge: the active PHY is Active with pl_trdy high.
  protected function bit fdi_ready();
    int unsigned p = cfg.lsm_cfg.active_phy;
    if (p >= AOU_T1_N_PHY || mb_vif[p] == null) return 1'b1;
    // An acknowledged stall (lp_stallack high) keeps the DUT from sending even
    // with pl_trdy high.
    return mb_vif[p].mon_cb.pl_trdy === 1'b1 && mb_vif[p].mon_cb.lp_stallack !== 1'b1 &&
           mb_vif[p].mon_cb.pl_state_sts == aou_fdi_pkg::FDI_STS_ACTIVE;
  endfunction

  protected function void sample(int unsigned c, int unsigned ev);
    s_cls = c;
    s_ev = ev;
    cg_crd.sample();
    fc_crd.sample(int'(c), int'(ev));
  endfunction

  protected function void cover_rp(int unsigned x, bit any_starved);
    for (int c = 0; c < AOU_CC_NUM; c++) begin
      bit st = queued(x, aou_cred_class_e'(c)) && !cred(x, aou_cred_class_e'(c));
      bit bs = any_starved && eligible(x, aou_cred_class_e'(c));
      if (st && !was_starved[x][c]) sample(c, 0);
      if (bs && !was_beside[x][c]) sample(c, 1);
      was_starved[x][c] = st;
      was_beside[x][c] = bs;
    end
  endfunction

  task run_phase(uvm_phase phase);
    bit was_open = 1'b0;
    if (!enable || s_vif.size() == 0 || model == null) return;
    forever begin
      @(s_vif[0].mon_cb);
      cyc++;
      for (int unsigned x = 0; x < cfg.n_rp; x++) track(x);
      link_check();
      if (!link_open()) begin
        for (int unsigned x = 0; x < cfg.n_rp; x++) begin
          forget(x);
          if (was_open) forget_m(x);
        end
        was_open = 1'b0;
        foreach (stall[c]) begin
          stall[c] = 0;
          rep[c] = 1'b0;
          sent[c] = 1'b0;
        end
        continue;
      end
      was_open = 1'b1;
      // A cycle the Adapter holds the TX (pl_trdy low, or a stall acknowledged)
      // neither counts nor ends a stall.
      if (fdi_ready()) judge();
    end
  endtask

  protected function void judge();
    int    el[AOU_CC_NUM];
    bit    st[AOU_RP_MAX];
    string why[AOU_RP_MAX];
    bit    any_st = 1'b0;
    bit    held = held_back() || (blk != null && blk.blocked());
    for (int unsigned x = 0; x < cfg.n_rp; x++) begin
      st[x] = starved(x, why[x]);
      if (st[x]) any_st = 1'b1;
    end
    for (int unsigned x = 0; x < cfg.n_rp; x++) cover_rp(x, any_st && !st[x]);
    for (int c = 0; c < AOU_CC_NUM; c++) begin
      el[c] = -1;
      for (int unsigned x = 0; x < cfg.n_rp && el[c] < 0; x++)
        if (eligible(x, aou_cred_class_e'(c))) el[c] = int'(x);
      if (sent[c] || el[c] < 0) begin
        stall[c] = 0;
        rep[c] = 1'b0;
      end else if (!busy_other(c)) begin
        if (stall[c] == 0) begin
          aou_rule_log::check("T1-C02", get_type_name());
          if (any_st) aou_rule_log::check("T1-C01", get_type_name());
        end
        stall[c]++;
        if (stall[c] > longest[c]) longest[c] = stall[c];
        if (!rep[c] && stall[c] >= block_cycles) report_c01(c, el[c], st, why);
        if (!rep[c] && stall[c] >= idle_cycles) report_c02(c, el[c]);
      end
      sent[c] = 1'b0;
      if (!held) for (int unsigned x = 0; x < cfg.n_rp; x++) rp_progress(x, c);
    end
  endfunction

  // One counted cycle of RP x and class c (T1-C43).
  protected function void rp_progress(int unsigned x, int c);
    string cn;
    if (!eligible(x, aou_cred_class_e'(c)) || !at_head(x, aou_cred_class_e'(c))) return;
    if (rp_wait[x][c] == 0) aou_rule_log::check("T1-C43", get_type_name());
    rp_wait[x][c]++;
    if (rp_wait[x][c] > longest_rp_wait[c]) begin
      longest_rp_wait[c] = rp_wait[x][c];
      longest_rp[c] = x;
      longest_at[c] = $time;
    end
    if (rp_rep[x][c] || rp_wait[x][c] < starve_cycles) return;
    cn = aou_cc_name(aou_cred_class_e'(c));
    rp_rep[x][c] = 1'b1;
    n_c43++;
    aou_rule_log::fire("T1-C43", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
        {"T1-C43: RP%0d has credit (%0d granules) and a queued %s%s, but the DUT sent no %s ",
         "on it for %0d such cycles"}, x, model.crd.rx_outstanding[wire_of(x)][c], cn,
        c == AOU_CC_WDATA ? " and is next in write order" : "", cn, rp_wait[x][c]))
  endfunction

  // The DUT sent a message of another class within the last busy_cycles:
  // its TX may be giving that class the bandwidth, so the stall does not count.
  protected function bit busy_other(int c);
    for (int c2 = 0; c2 < AOU_CC_NUM; c2++)
      if (c2 != c && last_msg[c2] != 0 && cyc - last_msg[c2] <= 64'(busy_cycles)) return 1'b1;
    return 1'b0;
  endfunction

  protected function void report_c01(int c, int x, bit st[AOU_RP_MAX], string why[AOU_RP_MAX]);
    string cn = aou_cc_name(aou_cred_class_e'(c));
    for (int unsigned y = 0; y < cfg.n_rp; y++) begin
      if (y == x || !st[y]) continue;
      rep[c] = 1'b1;
      n_c01++;
      aou_rule_log::fire("T1-C01", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"T1-C01: RP%0d %s blocked %0d cycles: credit (%0d granules) and a queued %s, ",
           "no %s sent on any RP, while %s"},
          x, cn, stall[c], model.crd.rx_outstanding[wire_of(x)][c], cn, cn, why[y]))
      return;
    end
  endfunction

  protected function void report_c02(int c, int x);
    string cn = aou_cc_name(aou_cred_class_e'(c));
    rep[c] = 1'b1;
    n_c02++;
    aou_rule_log::fire("T1-C02", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
        {"T1-C02: RP%0d has credit (%0d granules) and a queued %s, but no %s was sent on any ",
         "RP for %0d cycles"}, x, model.crd.rx_outstanding[wire_of(x)][c], cn, cn, stall[c]))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        {"longest eligible stall per class (cycles; WREQ RREQ WDATA RDATA WRESP): %p; ",
         "T1-C01 %0d, T1-C02 %0d"}, longest, n_c01, n_c02), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf(
        {"longest per-RP wait per class (cycles; WREQ RREQ WDATA RDATA WRESP): ",
         "%0d %0d %0d %0d %0d on RPs %0d %0d %0d %0d %0d; ",
         "T1-C43 %0d (bound %0d)"}, longest_rp_wait[0], longest_rp_wait[1], longest_rp_wait[2],
        longest_rp_wait[3], longest_rp_wait[4], longest_rp[0], longest_rp[1], longest_rp[2],
        longest_rp[3], longest_rp[4], n_c43, starve_cycles), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf(
        "longest per-RP wait per class ended at (WREQ RREQ WDATA RDATA WRESP): %0t %0t %0t %0t %0t",
        longest_at[0], longest_at[1], longest_at[2], longest_at[3], longest_at[4]), UVM_LOW)
  endfunction
endclass
