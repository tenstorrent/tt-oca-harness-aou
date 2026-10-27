// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of the env checkers' covergroups (aou_fc_macros.svh).
// aou_t1_crd_flow_chk: an RP held work of a class with no credit for it
// (starved), and an RP with credit and work of the class while another RP was
// starved.
`define AOU_T1_CRD_FC_CLS(B) `B``_VALS(c, 0, 4)
`define AOU_T1_CRD_FC_EV(B) `B``_BIN(starved, 0, 0) `B``_BIN(eligible_beside_starved, 1, 1)
// aou_t1_early_tbl_chk: the early table filled (an AW held), and a held AW
// was accepted once an entry was freed.
`define AOU_T1_EARLY_FC_EV(B) `B``_BIN(full_stall, 0, 0) `B``_BIN(stall_resumed, 1, 1)
// aou_t1_crd_rr_chk: RPs owed credit when a test opened a round-robin window.
`define AOU_T1_RR_FC_OWED(B) `B``_BIN(under_two, 0, 1) `B``_VALS(rps, 2, 4)
// aou_t1_wdt_chk: write-watchdog expiries (early response off/on, the
// threshold's class, masked, per RP, again after a software or hard reset),
// an AW restarting the count just before the threshold (aw_restart_edge: in
// the cycle that would have expired), a W1C with the RP still hung and
// WDT_EN set, the mask cleared with a status set, two or more RPs set at once.
`define AOU_T1_WDT_FC_EV(B) \
  `B``_BIN(expiry_early_off, 0, 0) `B``_BIN(expiry_early_on, 1, 1) \
  `B``_BIN(expiry_thr_zero, 2, 2) `B``_BIN(expiry_thr_small, 3, 3) \
  `B``_BIN(expiry_thr_large, 4, 4) `B``_BIN(expiry_masked, 5, 5) \
  `B``_BIN(aw_restart_near, 6, 6) `B``_BIN(aw_restart_edge, 7, 7) \
  `B``_BIN(w1c_while_hung, 8, 8) `B``_BIN(unmask_while_set, 9, 9) \
  `B``_BIN(multi_rp_set, 10, 10) `B``_BIN(re_expiry_after_sw, 11, 11) \
  `B``_BIN(re_expiry_after_hard, 12, 12) `B``_VALS(expiry_rp, 13, 16)
// aou_t1_status: how the DUT handled an injected DeactivateAck in ENABLED,
// which the spec does not define (any of these is accepted): ignored, flagged
// as an error on arrival (still ENABLED), or an error at the next deactivation.
`define AOU_T1_STRAY_FC_OUTCOME(B) \
  `B``_BIN(ignored, 0, 0) `B``_BIN(flagged_on_arrival, 1, 1) `B``_BIN(error_at_deact, 2, 2)
