// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
// Derived from PR #80 tb/aou_tb_top.sv (VNCHIPLabs, Apache-2.0): clocks, reset
// release and the DUT's bring-up tie-offs.
//
// T1 top (tb_top, no ports): AOU_TOP as u_dut against layered models. Build
// configuration comes from defines (aou_sim_cfg.toml targets; Makefile CONFIG): AOU_RP_COUNT, AOU_RP<n>_DATA_W (per RP; default
// AOU_RP_DATA_W), AOU_FDI_CONFIG, AOU_TX_NXT_PACKING (TX_NXT_PACKING_EN, default 0), TWO_PHY for the
// two-PHY FDI configurations, and
// AOU_RX_FIFO_ALT for non-default RX FIFO depths with the register slices off
// (aou_t1_env_pkg::AOU_T1_RX_DEPTH). Every interface is registered in
// uvm_config_db under scope "*" (docs/ARCHITECTURE.md) by the SV-UVM harness
// block at the end (`ifdef UVM), which also compiles the test classes
// (uvm/tests/aou_tests.sv) and calls run_test().

`timescale 1ns/1ps

`ifndef AOU_RP_COUNT
`define AOU_RP_COUNT 1
`endif
`ifndef AOU_RP_DATA_W
`define AOU_RP_DATA_W 512
`endif
`ifndef AOU_RP0_DATA_W
`define AOU_RP0_DATA_W `AOU_RP_DATA_W
`endif
`ifndef AOU_RP1_DATA_W
`define AOU_RP1_DATA_W `AOU_RP_DATA_W
`endif
`ifndef AOU_RP2_DATA_W
`define AOU_RP2_DATA_W `AOU_RP_DATA_W
`endif
`ifndef AOU_RP3_DATA_W
`define AOU_RP3_DATA_W `AOU_RP_DATA_W
`endif
`ifndef AOU_FDI_CONFIG
`define AOU_FDI_CONFIG 1
`endif
`ifndef AOU_TX_NXT_PACKING
`define AOU_TX_NXT_PACKING 0
`endif

module tb_top;
  import uvm_pkg::*;

  localparam int RP_COUNT   = `AOU_RP_COUNT;
  localparam int RPW0       = `AOU_RP0_DATA_W;
  localparam int RPW1       = `AOU_RP1_DATA_W;
  localparam int RPW2       = `AOU_RP2_DATA_W;
  localparam int RPW3       = `AOU_RP3_DATA_W;
  // The DUT sizes every RP's data ports to the widest of all four parameters
  // (RP_AXI_DATA_WD_MAX); a narrower RP uses the low bits of its slot.
  localparam int RPW01      = (RPW0 > RPW1) ? RPW0 : RPW1;
  localparam int RPW23      = (RPW2 > RPW3) ? RPW2 : RPW3;
  localparam int RP_DATA_W  = (RPW01 > RPW23) ? RPW01 : RPW23;
  function automatic int rp_w(int r);
    return (r == 0) ? RPW0 : (r == 1) ? RPW1 : (r == 2) ? RPW2 : RPW3;
  endfunction
  localparam int FDI_CFG    = `AOU_FDI_CONFIG;
  localparam int NXT_PACK   = `AOU_TX_NXT_PACKING;
  localparam int BUS_W      = 1024;
  localparam int AXI_W      = 1024;
  localparam int WD0 = (FDI_CFG == 0 || FDI_CFG == 3) ? 256 : (FDI_CFG == 2) ? 1024 : 512;
`ifdef TWO_PHY
  localparam int WD1 = (FDI_CFG == 4) ? 1024 : 512;
  localparam bit TWO_PHY_BUILD = 1'b1;
`else
  localparam bit TWO_PHY_BUILD = 1'b0;
`endif

  // The RTL does not cross-check FDI_CONFIG against TWO_PHY.
  initial begin
    if (TWO_PHY_BUILD != (FDI_CFG >= 3))
      $fatal(1, "FDI_CONFIG=%0d does not match TWO_PHY=%0b", FDI_CFG, TWO_PHY_BUILD);
  end

  // ---------------------------------------------------------------------------
  // Clocks and resets: 1 GHz core/FDI clock; the APB clock is 100 MHz unless
  // +pclk_ps=<period in ps> sets another PCLK:CLK ratio (the bridge is
  // asynchronous, so any ratio is legal).
  // ---------------------------------------------------------------------------
  logic clk;
  logic pclk;
  logic rst_n;
  logic prst_n;
  logic por_n;
  int unsigned pclk_ps = 10000;

  initial clk = 1'b0;
  always #0.5 clk = ~clk;
  initial begin
    pclk = 1'b0;
    void'($value$plusargs("pclk_ps=%d", pclk_ps));
    if (pclk_ps < 2) $fatal(1, "+pclk_ps=%0d: the PCLK period must be at least 2 ps", pclk_ps);
    if (pclk_ps != 10000) $info("PCLK period %0d ps (CLK 1000 ps)", pclk_ps);
    forever #(pclk_ps / 2000.0) pclk = ~pclk;
  end

  // +rtl_asserts=1 marks a run of the ASSERTION_ON regression (plan 11.18): it is
  // valid only on a build that compiled the RTL's assertions (make RTL_ASSERT=1).
  int unsigned rtl_asserts = 0;
  initial begin
    void'($value$plusargs("rtl_asserts=%d", rtl_asserts));
`ifdef ASSERTION_ON
    if (rtl_asserts != 0) `uvm_info("tb_top", "RTL ASSERTION_ON checks compiled in", UVM_LOW)
`else
    if (rtl_asserts != 0)
      `uvm_fatal("tb_top", "+rtl_asserts=1 needs the RTL assertions (make RTL_ASSERT=1)")
`endif
  end
`ifdef ASSERTION_ON
  // BUGS/054: AOU_AXI_WLAST_GEN's ready_valid_assertion wants AWREADY within 500
  // cycles of AWVALID, a bound AXI does not have, so it is the one RTL assertion
  // turned off; every other one stays on.
  for (genvar r = 0; r < RP_COUNT; r++) begin : g_waive_wlast_gen
    int unsigned on;
    initial begin
      if ($value$plusargs("rtl_asserts=%d", on) && on != 0)
        $assertoff(0, u_dut.u_aou_core_top.u_aou_core.gen_aou_core_rp[r].u_aou_core_rp
                          .u_wlast_gen.ready_valid_assertion);
    end
  end
`endif

  // Power-on reset, at least 25 cycles of each clock; the reset agent adds
  // mid-test resets through rst.
  initial begin
    por_n = 1'b0;
    fork
      repeat (25) @(posedge pclk);
      repeat (25) @(posedge clk);
    join
    por_n = 1'b1;
  end

  aou_rst_if rst (.clk(clk), .pclk(pclk));
  assign rst_n = por_n & rst.resetn;
  assign prst_n = por_n & rst.presetn;
  assign rst.rst_n = rst_n;
  assign rst.prst_n = prst_n;
  assign rst.core_rst_n = u_dut.u_aou_core_top.w_DFTED_sw_resetn;
  assign rst.apb_psel = apb.psel;
  assign rst.apb_bridge_idle =
      u_dut.u_aou_core_top.u_async_apb_bridge.u_async_apb_bridge_si.r_si_crt_st == 2'b00 &&
      !u_dut.u_aou_core_top.u_async_apb_bridge.u_async_apb_bridge_si.r_si_req_clks &&
      !u_dut.u_aou_core_top.u_async_apb_bridge.u_async_apb_bridge_si.w_mi_done_clks &&
      u_dut.u_aou_core_top.u_async_apb_bridge.u_async_apb_bridge_mi.r_mi_crt_st == 2'b00 &&
      !u_dut.u_aou_core_top.u_async_apb_bridge.u_async_apb_bridge_mi.r_mi_done_clkm &&
      !u_dut.u_aou_core_top.u_async_apb_bridge.u_async_apb_bridge_mi.w_si_req_clkm;
  assign rst.rx_w_pend = 8'(u_dut.u_aou_core_top.w_aou_rx_wlast_gen_wvalid);
  assign rst.rx_pend = 8'(u_dut.u_aou_core_top.w_aou_rx_wlast_gen_awvalid) |
                       8'(u_dut.u_aou_core_top.w_aou_rx_wlast_gen_wvalid) |
                       8'(u_dut.u_aou_core_top.w_aou_rx_axi_mm_arvalid) |
                       8'(u_dut.u_aou_core_top.w_aou_rx_axi_s_rvalid) |
                       8'(u_dut.u_aou_core_top.w_early_bresp_ctrl_bvalid);
  assign rst.rx_msgcrdt_valid = u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_valid;
  assign rst.rx_msgcrdt = {u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_rp,
                           u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_wrespcred,
                           u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_rdatacred,
                           u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_wdatacred,
                           u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_rreqcred,
                           u_dut.u_aou_core_top.u_aou_core.w_rxcore_msgcrdt_wreqcred};
  // The reset of the DUT's AXI port logic (AOU_CORE and the RX FIFOs, every S and
  // M port pin): the core reset, I_RESETN and AOU_SW_RESET. Either reset loses the AXI transactions in flight
  // or queued in the core (MAS 7.3.6, integration guide 3.1.1), and the SoC must
  // reset the AXI managers and subordinates on the AoU ports with it or let them
  // recover. The bench models the reset: the local AXI agents and Arm's Axi4PC on
  // the DUT's ports share this reset, so a software reset is a bus reset to them.
  wire axi_port_rst_n = rst.core_rst_n;
  aou_axi4pc_ctl_if axi4pc_ctl (.clk(clk));
  initial axi4pc_ctl.chk_scope = $sformatf("%m.g_axi4pc");

  // ---------------------------------------------------------------------------
  // Interfaces
  // ---------------------------------------------------------------------------
  aou_axi_bus_if #(.DATA_W(AXI_W)) s_axi [RP_COUNT] (.clk(clk), .resetn(axi_port_rst_n));
  aou_axi_bus_if #(.DATA_W(AXI_W)) m_axi [RP_COUNT] (.clk(clk), .resetn(axi_port_rst_n));
  aou_fdi_mb_if  #(.DATA_W(BUS_W)) fdi_mb0 (.clk(clk), .rst_n(rst_n));
`ifdef TWO_PHY
  aou_fdi_mb_if  #(.DATA_W(BUS_W)) fdi_mb1 (.clk(clk), .rst_n(rst_n));
`endif
  aou_fdi_lsm_if                   fdi_lsm (.clk(clk), .rst_n(rst_n));
  aou_apb_if #(.ADDR_W(32), .DATA_W(32)) apb (.pclk(pclk), .presetn(prst_n));
  aou_status_if                    status ();
  aou_irq_if                       irq (.clk(clk));
  aou_fdi_checker_if               fdi_chk (.clk(clk));

  // ---------------------------------------------------------------------------
  // AXI: per-RP interfaces to the DUT's packed [RP_COUNT-1:0] ports. Each RP is
  // connected at its own width, as a narrower bus plugged into the DUT's wider
  // slot: the DUT inputs above it are tied to 0, its outputs there are unread.
  // ---------------------------------------------------------------------------
  localparam int SW = RP_DATA_W / 8;

  logic [RP_COUNT-1:0][9:0]           s_awid, s_arid, s_bid, s_rid;
  logic [RP_COUNT-1:0][63:0]          s_awaddr, s_araddr;
  logic [RP_COUNT-1:0][7:0]           s_awlen, s_arlen;
  logic [RP_COUNT-1:0][2:0]           s_awsize, s_arsize, s_awprot, s_arprot;
  logic [RP_COUNT-1:0][1:0]           s_awburst, s_arburst, s_bresp, s_rresp;
  logic [RP_COUNT-1:0][3:0]           s_awcache, s_arcache, s_awqos, s_arqos;
  logic [RP_COUNT-1:0]                s_awlock, s_arlock, s_awvalid, s_awready, s_arvalid,
                                      s_arready, s_wlast, s_wvalid, s_wready, s_bvalid,
                                      s_bready, s_rlast, s_rvalid, s_rready;
  logic [RP_COUNT-1:0][RP_DATA_W-1:0] s_wdata, s_rdata;
  logic [RP_COUNT-1:0][SW-1:0]        s_wstrb;

  logic [RP_COUNT-1:0][9:0]           m_awid, m_arid, m_bid, m_rid;
  logic [RP_COUNT-1:0][63:0]          m_awaddr, m_araddr;
  logic [RP_COUNT-1:0][7:0]           m_awlen, m_arlen;
  logic [RP_COUNT-1:0][2:0]           m_awsize, m_arsize, m_awprot, m_arprot;
  logic [RP_COUNT-1:0][1:0]           m_awburst, m_arburst, m_bresp, m_rresp;
  logic [RP_COUNT-1:0][3:0]           m_awcache, m_arcache, m_awqos, m_arqos;
  logic [RP_COUNT-1:0]                m_awlock, m_arlock, m_awvalid, m_awready, m_arvalid,
                                      m_arready, m_wlast, m_wvalid, m_wready, m_bvalid,
                                      m_bready, m_rlast, m_rvalid, m_rready;
  logic [RP_COUNT-1:0][RP_DATA_W-1:0] m_wdata, m_rdata;
  logic [RP_COUNT-1:0][SW-1:0]        m_wstrb;

  for (genvar r = 0; r < RP_COUNT; r++) begin : g_rp
    localparam int W = rp_w(r);
    // S port: the manager agent drives AW/W/AR and BREADY/RREADY.
    assign s_awid[r]    = s_axi[r].awid;
    assign s_awaddr[r]  = s_axi[r].awaddr;
    assign s_awlen[r]   = s_axi[r].awlen;
    assign s_awsize[r]  = s_axi[r].awsize;
    assign s_awburst[r] = s_axi[r].awburst;
    assign s_awlock[r]  = s_axi[r].awlock;
    assign s_awcache[r] = s_axi[r].awcache;
    assign s_awprot[r]  = s_axi[r].awprot;
    assign s_awqos[r]   = s_axi[r].awqos;
    assign s_awvalid[r] = s_axi[r].awvalid;
    assign s_axi[r].awready = s_awready[r];
    assign s_wdata[r]   = RP_DATA_W'(s_axi[r].wdata[W-1:0]);
    assign s_wstrb[r]   = SW'(s_axi[r].wstrb[W/8-1:0]);
    assign s_wlast[r]   = s_axi[r].wlast;
    assign s_wvalid[r]  = s_axi[r].wvalid;
    assign s_axi[r].wready = s_wready[r];
    assign s_axi[r].bid    = s_bid[r];
    assign s_axi[r].bresp  = s_bresp[r];
    assign s_axi[r].bvalid = s_bvalid[r];
    assign s_bready[r]  = s_axi[r].bready;
    assign s_arid[r]    = s_axi[r].arid;
    assign s_araddr[r]  = s_axi[r].araddr;
    assign s_arlen[r]   = s_axi[r].arlen;
    assign s_arsize[r]  = s_axi[r].arsize;
    assign s_arburst[r] = s_axi[r].arburst;
    assign s_arlock[r]  = s_axi[r].arlock;
    assign s_arcache[r] = s_axi[r].arcache;
    assign s_arprot[r]  = s_axi[r].arprot;
    assign s_arqos[r]   = s_axi[r].arqos;
    assign s_arvalid[r] = s_axi[r].arvalid;
    assign s_axi[r].arready = s_arready[r];
    assign s_axi[r].rid    = s_rid[r];
    assign s_axi[r].rdata  = AXI_W'(s_rdata[r][W-1:0]);
    assign s_axi[r].rresp  = s_rresp[r];
    assign s_axi[r].rlast  = s_rlast[r];
    assign s_axi[r].rvalid = s_rvalid[r];
    assign s_rready[r]  = s_axi[r].rready;

    // M port: the subordinate agent drives AWREADY/WREADY/ARREADY and B/R.
    assign m_axi[r].awid    = m_awid[r];
    assign m_axi[r].awaddr  = m_awaddr[r];
    assign m_axi[r].awlen   = m_awlen[r];
    assign m_axi[r].awsize  = m_awsize[r];
    assign m_axi[r].awburst = m_awburst[r];
    assign m_axi[r].awlock  = m_awlock[r];
    assign m_axi[r].awcache = m_awcache[r];
    assign m_axi[r].awprot  = m_awprot[r];
    assign m_axi[r].awqos   = m_awqos[r];
    assign m_axi[r].awvalid = m_awvalid[r];
    assign m_awready[r] = m_axi[r].awready;
    assign m_axi[r].wdata   = AXI_W'(m_wdata[r][W-1:0]);
    assign m_axi[r].wstrb   = (AXI_W / 8)'(m_wstrb[r][W/8-1:0]);
    assign m_axi[r].wlast   = m_wlast[r];
    assign m_axi[r].wvalid  = m_wvalid[r];
    assign m_wready[r]  = m_axi[r].wready;
    assign m_bid[r]     = m_axi[r].bid;
    assign m_bresp[r]   = m_axi[r].bresp;
    assign m_bvalid[r]  = m_axi[r].bvalid;
    assign m_axi[r].bready  = m_bready[r];
    assign m_axi[r].arid    = m_arid[r];
    assign m_axi[r].araddr  = m_araddr[r];
    assign m_axi[r].arlen   = m_arlen[r];
    assign m_axi[r].arsize  = m_arsize[r];
    assign m_axi[r].arburst = m_arburst[r];
    assign m_axi[r].arlock  = m_arlock[r];
    assign m_axi[r].arcache = m_arcache[r];
    assign m_axi[r].arprot  = m_arprot[r];
    assign m_axi[r].arqos   = m_arqos[r];
    assign m_axi[r].arvalid = m_arvalid[r];
    assign m_arready[r] = m_axi[r].arready;
    assign m_rid[r]     = m_axi[r].rid;
    assign m_rdata[r]   = RP_DATA_W'(m_axi[r].rdata[W-1:0]);
    assign m_rresp[r]   = m_axi[r].rresp;
    assign m_rlast[r]   = m_axi[r].rlast;
    assign m_rvalid[r]  = m_axi[r].rvalid;
    assign m_axi[r].rready  = m_rready[r];

`ifndef AOU_T1_AXI_AGENTS
    // No AXI agents yet: the S port stays idle, the M port accepts requests
    // and never responds.
    assign s_axi[r].awid = '0;    assign s_axi[r].awaddr = '0;  assign s_axi[r].awlen = '0;
    assign s_axi[r].awsize = '0;  assign s_axi[r].awburst = '0; assign s_axi[r].awlock = '0;
    assign s_axi[r].awcache = '0; assign s_axi[r].awprot = '0;  assign s_axi[r].awqos = '0;
    assign s_axi[r].awvalid = 1'b0;
    assign s_axi[r].wdata = '0;   assign s_axi[r].wstrb = '0;   assign s_axi[r].wlast = 1'b0;
    assign s_axi[r].wvalid = 1'b0;
    assign s_axi[r].bready = 1'b1;
    assign s_axi[r].arid = '0;    assign s_axi[r].araddr = '0;  assign s_axi[r].arlen = '0;
    assign s_axi[r].arsize = '0;  assign s_axi[r].arburst = '0; assign s_axi[r].arlock = '0;
    assign s_axi[r].arcache = '0; assign s_axi[r].arprot = '0;  assign s_axi[r].arqos = '0;
    assign s_axi[r].arvalid = 1'b0;
    assign s_axi[r].rready = 1'b1;
    assign m_axi[r].awready = 1'b1;
    assign m_axi[r].wready = 1'b1;
    assign m_axi[r].bid = '0;     assign m_axi[r].bresp = '0;   assign m_axi[r].bvalid = 1'b0;
    assign m_axi[r].arready = 1'b1;
    assign m_axi[r].rid = '0;     assign m_axi[r].rdata = '0;   assign m_axi[r].rresp = '0;
    assign m_axi[r].rlast = 1'b0; assign m_axi[r].rvalid = 1'b0;
`endif
  end

  // ---------------------------------------------------------------------------
  // FDI: the mainband interfaces are BUS_W wide; the DUT uses the low WD bits.
  // ---------------------------------------------------------------------------
  logic [WD0-1:0] lp0_data;
  assign fdi_mb0.lp_data = BUS_W'(lp0_data);
  assign fdi_mb0.rx_active = fdi_lsm.pl_rx_active_req && fdi_lsm.lp_rx_active_sts;
`ifdef TWO_PHY
  logic [WD1-1:0] lp1_data;
  assign fdi_mb1.lp_data = BUS_W'(lp1_data);
  assign fdi_mb1.rx_active = fdi_lsm.pl_rx_active_req && fdi_lsm.lp_rx_active_sts;
`endif

  // Core-to-bringup triggers for the bringup reference model and the status
  // interface. AOU_TOP keeps the activation state and LinkReset request
  // internal, so they are read from its wires.
  assign fdi_lsm.int_req_linkreset = u_dut.w_aou_req_linkreset;
  assign fdi_lsm.act_st_disabled   = status.activate_st_disabled;
  assign fdi_lsm.sw_reset          = u_dut.w_sw_reset;
  assign fdi_lsm.int_activate_start = status.int_activate_start;
  assign fdi_lsm.int_fdi_link_down  = status.int_fdi_link_down;
  assign status.activate_st_disabled = u_dut.w_aou_activate_st_disabled;
  assign status.activate_st_enabled  = u_dut.w_aou_activate_st_enabled;
  assign status.o_aou_req_linkreset  = u_dut.w_aou_req_linkreset;

  assign irq.rst_n                = rst_n;
  assign irq.int_req_linkreset    = status.req_linkreset;
  assign irq.int_si0_id_mismatch  = status.int_si0_id_mismatch;
  assign irq.int_mi0_id_mismatch  = status.int_mi0_id_mismatch;
  assign irq.int_early_resp_err   = status.int_early_resp_err;
  assign irq.int_early_wdt_err    = status.int_early_wdt_err;
  assign irq.int_activate_start   = status.int_activate_start;
  assign irq.int_deactivate_start = status.int_deactivate_start;
  assign irq.int_fdi_link_down    = status.int_fdi_link_down;
  assign irq.act_st_disabled      = status.activate_st_disabled;
  assign irq.act_st_enabled       = status.activate_st_enabled;
  assign irq.slv_rid_agg          = u_dut.u_aou_core_top.u_aou_core.O_AXI_SLV_RID_MISMATCH_ERROR;
  assign irq.slv_bid_agg          = u_dut.u_aou_core_top.u_aou_core.O_AXI_SLV_BID_MISMATCH_ERROR;

  // Write-transaction watchdog taps (aou_wdt_if): each RP's early-response
  // controller ports, the SFR's watchdog outputs and status registers, and the
  // SFR's core-clock APB port.
`define AOU_WDT_SFR u_dut.u_aou_core_top.u_aou_core.u_aou_core_sfr
`define AOU_WDT_CTRL(R) \
    u_dut.u_aou_core_top.u_aou_core.gen_aou_core_rp[R].u_aou_core_rp.u_aou_early_bresp_s_ctrl
  aou_wdt_if wdt (.clk(clk));
  assign wdt.core_rst_n = rst.core_rst_n;
  assign wdt.rst_n      = rst_n;
  for (genvar r = 0; r < 4; r++) begin : g_wdt
    if (r < RP_COUNT) begin : g_rp
      assign wdt.aw_hs[r] = `AOU_WDT_CTRL(r).I_AXI_S_AWVALID & `AOU_WDT_CTRL(r).O_AXI_S_AWREADY;
      assign wdt.b_hs[r]  = `AOU_WDT_CTRL(r).I_AXI_M_BVALID & `AOU_WDT_CTRL(r).O_AXI_M_BREADY;
    end else begin : g_none
      assign wdt.aw_hs[r] = 1'b0;
      assign wdt.b_hs[r]  = 1'b0;
    end
  end
  assign wdt.en = {`AOU_WDT_SFR.O_WRITE_EARLY_RESPONSE_RP3_WDT_EN,
                   `AOU_WDT_SFR.O_WRITE_EARLY_RESPONSE_RP2_WDT_EN,
                   `AOU_WDT_SFR.O_WRITE_EARLY_RESPONSE_RP1_WDT_EN,
                   `AOU_WDT_SFR.O_WRITE_EARLY_RESPONSE_RP0_WDT_EN};
  assign wdt.thr  = `AOU_WDT_SFR.O_WRITE_EARLY_RESPONSE_WDT_THRESHOLD;
  assign wdt.mask = `AOU_WDT_SFR.O_AOU_INTERRUPT_MASK_INT_EARLY_WDT_MASK;
  assign wdt.status = {`AOU_WDT_SFR.r_write_early_response_rp3_wdt_trans_timeout_err,
                       `AOU_WDT_SFR.r_write_early_response_rp2_wdt_trans_timeout_err,
                       `AOU_WDT_SFR.r_write_early_response_rp1_wdt_trans_timeout_err,
                       `AOU_WDT_SFR.r_write_early_response_rp0_wdt_trans_timeout_err};
  assign wdt.pin     = status.int_early_wdt_err;
  assign wdt.psel    = `AOU_WDT_SFR.I_PSEL;
  assign wdt.penable = `AOU_WDT_SFR.I_PENABLE;
  assign wdt.pwrite  = `AOU_WDT_SFR.I_PWRITE;
  assign wdt.paddr   = `AOU_WDT_SFR.I_PADDR[15:0];
  assign wdt.pwdata  = `AOU_WDT_SFR.I_PWDATA;
  assign wdt.prdata  = `AOU_WDT_SFR.O_PRDATA;
  assign wdt.pready  = `AOU_WDT_SFR.O_PREADY;
`undef AOU_WDT_SFR
`undef AOU_WDT_CTRL

  AOU_TOP #(
      .RP_COUNT       (RP_COUNT),
      .FDI_CONFIG     (FDI_CFG),
      .RP0_AXI_DATA_WD(RPW0),
      .RP1_AXI_DATA_WD(RPW1),
      .RP2_AXI_DATA_WD(RPW2),
      .RP3_AXI_DATA_WD(RPW3),
      .TX_NXT_PACKING_EN(NXT_PACK),
      .S_RD_MO_CNT    (aou_t1_env_pkg::AOU_T1_S_MO_CNT),
      .S_WR_MO_CNT    (aou_t1_env_pkg::AOU_T1_S_MO_CNT),
      .M_RD_MO_CNT    (aou_t1_env_pkg::AOU_T1_M_MO_CNT),
      .M_WR_MO_CNT    (aou_t1_env_pkg::AOU_T1_M_MO_CNT)
`ifdef AOU_RX_FIFO_ALT
      ,
      .RP0_RX_AW_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[0][0]),
      .RP0_RX_AR_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[0][1]),
      .RP0_RX_W_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[0][2]),
      .RP0_RX_R_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[0][3]),
      .RP0_RX_B_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[0][4]),
      .RP1_RX_AW_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[1][0]),
      .RP1_RX_AR_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[1][1]),
      .RP1_RX_W_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[1][2]),
      .RP1_RX_R_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[1][3]),
      .RP1_RX_B_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[1][4]),
      .RP2_RX_AW_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[2][0]),
      .RP2_RX_AR_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[2][1]),
      .RP2_RX_W_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[2][2]),
      .RP2_RX_R_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[2][3]),
      .RP2_RX_B_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[2][4]),
      .RP3_RX_AW_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[3][0]),
      .RP3_RX_AR_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[3][1]),
      .RP3_RX_W_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[3][2]),
      .RP3_RX_R_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[3][3]),
      .RP3_RX_B_FIFO_DEPTH(aou_t1_env_pkg::AOU_T1_RX_DEPTH[3][4]),
      .RX_AW_FIFO_RS_EN(aou_t1_env_pkg::AOU_T1_RX_RS_EN),
      .RX_AR_FIFO_RS_EN(aou_t1_env_pkg::AOU_T1_RX_RS_EN),
      .RX_W_FIFO_RS_EN(aou_t1_env_pkg::AOU_T1_RX_RS_EN),
      .RX_R_FIFO_RS_EN(aou_t1_env_pkg::AOU_T1_RX_RS_EN),
      .RX_B_FIFO_RS_EN(aou_t1_env_pkg::AOU_T1_RX_RS_EN)
`endif
  ) u_dut (
      .I_CLK    (clk),
      .I_RESETN (rst_n),
      .I_PCLK   (pclk),
      .I_PRESETN(prst_n),

      .I_AOU_APB_SI0_PSEL   (apb.psel),
      .I_AOU_APB_SI0_PENABLE(apb.penable),
      .I_AOU_APB_SI0_PADDR  (apb.paddr),
      .I_AOU_APB_SI0_PWRITE (apb.pwrite),
      .I_AOU_APB_SI0_PWDATA (apb.pwdata),
      .O_AOU_APB_SI0_PRDATA (apb.prdata),
      .O_AOU_APB_SI0_PREADY (apb.pready),
      .O_AOU_APB_SI0_PSLVERR(apb.pslverr),

      .O_AOU_RX_AXI_M_ARID   (m_arid),    .O_AOU_RX_AXI_M_ARADDR (m_araddr),
      .O_AOU_RX_AXI_M_ARLEN  (m_arlen),   .O_AOU_RX_AXI_M_ARSIZE (m_arsize),
      .O_AOU_RX_AXI_M_ARBURST(m_arburst), .O_AOU_RX_AXI_M_ARLOCK (m_arlock),
      .O_AOU_RX_AXI_M_ARCACHE(m_arcache), .O_AOU_RX_AXI_M_ARPROT (m_arprot),
      .O_AOU_RX_AXI_M_ARQOS  (m_arqos),   .O_AOU_RX_AXI_M_ARVALID(m_arvalid),
      .I_AOU_RX_AXI_M_ARREADY(m_arready),
      .I_AOU_TX_AXI_M_RID    (m_rid),     .I_AOU_TX_AXI_M_RDATA  (m_rdata),
      .I_AOU_TX_AXI_M_RRESP  (m_rresp),   .I_AOU_TX_AXI_M_RLAST  (m_rlast),
      .I_AOU_TX_AXI_M_RVALID (m_rvalid),  .O_AOU_TX_AXI_M_RREADY (m_rready),
      .O_AOU_RX_AXI_M_AWID   (m_awid),    .O_AOU_RX_AXI_M_AWADDR (m_awaddr),
      .O_AOU_RX_AXI_M_AWLEN  (m_awlen),   .O_AOU_RX_AXI_M_AWSIZE (m_awsize),
      .O_AOU_RX_AXI_M_AWBURST(m_awburst), .O_AOU_RX_AXI_M_AWLOCK (m_awlock),
      .O_AOU_RX_AXI_M_AWCACHE(m_awcache), .O_AOU_RX_AXI_M_AWPROT (m_awprot),
      .O_AOU_RX_AXI_M_AWQOS  (m_awqos),   .O_AOU_RX_AXI_M_AWVALID(m_awvalid),
      .I_AOU_RX_AXI_M_AWREADY(m_awready),
      .O_AOU_RX_AXI_M_WDATA  (m_wdata),   .O_AOU_RX_AXI_M_WSTRB  (m_wstrb),
      .O_AOU_RX_AXI_M_WLAST  (m_wlast),   .O_AOU_RX_AXI_M_WVALID (m_wvalid),
      .I_AOU_RX_AXI_M_WREADY (m_wready),
      .I_AOU_TX_AXI_M_BID    (m_bid),     .I_AOU_TX_AXI_M_BRESP  (m_bresp),
      .I_AOU_TX_AXI_M_BVALID (m_bvalid),  .O_AOU_TX_AXI_M_BREADY (m_bready),

      .I_AOU_TX_AXI_S_ARID   (s_arid),    .I_AOU_TX_AXI_S_ARADDR (s_araddr),
      .I_AOU_TX_AXI_S_ARLEN  (s_arlen),   .I_AOU_TX_AXI_S_ARSIZE (s_arsize),
      .I_AOU_TX_AXI_S_ARBURST(s_arburst), .I_AOU_TX_AXI_S_ARLOCK (s_arlock),
      .I_AOU_TX_AXI_S_ARCACHE(s_arcache), .I_AOU_TX_AXI_S_ARPROT (s_arprot),
      .I_AOU_TX_AXI_S_ARQOS  (s_arqos),   .I_AOU_TX_AXI_S_ARVALID(s_arvalid),
      .O_AOU_TX_AXI_S_ARREADY(s_arready),
      .O_AOU_RX_AXI_S_RID    (s_rid),     .O_AOU_RX_AXI_S_RDATA  (s_rdata),
      .O_AOU_RX_AXI_S_RRESP  (s_rresp),   .O_AOU_RX_AXI_S_RLAST  (s_rlast),
      .O_AOU_RX_AXI_S_RVALID (s_rvalid),  .I_AOU_RX_AXI_S_RREADY (s_rready),
      .I_AOU_TX_AXI_S_AWID   (s_awid),    .I_AOU_TX_AXI_S_AWADDR (s_awaddr),
      .I_AOU_TX_AXI_S_AWLEN  (s_awlen),   .I_AOU_TX_AXI_S_AWSIZE (s_awsize),
      .I_AOU_TX_AXI_S_AWBURST(s_awburst), .I_AOU_TX_AXI_S_AWLOCK (s_awlock),
      .I_AOU_TX_AXI_S_AWCACHE(s_awcache), .I_AOU_TX_AXI_S_AWPROT (s_awprot),
      .I_AOU_TX_AXI_S_AWQOS  (s_awqos),   .I_AOU_TX_AXI_S_AWVALID(s_awvalid),
      .O_AOU_TX_AXI_S_AWREADY(s_awready),
      .I_AOU_TX_AXI_S_WDATA  (s_wdata),   .I_AOU_TX_AXI_S_WSTRB  (s_wstrb),
      .I_AOU_TX_AXI_S_WLAST  (s_wlast),   .I_AOU_TX_AXI_S_WVALID (s_wvalid),
      .O_AOU_TX_AXI_S_WREADY (s_wready),
      .O_AOU_RX_AXI_S_BID    (s_bid),     .O_AOU_RX_AXI_S_BRESP  (s_bresp),
      .O_AOU_RX_AXI_S_BVALID (s_bvalid),  .I_AOU_RX_AXI_S_BREADY (s_bready),

`ifdef TWO_PHY
      .I_PHY_TYPE            (fdi_lsm.phy_type),
`endif
      .I_FDI_PL_0_VALID      (fdi_mb0.pl_valid),
      .I_FDI_PL_0_DATA       (fdi_mb0.pl_data[WD0-1:0]),
      .I_FDI_PL_0_FLIT_CANCEL(fdi_mb0.pl_flit_cancel),
      .I_FDI_PL_0_TRDY       (fdi_mb0.pl_trdy),
      .I_FDI_PL_0_STALLREQ   (fdi_mb0.pl_stallreq),
      .I_FDI_PL_0_STATE_STS  (fdi_mb0.pl_state_sts),
      .O_FDI_LP_0_DATA       (lp0_data),
      .O_FDI_LP_0_VALID      (fdi_mb0.lp_valid),
      .O_FDI_LP_0_IRDY       (fdi_mb0.lp_irdy),
      .O_FDI_LP_0_STALLACK   (fdi_mb0.lp_stallack),
`ifdef TWO_PHY
      .I_FDI_PL_1_VALID      (fdi_mb1.pl_valid),
      .I_FDI_PL_1_DATA       (fdi_mb1.pl_data[WD1-1:0]),
      .I_FDI_PL_1_FLIT_CANCEL(fdi_mb1.pl_flit_cancel),
      .I_FDI_PL_1_TRDY       (fdi_mb1.pl_trdy),
      .I_FDI_PL_1_STALLREQ   (fdi_mb1.pl_stallreq),
      .I_FDI_PL_1_STATE_STS  (fdi_mb1.pl_state_sts),
      .O_FDI_LP_1_DATA       (lp1_data),
      .O_FDI_LP_1_VALID      (fdi_mb1.lp_valid),
      .O_FDI_LP_1_IRDY       (fdi_mb1.lp_irdy),
      .O_FDI_LP_1_STALLACK   (fdi_mb1.lp_stallack),
`endif

      .I_PL_INBAND_PRES      (fdi_lsm.pl_inband_pres),
      .I_PL_CLK_REQ          (fdi_lsm.pl_clk_req),
      .I_PL_WAKE_ACK         (fdi_lsm.pl_wake_ack),
      .I_PL_RX_ACTIVE_REQ    (fdi_lsm.pl_rx_active_req),
      .O_LP_STATE_REQ        (fdi_lsm.lp_state_req),
      .O_LP_WAKE_REQ         (fdi_lsm.lp_wake_req),
      .O_LP_CLK_ACK          (fdi_lsm.lp_clk_ack),
      .O_LP_RX_ACTIVE_STS    (fdi_lsm.lp_rx_active_sts),
      .O_LP_LINKERROR        (fdi_lsm.lp_linkerror),

      .I_SW_ACTIVATE_START   (fdi_lsm.sw_activate_start),
      .I_SW_LINKERROR_INJECT (fdi_lsm.sw_linkerror_inject),
      .O_FDI_FSM_STATE       (fdi_lsm.fdi_fsm_state),
      .O_FDI_LINK_UP         (fdi_lsm.fdi_link_up),

      .INT_REQ_LINKRESET     (status.req_linkreset),
      .INT_SI0_ID_MISMATCH   (status.int_si0_id_mismatch),
      .INT_MI0_ID_MISMATCH   (status.int_mi0_id_mismatch),
      .INT_EARLY_RESP_ERR    (status.int_early_resp_err),
      .INT_EARLY_WDT_ERR     (status.int_early_wdt_err),
      .INT_ACTIVATE_START    (status.int_activate_start),
      .INT_DEACTIVATE_START  (status.int_deactivate_start),
      .INT_FDI_LINK_DOWN     (status.int_fdi_link_down),

      .TIEL_DFT_MODESCAN        (rst.dft_modescan)
  );

  // ---------------------------------------------------------------------------
  // AOU_FDI_CHECKER (single-PHY builds only) on PHY 0: LP is the DUT's TX, PL the flits driven to it.
  // A new observed-link epoch starts whenever the Adapter reports Reset (both
  // encodings use 0). DEST_RP is the identity map the DUT resets to.
  // ---------------------------------------------------------------------------
`ifndef TWO_PHY
  logic [15:0] xchk_cnt;
  logic        xchk_trigger, xchk_capture_valid, xchk_capture_code, xchk_capture_die;
  logic [1:0]  xchk_capture_chk_st, xchk_capture_obs_st, xchk_compared;
  logic [31:0] xchk_capture_flit_seq;

  assign fdi_chk.rst_n = rst_n;

  AOU_FDI_CHECKER #(
      .FDI_IF_BYTES(WD0 / 8),
      .RP_COUNT    (RP_COUNT),
      .FDID        (0)
  ) u_fdi_chk (
      .I_CLK                  (clk),
      .I_RESETN               (rst_n),
      .I_LINK_RESET           (fdi_mb0.pl_state_sts == 4'h0),
      .I_LP_VALID             (fdi_mb0.lp_valid),
      .I_LP_IRDY              (fdi_mb0.lp_irdy),
      .I_LP_DATA              (lp0_data),
      .I_PL_TRDY              (fdi_mb0.pl_trdy),
      .I_PL_VALID             (fdi_mb0.pl_valid),
      .I_PL_DATA              (fdi_mb0.pl_data[WD0-1:0]),
      .I_PL_FLIT_CANCEL       (fdi_mb0.pl_flit_cancel),
      .I_CFG_RP_DEST_RP       ({2'd3, 2'd2, 2'd1, 2'd0}),
      .I_LP_ACT_ST_DISABLED   (status.activate_st_disabled),
      .I_LP_ACT_ST_ENABLED    (status.activate_st_enabled),
      .I_PL_ACT_ST_DISABLED   (1'b0),
      .I_PL_ACT_ST_ENABLED    (1'b0),
      .O_VIOLATION            (fdi_chk.violation),
      .O_VIOLATION_TRIGGER    (fdi_chk.trigger),
      .O_VIOLATION_CNT        (fdi_chk.viol_cnt),
      .O_CAPTURE_VALID        (fdi_chk.capture_valid),
      .O_CAPTURE_CODE         (fdi_chk.capture_code),
      .O_CAPTURE_DIR          (fdi_chk.capture_dir),
      .O_CAPTURE_FLIT_SEQ     (fdi_chk.capture_flit_seq),
      .O_CAPTURE_GRANULE_IDX  (fdi_chk.capture_granule_idx),
      .O_CAPTURE_GRANULE      (fdi_chk.capture_granule),
      .O_CHECK_ENABLED        (fdi_chk.check_enabled),
      .O_LP_FLIT_SEQ          (fdi_chk.lp_flit_seq),
      .O_PL_FLIT_SEQ          (fdi_chk.pl_flit_seq),
      .O_XCHK_VIOLATION       (fdi_chk.xchk_violation),
      .O_XCHK_TRIGGER         (xchk_trigger),
      .O_XCHK_CNT             (xchk_cnt),
      .O_XCHK_CAPTURE_VALID   (xchk_capture_valid),
      .O_XCHK_CAPTURE_CODE    (xchk_capture_code),
      .O_XCHK_CAPTURE_DIE     (xchk_capture_die),
      .O_XCHK_CAPTURE_CHK_ST  (xchk_capture_chk_st),
      .O_XCHK_CAPTURE_OBS_ST  (xchk_capture_obs_st),
      .O_XCHK_CAPTURE_FLIT_SEQ(xchk_capture_flit_seq),
      .O_XCHK_COMPARED        (xchk_compared),
      .I_ERR_CLEAR            (fdi_chk.err_clear)
  );

  aou_fdi_chk_dir_tap u_fdi_chk_dir (
      .clk          (clk),
      .rst_n        (rst_n),
      .clr          (fdi_chk.err_clear),
      .go           (u_fdi_chk.w_chk_go),
      .granule_viol (u_fdi_chk.w_granule_viol),
      .flit_seq     (u_fdi_chk.r_flit_seq),
      .dir_violation(fdi_chk.dir_violation),
      .dir_flit_seq (fdi_chk.dir_flit_seq)
  );
`endif

`ifdef UVM
  // ---------------------------------------------------------------------------
  // SV-UVM harness: the test classes (module scope, after aou_seq_lib_pkg),
  // uvm_config_db publication of every interface instance, run_test().
  // ---------------------------------------------------------------------------
  import ocah_lib_pkg::*;
  import aou_rule_pkg::*;
  import aou_axi_pkg::*;
  import aou_fdi_pkg::*;
  import aou_lsm_pkg::*;
  import aou_l3_pkg::*;
  import aou_reg_pkg::*;
  import aou_core_csr_uvm_pkg::*;
  import aou_t1_env_pkg::*;
  import aou_seq_lib_pkg::*;
  import aou_fdi_test_pkg::*;

  `include "aou_tests.sv"

  for (genvar r = 0; r < RP_COUNT; r++) begin : g_axi_cfg
    initial begin
      uvm_config_db #(virtual aou_axi_bus_if #(.DATA_W(AXI_W)))::set(
          null, "*", $sformatf("s_axi%0d", r), s_axi[r]);
      uvm_config_db #(virtual aou_axi_bus_if #(.DATA_W(AXI_W)))::set(
          null, "*", $sformatf("m_axi%0d", r), m_axi[r]);
    end
  end

  initial begin
    uvm_config_db #(virtual aou_fdi_mb_if #(.DATA_W(BUS_W)))::set(null, "*", "fdi_mb0", fdi_mb0);
`ifdef TWO_PHY
    uvm_config_db #(virtual aou_fdi_mb_if #(.DATA_W(BUS_W)))::set(null, "*", "fdi_mb1", fdi_mb1);
`endif
    uvm_config_db #(virtual aou_fdi_lsm_if)::set(null, "*", "fdi_lsm", fdi_lsm);
    uvm_config_db #(virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)))::set(null, "*", "apb", apb);
    uvm_config_db #(virtual aou_status_if)::set(null, "*", "status", status);
    uvm_config_db #(virtual aou_irq_if)::set(null, "*", "irq", irq);
    uvm_config_db #(virtual aou_wdt_if)::set(null, "*", "wdt", wdt);
    uvm_config_db #(virtual aou_rst_if)::set(null, "*", "rst", rst);
    uvm_config_db #(virtual aou_axi4pc_ctl_if)::set(null, "*", "axi4pc_ctl", axi4pc_ctl);
    uvm_config_db #(virtual aou_fdi_checker_if)::set(null, "*", "fdi_chk", fdi_chk);
    run_test();
  end
`endif

  // fc.json for scripts/fc_report.py, when the run passes +aou_fc_json (make run COV=1).
  final aou_fc_pkg::aou_fc_db::write_requested();

`ifdef AOU_AXI4PC
  // ---------------------------------------------------------------------------
  // Arm Axi4PC (BP063, optional; Makefile AXI4PC) on each RP's DUT S and M ports, at
  // the RP's own width (g_rp). tb/aou_axi4pc_msg.svh reports its failures as UVM
  // errors. AoU has no REGION or USER signals and no low-power interface.
  // The bench stalls READY on purpose, so the recommended MAX_WAIT rules are off.
  // ARESETn comes from tb/aou_axi4pc_gate.sv: the port's reset (axi_port_rst_n),
  // held after a reset only the DUT saw and after a link event (aou_t1_axi4pc_ctl).
  // ---------------------------------------------------------------------------
`define AOU_AXI4PC_PORT(P) \
    aou_axi4pc_gate u_``P``_gate ( \
      .clk(clk), .bus_rst_n(rst_n), .port_rst_n(axi_port_rst_n), .off_set(axi4pc_ctl.off_set), \
      .resync(axi4pc_ctl.P``_resync[r]), \
      .awvalid(P``_awvalid[r]), .awready(P``_awready[r]), .wvalid(P``_wvalid[r]), \
      .wready(P``_wready[r]), .wlast(P``_wlast[r]), .bvalid(P``_bvalid[r]), \
      .bready(P``_bready[r]), .arvalid(P``_arvalid[r]), .arready(P``_arready[r]), \
      .rvalid(P``_rvalid[r]), .rready(P``_rready[r]), .rlast(P``_rlast[r]), \
      .chk_rst_n(P``_chk_rst_n), .off(axi4pc_ctl.P``_off[r]), \
      .sync_wait(axi4pc_ctl.P``_sync_wait[r]) \
    ); \
    Axi4PC #( \
      .DATA_WIDTH(rp_w(r)), .WID_WIDTH(10), .RID_WIDTH(10), .ADDR_WIDTH(64), \
      .AWUSER_WIDTH(1), .WUSER_WIDTH(1), .BUSER_WIDTH(1), .ARUSER_WIDTH(1), .RUSER_WIDTH(1), \
      .MAXRBURSTS(`AOU_AXI4PC_MAXBURSTS), .MAXWBURSTS(`AOU_AXI4PC_MAXBURSTS), \
      .RecMaxWaitOn(1'b0) \
    ) u_``P``_axi4pc ( \
      .ACLK(clk), .ARESETn(P``_chk_rst_n), \
      .AWID(P``_awid[r]), .AWADDR(P``_awaddr[r]), .AWLEN(P``_awlen[r]), \
      .AWSIZE(P``_awsize[r]), .AWBURST(P``_awburst[r]), .AWLOCK(P``_awlock[r]), \
      .AWCACHE(P``_awcache[r]), .AWPROT(P``_awprot[r]), .AWQOS(P``_awqos[r]), \
      .AWREGION(4'b0), .AWUSER(1'b0), .AWVALID(P``_awvalid[r]), .AWREADY(P``_awready[r]), \
      .WLAST(P``_wlast[r]), .WDATA(P``_wdata[r][rp_w(r)-1:0]), .WSTRB(P``_wstrb[r][rp_w(r)/8-1:0]), .WUSER(1'b0), \
      .WVALID(P``_wvalid[r]), .WREADY(P``_wready[r]), \
      .BID(P``_bid[r]), .BRESP(P``_bresp[r]), .BUSER(1'b0), \
      .BVALID(P``_bvalid[r]), .BREADY(P``_bready[r]), \
      .ARID(P``_arid[r]), .ARADDR(P``_araddr[r]), .ARLEN(P``_arlen[r]), \
      .ARSIZE(P``_arsize[r]), .ARBURST(P``_arburst[r]), .ARLOCK(P``_arlock[r]), \
      .ARCACHE(P``_arcache[r]), .ARPROT(P``_arprot[r]), .ARQOS(P``_arqos[r]), \
      .ARREGION(4'b0), .ARUSER(1'b0), .ARVALID(P``_arvalid[r]), .ARREADY(P``_arready[r]), \
      .RID(P``_rid[r]), .RLAST(P``_rlast[r]), .RDATA(P``_rdata[r][rp_w(r)-1:0]), .RRESP(P``_rresp[r]), \
      .RUSER(1'b0), .RVALID(P``_rvalid[r]), .RREADY(P``_rready[r]), \
      .CACTIVE(1'b1), .CSYSREQ(1'b1), .CSYSACK(1'b1) \
    );
  for (genvar r = 0; r < RP_COUNT; r++) begin : g_axi4pc
    logic s_chk_rst_n;
    logic m_chk_rst_n;
    `AOU_AXI4PC_PORT(s)
    `AOU_AXI4PC_PORT(m)
  end
  for (genvar r = RP_COUNT; r < 8; r++) begin : g_axi4pc_none
    assign axi4pc_ctl.s_off[r] = 1'b0;
    assign axi4pc_ctl.m_off[r] = 1'b0;
    assign axi4pc_ctl.s_sync_wait[r] = 1'b0;
    assign axi4pc_ctl.m_sync_wait[r] = 1'b0;
  end
  assign axi4pc_ctl.present = 1'b1;
`undef AOU_AXI4PC_PORT
`else
  assign axi4pc_ctl.present = 1'b0;
  assign axi4pc_ctl.s_off = '0;
  assign axi4pc_ctl.m_off = '0;
  assign axi4pc_ctl.s_sync_wait = '0;
  assign axi4pc_ctl.m_sync_wait = '0;
`endif

endmodule : tb_top
