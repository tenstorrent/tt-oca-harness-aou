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
//  Module     : AOU_AXI4MUX_3X1_TOP
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AXI4MUX_3X1_TOP #(
    parameter   DATA_WD   = 512,
    parameter   ADDR_WD   = 64,
    parameter   ID_WD     = 10,
    parameter   STRB_WD   = DATA_WD / 8,
    parameter   LEN_WD    = 8,
    parameter   RD_MO_CNT = 64,
    parameter   WR_MO_CNT = 64,
    parameter   AOU_AGG_WCH_FIFO_DEPTH = 16,

    localparam  RD_MO_IDX_WD = $clog2(RD_MO_CNT)
)
(
    input                               I_CLK,
    input                               I_RESETN,

    output reg   [1:0]                  O_S_RDLEN,
    output reg   [ID_WD-1:0]            O_S_RID,
    output reg   [1023:0]               O_S_RDATA,
    output reg   [1:0]                  O_S_RRESP,
    output reg                          O_S_RLAST,
    output reg                          O_S_RVALID,
    input                               I_S_RREADY,

    // CH0 Slave I/F (256 bit)
    input       [ ID_WD-1: 0]           I_S_ARID_0,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR_0,
    input       [ LEN_WD-1: 0]          I_S_ARLEN_0,
    input       [ 2: 0]                 I_S_ARSIZE_0,
    input       [ 1: 0]                 I_S_ARBURST_0,
    input       [ 3: 0]                 I_S_ARCACHE_0,
    input       [ 2: 0]                 I_S_ARPROT_0,
    input                               I_S_ARLOCK_0,
    input       [ 3: 0]                 I_S_ARQOS_0,
    input                               I_S_ARVALID_0,
    output wire                         O_S_ARREADY_0,

    input       [ ID_WD-1: 0]           I_S_AWID_0,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR_0,
    input       [ LEN_WD-1: 0]          I_S_AWLEN_0,
    input       [ 2: 0]                 I_S_AWSIZE_0,
    input       [ 1: 0]                 I_S_AWBURST_0,
    input                               I_S_AWLOCK_0,
    input       [ 3: 0]                 I_S_AWCACHE_0,
    input       [ 2: 0]                 I_S_AWPROT_0,
    input       [ 3: 0]                 I_S_AWQOS_0,
    input                               I_S_AWVALID_0,
    output wire                         O_S_AWREADY_0,

    input       [ 255 : 0]              I_S_WDATA_0,
    input       [ 31  : 0]              I_S_WSTRB_0,
    input                               I_S_WLAST_0,
    input                               I_S_WVALID_0,
    output                              O_S_WREADY_0,

    output wire [ ID_WD-1: 0]           O_S_BID_0,
    output wire [ 1: 0]                 O_S_BRESP_0,
    output wire                         O_S_BVALID_0,
    input                               I_S_BREADY_0,

    // CH1 Slave I/F (512bit)
    input       [ ID_WD-1: 0]           I_S_ARID_1,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR_1,
    input       [ LEN_WD-1: 0]          I_S_ARLEN_1,
    input       [ 2: 0]                 I_S_ARSIZE_1,
    input       [ 1: 0]                 I_S_ARBURST_1,
    input       [ 3: 0]                 I_S_ARCACHE_1,
    input       [ 2: 0]                 I_S_ARPROT_1,
    input                               I_S_ARLOCK_1,
    input       [ 3: 0]                 I_S_ARQOS_1,
    input                               I_S_ARVALID_1,
    output wire                         O_S_ARREADY_1,

    input       [ ID_WD-1: 0]           I_S_AWID_1,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR_1,
    input       [ LEN_WD-1: 0]          I_S_AWLEN_1,
    input       [ 2: 0]                 I_S_AWSIZE_1,
    input       [ 1: 0]                 I_S_AWBURST_1,
    input                               I_S_AWLOCK_1,
    input       [ 3: 0]                 I_S_AWCACHE_1,
    input       [ 2: 0]                 I_S_AWPROT_1,
    input       [ 3: 0]                 I_S_AWQOS_1,
    input                               I_S_AWVALID_1,
    output wire                         O_S_AWREADY_1,

    input       [ 511 : 0]              I_S_WDATA_1,
    input       [ 63: 0]                I_S_WSTRB_1,  //WSTRB width = wdata width / 8
    input                               I_S_WLAST_1,
    input                               I_S_WVALID_1,
    output wire                         O_S_WREADY_1,

    output wire [ ID_WD-1: 0]           O_S_BID_1,
    output wire [ 1: 0]                 O_S_BRESP_1,
    output wire                         O_S_BVALID_1,
    input                               I_S_BREADY_1,

    // CH2 Slave I/F (1024bit)
    input       [ ID_WD-1: 0]           I_S_ARID_2,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR_2,
    input       [ LEN_WD-1: 0]          I_S_ARLEN_2,
    input       [ 2: 0]                 I_S_ARSIZE_2,
    input       [ 1: 0]                 I_S_ARBURST_2,
    input       [ 3: 0]                 I_S_ARCACHE_2,
    input       [ 2: 0]                 I_S_ARPROT_2,
    input                               I_S_ARLOCK_2,
    input       [ 3: 0]                 I_S_ARQOS_2,
    input                               I_S_ARVALID_2,
    output wire                         O_S_ARREADY_2,

    input       [ ID_WD-1: 0]           I_S_AWID_2,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR_2,
    input       [ LEN_WD-1: 0]          I_S_AWLEN_2,
    input       [ 2: 0]                 I_S_AWSIZE_2,
    input       [ 1: 0]                 I_S_AWBURST_2,
    input                               I_S_AWLOCK_2,
    input       [ 3: 0]                 I_S_AWCACHE_2,
    input       [ 2: 0]                 I_S_AWPROT_2,
    input       [ 3: 0]                 I_S_AWQOS_2,
    input                               I_S_AWVALID_2,
    output wire                         O_S_AWREADY_2,

    input       [ 1023: 0]              I_S_WDATA_2,
    input       [ 127: 0]               I_S_WSTRB_2,
    input                               I_S_WLAST_2,
    input                               I_S_WVALID_2,
    output wire                         O_S_WREADY_2,

    output wire [ ID_WD-1: 0]           O_S_BID_2,
    output wire [ 1: 0]                 O_S_BRESP_2,
    output wire                         O_S_BVALID_2,
    input                               I_S_BREADY_2,

    // Master I/F (512bit)
    output wire [ ID_WD-1: 0]           O_M_ARID,
    output wire [ ADDR_WD-1: 0]         O_M_ARADDR,
    output wire [ LEN_WD-1: 0]          O_M_ARLEN,
    output wire [ 2: 0]                 O_M_ARSIZE,
    output wire [ 1: 0]                 O_M_ARBURST,
    output wire [ 3: 0]                 O_M_ARCACHE,
    output wire [ 2: 0]                 O_M_ARPROT,
    output wire                         O_M_ARLOCK,
    output       [ 3: 0]                O_M_ARQOS,
    output wire                         O_M_ARVALID,
    input                               I_M_ARREADY,

    input       [ ID_WD-1: 0]           I_M_RID,
    input       [ DATA_WD-1: 0]         I_M_RDATA,
    input       [ 1: 0]                 I_M_RRESP,
    input                               I_M_RLAST,
    input                               I_M_RVALID,
    output wire                         O_M_RREADY,

    output wire [ ID_WD-1: 0]           O_M_AWID,
    output wire [ ADDR_WD-1: 0]         O_M_AWADDR,
    output wire [ LEN_WD-1: 0]          O_M_AWLEN,
    output wire [ 2: 0]                 O_M_AWSIZE,
    output wire [ 1: 0]                 O_M_AWBURST,
    output wire                         O_M_AWLOCK,
    output wire [ 3: 0]                 O_M_AWCACHE,
    output wire [ 2: 0]                 O_M_AWPROT,
    output      [ 3: 0]                 O_M_AWQOS,
    output wire                         O_M_AWVALID,
    input                               I_M_AWREADY,

    output wire [ DATA_WD-1: 0]         O_M_WDATA,
    output wire [ STRB_WD-1: 0]         O_M_WSTRB,
    output wire                         O_M_WLAST,
    output wire                         O_M_WVALID,
    input                               I_M_WREADY,

    input       [ ID_WD-1: 0]           I_M_BID,
    input       [ 1: 0]                 I_M_BRESP,
    input                               I_M_BVALID,
    output wire                         O_M_BREADY,

    input       [LEN_WD -1: 0]          I_MAX_AWBURSTLEN,
    input       [LEN_WD -1: 0]          I_MAX_ARBURSTLEN,

    input                               I_AXI_AGGREGATOR_EN,

    output      [ ID_WD-1:0]            O_BRESP_ERR_ID,
    output      [ ADDR_WD-1:0]          O_BRESP_ERR_ADDR,
    output      [ 1 :0]                 O_BRESP_ERR_BRESP,
    output                              O_BRESP_ERR,

    output      [ ID_WD-1:0]            O_RRESP_ERR_ID,
    output      [ ADDR_WD-1:0]          O_RRESP_ERR_ADDR,
    output      [ 1 :0]                 O_RRESP_ERR_RRESP,
    output                              O_RRESP_ERR,

    output      [ ID_WD-1: 0]           O_SPLIT_MISMATCH_BID,
    output      [ ID_WD-1: 0]           O_SPLIT_MISMATCH_RID, 
    output                              O_SPLIT_BID_MISMATCH_ERROR,
    output                              O_SPLIT_RID_MISMATCH_ERROR,

    output      [ ID_WD-1: 0]           O_AGGRE_MISMATCH_RID, 
    output                              O_AGGRE_RID_MISMATCH_ERROR,

    output      [ ID_WD-1: 0]           O_DOWN1024_MISMATCH_RID, 
    output                              O_DOWN1024_RID_MISMATCH_ERROR,

    output      [ ID_WD-1: 0]           O_DOWN512_MISMATCH_RID, 
    output                              O_DOWN512_RID_MISMATCH_ERROR

);

//========================================================================
//                      wire for aggregator
//========================================================================
wire [ ID_WD-1: 0]           o_m_awid;
wire [ ADDR_WD-1: 0]         o_m_awaddr;
wire [ LEN_WD-1: 0]          o_m_awlen;
wire [ 2: 0]                 o_m_awsize;
wire [ 1: 0]                 o_m_awburst;
wire                         o_m_awlock;
wire [ 3: 0]                 o_m_awcache;
wire [ 2: 0]                 o_m_awprot;
wire [ 3: 0]                 o_m_awqos;
wire                         o_m_awvalid;
wire                         o_s_awready;

wire [ DATA_WD-1: 0]         o_m_wdata;
wire [ STRB_WD-1: 0]         o_m_wstrb;
wire                         o_m_wlast;
wire                         o_m_wvalid;
wire                         o_s_wready;

wire [ID_WD-1: 0]            o_m_arid;    
wire [ADDR_WD-1: 0]          o_m_araddr; 
wire [LEN_WD-1: 0]           o_m_arlen;  
wire [2:0]                   o_m_arsize; 
wire [1:0]                   o_m_arburst;
wire [3:0]                   o_m_arcache;
wire [2:0]                   o_m_arprot; 
wire                         o_m_arlock; 
wire [3:0]                   o_m_arqos; 
wire                         o_m_arvalid;
wire                         i_m_arready;
                                        
wire [ID_WD-1:0]             i_m_rid;    
wire [DATA_WD-1:0]           i_m_rdata;  
wire [1:0]                   i_m_rresp;  
wire                         i_m_rlast;  
wire                         i_m_rvalid; 
wire                         o_m_rready; 

//========================================================================
//                      wire for aggregator muxing
//========================================================================

wire [ ID_WD-1: 0]           w_aggregator_awid;
wire [ ADDR_WD-1: 0]         w_aggregator_awaddr;
wire [ LEN_WD-1: 0]          w_aggregator_awlen;
wire [ 2: 0]                 w_aggregator_awsize;
wire [ 1: 0]                 w_aggregator_awburst;
wire                         w_aggregator_awlock;
wire [ 3: 0]                 w_aggregator_awcache;
wire [ 2: 0]                 w_aggregator_awprot;
wire [ 3: 0]                 w_aggregator_awqos;
wire                         w_aggregator_m_awvalid;
wire                         w_aggregator_m_awready;
wire                         w_aggregator_s_awvalid;
wire                         w_aggregator_s_awready;

wire [ DATA_WD-1: 0]         w_aggregator_wdata;
wire [ STRB_WD-1: 0]         w_aggregator_wstrb;
wire                         w_aggregator_wlast;
wire                         w_aggregator_m_wvalid;
wire                         w_aggregator_m_wready;
wire                         w_aggregator_s_wvalid;
wire                         w_aggregator_s_wready;

wire [ID_WD-1: 0]            w_aggregator_arid;    
wire [ADDR_WD-1: 0]          w_aggregator_araddr; 
wire [LEN_WD-1: 0]           w_aggregator_arlen;  
wire [2:0]                   w_aggregator_arsize; 
wire [1:0]                   w_aggregator_arburst;
wire [3:0]                   w_aggregator_arcache;
wire [2:0]                   w_aggregator_arprot; 
wire                         w_aggregator_arlock; 
wire [3:0]                   w_aggregator_arqos; 
wire                         w_aggregator_m_arvalid;
wire                         w_aggregator_m_arready;
wire                         w_aggregator_s_arvalid;
wire                         w_aggregator_s_arready;

wire [ID_WD-1:0]             w_aggregator_rid;    
wire [DATA_WD-1:0]           w_aggregator_rdata;  
wire [1:0]                   w_aggregator_rresp;  
wire                         w_aggregator_rlast;  
wire                         w_aggregator_m_rvalid; 
wire                         w_aggregator_m_rready; 
wire                         w_aggregator_s_rvalid; 
wire                         w_aggregator_s_rready;

//========================================================================

wire [ ID_WD+1: 0]           O_SPLIT_ARID;
wire [ ADDR_WD-1: 0]         O_SPLIT_ARADDR;
wire [ LEN_WD-1: 0]          O_SPLIT_ARLEN;
wire [ 2: 0]                 O_SPLIT_ARSIZE;
wire [ 1: 0]                 O_SPLIT_ARBURST;
wire [ 3: 0]                 O_SPLIT_ARCACHE;
wire [ 2: 0]                 O_SPLIT_ARPROT;
wire                         O_SPLIT_ARLOCK;
wire [ 3: 0]                 O_SPLIT_ARQOS;
wire                         O_SPLIT_ARVALID;
wire                         I_SPLIT_ARREADY;

wire [ ID_WD+1: 0]           I_SPLIT_RID;
wire [ DATA_WD-1: 0]         I_SPLIT_RDATA;
wire [ 1: 0]                 I_SPLIT_RRESP;
wire                         I_SPLIT_RLAST;
wire [ADDR_WD-1:0]           I_SPLIT_ADDR_CNT;
wire                         I_SPLIT_RVALID;
wire                         O_SPLIT_RREADY;


wire [ ID_WD+1: 0]           O_SPLIT_AWID;
wire [ ADDR_WD-1: 0]         O_SPLIT_AWADDR;
wire [ LEN_WD-1: 0]          O_SPLIT_AWLEN;
wire [ 2: 0]                 O_SPLIT_AWSIZE;
wire [ 1: 0]                 O_SPLIT_AWBURST;
wire                         O_SPLIT_AWLOCK;
wire [ 3: 0]                 O_SPLIT_AWCACHE;
wire [ 2: 0]                 O_SPLIT_AWPROT;
wire [ 3: 0]                 O_SPLIT_AWQOS;
wire                         O_SPLIT_AWVALID;
wire                         I_SPLIT_AWREADY;

wire [ DATA_WD-1: 0]         O_SPLIT_WDATA;
wire [ STRB_WD-1: 0]         O_SPLIT_WSTRB;
wire                         O_SPLIT_WLAST;
wire                         O_SPLIT_WVALID;
wire                         I_SPLIT_WREADY;

wire [ ID_WD+1: 0]           I_SPLIT_BID;
wire [ 1: 0]                 I_SPLIT_BRESP;
wire                         I_SPLIT_BVALID;
wire                         O_SPLIT_BREADY;

wire [ ID_WD+1: 0]           I_SPLIT_BID_RS;
wire [ 1: 0]                 I_SPLIT_BRESP_RS;
wire                         I_SPLIT_BVALID_RS;
wire                         O_SPLIT_BREADY_RS;

wire [ ID_WD-1: 0]           O_S_RID_0;
wire [ 255: 0]               O_S_RDATA_0;
wire [ 1: 0]                 O_S_RRESP_0;
wire                         O_S_RLAST_0;
wire                         O_S_RVALID_0;
wire                         I_S_RREADY_0;

wire [ ID_WD-1: 0]           O_S_RID_1;
wire [ 511: 0]               O_S_RDATA_1;
wire [ 1: 0]                 O_S_RRESP_1;
wire                         O_S_RLAST_1;
wire                         O_S_RVALID_1;
wire                         I_S_RREADY_1;

wire [ ID_WD-1: 0]           O_S_RID_2;
wire [ 1023: 0]              O_S_RDATA_2;
wire [ 1: 0]                 O_S_RRESP_2;
wire                         O_S_RLAST_2;
wire                         O_S_RVALID_2;
wire                         I_S_RREADY_2;

//-----------------------------------------------------------------------------
localparam AXIM_RCH_1024_PAYLOAD_WD = ID_WD + 1024 + 2 + 1; //RESP + LAST

logic [ID_WD-1:0]                                                           w_aou_tx_axi_s_1024_rid_rs;
logic [1024-1:0]                                                            w_aou_tx_axi_s_1024_rdata_rs;
logic [1:0]                                                                 w_aou_tx_axi_s_1024_rresp_rs;
logic                                                                       w_aou_tx_axi_s_1024_rlast_rs;
logic                                                                       w_aou_tx_axi_s_1024_rvalid_rs;
logic                                                                       w_aou_tx_axi_s_1024_rready_rs;

logic [AXIM_RCH_1024_PAYLOAD_WD-1:0]                                        w_aou_tx_axi_s_1024_rch_sdata;
logic [AXIM_RCH_1024_PAYLOAD_WD-1:0]                                        w_aou_tx_axi_s_1024_rch_mdata;

logic                                                                       w_aou_tx_axi_s_1024_rch_svalid;
logic                                                                       w_aou_tx_axi_s_1024_rch_sready;
//-----------------------------------------------------------------------------
localparam AXIM_RCH_512_PAYLOAD_WD = ID_WD + 512 + 2 + 1; //RESP + LAST

logic [ID_WD-1:0]                                                           w_aou_tx_axi_s_512_rid_rs;
logic [512-1:0]                                                             w_aou_tx_axi_s_512_rdata_rs;
logic [1:0]                                                                 w_aou_tx_axi_s_512_rresp_rs;
logic                                                                       w_aou_tx_axi_s_512_rlast_rs;
logic                                                                       w_aou_tx_axi_s_512_rvalid_rs;
logic                                                                       w_aou_tx_axi_s_512_rready_rs;

logic [AXIM_RCH_512_PAYLOAD_WD-1:0]                                         w_aou_tx_axi_s_512_rch_sdata;
logic [AXIM_RCH_512_PAYLOAD_WD-1:0]                                         w_aou_tx_axi_s_512_rch_mdata;

logic                                                                       w_aou_tx_axi_s_512_rch_svalid;
logic                                                                       w_aou_tx_axi_s_512_rch_sready;

//-----------------------------------------------------------------------------

assign I_S_RREADY_0 = I_S_RREADY;
assign I_S_RREADY_1 = I_S_RREADY;
assign I_S_RREADY_2 = I_S_RREADY;

always_comb begin
    case({O_S_RVALID_2, O_S_RVALID_1, O_S_RVALID_0})
        3'b001: begin
            O_S_RDLEN  = 2'b00;
            O_S_RID    = O_S_RID_0;
            O_S_RDATA  = {768'b0, O_S_RDATA_0};
            O_S_RRESP  = O_S_RRESP_0;
            O_S_RLAST  = O_S_RLAST_0;
            O_S_RVALID = O_S_RVALID_0;
        end
        3'b010: begin
            O_S_RDLEN  = 2'b01;
            O_S_RID    = O_S_RID_1;
            O_S_RDATA  = {512'b0, O_S_RDATA_1};
            O_S_RRESP  = O_S_RRESP_1;
            O_S_RLAST  = O_S_RLAST_1;
            O_S_RVALID = O_S_RVALID_1;
        end
        3'b100: begin
            O_S_RDLEN  = 2'b10;
            O_S_RID    = O_S_RID_2;
            O_S_RDATA  = O_S_RDATA_2;
            O_S_RRESP  = O_S_RRESP_2;
            O_S_RLAST  = O_S_RLAST_2;
            O_S_RVALID = O_S_RVALID_2;
        end
        default: begin 
            O_S_RDLEN  = 'd0;
            O_S_RID    = 'd0;
            O_S_RDATA  = 'd0;
            O_S_RRESP  = 'd0;
            O_S_RLAST  = 'd0;
            O_S_RVALID = 'd0;
        end
    endcase
end

//-----------------------------------------------------------------------------
generate

if(DATA_WD == 512) begin

    AOU_AXI4MUX_3X1_512 #(
        .ADDR_WD          ( ADDR_WD          ),
        .ID_WD            ( ID_WD            ),
        .LEN_WD           ( LEN_WD           ),

        .RD_MO_CNT        ( RD_MO_CNT        ),
        .WR_MO_CNT        ( WR_MO_CNT        )
    ) u_aou_axi4mux_3x1
    (
        .I_CLK            ( I_CLK            ),
        .I_RESETN         ( I_RESETN         ),

        .I_S_ARID_0       ( I_S_ARID_0       ),
        .I_S_ARADDR_0     ( I_S_ARADDR_0     ),
        .I_S_ARLEN_0      ( I_S_ARLEN_0      ),
        .I_S_ARSIZE_0     ( I_S_ARSIZE_0     ),
        .I_S_ARBURST_0    ( I_S_ARBURST_0    ),
        .I_S_ARCACHE_0    ( I_S_ARCACHE_0    ),
        .I_S_ARPROT_0     ( I_S_ARPROT_0     ),
        .I_S_ARLOCK_0     ( I_S_ARLOCK_0     ),
        .I_S_ARQOS_0      ( I_S_ARQOS_0      ),
        .I_S_ARVALID_0    ( I_S_ARVALID_0    ),
        .O_S_ARREADY_0    ( O_S_ARREADY_0    ),

        .O_S_RID_0        ( O_S_RID_0   ),
        .O_S_RDATA_0      ( O_S_RDATA_0 ),
        .O_S_RRESP_0      ( O_S_RRESP_0 ),
        .O_S_RLAST_0      ( O_S_RLAST_0 ),
        .O_S_RVALID_0     ( O_S_RVALID_0),
        .I_S_RREADY_0     ( I_S_RREADY_0),

        .I_S_AWID_0       ( I_S_AWID_0       ),
        .I_S_AWADDR_0     ( I_S_AWADDR_0     ),
        .I_S_AWLEN_0      ( I_S_AWLEN_0      ),
        .I_S_AWSIZE_0     ( I_S_AWSIZE_0     ),
        .I_S_AWBURST_0    ( I_S_AWBURST_0    ),
        .I_S_AWLOCK_0     ( I_S_AWLOCK_0     ),
        .I_S_AWCACHE_0    ( I_S_AWCACHE_0    ),
        .I_S_AWPROT_0     ( I_S_AWPROT_0     ),
        .I_S_AWQOS_0      ( I_S_AWQOS_0      ),
        .I_S_AWVALID_0    ( I_S_AWVALID_0    ),
        .O_S_AWREADY_0    ( O_S_AWREADY_0    ),

        .I_S_WDATA_0      ( I_S_WDATA_0      ),
        .I_S_WSTRB_0      ( I_S_WSTRB_0      ),
        .I_S_WLAST_0      ( I_S_WLAST_0      ),
        .I_S_WVALID_0     ( I_S_WVALID_0     ),
        .O_S_WREADY_0     ( O_S_WREADY_0     ),

        .O_S_BID_0        ( O_S_BID_0        ),
        .O_S_BRESP_0      ( O_S_BRESP_0      ),
        .O_S_BVALID_0     ( O_S_BVALID_0     ),
        .I_S_BREADY_0     ( I_S_BREADY_0     ),

        .I_S_ARID_1       ( I_S_ARID_1       ),
        .I_S_ARADDR_1     ( I_S_ARADDR_1     ),
        .I_S_ARLEN_1      ( I_S_ARLEN_1      ),
        .I_S_ARSIZE_1     ( I_S_ARSIZE_1     ),
        .I_S_ARBURST_1    ( I_S_ARBURST_1    ),
        .I_S_ARCACHE_1    ( I_S_ARCACHE_1    ),
        .I_S_ARPROT_1     ( I_S_ARPROT_1     ),
        .I_S_ARLOCK_1     ( I_S_ARLOCK_1     ),
        .I_S_ARQOS_1      ( I_S_ARQOS_1      ),
        .I_S_ARVALID_1    ( I_S_ARVALID_1    ),
        .O_S_ARREADY_1    ( O_S_ARREADY_1    ),

        .O_S_RID_1        ( O_S_RID_1   ),
        .O_S_RDATA_1      ( O_S_RDATA_1 ),
        .O_S_RRESP_1      ( O_S_RRESP_1 ),
        .O_S_RLAST_1      ( O_S_RLAST_1 ),
        .O_S_RVALID_1     ( O_S_RVALID_1),
        .I_S_RREADY_1     ( I_S_RREADY_1),

        .I_S_AWID_1       ( I_S_AWID_1       ),
        .I_S_AWADDR_1     ( I_S_AWADDR_1     ),
        .I_S_AWLEN_1      ( I_S_AWLEN_1      ),
        .I_S_AWSIZE_1     ( I_S_AWSIZE_1     ),
        .I_S_AWBURST_1    ( I_S_AWBURST_1    ),
        .I_S_AWLOCK_1     ( I_S_AWLOCK_1     ),
        .I_S_AWCACHE_1    ( I_S_AWCACHE_1    ),
        .I_S_AWPROT_1     ( I_S_AWPROT_1     ),
        .I_S_AWQOS_1      ( I_S_AWQOS_1      ),
        .I_S_AWVALID_1    ( I_S_AWVALID_1    ),
        .O_S_AWREADY_1    ( O_S_AWREADY_1    ),

        .I_S_WDATA_1      ( I_S_WDATA_1      ),
        .I_S_WSTRB_1      ( I_S_WSTRB_1      ),
        .I_S_WLAST_1      ( I_S_WLAST_1      ),
        .I_S_WVALID_1     ( I_S_WVALID_1     ),
        .O_S_WREADY_1     ( O_S_WREADY_1     ),

        .O_S_BID_1        ( O_S_BID_1        ),
        .O_S_BRESP_1      ( O_S_BRESP_1      ),
        .O_S_BVALID_1     ( O_S_BVALID_1     ),
        .I_S_BREADY_1     ( I_S_BREADY_1     ),

        .I_S_ARID_2       ( I_S_ARID_2       ),
        .I_S_ARADDR_2     ( I_S_ARADDR_2     ),
        .I_S_ARLEN_2      ( I_S_ARLEN_2      ),
        .I_S_ARSIZE_2     ( I_S_ARSIZE_2     ),
        .I_S_ARBURST_2    ( I_S_ARBURST_2    ),
        .I_S_ARCACHE_2    ( I_S_ARCACHE_2    ),
        .I_S_ARPROT_2     ( I_S_ARPROT_2     ),
        .I_S_ARLOCK_2     ( I_S_ARLOCK_2     ),
        .I_S_ARQOS_2      ( I_S_ARQOS_2      ),
        .I_S_ARVALID_2    ( I_S_ARVALID_2    ),
        .O_S_ARREADY_2    ( O_S_ARREADY_2    ),

        .O_S_RID_2        ( O_S_RID_2   ),
        .O_S_RDATA_2      ( O_S_RDATA_2 ),
        .O_S_RRESP_2      ( O_S_RRESP_2 ),
        .O_S_RLAST_2      ( O_S_RLAST_2 ),
        .O_S_RVALID_2     ( O_S_RVALID_2),
        .I_S_RREADY_2     ( I_S_RREADY_2),

        .I_S_AWID_2       ( I_S_AWID_2       ),
        .I_S_AWADDR_2     ( I_S_AWADDR_2     ),
        .I_S_AWLEN_2      ( I_S_AWLEN_2      ),
        .I_S_AWSIZE_2     ( I_S_AWSIZE_2     ),
        .I_S_AWBURST_2    ( I_S_AWBURST_2    ),
        .I_S_AWLOCK_2     ( I_S_AWLOCK_2     ),
        .I_S_AWCACHE_2    ( I_S_AWCACHE_2    ),
        .I_S_AWPROT_2     ( I_S_AWPROT_2     ),
        .I_S_AWQOS_2      ( I_S_AWQOS_2      ),
        .I_S_AWVALID_2    ( I_S_AWVALID_2    ),
        .O_S_AWREADY_2    ( O_S_AWREADY_2    ),

        .I_S_WDATA_2      ( I_S_WDATA_2      ),
        .I_S_WSTRB_2      ( I_S_WSTRB_2      ),
        .I_S_WLAST_2      ( I_S_WLAST_2      ),
        .I_S_WVALID_2     ( I_S_WVALID_2     ),
        .O_S_WREADY_2     ( O_S_WREADY_2     ),

        .O_S_BID_2        ( O_S_BID_2        ),
        .O_S_BRESP_2      ( O_S_BRESP_2      ),
        .O_S_BVALID_2     ( O_S_BVALID_2     ),
        .I_S_BREADY_2     ( I_S_BREADY_2     ),

        .O_M_ARID         ( O_SPLIT_ARID     ),
        .O_M_ARADDR       ( O_SPLIT_ARADDR   ),
        .O_M_ARLEN        ( O_SPLIT_ARLEN    ),
        .O_M_ARSIZE       ( O_SPLIT_ARSIZE   ),
        .O_M_ARBURST      ( O_SPLIT_ARBURST  ),
        .O_M_ARCACHE      ( O_SPLIT_ARCACHE  ),
        .O_M_ARPROT       ( O_SPLIT_ARPROT   ),
        .O_M_ARLOCK       ( O_SPLIT_ARLOCK   ),
        .O_M_ARQOS        ( O_SPLIT_ARQOS    ),
        .O_M_ARVALID      ( O_SPLIT_ARVALID  ),
        .I_M_ARREADY      ( I_SPLIT_ARREADY  ),

        .I_M_RID          ( I_SPLIT_RID      ),
        .I_M_RDATA        ( I_SPLIT_RDATA    ),
        .I_M_RRESP        ( I_SPLIT_RRESP    ),
        .I_M_RLAST        ( I_SPLIT_RLAST    ),
        .I_M_ADDR_CNT     ( I_SPLIT_ADDR_CNT ),
        .I_M_RVALID       ( I_SPLIT_RVALID   ),
        .O_M_RREADY       ( O_SPLIT_RREADY   ),

        .O_M_AWID         ( O_SPLIT_AWID     ),
        .O_M_AWADDR       ( O_SPLIT_AWADDR   ),
        .O_M_AWLEN        ( O_SPLIT_AWLEN    ),
        .O_M_AWSIZE       ( O_SPLIT_AWSIZE   ),
        .O_M_AWBURST      ( O_SPLIT_AWBURST  ),
        .O_M_AWLOCK       ( O_SPLIT_AWLOCK   ),
        .O_M_AWCACHE      ( O_SPLIT_AWCACHE  ),
        .O_M_AWPROT       ( O_SPLIT_AWPROT   ),
        .O_M_AWQOS        ( O_SPLIT_AWQOS    ),
        .O_M_AWVALID      ( O_SPLIT_AWVALID  ),
        .I_M_AWREADY      ( I_SPLIT_AWREADY  ),

        .O_M_WDATA        ( O_SPLIT_WDATA    ),
        .O_M_WSTRB        ( O_SPLIT_WSTRB    ),
        .O_M_WLAST        ( O_SPLIT_WLAST    ),
        .O_M_WVALID       ( O_SPLIT_WVALID   ),
        .I_M_WREADY       ( I_SPLIT_WREADY   ),

        .I_M_BID          ( I_SPLIT_BID_RS   ),
        .I_M_BRESP        ( I_SPLIT_BRESP_RS ),
        .I_M_BVALID       ( I_SPLIT_BVALID_RS),
        .O_M_BREADY       ( O_SPLIT_BREADY_RS),

        .O_DOWN1024_MISMATCH_RID        (O_DOWN1024_MISMATCH_RID        ),
        .O_DOWN1024_RID_MISMATCH_ERROR  (O_DOWN1024_RID_MISMATCH_ERROR  )
       
    );

    assign O_DOWN512_MISMATCH_RID       = '0;
    assign O_DOWN512_RID_MISMATCH_ERROR = 1'b0;

end else if (DATA_WD == 1024) begin

    AOU_AXI4MUX_3X1_1024 #(
        .ADDR_WD          ( ADDR_WD          ),
        .ID_WD            ( ID_WD            ),
        .LEN_WD           ( LEN_WD           )
    ) u_aou_axi4mux_3x1
    (
        .I_CLK            ( I_CLK            ),
        .I_RESETN         ( I_RESETN         ),

        .I_S_ARID_0       ( I_S_ARID_0       ),
        .I_S_ARADDR_0     ( I_S_ARADDR_0     ),
        .I_S_ARLEN_0      ( I_S_ARLEN_0      ),
        .I_S_ARSIZE_0     ( I_S_ARSIZE_0     ),
        .I_S_ARBURST_0    ( I_S_ARBURST_0    ),
        .I_S_ARCACHE_0    ( I_S_ARCACHE_0    ),
        .I_S_ARPROT_0     ( I_S_ARPROT_0     ),
        .I_S_ARLOCK_0     ( I_S_ARLOCK_0     ),
        .I_S_ARQOS_0      ( I_S_ARQOS_0      ),
        .I_S_ARVALID_0    ( I_S_ARVALID_0    ),
        .O_S_ARREADY_0    ( O_S_ARREADY_0    ),

        .O_S_RID_0        ( O_S_RID_0   ),
        .O_S_RDATA_0      ( O_S_RDATA_0 ),
        .O_S_RRESP_0      ( O_S_RRESP_0 ),
        .O_S_RLAST_0      ( O_S_RLAST_0 ),
        .O_S_RVALID_0     ( O_S_RVALID_0),
        .I_S_RREADY_0     ( I_S_RREADY_0),

        .I_S_AWID_0       ( I_S_AWID_0       ),
        .I_S_AWADDR_0     ( I_S_AWADDR_0     ),
        .I_S_AWLEN_0      ( I_S_AWLEN_0      ),
        .I_S_AWSIZE_0     ( I_S_AWSIZE_0     ),
        .I_S_AWBURST_0    ( I_S_AWBURST_0    ),
        .I_S_AWLOCK_0     ( I_S_AWLOCK_0     ),
        .I_S_AWCACHE_0    ( I_S_AWCACHE_0    ),
        .I_S_AWPROT_0     ( I_S_AWPROT_0     ),
        .I_S_AWQOS_0      ( I_S_AWQOS_0      ),
        .I_S_AWVALID_0    ( I_S_AWVALID_0    ),
        .O_S_AWREADY_0    ( O_S_AWREADY_0    ),

        .I_S_WDATA_0      ( I_S_WDATA_0      ),
        .I_S_WSTRB_0      ( I_S_WSTRB_0      ),
        .I_S_WLAST_0      ( I_S_WLAST_0      ),
        .I_S_WVALID_0     ( I_S_WVALID_0     ),
        .O_S_WREADY_0     ( O_S_WREADY_0     ),

        .O_S_BID_0        ( O_S_BID_0        ),
        .O_S_BRESP_0      ( O_S_BRESP_0      ),
        .O_S_BVALID_0     ( O_S_BVALID_0     ),
        .I_S_BREADY_0     ( I_S_BREADY_0     ),

        .I_S_ARID_1       ( I_S_ARID_1       ),
        .I_S_ARADDR_1     ( I_S_ARADDR_1     ),
        .I_S_ARLEN_1      ( I_S_ARLEN_1      ),
        .I_S_ARSIZE_1     ( I_S_ARSIZE_1     ),
        .I_S_ARBURST_1    ( I_S_ARBURST_1    ),
        .I_S_ARCACHE_1    ( I_S_ARCACHE_1    ),
        .I_S_ARPROT_1     ( I_S_ARPROT_1     ),
        .I_S_ARLOCK_1     ( I_S_ARLOCK_1     ),
        .I_S_ARQOS_1      ( I_S_ARQOS_1      ),
        .I_S_ARVALID_1    ( I_S_ARVALID_1    ),
        .O_S_ARREADY_1    ( O_S_ARREADY_1    ),

        .O_S_RID_1        ( O_S_RID_1   ),
        .O_S_RDATA_1      ( O_S_RDATA_1 ),
        .O_S_RRESP_1      ( O_S_RRESP_1 ),
        .O_S_RLAST_1      ( O_S_RLAST_1 ),
        .O_S_RVALID_1     ( O_S_RVALID_1),
        .I_S_RREADY_1     ( I_S_RREADY_1),

        .I_S_AWID_1       ( I_S_AWID_1       ),
        .I_S_AWADDR_1     ( I_S_AWADDR_1     ),
        .I_S_AWLEN_1      ( I_S_AWLEN_1      ),
        .I_S_AWSIZE_1     ( I_S_AWSIZE_1     ),
        .I_S_AWBURST_1    ( I_S_AWBURST_1    ),
        .I_S_AWLOCK_1     ( I_S_AWLOCK_1     ),
        .I_S_AWCACHE_1    ( I_S_AWCACHE_1    ),
        .I_S_AWPROT_1     ( I_S_AWPROT_1     ),
        .I_S_AWQOS_1      ( I_S_AWQOS_1      ),
        .I_S_AWVALID_1    ( I_S_AWVALID_1    ),
        .O_S_AWREADY_1    ( O_S_AWREADY_1    ),

        .I_S_WDATA_1      ( I_S_WDATA_1      ),
        .I_S_WSTRB_1      ( I_S_WSTRB_1      ),
        .I_S_WLAST_1      ( I_S_WLAST_1      ),
        .I_S_WVALID_1     ( I_S_WVALID_1     ),
        .O_S_WREADY_1     ( O_S_WREADY_1     ),

        .O_S_BID_1        ( O_S_BID_1        ),
        .O_S_BRESP_1      ( O_S_BRESP_1      ),
        .O_S_BVALID_1     ( O_S_BVALID_1     ),
        .I_S_BREADY_1     ( I_S_BREADY_1     ),

        .I_S_ARID_2       ( I_S_ARID_2       ),
        .I_S_ARADDR_2     ( I_S_ARADDR_2     ),
        .I_S_ARLEN_2      ( I_S_ARLEN_2      ),
        .I_S_ARSIZE_2     ( I_S_ARSIZE_2     ),
        .I_S_ARBURST_2    ( I_S_ARBURST_2    ),
        .I_S_ARCACHE_2    ( I_S_ARCACHE_2    ),
        .I_S_ARPROT_2     ( I_S_ARPROT_2     ),
        .I_S_ARLOCK_2     ( I_S_ARLOCK_2     ),
        .I_S_ARQOS_2      ( I_S_ARQOS_2      ),
        .I_S_ARVALID_2    ( I_S_ARVALID_2    ),
        .O_S_ARREADY_2    ( O_S_ARREADY_2    ),

        .O_S_RID_2        ( O_S_RID_2   ),
        .O_S_RDATA_2      ( O_S_RDATA_2 ),
        .O_S_RRESP_2      ( O_S_RRESP_2 ),
        .O_S_RLAST_2      ( O_S_RLAST_2 ),
        .O_S_RVALID_2     ( O_S_RVALID_2),
        .I_S_RREADY_2     ( I_S_RREADY_2),

        .I_S_AWID_2       ( I_S_AWID_2       ),
        .I_S_AWADDR_2     ( I_S_AWADDR_2     ),
        .I_S_AWLEN_2      ( I_S_AWLEN_2      ),
        .I_S_AWSIZE_2     ( I_S_AWSIZE_2     ),
        .I_S_AWBURST_2    ( I_S_AWBURST_2    ),
        .I_S_AWLOCK_2     ( I_S_AWLOCK_2     ),
        .I_S_AWCACHE_2    ( I_S_AWCACHE_2    ),
        .I_S_AWPROT_2     ( I_S_AWPROT_2     ),
        .I_S_AWQOS_2      ( I_S_AWQOS_2      ),
        .I_S_AWVALID_2    ( I_S_AWVALID_2    ),
        .O_S_AWREADY_2    ( O_S_AWREADY_2    ),

        .I_S_WDATA_2      ( I_S_WDATA_2      ),
        .I_S_WSTRB_2      ( I_S_WSTRB_2      ),
        .I_S_WLAST_2      ( I_S_WLAST_2      ),
        .I_S_WVALID_2     ( I_S_WVALID_2     ),
        .O_S_WREADY_2     ( O_S_WREADY_2     ),

        .O_S_BID_2        ( O_S_BID_2        ),
        .O_S_BRESP_2      ( O_S_BRESP_2      ),
        .O_S_BVALID_2     ( O_S_BVALID_2     ),
        .I_S_BREADY_2     ( I_S_BREADY_2     ),

        .O_M_ARID         ( O_SPLIT_ARID     ),
        .O_M_ARADDR       ( O_SPLIT_ARADDR   ),
        .O_M_ARLEN        ( O_SPLIT_ARLEN    ),
        .O_M_ARSIZE       ( O_SPLIT_ARSIZE   ),
        .O_M_ARBURST      ( O_SPLIT_ARBURST  ),
        .O_M_ARCACHE      ( O_SPLIT_ARCACHE  ),
        .O_M_ARPROT       ( O_SPLIT_ARPROT   ),
        .O_M_ARLOCK       ( O_SPLIT_ARLOCK   ),
        .O_M_ARQOS        ( O_SPLIT_ARQOS    ),
        .O_M_ARVALID      ( O_SPLIT_ARVALID  ),
        .I_M_ARREADY      ( I_SPLIT_ARREADY  ),

        .I_M_RID          ( I_SPLIT_RID      ),
        .I_M_RDATA        ( I_SPLIT_RDATA    ),
        .I_M_RRESP        ( I_SPLIT_RRESP    ),
        .I_M_RLAST        ( I_SPLIT_RLAST    ),
        .I_M_ADDR_CNT     ( I_SPLIT_ADDR_CNT ),
        .I_M_RVALID       ( I_SPLIT_RVALID   ),
        .O_M_RREADY       ( O_SPLIT_RREADY   ),

        .O_M_AWID         ( O_SPLIT_AWID     ),
        .O_M_AWADDR       ( O_SPLIT_AWADDR   ),
        .O_M_AWLEN        ( O_SPLIT_AWLEN    ),
        .O_M_AWSIZE       ( O_SPLIT_AWSIZE   ),
        .O_M_AWBURST      ( O_SPLIT_AWBURST  ),
        .O_M_AWLOCK       ( O_SPLIT_AWLOCK   ),
        .O_M_AWCACHE      ( O_SPLIT_AWCACHE  ),
        .O_M_AWPROT       ( O_SPLIT_AWPROT   ),
        .O_M_AWQOS        ( O_SPLIT_AWQOS    ),
        .O_M_AWVALID      ( O_SPLIT_AWVALID  ),
        .I_M_AWREADY      ( I_SPLIT_AWREADY  ),

        .O_M_WDATA        ( O_SPLIT_WDATA    ),
        .O_M_WSTRB        ( O_SPLIT_WSTRB    ),
        .O_M_WLAST        ( O_SPLIT_WLAST    ),
        .O_M_WVALID       ( O_SPLIT_WVALID   ),
        .I_M_WREADY       ( I_SPLIT_WREADY   ),

        .I_M_BID          ( I_SPLIT_BID_RS   ),
        .I_M_BRESP        ( I_SPLIT_BRESP_RS ),
        .I_M_BVALID       ( I_SPLIT_BVALID_RS),
        .O_M_BREADY       ( O_SPLIT_BREADY_RS)

    );

    assign O_DOWN512_MISMATCH_RID        = '0;
    assign O_DOWN512_RID_MISMATCH_ERROR  = 1'b0;
    assign O_DOWN1024_MISMATCH_RID       = '0;
    assign O_DOWN1024_RID_MISMATCH_ERROR = 1'b0;

end else if (DATA_WD == 256) begin

    AOU_AXI4MUX_3X1_256 #(
        .ADDR_WD          ( ADDR_WD          ),
        .ID_WD            ( ID_WD            ),
        .LEN_WD           ( LEN_WD           ),

        .RD_MO_CNT        ( RD_MO_CNT        ),
        .WR_MO_CNT        ( WR_MO_CNT        )
    ) u_aou_axi4mux_3x1
    (
        .I_CLK            ( I_CLK            ),
        .I_RESETN         ( I_RESETN         ),

        .I_S_ARID_0       ( I_S_ARID_0       ),
        .I_S_ARADDR_0     ( I_S_ARADDR_0     ),
        .I_S_ARLEN_0      ( I_S_ARLEN_0      ),
        .I_S_ARSIZE_0     ( I_S_ARSIZE_0     ),
        .I_S_ARBURST_0    ( I_S_ARBURST_0    ),
        .I_S_ARCACHE_0    ( I_S_ARCACHE_0    ),
        .I_S_ARPROT_0     ( I_S_ARPROT_0     ),
        .I_S_ARLOCK_0     ( I_S_ARLOCK_0     ),
        .I_S_ARQOS_0      ( I_S_ARQOS_0      ),
        .I_S_ARVALID_0    ( I_S_ARVALID_0    ),
        .O_S_ARREADY_0    ( O_S_ARREADY_0    ),

        .O_S_RID_0        ( O_S_RID_0   ),
        .O_S_RDATA_0      ( O_S_RDATA_0 ),
        .O_S_RRESP_0      ( O_S_RRESP_0 ),
        .O_S_RLAST_0      ( O_S_RLAST_0 ),
        .O_S_RVALID_0     ( O_S_RVALID_0),
        .I_S_RREADY_0     ( I_S_RREADY_0),

        .I_S_AWID_0       ( I_S_AWID_0       ),
        .I_S_AWADDR_0     ( I_S_AWADDR_0     ),
        .I_S_AWLEN_0      ( I_S_AWLEN_0      ),
        .I_S_AWSIZE_0     ( I_S_AWSIZE_0     ),
        .I_S_AWBURST_0    ( I_S_AWBURST_0    ),
        .I_S_AWLOCK_0     ( I_S_AWLOCK_0     ),
        .I_S_AWCACHE_0    ( I_S_AWCACHE_0    ),
        .I_S_AWPROT_0     ( I_S_AWPROT_0     ),
        .I_S_AWQOS_0      ( I_S_AWQOS_0      ),
        .I_S_AWVALID_0    ( I_S_AWVALID_0    ),
        .O_S_AWREADY_0    ( O_S_AWREADY_0    ),

        .I_S_WDATA_0      ( I_S_WDATA_0      ),
        .I_S_WSTRB_0      ( I_S_WSTRB_0      ),
        .I_S_WLAST_0      ( I_S_WLAST_0      ),
        .I_S_WVALID_0     ( I_S_WVALID_0     ),
        .O_S_WREADY_0     ( O_S_WREADY_0     ),

        .O_S_BID_0        ( O_S_BID_0        ),
        .O_S_BRESP_0      ( O_S_BRESP_0      ),
        .O_S_BVALID_0     ( O_S_BVALID_0     ),
        .I_S_BREADY_0     ( I_S_BREADY_0     ),

        .I_S_ARID_1       ( I_S_ARID_1       ),
        .I_S_ARADDR_1     ( I_S_ARADDR_1     ),
        .I_S_ARLEN_1      ( I_S_ARLEN_1      ),
        .I_S_ARSIZE_1     ( I_S_ARSIZE_1     ),
        .I_S_ARBURST_1    ( I_S_ARBURST_1    ),
        .I_S_ARCACHE_1    ( I_S_ARCACHE_1    ),
        .I_S_ARPROT_1     ( I_S_ARPROT_1     ),
        .I_S_ARLOCK_1     ( I_S_ARLOCK_1     ),
        .I_S_ARQOS_1      ( I_S_ARQOS_1      ),
        .I_S_ARVALID_1    ( I_S_ARVALID_1    ),
        .O_S_ARREADY_1    ( O_S_ARREADY_1    ),

        .O_S_RID_1        ( O_S_RID_1   ),
        .O_S_RDATA_1      ( O_S_RDATA_1 ),
        .O_S_RRESP_1      ( O_S_RRESP_1 ),
        .O_S_RLAST_1      ( O_S_RLAST_1 ),
        .O_S_RVALID_1     ( O_S_RVALID_1),
        .I_S_RREADY_1     ( I_S_RREADY_1),

        .I_S_AWID_1       ( I_S_AWID_1       ),
        .I_S_AWADDR_1     ( I_S_AWADDR_1     ),
        .I_S_AWLEN_1      ( I_S_AWLEN_1      ),
        .I_S_AWSIZE_1     ( I_S_AWSIZE_1     ),
        .I_S_AWBURST_1    ( I_S_AWBURST_1    ),
        .I_S_AWLOCK_1     ( I_S_AWLOCK_1     ),
        .I_S_AWCACHE_1    ( I_S_AWCACHE_1    ),
        .I_S_AWPROT_1     ( I_S_AWPROT_1     ),
        .I_S_AWQOS_1      ( I_S_AWQOS_1      ),
        .I_S_AWVALID_1    ( I_S_AWVALID_1    ),
        .O_S_AWREADY_1    ( O_S_AWREADY_1    ),

        .I_S_WDATA_1      ( I_S_WDATA_1      ),
        .I_S_WSTRB_1      ( I_S_WSTRB_1      ),
        .I_S_WLAST_1      ( I_S_WLAST_1      ),
        .I_S_WVALID_1     ( I_S_WVALID_1     ),
        .O_S_WREADY_1     ( O_S_WREADY_1     ),

        .O_S_BID_1        ( O_S_BID_1        ),
        .O_S_BRESP_1      ( O_S_BRESP_1      ),
        .O_S_BVALID_1     ( O_S_BVALID_1     ),
        .I_S_BREADY_1     ( I_S_BREADY_1     ),

        .I_S_ARID_2       ( I_S_ARID_2       ),
        .I_S_ARADDR_2     ( I_S_ARADDR_2     ),
        .I_S_ARLEN_2      ( I_S_ARLEN_2      ),
        .I_S_ARSIZE_2     ( I_S_ARSIZE_2     ),
        .I_S_ARBURST_2    ( I_S_ARBURST_2    ),
        .I_S_ARCACHE_2    ( I_S_ARCACHE_2    ),
        .I_S_ARPROT_2     ( I_S_ARPROT_2     ),
        .I_S_ARLOCK_2     ( I_S_ARLOCK_2     ),
        .I_S_ARQOS_2      ( I_S_ARQOS_2      ),
        .I_S_ARVALID_2    ( I_S_ARVALID_2    ),
        .O_S_ARREADY_2    ( O_S_ARREADY_2    ),

        .O_S_RID_2        ( O_S_RID_2   ),
        .O_S_RDATA_2      ( O_S_RDATA_2 ),
        .O_S_RRESP_2      ( O_S_RRESP_2 ),
        .O_S_RLAST_2      ( O_S_RLAST_2 ),
        .O_S_RVALID_2     ( O_S_RVALID_2),
        .I_S_RREADY_2     ( I_S_RREADY_2),

        .I_S_AWID_2       ( I_S_AWID_2       ),
        .I_S_AWADDR_2     ( I_S_AWADDR_2     ),
        .I_S_AWLEN_2      ( I_S_AWLEN_2      ),
        .I_S_AWSIZE_2     ( I_S_AWSIZE_2     ),
        .I_S_AWBURST_2    ( I_S_AWBURST_2    ),
        .I_S_AWLOCK_2     ( I_S_AWLOCK_2     ),
        .I_S_AWCACHE_2    ( I_S_AWCACHE_2    ),
        .I_S_AWPROT_2     ( I_S_AWPROT_2     ),
        .I_S_AWQOS_2      ( I_S_AWQOS_2      ),
        .I_S_AWVALID_2    ( I_S_AWVALID_2    ),
        .O_S_AWREADY_2    ( O_S_AWREADY_2    ),

        .I_S_WDATA_2      ( I_S_WDATA_2      ),
        .I_S_WSTRB_2      ( I_S_WSTRB_2      ),
        .I_S_WLAST_2      ( I_S_WLAST_2      ),
        .I_S_WVALID_2     ( I_S_WVALID_2     ),
        .O_S_WREADY_2     ( O_S_WREADY_2     ),

        .O_S_BID_2        ( O_S_BID_2        ),
        .O_S_BRESP_2      ( O_S_BRESP_2      ),
        .O_S_BVALID_2     ( O_S_BVALID_2     ),
        .I_S_BREADY_2     ( I_S_BREADY_2     ),

        .O_M_ARID         ( O_SPLIT_ARID     ),
        .O_M_ARADDR       ( O_SPLIT_ARADDR   ),
        .O_M_ARLEN        ( O_SPLIT_ARLEN    ),
        .O_M_ARSIZE       ( O_SPLIT_ARSIZE   ),
        .O_M_ARBURST      ( O_SPLIT_ARBURST  ),
        .O_M_ARCACHE      ( O_SPLIT_ARCACHE  ),
        .O_M_ARPROT       ( O_SPLIT_ARPROT   ),
        .O_M_ARLOCK       ( O_SPLIT_ARLOCK   ),
        .O_M_ARQOS        ( O_SPLIT_ARQOS    ),
        .O_M_ARVALID      ( O_SPLIT_ARVALID  ),
        .I_M_ARREADY      ( I_SPLIT_ARREADY  ),

        .I_M_RID          ( I_SPLIT_RID      ),
        .I_M_RDATA        ( I_SPLIT_RDATA    ),
        .I_M_RRESP        ( I_SPLIT_RRESP    ),
        .I_M_RLAST        ( I_SPLIT_RLAST    ),
        .I_M_RVALID       ( I_SPLIT_RVALID   ),
        .O_M_RREADY       ( O_SPLIT_RREADY   ),

        .O_M_AWID         ( O_SPLIT_AWID     ),
        .O_M_AWADDR       ( O_SPLIT_AWADDR   ),
        .O_M_AWLEN        ( O_SPLIT_AWLEN    ),
        .O_M_AWSIZE       ( O_SPLIT_AWSIZE   ),
        .O_M_AWBURST      ( O_SPLIT_AWBURST  ),
        .O_M_AWLOCK       ( O_SPLIT_AWLOCK   ),
        .O_M_AWCACHE      ( O_SPLIT_AWCACHE  ),
        .O_M_AWPROT       ( O_SPLIT_AWPROT   ),
        .O_M_AWQOS        ( O_SPLIT_AWQOS    ),
        .O_M_AWVALID      ( O_SPLIT_AWVALID  ),
        .I_M_AWREADY      ( I_SPLIT_AWREADY  ),

        .O_M_WDATA        ( O_SPLIT_WDATA    ),
        .O_M_WSTRB        ( O_SPLIT_WSTRB    ),
        .O_M_WLAST        ( O_SPLIT_WLAST    ),
        .O_M_WVALID       ( O_SPLIT_WVALID   ),
        .I_M_WREADY       ( I_SPLIT_WREADY   ),

        .I_M_BID          ( I_SPLIT_BID_RS   ),
        .I_M_BRESP        ( I_SPLIT_BRESP_RS ),
        .I_M_BVALID       ( I_SPLIT_BVALID_RS),
        .O_M_BREADY       ( O_SPLIT_BREADY_RS),

        .O_DOWN1024_MISMATCH_RID        (O_DOWN1024_MISMATCH_RID        ),
        .O_DOWN1024_RID_MISMATCH_ERROR  (O_DOWN1024_RID_MISMATCH_ERROR  ),
        
        .O_DOWN512_MISMATCH_RID         (O_DOWN512_MISMATCH_RID         ),
        .O_DOWN512_RID_MISMATCH_ERROR   (O_DOWN512_RID_MISMATCH_ERROR   )

    );

end
endgenerate

AOU_SYNC_FIFO_REG #(
    .FIFO_WIDTH      ( ID_WD + 2 + 2                ),
    .FIFO_DEPTH      ( 2                            )
) u_aou_b_rs
(
    .I_CLK           ( I_CLK                        ),
    .I_RESETN        ( I_RESETN                     ),

    .I_SVALID        ( I_SPLIT_BVALID               ),
    .I_SDATA         ( {I_SPLIT_BRESP, I_SPLIT_BID} ),
    .O_SREADY        ( O_SPLIT_BREADY               ),

    .I_MREADY        ( O_SPLIT_BREADY_RS            ),
    .O_MDATA         ( {I_SPLIT_BRESP_RS, I_SPLIT_BID_RS} ),
    .O_MVALID        ( I_SPLIT_BVALID_RS            ),

    .O_EMPTY_CNT     ( ),
    .O_FULL_CNT      ( )
);

//------------------------------------------------


AOU_AXI_SPLIT_TR #(
    .ADDR_WD          ( ADDR_WD          ),
    .DATA_WD          ( DATA_WD          ),
    .ID_WD            ( ID_WD + 2        ),
    .LEN_WD           ( LEN_WD           ),

    .RD_MO_CNT        ( RD_MO_CNT        ),
    .WR_MO_CNT        ( WR_MO_CNT        )
) u_aou_axi_split_tr
(
    .I_CLK            ( I_CLK            ),
    .I_RESETN         ( I_RESETN         ),

    .I_S_ARID         ( O_SPLIT_ARID     ),
    .I_S_ARADDR       ( O_SPLIT_ARADDR   ),
    .I_S_ARLEN        ( O_SPLIT_ARLEN    ),
    .I_S_ARSIZE       ( O_SPLIT_ARSIZE   ),
    .I_S_ARBURST      ( O_SPLIT_ARBURST  ),
    .I_S_ARCACHE      ( O_SPLIT_ARCACHE  ),
    .I_S_ARPROT       ( O_SPLIT_ARPROT   ),
    .I_S_ARLOCK       ( O_SPLIT_ARLOCK   ),
    .I_S_ARQOS        ( O_SPLIT_ARQOS    ),
    .I_S_ARVALID      ( O_SPLIT_ARVALID  ),
    .O_S_ARREADY      ( I_SPLIT_ARREADY  ),

    .O_S_RID          ( I_SPLIT_RID      ),
    .O_S_RDATA        ( I_SPLIT_RDATA    ),
    .O_S_RRESP        ( I_SPLIT_RRESP    ),
    .O_S_RLAST        ( I_SPLIT_RLAST    ),
    .O_S_ADDR_CNT     ( I_SPLIT_ADDR_CNT ),
    .O_S_RVALID       ( I_SPLIT_RVALID   ),
    .I_S_RREADY       ( O_SPLIT_RREADY   ),

    .I_S_AWID         ( O_SPLIT_AWID     ),
    .I_S_AWADDR       ( O_SPLIT_AWADDR   ),
    .I_S_AWLEN        ( O_SPLIT_AWLEN    ),
    .I_S_AWSIZE       ( O_SPLIT_AWSIZE   ),
    .I_S_AWBURST      ( O_SPLIT_AWBURST  ),
    .I_S_AWLOCK       ( O_SPLIT_AWLOCK   ),
    .I_S_AWCACHE      ( O_SPLIT_AWCACHE  ),
    .I_S_AWPROT       ( O_SPLIT_AWPROT   ),
    .I_S_AWQOS        ( O_SPLIT_AWQOS    ),
    .I_S_AWVALID      ( O_SPLIT_AWVALID  ),
    .O_S_AWREADY      ( I_SPLIT_AWREADY  ),

    .I_S_WDATA        ( O_SPLIT_WDATA    ),
    .I_S_WSTRB        ( O_SPLIT_WSTRB    ),
    .I_S_WLAST        ( O_SPLIT_WLAST    ),
    .I_S_WVALID       ( O_SPLIT_WVALID   ),
    .O_S_WREADY       ( I_SPLIT_WREADY   ),

    .O_S_BID          ( I_SPLIT_BID      ),
    .O_S_BRESP        ( I_SPLIT_BRESP    ),
    .O_S_BVALID       ( I_SPLIT_BVALID   ),
    .I_S_BREADY       ( O_SPLIT_BREADY   ),

    .O_M_ARID         ( o_m_arid         ),
    .O_M_ARADDR       ( o_m_araddr       ),
    .O_M_ARLEN        ( o_m_arlen        ),
    .O_M_ARSIZE       ( o_m_arsize       ),
    .O_M_ARBURST      ( o_m_arburst      ),
    .O_M_ARCACHE      ( o_m_arcache      ),
    .O_M_ARPROT       ( o_m_arprot       ),
    .O_M_ARLOCK       ( o_m_arlock       ),
    .O_M_ARQOS        ( o_m_arqos        ),
    .O_M_ARVALID      ( o_m_arvalid      ),
    .I_M_ARREADY      ( i_m_arready      ),

    .I_M_RID          ( i_m_rid          ),
    .I_M_RDATA        ( i_m_rdata        ),
    .I_M_RRESP        ( i_m_rresp        ),
    .I_M_RLAST        ( i_m_rlast        ),
    .I_M_RVALID       ( i_m_rvalid       ),
    .O_M_RREADY       ( o_m_rready       ),
    
    .O_M_AWID         ( o_m_awid         ),
    .O_M_AWADDR       ( o_m_awaddr       ),
    .O_M_AWLEN        ( o_m_awlen        ),
    .O_M_AWSIZE       ( o_m_awsize       ),
    .O_M_AWBURST      ( o_m_awburst      ),
    .O_M_AWLOCK       ( o_m_awlock       ),
    .O_M_AWCACHE      ( o_m_awcache      ),
    .O_M_AWPROT       ( o_m_awprot       ),
    .O_M_AWQOS        ( o_m_awqos        ),
    .O_M_AWVALID      ( o_m_awvalid      ),
    .I_M_AWREADY      ( o_s_awready      ),

    .O_M_WDATA        ( o_m_wdata        ),
    .O_M_WSTRB        ( o_m_wstrb        ),
    .O_M_WLAST        ( o_m_wlast        ),
    .O_M_WVALID       ( o_m_wvalid       ),
    .I_M_WREADY       ( o_s_wready       ),

    .I_M_BID          ( I_M_BID          ),
    .I_M_BRESP        ( I_M_BRESP        ),
    .I_M_BVALID       ( I_M_BVALID       ),
    .O_M_BREADY       ( O_M_BREADY       ),

    .O_BRESP_ERR_ID     ( O_BRESP_ERR_ID    ),
    .O_BRESP_ERR_ADDR   ( O_BRESP_ERR_ADDR  ),
    .O_BRESP_ERR_BRESP  ( O_BRESP_ERR_BRESP ),
    .O_BRESP_ERR        ( O_BRESP_ERR       ),

    .O_RRESP_ERR_ID     ( O_RRESP_ERR_ID    ),
    .O_RRESP_ERR_ADDR   ( O_RRESP_ERR_ADDR  ),
    .O_RRESP_ERR_RRESP  ( O_RRESP_ERR_RRESP ),
    .O_RRESP_ERR        ( O_RRESP_ERR       ),

    .O_SPLIT_MISMATCH_RID ( O_SPLIT_MISMATCH_RID       ),  
    .O_SPLIT_MISMATCH_BID ( O_SPLIT_MISMATCH_BID       ),
    .O_DEST_TABLE_RID_ERR ( O_SPLIT_RID_MISMATCH_ERROR ),
    .O_DEST_TABLE_BID_ERR ( O_SPLIT_BID_MISMATCH_ERROR ),

    .I_MAX_AWBURSTLEN (I_MAX_AWBURSTLEN  ),
    .I_MAX_ARBURSTLEN (I_MAX_ARBURSTLEN  )
);

AOU_AGGREGATOR # (
    .DATA_WD                ( DATA_WD                   ),
    .ADDR_WD                ( ADDR_WD                   ),
    .ID_WD                  ( ID_WD                     ),
    .STRB_WD                ( DATA_WD / 8               ),
    .LEN_WD                 ( LEN_WD                    ),
    .RD_MO_CNT              ( RD_MO_CNT                 ),
    .AOU_AGG_WCH_FIFO_DEPTH ( AOU_AGG_WCH_FIFO_DEPTH    )

) aou_aggregator 
(
    .I_CLK                  ( I_CLK                     ),
    .I_RESETN               ( I_RESETN                  ),
//WRITE TRANSACTION    
    .I_S_AWID               ( o_m_awid                  ),
    .I_S_AWADDR             ( o_m_awaddr                ),
    .I_S_AWLEN              ( o_m_awlen                 ),
    .I_S_AWSIZE             ( o_m_awsize                ),
    .I_S_AWBURST            ( o_m_awburst               ),
    .I_S_AWLOCK             ( o_m_awlock                ),
    .I_S_AWCACHE            ( o_m_awcache               ),
    .I_S_AWPROT             ( o_m_awprot                ),
    .I_S_AWQOS              ( o_m_awqos                 ),
    .I_S_AWVALID            ( w_aggregator_s_awvalid    ),
    .O_S_AWREADY            ( w_aggregator_s_awready    ),
             
             
    .I_S_WDATA              ( o_m_wdata                 ),
    .I_S_WSTRB              ( o_m_wstrb                 ),
    .I_S_WLAST              ( o_m_wlast                 ),
    .I_S_WVALID             ( w_aggregator_s_wvalid     ),
    .O_S_WREADY             ( w_aggregator_s_wready     ),
             
    .O_M_AWID               ( w_aggregator_awid         ),
    .O_M_AWADDR             ( w_aggregator_awaddr       ),
    .O_M_AWLEN              ( w_aggregator_awlen        ),
    .O_M_AWSIZE             ( w_aggregator_awsize       ),
    .O_M_AWBURST            ( w_aggregator_awburst      ),
    .O_M_AWLOCK             ( w_aggregator_awlock       ),
    .O_M_AWCACHE            ( w_aggregator_awcache      ),
    .O_M_AWPROT             ( w_aggregator_awprot       ),
    .O_M_AWQOS              ( w_aggregator_awqos        ),
    .O_M_AWVALID            ( w_aggregator_m_awvalid    ),
    .I_M_AWREADY            ( w_aggregator_m_awready    ),
             
    .O_M_WDATA              ( w_aggregator_wdata        ),
    .O_M_WSTRB              ( w_aggregator_wstrb        ),
    .O_M_WLAST              ( w_aggregator_wlast        ),
    .O_M_WVALID             ( w_aggregator_m_wvalid     ),
    .I_M_WREADY             ( w_aggregator_m_wready     ),

//READ TRANSACTION


    .I_S_ARID               ( o_m_arid                  ),
    .I_S_ARADDR             ( o_m_araddr                ),
    .I_S_ARLEN              ( o_m_arlen                 ),
    .I_S_ARSIZE             ( o_m_arsize                ),
    .I_S_ARBURST            ( o_m_arburst               ),
    .I_S_ARCACHE            ( o_m_arcache               ),
    .I_S_ARPROT             ( o_m_arprot                ),
    .I_S_ARLOCK             ( o_m_arlock                ),
    .I_S_ARQOS              ( o_m_arqos                 ),
    .I_S_ARVALID            ( w_aggregator_s_arvalid    ),
    .O_S_ARREADY            ( w_aggregator_s_arready    ),

    .O_S_RID                ( w_aggregator_rid          ),
    .O_S_RDATA              ( w_aggregator_rdata        ),
    .O_S_RRESP              ( w_aggregator_rresp        ),
    .O_S_RLAST              ( w_aggregator_rlast        ),
    .O_S_RVALID             ( w_aggregator_s_rvalid     ),
    .I_S_RREADY             ( w_aggregator_s_rready     ),

    .O_M_ARID               ( w_aggregator_arid         ),
    .O_M_ARADDR             ( w_aggregator_araddr       ),
    .O_M_ARLEN              ( w_aggregator_arlen        ),
    .O_M_ARSIZE             ( w_aggregator_arsize       ),
    .O_M_ARBURST            ( w_aggregator_arburst      ),
    .O_M_ARCACHE            ( w_aggregator_arcache      ),
    .O_M_ARPROT             ( w_aggregator_arprot       ),
    .O_M_ARLOCK             ( w_aggregator_arlock       ),
    .O_M_ARQOS              ( w_aggregator_arqos        ),
    .O_M_ARVALID            ( w_aggregator_m_arvalid    ),
    .I_M_ARREADY            ( w_aggregator_m_arready    ),

    .I_M_RID                ( I_M_RID                   ),
    .I_M_RDATA              ( I_M_RDATA                 ),
    .I_M_RRESP              ( I_M_RRESP                 ),
    .I_M_RLAST              ( I_M_RLAST                 ),
    .I_M_RVALID             ( w_aggregator_m_rvalid     ),
    .O_M_RREADY             ( w_aggregator_m_rready     ),

    .O_AGGRE_MISMATCH_RID   ( O_AGGRE_MISMATCH_RID      ),
    .O_DEST_TABLE_RID_ERR   ( O_AGGRE_RID_MISMATCH_ERROR)
);
//================================================================
assign O_M_AWID     = I_AXI_AGGREGATOR_EN ? w_aggregator_awid      : o_m_awid    ;
assign O_M_AWADDR   = I_AXI_AGGREGATOR_EN ? w_aggregator_awaddr    : o_m_awaddr  ;
assign O_M_AWLEN    = I_AXI_AGGREGATOR_EN ? w_aggregator_awlen     : o_m_awlen   ;
assign O_M_AWSIZE   = I_AXI_AGGREGATOR_EN ? w_aggregator_awsize    : o_m_awsize  ;
assign O_M_AWBURST  = I_AXI_AGGREGATOR_EN ? w_aggregator_awburst   : o_m_awburst ;
assign O_M_AWLOCK   = I_AXI_AGGREGATOR_EN ? w_aggregator_awlock    : o_m_awlock  ;
assign O_M_AWCACHE  = I_AXI_AGGREGATOR_EN ? w_aggregator_awcache   : o_m_awcache ;
assign O_M_AWPROT   = I_AXI_AGGREGATOR_EN ? w_aggregator_awprot    : o_m_awprot  ;
assign O_M_AWQOS    = I_AXI_AGGREGATOR_EN ? w_aggregator_awqos     : o_m_awqos   ;
assign O_M_AWVALID  = I_AXI_AGGREGATOR_EN ? w_aggregator_m_awvalid : o_m_awvalid ;
assign o_s_awready  = I_AXI_AGGREGATOR_EN ? w_aggregator_s_awready : I_M_AWREADY ;
assign w_aggregator_s_awvalid = o_m_awvalid && I_AXI_AGGREGATOR_EN;
assign w_aggregator_m_awready = I_AXI_AGGREGATOR_EN ? I_M_AWREADY : 1'b0;

assign O_M_WDATA    = I_AXI_AGGREGATOR_EN ? w_aggregator_wdata      : o_m_wdata  ;
assign O_M_WSTRB    = I_AXI_AGGREGATOR_EN ? w_aggregator_wstrb      : o_m_wstrb  ;
assign O_M_WLAST    = I_AXI_AGGREGATOR_EN ? w_aggregator_wlast      : o_m_wlast  ;
assign O_M_WVALID   = I_AXI_AGGREGATOR_EN ? w_aggregator_m_wvalid   : o_m_wvalid ;
assign o_s_wready   = I_AXI_AGGREGATOR_EN ? w_aggregator_s_wready   : I_M_WREADY ;
assign w_aggregator_s_wvalid = o_m_wvalid && I_AXI_AGGREGATOR_EN;
assign w_aggregator_m_wready = I_AXI_AGGREGATOR_EN ? I_M_WREADY : 1'b0;

assign O_M_ARID     = I_AXI_AGGREGATOR_EN ? w_aggregator_arid       : o_m_arid   ;
assign O_M_ARADDR   = I_AXI_AGGREGATOR_EN ? w_aggregator_araddr     : o_m_araddr ;
assign O_M_ARLEN    = I_AXI_AGGREGATOR_EN ? w_aggregator_arlen      : o_m_arlen  ;
assign O_M_ARSIZE   = I_AXI_AGGREGATOR_EN ? w_aggregator_arsize     : o_m_arsize ;
assign O_M_ARBURST  = I_AXI_AGGREGATOR_EN ? w_aggregator_arburst    : o_m_arburst;
assign O_M_ARCACHE  = I_AXI_AGGREGATOR_EN ? w_aggregator_arcache    : o_m_arcache;
assign O_M_ARPROT   = I_AXI_AGGREGATOR_EN ? w_aggregator_arprot     : o_m_arprot ;
assign O_M_ARLOCK   = I_AXI_AGGREGATOR_EN ? w_aggregator_arlock     : o_m_arlock ;
assign O_M_ARQOS    = I_AXI_AGGREGATOR_EN ? w_aggregator_arqos      : o_m_arqos  ;
assign O_M_ARVALID  = I_AXI_AGGREGATOR_EN ? w_aggregator_m_arvalid  : o_m_arvalid;
assign i_m_arready  = I_AXI_AGGREGATOR_EN ? w_aggregator_s_arready  : I_M_ARREADY;
assign w_aggregator_s_arvalid = o_m_arvalid && I_AXI_AGGREGATOR_EN;
assign w_aggregator_m_arready = I_AXI_AGGREGATOR_EN ? I_M_ARREADY : 1'b0; 

assign i_m_rid      = I_AXI_AGGREGATOR_EN ? w_aggregator_rid        : I_M_RID    ;
assign i_m_rdata    = I_AXI_AGGREGATOR_EN ? w_aggregator_rdata      : I_M_RDATA  ;
assign i_m_rresp    = I_AXI_AGGREGATOR_EN ? w_aggregator_rresp      : I_M_RRESP  ;
assign i_m_rlast    = I_AXI_AGGREGATOR_EN ? w_aggregator_rlast      : I_M_RLAST  ;
assign i_m_rvalid   = I_AXI_AGGREGATOR_EN ? w_aggregator_s_rvalid   : I_M_RVALID ; 
assign O_M_RREADY   = I_AXI_AGGREGATOR_EN ? w_aggregator_m_rready : o_m_rready;
assign w_aggregator_m_rvalid  = I_AXI_AGGREGATOR_EN ? I_M_RVALID : 1'b0;
assign w_aggregator_s_rready  = o_m_rready && I_AXI_AGGREGATOR_EN;
//========================================================================================

endmodule
