
`timescale 1ns/1ps

// Asymmetric routing for RP_COUNT=1..4.
// RP_COUNT=4: one 4:1 MUX for the first duplicate group, a 3:1 MUX for the second group in 2+2.
// Each RP has independent AW/AR remappers before its MUX.
// Default ID mapping: RP_COUNT=2: 10->9 bits; RP_COUNT=3/4: 10->8 bits.
// RP_COUNT=1 generates neither ID remappers nor output reverse register slices.
// Responses are demultiplexed first, then restored by the source RP table.
// Singleton and disabled-asymmetry routes preserve the original ten-bit ID.
// WDATA/WSTRB/WDLEN and the remaining AXI payload routing are preserved.
// Configure EN/DEST before traffic and keep stable until all traffic drains.
// Upstream per-RP MO limits must be enforced for remapper sizing.

module AOU_ASYMMETRIC_RP_PROC #(
    parameter   RP_COUNT                    = 1,
    parameter   AXI_ADDR_WD                 = 64,
    parameter   AXI_ID_WD                   = 10,
    parameter   AXI_LEN_WD                  = 8,
    parameter   RP_AXI_DATA_WD_MAX          = 1024,
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024,

    parameter   RP0_S_RD_MO_CNT             = 32,
    parameter   RP0_S_WR_MO_CNT             = 32,

    parameter   RP1_S_RD_MO_CNT             = 32,
    parameter   RP1_S_WR_MO_CNT             = 32,

    parameter   RP2_S_RD_MO_CNT             = 32,
    parameter   RP2_S_WR_MO_CNT             = 32,

    parameter   RP3_S_RD_MO_CNT             = 32,
    parameter   RP3_S_WR_MO_CNT             = 32,

    // 0: direct output; 1: AW/W/AR reverse slices when RP_COUNT >= 2.
    parameter bit OUTPUT_REV_RS_EN         = 1'b0,

    localparam  REMAP_ID_WD                 = (RP_COUNT == 2) ? 9 : 8,

    localparam  RP_AXI_STRB_WD_MAX          = RP_AXI_DATA_WD_MAX / 8

)
(
    input                                           I_CLK              ,
    input                                           I_RESETN           ,

    //AXI SI I/F
    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_AXI_S_ARID   ,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         I_AOU_AXI_S_ARADDR ,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]          I_AOU_AXI_S_ARLEN  ,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_AXI_S_ARSIZE ,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_AXI_S_ARBURST,       //There is no burst field on AOU
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_ARLOCK ,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_AXI_S_ARCACHE,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_AXI_S_ARPROT ,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_AXI_S_ARQOS  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_ARVALID,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_S_ARREADY,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_AXI_S_RID    ,
    output  [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]  O_AOU_AXI_S_RDATA  ,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_AXI_S_RRESP  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_S_RLAST  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_S_RVALID ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_RREADY ,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_AXI_S_AWID   ,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         I_AOU_AXI_S_AWADDR ,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]          I_AOU_AXI_S_AWLEN  ,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_AXI_S_AWSIZE ,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_AXI_S_AWBURST,       //There is no burst field on AOU
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_AWLOCK ,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_AXI_S_AWCACHE,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_AXI_S_AWPROT ,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_AXI_S_AWQOS  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_AWVALID,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_S_AWREADY,

    input   [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]  I_AOU_AXI_S_WDATA  ,
    input   [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]  I_AOU_AXI_S_WSTRB  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_WLAST  ,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_AXI_S_WDLEN  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_WVALID ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_S_WREADY ,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_AXI_S_BID    ,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_AXI_S_BRESP  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_S_BVALID ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_S_BREADY ,

    //AXI MI I/F
    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_AXI_M_ARID   ,
    output  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         O_AOU_AXI_M_ARADDR ,
    output  [RP_COUNT-1:0][AXI_LEN_WD-1:0]          O_AOU_AXI_M_ARLEN  ,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_AXI_M_ARSIZE ,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_AXI_M_ARBURST,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_ARLOCK ,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_AXI_M_ARCACHE,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_AXI_M_ARPROT ,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_AXI_M_ARQOS  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_ARVALID,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_M_ARREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_AXI_M_RID    ,
    input   [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]  I_AOU_AXI_M_RDATA  ,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_AXI_M_RRESP  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_M_RLAST  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_M_RVALID ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_RREADY ,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_AXI_M_AWID   ,
    output  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         O_AOU_AXI_M_AWADDR ,
    output  [RP_COUNT-1:0][AXI_LEN_WD-1:0]          O_AOU_AXI_M_AWLEN  ,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_AXI_M_AWSIZE ,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_AXI_M_AWBURST,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_AWLOCK ,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_AXI_M_AWCACHE,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_AXI_M_AWPROT ,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_AXI_M_AWQOS  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_AWVALID,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_M_AWREADY,

    output  [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]  O_AOU_AXI_M_WDATA  ,
    output  [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]  O_AOU_AXI_M_WSTRB  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_WLAST  ,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_AXI_M_WDLEN  ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_WVALID ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_M_WREADY ,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_AXI_M_BID    ,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_AXI_M_BRESP  ,
    input   [RP_COUNT-1:0]                          I_AOU_AXI_M_BVALID ,
    output  [RP_COUNT-1:0]                          O_AOU_AXI_M_BREADY ,
 
    // QoS policy matches AOU_TX_AXI_BUFFER; configure while traffic is idle.
    input   [1:0]                                   I_PRIOR_RP_AXI_ARB_MODE,
    input   [1:0]                                   I_PRIOR_RP_AXI_RP0_PRIOR,
    input   [1:0]                                   I_PRIOR_RP_AXI_RP1_PRIOR,
    input   [1:0]                                   I_PRIOR_RP_AXI_RP2_PRIOR,
    input   [1:0]                                   I_PRIOR_RP_AXI_RP3_PRIOR,
    input   [3:0]                                   I_PRIOR_RP_AXI_AXI_QOS_TO_NP,
    input   [3:0]                                   I_PRIOR_RP_AXI_AXI_QOS_TO_HP,
    input   [15:0]                                  I_PRIOR_TIMER_TIMER_RESOLUTION,
    input   [15:0]                                  I_PRIOR_TIMER_TIMER_THRESHOLD,

    //Destination RP configuration (static while traffic is active)
    input   [3:0][1:0]                              I_TX_RP_SEL          ,
    input                                           I_ASYMMETRIC_RP_EN 
);

// Source RP priorities are calculated before merging. Timeout aging tracks
// each currently presented AW/AR request without adding a payload FIFO.
// The original four-bit AxQOS remains part of the payload.
wire [3:0][1:0]          w_source_port_priority;
wire [RP_COUNT-1:0][1:0] w_source_aw_priority;
wire [RP_COUNT-1:0][1:0] w_source_ar_priority;
wire [RP_COUNT-1:0][1:0] w_base_aw_priority;
wire [RP_COUNT-1:0][1:0] w_base_ar_priority;

generate
    if(RP_COUNT > 1) begin
        wire [RP_COUNT-1:0]      w_aw_trans_expired;
        wire [RP_COUNT-1:0]      w_ar_trans_expired;
        wire w_trans_enable;

        assign w_trans_enable = I_ASYMMETRIC_RP_EN && ((I_PRIOR_RP_AXI_ARB_MODE == 2'b01) || (I_PRIOR_RP_AXI_ARB_MODE == 2'b10));

        // AW request aging: preserve timeout until this request is accepted.
        for (genvar aw_rp = 0; aw_rp < RP_COUNT; aw_rp++) begin : g_aw_trans
            logic [15:0] r_aw_resolution_count;
            logic [15:0] r_aw_timeout_count;
            wire w_aw_internal_count_tick;

            assign w_aw_internal_count_tick = (r_aw_resolution_count == I_PRIOR_TIMER_TIMER_RESOLUTION);
            assign w_aw_trans_expired[aw_rp] = w_trans_enable && I_AOU_AXI_S_AWVALID[aw_rp] && (r_aw_timeout_count >= I_PRIOR_TIMER_TIMER_THRESHOLD);

            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_aw_resolution_count <= '0;
                end else if (~w_trans_enable) begin
                    r_aw_resolution_count <= '0;
                end else if (I_AOU_AXI_S_AWVALID[aw_rp] && O_AOU_AXI_S_AWREADY[aw_rp]) begin
                    r_aw_resolution_count <= '0;
                end else if (I_AOU_AXI_S_AWVALID[aw_rp] && !w_aw_trans_expired[aw_rp]) begin
                    r_aw_resolution_count <= w_aw_internal_count_tick ? 0 : r_aw_resolution_count + 1;
                end
            end

            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_aw_timeout_count <= '0;
                end else if (~w_trans_enable) begin
                    r_aw_timeout_count <= '0;
                end else if (I_AOU_AXI_S_AWVALID[aw_rp] && O_AOU_AXI_S_AWREADY[aw_rp]) begin
                    r_aw_timeout_count <= '0;
                end else if (I_AOU_AXI_S_AWVALID[aw_rp] && w_aw_internal_count_tick) begin
                    r_aw_timeout_count <= (r_aw_timeout_count == I_PRIOR_TIMER_TIMER_THRESHOLD) ? r_aw_timeout_count : r_aw_timeout_count + 1;
                end
            end

            assign w_source_aw_priority[aw_rp] = w_aw_trans_expired[aw_rp] ? 2'b11 : w_base_aw_priority[aw_rp];
        end

        // AR request aging: preserve timeout until this request is accepted.
        for (genvar ar_rp = 0; ar_rp < RP_COUNT; ar_rp++) begin : g_ar_trans
            logic [15:0] r_ar_resolution_count;
            logic [15:0] r_ar_timeout_count;
            wire w_ar_internal_count_tick;

            assign w_ar_internal_count_tick = (r_ar_resolution_count == I_PRIOR_TIMER_TIMER_RESOLUTION);
            assign w_ar_trans_expired[ar_rp] = w_trans_enable && I_AOU_AXI_S_ARVALID[ar_rp] && (r_ar_timeout_count >= I_PRIOR_TIMER_TIMER_THRESHOLD);

            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_ar_resolution_count <= '0;
                end else if (~w_trans_enable) begin
                    r_ar_resolution_count <= '0;
                end else if (I_AOU_AXI_S_ARVALID[ar_rp] && O_AOU_AXI_S_ARREADY[ar_rp]) begin
                    r_ar_resolution_count <= '0;
                end else if (I_AOU_AXI_S_ARVALID[ar_rp] && !w_ar_trans_expired[ar_rp]) begin
                    r_ar_resolution_count <= w_ar_internal_count_tick ? 0 : r_ar_resolution_count + 1;
                end
            end

            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_ar_timeout_count <= '0;
                end else if (~w_trans_enable) begin
                    r_ar_timeout_count <= '0;
                end else if (I_AOU_AXI_S_ARVALID[ar_rp] && O_AOU_AXI_S_ARREADY[ar_rp]) begin
                    r_ar_timeout_count <= '0;
                end else if (I_AOU_AXI_S_ARVALID[ar_rp] && w_ar_internal_count_tick) begin
                    r_ar_timeout_count <= (r_ar_timeout_count == I_PRIOR_TIMER_TIMER_THRESHOLD) ? r_ar_timeout_count : r_ar_timeout_count + 1;
                end
            end

            assign w_source_ar_priority[ar_rp] = w_ar_trans_expired[ar_rp] ? 2'b11 : w_base_ar_priority[ar_rp];
        end
    end
endgenerate

assign w_source_port_priority[0] = (I_PRIOR_RP_AXI_RP0_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP0_PRIOR;
assign w_source_port_priority[1] = (I_PRIOR_RP_AXI_RP1_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP1_PRIOR;
assign w_source_port_priority[2] = (I_PRIOR_RP_AXI_RP2_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP2_PRIOR;
assign w_source_port_priority[3] = (I_PRIOR_RP_AXI_RP3_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP3_PRIOR;

generate
    for (genvar qos_rp = 0; qos_rp < RP_COUNT; qos_rp++) begin : g_source_priority
        assign w_base_aw_priority[qos_rp] = (I_PRIOR_RP_AXI_ARB_MODE == 2'b01) ? w_source_port_priority[qos_rp] :
            (I_AOU_AXI_S_AWQOS[qos_rp] >= I_PRIOR_RP_AXI_AXI_QOS_TO_HP) ? 2'b11 :
            (I_AOU_AXI_S_AWQOS[qos_rp] >= I_PRIOR_RP_AXI_AXI_QOS_TO_NP) ? 2'b10 : 2'b01;
        assign w_base_ar_priority[qos_rp] = (I_PRIOR_RP_AXI_ARB_MODE == 2'b01) ? w_source_port_priority[qos_rp] :
            (I_AOU_AXI_S_ARQOS[qos_rp] >= I_PRIOR_RP_AXI_AXI_QOS_TO_HP) ? 2'b11 :
            (I_AOU_AXI_S_ARQOS[qos_rp] >= I_PRIOR_RP_AXI_AXI_QOS_TO_NP) ? 2'b10 : 2'b01;
    end
endgenerate

// Output reverse register slices: independent AW/W/AR skid buffers per MI RP.
// Bypass for RP_COUNT=1 or OUTPUT_REV_RS_EN=0.
wire [RP_COUNT-1:0][AXI_ID_WD-1:0] w_pre_rs_awid;
wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0] w_pre_rs_awaddr;
wire [RP_COUNT-1:0][AXI_LEN_WD-1:0] w_pre_rs_awlen;
wire [RP_COUNT-1:0][2:0] w_pre_rs_awsize;
wire [RP_COUNT-1:0][1:0] w_pre_rs_awburst;
wire [RP_COUNT-1:0] w_pre_rs_awlock;
wire [RP_COUNT-1:0][3:0] w_pre_rs_awcache;
wire [RP_COUNT-1:0][2:0] w_pre_rs_awprot;
wire [RP_COUNT-1:0][3:0] w_pre_rs_awqos;
wire [RP_COUNT-1:0] w_pre_rs_awvalid;
wire [RP_COUNT-1:0] w_pre_rs_awready;
wire [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] w_pre_rs_wdata;
wire [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0] w_pre_rs_wstrb;
wire [RP_COUNT-1:0] w_pre_rs_wlast;
wire [RP_COUNT-1:0][1:0] w_pre_rs_wdlen;
wire [RP_COUNT-1:0] w_pre_rs_wvalid;
wire [RP_COUNT-1:0] w_pre_rs_wready;
wire [RP_COUNT-1:0][AXI_ID_WD-1:0] w_pre_rs_arid;
wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0] w_pre_rs_araddr;
wire [RP_COUNT-1:0][AXI_LEN_WD-1:0] w_pre_rs_arlen;
wire [RP_COUNT-1:0][2:0] w_pre_rs_arsize;
wire [RP_COUNT-1:0][1:0] w_pre_rs_arburst;
wire [RP_COUNT-1:0] w_pre_rs_arlock;
wire [RP_COUNT-1:0][3:0] w_pre_rs_arcache;
wire [RP_COUNT-1:0][2:0] w_pre_rs_arprot;
wire [RP_COUNT-1:0][3:0] w_pre_rs_arqos;
wire [RP_COUNT-1:0] w_pre_rs_arvalid;
wire [RP_COUNT-1:0] w_pre_rs_arready;

generate
    if ((RP_COUNT == 1) || !OUTPUT_REV_RS_EN) begin : g_output_bypass
        assign O_AOU_AXI_M_AWID      = w_pre_rs_awid;
        assign O_AOU_AXI_M_AWADDR    = w_pre_rs_awaddr;
        assign O_AOU_AXI_M_AWLEN     = w_pre_rs_awlen;
        assign O_AOU_AXI_M_AWSIZE    = w_pre_rs_awsize;
        assign O_AOU_AXI_M_AWBURST   = w_pre_rs_awburst;
        assign O_AOU_AXI_M_AWLOCK    = w_pre_rs_awlock;
        assign O_AOU_AXI_M_AWCACHE   = w_pre_rs_awcache;
        assign O_AOU_AXI_M_AWPROT    = w_pre_rs_awprot;
        assign O_AOU_AXI_M_AWQOS     = w_pre_rs_awqos;
        assign O_AOU_AXI_M_AWVALID   = w_pre_rs_awvalid;
        assign w_pre_rs_awready      = I_AOU_AXI_M_AWREADY;
        assign O_AOU_AXI_M_WDATA     = w_pre_rs_wdata;
        assign O_AOU_AXI_M_WSTRB     = w_pre_rs_wstrb;
        assign O_AOU_AXI_M_WLAST     = w_pre_rs_wlast;
        assign O_AOU_AXI_M_WDLEN     = w_pre_rs_wdlen;
        assign O_AOU_AXI_M_WVALID    = w_pre_rs_wvalid;
        assign w_pre_rs_wready       = I_AOU_AXI_M_WREADY;
        assign O_AOU_AXI_M_ARID      = w_pre_rs_arid;
        assign O_AOU_AXI_M_ARADDR    = w_pre_rs_araddr;
        assign O_AOU_AXI_M_ARLEN     = w_pre_rs_arlen;
        assign O_AOU_AXI_M_ARSIZE    = w_pre_rs_arsize;
        assign O_AOU_AXI_M_ARBURST   = w_pre_rs_arburst;
        assign O_AOU_AXI_M_ARLOCK    = w_pre_rs_arlock;
        assign O_AOU_AXI_M_ARCACHE   = w_pre_rs_arcache;
        assign O_AOU_AXI_M_ARPROT    = w_pre_rs_arprot;
        assign O_AOU_AXI_M_ARQOS     = w_pre_rs_arqos;
        assign O_AOU_AXI_M_ARVALID   = w_pre_rs_arvalid;
        assign w_pre_rs_arready      = I_AOU_AXI_M_ARREADY;
    end else begin : g_output_rs_en
        for (genvar out_rp = 0; out_rp < RP_COUNT; out_rp++) begin : g_output_rev_rs
            AOU_REV_RS #(
                .DATA_WIDTH (AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 17)
            ) u_aw_rev_rs (
                .I_CLK     ( I_CLK                       ),
                .I_RESETN  ( I_RESETN                    ),
                .I_SVALID  ( w_pre_rs_awvalid[out_rp]    ),
                .O_SREADY  ( w_pre_rs_awready[out_rp]    ),
                .I_SDATA   ( {w_pre_rs_awid[out_rp], w_pre_rs_awaddr[out_rp], w_pre_rs_awlen[out_rp], w_pre_rs_awsize[out_rp], w_pre_rs_awburst[out_rp], w_pre_rs_awlock[out_rp], w_pre_rs_awcache[out_rp], w_pre_rs_awprot[out_rp], w_pre_rs_awqos[out_rp]}),
                .O_MVALID  ( O_AOU_AXI_M_AWVALID[out_rp] ),
                .I_MREADY  ( I_AOU_AXI_M_AWREADY[out_rp] ),
                .O_MDATA   ( {O_AOU_AXI_M_AWID[out_rp], O_AOU_AXI_M_AWADDR[out_rp], O_AOU_AXI_M_AWLEN[out_rp], O_AOU_AXI_M_AWSIZE[out_rp], O_AOU_AXI_M_AWBURST[out_rp], O_AOU_AXI_M_AWLOCK[out_rp], O_AOU_AXI_M_AWCACHE[out_rp], O_AOU_AXI_M_AWPROT[out_rp], O_AOU_AXI_M_AWQOS[out_rp]})
            );
            AOU_REV_RS #(
                .DATA_WIDTH(RP_AXI_DATA_WD_MAX + RP_AXI_STRB_WD_MAX + 3)
            ) u_w_rev_rs (
                .I_CLK     ( I_CLK                      ),
                .I_RESETN  ( I_RESETN                   ),
                .I_SVALID  ( w_pre_rs_wvalid[out_rp]    ),
                .O_SREADY  ( w_pre_rs_wready[out_rp]    ),
                .I_SDATA   ( {w_pre_rs_wdata[out_rp], w_pre_rs_wstrb[out_rp], w_pre_rs_wlast[out_rp], w_pre_rs_wdlen[out_rp]}),
                .O_MVALID  ( O_AOU_AXI_M_WVALID[out_rp] ),
                .I_MREADY  ( I_AOU_AXI_M_WREADY[out_rp] ),
                .O_MDATA   ( {O_AOU_AXI_M_WDATA[out_rp], O_AOU_AXI_M_WSTRB[out_rp], O_AOU_AXI_M_WLAST[out_rp], O_AOU_AXI_M_WDLEN[out_rp]})
            );
            AOU_REV_RS #(
                .DATA_WIDTH(AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 17)
            ) u_ar_rev_rs (
                .I_CLK     ( I_CLK                       ),
                .I_RESETN  ( I_RESETN                    ),
                .I_SVALID  ( w_pre_rs_arvalid[out_rp]    ),
                .O_SREADY  ( w_pre_rs_arready[out_rp]    ),
                .I_SDATA   ( {w_pre_rs_arid[out_rp], w_pre_rs_araddr[out_rp], w_pre_rs_arlen[out_rp], w_pre_rs_arsize[out_rp], w_pre_rs_arburst[out_rp], w_pre_rs_arlock[out_rp], w_pre_rs_arcache[out_rp], w_pre_rs_arprot[out_rp], w_pre_rs_arqos[out_rp]}),
                .O_MVALID  ( O_AOU_AXI_M_ARVALID[out_rp] ),
                .I_MREADY  ( I_AOU_AXI_M_ARREADY[out_rp] ),
                .O_MDATA   ( {O_AOU_AXI_M_ARID[out_rp], O_AOU_AXI_M_ARADDR[out_rp], O_AOU_AXI_M_ARLEN[out_rp], O_AOU_AXI_M_ARSIZE[out_rp], O_AOU_AXI_M_ARBURST[out_rp], O_AOU_AXI_M_ARLOCK[out_rp], O_AOU_AXI_M_ARCACHE[out_rp], O_AOU_AXI_M_ARPROT[out_rp], O_AOU_AXI_M_ARQOS[out_rp]})
            );
        end
    end
endgenerate




// Per-RP ID conversion before arbitration. A four-RP merge emits
// {remapped_ID[7:0], source_RP[1:0]} on the existing ten-bit MI ID.
localparam int RP_WR_MO_CNT [4] = '{RP0_S_WR_MO_CNT, RP1_S_WR_MO_CNT, RP2_S_WR_MO_CNT, RP3_S_WR_MO_CNT};
localparam int RP_RD_MO_CNT [4] = '{RP0_S_RD_MO_CNT, RP1_S_RD_MO_CNT, RP2_S_RD_MO_CNT, RP3_S_RD_MO_CNT};
wire [RP_COUNT-1:0] w_rp_remap_en;
wire [RP_COUNT-1:0] w_rp_aw_map_ready, w_rp_ar_map_ready;
wire [RP_COUNT-1:0][REMAP_ID_WD-1:0] w_rp_aw_nid, w_rp_ar_nid;
wire [RP_COUNT-1:0][REMAP_ID_WD-1:0] w_rp_b_nid, w_rp_r_nid;
wire [RP_COUNT-1:0] w_rp_bvalid, w_rp_rvalid, w_rp_rlast;
wire [RP_COUNT-1:0][AXI_ID_WD-1:0] w_rp_bid, w_rp_rid;

generate
    if (RP_COUNT >= 2) begin : g_id_remap_enabled
        for (genvar rp = 0; rp < RP_COUNT; rp++) begin : g_rp_id_remap
            AOU_ID_REMAPPER #(
                .WID_WD ( AXI_ID_WD          ),
                .NID_WD ( REMAP_ID_WD        ),
                .MO_NUM ( RP_WR_MO_CNT[rp]   )
            ) u_awid_remapper (
                .I_CLK          ( I_CLK                                       ),
                .I_RESETN       ( I_RESETN                                    ),
                .I_AR_WID       ( I_AOU_AXI_S_AWID[rp]                        ),
                .I_AR_VALID     ( I_AOU_AXI_S_AWVALID[rp] & w_rp_remap_en[rp] ),
                .I_AR_READY     ( O_AOU_AXI_S_AWREADY[rp]                     ),
                .O_AR_MAP_READY ( w_rp_aw_map_ready[rp]                       ),
                .O_AR_NID       ( w_rp_aw_nid[rp]                             ),
                .I_R_NID        ( w_rp_b_nid[rp]                              ),
                .I_R_VALID      ( w_rp_bvalid[rp]                             ),
                .I_R_READY      ( I_AOU_AXI_S_BREADY[rp]                      ),
                .I_R_LAST       ( 1'b1                                        ),
                .O_R_WID        ( w_rp_bid[rp]                                )
            );
    
            AOU_ID_REMAPPER #(
                .WID_WD ( AXI_ID_WD         ),
                .NID_WD ( REMAP_ID_WD       ),
                .MO_NUM ( RP_RD_MO_CNT[rp]  )
            ) u_arid_remapper (
                .I_CLK          ( I_CLK                                       ),
                .I_RESETN       ( I_RESETN                                    ),
                .I_AR_WID       ( I_AOU_AXI_S_ARID[rp]                        ),
                .I_AR_VALID     ( I_AOU_AXI_S_ARVALID[rp] & w_rp_remap_en[rp] ),
                .I_AR_READY     ( O_AOU_AXI_S_ARREADY[rp]                     ),
                .O_AR_MAP_READY ( w_rp_ar_map_ready[rp]                       ),
                .O_AR_NID       ( w_rp_ar_nid[rp]                             ),
                .I_R_NID        ( w_rp_r_nid[rp]                              ),
                .I_R_VALID      ( w_rp_rvalid[rp]                             ),
                .I_R_READY      ( I_AOU_AXI_S_RREADY[rp]                      ),
                .I_R_LAST       ( w_rp_rlast[rp]                              ),
                .O_R_WID        ( w_rp_rid[rp]                                )
            );
        end
    end else begin : g_id_remap_unused
        // RP_COUNT=1 uses the full-width ID on the existing direct path.
        assign w_rp_aw_map_ready = '1;
        assign w_rp_ar_map_ready = '1;
        assign w_rp_aw_nid = '0;
        assign w_rp_ar_nid = '0;
        assign w_rp_bid = '0;
        assign w_rp_rid = '0;
    end
endgenerate

generate
    if ((RP_COUNT == 2) | (RP_COUNT == 3)) begin : g_rp2_rp3
        localparam RP_IDX_WD = $clog2(RP_COUNT);
        localparam integer MUX_ID_WD = REMAP_ID_WD + RP_IDX_WD;

        logic w_cfg_valid;
        wire w_merge_en;
        logic [RP_COUNT-1:0][RP_IDX_WD-1:0] w_src_dest;
        logic [RP_COUNT-1:0] w_merge_mask;
        logic [RP_IDX_WD-1:0] w_merge_dest;
        logic [RP_COUNT-1:0] w_direct_valid;
        logic [RP_COUNT-1:0][RP_IDX_WD-1:0] w_direct_src;

        assign w_merge_en = |w_merge_mask;

        always_comb begin
            // Validate full 2-bit destinations before indexing an MI array.
            w_cfg_valid = 1'b1;
            for (int src = 0; src < RP_COUNT; src = src + 1) begin
                if (I_ASYMMETRIC_RP_EN && (I_TX_RP_SEL[src] >= 2'(RP_COUNT)))
                    w_cfg_valid = 1'b0;
            end

            // EN=0 always uses identity routes, irrespective of DEST settings.
            w_src_dest = '0;
            for (int src = 0; src < RP_COUNT; src = src + 1) begin
                if (!I_ASYMMETRIC_RP_EN)
                    w_src_dest[src] = RP_IDX_WD'(src);
                else if (w_cfg_valid)
                    w_src_dest[src] = RP_IDX_WD'(I_TX_RP_SEL[src]);
            end

            // A source joins the mux if another source has the same DEST.
            // For RP_COUNT=2/3 all marked sources necessarily share one DEST.
            w_merge_mask = '0;
            w_merge_dest = '0;
            for (int src = 0; src < RP_COUNT; src = src + 1) begin
                for (int peer = 0; peer < RP_COUNT; peer = peer + 1) begin
                    if (I_ASYMMETRIC_RP_EN && w_cfg_valid && (src != peer) && (w_src_dest[src] == w_src_dest[peer])) begin
                        w_merge_mask[src] = 1'b1;
                        w_merge_dest = w_src_dest[src];
                    end
                end
            end

            // Singleton routes use an inverse destination-to-source map.
            w_direct_valid = '0;
            w_direct_src = '0;
            for (int dst = 0; dst < RP_COUNT; dst = dst + 1) begin
                for (int src = 0; src < RP_COUNT; src = src + 1) begin
                    if (w_cfg_valid && !w_merge_mask[src] && (w_src_dest[src] == RP_IDX_WD'(dst))) begin
                        w_direct_valid[dst] = 1'b1;
                        w_direct_src[dst] = RP_IDX_WD'(src);
                    end
                end
            end
        end

        // Keep each source at its original mux input index, including partial groups.
        // The low $clog2(RP_COUNT) ID bits identify the original source RP.

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0] w_mux_s_awid;
        wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0] w_mux_s_awaddr;
        wire [RP_COUNT-1:0][AXI_LEN_WD-1:0] w_mux_s_awlen;
        wire [RP_COUNT-1:0][2:0] w_mux_s_awsize;
        wire [RP_COUNT-1:0][1:0] w_mux_s_awburst;
        wire [RP_COUNT-1:0] w_mux_s_awlock;
        wire [RP_COUNT-1:0][3:0] w_mux_s_awcache;
        wire [RP_COUNT-1:0][2:0] w_mux_s_awprot;
        wire [RP_COUNT-1:0][3:0] w_mux_s_awqos;
        wire [RP_COUNT-1:0] w_mux_s_awvalid;
        wire [RP_COUNT-1:0] w_mux_s_awready;
        wire [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] w_mux_s_wdata;
        wire [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0] w_mux_s_wstrb;
        wire [RP_COUNT-1:0] w_mux_s_wlast;
        wire [RP_COUNT-1:0][1:0] w_mux_s_wdlen;
        wire [RP_COUNT-1:0] w_mux_s_wvalid;
        wire [RP_COUNT-1:0] w_mux_s_wready;
        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0] w_mux_s_arid;
        wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0] w_mux_s_araddr;
        wire [RP_COUNT-1:0][AXI_LEN_WD-1:0] w_mux_s_arlen;
        wire [RP_COUNT-1:0][2:0] w_mux_s_arsize;
        wire [RP_COUNT-1:0][1:0] w_mux_s_arburst;
        wire [RP_COUNT-1:0] w_mux_s_arlock;
        wire [RP_COUNT-1:0][3:0] w_mux_s_arcache;
        wire [RP_COUNT-1:0][2:0] w_mux_s_arprot;
        wire [RP_COUNT-1:0][3:0] w_mux_s_arqos;
        wire [RP_COUNT-1:0] w_mux_s_arvalid;
        wire [RP_COUNT-1:0] w_mux_s_arready;
        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0] w_mux_s_bid;
        wire [RP_COUNT-1:0][1:0] w_mux_s_bresp;
        wire [RP_COUNT-1:0] w_mux_s_bvalid;
        wire [RP_COUNT-1:0] w_mux_s_bready;
        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0] w_mux_s_rid;
        wire [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0] w_mux_s_rdata;
        wire [RP_COUNT-1:0][1:0] w_mux_s_rresp;
        wire [RP_COUNT-1:0] w_mux_s_rlast;
        wire [RP_COUNT-1:0] w_mux_s_rvalid;
        wire [RP_COUNT-1:0] w_mux_s_rready;

        wire [MUX_ID_WD-1:0] w_mux_awid;
        wire [AXI_ADDR_WD-1:0] w_mux_awaddr;
        wire [AXI_LEN_WD-1:0] w_mux_awlen;
        wire [2:0] w_mux_awsize;
        wire [1:0] w_mux_awburst;
        wire  w_mux_awlock;
        wire [3:0] w_mux_awcache;
        wire [2:0] w_mux_awprot;
        wire [3:0] w_mux_awqos;
        wire  w_mux_awvalid;
        wire  w_mux_awready;
        wire [RP_AXI_DATA_WD_MAX-1:0] w_mux_wdata;
        wire [RP_AXI_STRB_WD_MAX-1:0] w_mux_wstrb;
        wire  w_mux_wlast;
        wire [1:0] w_mux_wdlen;
        wire  w_mux_wvalid;
        wire  w_mux_wready;
        wire [MUX_ID_WD-1:0] w_mux_arid;
        wire [AXI_ADDR_WD-1:0] w_mux_araddr;
        wire [AXI_LEN_WD-1:0] w_mux_arlen;
        wire [2:0] w_mux_arsize;
        wire [1:0] w_mux_arburst;
        wire  w_mux_arlock;
        wire [3:0] w_mux_arcache;
        wire [2:0] w_mux_arprot;
        wire [3:0] w_mux_arqos;
        wire  w_mux_arvalid;
        wire  w_mux_arready;
        wire [MUX_ID_WD-1:0] w_mux_bid;
        wire  w_mux_bready;
        wire [MUX_ID_WD-1:0] w_mux_rid;
        wire  w_mux_rready;

        wire [AXI_ID_WD-1:0] w_tagged_awid;
        wire [AXI_ID_WD-1:0] w_tagged_arid;


        assign w_mux_awready = w_merge_en & w_pre_rs_awready[w_merge_dest];
        assign w_mux_arready = w_merge_en & w_pre_rs_arready[w_merge_dest];
        assign w_mux_wready  = w_merge_en & w_pre_rs_wready[w_merge_dest];

        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_mux_input

            assign w_mux_s_awid[src]       = w_rp_aw_nid[src];
            assign w_mux_s_awaddr[src]     = I_AOU_AXI_S_AWADDR[src];
            assign w_mux_s_awlen[src]      = I_AOU_AXI_S_AWLEN[src];
            assign w_mux_s_awsize[src]     = I_AOU_AXI_S_AWSIZE[src];
            assign w_mux_s_awburst[src]    = I_AOU_AXI_S_AWBURST[src];
            assign w_mux_s_awlock[src]     = I_AOU_AXI_S_AWLOCK[src];
            assign w_mux_s_awcache[src]    = I_AOU_AXI_S_AWCACHE[src];
            assign w_mux_s_awprot[src]     = I_AOU_AXI_S_AWPROT[src];
            assign w_mux_s_awqos[src]      = I_AOU_AXI_S_AWQOS[src];
            assign w_mux_s_awvalid[src]    = I_AOU_AXI_S_AWVALID[src] & w_merge_mask[src] & w_rp_aw_map_ready[src];
            assign w_mux_s_wdata[src]      = I_AOU_AXI_S_WDATA[src];
            assign w_mux_s_wstrb[src]      = I_AOU_AXI_S_WSTRB[src];
            assign w_mux_s_wlast[src]      = I_AOU_AXI_S_WLAST[src];
            assign w_mux_s_wdlen[src]      = I_AOU_AXI_S_WDLEN[src];
            assign w_mux_s_wvalid[src]     = I_AOU_AXI_S_WVALID[src] & w_merge_mask[src];
            assign w_mux_s_arid[src]       = w_rp_ar_nid[src];
            assign w_mux_s_araddr[src]     = I_AOU_AXI_S_ARADDR[src];
            assign w_mux_s_arlen[src]      = I_AOU_AXI_S_ARLEN[src];
            assign w_mux_s_arsize[src]     = I_AOU_AXI_S_ARSIZE[src];
            assign w_mux_s_arburst[src]    = I_AOU_AXI_S_ARBURST[src];
            assign w_mux_s_arlock[src]     = I_AOU_AXI_S_ARLOCK[src];
            assign w_mux_s_arcache[src]    = I_AOU_AXI_S_ARCACHE[src];
            assign w_mux_s_arprot[src]     = I_AOU_AXI_S_ARPROT[src];
            assign w_mux_s_arqos[src]      = I_AOU_AXI_S_ARQOS[src];
            assign w_mux_s_arvalid[src]    = I_AOU_AXI_S_ARVALID[src] & w_merge_mask[src] & w_rp_ar_map_ready[src];
            assign w_mux_s_bready[src]     = I_AOU_AXI_S_BREADY[src] & w_merge_mask[src];
            assign w_mux_s_rready[src]     = I_AOU_AXI_S_RREADY[src] & w_merge_mask[src];
        end

        // A merged source returns through the mux. A singleton source uses its
        // own destination's READY/B/R directly, preserving its original ID.
        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_si_route
            assign O_AOU_AXI_S_AWREADY[src]  = !w_cfg_valid ? '0 : w_merge_mask[src] ? (w_mux_s_awready[src] & w_rp_aw_map_ready[src]) : w_pre_rs_awready[w_src_dest[src]];
            assign O_AOU_AXI_S_WREADY[src]   = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_wready[src]  : w_pre_rs_wready[w_src_dest[src]];
            assign O_AOU_AXI_S_ARREADY[src]  = !w_cfg_valid ? '0 : w_merge_mask[src] ? (w_mux_s_arready[src] & w_rp_ar_map_ready[src]) : w_pre_rs_arready[w_src_dest[src]];
            assign O_AOU_AXI_S_BID[src]      = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_rp_bid[src]     : I_AOU_AXI_M_BID[w_src_dest[src]];
            assign O_AOU_AXI_S_BRESP[src]    = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_bresp[src]   : I_AOU_AXI_M_BRESP[w_src_dest[src]];
            assign O_AOU_AXI_S_BVALID[src]   = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_bvalid[src]  : I_AOU_AXI_M_BVALID[w_src_dest[src]];
            assign O_AOU_AXI_S_RID[src]      = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_rp_rid[src]     : I_AOU_AXI_M_RID[w_src_dest[src]];
            assign O_AOU_AXI_S_RDATA[src]    = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_rdata[src]   : I_AOU_AXI_M_RDATA[w_src_dest[src]];
            assign O_AOU_AXI_S_RRESP[src]    = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_rresp[src]   : I_AOU_AXI_M_RRESP[w_src_dest[src]];
            assign O_AOU_AXI_S_RLAST[src]    = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_rlast[src]   : I_AOU_AXI_M_RLAST[w_src_dest[src]];
            assign O_AOU_AXI_S_RVALID[src]   = !w_cfg_valid ? '0 : w_merge_mask[src] ? w_mux_s_rvalid[src]  : I_AOU_AXI_M_RVALID[w_src_dest[src]];
        end

        // Each MI is either the merge destination, one singleton route, or idle.
        for (genvar dst = 0; dst < RP_COUNT; dst = dst + 1) begin : g_mi_route
            wire w_this_merge;
            assign w_this_merge             = w_merge_en && (w_merge_dest == RP_IDX_WD'(dst));
            assign w_pre_rs_awid[dst]       = w_this_merge ? w_tagged_awid                      : w_direct_valid[dst] ? I_AOU_AXI_S_AWID[w_direct_src[dst]]     : '0;
            assign w_pre_rs_awaddr[dst]     = w_this_merge ? w_mux_awaddr                    : w_direct_valid[dst] ? I_AOU_AXI_S_AWADDR[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awlen[dst]      = w_this_merge ? w_mux_awlen                     : w_direct_valid[dst] ? I_AOU_AXI_S_AWLEN[w_direct_src[dst]]    : '0;
            assign w_pre_rs_awsize[dst]     = w_this_merge ? w_mux_awsize                    : w_direct_valid[dst] ? I_AOU_AXI_S_AWSIZE[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awburst[dst]    = w_this_merge ? w_mux_awburst                   : w_direct_valid[dst] ? I_AOU_AXI_S_AWBURST[w_direct_src[dst]]  : '0;
            assign w_pre_rs_awlock[dst]     = w_this_merge ? w_mux_awlock                    : w_direct_valid[dst] ? I_AOU_AXI_S_AWLOCK[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awcache[dst]    = w_this_merge ? w_mux_awcache                   : w_direct_valid[dst] ? I_AOU_AXI_S_AWCACHE[w_direct_src[dst]]  : '0;
            assign w_pre_rs_awprot[dst]     = w_this_merge ? w_mux_awprot                    : w_direct_valid[dst] ? I_AOU_AXI_S_AWPROT[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awqos[dst]      = w_this_merge ? w_mux_awqos                     : w_direct_valid[dst] ? I_AOU_AXI_S_AWQOS[w_direct_src[dst]]    : '0;
            assign w_pre_rs_awvalid[dst]    = w_this_merge ? w_mux_awvalid: w_direct_valid[dst] ? I_AOU_AXI_S_AWVALID[w_direct_src[dst]]  : '0;
            assign w_pre_rs_wdata[dst]      = w_this_merge ? w_mux_wdata                     : w_direct_valid[dst] ? I_AOU_AXI_S_WDATA[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wstrb[dst]      = w_this_merge ? w_mux_wstrb                     : w_direct_valid[dst] ? I_AOU_AXI_S_WSTRB[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wlast[dst]      = w_this_merge ? w_mux_wlast                     : w_direct_valid[dst] ? I_AOU_AXI_S_WLAST[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wdlen[dst]      = w_this_merge ? w_mux_wdlen                     : w_direct_valid[dst] ? I_AOU_AXI_S_WDLEN[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wvalid[dst]     = w_this_merge ? w_mux_wvalid                    : w_direct_valid[dst] ? I_AOU_AXI_S_WVALID[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arid[dst]       = w_this_merge ? w_tagged_arid                      : w_direct_valid[dst] ? I_AOU_AXI_S_ARID[w_direct_src[dst]]     : '0;
            assign w_pre_rs_araddr[dst]     = w_this_merge ? w_mux_araddr                    : w_direct_valid[dst] ? I_AOU_AXI_S_ARADDR[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arlen[dst]      = w_this_merge ? w_mux_arlen                     : w_direct_valid[dst] ? I_AOU_AXI_S_ARLEN[w_direct_src[dst]]    : '0;
            assign w_pre_rs_arsize[dst]     = w_this_merge ? w_mux_arsize                    : w_direct_valid[dst] ? I_AOU_AXI_S_ARSIZE[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arburst[dst]    = w_this_merge ? w_mux_arburst                   : w_direct_valid[dst] ? I_AOU_AXI_S_ARBURST[w_direct_src[dst]]  : '0;
            assign w_pre_rs_arlock[dst]     = w_this_merge ? w_mux_arlock                    : w_direct_valid[dst] ? I_AOU_AXI_S_ARLOCK[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arcache[dst]    = w_this_merge ? w_mux_arcache                   : w_direct_valid[dst] ? I_AOU_AXI_S_ARCACHE[w_direct_src[dst]]  : '0;
            assign w_pre_rs_arprot[dst]     = w_this_merge ? w_mux_arprot                    : w_direct_valid[dst] ? I_AOU_AXI_S_ARPROT[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arqos[dst]      = w_this_merge ? w_mux_arqos                     : w_direct_valid[dst] ? I_AOU_AXI_S_ARQOS[w_direct_src[dst]]    : '0;
            assign w_pre_rs_arvalid[dst]    = w_this_merge ? w_mux_arvalid: w_direct_valid[dst] ? I_AOU_AXI_S_ARVALID[w_direct_src[dst]]  : '0;
            assign O_AOU_AXI_M_BREADY[dst]  = w_this_merge ? w_mux_bready                    : w_direct_valid[dst] ? I_AOU_AXI_S_BREADY[w_direct_src[dst]]   : '0;
            assign O_AOU_AXI_M_RREADY[dst]  = w_this_merge ? w_mux_rready                    : w_direct_valid[dst] ? I_AOU_AXI_S_RREADY[w_direct_src[dst]]   : '0;
        end

        AOU_AXIMUX_NX1 #(
            .AXI_SLV_NUM  (RP_COUNT),
            .AXI_DATA_WD  (RP_AXI_DATA_WD_MAX),
            .AXI_PEER_DIE_MAX_DATA_WD (AXI_PEER_DIE_MAX_DATA_WD),
            .AXI_ADDR_WD  (AXI_ADDR_WD),
            .AXI_ID_WD    (REMAP_ID_WD),
            .AXI_QOS_WD   (4),
            .AXI_STRB_WD  (RP_AXI_STRB_WD_MAX),
            .AXI_LEN_WD   (AXI_LEN_WD)
        ) u_aou_asymmetric_rp_nx1_mux (
            .I_ARB_MODE (I_PRIOR_RP_AXI_ARB_MODE),
            .I_AW_PRIORITY (w_source_aw_priority),
            .I_AR_PRIORITY (w_source_ar_priority),
            .I_CLK        (I_CLK),
            .I_RESETN     (I_RESETN),
            .I_S_AWID      (w_mux_s_awid),
            .I_S_AWADDR    (w_mux_s_awaddr),
            .I_S_AWLEN     (w_mux_s_awlen),
            .I_S_AWSIZE    (w_mux_s_awsize),
            .I_S_AWBURST   (w_mux_s_awburst),
            .I_S_AWLOCK    (w_mux_s_awlock),
            .I_S_AWCACHE   (w_mux_s_awcache),
            .I_S_AWPROT    (w_mux_s_awprot),
            .I_S_AWQOS     (w_mux_s_awqos),
            .I_S_AWVALID   (w_mux_s_awvalid),
            .O_S_AWREADY   (w_mux_s_awready),
            .I_S_WDATA     (w_mux_s_wdata),
            .I_S_WSTRB     (w_mux_s_wstrb),
            .I_S_WLAST     (w_mux_s_wlast),
            .I_S_WDLEN     (w_mux_s_wdlen),
            .I_S_WVALID    (w_mux_s_wvalid),
            .O_S_WREADY    (w_mux_s_wready),
            .I_S_ARID      (w_mux_s_arid),
            .I_S_ARADDR    (w_mux_s_araddr),
            .I_S_ARLEN     (w_mux_s_arlen),
            .I_S_ARSIZE    (w_mux_s_arsize),
            .I_S_ARBURST   (w_mux_s_arburst),
            .I_S_ARLOCK    (w_mux_s_arlock),
            .I_S_ARCACHE   (w_mux_s_arcache),
            .I_S_ARPROT    (w_mux_s_arprot),
            .I_S_ARQOS     (w_mux_s_arqos),
            .I_S_ARVALID   (w_mux_s_arvalid),
            .O_S_ARREADY   (w_mux_s_arready),
            .O_S_BID       (w_mux_s_bid),
            .O_S_BRESP     (w_mux_s_bresp),
            .O_S_BVALID    (w_mux_s_bvalid),
            .I_S_BREADY    (w_mux_s_bready),
            .O_S_RID       (w_mux_s_rid),
            .O_S_RDATA     (w_mux_s_rdata),
            .O_S_RRESP     (w_mux_s_rresp),
            .O_S_RLAST     (w_mux_s_rlast),
            .O_S_RVALID    (w_mux_s_rvalid),
            .I_S_RREADY    (w_mux_s_rready),
            .O_M_AWID      (w_mux_awid),
            .O_M_AWADDR    (w_mux_awaddr),
            .O_M_AWLEN     (w_mux_awlen),
            .O_M_AWSIZE    (w_mux_awsize),
            .O_M_AWBURST   (w_mux_awburst),
            .O_M_AWLOCK    (w_mux_awlock),
            .O_M_AWCACHE   (w_mux_awcache),
            .O_M_AWPROT    (w_mux_awprot),
            .O_M_AWQOS     (w_mux_awqos),
            .O_M_AWVALID   (w_mux_awvalid),
            .I_M_AWREADY   (w_mux_awready),
            .O_M_WDATA     (w_mux_wdata),
            .O_M_WSTRB     (w_mux_wstrb),
            .O_M_WLAST     (w_mux_wlast),
            .O_M_WDLEN     (w_mux_wdlen),
            .O_M_WVALID    (w_mux_wvalid),
            .I_M_WREADY    (w_mux_wready),
            .O_M_ARID      (w_mux_arid),
            .O_M_ARADDR    (w_mux_araddr),
            .O_M_ARLEN     (w_mux_arlen),
            .O_M_ARSIZE    (w_mux_arsize),
            .O_M_ARBURST   (w_mux_arburst),
            .O_M_ARLOCK    (w_mux_arlock),
            .O_M_ARCACHE   (w_mux_arcache),
            .O_M_ARPROT    (w_mux_arprot),
            .O_M_ARQOS     (w_mux_arqos),
            .O_M_ARVALID   (w_mux_arvalid),
            .I_M_ARREADY   (w_mux_arready),
            .I_M_BID       (w_mux_bid),
            .I_M_BRESP     (I_AOU_AXI_M_BRESP[w_merge_dest]),
            .I_M_BVALID    (I_AOU_AXI_M_BVALID[w_merge_dest] & w_merge_en),
            .O_M_BREADY    (w_mux_bready),
            .I_M_RID       (w_mux_rid),
            .I_M_RDATA     (I_AOU_AXI_M_RDATA[w_merge_dest]),
            .I_M_RRESP     (I_AOU_AXI_M_RRESP[w_merge_dest]),
            .I_M_RLAST     (I_AOU_AXI_M_RLAST[w_merge_dest]),
            .I_M_RVALID    (I_AOU_AXI_M_RVALID[w_merge_dest] & w_merge_en),
            .O_M_RREADY    (w_mux_rready)
        );

        // MUX output already contains {REMAP_ID_WD-bit NID, source tag}.
        assign w_tagged_awid = AXI_ID_WD'(w_mux_awid);
        assign w_tagged_arid = AXI_ID_WD'(w_mux_arid);
        assign w_mux_bid = I_AOU_AXI_M_BID[w_merge_dest][MUX_ID_WD-1:0];
        assign w_mux_rid = I_AOU_AXI_M_RID[w_merge_dest][MUX_ID_WD-1:0];
        assign w_rp_remap_en = w_merge_mask;
        assign w_rp_b_nid = w_mux_s_bid;
        assign w_rp_bvalid = w_mux_s_bvalid & w_merge_mask;
        assign w_rp_r_nid = w_mux_s_rid;
        assign w_rp_rvalid = w_mux_s_rvalid & w_merge_mask;
        assign w_rp_rlast = w_mux_s_rlast;

 
    end else if (RP_COUNT == 4) begin : g_rp4
        localparam RP_IDX_WD = $clog2(RP_COUNT);
        localparam integer MUX_ID_WD = REMAP_ID_WD + RP_IDX_WD;

        // CH1 never owns RP0: in 2+2, the group containing RP0 belongs to CH0.
        // Upstream must enforce each RP outstanding limit.

        logic                               w_ch0_merge_en;
        logic [RP_COUNT-1:0]                w_ch0_merge_mask;
        logic [RP_IDX_WD-1:0]               w_ch0_merge_dest;

        logic                               w_ch1_merge_en;
        logic [RP_COUNT-1:0]                w_ch1_merge_mask;
        logic [RP_IDX_WD-1:0]               w_ch1_merge_dest;

        logic [RP_COUNT-1:0][RP_IDX_WD-1:0] w_src_dest;
        logic [RP_COUNT-1:0]                w_direct_valid;
        logic [RP_COUNT-1:0][RP_IDX_WD-1:0] w_direct_src;

        logic w_pair_01_23, w_pair_02_13, w_pair_03_12;
        logic w_eq01, w_eq02, w_eq03, w_eq12, w_eq13, w_eq23;
        logic [RP_COUNT-1:0] w_has_peer;

        // Keep EN/DEST stable while any request or response is pending.
        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_src_dest
            assign w_src_dest[src] = I_ASYMMETRIC_RP_EN ? I_TX_RP_SEL[src] : RP_IDX_WD'(src);
        end

        assign w_eq01 = (w_src_dest[0] == w_src_dest[1]);
        assign w_eq02 = (w_src_dest[0] == w_src_dest[2]);
        assign w_eq03 = (w_src_dest[0] == w_src_dest[3]);
        assign w_eq12 = (w_src_dest[1] == w_src_dest[2]);
        assign w_eq13 = (w_src_dest[1] == w_src_dest[3]);
        assign w_eq23 = (w_src_dest[2] == w_src_dest[3]);
        assign w_has_peer[0] = I_ASYMMETRIC_RP_EN && (w_eq01 || w_eq02 || w_eq03);
        assign w_has_peer[1] = I_ASYMMETRIC_RP_EN && (w_eq01 || w_eq12 || w_eq13);
        assign w_has_peer[2] = I_ASYMMETRIC_RP_EN && (w_eq02 || w_eq12 || w_eq23);
        assign w_has_peer[3] = I_ASYMMETRIC_RP_EN && (w_eq03 || w_eq13 || w_eq23);

        // CH0 owns the duplicate group containing the lowest source index.
        assign w_ch0_merge_dest = w_has_peer[0] ? w_src_dest[0] : w_has_peer[1] ? w_src_dest[1] : w_has_peer[2] ? w_src_dest[2] : '0;
        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_merge_mask
            assign w_ch0_merge_mask[src] = w_has_peer[src] && (w_src_dest[src] == w_ch0_merge_dest);
        end

        // Decode CH1 independently of CH0; exclude the all-equal case.
        assign w_pair_01_23 = I_ASYMMETRIC_RP_EN && w_eq01 && w_eq23 && !w_eq02;
        assign w_pair_02_13 = I_ASYMMETRIC_RP_EN && w_eq02 && w_eq13 && !w_eq01;
        assign w_pair_03_12 = I_ASYMMETRIC_RP_EN && w_eq03 && w_eq12 && !w_eq01;
        assign w_ch1_merge_mask[0] = 1'b0;
        assign w_ch1_merge_mask[1] = w_pair_02_13 || w_pair_03_12;
        assign w_ch1_merge_mask[2] = w_pair_01_23 || w_pair_03_12;
        assign w_ch1_merge_mask[3] = w_pair_01_23 || w_pair_02_13;
        assign w_ch1_merge_dest = w_pair_01_23 ? w_src_dest[2] : (w_pair_02_13 || w_pair_03_12) ? w_src_dest[1] : '0;

        // Singleton routes use an inverse destination-to-source map.
        always_comb begin
            w_direct_valid = '0;
            w_direct_src = '0;
            for (int dst = 0; dst < RP_COUNT; dst = dst + 1) begin
                for (int src = 0; src < RP_COUNT; src = src + 1) begin
                    if (!w_has_peer[src] && (w_src_dest[src] == $unsigned(RP_IDX_WD'(dst)))) begin
                        w_direct_valid[dst] = 1'b1;
                        w_direct_src[dst] = RP_IDX_WD'(src);
                    end
                end
            end
        end

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0]                w_mux_s_awid;
        wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                w_mux_s_awaddr;
        wire [RP_COUNT-1:0][AXI_LEN_WD-1:0]                 w_mux_s_awlen;
        wire [RP_COUNT-1:0][2:0]                            w_mux_s_awsize;
        wire [RP_COUNT-1:0][1:0]                            w_mux_s_awburst;
        wire [RP_COUNT-1:0]                                 w_mux_s_awlock;
        wire [RP_COUNT-1:0][3:0]                            w_mux_s_awcache;
        wire [RP_COUNT-1:0][2:0]                            w_mux_s_awprot;
        wire [RP_COUNT-1:0][3:0]                            w_mux_s_awqos;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_awvalid;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_awready;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_awvalid;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_awready;

        wire [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]         w_mux_s_wdata;
        wire [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]         w_mux_s_wstrb;
        wire [RP_COUNT-1:0]                                 w_mux_s_wlast;
        wire [RP_COUNT-1:0][1:0]                            w_mux_s_wdlen;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_wvalid;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_wready;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_wvalid;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_wready;

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0]                w_mux_s_arid;
        wire [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                w_mux_s_araddr;
        wire [RP_COUNT-1:0][AXI_LEN_WD-1:0]                 w_mux_s_arlen;
        wire [RP_COUNT-1:0][2:0]                            w_mux_s_arsize;
        wire [RP_COUNT-1:0][1:0]                            w_mux_s_arburst;
        wire [RP_COUNT-1:0]                                 w_mux_s_arlock;
        wire [RP_COUNT-1:0][3:0]                            w_mux_s_arcache;
        wire [RP_COUNT-1:0][2:0]                            w_mux_s_arprot;
        wire [RP_COUNT-1:0][3:0]                            w_mux_s_arqos;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_arvalid;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_arready;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_arvalid;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_arready;

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0]                w_ch0_mux_s_bid;

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0]                w_ch1_mux_s_bid;
        wire [RP_COUNT-1:0][1:0]                            w_ch0_mux_s_bresp;
        wire [RP_COUNT-1:0][1:0]                            w_ch1_mux_s_bresp;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_bvalid;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_bready;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_bvalid;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_bready;

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0]                w_ch0_mux_s_rid;

        wire [RP_COUNT-1:0][REMAP_ID_WD-1:0]                w_ch1_mux_s_rid;
        wire [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]   w_ch0_mux_s_rdata;
        wire [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]   w_ch1_mux_s_rdata;
        wire [RP_COUNT-1:0][1:0]                            w_ch0_mux_s_rresp;
        wire [RP_COUNT-1:0][1:0]                            w_ch1_mux_s_rresp;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_rlast;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_rlast;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_rvalid;
        wire [RP_COUNT-1:0]                                 w_ch0_mux_s_rready;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_rvalid;
        wire [RP_COUNT-1:0]                                 w_ch1_mux_s_rready;

        wire [MUX_ID_WD-1:0]                                w_ch0_mux_awid;
        wire [AXI_ADDR_WD-1:0]                              w_ch0_mux_awaddr;
        wire [AXI_LEN_WD-1:0]                               w_ch0_mux_awlen;
        wire [2:0]                                          w_ch0_mux_awsize;
        wire [1:0]                                          w_ch0_mux_awburst;
        wire                                                w_ch0_mux_awlock;
        wire [3:0]                                          w_ch0_mux_awcache;
        wire [2:0]                                          w_ch0_mux_awprot;
        wire [3:0]                                          w_ch0_mux_awqos;
        wire                                                w_ch0_mux_awvalid;
        wire                                                w_ch0_mux_awready;
        wire [RP_AXI_DATA_WD_MAX-1:0]                       w_ch0_mux_wdata;
        wire [RP_AXI_STRB_WD_MAX-1:0]                       w_ch0_mux_wstrb;
        wire                                                w_ch0_mux_wlast;
        wire [1:0]                                          w_ch0_mux_wdlen;
        wire                                                w_ch0_mux_wvalid;
        wire                                                w_ch0_mux_wready;
        wire [MUX_ID_WD-1:0]                                w_ch0_mux_arid;
        wire [AXI_ADDR_WD-1:0]                              w_ch0_mux_araddr;
        wire [AXI_LEN_WD-1:0]                               w_ch0_mux_arlen;
        wire [2:0]                                          w_ch0_mux_arsize;
        wire [1:0]                                          w_ch0_mux_arburst;
        wire                                                w_ch0_mux_arlock;
        wire [3:0]                                          w_ch0_mux_arcache;
        wire [2:0]                                          w_ch0_mux_arprot;
        wire [3:0]                                          w_ch0_mux_arqos;
        wire                                                w_ch0_mux_arvalid;
        wire                                                w_ch0_mux_arready;
        wire [MUX_ID_WD-1:0]                                w_ch0_mux_bid;
        wire                                                w_ch0_mux_bready;
        wire [MUX_ID_WD-1:0]                                w_ch0_mux_rid;
        wire                                                w_ch0_mux_rready;

        wire [AXI_ID_WD-1:0]                                w_ch0_tagged_awid;
        wire [AXI_ID_WD-1:0]                                w_ch0_tagged_arid;


        wire [MUX_ID_WD-1:0]                                w_ch1_mux_awid;
        wire [AXI_ADDR_WD-1:0]                              w_ch1_mux_awaddr;
        wire [AXI_LEN_WD-1:0]                               w_ch1_mux_awlen;
        wire [2:0]                                          w_ch1_mux_awsize;
        wire [1:0]                                          w_ch1_mux_awburst;
        wire                                                w_ch1_mux_awlock;
        wire [3:0]                                          w_ch1_mux_awcache;
        wire [2:0]                                          w_ch1_mux_awprot;
        wire [3:0]                                          w_ch1_mux_awqos;
        wire                                                w_ch1_mux_awvalid;
        wire                                                w_ch1_mux_awready;
        wire [RP_AXI_DATA_WD_MAX-1:0]                       w_ch1_mux_wdata;
        wire [RP_AXI_STRB_WD_MAX-1:0]                       w_ch1_mux_wstrb;
        wire                                                w_ch1_mux_wlast;
        wire [1:0]                                          w_ch1_mux_wdlen;
        wire                                                w_ch1_mux_wvalid;
        wire                                                w_ch1_mux_wready;
        wire [MUX_ID_WD-1:0]                                w_ch1_mux_arid;
        wire [AXI_ADDR_WD-1:0]                              w_ch1_mux_araddr;
        wire [AXI_LEN_WD-1:0]                               w_ch1_mux_arlen;
        wire [2:0]                                          w_ch1_mux_arsize;
        wire [1:0]                                          w_ch1_mux_arburst;
        wire                                                w_ch1_mux_arlock;
        wire [3:0]                                          w_ch1_mux_arcache;
        wire [2:0]                                          w_ch1_mux_arprot;
        wire [3:0]                                          w_ch1_mux_arqos;
        wire                                                w_ch1_mux_arvalid;
        wire                                                w_ch1_mux_arready;
        wire [MUX_ID_WD-1:0]                                w_ch1_mux_bid;
        wire                                                w_ch1_mux_bready;
        wire [MUX_ID_WD-1:0]                                w_ch1_mux_rid;
        wire                                                w_ch1_mux_rready;

        wire [AXI_ID_WD-1:0]                                w_ch1_tagged_awid;
        wire [AXI_ID_WD-1:0]                                w_ch1_tagged_arid;


        assign w_ch0_merge_en = |w_ch0_merge_mask;
        assign w_ch1_merge_en = w_pair_01_23 || w_pair_02_13 || w_pair_03_12;

        assign w_ch0_mux_awready = w_ch0_merge_en & w_pre_rs_awready[w_ch0_merge_dest];
        assign w_ch0_mux_arready = w_ch0_merge_en & w_pre_rs_arready[w_ch0_merge_dest];
        assign w_ch0_mux_wready  = w_ch0_merge_en & w_pre_rs_wready[w_ch0_merge_dest];

        assign w_ch1_mux_awready = w_ch1_merge_en & w_pre_rs_awready[w_ch1_merge_dest];
        assign w_ch1_mux_arready = w_ch1_merge_en & w_pre_rs_arready[w_ch1_merge_dest];
        assign w_ch1_mux_wready  = w_ch1_merge_en & w_pre_rs_wready[w_ch1_merge_dest];

        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_ch0_mux_input

            assign w_mux_s_awid[src]       = w_rp_aw_nid[src];
            assign w_mux_s_awaddr[src]     = I_AOU_AXI_S_AWADDR[src];
            assign w_mux_s_awlen[src]      = I_AOU_AXI_S_AWLEN[src];
            assign w_mux_s_awsize[src]     = I_AOU_AXI_S_AWSIZE[src];
            assign w_mux_s_awburst[src]    = I_AOU_AXI_S_AWBURST[src];
            assign w_mux_s_awlock[src]     = I_AOU_AXI_S_AWLOCK[src];
            assign w_mux_s_awcache[src]    = I_AOU_AXI_S_AWCACHE[src];
            assign w_mux_s_awprot[src]     = I_AOU_AXI_S_AWPROT[src];
            assign w_mux_s_awqos[src]      = I_AOU_AXI_S_AWQOS[src];
            assign w_ch0_mux_s_awvalid[src]= I_AOU_AXI_S_AWVALID[src] & w_ch0_merge_mask[src] & w_rp_aw_map_ready[src];
            assign w_mux_s_wdata[src]      = I_AOU_AXI_S_WDATA[src];
            assign w_mux_s_wstrb[src]      = I_AOU_AXI_S_WSTRB[src];
            assign w_mux_s_wlast[src]      = I_AOU_AXI_S_WLAST[src];
            assign w_mux_s_wdlen[src]      = I_AOU_AXI_S_WDLEN[src];
            assign w_ch0_mux_s_wvalid[src] = I_AOU_AXI_S_WVALID[src] & w_ch0_merge_mask[src];
            assign w_mux_s_arid[src]       = w_rp_ar_nid[src];
            assign w_mux_s_araddr[src]     = I_AOU_AXI_S_ARADDR[src];
            assign w_mux_s_arlen[src]      = I_AOU_AXI_S_ARLEN[src];
            assign w_mux_s_arsize[src]     = I_AOU_AXI_S_ARSIZE[src];
            assign w_mux_s_arburst[src]    = I_AOU_AXI_S_ARBURST[src];
            assign w_mux_s_arlock[src]     = I_AOU_AXI_S_ARLOCK[src];
            assign w_mux_s_arcache[src]    = I_AOU_AXI_S_ARCACHE[src];
            assign w_mux_s_arprot[src]     = I_AOU_AXI_S_ARPROT[src];
            assign w_mux_s_arqos[src]      = I_AOU_AXI_S_ARQOS[src];
            assign w_ch0_mux_s_arvalid[src]= I_AOU_AXI_S_ARVALID[src] & w_ch0_merge_mask[src] & w_rp_ar_map_ready[src];
            assign w_ch0_mux_s_bready[src] = I_AOU_AXI_S_BREADY[src] & w_ch0_merge_mask[src];
            assign w_ch0_mux_s_rready[src] = I_AOU_AXI_S_RREADY[src] & w_ch0_merge_mask[src];
        end
        AOU_AXIMUX_NX1 #(
            .AXI_SLV_NUM  (RP_COUNT),
            .AXI_DATA_WD  (RP_AXI_DATA_WD_MAX),
            .AXI_PEER_DIE_MAX_DATA_WD (AXI_PEER_DIE_MAX_DATA_WD),
            .AXI_ADDR_WD  (AXI_ADDR_WD),
            .AXI_ID_WD    (REMAP_ID_WD),
            .AXI_QOS_WD   (4),
            .AXI_STRB_WD  (RP_AXI_STRB_WD_MAX),
            .AXI_LEN_WD   (AXI_LEN_WD)
        ) u_ch0_aou_asymmetric_rp_nx1_mux (
            .I_ARB_MODE (I_PRIOR_RP_AXI_ARB_MODE),
            .I_AW_PRIORITY (w_source_aw_priority),
            .I_AR_PRIORITY (w_source_ar_priority),
            .I_CLK        (I_CLK),
            .I_RESETN     (I_RESETN),
            .I_S_AWID      (w_mux_s_awid),
            .I_S_AWADDR    (w_mux_s_awaddr),
            .I_S_AWLEN     (w_mux_s_awlen),
            .I_S_AWSIZE    (w_mux_s_awsize),
            .I_S_AWBURST   (w_mux_s_awburst),
            .I_S_AWLOCK    (w_mux_s_awlock),
            .I_S_AWCACHE   (w_mux_s_awcache),
            .I_S_AWPROT    (w_mux_s_awprot),
            .I_S_AWQOS     (w_mux_s_awqos),
            .I_S_AWVALID   (w_ch0_mux_s_awvalid),
            .O_S_AWREADY   (w_ch0_mux_s_awready),
            .I_S_WDATA     (w_mux_s_wdata),
            .I_S_WSTRB     (w_mux_s_wstrb),
            .I_S_WLAST     (w_mux_s_wlast),
            .I_S_WDLEN     (w_mux_s_wdlen),
            .I_S_WVALID    (w_ch0_mux_s_wvalid),
            .O_S_WREADY    (w_ch0_mux_s_wready),
            .I_S_ARID      (w_mux_s_arid),
            .I_S_ARADDR    (w_mux_s_araddr),
            .I_S_ARLEN     (w_mux_s_arlen),
            .I_S_ARSIZE    (w_mux_s_arsize),
            .I_S_ARBURST   (w_mux_s_arburst),
            .I_S_ARLOCK    (w_mux_s_arlock),
            .I_S_ARCACHE   (w_mux_s_arcache),
            .I_S_ARPROT    (w_mux_s_arprot),
            .I_S_ARQOS     (w_mux_s_arqos),
            .I_S_ARVALID   (w_ch0_mux_s_arvalid),
            .O_S_ARREADY   (w_ch0_mux_s_arready),
            .O_S_BID       (w_ch0_mux_s_bid),
            .O_S_BRESP     (w_ch0_mux_s_bresp),
            .O_S_BVALID    (w_ch0_mux_s_bvalid),
            .I_S_BREADY    (w_ch0_mux_s_bready),
            .O_S_RID       (w_ch0_mux_s_rid),
            .O_S_RDATA     (w_ch0_mux_s_rdata),
            .O_S_RRESP     (w_ch0_mux_s_rresp),
            .O_S_RLAST     (w_ch0_mux_s_rlast),
            .O_S_RVALID    (w_ch0_mux_s_rvalid),
            .I_S_RREADY    (w_ch0_mux_s_rready),
            .O_M_AWID      (w_ch0_mux_awid),
            .O_M_AWADDR    (w_ch0_mux_awaddr),
            .O_M_AWLEN     (w_ch0_mux_awlen),
            .O_M_AWSIZE    (w_ch0_mux_awsize),
            .O_M_AWBURST   (w_ch0_mux_awburst),
            .O_M_AWLOCK    (w_ch0_mux_awlock),
            .O_M_AWCACHE   (w_ch0_mux_awcache),
            .O_M_AWPROT    (w_ch0_mux_awprot),
            .O_M_AWQOS     (w_ch0_mux_awqos),
            .O_M_AWVALID   (w_ch0_mux_awvalid),
            .I_M_AWREADY   (w_ch0_mux_awready),
            .O_M_WDATA     (w_ch0_mux_wdata),
            .O_M_WSTRB     (w_ch0_mux_wstrb),
            .O_M_WLAST     (w_ch0_mux_wlast),
            .O_M_WDLEN     (w_ch0_mux_wdlen),
            .O_M_WVALID    (w_ch0_mux_wvalid),
            .I_M_WREADY    (w_ch0_mux_wready),
            .O_M_ARID      (w_ch0_mux_arid),
            .O_M_ARADDR    (w_ch0_mux_araddr),
            .O_M_ARLEN     (w_ch0_mux_arlen),
            .O_M_ARSIZE    (w_ch0_mux_arsize),
            .O_M_ARBURST   (w_ch0_mux_arburst),
            .O_M_ARLOCK    (w_ch0_mux_arlock),
            .O_M_ARCACHE   (w_ch0_mux_arcache),
            .O_M_ARPROT    (w_ch0_mux_arprot),
            .O_M_ARQOS     (w_ch0_mux_arqos),
            .O_M_ARVALID   (w_ch0_mux_arvalid),
            .I_M_ARREADY   (w_ch0_mux_arready),
            .I_M_BID       (w_ch0_mux_bid),
            .I_M_BRESP     (I_AOU_AXI_M_BRESP[w_ch0_merge_dest]),
            .I_M_BVALID    (I_AOU_AXI_M_BVALID[w_ch0_merge_dest] & w_ch0_merge_en),
            .O_M_BREADY    (w_ch0_mux_bready),
            .I_M_RID       (w_ch0_mux_rid),
            .I_M_RDATA     (I_AOU_AXI_M_RDATA[w_ch0_merge_dest]),
            .I_M_RRESP     (I_AOU_AXI_M_RRESP[w_ch0_merge_dest]),
            .I_M_RLAST     (I_AOU_AXI_M_RLAST[w_ch0_merge_dest]),
            .I_M_RVALID    (I_AOU_AXI_M_RVALID[w_ch0_merge_dest] & w_ch0_merge_en),
            .O_M_RREADY    (w_ch0_mux_rready)
        );

        // MUX output already contains {REMAP_ID_WD-bit NID, source tag}.
        assign w_ch0_tagged_awid = AXI_ID_WD'(w_ch0_mux_awid);
        assign w_ch0_tagged_arid = AXI_ID_WD'(w_ch0_mux_arid);
        assign w_ch0_mux_bid = I_AOU_AXI_M_BID[w_ch0_merge_dest][MUX_ID_WD-1:0];
        assign w_ch0_mux_rid = I_AOU_AXI_M_RID[w_ch0_merge_dest][MUX_ID_WD-1:0];
        assign w_rp_remap_en = w_ch0_merge_mask | w_ch1_merge_mask;

        for (genvar rp = 0; rp < RP_COUNT; rp++) begin : g_rp_remap_response
            assign w_rp_b_nid[rp]  = w_ch0_merge_mask[rp] ? w_ch0_mux_s_bid[rp] : w_ch1_mux_s_bid[rp];
            assign w_rp_bvalid[rp] = (w_ch0_merge_mask[rp] & w_ch0_mux_s_bvalid[rp]) | (w_ch1_merge_mask[rp] & w_ch1_mux_s_bvalid[rp]);
            assign w_rp_r_nid[rp]  = w_ch0_merge_mask[rp] ? w_ch0_mux_s_rid[rp] : w_ch1_mux_s_rid[rp];
            assign w_rp_rvalid[rp] = (w_ch0_merge_mask[rp] & w_ch0_mux_s_rvalid[rp]) | (w_ch1_merge_mask[rp] & w_ch1_mux_s_rvalid[rp]);
            assign w_rp_rlast[rp]  = w_ch0_merge_mask[rp] ? w_ch0_mux_s_rlast[rp] : w_ch1_mux_s_rlast[rp];
        end

 
        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_ch1_mux_input
            assign w_ch1_mux_s_awvalid[src]    = I_AOU_AXI_S_AWVALID[src] & w_ch1_merge_mask[src] & w_rp_aw_map_ready[src];
            assign w_ch1_mux_s_wvalid[src]     = I_AOU_AXI_S_WVALID[src] & w_ch1_merge_mask[src];
            assign w_ch1_mux_s_arvalid[src]    = I_AOU_AXI_S_ARVALID[src] & w_ch1_merge_mask[src] & w_rp_ar_map_ready[src];
            assign w_ch1_mux_s_bready[src]     = I_AOU_AXI_S_BREADY[src] & w_ch1_merge_mask[src];
            assign w_ch1_mux_s_rready[src]     = I_AOU_AXI_S_RREADY[src] & w_ch1_merge_mask[src];
        end
        // Packed slice [3:1] maps local MUX ports 0/1/2 to RP1/RP2/RP3.
        // CH1 tags are translated between local MUX indices and physical RP
        // indices at the MI boundary. Both 3:1 and 4:1 use two tag bits.
        assign w_ch1_mux_s_awready[0] = '0;
        assign w_ch1_mux_s_wready[0] = '0;
        assign w_ch1_mux_s_arready[0] = '0;
        assign w_ch1_mux_s_bid[0] = '0;
        assign w_ch1_mux_s_bresp[0] = '0;
        assign w_ch1_mux_s_bvalid[0] = '0;
        assign w_ch1_mux_s_rid[0] = '0;
        assign w_ch1_mux_s_rdata[0] = '0;
        assign w_ch1_mux_s_rresp[0] = '0;
        assign w_ch1_mux_s_rlast[0] = '0;
        assign w_ch1_mux_s_rvalid[0] = '0;

        AOU_AXIMUX_NX1 #(
            .AXI_SLV_NUM  (3),
            .AXI_DATA_WD  (RP_AXI_DATA_WD_MAX),
            .AXI_PEER_DIE_MAX_DATA_WD (AXI_PEER_DIE_MAX_DATA_WD),
            .AXI_ADDR_WD  (AXI_ADDR_WD),
            .AXI_ID_WD    (REMAP_ID_WD),
            .AXI_QOS_WD   (4),
            .AXI_STRB_WD  (RP_AXI_STRB_WD_MAX),
            .AXI_LEN_WD   (AXI_LEN_WD)
        ) u_ch1_aou_asymmetric_rp_nx1_mux (
            .I_ARB_MODE (I_PRIOR_RP_AXI_ARB_MODE),
            .I_AW_PRIORITY (w_source_aw_priority[3:1]),
            .I_AR_PRIORITY (w_source_ar_priority[3:1]),
            .I_CLK        (I_CLK),
            .I_RESETN     (I_RESETN),
            .I_S_AWID      (w_mux_s_awid[3:1]),
            .I_S_AWADDR    (w_mux_s_awaddr[3:1]),
            .I_S_AWLEN     (w_mux_s_awlen[3:1]),
            .I_S_AWSIZE    (w_mux_s_awsize[3:1]),
            .I_S_AWBURST   (w_mux_s_awburst[3:1]),
            .I_S_AWLOCK    (w_mux_s_awlock[3:1]),
            .I_S_AWCACHE   (w_mux_s_awcache[3:1]),
            .I_S_AWPROT    (w_mux_s_awprot[3:1]),
            .I_S_AWQOS     (w_mux_s_awqos[3:1]),
            .I_S_AWVALID   (w_ch1_mux_s_awvalid[3:1]),
            .O_S_AWREADY   (w_ch1_mux_s_awready[3:1]),
            .I_S_WDATA     (w_mux_s_wdata[3:1]),
            .I_S_WSTRB     (w_mux_s_wstrb[3:1]),
            .I_S_WLAST     (w_mux_s_wlast[3:1]),
            .I_S_WDLEN     (w_mux_s_wdlen[3:1]),
            .I_S_WVALID    (w_ch1_mux_s_wvalid[3:1]),
            .O_S_WREADY    (w_ch1_mux_s_wready[3:1]),
            .I_S_ARID      (w_mux_s_arid[3:1]),
            .I_S_ARADDR    (w_mux_s_araddr[3:1]),
            .I_S_ARLEN     (w_mux_s_arlen[3:1]),
            .I_S_ARSIZE    (w_mux_s_arsize[3:1]),
            .I_S_ARBURST   (w_mux_s_arburst[3:1]),
            .I_S_ARLOCK    (w_mux_s_arlock[3:1]),
            .I_S_ARCACHE   (w_mux_s_arcache[3:1]),
            .I_S_ARPROT    (w_mux_s_arprot[3:1]),
            .I_S_ARQOS     (w_mux_s_arqos[3:1]),
            .I_S_ARVALID   (w_ch1_mux_s_arvalid[3:1]),
            .O_S_ARREADY   (w_ch1_mux_s_arready[3:1]),
            .O_S_BID       (w_ch1_mux_s_bid[3:1]),
            .O_S_BRESP     (w_ch1_mux_s_bresp[3:1]),
            .O_S_BVALID    (w_ch1_mux_s_bvalid[3:1]),
            .I_S_BREADY    (w_ch1_mux_s_bready[3:1]),
            .O_S_RID       (w_ch1_mux_s_rid[3:1]),
            .O_S_RDATA     (w_ch1_mux_s_rdata[3:1]),
            .O_S_RRESP     (w_ch1_mux_s_rresp[3:1]),
            .O_S_RLAST     (w_ch1_mux_s_rlast[3:1]),
            .O_S_RVALID    (w_ch1_mux_s_rvalid[3:1]),
            .I_S_RREADY    (w_ch1_mux_s_rready[3:1]),
            .O_M_AWID      (w_ch1_mux_awid),
            .O_M_AWADDR    (w_ch1_mux_awaddr),
            .O_M_AWLEN     (w_ch1_mux_awlen),
            .O_M_AWSIZE    (w_ch1_mux_awsize),
            .O_M_AWBURST   (w_ch1_mux_awburst),
            .O_M_AWLOCK    (w_ch1_mux_awlock),
            .O_M_AWCACHE   (w_ch1_mux_awcache),
            .O_M_AWPROT    (w_ch1_mux_awprot),
            .O_M_AWQOS     (w_ch1_mux_awqos),
            .O_M_AWVALID   (w_ch1_mux_awvalid),
            .I_M_AWREADY   (w_ch1_mux_awready),
            .O_M_WDATA     (w_ch1_mux_wdata),
            .O_M_WSTRB     (w_ch1_mux_wstrb),
            .O_M_WLAST     (w_ch1_mux_wlast),
            .O_M_WDLEN     (w_ch1_mux_wdlen),
            .O_M_WVALID    (w_ch1_mux_wvalid),
            .I_M_WREADY    (w_ch1_mux_wready),
            .O_M_ARID      (w_ch1_mux_arid),
            .O_M_ARADDR    (w_ch1_mux_araddr),
            .O_M_ARLEN     (w_ch1_mux_arlen),
            .O_M_ARSIZE    (w_ch1_mux_arsize),
            .O_M_ARBURST   (w_ch1_mux_arburst),
            .O_M_ARLOCK    (w_ch1_mux_arlock),
            .O_M_ARCACHE   (w_ch1_mux_arcache),
            .O_M_ARPROT    (w_ch1_mux_arprot),
            .O_M_ARQOS     (w_ch1_mux_arqos),
            .O_M_ARVALID   (w_ch1_mux_arvalid),
            .I_M_ARREADY   (w_ch1_mux_arready),
            .I_M_BID       (w_ch1_mux_bid),
            .I_M_BRESP     (I_AOU_AXI_M_BRESP[w_ch1_merge_dest]),
            .I_M_BVALID    (I_AOU_AXI_M_BVALID[w_ch1_merge_dest] & w_ch1_merge_en),
            .O_M_BREADY    (w_ch1_mux_bready),
            .I_M_RID       (w_ch1_mux_rid),
            .I_M_RDATA     (I_AOU_AXI_M_RDATA[w_ch1_merge_dest]),
            .I_M_RRESP     (I_AOU_AXI_M_RRESP[w_ch1_merge_dest]),
            .I_M_RLAST     (I_AOU_AXI_M_RLAST[w_ch1_merge_dest]),
            .I_M_RVALID    (I_AOU_AXI_M_RVALID[w_ch1_merge_dest] & w_ch1_merge_en),
            .O_M_RREADY    (w_ch1_mux_rready)
        );

        // CH1 local MUX ports 0/1/2 correspond to physical RP1/RP2/RP3.
        // Use physical RP tags on the MI ID, and translate back for the MUX.
        assign w_ch1_tagged_awid = AXI_ID_WD'({w_ch1_mux_awid[MUX_ID_WD-1:RP_IDX_WD],
            (w_ch1_mux_awid[RP_IDX_WD-1:0] + RP_IDX_WD'(1))});
        assign w_ch1_tagged_arid = AXI_ID_WD'({w_ch1_mux_arid[MUX_ID_WD-1:RP_IDX_WD],
            (w_ch1_mux_arid[RP_IDX_WD-1:0] + RP_IDX_WD'(1))});
        assign w_ch1_mux_bid = {I_AOU_AXI_M_BID[w_ch1_merge_dest][MUX_ID_WD-1:RP_IDX_WD],
            (I_AOU_AXI_M_BID[w_ch1_merge_dest][RP_IDX_WD-1:0] - RP_IDX_WD'(1))};
        assign w_ch1_mux_rid = {I_AOU_AXI_M_RID[w_ch1_merge_dest][MUX_ID_WD-1:RP_IDX_WD],
            (I_AOU_AXI_M_RID[w_ch1_merge_dest][RP_IDX_WD-1:0] - RP_IDX_WD'(1))};

 
        for (genvar src = 0; src < RP_COUNT; src = src + 1) begin : g_si_route
            assign O_AOU_AXI_S_AWREADY[src]  = w_ch0_merge_mask[src] ? (w_ch0_mux_s_awready[src] & w_rp_aw_map_ready[src]) :w_ch1_merge_mask[src] ? (w_ch1_mux_s_awready[src] & w_rp_aw_map_ready[src]) : w_pre_rs_awready[w_src_dest[src]];
            assign O_AOU_AXI_S_WREADY[src]   = w_ch0_merge_mask[src] ? w_ch0_mux_s_wready[src]  :w_ch1_merge_mask[src] ? w_ch1_mux_s_wready[src]  : w_pre_rs_wready[w_src_dest[src]];
            assign O_AOU_AXI_S_ARREADY[src]  = w_ch0_merge_mask[src] ? (w_ch0_mux_s_arready[src] & w_rp_ar_map_ready[src]) :w_ch1_merge_mask[src] ? (w_ch1_mux_s_arready[src] & w_rp_ar_map_ready[src]) : w_pre_rs_arready[w_src_dest[src]];
            assign O_AOU_AXI_S_BID[src]      = w_ch0_merge_mask[src] ? w_rp_bid[src]     :w_ch1_merge_mask[src] ? w_rp_bid[src]     : I_AOU_AXI_M_BID[w_src_dest[src]];
            assign O_AOU_AXI_S_BRESP[src]    = w_ch0_merge_mask[src] ? w_ch0_mux_s_bresp[src]   :w_ch1_merge_mask[src] ? w_ch1_mux_s_bresp[src]   : I_AOU_AXI_M_BRESP[w_src_dest[src]];
            assign O_AOU_AXI_S_BVALID[src]   = w_ch0_merge_mask[src] ? w_ch0_mux_s_bvalid[src]  :w_ch1_merge_mask[src] ? w_ch1_mux_s_bvalid[src]  : I_AOU_AXI_M_BVALID[w_src_dest[src]];
            assign O_AOU_AXI_S_RID[src]      = w_ch0_merge_mask[src] ? w_rp_rid[src]     :w_ch1_merge_mask[src] ? w_rp_rid[src]     : I_AOU_AXI_M_RID[w_src_dest[src]];
            assign O_AOU_AXI_S_RDATA[src]    = w_ch0_merge_mask[src] ? w_ch0_mux_s_rdata[src]   :w_ch1_merge_mask[src] ? w_ch1_mux_s_rdata[src]   : I_AOU_AXI_M_RDATA[w_src_dest[src]];
            assign O_AOU_AXI_S_RRESP[src]    = w_ch0_merge_mask[src] ? w_ch0_mux_s_rresp[src]   :w_ch1_merge_mask[src] ? w_ch1_mux_s_rresp[src]   : I_AOU_AXI_M_RRESP[w_src_dest[src]];
            assign O_AOU_AXI_S_RLAST[src]    = w_ch0_merge_mask[src] ? w_ch0_mux_s_rlast[src]   :w_ch1_merge_mask[src] ? w_ch1_mux_s_rlast[src]   : I_AOU_AXI_M_RLAST[w_src_dest[src]];
            assign O_AOU_AXI_S_RVALID[src]   = w_ch0_merge_mask[src] ? w_ch0_mux_s_rvalid[src]  :w_ch1_merge_mask[src] ? w_ch1_mux_s_rvalid[src]  : I_AOU_AXI_M_RVALID[w_src_dest[src]];
        end

        for (genvar dst = 0; dst < RP_COUNT; dst = dst + 1) begin : g_mi_route
            wire w_ch0_this_merge;
            wire w_ch1_this_merge;
            assign w_ch0_this_merge      = w_ch0_merge_en && (w_ch0_merge_dest == $unsigned(RP_IDX_WD'(dst)));
            assign w_ch1_this_merge      = w_ch1_merge_en && (w_ch1_merge_dest == $unsigned(RP_IDX_WD'(dst)));
            assign w_pre_rs_awid[dst]    = w_ch0_this_merge ? w_ch0_tagged_awid                       : w_ch1_this_merge ? w_ch1_tagged_awid                       : w_direct_valid[dst] ? I_AOU_AXI_S_AWID[w_direct_src[dst]]     : '0;
            assign w_pre_rs_awaddr[dst]  = w_ch0_this_merge ? w_ch0_mux_awaddr                        : w_ch1_this_merge ? w_ch1_mux_awaddr                        : w_direct_valid[dst] ? I_AOU_AXI_S_AWADDR[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awlen[dst]   = w_ch0_this_merge ? w_ch0_mux_awlen                         : w_ch1_this_merge ? w_ch1_mux_awlen                         : w_direct_valid[dst] ? I_AOU_AXI_S_AWLEN[w_direct_src[dst]]    : '0;
            assign w_pre_rs_awsize[dst]  = w_ch0_this_merge ? w_ch0_mux_awsize                        : w_ch1_this_merge ? w_ch1_mux_awsize                        : w_direct_valid[dst] ? I_AOU_AXI_S_AWSIZE[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awburst[dst] = w_ch0_this_merge ? w_ch0_mux_awburst                       : w_ch1_this_merge ? w_ch1_mux_awburst                       : w_direct_valid[dst] ? I_AOU_AXI_S_AWBURST[w_direct_src[dst]]  : '0;
            assign w_pre_rs_awlock[dst]  = w_ch0_this_merge ? w_ch0_mux_awlock                        : w_ch1_this_merge ? w_ch1_mux_awlock                        : w_direct_valid[dst] ? I_AOU_AXI_S_AWLOCK[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awcache[dst] = w_ch0_this_merge ? w_ch0_mux_awcache                       : w_ch1_this_merge ? w_ch1_mux_awcache                       : w_direct_valid[dst] ? I_AOU_AXI_S_AWCACHE[w_direct_src[dst]]  : '0;
            assign w_pre_rs_awprot[dst]  = w_ch0_this_merge ? w_ch0_mux_awprot                        : w_ch1_this_merge ? w_ch1_mux_awprot                        : w_direct_valid[dst] ? I_AOU_AXI_S_AWPROT[w_direct_src[dst]]   : '0;
            assign w_pre_rs_awqos[dst]   = w_ch0_this_merge ? w_ch0_mux_awqos                         : w_ch1_this_merge ? w_ch1_mux_awqos                         : w_direct_valid[dst] ? I_AOU_AXI_S_AWQOS[w_direct_src[dst]]    : '0;
            assign w_pre_rs_awvalid[dst] = w_ch0_this_merge ? w_ch0_mux_awvalid: w_ch1_this_merge ? w_ch1_mux_awvalid: w_direct_valid[dst] ? I_AOU_AXI_S_AWVALID[w_direct_src[dst]]  : '0;
            assign w_pre_rs_wdata[dst]   = w_ch0_this_merge ? w_ch0_mux_wdata                         : w_ch1_this_merge ? w_ch1_mux_wdata                         : w_direct_valid[dst] ? I_AOU_AXI_S_WDATA[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wstrb[dst]   = w_ch0_this_merge ? w_ch0_mux_wstrb                         : w_ch1_this_merge ? w_ch1_mux_wstrb                         : w_direct_valid[dst] ? I_AOU_AXI_S_WSTRB[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wlast[dst]   = w_ch0_this_merge ? w_ch0_mux_wlast                         : w_ch1_this_merge ? w_ch1_mux_wlast                         : w_direct_valid[dst] ? I_AOU_AXI_S_WLAST[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wdlen[dst]   = w_ch0_this_merge ? w_ch0_mux_wdlen                         : w_ch1_this_merge ? w_ch1_mux_wdlen                         : w_direct_valid[dst] ? I_AOU_AXI_S_WDLEN[w_direct_src[dst]]    : '0;
            assign w_pre_rs_wvalid[dst]  = w_ch0_this_merge ? w_ch0_mux_wvalid                        : w_ch1_this_merge ? w_ch1_mux_wvalid                        : w_direct_valid[dst] ? I_AOU_AXI_S_WVALID[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arid[dst]    = w_ch0_this_merge ? w_ch0_tagged_arid                       : w_ch1_this_merge ? w_ch1_tagged_arid                       : w_direct_valid[dst] ? I_AOU_AXI_S_ARID[w_direct_src[dst]]     : '0;
            assign w_pre_rs_araddr[dst]  = w_ch0_this_merge ? w_ch0_mux_araddr                        : w_ch1_this_merge ? w_ch1_mux_araddr                        : w_direct_valid[dst] ? I_AOU_AXI_S_ARADDR[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arlen[dst]   = w_ch0_this_merge ? w_ch0_mux_arlen                         : w_ch1_this_merge ? w_ch1_mux_arlen                         : w_direct_valid[dst] ? I_AOU_AXI_S_ARLEN[w_direct_src[dst]]    : '0;
            assign w_pre_rs_arsize[dst]  = w_ch0_this_merge ? w_ch0_mux_arsize                        : w_ch1_this_merge ? w_ch1_mux_arsize                        : w_direct_valid[dst] ? I_AOU_AXI_S_ARSIZE[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arburst[dst] = w_ch0_this_merge ? w_ch0_mux_arburst                       : w_ch1_this_merge ? w_ch1_mux_arburst                       : w_direct_valid[dst] ? I_AOU_AXI_S_ARBURST[w_direct_src[dst]]  : '0;
            assign w_pre_rs_arlock[dst]  = w_ch0_this_merge ? w_ch0_mux_arlock                        : w_ch1_this_merge ? w_ch1_mux_arlock                        : w_direct_valid[dst] ? I_AOU_AXI_S_ARLOCK[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arcache[dst] = w_ch0_this_merge ? w_ch0_mux_arcache                       : w_ch1_this_merge ? w_ch1_mux_arcache                       : w_direct_valid[dst] ? I_AOU_AXI_S_ARCACHE[w_direct_src[dst]]  : '0;
            assign w_pre_rs_arprot[dst]  = w_ch0_this_merge ? w_ch0_mux_arprot                        : w_ch1_this_merge ? w_ch1_mux_arprot                        : w_direct_valid[dst] ? I_AOU_AXI_S_ARPROT[w_direct_src[dst]]   : '0;
            assign w_pre_rs_arqos[dst]   = w_ch0_this_merge ? w_ch0_mux_arqos                         : w_ch1_this_merge ? w_ch1_mux_arqos                         : w_direct_valid[dst] ? I_AOU_AXI_S_ARQOS[w_direct_src[dst]]    : '0;
            assign w_pre_rs_arvalid[dst] = w_ch0_this_merge ? w_ch0_mux_arvalid: w_ch1_this_merge ? w_ch1_mux_arvalid: w_direct_valid[dst] ? I_AOU_AXI_S_ARVALID[w_direct_src[dst]]  : '0;
            assign O_AOU_AXI_M_BREADY[dst]  = w_ch0_this_merge ? w_ch0_mux_bready                     : w_ch1_this_merge ? w_ch1_mux_bready                        : w_direct_valid[dst] ? I_AOU_AXI_S_BREADY[w_direct_src[dst]]   : '0;
            assign O_AOU_AXI_M_RREADY[dst]  = w_ch0_this_merge ? w_ch0_mux_rready                     : w_ch1_this_merge ? w_ch1_mux_rready                        : w_direct_valid[dst] ? I_AOU_AXI_S_RREADY[w_direct_src[dst]]   : '0;
        end

    end else begin : g_rp0

            assign w_rp_remap_en = '0;
            assign w_rp_b_nid = '0;
            assign w_rp_bvalid = '0;
            assign w_rp_r_nid = '0;
            assign w_rp_rvalid = '0;
            assign w_rp_rlast = '0;

            assign w_pre_rs_awid        = I_AOU_AXI_S_AWID    ; 
            assign w_pre_rs_awaddr      = I_AOU_AXI_S_AWADDR  ; 
            assign w_pre_rs_awlen       = I_AOU_AXI_S_AWLEN   ; 
            assign w_pre_rs_awsize      = I_AOU_AXI_S_AWSIZE  ; 
            assign w_pre_rs_awburst     = I_AOU_AXI_S_AWBURST ;
            assign w_pre_rs_awlock      = I_AOU_AXI_S_AWLOCK  ; 
            assign w_pre_rs_awcache     = I_AOU_AXI_S_AWCACHE ;
            assign w_pre_rs_awprot      = I_AOU_AXI_S_AWPROT  ; 
            assign w_pre_rs_awqos       = I_AOU_AXI_S_AWQOS   ; 
            assign w_pre_rs_awvalid     = I_AOU_AXI_S_AWVALID ;
            assign O_AOU_AXI_S_AWREADY  = w_pre_rs_awready    ;
            assign w_pre_rs_wdata       = I_AOU_AXI_S_WDATA   ;
            assign w_pre_rs_wdlen       = I_AOU_AXI_S_WDLEN   ; 
            assign w_pre_rs_wstrb       = I_AOU_AXI_S_WSTRB   ; 
            assign w_pre_rs_wlast       = I_AOU_AXI_S_WLAST   ; 
            assign w_pre_rs_wvalid      = I_AOU_AXI_S_WVALID  ; 
            assign O_AOU_AXI_S_WREADY   = w_pre_rs_wready     ; 
            assign w_pre_rs_arid        = I_AOU_AXI_S_ARID    ; 
            assign w_pre_rs_araddr      = I_AOU_AXI_S_ARADDR  ; 
            assign w_pre_rs_arlen       = I_AOU_AXI_S_ARLEN   ; 
            assign w_pre_rs_arsize      = I_AOU_AXI_S_ARSIZE  ; 
            assign w_pre_rs_arburst     = I_AOU_AXI_S_ARBURST ;
            assign w_pre_rs_arlock      = I_AOU_AXI_S_ARLOCK  ; 
            assign w_pre_rs_arcache     = I_AOU_AXI_S_ARCACHE ;
            assign w_pre_rs_arprot      = I_AOU_AXI_S_ARPROT  ; 
            assign w_pre_rs_arqos       = I_AOU_AXI_S_ARQOS   ; 
            assign w_pre_rs_arvalid     = I_AOU_AXI_S_ARVALID ;
            assign O_AOU_AXI_S_ARREADY  = w_pre_rs_arready    ;
            assign O_AOU_AXI_S_BID      = I_AOU_AXI_M_BID     ; 
            assign O_AOU_AXI_S_BRESP    = I_AOU_AXI_M_BRESP   ; 
            assign O_AOU_AXI_S_BVALID   = I_AOU_AXI_M_BVALID  ; 
            assign O_AOU_AXI_M_BREADY   = I_AOU_AXI_S_BREADY  ; 
            assign O_AOU_AXI_S_RID      = I_AOU_AXI_M_RID     ; 
            assign O_AOU_AXI_S_RDATA    = I_AOU_AXI_M_RDATA   ;
            assign O_AOU_AXI_S_RRESP    = I_AOU_AXI_M_RRESP   ; 
            assign O_AOU_AXI_S_RLAST    = I_AOU_AXI_M_RLAST   ; 
            assign O_AOU_AXI_S_RVALID   = I_AOU_AXI_M_RVALID  ; 
            assign O_AOU_AXI_M_RREADY   = I_AOU_AXI_S_RREADY  ; 


    end
endgenerate


endmodule
