// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins table of aou_t1_mo_chk's covergroup (aou_fc_macros.svh): M-port
// outstanding bursts of one RP and kind after each AR/AW handshake, against
// the pending-ID table depth (32).
`define AOU_T1_MO_FC_DIR(B) `B``_BIN(wr, 0, 0) `B``_BIN(rd, 1, 1)
`define AOU_T1_MO_FC_OCC(B) \
  `B``_BIN(one, 1, 1) `B``_BIN(upto15, 2, 15) `B``_BIN(upto31, 16, 31) `B``_BIN(full, 32, 32)
