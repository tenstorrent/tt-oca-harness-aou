// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// The DUT's bringup pins that are not part of the FDI (integrator guide
// §3.14-3.16): the PHY select, the bringup software pins, the bringup status,
// and the core-to-bringup triggers and activation state the bringup reference
// model and the AXI protocol-checker control need. The FDI link-state signals
// themselves are on the UCIe model's ucie_fdi_lsm_if.

interface aou_bringup_if (
    input logic clk,
    input logic rst_n
);

  logic       phy_type;               // TWO_PHY builds: PHY whose state the DUT follows

  // Bringup software pins (not SFR-mapped)
  logic       sw_activate_start;
  logic       sw_linkerror_inject;

  // Bringup status
  logic [3:0] fdi_fsm_state;
  logic       fdi_link_up;

  // Core-to-bringup triggers the reference model needs, and the activation
  // state for the AXI protocol-checker control. The top connects them from
  // the DUT's interrupt outputs and its internal wires.
  logic       int_activate_start;
  logic       int_req_linkreset;
  logic       int_fdi_link_down;      // INT_FDI_LINK_DOWN: link lost with AoU in use
  logic       act_st_disabled;
  logic       sw_reset;               // AOU_CON0.AOU_SW_RESET in effect (AOU_CORE in reset)

  clocking drv_cb @(posedge clk);
    output phy_type, sw_activate_start, sw_linkerror_inject;
    input  rst_n;
  endclocking

  clocking mon_cb @(posedge clk);
    input phy_type, sw_activate_start, sw_linkerror_inject, fdi_fsm_state, fdi_link_up,
          int_activate_start, int_req_linkreset, int_fdi_link_down, act_st_disabled, sw_reset,
          rst_n;
  endclocking

endinterface
