// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// FDI link-state handshakes (shared by both PHYs), the DUT's bringup software
// pins and its bringup status. pl_state_sts is per PHY and lives on
// aou_fdi_mb_if.

interface aou_fdi_lsm_if (
    input logic clk,
    input logic rst_n
);

  // Adapter to Protocol Layer
  logic       pl_inband_pres;
  logic       pl_clk_req;
  logic       pl_wake_ack;
  logic       pl_rx_active_req;
  logic       phy_type;               // TWO_PHY builds: PHY whose state the DUT follows

  // Protocol Layer to Adapter
  logic [3:0] lp_state_req;
  logic       lp_wake_req;
  logic       lp_clk_ack;
  logic       lp_rx_active_sts;
  logic       lp_linkerror;           // UCIe lp_linkerror; tied 0 by a top whose DUT lacks it

  // Bringup software pins (not SFR-mapped)
  logic       sw_activate_start;
  logic       sw_deactivate_start;
  logic       sw_retrain_req;
  logic       sw_linkerror_inject;

  // Bringup status
  logic [3:0] fdi_fsm_state;
  logic       fdi_link_up;

  // Core-to-bringup triggers the reference model needs. The top connects
  // them from the DUT's interrupt outputs and its activation state.
  logic       int_activate_start;
  logic       int_deactivate_start;
  logic       int_req_linkreset;
  logic       act_st_disabled;

  clocking drv_cb @(posedge clk);
    output pl_inband_pres, pl_clk_req, pl_wake_ack, pl_rx_active_req, phy_type,
           sw_activate_start, sw_deactivate_start, sw_retrain_req, sw_linkerror_inject;
    input  lp_state_req, lp_wake_req, lp_clk_ack, lp_rx_active_sts, lp_linkerror, rst_n;
  endclocking

  clocking mon_cb @(posedge clk);
    input pl_inband_pres, pl_clk_req, pl_wake_ack, pl_rx_active_req, phy_type,
          lp_state_req, lp_wake_req, lp_clk_ack, lp_rx_active_sts, lp_linkerror,
          sw_activate_start, sw_deactivate_start, sw_retrain_req, sw_linkerror_inject,
          fdi_fsm_state, fdi_link_up,
          int_activate_start, int_deactivate_start, int_req_linkreset, act_st_disabled,
          rst_n;
  endclocking

endinterface
