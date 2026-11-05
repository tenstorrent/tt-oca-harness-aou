// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// White-box tap of the DUT's RX granule stores (AOU_RX_GRANULE_STORE, one per
// RP for WriteData/WriteDataFull and one for ReadData) for
// aou_t1_rx_granule_chk (config_db key "gs"), sampled on the core clock.
// tb_top assigns them from each store's read side:
//   valid[k][r]: store k (0 WriteData, 1 ReadData) of RP r hands a complete
//     message to its output buffer this cycle (w_out_svalid);
//   g[k][r]: that message's raw granules aligned to granule 0 (w_msg_g),
//     meaningful up to the length its header granule gives, in the RTL's
//     byte order: message byte 5i at bits [7:0] of granule i (the wire's
//     aou_granule_t has it at [39:32]).
// Entries of RPs the build does not have are 0.
interface aou_rx_gs_if (input logic clk);
  localparam int MAX_G = 30;   // WriteData1024
  logic [1:0][3:0]                   valid;
  logic [1:0][3:0][MAX_G-1:0][39:0]  g;

  clocking mon_cb @(posedge clk);
    input valid, g;
  endclocking
endinterface
