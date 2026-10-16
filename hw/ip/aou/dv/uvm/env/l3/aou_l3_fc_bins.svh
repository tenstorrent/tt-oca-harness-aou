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
`define AOU_L3_FC_ACT_OP(B) `B``_VALS(op, 0, 3) `B``_BIN(reserved, 4, 15)
`define AOU_L3_FC_LEGAL(B) `B``_BIN(illegal, 0, 0) `B``_BIN(legal, 1, 1)
// A reserved op is never legal. The DUT sending an illegal op is AOU-R40's
// check, so it can't happen in a passing run; ours come from the inject path.
`define AOU_L3_FC_X_ACT_OP(B) \
  `B``_XIGN("reserved,*,legal") \
  `B``_XIGN("*,rx,illegal")
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
  `B``_BIN(g27, 27, 27) `B``_BIN(g30, 30, 30) \
  `B``_TAG("g4", "v0.8")
`define AOU_L3_FC_SPAN(B) `B``_BIN(one_flit, 0, 0) `B``_BIN(multi_flit, 1, 1)
// The 4-granule ActivateReq is v0.8 (AoU v0.8 Table 27).
`define AOU_L3_FC_X_START_SIZE(B) `B``_TAG("*,g4", "v0.8")
// A 1-granule message can't span flits.
`define AOU_L3_FC_X_SIZE_SPAN(B) \
  `B``_XIGN("g1,multi_flit") \
  `B``_TAG("g4,*", "v0.8")
`define AOU_L3_FC_NMSGS(B) \
  `B``_BIN(none, 0, 0) `B``_BIN(one, 1, 1) `B``_BIN(few, 2, 4) `B``_BIN(many, 5, 15) \
  `B``_BIN(dense, 16, 48)
`define AOU_L3_FC_MISC(B) `B``_VALS(n, 0, 2) `B``_BIN(over, 3, 24)
`define AOU_L3_FC_CARRY(B) \
  `B``_BIN(none, 0, 0) `B``_BIN(short_carry, 1, 11) `B``_BIN(long_carry, 12, 30)
`define AOU_L3_FC_CREDIT_ONLY(B) `B``_BIN(no, 0, 0) `B``_BIN(yes, 1, 1)
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
  `B``_BIN(inj_overflow, EV_INJ_OVERFLOW, EV_INJ_OVERFLOW)
// Each event has one direction: the model stalls on DUT credit (tx), the DUT
// waits for ours (rx), our over-grant (tx), our send without credit (tx).
`define AOU_L3_FC_X_CREDIT(B) \
  `B``_XIGN("zero_stall,*,rx") \
  `B``_XIGN("dut_zero_stall,*,tx") \
  `B``_XIGN("dut_saturate,*,rx") \
  `B``_XIGN("inj_overflow,*,rx")
`define AOU_L3_FC_CLS(B) `B``_VALS(c, 0, 4)
