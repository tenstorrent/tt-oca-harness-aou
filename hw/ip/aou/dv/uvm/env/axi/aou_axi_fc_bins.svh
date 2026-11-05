// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of aou_axi_monitor's covergroups (aou_fc_macros.svh), shared by
// the covergroups and the service.
`define AOU_AXI_FC_DIR(B) `B``_BIN(wr, 0, 0) `B``_BIN(rd, 1, 1)
`define AOU_AXI_FC_SIZE(B) `B``_VALS(size, 0, 7)
`define AOU_AXI_FC_LEN(B) \
  `B``_BIN(one, 0, 0) `B``_BIN(upto4, 1, 1) `B``_BIN(upto16, 2, 2) `B``_BIN(over16, 3, 3)
`define AOU_AXI_FC_ALIGN(B) `B``_BIN(aligned, 0, 0) `B``_BIN(unaligned, 1, 1)
// No burst coverpoint: the DUT supports INCR only (DECISIONS D5), and AXI-R19
// flags any other burst on its S port. A 1-byte transfer is never unaligned.
`define AOU_AXI_FC_X_TXN(B) \
  `B``_XIGN("*,size[0],*,unaligned")
// zero_cycle: the response in the first cycle after its request's last
// handshake (B after the later of AW and W, the first R beat after AR), the
// minimum legal latency; later: one or more idle cycles between.
`define AOU_AXI_FC_ZERO(B) `B``_BIN(later, 0, 0) `B``_BIN(zero_cycle, 1, 1)
