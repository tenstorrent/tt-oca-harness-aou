// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of aou_fdi_cov's covergroups (aou_fc_macros.svh), shared by the
// covergroups and the service. The top bin of each clamped value is "that
// many or more".
`define AOU_FDI_FC_WIDTH(B) `B``_BIN(b32, 32, 32) `B``_BIN(b64, 64, 64) `B``_BIN(b128, 128, 128)
`define AOU_FDI_FC_STALL(B) \
  `B``_BIN(none, 0, 0) `B``_BIN(one, 1, 1) `B``_BIN(few, 2, 4) `B``_BIN(many, 5, 5)
`define AOU_FDI_FC_GAP(B) `B``_BIN(b2b, 0, 0) `B``_BIN(short_gap, 1, 3) `B``_BIN(long_gap, 4, 4)
`define AOU_FDI_FC_HALF(B) `B``_BIN(h0, 0, 0) `B``_BIN(h1, 1, 1)
`define AOU_FDI_FC_CANCEL_KIND(B) `B``_BIN(idle, 0, 0) `B``_BIN(with_valid, 1, 1)
`define AOU_FDI_FC_REPEAT(B) `B``_BIN(first, 1, 1) `B``_BIN(second, 2, 2) `B``_BIN(more, 3, 3)
`define AOU_FDI_FC_LAT(B) \
  `B``_BIN(l2, 2, 2) `B``_BIN(l3, 3, 3) `B``_BIN(l4_6, 4, 6) `B``_BIN(l7_up, 7, 7)
`define AOU_FDI_FC_HOLD(B) `B``_BIN(h1, 1, 1) `B``_BIN(h2_4, 2, 4) `B``_BIN(h5_up, 5, 5)
`define AOU_FDI_FC_WHERE(B) `B``_BIN(boundary, 0, 0) `B``_BIN(mid_flit, 1, 1)
`define AOU_FDI_FC_TRDY_AT_REQ(B) `B``_BIN(trdy_high, 0, 0) `B``_BIN(trdy_low, 1, 1)
`define AOU_FDI_FC_TX_STALLED(B) `B``_BIN(tx_running, 0, 0) `B``_BIN(tx_stalled, 1, 1)
`define AOU_FDI_FC_ABANDON(B) `B``_BIN(tx_flit, 0, 0) `B``_BIN(rx_flit, 1, 1)
