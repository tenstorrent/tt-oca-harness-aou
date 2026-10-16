// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Configuration of one L3 remote-die protocol model.
class aou_l3_cfg extends uvm_object;
  `uvm_object_utils(aou_l3_cfg)

  aou_spec_rev_e     spec_rev = AOU_SPEC_V07;
  int unsigned       rp_count = 1;
  // The DUT's RP count; 0: the same as ours. When they differ the link uses the
  // smaller (MAS 3.10.1): AXI messages stay below it, and each side's credits
  // may name any of its own RPs (the other side ignores the ones it lacks).
  int unsigned       peer_rp_count = 0;
  bit [1:0]          fdid = 2'd0;
  // FH byte 0 placed in every TX flit (Protocol Identifier in [7:6]); L1 may
  // overwrite the adapter bytes.
  bit [7:0]          fh_byte0 = 8'hC0;

  // Modelled RX buffer per RP and class, in granules: the credits advertised
  // to the DUT at activation.
  int unsigned       rx_depth[AOU_CC_NUM] = '{64, 64, 256, 256, 32};
  // Per RP and class: that buffer has no space, so nothing is advertised for it.
  bit                rx_starve[AOU_RP_MAX][AOU_CC_NUM];
  aou_cred_ret_e     ret_policy[AOU_CC_NUM] =
      '{AOU_RET_ON_CONSUME, AOU_RET_ON_CONSUME, AOU_RET_ON_CONSUME, AOU_RET_IMMEDIATE,
        AOU_RET_IMMEDIATE};
  int unsigned       ret_delay = 4;      // ticks, for AOU_RET_DELAYED
  // TX counter maximum: credits granted beyond it saturate (6.4).
  int unsigned       tx_cred_max = 2048;
  // Most credit the DUT may advertise per RP and class (its RX FIFO, MAS 3.9);
  // 0: not known, unchecked (T1-C40).
  int unsigned       dut_max_cred[AOU_RP_MAX][AOU_CC_NUM];
  // Return RDATA/WRESP credits after our DeactivateAck (MAS CREDIT_MANAGE=1
  // reading). Off follows v0.7 8.4: no credits after DeactivateAck.
  bit                resp_credits_after_deact_ack;
  // A MAS CREDIT_MANAGE=0 partner: our DeactivateReq waits until every DUT
  // request has been answered (MAS 7.2 DEACTIVATE_START condition 1), and no
  // credited message follows it (7.3.1). A DUT request that crosses our
  // DeactivateReq is answered after the next activation (7.3.5).
  bit                cm0_deact;
  // Our DeactivateReq goes out once our queued messages are sent, with our
  // requests still unanswered; they are answered after the next activation
  // (MAS 7.3.4: a request crossing the partner's DeactivateReq).
  bit                deact_own_open;
  // PropertyReq of our DeactivateReq (BUGS/010: DEACTIVATE_FORCE on the wire).
  bit                deact_prop;

  // Link controller.
  bit                auto_activate = 1'b1;   // answer a peer ActivateReq with our own
  bit                auto_ack = 1'b1;
  bit                auto_deactivate = 1'b1;
  bit                auto_deact_ack = 1'b1;
  bit                ack_first;              // our Ack before our own Req
  bit                initial_grant = 1'b1;   // CrdtGrant right after our ActivateAck
  // Send credited messages once ActivateReq is sent and ActivateAck received
  // (9.2) instead of waiting for ENABLED (8.4).
  bit                send_after_ack_rcvd;
  // v0.8: an out-of-sequence Req/Ack moves the link to ERROR (8.3.3).
  bit                error_state_en = 1'b1;

  // Checks on the DUT.
  bit                chk_deact_quiesce = 1'b1;   // AOU-R33
  bit                chk_end_state = 1'b1;       // AOU-R28/R36 at end of test
  // AOU-R31: once quiescent in ENABLED, every credit the DUT advertised is
  // back within cred_return_cycles (MAS 7.1: LP threshold 0 still launches a
  // flit for pending MsgCredit-header credits).
  bit                chk_cred_return = 1'b1;
  int unsigned       cred_return_cycles = 4000;

  // Responder: DUT requests go to l4a. With resp_fork each request runs in
  // its own thread (responses may reorder across IDs, never within one);
  // otherwise requests are served in arrival order per RP and class.
  aou_l4a_if_c       l4a;
  bit                resp_fork;
  // With resp_fork: after each ReadData beat but the last, a read waits for
  // the next flit, so beats of reads on other IDs interleave with it.
  bit                rdata_ilv;
  // Our DEST_RP map: a response to a DUT request on our plane p goes to the
  // DUT's plane dest_rp[p] (MAS 3.10).
  bit [1:0]          dest_rp[AOU_RP_MAX] = '{2'd0, 2'd1, 2'd2, 2'd3};
  // Error injection: the next rdata_wide[p] DUT reads on our plane p that need
  // less than ReadData1024 are answered with ReadData1024 anyway, the requested
  // bytes repeated across the beat (MAS overview: read data wider than the
  // requester's AXI width is a violation).
  int unsigned       rdata_wide[AOU_RP_MAX];
  int unsigned       n_rdata_wide;   // reads answered that way

  aou_packer_policy  pol;
  aou_l3_rule_chk    chk;
  bit                cov_en = 1'b1;

  function new(string name = "aou_l3_cfg");
    super.new(name);
    pol = aou_packer_policy::type_id::create("pol");
    chk = aou_l3_rule_chk::type_id::create("chk");
  endfunction

  function int unsigned peer_count();
    return (peer_rp_count == 0) ? rp_count : peer_rp_count;
  endfunction

  // RPs both dies have: the only ones AXI messages may use (MAS 3.10.1).
  function int unsigned eff_rp_count();
    return (peer_count() < rp_count) ? peer_count() : rp_count;
  endfunction

  virtual function string convert2string();
    return $sformatf("spec=%s rp_count=%0d fdid=%0d depth=%p ret=%p pol={%s}",
                     (spec_rev == AOU_SPEC_V08) ? "v0.8" : "v0.7", rp_count, fdid, rx_depth,
                     ret_policy, pol.convert2string());
  endfunction
endclass
