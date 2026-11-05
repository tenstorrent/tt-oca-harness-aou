// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Tenstorrent USA Inc
//*************************************************************************
//
// AXI4 functional-coverage bind host for AOU_CORE_TOP.
//
//   One aou_axi4_coverage_mod per resource plane and direction:
//     axi_tx_rp<n> : AXI S port (local masters -> DUT)
//     axi_rx_rp<n> : AXI M port (DUT -> local slaves)
//
//   Attached via `bind AOU_CORE_TOP`: no RTL/TB source modified, no
//   VIP / BFM / UVM dependency, works in any TB that instantiates the core.
//   Ports carry AOU_CORE_TOP's names so the bind connects with `.*`;
//   all inputs (observe-only).
//
//   Enable with +define+AOU_AXI4_FC_COV_EN (Makefile: COV=1).
//
//*************************************************************************

`ifndef AOU_AXI4_COV_BIND_SV
`define AOU_AXI4_COV_BIND_SV

module aou_axi4_cov_bind #(
  parameter int RP_COUNT     = 1,
  parameter int RP0_AXI_DATA_WD = 512,
  parameter int RP1_AXI_DATA_WD = 512,
  parameter int RP2_AXI_DATA_WD = 512,
  parameter int RP3_AXI_DATA_WD = 512,
  // Port width: the widest RP. Each RP's monitor sees only its own width.
  parameter int AXI_DATA_WD  = 512,
  parameter int AXI_ADDR_WD  = 64,
  parameter int AXI_ID_WD    = 10,
  parameter int AXI_LEN_WD   = 8,
  parameter int AXI_STRB_WD  = AXI_DATA_WD / 8,
  // Outstanding limits per RP, as AOU_CORE_TOP takes them: the S port's read and
  // write limits and the M port's pending-ID table depths.
  parameter int RP0_S_RD_MO_CNT = 32,
  parameter int RP0_S_WR_MO_CNT = 32,
  parameter int RP0_M_RD_MO_CNT = 32,
  parameter int RP0_M_WR_MO_CNT = 32,
  parameter int RP1_S_RD_MO_CNT = 32,
  parameter int RP1_S_WR_MO_CNT = 32,
  parameter int RP1_M_RD_MO_CNT = 32,
  parameter int RP1_M_WR_MO_CNT = 32,
  parameter int RP2_S_RD_MO_CNT = 32,
  parameter int RP2_S_WR_MO_CNT = 32,
  parameter int RP2_M_RD_MO_CNT = 32,
  parameter int RP2_M_WR_MO_CNT = 32,
  parameter int RP3_S_RD_MO_CNT = 32,
  parameter int RP3_S_WR_MO_CNT = 32,
  parameter int RP3_M_RD_MO_CNT = 32,
  parameter int RP3_M_WR_MO_CNT = 32
) (
  input wire                                     I_CLK,
  input wire                                     I_RESETN,

  // ---- TX direction: AXI slave ports (local masters -> DUT) ----
  input wire [RP_COUNT-1:0][AXI_ID_WD-1:0]       I_AOU_TX_AXI_S_AWID,
  input wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0]     I_AOU_TX_AXI_S_AWADDR,
  input wire [RP_COUNT-1:0][AXI_LEN_WD-1:0]      I_AOU_TX_AXI_S_AWLEN,
  input wire [RP_COUNT-1:0][2:0]                 I_AOU_TX_AXI_S_AWSIZE,
  input wire [RP_COUNT-1:0][1:0]                 I_AOU_TX_AXI_S_AWBURST,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_S_AWLOCK,
  input wire [RP_COUNT-1:0][3:0]                 I_AOU_TX_AXI_S_AWCACHE,
  input wire [RP_COUNT-1:0][2:0]                 I_AOU_TX_AXI_S_AWPROT,
  input wire [RP_COUNT-1:0][3:0]                 I_AOU_TX_AXI_S_AWQOS,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_S_AWVALID,
  input wire [RP_COUNT-1:0]                      O_AOU_TX_AXI_S_AWREADY,

  input wire [RP_COUNT-1:0][AXI_STRB_WD-1:0]     I_AOU_TX_AXI_S_WSTRB,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_S_WLAST,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_S_WVALID,
  input wire [RP_COUNT-1:0]                      O_AOU_TX_AXI_S_WREADY,

  input wire [RP_COUNT-1:0][1:0]                 O_AOU_RX_AXI_S_BRESP,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_S_BVALID,
  input wire [RP_COUNT-1:0]                      I_AOU_RX_AXI_S_BREADY,

  input wire [RP_COUNT-1:0][AXI_ID_WD-1:0]       I_AOU_TX_AXI_S_ARID,
  input wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0]     I_AOU_TX_AXI_S_ARADDR,
  input wire [RP_COUNT-1:0][AXI_LEN_WD-1:0]      I_AOU_TX_AXI_S_ARLEN,
  input wire [RP_COUNT-1:0][2:0]                 I_AOU_TX_AXI_S_ARSIZE,
  input wire [RP_COUNT-1:0][1:0]                 I_AOU_TX_AXI_S_ARBURST,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_S_ARLOCK,
  input wire [RP_COUNT-1:0][3:0]                 I_AOU_TX_AXI_S_ARCACHE,
  input wire [RP_COUNT-1:0][2:0]                 I_AOU_TX_AXI_S_ARPROT,
  input wire [RP_COUNT-1:0][3:0]                 I_AOU_TX_AXI_S_ARQOS,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_S_ARVALID,
  input wire [RP_COUNT-1:0]                      O_AOU_TX_AXI_S_ARREADY,

  input wire [RP_COUNT-1:0][1:0]                 O_AOU_RX_AXI_S_RRESP,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_S_RLAST,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_S_RVALID,
  input wire [RP_COUNT-1:0]                      I_AOU_RX_AXI_S_RREADY,

  // ---- RX direction: AXI master ports (DUT -> local slaves) ----
  input wire [RP_COUNT-1:0][AXI_ID_WD-1:0]       O_AOU_RX_AXI_M_AWID,
  input wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0]     O_AOU_RX_AXI_M_AWADDR,
  input wire [RP_COUNT-1:0][AXI_LEN_WD-1:0]      O_AOU_RX_AXI_M_AWLEN,
  input wire [RP_COUNT-1:0][2:0]                 O_AOU_RX_AXI_M_AWSIZE,
  input wire [RP_COUNT-1:0][1:0]                 O_AOU_RX_AXI_M_AWBURST,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_M_AWLOCK,
  input wire [RP_COUNT-1:0][3:0]                 O_AOU_RX_AXI_M_AWCACHE,
  input wire [RP_COUNT-1:0][2:0]                 O_AOU_RX_AXI_M_AWPROT,
  input wire [RP_COUNT-1:0][3:0]                 O_AOU_RX_AXI_M_AWQOS,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_M_AWVALID,
  input wire [RP_COUNT-1:0]                      I_AOU_RX_AXI_M_AWREADY,

  input wire [RP_COUNT-1:0][AXI_STRB_WD-1:0]     O_AOU_RX_AXI_M_WSTRB,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_M_WLAST,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_M_WVALID,
  input wire [RP_COUNT-1:0]                      I_AOU_RX_AXI_M_WREADY,

  input wire [RP_COUNT-1:0][1:0]                 I_AOU_TX_AXI_M_BRESP,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_M_BVALID,
  input wire [RP_COUNT-1:0]                      O_AOU_TX_AXI_M_BREADY,

  input wire [RP_COUNT-1:0][AXI_ID_WD-1:0]       O_AOU_RX_AXI_M_ARID,
  input wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0]     O_AOU_RX_AXI_M_ARADDR,
  input wire [RP_COUNT-1:0][AXI_LEN_WD-1:0]      O_AOU_RX_AXI_M_ARLEN,
  input wire [RP_COUNT-1:0][2:0]                 O_AOU_RX_AXI_M_ARSIZE,
  input wire [RP_COUNT-1:0][1:0]                 O_AOU_RX_AXI_M_ARBURST,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_M_ARLOCK,
  input wire [RP_COUNT-1:0][3:0]                 O_AOU_RX_AXI_M_ARCACHE,
  input wire [RP_COUNT-1:0][2:0]                 O_AOU_RX_AXI_M_ARPROT,
  input wire [RP_COUNT-1:0][3:0]                 O_AOU_RX_AXI_M_ARQOS,
  input wire [RP_COUNT-1:0]                      O_AOU_RX_AXI_M_ARVALID,
  input wire [RP_COUNT-1:0]                      I_AOU_RX_AXI_M_ARREADY,

  input wire [RP_COUNT-1:0][1:0]                 I_AOU_TX_AXI_M_RRESP,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_M_RLAST,
  input wire [RP_COUNT-1:0]                      I_AOU_TX_AXI_M_RVALID,
  input wire [RP_COUNT-1:0]                      O_AOU_TX_AXI_M_RREADY
);

  // Each RP's monitors are sized by that RP's larger read or write limit per
  // direction.
  localparam int RP_DATA_WD[4] = '{RP0_AXI_DATA_WD, RP1_AXI_DATA_WD,
                                   RP2_AXI_DATA_WD, RP3_AXI_DATA_WD};
  localparam int RP_S_RD_MO[4] = '{RP0_S_RD_MO_CNT, RP1_S_RD_MO_CNT,
                                   RP2_S_RD_MO_CNT, RP3_S_RD_MO_CNT};
  localparam int RP_S_WR_MO[4] = '{RP0_S_WR_MO_CNT, RP1_S_WR_MO_CNT,
                                   RP2_S_WR_MO_CNT, RP3_S_WR_MO_CNT};
  localparam int RP_M_RD_MO[4] = '{RP0_M_RD_MO_CNT, RP1_M_RD_MO_CNT,
                                   RP2_M_RD_MO_CNT, RP3_M_RD_MO_CNT};
  localparam int RP_M_WR_MO[4] = '{RP0_M_WR_MO_CNT, RP1_M_WR_MO_CNT,
                                   RP2_M_WR_MO_CNT, RP3_M_WR_MO_CNT};

  for (genvar g = 0; g < RP_COUNT; g++) begin : g_rp

    localparam string RPS = $sformatf("rp%0d", g);
    localparam int    WD  = RP_DATA_WD[g];
    localparam int    S_MAX_OS = (RP_S_RD_MO[g] > RP_S_WR_MO[g]) ? RP_S_RD_MO[g] : RP_S_WR_MO[g];
    localparam int    M_MAX_OS = (RP_M_RD_MO[g] > RP_M_WR_MO[g]) ? RP_M_RD_MO[g] : RP_M_WR_MO[g];

    aou_axi4_coverage_mod #(
      .INST_NAME       ({"axi_tx_", RPS}),
      .ADDR_WIDTH      (AXI_ADDR_WD),
      .DATA_WIDTH      (WD),
      .ID_WIDTH        (AXI_ID_WD),
      .MAX_OUTSTANDING (S_MAX_OS)
    ) u_cov_tx (
      .clk      (I_CLK),
      .rst_n    (I_RESETN),

      .aw_valid (I_AOU_TX_AXI_S_AWVALID[g]),
      .aw_ready (O_AOU_TX_AXI_S_AWREADY[g]),
      .aw_addr  (I_AOU_TX_AXI_S_AWADDR[g]),
      .aw_id    (I_AOU_TX_AXI_S_AWID[g]),
      .aw_len   (8'(I_AOU_TX_AXI_S_AWLEN[g])),
      .aw_size  (I_AOU_TX_AXI_S_AWSIZE[g]),
      .aw_burst (I_AOU_TX_AXI_S_AWBURST[g]),
      .aw_lock  (I_AOU_TX_AXI_S_AWLOCK[g]),
      .aw_cache (I_AOU_TX_AXI_S_AWCACHE[g]),
      .aw_prot  (I_AOU_TX_AXI_S_AWPROT[g]),
      .aw_qos   (I_AOU_TX_AXI_S_AWQOS[g]),

      .w_valid  (I_AOU_TX_AXI_S_WVALID[g]),
      .w_ready  (O_AOU_TX_AXI_S_WREADY[g]),
      .w_strb   (I_AOU_TX_AXI_S_WSTRB[g][WD/8-1:0]),
      .w_last   (I_AOU_TX_AXI_S_WLAST[g]),

      .b_valid  (O_AOU_RX_AXI_S_BVALID[g]),
      .b_ready  (I_AOU_RX_AXI_S_BREADY[g]),
      .b_resp   (O_AOU_RX_AXI_S_BRESP[g]),

      .ar_valid (I_AOU_TX_AXI_S_ARVALID[g]),
      .ar_ready (O_AOU_TX_AXI_S_ARREADY[g]),
      .ar_addr  (I_AOU_TX_AXI_S_ARADDR[g]),
      .ar_id    (I_AOU_TX_AXI_S_ARID[g]),
      .ar_len   (8'(I_AOU_TX_AXI_S_ARLEN[g])),
      .ar_size  (I_AOU_TX_AXI_S_ARSIZE[g]),
      .ar_burst (I_AOU_TX_AXI_S_ARBURST[g]),
      .ar_lock  (I_AOU_TX_AXI_S_ARLOCK[g]),
      .ar_cache (I_AOU_TX_AXI_S_ARCACHE[g]),
      .ar_prot  (I_AOU_TX_AXI_S_ARPROT[g]),
      .ar_qos   (I_AOU_TX_AXI_S_ARQOS[g]),

      .r_valid  (O_AOU_RX_AXI_S_RVALID[g]),
      .r_ready  (I_AOU_RX_AXI_S_RREADY[g]),
      .r_resp   (O_AOU_RX_AXI_S_RRESP[g]),
      .r_last   (O_AOU_RX_AXI_S_RLAST[g])
    );

    aou_axi4_coverage_mod #(
      .INST_NAME       ({"axi_rx_", RPS}),
      .ADDR_WIDTH      (AXI_ADDR_WD),
      .DATA_WIDTH      (WD),
      .ID_WIDTH        (AXI_ID_WD),
      .MAX_OUTSTANDING (M_MAX_OS)
    ) u_cov_rx (
      .clk      (I_CLK),
      .rst_n    (I_RESETN),

      .aw_valid (O_AOU_RX_AXI_M_AWVALID[g]),
      .aw_ready (I_AOU_RX_AXI_M_AWREADY[g]),
      .aw_addr  (O_AOU_RX_AXI_M_AWADDR[g]),
      .aw_id    (O_AOU_RX_AXI_M_AWID[g]),
      .aw_len   (8'(O_AOU_RX_AXI_M_AWLEN[g])),
      .aw_size  (O_AOU_RX_AXI_M_AWSIZE[g]),
      .aw_burst (O_AOU_RX_AXI_M_AWBURST[g]),
      .aw_lock  (O_AOU_RX_AXI_M_AWLOCK[g]),
      .aw_cache (O_AOU_RX_AXI_M_AWCACHE[g]),
      .aw_prot  (O_AOU_RX_AXI_M_AWPROT[g]),
      .aw_qos   (O_AOU_RX_AXI_M_AWQOS[g]),

      .w_valid  (O_AOU_RX_AXI_M_WVALID[g]),
      .w_ready  (I_AOU_RX_AXI_M_WREADY[g]),
      .w_strb   (O_AOU_RX_AXI_M_WSTRB[g][WD/8-1:0]),
      .w_last   (O_AOU_RX_AXI_M_WLAST[g]),

      .b_valid  (I_AOU_TX_AXI_M_BVALID[g]),
      .b_ready  (O_AOU_TX_AXI_M_BREADY[g]),
      .b_resp   (I_AOU_TX_AXI_M_BRESP[g]),

      .ar_valid (O_AOU_RX_AXI_M_ARVALID[g]),
      .ar_ready (I_AOU_RX_AXI_M_ARREADY[g]),
      .ar_addr  (O_AOU_RX_AXI_M_ARADDR[g]),
      .ar_id    (O_AOU_RX_AXI_M_ARID[g]),
      .ar_len   (8'(O_AOU_RX_AXI_M_ARLEN[g])),
      .ar_size  (O_AOU_RX_AXI_M_ARSIZE[g]),
      .ar_burst (O_AOU_RX_AXI_M_ARBURST[g]),
      .ar_lock  (O_AOU_RX_AXI_M_ARLOCK[g]),
      .ar_cache (O_AOU_RX_AXI_M_ARCACHE[g]),
      .ar_prot  (O_AOU_RX_AXI_M_ARPROT[g]),
      .ar_qos   (O_AOU_RX_AXI_M_ARQOS[g]),

      .r_valid  (I_AOU_TX_AXI_M_RVALID[g]),
      .r_ready  (O_AOU_TX_AXI_M_RREADY[g]),
      .r_resp   (I_AOU_TX_AXI_M_RRESP[g]),
      .r_last   (I_AOU_TX_AXI_M_RLAST[g])
    );

  end : g_rp

endmodule : aou_axi4_cov_bind

`endif // AOU_AXI4_COV_BIND_SV

//*************************************************************************
// Bind directive: attach the coverage host to every AOU_CORE_TOP instance.
// Parameters are evaluated in the context of each target instance, so the
// coverage tracks the DUT's RP_COUNT / widths / MO counts.
//*************************************************************************
`ifdef AOU_AXI4_FC_COV_EN
bind AOU_CORE_TOP aou_axi4_cov_bind #(
  .RP_COUNT        (RP_COUNT),
  .RP0_AXI_DATA_WD (RP0_AXI_DATA_WD),
  .RP1_AXI_DATA_WD (RP1_AXI_DATA_WD),
  .RP2_AXI_DATA_WD (RP2_AXI_DATA_WD),
  .RP3_AXI_DATA_WD (RP3_AXI_DATA_WD),
  .AXI_DATA_WD     (RP_AXI_DATA_WD_MAX),
  .AXI_ADDR_WD     (AXI_ADDR_WD),
  .AXI_ID_WD       (AXI_ID_WD),
  .AXI_LEN_WD      (AXI_LEN_WD),
  .AXI_STRB_WD     (RP_AXI_STRB_WD_MAX),
  .RP0_S_RD_MO_CNT (RP0_S_RD_MO_CNT),
  .RP0_S_WR_MO_CNT (RP0_S_WR_MO_CNT),
  .RP0_M_RD_MO_CNT (RP0_M_RD_MO_CNT),
  .RP0_M_WR_MO_CNT (RP0_M_WR_MO_CNT),
  .RP1_S_RD_MO_CNT (RP1_S_RD_MO_CNT),
  .RP1_S_WR_MO_CNT (RP1_S_WR_MO_CNT),
  .RP1_M_RD_MO_CNT (RP1_M_RD_MO_CNT),
  .RP1_M_WR_MO_CNT (RP1_M_WR_MO_CNT),
  .RP2_S_RD_MO_CNT (RP2_S_RD_MO_CNT),
  .RP2_S_WR_MO_CNT (RP2_S_WR_MO_CNT),
  .RP2_M_RD_MO_CNT (RP2_M_RD_MO_CNT),
  .RP2_M_WR_MO_CNT (RP2_M_WR_MO_CNT),
  .RP3_S_RD_MO_CNT (RP3_S_RD_MO_CNT),
  .RP3_S_WR_MO_CNT (RP3_S_WR_MO_CNT),
  .RP3_M_RD_MO_CNT (RP3_M_RD_MO_CNT),
  .RP3_M_WR_MO_CNT (RP3_M_WR_MO_CNT)
) u_aou_axi4_cov_bind (.*);
`endif
