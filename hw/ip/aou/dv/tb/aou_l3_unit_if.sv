// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Unit-test stand-in for the FDI: two 64-byte beat streams that carry the
// flits of two L3 models into AOU_FDI_CHECKER. LP is die A (in the DUT's
// place), PL is die B (the remote model).
interface aou_l3_unit_if (input logic clk);
  logic         rst_n;
  logic         lp_valid;
  logic [511:0] lp_data;
  logic         pl_valid;
  logic [511:0] pl_data;
  // Die A's DEST_RP map for AOU_FDI_CHECKER, {RP3, RP2, RP1, RP0}.
  logic [7:0]   dest_rp = 8'hE4;

  clocking drv_cb @(posedge clk);
    output lp_valid, lp_data, pl_valid, pl_data, dest_rp;
  endclocking

  clocking mon_cb @(posedge clk);
    input rst_n;
  endclocking
endinterface
