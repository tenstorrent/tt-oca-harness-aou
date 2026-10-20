// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 BOS Semiconductors
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
//  Module     : AOU_AXIMUX_1XN_SS
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AXIMUX_1XN_SS #(
    parameter   AOU_AXIMUX_1XN_ARCH_RS_EN = 1,
    parameter   AOU_AXIMUX_1XN_RCH_RS_EN  = 1,
    parameter   AOU_AXIMUX_1XN_AWCH_RS_EN = 0,//In AoU, it connects with Aggegator, so it should be 0.
    parameter   AOU_AXIMUX_1XN_WCH_RS_EN  = 1,
    parameter   AOU_AXIMUX_1XN_M_AWCH_RS_EN = 1,
    parameter   AOU_AXIMUX_1XN_M_WCH_RS_EN = 1,

    parameter   SN            = 4,
    parameter   SA            = 20,

    parameter   AXI_DATA_WD   = 128,
    parameter   AXI_ADDR_WD   = 32,
    parameter   AXI_ID_WD     = 2,
    parameter   AXI_QOS_WD    = 4,
    parameter   AXI_LEN_WD    = 8,

    localparam  AXI_WSTRB_WD  = AXI_DATA_WD / 8,
    localparam  LOG_SN        = $clog2(SN)
)
(
    input                                     I_CLK         ,
    input                                     I_RESETN      ,

    input         [AXI_ID_WD-1:0]             I_S_ARID      ,
    input         [AXI_ADDR_WD-1:0]           I_S_ARADDR    ,
    input         [AXI_LEN_WD-1:0]            I_S_ARLEN     ,
    input         [2:0]                       I_S_ARSIZE    ,
    input         [1:0]                       I_S_ARBURST   ,
    input         [3:0]                       I_S_ARCACHE   ,
    input         [2:0]                       I_S_ARPROT    ,
    input                                     I_S_ARLOCK    ,
    input         [AXI_QOS_WD-1:0]            I_S_ARQOS     ,
    input                                     I_S_ARVALID   ,
    output                                    O_S_ARREADY   ,

    output        [AXI_ID_WD-1:0]             O_S_RID       ,
    output        [AXI_DATA_WD-1:0]           O_S_RDATA     ,
    output        [1:0]                       O_S_RRESP     ,
    output                                    O_S_RLAST     ,
    output                                    O_S_RVALID    ,
    input                                     I_S_RREADY    ,

    input         [AXI_ID_WD-1:0]             I_S_AWID      ,
    input         [AXI_ADDR_WD-1:0]           I_S_AWADDR    ,
    input         [AXI_LEN_WD-1:0]            I_S_AWLEN     ,
    input         [2:0]                       I_S_AWSIZE    ,
    input         [1:0]                       I_S_AWBURST   ,
    input                                     I_S_AWLOCK    ,
    input         [3:0]                       I_S_AWCACHE   ,
    input         [2:0]                       I_S_AWPROT    ,
    input         [AXI_QOS_WD-1:0]            I_S_AWQOS     ,
    input                                     I_S_AWVALID   ,
    output                                    O_S_AWREADY   ,

    input         [AXI_DATA_WD-1:0]           I_S_WDATA     ,
    input         [AXI_WSTRB_WD-1:0]          I_S_WSTRB     ,
    input                                     I_S_WLAST     ,
    input                                     I_S_WVALID    ,
    output                                    O_S_WREADY    ,

    output        [AXI_ID_WD-1:0]             O_S_BID       ,
    output        [1:0]                       O_S_BRESP     ,
    output                                    O_S_BVALID    ,
    input                                     I_S_BREADY    ,

    output        [SN-1:0][AXI_ID_WD-1:0]     O_M_AWID      ,
    output        [SN-1:0][AXI_ADDR_WD-1:0]   O_M_AWADDR    ,
    output        [SN-1:0][AXI_LEN_WD-1:0]    O_M_AWLEN     ,
    output        [SN-1:0][2:0]               O_M_AWSIZE    ,
    output        [SN-1:0][1:0]               O_M_AWBURST   ,
    output        [SN-1:0]                    O_M_AWLOCK    ,
    output        [SN-1:0][3:0]               O_M_AWCACHE   ,
    output        [SN-1:0][2:0]               O_M_AWPROT    ,
    output        [SN-1:0][AXI_QOS_WD-1:0]    O_M_AWQOS     ,
    output        [SN-1:0]                    O_M_AWVALID   ,
    input         [SN-1:0]                    I_M_AWREADY   ,

    output        [SN-1:0][AXI_DATA_WD-1:0]   O_M_WDATA     ,
    output        [SN-1:0][AXI_WSTRB_WD-1:0]  O_M_WSTRB     ,
    output        [SN-1:0]                    O_M_WLAST     ,
    output        [SN-1:0]                    O_M_WVALID    ,
    input         [SN-1:0]                    I_M_WREADY    ,

    input         [SN-1:0][AXI_ID_WD-1:0]     I_M_BID       ,
    input         [SN-1:0][1:0]               I_M_BRESP     ,
    input         [SN-1:0]                    I_M_BVALID    ,
    output        [SN-1:0]                    O_M_BREADY    ,

    output        [SN-1:0][AXI_ID_WD-1:0]     O_M_ARID      ,
    output        [SN-1:0][AXI_ADDR_WD-1:0]   O_M_ARADDR    ,
    output        [SN-1:0][AXI_LEN_WD-1:0]    O_M_ARLEN     ,
    output        [SN-1:0][2:0]               O_M_ARSIZE    ,
    output        [SN-1:0][1:0]               O_M_ARBURST   ,
    output        [SN-1:0][3:0]               O_M_ARCACHE   ,
    output        [SN-1:0][2:0]               O_M_ARPROT    ,
    output        [SN-1:0]                    O_M_ARLOCK    ,
    output        [SN-1:0][AXI_QOS_WD-1:0]    O_M_ARQOS     ,
    output        [SN-1:0]                    O_M_ARVALID   ,
    input         [SN-1:0]                    I_M_ARREADY   ,

    input         [SN-1:0][AXI_ID_WD-1:0]     I_M_RID       ,
    input         [SN-1:0][AXI_DATA_WD-1:0]   I_M_RDATA     ,
    input         [SN-1:0][1:0]               I_M_RRESP     ,
    input         [SN-1:0]                    I_M_RLAST     ,
    input         [SN-1:0]                    I_M_RVALID    ,
    output        [SN-1:0]                    O_M_RREADY    ,

    input         [31:0]                      I_DEBUG_ERR_UPPER_ADDR,
    input         [31:0]                      I_DEBUG_ERR_LOWER_ADDR,
    input                                     I_DEBUG_ERR_ACCESS_ENABLE
);


//--------------------------------------------------------------
reg                                 r_s_wbusy_tt     ;

//--------------------------------------------------------------
localparam AOU_AXIMUX_1XN_AWCH_PAYLOAD_WD = AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 2 + 1 + 4 + 3 + 4; 
wire [AOU_AXIMUX_1XN_AWCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_awch_rs_sdata;
wire [AOU_AXIMUX_1XN_AWCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_awch_rs_mdata;

wire [AXI_ID_WD-1:0]             I_S_AWID_RS;
wire [AXI_ADDR_WD-1: 0]          I_S_AWADDR_RS;
wire [AXI_LEN_WD-1: 0]           I_S_AWLEN_RS;
wire [2: 0]                      I_S_AWSIZE_RS;
wire [1:0]                       I_S_AWBURST_RS;
wire                             I_S_AWLOCK_RS;
wire [3:0]                       I_S_AWCACHE_RS;
wire [2:0]                       I_S_AWPROT_RS;
wire [3:0]                       I_S_AWQOS_RS;
wire                             I_S_AWVALID_RS;
reg                              O_S_AWREADY_RS;

assign w_aou_aximux_1xn_awch_rs_sdata = {I_S_AWID,
                                      I_S_AWADDR,
                                      I_S_AWLEN,
                                      I_S_AWSIZE,
                                      I_S_AWBURST,
                                      I_S_AWLOCK,
                                      I_S_AWCACHE,
                                      I_S_AWPROT,
                                      I_S_AWQOS};

assign {I_S_AWID_RS,
       I_S_AWADDR_RS,
       I_S_AWLEN_RS,
       I_S_AWSIZE_RS,
       I_S_AWBURST_RS,
       I_S_AWLOCK_RS,
       I_S_AWCACHE_RS,
       I_S_AWPROT_RS,
       I_S_AWQOS_RS} = w_aou_aximux_1xn_awch_rs_mdata;

generate
if (AOU_AXIMUX_1XN_AWCH_RS_EN == 1) begin

    AOU_FWD_RS #(
        .DATA_WIDTH         (AOU_AXIMUX_1XN_AWCH_PAYLOAD_WD)
    ) u_aou_aximux_1xn_awch_rs
    (
        .I_CLK              ( I_CLK                    ),
        .I_RESETN           ( I_RESETN                 ),
    
        .I_SVALID           ( I_S_AWVALID              ),
        .O_SREADY           ( O_S_AWREADY              ),
        .I_SDATA            ( w_aou_aximux_1xn_awch_rs_sdata  ),
    
        .O_MVALID           ( I_S_AWVALID_RS           ),
        .I_MREADY           ( O_S_AWREADY_RS           ),
        .O_MDATA            ( w_aou_aximux_1xn_awch_rs_mdata  )
    );

end else begin
    assign w_aou_aximux_1xn_awch_rs_mdata = w_aou_aximux_1xn_awch_rs_sdata;

    assign I_S_AWVALID_RS = I_S_AWVALID;
    assign O_S_AWREADY = O_S_AWREADY_RS;
end
endgenerate

//--------------------------------------------------------------

localparam AOU_AXIMUX_1XN_WCH_PAYLOAD_WD = AXI_DATA_WD + AXI_WSTRB_WD + 1; 
wire [AOU_AXIMUX_1XN_WCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_wch_rs_sdata;
wire [AOU_AXIMUX_1XN_WCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_wch_rs_mdata;

wire [ AXI_DATA_WD-1: 0]            I_S_WDATA_RS;
wire [ AXI_WSTRB_WD-1: 0]           I_S_WSTRB_RS;
wire                                I_S_WLAST_RS;
wire                                I_S_WVALID_RS;
reg                                 O_S_WREADY_RS;

assign w_aou_aximux_1xn_wch_rs_sdata = {I_S_WDATA, 
                                 I_S_WSTRB, 
                                 I_S_WLAST};

assign {I_S_WDATA_RS, 
        I_S_WSTRB_RS, 
        I_S_WLAST_RS} = w_aou_aximux_1xn_wch_rs_mdata;

generate
if (AOU_AXIMUX_1XN_WCH_RS_EN == 1) begin

    AOU_FWD_RS #(
        .DATA_WIDTH         (AOU_AXIMUX_1XN_WCH_PAYLOAD_WD)
    ) u_aou_aximux_1xn_wch_rs
    (
        .I_CLK              ( I_CLK                   ),
        .I_RESETN           ( I_RESETN                ),
    
        .I_SVALID           ( I_S_WVALID              ),
        .O_SREADY           ( O_S_WREADY              ),
        .I_SDATA            ( w_aou_aximux_1xn_wch_rs_sdata  ),
    
        .O_MVALID           ( I_S_WVALID_RS           ),
        .I_MREADY           ( O_S_WREADY_RS           ),
        .O_MDATA            ( w_aou_aximux_1xn_wch_rs_mdata  )
    );

end else begin
    assign w_aou_aximux_1xn_wch_rs_mdata = w_aou_aximux_1xn_wch_rs_sdata;

    assign I_S_WVALID_RS = I_S_WVALID;
    assign O_S_WREADY = O_S_WREADY_RS;
end
endgenerate

//--------------------------------------------------------------
localparam AOU_AXIMUX_1XN_ARCH_PAYLOAD_WD = AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 2 + 1 + 4 + 3 + 4; 
wire [AOU_AXIMUX_1XN_ARCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_arch_rs_sdata;
wire [AOU_AXIMUX_1XN_ARCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_arch_rs_mdata;

wire [AXI_ID_WD-1:0]             I_S_ARID_RS;
wire [AXI_ADDR_WD-1: 0]          I_S_ARADDR_RS;
wire [AXI_LEN_WD-1: 0]           I_S_ARLEN_RS;
wire [2: 0]                      I_S_ARSIZE_RS;
wire [1:0]                       I_S_ARBURST_RS;
wire                             I_S_ARLOCK_RS;
wire [3:0]                       I_S_ARCACHE_RS;
wire [2:0]                       I_S_ARPROT_RS;
wire [3:0]                       I_S_ARQOS_RS;
wire                             I_S_ARVALID_RS;
reg                              O_S_ARREADY_RS;

assign w_aou_aximux_1xn_arch_rs_sdata = {I_S_ARID,
                                      I_S_ARADDR,
                                      I_S_ARLEN,
                                      I_S_ARSIZE,
                                      I_S_ARBURST,
                                      I_S_ARLOCK,
                                      I_S_ARCACHE,
                                      I_S_ARPROT,
                                      I_S_ARQOS};

assign {I_S_ARID_RS,
       I_S_ARADDR_RS,
       I_S_ARLEN_RS,
       I_S_ARSIZE_RS,
       I_S_ARBURST_RS,
       I_S_ARLOCK_RS,
       I_S_ARCACHE_RS,
       I_S_ARPROT_RS,
       I_S_ARQOS_RS} = w_aou_aximux_1xn_arch_rs_mdata;

generate
if (AOU_AXIMUX_1XN_ARCH_RS_EN == 1) begin

    AOU_FWD_RS #(
        .DATA_WIDTH         (AOU_AXIMUX_1XN_ARCH_PAYLOAD_WD)
    ) u_aou_aximux_1xn_arch_rs
    (
        .I_CLK              ( I_CLK                    ),
        .I_RESETN           ( I_RESETN                 ),
    
        .I_SVALID           ( I_S_ARVALID              ),
        .O_SREADY           ( O_S_ARREADY              ),
        .I_SDATA            ( w_aou_aximux_1xn_arch_rs_sdata  ),
    
        .O_MVALID           ( I_S_ARVALID_RS           ),
        .I_MREADY           ( O_S_ARREADY_RS           ),
        .O_MDATA            ( w_aou_aximux_1xn_arch_rs_mdata  )
    );

end else begin
    assign w_aou_aximux_1xn_arch_rs_mdata = w_aou_aximux_1xn_arch_rs_sdata;

    assign I_S_ARVALID_RS = I_S_ARVALID;
    assign O_S_ARREADY = O_S_ARREADY_RS;
end
endgenerate

//--------------------------------------------------------------
localparam AOU_AXIMUX_1XN_RCH_PAYLOAD_WD = AXI_ID_WD + AXI_DATA_WD + 2 + 1; 
wire [AOU_AXIMUX_1XN_RCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_rch_rs_sdata;
wire [AOU_AXIMUX_1XN_RCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_rch_rs_mdata;

wire        [AXI_ID_WD-1:0]             O_S_RID_RS       ;
wire        [AXI_DATA_WD-1:0]           O_S_RDATA_RS     ;
wire        [1:0]                       O_S_RRESP_RS     ;
wire                                    O_S_RLAST_RS     ;
wire                                    O_S_RVALID_RS    ;
wire                                    I_S_RREADY_RS    ;

assign w_aou_aximux_1xn_rch_rs_sdata = {O_S_RID_RS       ,
                                        O_S_RDATA_RS     ,
                                        O_S_RRESP_RS     ,
                                        O_S_RLAST_RS     };

assign {O_S_RID   ,    
        O_S_RDATA ,   
        O_S_RRESP ,  
        O_S_RLAST} = w_aou_aximux_1xn_rch_rs_mdata;

generate
if (AOU_AXIMUX_1XN_RCH_RS_EN == 1) begin

    AOU_FWD_RS #(
        .DATA_WIDTH         (AOU_AXIMUX_1XN_RCH_PAYLOAD_WD)
    ) u_aou_aximux_1xn_rch_rs
    (
        .I_CLK              ( I_CLK                   ),
        .I_RESETN           ( I_RESETN                ),
    
        .I_SVALID           ( O_S_RVALID_RS           ),
        .O_SREADY           ( I_S_RREADY_RS           ),
        .I_SDATA            ( w_aou_aximux_1xn_rch_rs_sdata  ),
    
        .O_MVALID           ( O_S_RVALID              ),
        .I_MREADY           ( I_S_RREADY              ),
        .O_MDATA            ( w_aou_aximux_1xn_rch_rs_mdata  )
    );

end else begin
    assign w_aou_aximux_1xn_rch_rs_mdata = w_aou_aximux_1xn_rch_rs_sdata;

    assign O_S_RVALID = O_S_RVALID_RS;
    assign I_S_RREADY_RS = I_S_RREADY;
end
endgenerate

//--------------------------------------------------------------

wire w_ar_sel_err_info = (I_S_ARADDR_RS == {I_DEBUG_ERR_UPPER_ADDR, I_DEBUG_ERR_LOWER_ADDR}) && I_DEBUG_ERR_ACCESS_ENABLE;
wire w_aw_sel_err_info = (O_M_AWADDR[SN-1] == {I_DEBUG_ERR_UPPER_ADDR, I_DEBUG_ERR_LOWER_ADDR}) && I_DEBUG_ERR_ACCESS_ENABLE;
wire w_aw_tt_sel_err_info = (I_S_AWADDR_RS == {I_DEBUG_ERR_UPPER_ADDR, I_DEBUG_ERR_LOWER_ADDR}) && I_DEBUG_ERR_ACCESS_ENABLE;

reg r_cur_ar_valid;
reg r_cur_aw_valid;

reg [LOG_SN-1:0] r_selected_ar_ch;
reg [LOG_SN-1:0] r_selected_aw_ch;

reg [7:0] ar_pending_cnt;
reg [7:0] aw_pending_cnt;

always @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_cur_ar_valid <= 1'b0;
        r_selected_ar_ch <= 'd0;
        ar_pending_cnt <= 'd0;

        r_cur_aw_valid <= 1'b0;
        r_selected_aw_ch <= 'd0;
        aw_pending_cnt <= 'd0;

        r_s_wbusy_tt <= 'd0;
    end else begin
        if ((I_S_ARVALID_RS & O_S_ARREADY_RS) & ~(O_S_RLAST_RS & O_S_RVALID_RS & I_S_RREADY_RS)) begin
            ar_pending_cnt <=  ar_pending_cnt + 1;
            if (r_cur_ar_valid == 1'b0) begin
                r_cur_ar_valid <= 1'b1;
                r_selected_ar_ch <= w_ar_sel_err_info;
            end

        end else if (~(I_S_ARVALID_RS & O_S_ARREADY_RS) & (O_S_RLAST_RS & O_S_RVALID_RS & I_S_RREADY_RS)) begin
            ar_pending_cnt <=  ar_pending_cnt - 1;
            if (ar_pending_cnt == 1) begin
                r_cur_ar_valid  <= 1'b0;
            end
        end

        if (I_S_AWVALID_RS & O_S_AWREADY_RS) begin
            if (I_S_WVALID_RS & O_S_WREADY_RS & I_S_WLAST_RS)
                r_s_wbusy_tt <=1'b0;
            else
                r_s_wbusy_tt <=1'b1;

            if (~(O_S_BVALID & I_S_BREADY)) begin
                aw_pending_cnt <=  aw_pending_cnt + 1;
                if (r_cur_aw_valid == 1'b0) begin
                    r_cur_aw_valid <= 1'b1;
                    r_selected_aw_ch <= w_aw_sel_err_info;
                end
            end

        end else begin
            if (I_S_WVALID_RS & O_S_WREADY_RS & I_S_WLAST_RS)
                r_s_wbusy_tt <=1'b0;

            if (O_S_BVALID & I_S_BREADY) begin
                aw_pending_cnt <=  aw_pending_cnt - 1;
                if (aw_pending_cnt == 1) begin
                    r_cur_aw_valid <= 1'b0;
                end
            end
        end
    end
end

wire  [SN-1:0]  O_M_AWVALID_RS;
wire  [SN-1:0]  I_M_AWREADY_RS;

wire  [SN-1:0]  O_M_WVALID_RS;
wire  [SN-1:0]  I_M_WREADY_RS;

assign O_S_ARREADY_RS = I_M_ARREADY[w_ar_sel_err_info] & (~r_cur_ar_valid | (r_cur_ar_valid & (w_ar_sel_err_info == r_selected_ar_ch)));
assign O_S_AWREADY_RS = ~r_s_wbusy_tt & I_M_AWREADY_RS[w_aw_tt_sel_err_info] & (~r_cur_aw_valid | (r_cur_aw_valid & (w_aw_tt_sel_err_info == r_selected_aw_ch)));
assign O_S_WREADY_RS  = ((~r_s_wbusy_tt & I_S_AWVALID_RS & O_S_AWREADY_RS) | r_s_wbusy_tt) & (r_cur_aw_valid ? I_M_WREADY_RS[r_selected_aw_ch] : I_M_WREADY_RS[w_aw_tt_sel_err_info]);

parameter AOU_AXIMUX_1XN_M_AWCH_PAYLOAD_WD = AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 2 + 1 + 4 + 3 + 4; 
parameter AOU_AXIMUX_1XN_M_WCH_PAYLOAD_WD = AXI_DATA_WD + AXI_WSTRB_WD + 1; 

genvar p;
generate
    for(p = 0; p < SN; p = p + 1) begin
        assign O_M_ARVALID[p]   = I_S_ARVALID_RS & (w_ar_sel_err_info == p) & (r_cur_ar_valid ? (r_selected_ar_ch == p) : 1'b1);
        assign O_M_RREADY[p]    = I_S_RREADY_RS & (r_cur_ar_valid ? (r_selected_ar_ch == p) : 1'b0); //any value for non_selected ch is ok

        assign O_M_AWVALID_RS[p]   = ~r_s_wbusy_tt & I_S_AWVALID_RS & (w_aw_tt_sel_err_info == p) & (r_cur_aw_valid ? (r_selected_aw_ch == p) : 1'b1);
        assign O_M_BREADY[p]    = I_S_BREADY & (r_cur_aw_valid ? (r_selected_aw_ch == p) : 1'b0); //any value for non_selected ch is ok

        assign O_M_WVALID_RS[p]    = ((~r_s_wbusy_tt & I_S_AWVALID_RS & O_S_AWREADY_RS) | r_s_wbusy_tt) & I_S_WVALID_RS & (r_cur_aw_valid ? (r_selected_aw_ch == p) : (I_S_AWVALID_RS & O_S_AWREADY_RS & (w_aw_tt_sel_err_info == p)));

        assign O_M_ARID[p]     = I_S_ARID_RS      ;
        assign O_M_ARADDR[p]   = I_S_ARADDR_RS    ;
        assign O_M_ARLEN[p]    = I_S_ARLEN_RS     ;
        assign O_M_ARSIZE[p]   = I_S_ARSIZE_RS    ;
        assign O_M_ARBURST[p]  = I_S_ARBURST_RS   ;
        assign O_M_ARCACHE[p]  = I_S_ARCACHE_RS   ;
        assign O_M_ARPROT[p]   = I_S_ARPROT_RS    ;
        assign O_M_ARLOCK[p]   = I_S_ARLOCK_RS    ;
        assign O_M_ARQOS[p]    = I_S_ARQOS_RS     ;

        //--------------------------------------------------------------
        wire [AOU_AXIMUX_1XN_M_AWCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_m_awch_rs_sdata;
        wire [AOU_AXIMUX_1XN_M_AWCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_m_awch_rs_mdata;
        
        wire [AXI_ID_WD-1:0]             O_M_AWID_RS;
        wire [AXI_ADDR_WD-1: 0]          O_M_AWADDR_RS;
        wire [AXI_LEN_WD-1: 0]           O_M_AWLEN_RS;
        wire [2: 0]                      O_M_AWSIZE_RS;
        wire [1:0]                       O_M_AWBURST_RS;
        wire                             O_M_AWLOCK_RS;
        wire [3:0]                       O_M_AWCACHE_RS;
        wire [2:0]                       O_M_AWPROT_RS;
        wire [3:0]                       O_M_AWQOS_RS;
        
        assign w_aou_aximux_1xn_m_awch_rs_sdata = {O_M_AWID_RS,
                                              O_M_AWADDR_RS,
                                              O_M_AWLEN_RS,
                                              O_M_AWSIZE_RS,
                                              O_M_AWBURST_RS,
                                              O_M_AWLOCK_RS,
                                              O_M_AWCACHE_RS,
                                              O_M_AWPROT_RS,
                                              O_M_AWQOS_RS};
        
        assign {O_M_AWID[p],
               O_M_AWADDR[p],
               O_M_AWLEN[p],
               O_M_AWSIZE[p],
               O_M_AWBURST[p],
               O_M_AWLOCK[p],
               O_M_AWCACHE[p],
               O_M_AWPROT[p],
               O_M_AWQOS[p]} = w_aou_aximux_1xn_m_awch_rs_mdata;
        
        if ((AOU_AXIMUX_1XN_M_AWCH_RS_EN == 1) & (p==0)) begin
        
            AOU_REV_RS #(
                .DATA_WIDTH         (AOU_AXIMUX_1XN_M_AWCH_PAYLOAD_WD)
            ) u_aou_aximux_1xn_m_awch_rs
            (
                .I_CLK              ( I_CLK                    ),
                .I_RESETN           ( I_RESETN                 ),
            
                .I_SVALID           ( O_M_AWVALID_RS[p]        ),
                .O_SREADY           ( I_M_AWREADY_RS[p]        ),
                .I_SDATA            ( w_aou_aximux_1xn_m_awch_rs_sdata  ),
            
                .O_MVALID           ( O_M_AWVALID[p]           ),
                .I_MREADY           ( I_M_AWREADY[p]           ),
                .O_MDATA            ( w_aou_aximux_1xn_m_awch_rs_mdata  )
            );
        
        end else begin
            assign w_aou_aximux_1xn_m_awch_rs_mdata = w_aou_aximux_1xn_m_awch_rs_sdata;
        
            assign O_M_AWVALID[p] = O_M_AWVALID_RS[p];
            assign I_M_AWREADY_RS[p] = I_M_AWREADY[p];
        end
    
        //---------------------------------------------------
        wire [AOU_AXIMUX_1XN_M_WCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_m_wch_rs_sdata;
        wire [AOU_AXIMUX_1XN_M_WCH_PAYLOAD_WD - 1:0] w_aou_aximux_1xn_m_wch_rs_mdata;
        
        wire [ AXI_DATA_WD-1: 0]            O_M_WDATA_RS;
        wire [ AXI_WSTRB_WD-1: 0]           O_M_WSTRB_RS;
        wire                                O_M_WLAST_RS;
        
        assign w_aou_aximux_1xn_m_wch_rs_sdata = {O_M_WDATA_RS, 
                                            O_M_WSTRB_RS, 
                                            O_M_WLAST_RS};
        
        assign {O_M_WDATA[p], 
                O_M_WSTRB[p], 
                O_M_WLAST[p]} = w_aou_aximux_1xn_m_wch_rs_mdata;
    
        if ((AOU_AXIMUX_1XN_M_WCH_RS_EN == 1) & (p==0)) begin
        
            AOU_REV_RS #(
                .DATA_WIDTH         (AOU_AXIMUX_1XN_M_WCH_PAYLOAD_WD)
            ) u_aou_aximux_1xn_m_wch_rs
            (
                .I_CLK              ( I_CLK                   ),
                .I_RESETN           ( I_RESETN                ),
            
                .I_SVALID           ( O_M_WVALID_RS[p]        ),
                .O_SREADY           ( I_M_WREADY_RS[p]        ),
                .I_SDATA            ( w_aou_aximux_1xn_m_wch_rs_sdata  ),
            
                .O_MVALID           ( O_M_WVALID[p]           ),
                .I_MREADY           ( I_M_WREADY[p]           ),
                .O_MDATA            ( w_aou_aximux_1xn_m_wch_rs_mdata  )
            );
        
        end else begin
            assign w_aou_aximux_1xn_m_wch_rs_mdata = w_aou_aximux_1xn_m_wch_rs_sdata;
        
            assign O_M_WVALID[p] = O_M_WVALID_RS[p];
            assign I_M_WREADY_RS[p] = I_M_WREADY[p];
    
    end
    
        //---------------------------------------------------
        assign O_M_AWID_RS     = I_S_AWID_RS      ;
        assign O_M_AWADDR_RS   = I_S_AWADDR_RS    ;
        assign O_M_AWLEN_RS    = I_S_AWLEN_RS     ;
        assign O_M_AWSIZE_RS   = I_S_AWSIZE_RS    ;
        assign O_M_AWBURST_RS  = I_S_AWBURST_RS   ;
        assign O_M_AWCACHE_RS  = I_S_AWCACHE_RS   ;
        assign O_M_AWPROT_RS   = I_S_AWPROT_RS    ;
        assign O_M_AWLOCK_RS   = I_S_AWLOCK_RS    ;
        assign O_M_AWQOS_RS    = I_S_AWQOS_RS     ;
        
        assign O_M_WDATA_RS = I_S_WDATA_RS     ;
        assign O_M_WSTRB_RS = I_S_WSTRB_RS     ;
        assign O_M_WLAST_RS = I_S_WLAST_RS     ;
    end

endgenerate

assign O_S_RID_RS      = I_M_RID[r_selected_ar_ch];
assign O_S_RDATA_RS    = I_M_RDATA[r_selected_ar_ch];
assign O_S_RRESP_RS    = I_M_RRESP[r_selected_ar_ch];
assign O_S_RLAST_RS    = I_M_RLAST[r_selected_ar_ch];
assign O_S_RVALID_RS   = I_M_RVALID[r_selected_ar_ch];

assign O_S_BID      = I_M_BID[r_selected_aw_ch];
assign O_S_BRESP    = I_M_BRESP[r_selected_aw_ch];
assign O_S_BVALID   = I_M_BVALID[r_selected_aw_ch];

//--------------------------------------------------------------
`ifdef ASSERTION_ON
// synopsys translate_off
genvar k;
generate
    for (k = 0; k < SN; k ++) begin : G_AW_PROPERTY
        AW_assertion:
            assert
                property (
                    @(posedge I_CLK) disable iff (!I_RESETN)
                        (O_M_AWVALID[k] & ~I_M_AWREADY[k]) |-> ##1
                        (~(~O_M_AWVALID[k] & ~I_M_AWREADY[k]) &
                        $stable(O_M_AWID[k]) &
                        $stable(O_M_AWADDR[k]) &
                        $stable(O_M_AWLEN[k]) &
                        $stable(O_M_AWSIZE[k]) &
                        $stable(O_M_AWBURST[k]))
                    )
                    else begin
                        $error("\n[%t]AW VALID SIGNAL ERROR", $time);
                        $finish;
                    end

        AR_assertion:
            assert
                property (
                    @(posedge I_CLK)  disable iff (!I_RESETN)
                        (O_M_ARVALID[k] & ~I_M_ARREADY[k]) |-> ##1
                        (~(~O_M_ARVALID[k] & ~I_M_ARREADY[k]) &
                        $stable(O_M_ARID[k]) &
                        $stable (O_M_ARADDR[k]) &
                        $stable(O_M_ARLEN[k]) &
                        $stable(O_M_ARSIZE[k]) &
                        $stable(O_M_ARBURST[k]))
                )
                else begin
                    $error("\n[%t] AR VALID SIGNAL ERROR", $time);
                    $finish;
                end
   end
endgenerate
// synopsys translate_on
`endif

endmodule

