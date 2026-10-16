// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// FDI mainband of one PHY, seen from the Adapter (PL) side. The bus is
// always DATA_W wide so every PHY shares one virtual-interface type; the
// agent config holds the real beat width and the top slices the bus.

interface aou_fdi_mb_if #(
    parameter int DATA_W = 1024
) (
    input logic clk,
    input logic rst_n
);

  // Adapter to Protocol Layer (DUT RX)
  logic              pl_valid;
  logic [DATA_W-1:0] pl_data;
  logic              pl_flit_cancel;

  // Protocol Layer to Adapter (DUT TX)
  logic              pl_trdy;
  logic [DATA_W-1:0] lp_data;
  logic              lp_valid;
  logic              lp_irdy;

  logic              pl_stallreq;
  logic              lp_stallack;
  logic [3:0]        pl_state_sts;

  // L1: mainband stimulus and TX responder.
  clocking drv_cb @(posedge clk);
    output pl_valid, pl_data, pl_flit_cancel, pl_trdy, pl_stallreq;
    input  lp_valid, lp_irdy, lp_stallack, rst_n;
  endclocking

  // L2: link state of this PHY.
  clocking lsm_cb @(posedge clk);
    output pl_state_sts;
  endclocking

  clocking mon_cb @(posedge clk);
    input pl_valid, pl_data, pl_flit_cancel, pl_trdy, pl_stallreq, pl_state_sts,
          lp_data, lp_valid, lp_irdy, lp_stallack, rst_n;
  endclocking

endinterface
