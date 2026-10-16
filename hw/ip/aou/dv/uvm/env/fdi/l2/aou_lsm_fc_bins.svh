// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of aou_lsm_cov's covergroups (aou_fc_macros.svh), shared by the
// covergroups and the service. A transition is prev * 16 + cur.
`define AOU_LSM_FC_TR(B, n, a, b) `B``_BIN(n, int'(a) * 16 + int'(b), int'(a) * 16 + int'(b))
`define AOU_LSM_FC_LINK_TR(B) \
  `AOU_LSM_FC_TR(B, reset_active, LSM_RESET, LSM_ACTIVE) \
  `AOU_LSM_FC_TR(B, active_retrain, LSM_ACTIVE, LSM_RETRAIN) \
  `AOU_LSM_FC_TR(B, retrain_active, LSM_RETRAIN, LSM_ACTIVE) \
  `AOU_LSM_FC_TR(B, active_linkerror, LSM_ACTIVE, LSM_LINKERROR) \
  `AOU_LSM_FC_TR(B, retrain_linkerror, LSM_RETRAIN, LSM_LINKERROR) \
  `AOU_LSM_FC_TR(B, linkerror_reset, LSM_LINKERROR, LSM_RESET) \
  `AOU_LSM_FC_TR(B, active_l1, LSM_ACTIVE, LSM_L1) \
  `AOU_LSM_FC_TR(B, l1_retrain, LSM_L1, LSM_RETRAIN) \
  `AOU_LSM_FC_TR(B, active_reset, LSM_ACTIVE, LSM_RESET) \
  `AOU_LSM_FC_TR(B, active_linkreset, LSM_ACTIVE, LSM_LINKRESET) \
  `AOU_LSM_FC_TR(B, linkreset_reset, LSM_LINKRESET, LSM_RESET) \
  `AOU_LSM_FC_TR(B, active_disabled, LSM_ACTIVE, LSM_DISABLED) \
  `AOU_LSM_FC_TR(B, disabled_reset, LSM_DISABLED, LSM_RESET) \
  `AOU_LSM_FC_TR(B, reset_linkerror, LSM_RESET, LSM_LINKERROR)
`define AOU_LSM_FC_STS(B) \
  `B``_BIN(reset, LSM_RESET, LSM_RESET) `B``_BIN(active, LSM_ACTIVE, LSM_ACTIVE) \
  `B``_BIN(l1, LSM_L1, LSM_L1) `B``_BIN(linkreset, LSM_LINKRESET, LSM_LINKRESET) \
  `B``_BIN(linkerror, LSM_LINKERROR, LSM_LINKERROR) `B``_BIN(disabled, LSM_DISABLED, LSM_DISABLED) \
  `B``_BIN(retrain, LSM_RETRAIN, LSM_RETRAIN)
`define AOU_LSM_FC_REQ(B) \
  `B``_BIN(nop, LSM_REQ_NOP, LSM_REQ_NOP) `B``_BIN(active, LSM_REQ_ACTIVE, LSM_REQ_ACTIVE) \
  `B``_BIN(l1, LSM_REQ_L1, LSM_REQ_L1) `B``_BIN(retrain, LSM_REQ_RETRAIN, LSM_REQ_RETRAIN) \
  `B``_ILL(reserved, LSM_REQ_RESERVED, LSM_REQ_RESERVED, "") \
  `B``_BIN(linkreset, LSM_REQ_LINKRESET, LSM_REQ_LINKRESET) \
  `B``_BIN(disabled, LSM_REQ_DISABLED, LSM_REQ_DISABLED)
// Status x request pairs UCIe r1.1 Table 8-3 gives a meaning to and the bringup
// model expects (FDI-M01): Reset NOP/Active; Active Active/L1, Retrain (RTL
// encodings), LinkReset/Disabled (teardown, SPEC encodings); L1 L1/Active;
// Retrain Retrain (RTL), NOP (SPEC), Active; LinkError, LinkReset and Disabled
// NOP/Active. Every other pair is ignored; a reserved request is FDI-R46's.
`define AOU_LSM_FC_X_STS_REQ(B) \
  `B``_XIGN("reset,l1|retrain|linkreset|disabled") \
  `B``_XIGN("active,nop") \
  `B``_XIGN("l1,nop|retrain|linkreset|disabled") \
  `B``_XIGN("retrain,l1|linkreset|disabled") \
  `B``_XIGN("linkerror,l1|retrain|linkreset|disabled") \
  `B``_XIGN("linkreset,l1|retrain|linkreset|disabled") \
  `B``_XIGN("disabled,l1|retrain|linkreset|disabled")
// FDI state encoding of the run (lsm_cfg.fdi_enc). rtl goes when BUGS/001 is fixed.
`define AOU_LSM_FC_ENC(B) \
  `B``_BIN(rtl, AOU_FDI_ENC_RTL, AOU_FDI_ENC_RTL) `B``_BIN(spec, AOU_FDI_ENC_SPEC, AOU_FDI_ENC_SPEC)
`define AOU_LSM_FC_BRG_TR(B) \
  `AOU_LSM_FC_TR(B, reset_wait, BRG_RESET, BRG_WAIT_PRESENCE) \
  `AOU_LSM_FC_TR(B, wait_reset, BRG_WAIT_PRESENCE, BRG_RESET) \
  `AOU_LSM_FC_TR(B, wait_wake, BRG_WAIT_PRESENCE, BRG_WAKE_ASSERT) \
  `AOU_LSM_FC_TR(B, wake_waitack, BRG_WAKE_ASSERT, BRG_WAKE_WAIT_ACK) \
  `AOU_LSM_FC_TR(B, waitack_req, BRG_WAKE_WAIT_ACK, BRG_REQ_ACTIVE) \
  `AOU_LSM_FC_TR(B, req_active, BRG_REQ_ACTIVE, BRG_ACTIVE) \
  `AOU_LSM_FC_TR(B, active_linkerror, BRG_ACTIVE, BRG_LINKERROR) \
  `AOU_LSM_FC_TR(B, active_retrain, BRG_ACTIVE, BRG_RETRAIN) \
  `AOU_LSM_FC_TR(B, active_deact, BRG_ACTIVE, BRG_DEACTIVATE) \
  `AOU_LSM_FC_TR(B, active_l1, BRG_ACTIVE, BRG_L1) \
  `AOU_LSM_FC_TR(B, active_reset, BRG_ACTIVE, BRG_RESET) \
  `AOU_LSM_FC_TR(B, linkerror_reset, BRG_LINKERROR, BRG_RESET) \
  `AOU_LSM_FC_TR(B, retrain_active, BRG_RETRAIN, BRG_ACTIVE) \
  `AOU_LSM_FC_TR(B, retrain_linkerr, BRG_RETRAIN, BRG_LINKERROR) \
  `AOU_LSM_FC_TR(B, deact_unwake, BRG_DEACTIVATE, BRG_UNWAKE_WAIT) \
  `AOU_LSM_FC_TR(B, unwake_reset, BRG_UNWAKE_WAIT, BRG_RESET) \
  `AOU_LSM_FC_TR(B, active_linkdown, BRG_ACTIVE, BRG_LINKDOWN) \
  `AOU_LSM_FC_TR(B, deact_linkdown, BRG_DEACTIVATE, BRG_LINKDOWN) \
  `AOU_LSM_FC_TR(B, linkdown_unwake, BRG_LINKDOWN, BRG_UNWAKE_WAIT) \
  `AOU_LSM_FC_TR(B, l1_clkwake, BRG_L1, BRG_L1_CLK_WAKE) \
  `AOU_LSM_FC_TR(B, l1_wake, BRG_L1, BRG_WAKE_ASSERT) \
  `AOU_LSM_FC_TR(B, clkwake_wake, BRG_L1_CLK_WAKE, BRG_WAKE_ASSERT)
