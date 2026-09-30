// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 BOS Semiconductors
//  Copyright (c) 2026 Tenstorrent USA Inc
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
//  Module     : AOU_AXI_SPLIT_TR
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AXI_SPLIT_TR #(
    parameter   DATA_WD   = 512,
    parameter   ADDR_WD   = 64,
    parameter   ID_WD     = 10,
    parameter   STRB_WD   = DATA_WD / 8,
    parameter   QOS_WD    = 4,
    parameter   LEN_WD    = 8,
    parameter   RD_MO_CNT = 64,
    parameter   WR_MO_CNT = 64,
    parameter   AOU_AXI_SPLIT_TR_SLV_ARCH_RS_EN = 1,
    parameter   AOU_AXI_SPLIT_TR_SLV_RCH_RS_EN = 1,
    parameter   AOU_AXI_SPLIT_TR_MST_AWCH_RS_EN = 1,
    parameter   AOU_AXI_SPLIT_TR_MST_WCH_RS_EN = 1,
    parameter   AOU_AXI_SPLIT_TR_MST_BCH_RS_EN = 0,
    parameter   AOU_AXI_SPLIT_TR_MST_ARCH_RS_EN = 0,
    parameter   AOU_AXI_SPLIT_TR_MST_RCH_RS_EN = 1,

    localparam  RD_MO_IDX_WD = $clog2(RD_MO_CNT)

)
(
    input                               I_CLK,
    input                               I_RESETN,

    input       [ ID_WD-1: 0]           I_S_AWID,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR,
    input       [ LEN_WD-1: 0]          I_S_AWLEN,
    input       [ 2: 0]                 I_S_AWSIZE,
    input       [ 1: 0]                 I_S_AWBURST,
    input                               I_S_AWLOCK,
    input       [ 3: 0]                 I_S_AWCACHE,
    input       [ 2: 0]                 I_S_AWPROT,
    input       [ QOS_WD-1: 0]          I_S_AWQOS,
    input                               I_S_AWVALID,
    output wire                         O_S_AWREADY,

    input       [ DATA_WD-1 : 0]        I_S_WDATA,
    input       [ STRB_WD-1 : 0]        I_S_WSTRB,
    input                               I_S_WLAST,
    input                               I_S_WVALID,
    output                              O_S_WREADY,

    output wire [ ID_WD-1: 0]           O_S_BID,
    output wire [ 1: 0]                 O_S_BRESP,
    output wire                         O_S_BVALID,
    input                               I_S_BREADY,

    input       [ ID_WD-1: 0]           I_S_ARID,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR,
    input       [ 2: 0]                 I_S_ARSIZE,
    input       [ 1: 0]                 I_S_ARBURST,
    input       [ 3: 0]                 I_S_ARCACHE,
    input       [ 2: 0]                 I_S_ARPROT,
    input       [ LEN_WD-1: 0]          I_S_ARLEN,
    input                               I_S_ARLOCK,
    input       [ QOS_WD-1: 0]          I_S_ARQOS,
    input                               I_S_ARVALID,
    output wire                         O_S_ARREADY,

    output wire [ ID_WD-1: 0]           O_S_RID,
    output wire [ DATA_WD-1: 0]         O_S_RDATA,
    output wire [ 1: 0]                 O_S_RRESP,
    output wire                         O_S_RLAST,
    output wire [ADDR_WD-1:0]           O_S_ADDR_CNT,
    output wire                         O_S_RVALID,
    input                               I_S_RREADY,
 
    output wire [ ID_WD-3: 0]           O_M_AWID,
    output wire [ ADDR_WD-1: 0]         O_M_AWADDR,
    output wire [ LEN_WD-1: 0]          O_M_AWLEN,
    output wire [ 2: 0]                 O_M_AWSIZE,
    output wire [ 1: 0]                 O_M_AWBURST,
    output wire                         O_M_AWLOCK,
    output wire [ 3: 0]                 O_M_AWCACHE,
    output wire [ 2: 0]                 O_M_AWPROT,
    output wire [ 3: 0]                 O_M_AWQOS,
    output wire                         O_M_AWVALID,
    input                               I_M_AWREADY,      

    output wire [ DATA_WD-1: 0]         O_M_WDATA,
    output wire [ STRB_WD-1: 0]         O_M_WSTRB,
    output wire                         O_M_WLAST,
    output wire                         O_M_WVALID,
    input                               I_M_WREADY,

    input       [ ID_WD-3: 0]           I_M_BID,
    input       [ 1: 0]                 I_M_BRESP,
    input                               I_M_BVALID,
    output wire                         O_M_BREADY,

    output wire [ ID_WD-3: 0]           O_M_ARID,
    output wire [ ADDR_WD-1: 0]         O_M_ARADDR,
    output wire [ 2: 0]                 O_M_ARSIZE,
    output wire [ 1: 0]                 O_M_ARBURST,
    output wire [ 3: 0]                 O_M_ARCACHE,
    output wire [ 2: 0]                 O_M_ARPROT,
    output wire [ LEN_WD-1: 0]          O_M_ARLEN,
    output wire                         O_M_ARLOCK,
    output      [ QOS_WD-1: 0]          O_M_ARQOS,
    output wire                         O_M_ARVALID,
    input                               I_M_ARREADY,

    input       [ ID_WD-3: 0]           I_M_RID,
    input       [ DATA_WD-1: 0]         I_M_RDATA,
    input       [ 1: 0]                 I_M_RRESP,
    input                               I_M_RLAST,
    input                               I_M_RVALID,
    output wire                         O_M_RREADY,

    output      [ ID_WD-3:0]            O_BRESP_ERR_ID,
    output      [ ADDR_WD-1:0]          O_BRESP_ERR_ADDR,
    output      [ 1 :0]                 O_BRESP_ERR_BRESP,
    output                              O_BRESP_ERR,

    output      [ ID_WD-3:0]            O_RRESP_ERR_ID,
    output      [ ADDR_WD-1:0]          O_RRESP_ERR_ADDR,
    output      [ 1 :0]                 O_RRESP_ERR_RRESP,
    output                              O_RRESP_ERR,

    output      [ID_WD-3: 0]            O_SPLIT_MISMATCH_RID,
    output      [ID_WD-3: 0]            O_SPLIT_MISMATCH_BID,    
    output wire                         O_DEST_TABLE_RID_ERR,
    output wire                         O_DEST_TABLE_BID_ERR,

    input       [ LEN_WD-1: 0]          I_MAX_AWBURSTLEN,
    input       [ LEN_WD-1: 0]          I_MAX_ARBURSTLEN
);

//----------------------------------------------------
localparam AXI_ARCH_PAYLOAD_WD = ID_WD + ADDR_WD + LEN_WD + 3 + 2 + 1 + 4 + 3 + QOS_WD;
localparam AXI_AWCH_PAYLOAD_WD = ID_WD + ADDR_WD + LEN_WD + 3 + 2 + 1 + 4 + 3 + QOS_WD;
localparam AXI_WCH_PAYLOAD_WD  = DATA_WD + STRB_WD + 1;

localparam AXI_M_ARCH_PAYLOAD_WD = ID_WD -2 + ADDR_WD + LEN_WD + 3 + 2 + 1 + 4 + 3 + QOS_WD;
localparam AXI_M_AWCH_PAYLOAD_WD = ID_WD -2 + ADDR_WD + LEN_WD + 3 + 2 + 1 + 4 + 3 + QOS_WD;

//----------------------------------------------------
localparam PENDING_CNT_WD = $clog2(WR_MO_CNT+1);
reg [PENDING_CNT_WD-1:0]            r_wr_pending_cnt;
wire                                w_aw_no_stop;
wire                                w_fc_m_awready;
wire                                w_fc_m_bvalid;
//----------------------------------------------------
wire [AXI_ARCH_PAYLOAD_WD - 1 : 0]  w_aou_split_tr_s_arch_rs_sdata;
wire [AXI_ARCH_PAYLOAD_WD - 1 : 0]  w_aou_split_tr_s_arch_rs_mdata;
wire                                w_aou_split_tr_s_arch_rs_mvalid;
wire                                w_aou_split_tr_s_arch_rs_sready;

wire [ADDR_WD-1:0]                  w_aou_split_tr_s_arch_rs_mdata_araddr;
wire [LEN_WD-1:0]                   w_aou_split_tr_s_arch_rs_mdata_arlen;

reg  [ADDR_WD-1:0]                  r_arch_fwd_rs_mdata_araddr;
reg  [LEN_WD-1:0]                   r_arch_fwd_rs_mdata_arlen;

wire                                w_m_arch_start_valid; 
wire                                w_m_arch_next_valid;

wire                                w_m_arch_ready;

wire                                w_m_arch_working;
wire [ 11 : 0]                      w_next_araddr;
reg  [ 11 : 0]                      r_cur_araddr;
wire [ 11 : 0]                      w_splitter_input_araddr;

wire                                w_s_arvalid ;
wire                                w_s_arready ;
wire                                w_arch_no_stop;
//----------------------------------------------------
wire [AXI_AWCH_PAYLOAD_WD - 1 : 0]  w_awch_fwd_rs_sdata;
wire [AXI_AWCH_PAYLOAD_WD - 1 : 0]  w_awch_fwd_rs_mdata;
wire                                w_awch_fwd_rs_mvalid;
wire                                w_awch_fwd_rs_sready;

wire [AXI_WCH_PAYLOAD_WD - 1 : 0]   w_wch_fwd_rs_sdata;
wire [AXI_WCH_PAYLOAD_WD - 1 : 0]   w_wch_fwd_rs_mdata;
wire                                w_wch_fwd_rs_mvalid;
wire                                w_wch_fwd_rs_sready;

wire                                w_m_awch_en;
wire                                w_m_awch_ready;
wire                                w_m_wch_ready;

wire                                w_m_awch_working;
wire [ 11 : 0]                      w_next_awaddr;
reg  [ 11 : 0]                      r_cur_awaddr;
wire [ 11 : 0]                      w_splitter_input_awaddr;

wire [ADDR_WD-1:0]                  w_awch_fwd_rs_mdata_awaddr;
wire [LEN_WD-1:0]                   w_awch_fwd_rs_mdata_awlen;

reg  [ADDR_WD-1:0]                  r_awch_fwd_rs_mdata_awaddr;
reg  [LEN_WD-1:0]                   r_awch_fwd_rs_mdata_awlen;

wire                                w_wch_fwd_rs_mdata_wlast;

reg [LEN_WD-1:0]                    r_cur_wr_beatcnt;

wire                                w_m_awch_start_valid;
wire                                w_m_awch_next_valid;

wire                                w_s_awready;

//----------------------------------------------------
//--------------------------------------------------------------
localparam AXI_RCH_PAYLOAD_WD  = ID_WD + DATA_WD + 2 + 1 + ADDR_WD;
wire [AXI_RCH_PAYLOAD_WD - 1:0] w_aou_axi_split_tr_rch_rs_sdata;
wire [AXI_RCH_PAYLOAD_WD - 1:0] w_aou_axi_split_tr_rch_rs_mdata;

wire [ID_WD-1:0]                          O_S_RID_RS       ;
wire [DATA_WD-1:0]                        O_S_RDATA_RS     ;
wire [1:0]                                O_S_RRESP_RS     ;
wire                                      O_S_RLAST_RS     ;
wire [ADDR_WD-1:0]                        O_S_ADDR_CNT_RS  ;
wire                                      O_S_RVALID_RS    ;
wire                                      I_S_RREADY_RS    ;

assign w_aou_axi_split_tr_rch_rs_sdata = {O_S_RID_RS       ,
                                          O_S_RDATA_RS     ,
                                          O_S_RRESP_RS     ,
                                          O_S_ADDR_CNT_RS  ,
                                          O_S_RLAST_RS     };

assign {O_S_RID   ,    
        O_S_RDATA ,   
        O_S_RRESP ,  
        O_S_ADDR_CNT,  
        O_S_RLAST} = w_aou_axi_split_tr_rch_rs_mdata;

generate
if (AOU_AXI_SPLIT_TR_SLV_RCH_RS_EN == 1) begin

    AOU_REV_RS #(
        .DATA_WIDTH         (AXI_RCH_PAYLOAD_WD)
    ) u_aou_axi_split_tr_rch_rs
    (
        .I_CLK              ( I_CLK                           ),
        .I_RESETN           ( I_RESETN                        ),
    
        .I_SVALID           ( O_S_RVALID_RS                   ),
        .O_SREADY           ( I_S_RREADY_RS                   ),
        .I_SDATA            ( w_aou_axi_split_tr_rch_rs_sdata ),
    
        .O_MVALID           ( O_S_RVALID                      ),
        .I_MREADY           ( I_S_RREADY                      ),
        .O_MDATA            ( w_aou_axi_split_tr_rch_rs_mdata )
    );

end else begin
    assign w_aou_axi_split_tr_rch_rs_mdata = w_aou_axi_split_tr_rch_rs_sdata;

    assign O_S_RVALID = O_S_RVALID_RS;
    assign I_S_RREADY_RS = I_S_RREADY;
end
endgenerate

//----------------------------------------------------
wire [AXI_M_AWCH_PAYLOAD_WD - 1:0] w_aou_split_tr_m_awch_rs_sdata;
wire [AXI_M_AWCH_PAYLOAD_WD - 1:0] w_aou_split_tr_m_awch_rs_mdata;
wire                             w_aou_split_tr_m_awch_rs_mvalid;
wire                             w_aou_split_tr_m_awch_rs_mready;

wire [ ID_WD-1: 0]               O_M_AWID_RS;
wire [ ADDR_WD-1: 0]             O_M_AWADDR_RS;
wire [ LEN_WD-1: 0]              O_M_AWLEN_RS;
wire [ 2: 0]                     O_M_AWSIZE_RS;
wire [ 1: 0]                     O_M_AWBURST_RS;
wire                             O_M_AWLOCK_RS;
wire [ 3: 0]                     O_M_AWCACHE_RS;
wire [ 2: 0]                     O_M_AWPROT_RS;
wire [ 3: 0]                     O_M_AWQOS_RS;
wire                             O_M_AWVALID_RS;
wire                             I_M_AWREADY_RS;      

assign w_aou_split_tr_m_awch_rs_sdata = {O_M_AWID_RS[ID_WD-1:2],
                                       O_M_AWADDR_RS,
                                       O_M_AWLEN_RS,
                                       O_M_AWSIZE_RS,
                                       O_M_AWBURST_RS,
                                       O_M_AWLOCK_RS,
                                       O_M_AWCACHE_RS,
                                       O_M_AWPROT_RS,
                                       O_M_AWQOS_RS};

assign {O_M_AWID,
       O_M_AWADDR,
       O_M_AWLEN,
       O_M_AWSIZE,
       O_M_AWBURST,
       O_M_AWLOCK,
       O_M_AWCACHE,
       O_M_AWPROT,
       O_M_AWQOS} = w_aou_split_tr_m_awch_rs_mdata;

generate
if (AOU_AXI_SPLIT_TR_MST_AWCH_RS_EN == 1) begin
    AOU_ISO_RS #(
        .DATA_WIDTH         (AXI_M_AWCH_PAYLOAD_WD)
    ) u_aou_split_tr_m_awch_rs
    (
        .I_CLK              ( I_CLK                        ),
        .I_RESETN           ( I_RESETN                     ),
    
        .I_SVALID           ( O_M_AWVALID_RS               ),
        .O_SREADY           ( I_M_AWREADY_RS               ),
        .I_SDATA            ( w_aou_split_tr_m_awch_rs_sdata ),
    
        .O_MVALID           ( O_M_AWVALID                  ),
        .I_MREADY           ( I_M_AWREADY                  ),
        .O_MDATA            ( w_aou_split_tr_m_awch_rs_mdata )
    );
end else begin
    assign w_aou_split_tr_m_awch_rs_mdata = w_aou_split_tr_m_awch_rs_sdata; 
    assign O_M_AWVALID = O_M_AWVALID_RS;
    assign I_M_AWREADY_RS = I_M_AWREADY;

end

//----------------------------------------------------
wire [AXI_WCH_PAYLOAD_WD - 1:0] w_aou_split_tr_m_wch_rs_sdata;
wire [AXI_WCH_PAYLOAD_WD - 1:0] w_aou_split_tr_m_wch_rs_mdata;
wire                            w_aou_split_tr_m_wch_rs_mvalid;
wire                            w_aou_split_tr_m_wch_rs_mready;

wire [ DATA_WD-1: 0]         O_M_WDATA_RS;
wire [ STRB_WD-1: 0]         O_M_WSTRB_RS;
wire                         O_M_WLAST_RS;
wire                         O_M_WVALID_RS;
wire                         I_M_WREADY_RS;

assign w_aou_split_tr_m_wch_rs_sdata = {O_M_WDATA_RS, 
                                        O_M_WSTRB_RS, 
                                        O_M_WLAST_RS};

assign {O_M_WDATA, 
        O_M_WSTRB, 
        O_M_WLAST} = w_aou_split_tr_m_wch_rs_mdata;

if (AOU_AXI_SPLIT_TR_MST_WCH_RS_EN == 1) begin
    AOU_ISO_RS #(
        .DATA_WIDTH         (AXI_WCH_PAYLOAD_WD)
    ) u_aou_split_tr_m_wch_rs
    (
        .I_CLK              ( I_CLK                          ),
        .I_RESETN           ( I_RESETN                       ),
    
        .I_SVALID           ( O_M_WVALID_RS                  ),
        .O_SREADY           ( I_M_WREADY_RS                  ),
        .I_SDATA            ( w_aou_split_tr_m_wch_rs_sdata  ),
    
        .O_MVALID           ( O_M_WVALID                     ),
        .I_MREADY           ( I_M_WREADY                     ),
        .O_MDATA            ( w_aou_split_tr_m_wch_rs_mdata  )
    );
end else begin
    assign w_aou_split_tr_m_wch_rs_mdata = w_aou_split_tr_m_wch_rs_sdata; 
    assign O_M_WVALID    = O_M_WVALID_RS ; 
    assign I_M_WREADY_RS = I_M_WREADY    ; 
end
endgenerate

//--------------------------------------------------------------
localparam AXI_M_BCH_PAYLOAD_WD  = ID_WD - 2 + 2 ;
wire [AXI_M_BCH_PAYLOAD_WD - 1:0] w_aou_axi_split_tr_m_bch_rs_sdata;
wire [AXI_M_BCH_PAYLOAD_WD - 1:0] w_aou_axi_split_tr_m_bch_rs_mdata;

wire [ID_WD-3:0]                            I_M_BID_RS       ;
wire [1:0]                                  I_M_BRESP_RS     ;
wire                                        I_M_BVALID_RS    ;
wire                                        O_M_BREADY_RS    ;

assign w_aou_axi_split_tr_m_bch_rs_sdata = {I_M_BID          ,
                                            I_M_BRESP        };

assign {I_M_BID_RS   ,    
        I_M_BRESP_RS } = w_aou_axi_split_tr_m_bch_rs_mdata;

generate
if (AOU_AXI_SPLIT_TR_MST_BCH_RS_EN == 1) begin

    AOU_ISO_RS #(
        .DATA_WIDTH         (AXI_M_BCH_PAYLOAD_WD)
    ) u_aou_axi_split_tr_m_bch_rs
    (
        .I_CLK              ( I_CLK                             ),
        .I_RESETN           ( I_RESETN                          ),
    
        .I_SVALID           ( I_M_BVALID                        ),
        .O_SREADY           ( O_M_BREADY                        ),
        .I_SDATA            ( w_aou_axi_split_tr_m_bch_rs_sdata ),
    
        .O_MVALID           ( I_M_BVALID_RS                     ),
        .I_MREADY           ( O_M_BREADY_RS                     ),
        .O_MDATA            ( w_aou_axi_split_tr_m_bch_rs_mdata )
    );

end else begin
    assign w_aou_axi_split_tr_m_bch_rs_mdata = w_aou_axi_split_tr_m_bch_rs_sdata;

    assign I_M_BVALID_RS = I_M_BVALID;
    assign O_M_BREADY = O_M_BREADY_RS;
end
endgenerate

//----------------------------------------------------
wire [AXI_M_ARCH_PAYLOAD_WD - 1:0] w_aou_split_tr_m_arch_rs_sdata;
wire [AXI_M_ARCH_PAYLOAD_WD - 1:0] w_aou_split_tr_m_arch_rs_mdata;
wire                             w_aou_split_tr_m_arch_rs_mvalid;
wire                             w_aou_split_tr_m_arch_rs_mready;

wire [ ID_WD-1: 0]               O_M_ARID_RS;
wire [ ADDR_WD-1: 0]             O_M_ARADDR_RS;
wire [ LEN_WD-1: 0]              O_M_ARLEN_RS;
wire [ 2: 0]                     O_M_ARSIZE_RS;
wire [ 1: 0]                     O_M_ARBURST_RS;
wire                             O_M_ARLOCK_RS;
wire [ 3: 0]                     O_M_ARCACHE_RS;
wire [ 2: 0]                     O_M_ARPROT_RS;
wire [ 3: 0]                     O_M_ARQOS_RS;
wire                             O_M_ARVALID_RS;
wire                             I_M_ARREADY_RS;      

assign w_aou_split_tr_m_arch_rs_sdata = {O_M_ARID_RS[ ID_WD-1: 2],
                                         O_M_ARADDR_RS,
                                         O_M_ARLEN_RS,
                                         O_M_ARSIZE_RS,
                                         O_M_ARBURST_RS,
                                         O_M_ARLOCK_RS,
                                         O_M_ARCACHE_RS,
                                         O_M_ARPROT_RS,
                                         O_M_ARQOS_RS};

assign {O_M_ARID,
       O_M_ARADDR,
       O_M_ARLEN,
       O_M_ARSIZE,
       O_M_ARBURST,
       O_M_ARLOCK,
       O_M_ARCACHE,
       O_M_ARPROT,
       O_M_ARQOS} = w_aou_split_tr_m_arch_rs_mdata;

generate
if (AOU_AXI_SPLIT_TR_MST_ARCH_RS_EN == 1) begin
    AOU_ISO_RS #(
        .DATA_WIDTH         (AXI_M_ARCH_PAYLOAD_WD)
    ) u_aou_split_tr_m_arch_rs
    (
        .I_CLK              ( I_CLK                          ),
        .I_RESETN           ( I_RESETN                       ),
    
        .I_SVALID           ( O_M_ARVALID_RS                 ),
        .O_SREADY           ( I_M_ARREADY_RS                 ),
        .I_SDATA            ( w_aou_split_tr_m_arch_rs_sdata ),
    
        .O_MVALID           ( O_M_ARVALID                    ),
        .I_MREADY           ( I_M_ARREADY                    ),
        .O_MDATA            ( w_aou_split_tr_m_arch_rs_mdata )
    );
end else begin
    assign w_aou_split_tr_m_arch_rs_mdata = w_aou_split_tr_m_arch_rs_sdata;
    assign O_M_ARVALID          =  O_M_ARVALID_RS;
    assign I_M_ARREADY_RS       =  I_M_ARREADY;

end
endgenerate

//--------------------------------------------------------------
localparam AXI_M_RCH_PAYLOAD_WD  = ID_WD - 2 + DATA_WD + 2 + 1 ;
wire [AXI_M_RCH_PAYLOAD_WD - 1:0] w_aou_axi_split_tr_m_rch_rs_sdata;
wire [AXI_M_RCH_PAYLOAD_WD - 1:0] w_aou_axi_split_tr_m_rch_rs_mdata;

wire [ID_WD-3:0]                            I_M_RID_RS       ;
wire [DATA_WD-1:0]                          I_M_RDATA_RS     ;
wire [1:0]                                  I_M_RRESP_RS     ;
wire                                        I_M_RLAST_RS     ;
wire                                        I_M_RVALID_RS    ;
wire                                        O_M_RREADY_RS    ;

assign w_aou_axi_split_tr_m_rch_rs_sdata = {I_M_RID       ,
                                            I_M_RDATA     ,
                                            I_M_RRESP     ,
                                            I_M_RLAST     };

assign {I_M_RID_RS   ,    
        I_M_RDATA_RS ,   
        I_M_RRESP_RS ,  
        I_M_RLAST_RS} = w_aou_axi_split_tr_m_rch_rs_mdata;

generate
if (AOU_AXI_SPLIT_TR_MST_RCH_RS_EN == 1) begin

    AOU_ISO_RS #(
        .DATA_WIDTH         (AXI_M_RCH_PAYLOAD_WD)
    ) u_aou_axi_split_tr_m_rch_rs
    (
        .I_CLK              ( I_CLK                             ),
        .I_RESETN           ( I_RESETN                          ),
    
        .I_SVALID           ( I_M_RVALID                        ),
        .O_SREADY           ( O_M_RREADY                        ),
        .I_SDATA            ( w_aou_axi_split_tr_m_rch_rs_sdata ),
    
        .O_MVALID           ( I_M_RVALID_RS                     ),
        .I_MREADY           ( O_M_RREADY_RS                     ),
        .O_MDATA            ( w_aou_axi_split_tr_m_rch_rs_mdata )
    );

end else begin
    assign w_aou_axi_split_tr_m_rch_rs_mdata = w_aou_axi_split_tr_m_rch_rs_sdata;

    assign I_M_RVALID_RS = I_M_RVALID;
    assign O_M_RREADY    = O_M_RREADY_RS;
end
endgenerate

//--------------------------------------------------------------
// MAX_SPLIT_BURST_CNT_WD
//----------------------------------------------------
wire [3:0] ar_shift_count;
wire [3:0] aw_shift_count;

reg  [LEN_WD-1:0] w_arch_split_tr_cnt;
reg  [LEN_WD-1:0] w_awch_split_tr_cnt;

always @ (*) begin
    case (I_MAX_ARBURSTLEN)
        0:   w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 0;
        1:   w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 1;
        3:   w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 2;
        7:   w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 3;
        15:  w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 4;
        31:  w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 5;
        63:  w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 6;
        127: w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 7;
        // 256-beat sub-burst covers any AXI burst: no additional sub-bursts.
        255: w_arch_split_tr_cnt = {LEN_WD{1'b0}};
        default: w_arch_split_tr_cnt = w_aou_split_tr_s_arch_rs_mdata_arlen >> 0;
    endcase
end

always @ (*) begin
    case (I_MAX_AWBURSTLEN)
        0:   w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 0;
        1:   w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 1;
        3:   w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 2;
        7:   w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 3;
        15:  w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 4;
        31:  w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 5;
        63:  w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 6;
        127: w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 7;
        // 256-beat sub-burst covers any AXI burst: no additional sub-bursts.
        255: w_awch_split_tr_cnt = {LEN_WD{1'b0}};
        default: w_awch_split_tr_cnt = w_awch_fwd_rs_mdata_awlen >> 0;
    endcase
end

//----------------------------------------------------
// AR transaction splitter
//----------------------------------------------------
assign w_s_arvalid = I_S_ARVALID;
assign O_S_ARREADY = w_s_arready;

assign w_aou_split_tr_s_arch_rs_sdata = {
    I_S_ARID,
    I_S_ARADDR,
    I_S_ARLEN,
    I_S_ARSIZE,
    I_S_ARBURST,
    I_S_ARLOCK,
    I_S_ARCACHE,
    I_S_ARPROT,
    I_S_ARQOS
};

assign {O_M_ARID_RS,
        w_aou_split_tr_s_arch_rs_mdata_araddr,
        w_aou_split_tr_s_arch_rs_mdata_arlen,
        O_M_ARSIZE_RS,
        O_M_ARBURST_RS,
        O_M_ARLOCK_RS, 
        O_M_ARCACHE_RS,
        O_M_ARPROT_RS, 
        O_M_ARQOS_RS} = w_aou_split_tr_s_arch_rs_mdata;

generate
if (AOU_AXI_SPLIT_TR_SLV_ARCH_RS_EN == 1) begin
    AOU_ISO_RS #(
        .DATA_WIDTH ( AXI_ARCH_PAYLOAD_WD  )
    ) u_aou_fwd_rs_arch
    (
       // global interconnect inputs
       .I_RESETN( I_RESETN                      ),
       .I_CLK   ( I_CLK                         ),
    
       // inputs
       .I_SVALID( w_s_arvalid                   ),
       .O_SREADY( w_s_arready                   ),
       .I_SDATA ( w_aou_split_tr_s_arch_rs_sdata           ),
    
       // outputs
       .I_MREADY( w_m_arch_ready  ),
       .O_MVALID( w_aou_split_tr_s_arch_rs_mvalid          ),
       .O_MDATA ( w_aou_split_tr_s_arch_rs_mdata           )
    );

end else begin
    assign w_aou_split_tr_s_arch_rs_mdata = w_aou_split_tr_s_arch_rs_sdata;
    assign w_aou_split_tr_s_arch_rs_mvalid = w_s_arvalid ;
    assign w_s_arready = w_m_arch_ready ;

end
endgenerate

//----------------------------------------------------

always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_arch_fwd_rs_mdata_arlen    <= 'd0;
        r_arch_fwd_rs_mdata_araddr   <= 'd0;

    end else begin
        if (w_m_arch_start_valid & I_M_ARREADY_RS) begin
            if(w_aou_split_tr_s_arch_rs_mdata_arlen > I_MAX_ARBURSTLEN)
                r_arch_fwd_rs_mdata_arlen <= w_aou_split_tr_s_arch_rs_mdata_arlen - I_MAX_ARBURSTLEN ; // + 1 to actual left transaction count
            else
                r_arch_fwd_rs_mdata_arlen <= 0; 
            r_arch_fwd_rs_mdata_araddr  <= w_aou_split_tr_s_arch_rs_mdata_araddr ;

        end else if(I_M_ARREADY_RS & (|r_arch_fwd_rs_mdata_arlen)) begin
            if(r_arch_fwd_rs_mdata_arlen > I_MAX_ARBURSTLEN)
                r_arch_fwd_rs_mdata_arlen <= r_arch_fwd_rs_mdata_arlen - I_MAX_ARBURSTLEN - 1;
            else
                r_arch_fwd_rs_mdata_arlen <= 0; 
        end
    end
end

//----------------------------------------------------
assign w_splitter_input_araddr = (w_m_arch_start_valid) ? w_aou_split_tr_s_arch_rs_mdata_araddr[11:0] : r_cur_araddr;
assign w_m_arch_working = (O_M_ARVALID_RS & (I_M_ARREADY_RS & w_arch_no_stop)) | (r_arch_fwd_rs_mdata_arlen != 0) ;

AOU_AXI_SPLIT_ADDRGEN #(
    .AXI_LEN_WD      (LEN_WD)
) u_aou_axi_split_addrgen_ar
(
    .I_AXI_AXADDR ( w_splitter_input_araddr[11:0] ),
    .I_AXI_AXSIZE ( O_M_ARSIZE_RS       ),
    .I_AXI_AXLEN  ( O_M_ARLEN_RS        ),

    .O_AXI_AXADDR ( w_next_araddr    )
);

always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_cur_araddr <= 'd0;
    end else begin
        if (w_m_arch_working & I_M_ARREADY_RS) begin
            r_cur_araddr <= w_next_araddr;
        end

    end
end

assign O_M_ARADDR_RS[ADDR_WD-1:12] = (w_m_arch_start_valid) ? w_aou_split_tr_s_arch_rs_mdata_araddr[ADDR_WD-1:12] : r_arch_fwd_rs_mdata_araddr[ADDR_WD-1:12];
assign O_M_ARADDR_RS[11:0]         = w_splitter_input_araddr;

assign O_M_ARLEN_RS                = (w_m_arch_start_valid) ? ((w_aou_split_tr_s_arch_rs_mdata_arlen > I_MAX_ARBURSTLEN) ? I_MAX_ARBURSTLEN : w_aou_split_tr_s_arch_rs_mdata_arlen) :
                                  (r_arch_fwd_rs_mdata_arlen > I_MAX_ARBURSTLEN) ? I_MAX_ARBURSTLEN : (r_arch_fwd_rs_mdata_arlen - 1);

assign w_m_arch_start_valid     = (w_aou_split_tr_s_arch_rs_mvalid & w_arch_no_stop) & (r_arch_fwd_rs_mdata_arlen == 0);
assign w_m_arch_next_valid      = (r_arch_fwd_rs_mdata_arlen != 0);

assign O_M_ARVALID_RS = w_m_arch_start_valid | w_m_arch_next_valid;
assign w_m_arch_ready = I_M_ARREADY_RS & ((w_m_arch_start_valid & (w_aou_split_tr_s_arch_rs_mdata_arlen <= I_MAX_ARBURSTLEN)) | 
                                       (w_m_arch_next_valid & (r_arch_fwd_rs_mdata_arlen <= I_MAX_ARBURSTLEN + 1)));

//----------------------------------------------------
wire [ADDR_WD-1:0]  w_araddr_align;
wire [ADDR_WD-1:0]  w_araddr_cnt;
wire [ADDR_WD-1:0]  w_rresp_err_araddr;

assign w_araddr_align = O_M_ARADDR_RS & ~((1<< O_M_ARSIZE_RS)-1);

AOU_SPLIT_RD_PENDING_INFO #(
    .AXI_ID_WD                  ( ID_WD-2               ),
    .AXI_LEN_WD                 ( LEN_WD                ),
    .AXI_ADDR_WD                ( ADDR_WD               ),
    .RD_MO_CNT                  ( RD_MO_CNT             )
) u_aou_split_tr_arch
(
    .I_CLK                      ( I_CLK                 ),
    .I_RESETN                   ( I_RESETN              ), 

    .I_AXI_ArId                 ( O_M_ARID_RS[ID_WD-1:2]), 
    .I_AXI_ArLen                ( w_arch_split_tr_cnt   ),
    .I_AXI_MuxId                ( O_M_ARID_RS[1:0]      ),
    .I_AXI_ArSize               ( O_M_ARSIZE_RS         ),
    .I_AXI_ArAddr_align         ( w_araddr_align        ),
    .I_AXI_ArValid              ( w_m_arch_start_valid  ),
    .I_AXI_ArReady              ( I_M_ARREADY_RS        ),
    .O_AR_Slot_Available_Flag   ( w_arch_no_stop        ),  

    .I_AXI_RId                  ( I_M_RID_RS            ),
    .I_AXI_RLast                ( I_M_RLAST_RS          ),
    .I_AXI_RValid               ( I_M_RVALID_RS         ),
    .I_AXI_RReady               ( O_M_RREADY_RS         ),

    .O_CUR_ARADDR               ( w_rresp_err_araddr    ),
    .O_ReorderBuf_MValid        ( O_S_RLAST_RS          ),
    .O_ReorderBuf_MData         ( {O_S_ADDR_CNT_RS, O_S_RID_RS[1:0]} ),

    .O_DEST_TABLE_ID_ERR        ( O_DEST_TABLE_RID_ERR  )

);
assign O_SPLIT_MISMATCH_RID = I_M_RID_RS;

assign O_RRESP_ERR_ADDR = O_RRESP_ERR ? w_rresp_err_araddr : 'b0;
assign O_RRESP_ERR_ID = O_RRESP_ERR ? O_S_RID_RS[ID_WD-1:2] : 'b0;
assign O_RRESP_ERR_RRESP = O_RRESP_ERR ? I_M_RRESP_RS : 'b0;
assign O_RRESP_ERR = I_M_RVALID_RS & O_M_RREADY_RS & (|I_M_RRESP_RS);

//----------------------------------------------------
// AW transaction splitter
//----------------------------------------------------
assign w_awch_fwd_rs_sdata = {
    I_S_AWID,
    I_S_AWADDR,
    I_S_AWLEN,
    I_S_AWSIZE,
    I_S_AWBURST,
    I_S_AWLOCK,
    I_S_AWCACHE,
    I_S_AWPROT,
    I_S_AWQOS
};

assign  O_S_AWREADY = w_s_awready;

AOU_ISO_RS #(
    .DATA_WIDTH ( AXI_AWCH_PAYLOAD_WD  )
) u_aou_fwd_rs_awch
(
   // global interconnect inputs
   .I_RESETN( I_RESETN                      ),
   .I_CLK   ( I_CLK                         ),

   // inputs
   .I_SVALID( I_S_AWVALID                   ),
   .O_SREADY( w_s_awready                   ),
   .I_SDATA ( w_awch_fwd_rs_sdata           ),

   // outputs
   .I_MREADY( w_m_awch_ready                ),
   .O_MVALID( w_awch_fwd_rs_mvalid          ),
   .O_MDATA ( w_awch_fwd_rs_mdata           )
);

assign {O_M_AWID_RS,
        w_awch_fwd_rs_mdata_awaddr,
        w_awch_fwd_rs_mdata_awlen,
        O_M_AWSIZE_RS,
        O_M_AWBURST_RS,
        O_M_AWLOCK_RS, 
        O_M_AWCACHE_RS,
        O_M_AWPROT_RS, 
        O_M_AWQOS_RS} = w_awch_fwd_rs_mdata;

//----------------------------------------------------
assign w_wch_fwd_rs_sdata = {
    I_S_WDATA,
    I_S_WSTRB,
    I_S_WLAST
};

AOU_ISO_RS #(
    .DATA_WIDTH ( AXI_WCH_PAYLOAD_WD  )
) u_aou_fwd_rs_wch
(
   // global interconnect inputs
   .I_RESETN( I_RESETN                     ),
   .I_CLK   ( I_CLK                        ),

   // inputs
   .I_SVALID( I_S_WVALID                   ),
   .O_SREADY( O_S_WREADY                   ),
   .I_SDATA ( w_wch_fwd_rs_sdata           ),

   // outputs
   .I_MREADY( w_m_wch_ready                ),
   .O_MVALID( w_wch_fwd_rs_mvalid          ),
   .O_MDATA ( w_wch_fwd_rs_mdata           )
);

assign {O_M_WDATA_RS,
        O_M_WSTRB_RS,
        w_wch_fwd_rs_mdata_wlast
} = w_wch_fwd_rs_mdata;

//----------------------------------------------------
assign w_fc_m_awready = w_aw_no_stop & I_M_AWREADY_RS;
assign w_splitter_input_awaddr = (w_m_awch_start_valid) ? w_awch_fwd_rs_mdata_awaddr[11:0] : r_cur_awaddr;
assign w_m_awch_working = (O_M_AWVALID_RS & w_fc_m_awready) | (r_awch_fwd_rs_mdata_awlen != 0) ;

AOU_AXI_SPLIT_ADDRGEN #(
    .AXI_LEN_WD      (LEN_WD)
) u_aou_axi_split_addrgen_aw
(
    .I_AXI_AXADDR ( w_splitter_input_awaddr[11:0] ),
    .I_AXI_AXSIZE ( O_M_AWSIZE_RS       ),
    .I_AXI_AXLEN  ( {LEN_WD{1'b0}}   ),

    .O_AXI_AXADDR ( w_next_awaddr    )
);

always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_cur_awaddr <= 'd0;
    end else begin
        if (w_m_awch_working & O_M_WVALID_RS & I_M_WREADY_RS) begin
            r_cur_awaddr <= w_next_awaddr;
        end

    end
end

//----------------------------------------------------
assign w_m_awch_start_valid = w_aw_no_stop & w_wch_fwd_rs_mvalid & w_awch_fwd_rs_mvalid & (r_awch_fwd_rs_mdata_awlen == 0);
assign w_m_awch_next_valid  = w_wch_fwd_rs_mvalid & (r_awch_fwd_rs_mdata_awlen >= 1) & (r_cur_wr_beatcnt == 0);

assign w_m_awch_en = w_m_awch_start_valid | w_m_awch_next_valid;
assign O_M_AWVALID_RS = w_m_awch_en & I_M_WREADY_RS;
assign w_m_awch_ready = O_M_WVALID_RS & I_M_WREADY_RS & O_M_WLAST_RS & 
(
(w_awch_fwd_rs_mdata_awlen == 'd0) |
((w_awch_fwd_rs_mdata_awlen >= 'd1) & (r_awch_fwd_rs_mdata_awlen == 'd1))
)
;
always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_awch_fwd_rs_mdata_awlen    <= 'd0;
        r_awch_fwd_rs_mdata_awaddr   <= 'd0;

    end else begin
        if (w_m_awch_start_valid & w_fc_m_awready & I_M_WREADY_RS) begin
            r_awch_fwd_rs_mdata_awlen   <= w_awch_fwd_rs_mdata_awlen  ;
            r_awch_fwd_rs_mdata_awaddr  <= w_awch_fwd_rs_mdata_awaddr ;

        end else if(O_M_WVALID_RS & I_M_WREADY_RS & (|r_awch_fwd_rs_mdata_awlen)) begin
            r_awch_fwd_rs_mdata_awlen <= r_awch_fwd_rs_mdata_awlen - 1;
        end
    end
end

always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_cur_wr_beatcnt <= 'd0;
    end else begin
        if (O_M_AWVALID_RS & w_fc_m_awready) begin
            if(I_MAX_AWBURSTLEN == 0)
                r_cur_wr_beatcnt <= 'd0;
            else
                r_cur_wr_beatcnt <= 'd1;
        end else if(O_M_WVALID_RS & I_M_WREADY_RS ) begin
            if(r_cur_wr_beatcnt >= I_MAX_AWBURSTLEN)
                r_cur_wr_beatcnt <= 'd0;
            else
                r_cur_wr_beatcnt <= r_cur_wr_beatcnt + 1;
        end
    end
end

//----------------------------------------------------
assign O_M_AWADDR_RS[ADDR_WD-1:12] =  (w_m_awch_start_valid) ? w_awch_fwd_rs_mdata_awaddr[ADDR_WD-1:12] : r_awch_fwd_rs_mdata_awaddr[ADDR_WD-1:12];
assign O_M_AWADDR_RS[11:0] =  w_splitter_input_awaddr;

assign O_M_AWLEN_RS        =  (w_m_awch_start_valid) ? ((w_awch_fwd_rs_mdata_awlen > I_MAX_AWBURSTLEN) ? I_MAX_AWBURSTLEN : w_awch_fwd_rs_mdata_awlen) :
                           (r_awch_fwd_rs_mdata_awlen > I_MAX_AWBURSTLEN) ? I_MAX_AWBURSTLEN : 
                                                                    (r_awch_fwd_rs_mdata_awlen - 1) ;

assign w_m_wch_ready    = w_m_awch_working & I_M_WREADY_RS & w_wch_fwd_rs_mvalid;
assign O_M_WVALID_RS       = w_m_awch_working & w_wch_fwd_rs_mvalid;
assign O_M_WLAST_RS        = (O_M_AWVALID_RS & w_fc_m_awready & (O_M_AWLEN_RS == 'd0)) |
                          (~(O_M_AWVALID_RS & w_fc_m_awready) & ((r_awch_fwd_rs_mdata_awlen == 'd1) | (r_cur_wr_beatcnt == I_MAX_AWBURSTLEN)));

wire [ADDR_WD-1:0] w_bresp_err_awaddr;

//----------------------------------------------------
AOU_SPLIT_WR_PENDING_INFO #(
    .AXI_ID_WD                  ( ID_WD -2              ),
    .AXI_LEN_WD                 ( LEN_WD                ),
    .AXI_ADDR_WD                ( ADDR_WD               ),
    .WR_MO_CNT                  ( WR_MO_CNT             )
) u_aou_split_tr_awch
(
    .I_CLK                      ( I_CLK                 ),
    .I_RESETN                   ( I_RESETN              ), 
 
    .I_AXI_AwId                 ( O_M_AWID_RS[ID_WD-1:2]),
    .I_AXI_MuxId                ( O_M_AWID_RS[1:0]      ), 
    .I_AXI_AwAddr               ( O_M_AWADDR_RS         ),
    .I_AXI_AwLen                ( w_awch_split_tr_cnt   ),
    .I_AXI_AwValid              ( w_m_awch_start_valid & O_M_WVALID_RS),
    .I_AXI_AwReady              ( I_M_WREADY_RS         ),

    .I_AXI_BId                  ( {I_M_BRESP_RS, I_M_BID_RS}),
    .I_AXI_BValid               ( w_fc_m_bvalid         ),
    .I_AXI_BReady               ( O_M_BREADY_RS         ),
    .O_AW_Slot_Available_Flag   ( w_aw_no_stop          ),  

    .O_CUR_AWADDR               ( w_bresp_err_awaddr    ),
    .O_ReorderBuf_MValid        ( O_S_BVALID            ),
    .O_ReorderBuf_MData         ( {O_S_BRESP, O_S_BID}  ),

    .O_DEST_TABLE_ID_ERR        ( O_DEST_TABLE_BID_ERR  )

);
assign O_SPLIT_MISMATCH_BID = I_M_BID_RS;

assign O_BRESP_ERR_ADDR     = O_BRESP_ERR ? w_bresp_err_awaddr : 'b0;
assign O_BRESP_ERR_ID       = O_BRESP_ERR ? I_M_BID_RS : '0;
assign O_BRESP_ERR_BRESP    = O_BRESP_ERR ? I_M_BRESP_RS : '0;
assign O_BRESP_ERR          = w_fc_m_bvalid & O_M_BREADY_RS & (|I_M_BRESP_RS);

assign w_fc_m_bvalid = I_M_BVALID_RS;      
assign O_M_BREADY_RS    = I_S_BREADY;

//----------------------------------------------------

assign O_S_RID_RS[ID_WD-1:2]   = I_M_RID_RS       ;
assign O_S_RDATA_RS            = I_M_RDATA_RS     ;
assign O_S_RRESP_RS            = I_M_RRESP_RS     ;
assign O_S_RVALID_RS           = I_M_RVALID_RS    ;
assign O_M_RREADY_RS           = I_S_RREADY_RS    ;

//----------------------------------------------------

endmodule
