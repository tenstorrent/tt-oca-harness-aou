// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reset requests from the T1 reset agent (config_db key "rst"). The top ANDs
// resetn/presetn with its power-on reset, so a bench without the agent still
// comes out of reset; rst_n/prst_n are what the DUT actually sees. core_rst_n is
// the reset the DUT core itself sees (I_RESETN and AOU_SW_RESET), read from the DUT.
// port_iso[r] is 1 while the BUGS/021 guard isolates RP r's AXI ports from the
// core (always 0 without the guard). rx_w_pend[r] is RP r's RX W FIFO output
// valid towards the M port (BUGS/007). apb_psel is the APB master's PSEL and
// apb_bridge_idle is 1 when the async APB bridge's request/done handshake is
// back at idle in both clock domains (both FSMs idle, req and done low, both
// synchroniser outputs low); apb_quiet is the two together, the precondition
// for asserting I_RESETN or I_PRESETN (integration guide 3.1.1). dft_modescan
// drives TIEL_DFT_MODESCAN (0 outside the DFT test).
interface aou_rst_if (input logic clk, input logic pclk);
  logic resetn = 1'b1;
  logic presetn = 1'b1;
  logic dft_modescan = 1'b0;
  logic rst_n;
  logic prst_n;
  logic core_rst_n;
  logic [7:0] port_iso;
  logic [7:0] rx_w_pend;
  logic apb_psel;
  logic apb_bridge_idle;
  wire  apb_quiet = apb_psel === 1'b0 && apb_bridge_idle === 1'b1;

  clocking drv_cb @(posedge clk);
    output resetn, dft_modescan;
    input  rst_n;
  endclocking

  clocking pdrv_cb @(posedge pclk);
    output presetn;
    input  prst_n;
  endclocking

  clocking mon_cb @(posedge clk);
    input rst_n, prst_n, core_rst_n, port_iso, rx_w_pend, apb_quiet, dft_modescan;
  endclocking

  clocking pmon_cb @(posedge pclk);
    input apb_quiet;
  endclocking
endinterface
