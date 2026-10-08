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
//  Interface  : aou_axi_if
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
interface aou_axi_if #(
    parameter int ID_W   = 10,
    parameter int ADDR_W = 64,
    parameter int LEN_W  = 8,
    // MUST be kept equal to aou_pkg::AXI_DATA_W (i.e. AXI_DATA_BYTES*8)
    // whenever AXI_DATA_BYTES changes -- a plain literal, not a
    // package-scope reference, because Verilator generates a distinct
    // C++ class per interface parameterization and resolves a
    // package-referenced default inconsistently between this default and
    // the explicit `.DATA_W(...)` at instantiation, producing a
    // compile-time C++ type mismatch (same class of issue hit and fixed
    // for aou_fdi_if's DATA_W with a plain literal there too). This
    // default is what unparameterized virtual interface handles
    // (aou_axi_driver/aou_axi_target_driver's `virtual aou_axi_if vif;`)
    // resolve to, so it must match the width actually instantiated in
    // aou_tb_top.sv.
    parameter int DATA_W =
`ifdef AOU_AXI_DATA_BYTES
      `AOU_AXI_DATA_BYTES * 8
`else
      512
`endif
) (
    input logic clk,
    input logic resetn
);

  // AW
  logic [ID_W-1:0]   awid;
  logic [ADDR_W-1:0] awaddr;
  logic [LEN_W-1:0]  awlen;
  logic [2:0]        awsize;
  logic [1:0]        awburst;
  logic               awlock;
  logic [3:0]        awcache;
  logic [2:0]        awprot;
  logic [3:0]        awqos;
  logic               awvalid;
  logic               awready;

  // W
  logic [DATA_W-1:0]   wdata;
  logic [DATA_W/8-1:0] wstrb;
  logic                 wlast;
  logic                 wvalid;
  logic                 wready;

  // B
  logic [ID_W-1:0] bid;
  logic [1:0]      bresp;
  logic             bvalid;
  logic             bready;

  // AR
  logic [ID_W-1:0]   arid;
  logic [ADDR_W-1:0] araddr;
  logic [LEN_W-1:0]  arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic               arlock;
  logic [3:0]        arcache;
  logic [2:0]        arprot;
  logic [3:0]        arqos;
  logic               arvalid;
  logic               arready;

  // R
  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic               rlast;
  logic               rvalid;
  logic               rready;

  clocking init_cb @(posedge clk);
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid;
    input  awready;
    output wdata, wstrb, wlast, wvalid;
    input  wready;
    input  bid, bresp, bvalid;
    output bready;
    output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid;
    input  arready;
    input  rid, rdata, rresp, rlast, rvalid;
    output rready;
  endclocking

  // target_cb: opposite direction of init_cb -- samples requests, drives
  // responses. Used by a passive AXI target/responder (e.g.
  // aou_axi_target_driver on the M-port).
  clocking target_cb @(posedge clk);
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid;
    output awready;
    input  wdata, wstrb, wlast, wvalid;
    output wready;
    output bid, bresp, bvalid;
    input  bready;
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid;
    output arready;
    output rid, rdata, rresp, rlast, rvalid;
    input  rready;
  endclocking

  // Passive full-boundary observation clocking block.  All channels are
  // inputs here, regardless of whether the interface instance is the local
  // S-port or M-port.  This avoids reading output clockvars from Verilator
  // while preserving edge-accurate sampling for the transaction oracle.
  clocking monitor_cb @(posedge clk);
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  // Passive property observation port.  This is deliberately a
  // signal-level input-only view; it does not expose any driver clocking
  // block or permit the property monitor to drive the interface.
  modport monitor (
    input clk, resetn,
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos,
          awvalid, awready,
    input wdata, wstrb, wlast, wvalid, wready,
    input bid, bresp, bvalid, bready,
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos,
          arvalid, arready,
    input rid, rdata, rresp, rlast, rvalid, rready
  );

  modport init   (clocking init_cb,   input clk, resetn);
  modport target (clocking target_cb, input clk, resetn);
  modport dut  (
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    output awready,
    input  wdata, wstrb, wlast, wvalid,
    output wready,
    output bid, bresp, bvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, rvalid,
    input  rready
  );

endinterface
