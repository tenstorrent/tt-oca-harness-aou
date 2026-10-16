// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
// SPDX-FileCopyrightText: © 2026 VNCHIPLabs
// Derived from PR #80 intf/aou_axi_if.sv (VNCHIPLabs, Apache-2.0): signal set and
// the two clocking blocks.

// One AXI4 port. Instantiate at DATA_W=1024 so every agent shares one virtual
// interface type; the agent config carries the real width, and the unused upper
// lanes stay zero.
interface aou_axi_bus_if #(
  parameter int DATA_W = 1024
) (
  input logic clk,
  input logic resetn
);
  localparam int ID_W   = 10;
  localparam int ADDR_W = 64;
  localparam int LEN_W  = 8;
  localparam int STRB_W = DATA_W / 8;

  logic [ID_W-1:0]   awid;
  logic [ADDR_W-1:0] awaddr;
  logic [LEN_W-1:0]  awlen;
  logic [2:0]        awsize;
  logic [1:0]        awburst;
  logic              awlock;
  logic [3:0]        awcache;
  logic [2:0]        awprot;
  logic [3:0]        awqos;
  logic              awvalid;
  logic              awready;

  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;

  logic [ID_W-1:0]   bid;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;

  logic [ID_W-1:0]   arid;
  logic [ADDR_W-1:0] araddr;
  logic [LEN_W-1:0]  arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic              arlock;
  logic [3:0]        arcache;
  logic [2:0]        arprot;
  logic [3:0]        arqos;
  logic              arvalid;
  logic              arready;

  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;

  // Manager: drives AW/W/AR and the B/R ready signals.
  clocking mgr_cb @(posedge clk);
    input  resetn;
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

  // Subordinate: drives the AW/W/AR ready signals and B/R.
  clocking sub_cb @(posedge clk);
    input  resetn;
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

  clocking mon_cb @(posedge clk);
    input resetn;
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  modport mgr (clocking mgr_cb);
  modport sub (clocking sub_cb);
  modport mon (clocking mon_cb);

endinterface
