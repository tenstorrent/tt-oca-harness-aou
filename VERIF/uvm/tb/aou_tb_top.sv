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
//  Module     : aou_tb_top
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
`timescale 1ns/1ps

module aou_tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import packet_def_pkg::*;
  import aou_pkg::*;
  import aou_uvm_pkg::*;

  // ---------------------------------------------------------------------
  // Clocks / resets -- matches VERIF/tests/dut_setup.py: CORE_CLK_PERIOD_NS=1,
  // APB_CLK_PERIOD_NS=10, both resets held low >=20 pclk cycles then
  // released together, active-low.
  // ---------------------------------------------------------------------
  logic clk;
  logic pclk;

  initial clk  = 1'b0;
  always  #0.5 clk  = ~clk;   // 1ns period

  initial pclk = 1'b0;
  always  #5.0 pclk = ~pclk;  // 10ns period

  // Physical reset signals are driven here and connected directly to the DUT.
  aou_reset_if reset_if();

  initial begin
    reset_if.resetn  = 1'b0;
    reset_if.presetn = 1'b0;
    repeat (25) @(posedge pclk);
    reset_if.resetn  = 1'b1;
    reset_if.presetn = 1'b1;
  end

  // ---------------------------------------------------------------------
  // Interfaces
  // ---------------------------------------------------------------------
  localparam int RP_COUNT   = `AOU_RP_COUNT;
  // The public smoke uses 512-bit AXI and a single SP64B FDI lane.
  localparam int AXI_DATA_W = aou_pkg::AXI_DATA_W;
  localparam int FDI_DATA_W = aou_pkg::FDI_DATA_W;
  localparam int FDI_CONFIG = FDI_CFG_SP_64B;

  aou_axi_if    #(.ID_W(10), .ADDR_W(64), .LEN_W(8), .DATA_W(AXI_DATA_W))
                s_axi_if [RP_COUNT] (.clk(clk), .resetn(reset_if.resetn));
  aou_axi_if    #(.ID_W(10), .ADDR_W(64), .LEN_W(8), .DATA_W(AXI_DATA_W))
                m_axi_if [RP_COUNT] (.clk(clk), .resetn(reset_if.resetn));
  aou_fdi_if    #(.DATA_W(FDI_DATA_W)) fdi_if (.clk(clk), .resetn(reset_if.resetn));
  aou_apb_if    #(.ADDR_W(32), .DATA_W(32)) apb_if (.pclk(pclk), .presetn(reset_if.presetn));
  aou_status_if status_if ();
  // Per-RP signal-array binding -- packs/unpacks each s_axi_if[i] /
  // m_axi_if[i]'s flat signals into the [RP_COUNT-1:0] arrays the DUT
  // ports expect. S-port direction matches init_cb (testbench drives
  // AW/W/AR, DUT drives ready/B/R); M-port direction is reversed (DUT
  // drives AW/W/AR, testbench's target driver drives ready/B/R).
  // ---------------------------------------------------------------------
  wire [RP_COUNT-1:0][9:0]   s_awid;    wire [RP_COUNT-1:0][63:0] s_awaddr;
  wire [RP_COUNT-1:0][9:0]   s_awid_dut; wire [RP_COUNT-1:0][63:0] s_awaddr_dut;
  wire [RP_COUNT-1:0][7:0]   s_awlen;   wire [RP_COUNT-1:0][2:0]  s_awsize;
  wire [RP_COUNT-1:0][1:0]   s_awburst; wire [RP_COUNT-1:0]       s_awlock;
  wire [RP_COUNT-1:0][3:0]   s_awcache; wire [RP_COUNT-1:0][2:0]  s_awprot;
  wire [RP_COUNT-1:0][3:0]   s_awqos;   wire [RP_COUNT-1:0]       s_awvalid;
  wire [RP_COUNT-1:0]        s_awready;

  wire [RP_COUNT-1:0][AXI_DATA_W-1:0]   s_wdata;
  wire [RP_COUNT-1:0][AXI_DATA_W-1:0]   s_wdata_dut;
  wire [RP_COUNT-1:0][AXI_DATA_W/8-1:0] s_wstrb;
  wire [RP_COUNT-1:0]        s_wlast;   wire [RP_COUNT-1:0]       s_wvalid;
  wire [RP_COUNT-1:0]        s_wready;

  wire [RP_COUNT-1:0][9:0]   s_bid_dut; wire [RP_COUNT-1:0][1:0]  s_bresp_dut;
  wire [RP_COUNT-1:0][9:0]   s_bid;     wire [RP_COUNT-1:0][1:0]  s_bresp;
  wire [RP_COUNT-1:0]        s_bvalid;  wire [RP_COUNT-1:0]       s_bready;

  wire [RP_COUNT-1:0][9:0]   s_arid;    wire [RP_COUNT-1:0][63:0] s_araddr;
  wire [RP_COUNT-1:0][9:0]   s_arid_dut; wire [RP_COUNT-1:0][63:0] s_araddr_dut;
  wire [RP_COUNT-1:0][7:0]   s_arlen;   wire [RP_COUNT-1:0][2:0]  s_arsize;
  wire [RP_COUNT-1:0][1:0]   s_arburst; wire [RP_COUNT-1:0]       s_arlock;
  wire [RP_COUNT-1:0][3:0]   s_arcache; wire [RP_COUNT-1:0][2:0]  s_arprot;
  wire [RP_COUNT-1:0][3:0]   s_arqos;   wire [RP_COUNT-1:0]       s_arvalid;
  wire [RP_COUNT-1:0]        s_arready;

  wire [RP_COUNT-1:0][9:0]   s_rid;     wire [RP_COUNT-1:0][AXI_DATA_W-1:0] s_rdata;
  wire [RP_COUNT-1:0][1:0]   s_rresp;   wire [RP_COUNT-1:0]       s_rlast;
  wire [RP_COUNT-1:0]        s_rvalid;  wire [RP_COUNT-1:0]       s_rready;

  wire [RP_COUNT-1:0][9:0]   m_awid;    wire [RP_COUNT-1:0][63:0] m_awaddr;
  wire [RP_COUNT-1:0][7:0]   m_awlen;   wire [RP_COUNT-1:0][2:0]  m_awsize;
  wire [RP_COUNT-1:0][1:0]   m_awburst; wire [RP_COUNT-1:0]       m_awlock;
  wire [RP_COUNT-1:0][3:0]   m_awcache; wire [RP_COUNT-1:0][2:0]  m_awprot;
  wire [RP_COUNT-1:0][3:0]   m_awqos;   wire [RP_COUNT-1:0]       m_awvalid;
  wire [RP_COUNT-1:0]        m_awready;

  wire [RP_COUNT-1:0][AXI_DATA_W-1:0]   m_wdata;
  wire [RP_COUNT-1:0][AXI_DATA_W/8-1:0] m_wstrb_dut;
  wire [RP_COUNT-1:0]        m_wlast_dut;
  wire [RP_COUNT-1:0][AXI_DATA_W/8-1:0] m_wstrb;
  wire [RP_COUNT-1:0]        m_wlast;   wire [RP_COUNT-1:0]       m_wvalid;
  wire [RP_COUNT-1:0]        m_wready;

  wire [RP_COUNT-1:0][9:0]   m_bid;     wire [RP_COUNT-1:0][1:0]  m_bresp;
  wire [RP_COUNT-1:0]        m_bvalid;  wire [RP_COUNT-1:0]       m_bready;

  wire [RP_COUNT-1:0][9:0]   m_arid;    wire [RP_COUNT-1:0][63:0] m_araddr;
  wire [RP_COUNT-1:0][7:0]   m_arlen;   wire [RP_COUNT-1:0][2:0]  m_arsize;
  wire [RP_COUNT-1:0][1:0]   m_arburst; wire [RP_COUNT-1:0]       m_arlock;
  wire [RP_COUNT-1:0][3:0]   m_arcache; wire [RP_COUNT-1:0][2:0]  m_arprot;
  wire [RP_COUNT-1:0][3:0]   m_arqos;   wire [RP_COUNT-1:0]       m_arvalid;
  wire [RP_COUNT-1:0]        m_arready;

  wire [RP_COUNT-1:0][9:0]   m_rid;     wire [RP_COUNT-1:0][AXI_DATA_W-1:0] m_rdata;
  wire [RP_COUNT-1:0][1:0]   m_rresp;   wire [RP_COUNT-1:0]       m_rlast;
  wire [RP_COUNT-1:0]        m_rvalid;  wire [RP_COUNT-1:0]       m_rready;

  genvar gr;
  generate
    for (gr = 0; gr < RP_COUNT; gr++) begin : g_axi_bind
      // S-port: testbench (aou_axi_driver) drives AW/W/AR + BREADY/RREADY;
      // DUT drives AWREADY/WREADY/ARREADY + B/R.
      assign s_awid[gr]    = s_axi_if[gr].awid;
      assign s_awaddr[gr]  = s_axi_if[gr].awaddr;
      assign s_awlen[gr]   = s_axi_if[gr].awlen;
      assign s_awsize[gr]  = s_axi_if[gr].awsize;
      assign s_awburst[gr] = s_axi_if[gr].awburst;
      assign s_awlock[gr]  = s_axi_if[gr].awlock;
      assign s_awcache[gr] = s_axi_if[gr].awcache;
      assign s_awprot[gr]  = s_axi_if[gr].awprot;
      assign s_awqos[gr]   = s_axi_if[gr].awqos;
      assign s_awvalid[gr] = s_axi_if[gr].awvalid;
      assign s_axi_if[gr].awready = s_awready[gr];

      assign s_wdata[gr]  = s_axi_if[gr].wdata;
      assign s_wstrb[gr]  = s_axi_if[gr].wstrb;
      assign s_wlast[gr]  = s_axi_if[gr].wlast;
      assign s_wvalid[gr] = s_axi_if[gr].wvalid;
      assign s_axi_if[gr].wready = s_wready[gr];

      assign s_axi_if[gr].bid    = s_bid[gr];
      assign s_axi_if[gr].bresp  = s_bresp[gr];
      assign s_axi_if[gr].bvalid = s_bvalid[gr];
      assign s_bready[gr] = s_axi_if[gr].bready;

      assign s_arid[gr]    = s_axi_if[gr].arid;
      assign s_araddr[gr]  = s_axi_if[gr].araddr;
      assign s_arlen[gr]   = s_axi_if[gr].arlen;
      assign s_arsize[gr]  = s_axi_if[gr].arsize;
      assign s_arburst[gr] = s_axi_if[gr].arburst;
      assign s_arlock[gr]  = s_axi_if[gr].arlock;
      assign s_arcache[gr] = s_axi_if[gr].arcache;
      assign s_arprot[gr]  = s_axi_if[gr].arprot;
      assign s_arqos[gr]   = s_axi_if[gr].arqos;
      assign s_arvalid[gr] = s_axi_if[gr].arvalid;
      assign s_axi_if[gr].arready = s_arready[gr];

      assign s_axi_if[gr].rid    = s_rid[gr];
      assign s_axi_if[gr].rdata  = s_rdata[gr];
      assign s_axi_if[gr].rresp  = s_rresp[gr];
      assign s_axi_if[gr].rlast  = s_rlast[gr];
      assign s_axi_if[gr].rvalid = s_rvalid[gr];
      assign s_rready[gr] = s_axi_if[gr].rready;

      // M-port: DUT drives AW/W/AR + BREADY/RREADY; testbench
      // (aou_axi_target_driver) drives AWREADY/WREADY/ARREADY + B/R.
      assign m_axi_if[gr].awid    = m_awid[gr];
      assign m_axi_if[gr].awaddr  = m_awaddr[gr];
      assign m_axi_if[gr].awlen   = m_awlen[gr];
      assign m_axi_if[gr].awsize  = m_awsize[gr];
      assign m_axi_if[gr].awburst = m_awburst[gr];
      assign m_axi_if[gr].awlock  = m_awlock[gr];
      assign m_axi_if[gr].awcache = m_awcache[gr];
      assign m_axi_if[gr].awprot  = m_awprot[gr];
      assign m_axi_if[gr].awqos   = m_awqos[gr];
      assign m_axi_if[gr].awvalid = m_awvalid[gr];
      assign m_awready[gr] = m_axi_if[gr].awready;

      assign m_axi_if[gr].wdata  = m_wdata[gr];
      assign m_axi_if[gr].wstrb  = m_wstrb[gr];
      assign m_axi_if[gr].wlast  = m_wlast[gr];
      assign m_axi_if[gr].wvalid = m_wvalid[gr];
      assign m_wready[gr] = m_axi_if[gr].wready;

      assign m_bid[gr]    = m_axi_if[gr].bid;
      assign m_bresp[gr]  = m_axi_if[gr].bresp;
      assign m_bvalid[gr] = m_axi_if[gr].bvalid;
      assign m_axi_if[gr].bready = m_bready[gr];

      assign m_axi_if[gr].arid    = m_arid[gr];
      assign m_axi_if[gr].araddr  = m_araddr[gr];
      assign m_axi_if[gr].arlen   = m_arlen[gr];
      assign m_axi_if[gr].arsize  = m_arsize[gr];
      assign m_axi_if[gr].arburst = m_arburst[gr];
      assign m_axi_if[gr].arlock  = m_arlock[gr];
      assign m_axi_if[gr].arcache = m_arcache[gr];
      assign m_axi_if[gr].arprot  = m_arprot[gr];
      assign m_axi_if[gr].arqos   = m_arqos[gr];
      assign m_axi_if[gr].arvalid = m_arvalid[gr];
      assign m_arready[gr] = m_axi_if[gr].arready;

      assign m_rid[gr]    = m_axi_if[gr].rid;
      assign m_rdata[gr]  = m_axi_if[gr].rdata;
      assign m_rresp[gr]  = m_axi_if[gr].rresp;
      assign m_rlast[gr]  = m_axi_if[gr].rlast;
      assign m_rvalid[gr] = m_axi_if[gr].rvalid;
      assign m_axi_if[gr].rready = m_rready[gr];
    end
  endgenerate

  generate
    for (gr = 0; gr < RP_COUNT; gr++) begin : g_axi_bypass
      assign s_awid_dut[gr] = s_awid[gr];
      assign s_awaddr_dut[gr] = s_awaddr[gr];
      assign s_arid_dut[gr] = s_arid[gr];
      assign s_araddr_dut[gr] = s_araddr[gr];
      assign s_wdata_dut[gr] = s_wdata[gr];
      assign s_bid[gr] = s_bid_dut[gr];
      assign s_bresp[gr] = s_bresp_dut[gr];
      assign m_wstrb[gr] = m_wstrb_dut[gr];
      assign m_wlast[gr] = m_wlast_dut[gr];
    end
  endgenerate

  // DUT
  // ---------------------------------------------------------------------
  AOU_CORE_TOP #(
      .RP_COUNT       (RP_COUNT),
      .FDI_CONFIG     (FDI_CONFIG),
      .RP0_AXI_DATA_WD(AXI_DATA_W),
      .RP1_AXI_DATA_WD(AXI_DATA_W),
      .RP2_AXI_DATA_WD(AXI_DATA_W),
      .RP3_AXI_DATA_WD(AXI_DATA_W)
  ) u_dut (
      .I_CLK    (clk),
      .I_RESETN (reset_if.resetn),
      .I_PCLK   (pclk),
      .I_PRESETN(reset_if.presetn),

      // APB
      .I_AOU_APB_SI0_PSEL   (apb_if.psel),
      .I_AOU_APB_SI0_PENABLE(apb_if.penable),
      .I_AOU_APB_SI0_PADDR  (apb_if.paddr),
      .I_AOU_APB_SI0_PWRITE (apb_if.pwrite),
      .I_AOU_APB_SI0_PWDATA (apb_if.pwdata),
      .O_AOU_APB_SI0_PRDATA (apb_if.prdata),
      .O_AOU_APB_SI0_PREADY (apb_if.pready),
      .O_AOU_APB_SI0_PSLVERR(apb_if.pslverr),

      // AXI MI I/F (downstream target side) -- served by aou_axi_target_driver
      // via m_axi_if[i].target_cb, one instance per RP (reverse direction:
      // FDI-RX-injected WriteReq/ReadReq -> Unpacker -> this port ->
      // target driver's response -> Packer relays WriteResp/ReadData back
      // out FDI-TX).
      .O_AOU_RX_AXI_M_ARID   (m_arid),   .O_AOU_RX_AXI_M_ARADDR(m_araddr),
      .O_AOU_RX_AXI_M_ARLEN  (m_arlen),  .O_AOU_RX_AXI_M_ARSIZE(m_arsize),
      .O_AOU_RX_AXI_M_ARBURST(m_arburst),.O_AOU_RX_AXI_M_ARLOCK(m_arlock),
      .O_AOU_RX_AXI_M_ARCACHE(m_arcache),.O_AOU_RX_AXI_M_ARPROT(m_arprot),
      .O_AOU_RX_AXI_M_ARQOS  (m_arqos),  .O_AOU_RX_AXI_M_ARVALID(m_arvalid),
      .I_AOU_RX_AXI_M_ARREADY(m_arready),

      .I_AOU_TX_AXI_M_RID   (m_rid),   .I_AOU_TX_AXI_M_RDATA(m_rdata),
      .I_AOU_TX_AXI_M_RRESP (m_rresp), .I_AOU_TX_AXI_M_RLAST(m_rlast),
      .I_AOU_TX_AXI_M_RVALID(m_rvalid), .O_AOU_TX_AXI_M_RREADY(m_rready),

      .O_AOU_RX_AXI_M_AWID   (m_awid),   .O_AOU_RX_AXI_M_AWADDR(m_awaddr),
      .O_AOU_RX_AXI_M_AWLEN  (m_awlen),  .O_AOU_RX_AXI_M_AWSIZE(m_awsize),
      .O_AOU_RX_AXI_M_AWBURST(m_awburst),.O_AOU_RX_AXI_M_AWLOCK(m_awlock),
      .O_AOU_RX_AXI_M_AWCACHE(m_awcache),.O_AOU_RX_AXI_M_AWPROT(m_awprot),
      .O_AOU_RX_AXI_M_AWQOS  (m_awqos),  .O_AOU_RX_AXI_M_AWVALID(m_awvalid),
      .I_AOU_RX_AXI_M_AWREADY(m_awready),

      .O_AOU_RX_AXI_M_WDATA(m_wdata), .O_AOU_RX_AXI_M_WSTRB(m_wstrb_dut),
      .O_AOU_RX_AXI_M_WLAST(m_wlast_dut), .O_AOU_RX_AXI_M_WVALID(m_wvalid),
      .I_AOU_RX_AXI_M_WREADY(m_wready),

      .I_AOU_TX_AXI_M_BID(m_bid), .I_AOU_TX_AXI_M_BRESP(m_bresp),
      .I_AOU_TX_AXI_M_BVALID(m_bvalid), .O_AOU_TX_AXI_M_BREADY(m_bready),

      // AXI SI I/F (local initiator side) -- driven by aou_axi_driver, one
      // instance per RP.
      .I_AOU_TX_AXI_S_ARID   (s_arid_dut),   .I_AOU_TX_AXI_S_ARADDR(s_araddr_dut),
      .I_AOU_TX_AXI_S_ARLEN  (s_arlen),  .I_AOU_TX_AXI_S_ARSIZE(s_arsize),
      .I_AOU_TX_AXI_S_ARBURST(s_arburst),.I_AOU_TX_AXI_S_ARLOCK(s_arlock),
      .I_AOU_TX_AXI_S_ARCACHE(s_arcache),.I_AOU_TX_AXI_S_ARPROT(s_arprot),
      .I_AOU_TX_AXI_S_ARQOS  (s_arqos),  .I_AOU_TX_AXI_S_ARVALID(s_arvalid),
      .O_AOU_TX_AXI_S_ARREADY(s_arready),

      .O_AOU_RX_AXI_S_RID  (s_rid),   .O_AOU_RX_AXI_S_RDATA(s_rdata),
      .O_AOU_RX_AXI_S_RRESP(s_rresp), .O_AOU_RX_AXI_S_RLAST(s_rlast),
      .O_AOU_RX_AXI_S_RVALID(s_rvalid), .I_AOU_RX_AXI_S_RREADY(s_rready),

      .I_AOU_TX_AXI_S_AWID   (s_awid_dut),   .I_AOU_TX_AXI_S_AWADDR(s_awaddr_dut),
      .I_AOU_TX_AXI_S_AWLEN  (s_awlen),  .I_AOU_TX_AXI_S_AWSIZE(s_awsize),
      .I_AOU_TX_AXI_S_AWBURST(s_awburst),.I_AOU_TX_AXI_S_AWLOCK(s_awlock),
      .I_AOU_TX_AXI_S_AWCACHE(s_awcache),.I_AOU_TX_AXI_S_AWPROT(s_awprot),
      .I_AOU_TX_AXI_S_AWQOS  (s_awqos),  .I_AOU_TX_AXI_S_AWVALID(s_awvalid),
      .O_AOU_TX_AXI_S_AWREADY(s_awready),

      .I_AOU_TX_AXI_S_WDATA(s_wdata_dut), .I_AOU_TX_AXI_S_WSTRB(s_wstrb),
      .I_AOU_TX_AXI_S_WLAST(s_wlast), .I_AOU_TX_AXI_S_WVALID(s_wvalid),
      .O_AOU_TX_AXI_S_WREADY(s_wready),

      .O_AOU_RX_AXI_S_BID(s_bid_dut), .O_AOU_RX_AXI_S_BRESP(s_bresp_dut),
      .O_AOU_RX_AXI_S_BVALID(s_bvalid), .I_AOU_RX_AXI_S_BREADY(s_bready),

      // Single-PHY SP64B partner connection used by the public smoke.
      .I_FDI_PL_0_VALID      (fdi_if.pl_valid),
      .I_FDI_PL_0_DATA       (fdi_if.pl_data),
      .I_FDI_PL_0_FLIT_CANCEL(fdi_if.pl_flit_cancel),
      .I_FDI_PL_0_TRDY       (fdi_if.pl_trdy),
      .I_FDI_PL_0_STALLREQ   (fdi_if.pl_stallreq),
      .I_FDI_PL_0_STATE_STS  (fdi_if.pl_state_sts),
      .O_FDI_LP_0_DATA       (fdi_if.lp_data),
      .O_FDI_LP_0_VALID      (fdi_if.lp_valid),
      .O_FDI_LP_0_IRDY       (fdi_if.lp_irdy),
      .O_FDI_LP_0_STALLACK   (fdi_if.lp_stallack),

      // Error/interrupt outputs -- observed only, see aou_status_if
      .INT_REQ_LINKRESET   (status_if.req_linkreset),
      .INT_SI0_ID_MISMATCH (status_if.int_si0_id_mismatch),
      .INT_MI0_ID_MISMATCH (status_if.int_mi0_id_mismatch),
      .INT_EARLY_RESP_ERR  (status_if.int_early_resp_err),
      .INT_ACTIVATE_START  (status_if.int_activate_start),
      .INT_DEACTIVATE_START(status_if.int_deactivate_start),

      // UCIE_CORE handshake -- this testbench stands in for the link/PHY
      // bring-up controller AOU_CORE_TOP expects. The smoke holds these
      // inputs active and does not exercise deactivation.
      .I_INT_FSM_IN_ACTIVE      (1'b1),
      .I_MST_BUS_CLEANY_COMPLETE(1'b1),
      .I_SLV_BUS_CLEANY_COMPLETE(1'b1),
      .O_AOU_ACTIVATE_ST_DISABLED(status_if.activate_st_disabled),
      .O_AOU_ACTIVATE_ST_ENABLED (status_if.activate_st_enabled),
      .O_AOU_REQ_LINKRESET       (status_if.o_aou_req_linkreset),

      .TIEL_DFT_MODESCAN(1'b0)
  );

  generate
    for (gr = 0; gr < RP_COUNT; gr++) begin : g_vif_cfg
      initial begin
        uvm_config_db#(virtual aou_axi_if #(.ID_W(10), .ADDR_W(64), .LEN_W(8), .DATA_W(AXI_DATA_W)))::set(null, $sformatf("uvm_test_top.env.axi_agt[%0d].drv", gr), "vif", s_axi_if[gr]);
        uvm_config_db#(virtual aou_axi_if #(.ID_W(10), .ADDR_W(64), .LEN_W(8), .DATA_W(AXI_DATA_W)))::set(null, $sformatf("uvm_test_top.env.m_drv[%0d]", gr), "vif", m_axi_if[gr]);
      end
    end
  endgenerate

  // ---------------------------------------------------------------------
  // UVM wiring + run
  // ---------------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual aou_fdi_if #(.DATA_W(FDI_DATA_W)))::set(null, "uvm_test_top.env.fdi_tx_mon", "vif", fdi_if);
    uvm_config_db#(virtual aou_fdi_if #(.DATA_W(FDI_DATA_W)))::set(null, "uvm_test_top.env.fdi_rx_drv", "vif", fdi_if);
    uvm_config_db#(virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)))::set(null, "uvm_test_top.env.apb_act", "vif", apb_if);
    uvm_config_db#(virtual aou_status_if.mon)::set(null, "uvm_test_top", "status_vif", status_if);
    run_test();
  end

endmodule
