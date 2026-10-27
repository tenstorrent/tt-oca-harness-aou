// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins table of aou_t1_mo_chk's covergroup (aou_fc_macros.svh): remote
// requests of one RP and kind in service at the M port after each request's
// first AR/AW handshake, against the pending-ID table depth (AOU_T1_M_MO_CNT,
// 32 by default): one, below half, from half, and full.
`define AOU_T1_MO_FC_DIR(B) `B``_BIN(wr, 0, 0) `B``_BIN(rd, 1, 1)
`define AOU_T1_MO_FC_OCC(B) \
  `B``_BIN(one, 1, 1) `B``_BIN(below_half, 2, AOU_T1_M_MO_CNT / 2 - 1) \
  `B``_BIN(from_half, AOU_T1_M_MO_CNT / 2, AOU_T1_M_MO_CNT - 1) \
  `B``_BIN(full, AOU_T1_M_MO_CNT, AOU_T1_M_MO_CNT)
