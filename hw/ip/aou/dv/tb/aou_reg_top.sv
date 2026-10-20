// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
// Derived from PR #80 tb/aou_tb_top.sv (VNCHIPLabs, Apache-2.0): clocks, reset
// release and the DUT's bring-up tie-offs.

// Register-only bench: AOU_CORE_TOP with its APB port driven by the APB agent and
// every other input held idle (no AXI traffic, FDI link in Reset). Built with
// make TB=reg until the T1 top hosts the register tests. The DUT parameters a
// target sets through defines (AOU_PEER_MAX_W, AOU_TX_NXT_PACKING; aou_reg_sim_cfg.toml)
// reach the DUT here as in tb_top, so a target's register runs are built on
// the DUT configuration they are labelled with.
`timescale 1ns/1ps

`ifndef AOU_PEER_MAX_W
`define AOU_PEER_MAX_W 1024
`endif
`ifndef AOU_TX_NXT_PACKING
`define AOU_TX_NXT_PACKING 0
`endif

module aou_reg_top;
  import uvm_pkg::*;
  import packet_def_pkg::*;
  import aou_reg_test_pkg::*;

  localparam int RP_COUNT = `AOU_RP_COUNT;
  localparam int AXI_W = 8 * `AOU_AXI_DATA_BYTES;
  localparam int FDI_W = `AOU_FDI_DATA_W;
  localparam int PEER_W = `AOU_PEER_MAX_W;
  localparam int NXT_PACK = `AOU_TX_NXT_PACKING;

  logic clk;
  logic pclk;
  logic resetn = 1'b0;
  logic presetn = 1'b0;

  int unsigned pclk_ps = 10000;   // +pclk_ps: PCLK period (CLK is 1000 ps)

  initial clk = 1'b0;
  always #0.5 clk = ~clk;
  initial begin
    pclk = 1'b0;
    void'($value$plusargs("pclk_ps=%d", pclk_ps));
    if (pclk_ps < 2) $fatal(1, "+pclk_ps=%0d: the PCLK period must be at least 2 ps", pclk_ps);
    if (pclk_ps != 10000) $info("PCLK period %0d ps (CLK 1000 ps)", pclk_ps);
    forever #(pclk_ps / 2000.0) pclk = ~pclk;
  end

  initial begin
    fork
      repeat (25) @(posedge pclk);
      repeat (25) @(posedge clk);
    join
    resetn  = 1'b1;
    presetn = 1'b1;
  end

  aou_apb_if #(.ADDR_W(32), .DATA_W(32)) apb_if (.pclk(pclk), .presetn(presetn));

  // Outputs the register tests don't observe.
  wire [RP_COUNT-1:0][9:0]        m_arid, m_awid, s_rid, s_bid;
  wire [RP_COUNT-1:0][63:0]       m_araddr, m_awaddr;
  wire [RP_COUNT-1:0][7:0]        m_arlen, m_awlen;
  wire [RP_COUNT-1:0][2:0]        m_arsize, m_awsize, m_arprot, m_awprot;
  wire [RP_COUNT-1:0][1:0]        m_arburst, m_awburst, s_rresp, s_bresp;
  wire [RP_COUNT-1:0][3:0]        m_arcache, m_awcache, m_arqos, m_awqos;
  wire [RP_COUNT-1:0]             m_arlock, m_awlock, m_arvalid, m_awvalid, m_wlast, m_wvalid;
  wire [RP_COUNT-1:0]             m_rready, m_bready, s_arready, s_awready, s_wready;
  wire [RP_COUNT-1:0]             s_rlast, s_rvalid, s_bvalid;
  wire [RP_COUNT-1:0][AXI_W-1:0]  m_wdata, s_rdata;
  wire [RP_COUNT-1:0][AXI_W/8-1:0] m_wstrb;
  wire [FDI_W-1:0]                lp_data;
  wire                            lp_valid, lp_irdy, lp_stallack;
  wire [6:0]                      irq;
  wire                            st_disabled, st_enabled, req_linkreset;

  AOU_CORE_TOP #(
      .RP_COUNT       (RP_COUNT),
      .FDI_CONFIG     (FDI_CFG_SP_64B),
      .RP0_AXI_DATA_WD(AXI_W),
      .RP1_AXI_DATA_WD(AXI_W),
      .RP2_AXI_DATA_WD(AXI_W),
      .RP3_AXI_DATA_WD(AXI_W),
      .AXI_PEER_DIE_MAX_DATA_WD(PEER_W),
      .TX_NXT_PACKING_EN(NXT_PACK)
  ) u_dut (
      .I_CLK    (clk),
      .I_RESETN (resetn),
      .I_PCLK   (pclk),
      .I_PRESETN(presetn),

      .I_AOU_APB_SI0_PSEL   (apb_if.psel),
      .I_AOU_APB_SI0_PENABLE(apb_if.penable),
      .I_AOU_APB_SI0_PADDR  (apb_if.paddr),
      .I_AOU_APB_SI0_PWRITE (apb_if.pwrite),
      .I_AOU_APB_SI0_PWDATA (apb_if.pwdata),
      .O_AOU_APB_SI0_PRDATA (apb_if.prdata),
      .O_AOU_APB_SI0_PREADY (apb_if.pready),
      .O_AOU_APB_SI0_PSLVERR(apb_if.pslverr),

      .O_AOU_RX_AXI_M_ARID   (m_arid),
      .O_AOU_RX_AXI_M_ARADDR (m_araddr),
      .O_AOU_RX_AXI_M_ARLEN  (m_arlen),
      .O_AOU_RX_AXI_M_ARSIZE (m_arsize),
      .O_AOU_RX_AXI_M_ARBURST(m_arburst),
      .O_AOU_RX_AXI_M_ARLOCK (m_arlock),
      .O_AOU_RX_AXI_M_ARCACHE(m_arcache),
      .O_AOU_RX_AXI_M_ARPROT (m_arprot),
      .O_AOU_RX_AXI_M_ARQOS  (m_arqos),
      .O_AOU_RX_AXI_M_ARVALID(m_arvalid),
      .I_AOU_RX_AXI_M_ARREADY('0),
      .I_AOU_TX_AXI_M_RID    ('0),
      .I_AOU_TX_AXI_M_RDATA  ('0),
      .I_AOU_TX_AXI_M_RRESP  ('0),
      .I_AOU_TX_AXI_M_RLAST  ('0),
      .I_AOU_TX_AXI_M_RVALID ('0),
      .O_AOU_TX_AXI_M_RREADY (m_rready),
      .O_AOU_RX_AXI_M_AWID   (m_awid),
      .O_AOU_RX_AXI_M_AWADDR (m_awaddr),
      .O_AOU_RX_AXI_M_AWLEN  (m_awlen),
      .O_AOU_RX_AXI_M_AWSIZE (m_awsize),
      .O_AOU_RX_AXI_M_AWBURST(m_awburst),
      .O_AOU_RX_AXI_M_AWLOCK (m_awlock),
      .O_AOU_RX_AXI_M_AWCACHE(m_awcache),
      .O_AOU_RX_AXI_M_AWPROT (m_awprot),
      .O_AOU_RX_AXI_M_AWQOS  (m_awqos),
      .O_AOU_RX_AXI_M_AWVALID(m_awvalid),
      .I_AOU_RX_AXI_M_AWREADY('0),
      .O_AOU_RX_AXI_M_WDATA  (m_wdata),
      .O_AOU_RX_AXI_M_WSTRB  (m_wstrb),
      .O_AOU_RX_AXI_M_WLAST  (m_wlast),
      .O_AOU_RX_AXI_M_WVALID (m_wvalid),
      .I_AOU_RX_AXI_M_WREADY ('0),
      .I_AOU_TX_AXI_M_BID    ('0),
      .I_AOU_TX_AXI_M_BRESP  ('0),
      .I_AOU_TX_AXI_M_BVALID ('0),
      .O_AOU_TX_AXI_M_BREADY (m_bready),

      .I_AOU_TX_AXI_S_ARID   ('0),
      .I_AOU_TX_AXI_S_ARADDR ('0),
      .I_AOU_TX_AXI_S_ARLEN  ('0),
      .I_AOU_TX_AXI_S_ARSIZE ('0),
      .I_AOU_TX_AXI_S_ARBURST('0),
      .I_AOU_TX_AXI_S_ARLOCK ('0),
      .I_AOU_TX_AXI_S_ARCACHE('0),
      .I_AOU_TX_AXI_S_ARPROT ('0),
      .I_AOU_TX_AXI_S_ARQOS  ('0),
      .I_AOU_TX_AXI_S_ARVALID('0),
      .O_AOU_TX_AXI_S_ARREADY(s_arready),
      .O_AOU_RX_AXI_S_RID    (s_rid),
      .O_AOU_RX_AXI_S_RDATA  (s_rdata),
      .O_AOU_RX_AXI_S_RRESP  (s_rresp),
      .O_AOU_RX_AXI_S_RLAST  (s_rlast),
      .O_AOU_RX_AXI_S_RVALID (s_rvalid),
      .I_AOU_RX_AXI_S_RREADY ('0),
      .I_AOU_TX_AXI_S_AWID   ('0),
      .I_AOU_TX_AXI_S_AWADDR ('0),
      .I_AOU_TX_AXI_S_AWLEN  ('0),
      .I_AOU_TX_AXI_S_AWSIZE ('0),
      .I_AOU_TX_AXI_S_AWBURST('0),
      .I_AOU_TX_AXI_S_AWLOCK ('0),
      .I_AOU_TX_AXI_S_AWCACHE('0),
      .I_AOU_TX_AXI_S_AWPROT ('0),
      .I_AOU_TX_AXI_S_AWQOS  ('0),
      .I_AOU_TX_AXI_S_AWVALID('0),
      .O_AOU_TX_AXI_S_AWREADY(s_awready),
      .I_AOU_TX_AXI_S_WDATA  ('0),
      .I_AOU_TX_AXI_S_WSTRB  ('0),
      .I_AOU_TX_AXI_S_WLAST  ('0),
      .I_AOU_TX_AXI_S_WVALID ('0),
      .O_AOU_TX_AXI_S_WREADY (s_wready),
      .O_AOU_RX_AXI_S_BID    (s_bid),
      .O_AOU_RX_AXI_S_BRESP  (s_bresp),
      .O_AOU_RX_AXI_S_BVALID (s_bvalid),
      .I_AOU_RX_AXI_S_BREADY ('0),

      .I_FDI_PL_0_VALID      (1'b0),
      .I_FDI_PL_0_DATA       ('0),
      .I_FDI_PL_0_FLIT_CANCEL(1'b0),
      .I_FDI_PL_0_TRDY       (1'b0),
      .I_FDI_PL_0_STALLREQ   (1'b0),
      .I_FDI_PL_0_STATE_STS  (4'h0),
      .O_FDI_LP_0_DATA       (lp_data),
      .O_FDI_LP_0_VALID      (lp_valid),
      .O_FDI_LP_0_IRDY       (lp_irdy),
      .O_FDI_LP_0_STALLACK   (lp_stallack),

      .INT_REQ_LINKRESET   (irq[0]),
      .INT_SI0_ID_MISMATCH (irq[1]),
      .INT_MI0_ID_MISMATCH (irq[2]),
      .INT_EARLY_RESP_ERR  (irq[3]),
      .INT_EARLY_WDT_ERR   (irq[6]),
      .INT_ACTIVATE_START  (irq[4]),
      .INT_DEACTIVATE_START(irq[5]),

      .I_INT_FSM_IN_ACTIVE      (1'b0),
      .O_AOU_ACTIVATE_ST_DISABLED(st_disabled),
      .O_AOU_ACTIVATE_ST_ENABLED (st_enabled),
      .O_AOU_REQ_LINKRESET       (req_linkreset),

      .TIEL_DFT_MODESCAN(1'b0)
  );

  initial begin
    uvm_config_db#(virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)))::set(null, "*", "apb", apb_if);
    run_test();
  end
endmodule
