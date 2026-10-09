// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 VNCHIPLabs
// *****************************************************************************
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// *****************************************************************************
//
//  Interface  : aou_fdi_if
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
interface aou_fdi_if #(
    // Must match aou_tb_top.sv's FDI_DATA_W: Verilator generates a
    // distinct C++ class per interface parameterization.  The UVM package
    // and top-level config_db entries spell out DATA_W explicitly; an
    // otherwise equivalent unparameterized virtual-interface type can
    // remain distinct in generated C++, causing a compile-time mismatch.
    // The physical FDI profile is independently configurable from AXI width.
    parameter int DATA_W =
`ifdef AOU_FDI_DATA_W
      `AOU_FDI_DATA_W
`elsif AOU_AXI_DATA_BYTES
      (`AOU_AXI_DATA_BYTES == 128) ? 1024 :
      (`AOU_AXI_DATA_BYTES == 32)  ? 256  : 512
`else
      512
`endif
) (
    input logic clk,
    input logic resetn
);

  // RX into DUT (AOU_RX_CORE side)
  logic                 pl_valid;
  logic [DATA_W-1:0]    pl_data;
  logic                 pl_flit_cancel;

  // TX out of DUT (AOU_TX_CORE side)
  logic                 pl_trdy;
  logic                 pl_stallreq;
  logic [3:0]            pl_state_sts;
  logic [DATA_W-1:0]    lp_data;
  logic                 lp_valid;
  logic                 lp_irdy;
  logic                 lp_stallack;

  localparam logic [3:0] STATE_STS_RST    = 4'b0000;
  localparam logic [3:0] STATE_STS_ACTIVE = 4'b0001;

  clocking rx_cb @(posedge clk);   // driven by the FDI RX driver (us -> DUT)
    output pl_valid, pl_data, pl_flit_cancel;
  endclocking

  clocking tx_cb @(posedge clk);   // sampled by the FDI TX monitor (DUT -> us)
    input lp_data, lp_valid, lp_irdy, lp_stallack;
    output pl_trdy, pl_stallreq, pl_state_sts;
  endclocking

  modport rx  (clocking rx_cb, input clk, resetn);
  modport tx  (clocking tx_cb, input clk, resetn);
  modport dut (
    input  pl_valid, pl_data, pl_flit_cancel,
    input  pl_trdy, pl_stallreq, pl_state_sts,
    output lp_data, lp_valid, lp_irdy, lp_stallack
  );

  // Passive property observation port.  All boundary signals are
  // inputs to the monitor, including the peer-driven RX side, so the monitor
  // cannot alter partner or DUT behavior.
  modport monitor (
    input clk, resetn,
    input pl_valid, pl_data, pl_flit_cancel,
          pl_trdy, pl_stallreq, pl_state_sts,
          lp_data, lp_valid, lp_irdy, lp_stallack
  );

endinterface
