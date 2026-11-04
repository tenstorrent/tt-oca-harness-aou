// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// FDI link-state handshakes (UCIe r1.1 §8.2.3, §8.2.7, Table 8-2), shared by
// every FDI of the link. pl_state_sts is per FDI and lives on ucie_fdi_mb_if.
// Signals of the Protocol Layer under test that are not FDI (software pins,
// status outputs) belong on an interface of the bench's own.

interface ucie_fdi_lsm_if (
    input logic clk,
    input logic rst_n
);

  // Adapter to Protocol Layer
  logic       pl_inband_pres;
  logic       pl_clk_req;
  logic       pl_wake_ack;
  logic       pl_rx_active_req;

  // Protocol Layer to Adapter
  logic [3:0] lp_state_req;
  logic       lp_wake_req;
  logic       lp_clk_ack;
  logic       lp_rx_active_sts;
  logic       lp_linkerror;           // tie 0 when the Protocol Layer has none

  clocking drv_cb @(posedge clk);
    output pl_inband_pres, pl_clk_req, pl_wake_ack, pl_rx_active_req;
    input  lp_state_req, lp_wake_req, lp_clk_ack, lp_rx_active_sts, lp_linkerror, rst_n;
  endclocking

  clocking mon_cb @(posedge clk);
    input pl_inband_pres, pl_clk_req, pl_wake_ack, pl_rx_active_req,
          lp_state_req, lp_wake_req, lp_clk_ack, lp_rx_active_sts, lp_linkerror, rst_n;
  endclocking

endinterface
