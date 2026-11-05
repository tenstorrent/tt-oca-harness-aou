// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of aou_l3_cov's covergroups (aou_fc_macros.svh), shared by the
// covergroups and the service. Activation transitions are prev * 8 + cur
// (aou_link_state_e), plus 64 when the link was lost under the model
// (LinkReset or link down returns it to DISABLED from any state). The ERROR
// state is v0.8 only.
`define AOU_L3_FC_ACT_TRANS(B) \
  `B``_BIN(disabled_activate, 0 * 8 + 1, 0 * 8 + 1) \
  `B``_BIN(activate_enabled, 1 * 8 + 2, 1 * 8 + 2) \
  `B``_BIN(enabled_deactivate, 2 * 8 + 3, 2 * 8 + 3) \
  `B``_BIN(deactivate_disabled, 3 * 8 + 0, 3 * 8 + 0) \
  `B``_BIN(activate_error, 1 * 8 + 4, 1 * 8 + 4) \
  `B``_BIN(enabled_error, 2 * 8 + 4, 2 * 8 + 4) \
  `B``_BIN(deactivate_error, 3 * 8 + 4, 3 * 8 + 4) \
  `B``_BIN(error_disabled, 4 * 8 + 0, 4 * 8 + 0) \
  `B``_BIN(activate_disabled_lr, 64 + 1 * 8 + 0, 64 + 1 * 8 + 0) \
  `B``_BIN(enabled_disabled_lr, 64 + 2 * 8 + 0, 64 + 2 * 8 + 0) \
  `B``_BIN(deactivate_disabled_lr, 64 + 3 * 8 + 0, 64 + 3 * 8 + 0) \
  `B``_TAG("*_error|error_disabled", "v0.8")
// A reserved op (AoU v0.8 Table 27: ops 4-15) is no target: no compliant die
// sends one, so seeing one takes out-of-protocol stimulus.
`define AOU_L3_FC_ACT_OP(B) `B``_VALS(op, 0, 3) `B``_IGN(reserved, 4, 15)
`define AOU_L3_FC_LEGAL(B) `B``_BIN(illegal, 0, 0) `B``_BIN(legal, 1, 1)
// The DUT sending an illegal op is AOU-R40's check, so it can't happen in a
// passing run; ours come from the inject path.
`define AOU_L3_FC_X_ACT_OP(B) `B``_XIGN("*,rx,illegal")
// Message kinds as msg_kind() numbers them.
`define AOU_L3_FC_MSG_KIND(B) \
  `B``_BIN(wreq, 0, 0) `B``_BIN(rreq, 1, 1) \
  `B``_BIN(w256, 2, 2) `B``_BIN(w512, 3, 3) `B``_BIN(w1024, 4, 4) \
  `B``_BIN(wf256, 5, 5) `B``_BIN(wf512, 6, 6) `B``_BIN(wf1024, 7, 7) \
  `B``_BIN(r256, 8, 8) `B``_BIN(r512, 9, 9) `B``_BIN(r1024, 10, 10) \
  `B``_BIN(wresp, 11, 11) `B``_BIN(act, 12, 12) `B``_BIN(crdt, 13, 13)
`define AOU_L3_FC_RP(B) `B``_VALS(rp, 0, 3)
// Activation and CrdtGrant are Misc messages with no RP field (AoU Tables 15
// and 27): they are sampled as rp[0], which means no RP.
`define AOU_L3_FC_X_KIND_RP(B) \
  `B``_XIGN("act|crdt,rp[1]|rp[2]|rp[3],*")
`define AOU_L3_FC_START(B) `B``_VALS(g, 0, 47)
// Message sizes in granules.
`define AOU_L3_FC_SIZE(B) \
  `B``_BIN(g1, 1, 1) `B``_BIN(g2, 2, 2) `B``_BIN(g3, 3, 3) `B``_BIN(g4, 4, 4) \
  `B``_BIN(g7, 7, 7) `B``_BIN(g8, 8, 8) `B``_BIN(g14, 14, 14) `B``_BIN(g15, 15, 15) \
  `B``_BIN(g27, 27, 27) `B``_BIN(g30, 30, 30)
`define AOU_L3_FC_SPAN(B) `B``_BIN(one_flit, 0, 0) `B``_BIN(multi_flit, 1, 1)
// g4 is the ActivateReq (AoU v0.8 Table 27), sent and received by the DUT; an
// Activation message starts at G0 (4.4), so g4 away from G0 is AOU-R6's case.
`define AOU_L3_FC_X_START_SIZE(B) \
  `B``_XILL("g[1*]|g[2*]|g[3*]|g[4*]|g[5]|g[6]|g[7]|g[8]|g[9],g4", "AOU-R6")
// A 1-granule message can't span flits; the 4-granule ActivateReq starts at
// G0, so it can't either (AOU-R6 reports one that does).
`define AOU_L3_FC_X_SIZE_SPAN(B) \
  `B``_XIGN("g1,multi_flit") \
  `B``_XILL("g4,multi_flit", "AOU-R6")
// Messages that span flits, by kind (msg_kind() numbers) and direction
// (cg_span). A WriteResp is one granule and an Activation starts at G0 and is
// at most 4 granules, so neither can span; a CrdtGrant can, but it is no
// packing target.
`define AOU_L3_FC_SPAN_KIND(B) \
  `B``_BIN(wreq, 0, 0) `B``_BIN(rreq, 1, 1) \
  `B``_BIN(w256, 2, 2) `B``_BIN(w512, 3, 3) `B``_BIN(w1024, 4, 4) \
  `B``_BIN(wf256, 5, 5) `B``_BIN(wf512, 6, 6) `B``_BIN(wf1024, 7, 7) \
  `B``_BIN(r256, 8, 8) `B``_BIN(r512, 9, 9) `B``_BIN(r1024, 10, 10) \
  `B``_IGN(other, 11, 15)
`define AOU_L3_FC_NMSGS(B) \
  `B``_BIN(none, 0, 0) `B``_BIN(one, 1, 1) `B``_BIN(few, 2, 4) `B``_BIN(many, 5, 15) \
  `B``_BIN(dense, 16, 48)
// WriteResp starting in one flit (cg_wresp_flit; flits with none aren't
// sampled). A WriteResp is one granule, so a flit holds at most 48.
`define AOU_L3_FC_NWRESP(B) \
  `B``_BIN(one, 1, 1) `B``_BIN(two, 2, 2) `B``_BIN(few, 3, 4) `B``_BIN(many, 5, 15) \
  `B``_BIN(dense, 16, 47) `B``_BIN(full, 48, 48)
// Misc messages other than Activation in one half-flit. AoU v0.8 4.4 allows at
// most two, so three or more is a violation, not a target: the unpacker's
// half-flit Misc check (AOU-R7) reports it.
`define AOU_L3_FC_MISC(B) `B``_VALS(n, 0, 2) `B``_ILL(over, 3, 24, "")
// A flit that starts an Activation message, by what shares it (cg_act_flit;
// aou_l3_cov::act_layout()). AoU v0.8 4.4 puts an Activation message alone in
// its flit. The v0.9 draft of 4.4 permits one CrdtGrant beside an
// ActivateReq/Ack and responses beside a DeactivateReq, so those layouts carry
// the tag "v0.9draft" and stay out of the headline figure; anything else is
// AOU-R6, so it is no coverage goal. The DUT sends its initial CrdtGrant in
// its ActivateAck's flit every time, so its Ack is never alone and its
// ActivateReq never carries the grant (rx). Our ActivateReq carries it only
// when our Ack went before our Req (ack_first) without it.
`define AOU_L3_FC_ACT_FLIT(B) \
  `B``_BIN(req_alone, 0, 0) `B``_BIN(req_grant, 1, 1) \
  `B``_BIN(ack_alone, 2, 2) `B``_BIN(ack_grant, 3, 3) \
  `B``_BIN(dreq_alone, 4, 4) `B``_BIN(dreq_rsp, 5, 5) `B``_BIN(dack_alone, 6, 6) \
  `B``_IGN(forbidden, 7, 7) \
  `B``_TAG("req_grant|ack_grant|dreq_rsp", "v0.9draft")
`define AOU_L3_FC_X_ACT_FLIT(B) \
  `B``_XIGN("ack_alone,rx") `B``_XIGN("req_grant,rx") \
  `B``_TAG("req_grant|ack_grant|dreq_rsp,*", "v0.9draft")
`define AOU_L3_FC_CARRY(B) \
  `B``_BIN(none, 0, 0) `B``_BIN(short_carry, 1, 11) `B``_BIN(long_carry, 12, 30)
`define AOU_L3_FC_CREDIT_ONLY(B) `B``_BIN(no, 0, 0) `B``_BIN(yes, 1, 1)
// The model's own counter saturating is no target. Sending without credit
// (inj_overflow, an injection) is none either: AoU v0.8 6.1 defines no
// receiver reaction to it, so it is undefined stimulus.
`define AOU_L3_FC_CREDIT_EV(B) \
  `B``_BIN(hdr_grant, EV_HDR_GRANT, EV_HDR_GRANT) \
  `B``_BIN(crdt_grant, EV_CRDT_GRANT, EV_CRDT_GRANT) \
  `B``_BIN(both, EV_BOTH, EV_BOTH) \
  `B``_BIN(consume, EV_CONSUME, EV_CONSUME) \
  `B``_BIN(zero_stall, EV_ZERO_STALL, EV_ZERO_STALL) \
  `B``_IGN(saturate, EV_SATURATE, EV_SATURATE) \
  `B``_ILL(overflow, EV_OVERFLOW, EV_OVERFLOW, "") \
  `B``_BIN(dut_zero_stall, EV_DUT_ZERO_STALL, EV_DUT_ZERO_STALL) \
  `B``_BIN(dut_saturate, EV_DUT_SATURATE, EV_DUT_SATURATE) \
  `B``_IGN(inj_overflow, EV_INJ_OVERFLOW, EV_INJ_OVERFLOW) \
  `B``_BIN(late_adv, EV_LATE_ADV, EV_LATE_ADV)
// Each event has one direction: the model stalls on DUT credit (tx), the DUT
// waits for ours (rx), our over-grant (tx), our late advertisement (tx). Only
// request credits go on past our DeactivateReq.
`define AOU_L3_FC_X_CREDIT(B) \
  `B``_XIGN("zero_stall,*,rx") \
  `B``_XIGN("dut_zero_stall,*,tx") \
  `B``_XIGN("dut_saturate,*,rx") \
  `B``_XIGN("late_adv,*,rx") \
  `B``_XIGN("late_adv,c[3]|c[4],*")
`define AOU_L3_FC_CLS(B) `B``_VALS(c, 0, 4)
// A WriteReq the model sent (cg_wr_order), by how many of its own WriteData
// messages went before it (AoU v0.8 5.7 leaves the order open; the DUT's RX
// holds the early data in its RX W FIFO), whether that was the whole burst,
// and how many other RPs had WriteData ahead of their WriteReq at the time.
`define AOU_L3_FC_WF_AHEAD(B) \
  `B``_BIN(none, 0, 0) `B``_BIN(one, 1, 1) `B``_BIN(few, 2, 3) `B``_BIN(many, 4, 15) \
  `B``_BIN(deep, 16, 256)
`define AOU_L3_FC_WF_WHOLE(B) `B``_BIN(part, 0, 0) `B``_BIN(whole, 1, 1)
`define AOU_L3_FC_WF_OTHERS(B) `B``_BIN(alone, 0, 0) `B``_BIN(one, 1, 1) `B``_BIN(more, 2, 3)
// Nothing ahead is never the whole burst; other RPs count only when this RP's
// data went first too.
`define AOU_L3_FC_X_WF(B) \
  `B``_XIGN("none,whole,*") \
  `B``_XIGN("none,*,one|more")
// FLEX of an AXI message (cg_flex): zero, some other value, or all ones. In
// the Basic Profile FLEX is USER[15:0] (AoU v0.8 5.2 / 11.1): on rx (the DUT's
// messages) the DUT forwards the USER its AXI port got, on tx the model's FLEX
// to the DUT.
`define AOU_L3_FC_FLEX(B) `B``_BIN(zero, 0, 0) `B``_BIN(nonzero, 1, 1) `B``_BIN(all_ones, 2, 2)
// The AXI messages that carry FLEX, in msg_kind() order.
`define AOU_L3_FC_FLEX_KIND(B) \
  `B``_BIN(wreq, 0, 0) `B``_BIN(rreq, 1, 1) `B``_BIN(wdata, 2, 4) `B``_BIN(wdataf, 5, 7) \
  `B``_BIN(rdata, 8, 10) `B``_BIN(wresp, 11, 11)
// Every cell is reachable on both directions: the remote AXI agents' USER
// (aou_axi_cfg::user_pat, incl. all ones; aou_attr_test attr_user-1) is the
// FLEX of the model's messages (flex_fixed), and the packer's random FLEX
// (aou_packer_policy::prof_pct) only covers messages without one.
`define AOU_L3_FC_X_FLEX(B)
// ActivateReq profile fields per RP (cg_act_profile; AoU v0.8 Ch. 11): on rx
// the DUT's, always the Basic Profile (PROFILE_CFG_RPn read-only 0/0/0), on
// tx the model's cfg.profile_*. An RP the sender does not have carries 0 (its
// fields are reserved); the non-zero bins are reached on tx only.
`define AOU_L3_FC_PROFILE_ID(B) `B``_BIN(basic, 0, 0) `B``_BIN(low, 1, 15) `B``_BIN(high, 16, 31)
`define AOU_L3_FC_PROFILE_NZ(B) `B``_BIN(zero, 0, 0) `B``_BIN(nonzero, 1, 1)
`define AOU_L3_FC_PRESENT(B) `B``_BIN(absent, 0, 0) `B``_BIN(present, 1, 1)
`define AOU_L3_FC_X_PROFILE(B) \
  `B``_XIGN("*,low|high,*,*,absent") \
  `B``_XIGN("*,*,nonzero,*,absent") \
  `B``_XIGN("*,*,*,nonzero,absent") \
  `B``_XIGN("rp[0],*,*,*,absent")
