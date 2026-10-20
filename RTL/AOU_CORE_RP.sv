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
//  Module     : AOU_CORE_RP
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_CORE_RP
import packet_def_pkg::*;
#(

    parameter   AXI_DATA_WD                 = 512,
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024,

    parameter   S_RD_MO_CNT                 = 32,
    parameter   S_WR_MO_CNT                 = 32,

    parameter   M_RD_MO_CNT                 = 32,
    parameter   M_WR_MO_CNT                 = 32,
    parameter   AOU_AGG_WCH_FIFO_DEPTH      = 16,

    localparam  AXI_ADDR_WD                 = 64,
    localparam  AXI_ID_WD                   = 10,
    localparam  AXI_LEN_WD                  = 8,

    localparam  AXI_STRB_WD                 = AXI_DATA_WD / 8,
    localparam  AXI_MAX_STRB_WD             = AXI_PEER_DIE_MAX_DATA_WD / 8,

    localparam  B_FIFO_WIDTH                = AXI_ID_WD + 2
)
(
    input                                   I_CLK,
    input                                   I_RESETN,

    //AXI MI I/F
    output  [AXI_ID_WD-1:0]                 O_AOU_RX_AXI_M_ARID,
    output  [AXI_ADDR_WD-1:0]               O_AOU_RX_AXI_M_ARADDR,
    output  [AXI_LEN_WD-1:0]                O_AOU_RX_AXI_M_ARLEN,
    output  [2:0]                           O_AOU_RX_AXI_M_ARSIZE,
    output  [1:0]                           O_AOU_RX_AXI_M_ARBURST,
    output                                  O_AOU_RX_AXI_M_ARLOCK,
    output  [3:0]                           O_AOU_RX_AXI_M_ARCACHE,
    output  [2:0]                           O_AOU_RX_AXI_M_ARPROT,
    output  [3:0]                           O_AOU_RX_AXI_M_ARQOS,
    output                                  O_AOU_RX_AXI_M_ARVALID,
    input                                   I_AOU_RX_AXI_M_ARREADY,

    input   [AXI_ID_WD-1:0]                 I_AOU_TX_AXI_M_RID,
    input   [AXI_DATA_WD-1:0]               I_AOU_TX_AXI_M_RDATA,
    input   [1:0]                           I_AOU_TX_AXI_M_RRESP,
    input                                   I_AOU_TX_AXI_M_RLAST,
    input                                   I_AOU_TX_AXI_M_RVALID,
    output                                  O_AOU_TX_AXI_M_RREADY,

    output  [AXI_ID_WD-1:0]                 O_AOU_RX_AXI_M_AWID,
    output  [AXI_ADDR_WD-1:0]               O_AOU_RX_AXI_M_AWADDR,
    output  [AXI_LEN_WD-1:0]                O_AOU_RX_AXI_M_AWLEN,
    output  [2:0]                           O_AOU_RX_AXI_M_AWSIZE,
    output  [1:0]                           O_AOU_RX_AXI_M_AWBURST,
    output                                  O_AOU_RX_AXI_M_AWLOCK,
    output  [3:0]                           O_AOU_RX_AXI_M_AWCACHE,
    output  [2:0]                           O_AOU_RX_AXI_M_AWPROT,
    output  [3:0]                           O_AOU_RX_AXI_M_AWQOS,
    output                                  O_AOU_RX_AXI_M_AWVALID,
    input                                   I_AOU_RX_AXI_M_AWREADY,

    output  [AXI_DATA_WD-1:0]               O_AOU_RX_AXI_M_WDATA,
    output  [AXI_STRB_WD-1:0]               O_AOU_RX_AXI_M_WSTRB,
    output                                  O_AOU_RX_AXI_M_WLAST,
    output                                  O_AOU_RX_AXI_M_WVALID,
    input                                   I_AOU_RX_AXI_M_WREADY,

    input   [AXI_ID_WD-1:0]                 I_AOU_TX_AXI_M_BID,
    input   [1:0]                           I_AOU_TX_AXI_M_BRESP,
    input                                   I_AOU_TX_AXI_M_BVALID,
    output                                  O_AOU_TX_AXI_M_BREADY,

    //AXI SI I/F
    input   [AXI_ID_WD-1:0]                 I_AOU_TX_AXI_S_ARID,
    input                                   I_AOU_TX_AXI_S_ARVALID,
    input                                   I_AOU_TX_AXI_S_ARREADY,    
    output                                  O_AOU_SLV_INFO_AR_HOLD_FLAG,

    input  [AXI_ID_WD-1:0]                  I_AOU_RX_AXI_S_RID,
    input                                   I_AOU_RX_AXI_S_RLAST,
    input                                   I_AOU_RX_AXI_S_RVALID,
    input                                   I_AOU_RX_AXI_S_RREADY,
    output                                  O_AOU_RX_AXI_S_RVALID_BLOCKED,

    input   [AXI_ID_WD-1:0]                 I_AOU_TX_AXI_S_AWID,
    input   [AXI_ADDR_WD-1:0]               I_AOU_TX_AXI_S_AWADDR,
    input   [AXI_LEN_WD-1:0]                I_AOU_TX_AXI_S_AWLEN,
    input   [2:0]                           I_AOU_TX_AXI_S_AWSIZE,
    input   [1:0]                           I_AOU_TX_AXI_S_AWBURST,       //There is no burst field on AOU
    input                                   I_AOU_TX_AXI_S_AWLOCK,
    input   [3:0]                           I_AOU_TX_AXI_S_AWCACHE,
    input   [2:0]                           I_AOU_TX_AXI_S_AWPROT,
    input   [3:0]                           I_AOU_TX_AXI_S_AWQOS,
    input                                   I_AOU_TX_AXI_S_AWVALID,
    output                                  O_AOU_TX_AXI_S_AWREADY,

    input   [AXI_DATA_WD-1:0]               I_AOU_TX_AXI_S_WDATA,
    input   [AXI_STRB_WD-1:0]               I_AOU_TX_AXI_S_WSTRB,
    input                                   I_AOU_TX_AXI_S_WLAST,
    input                                   I_AOU_TX_AXI_S_WVALID,
    output                                  O_AOU_TX_AXI_S_WREADY,

    output  [AXI_ID_WD-1:0]                 O_AOU_RX_AXI_S_BID,
    output  [1:0]                           O_AOU_RX_AXI_S_BRESP,
    output                                  O_AOU_RX_AXI_S_BVALID,
    input                                   I_AOU_RX_AXI_S_BREADY,

    //From RX W_FIFO
    input   [AXI_ID_WD-1:0]                 I_AOU_RX_WLAST_GEN_AWID,
    input   [AXI_ADDR_WD-1:0]               I_AOU_RX_WLAST_GEN_AWADDR,
    input   [AXI_LEN_WD-1:0]                I_AOU_RX_WLAST_GEN_AWLEN,
    input   [2:0]                           I_AOU_RX_WLAST_GEN_AWSIZE,      
    input                                   I_AOU_RX_WLAST_GEN_AWLOCK,      
    input   [3:0]                           I_AOU_RX_WLAST_GEN_AWCACHE,     
    input   [2:0]                           I_AOU_RX_WLAST_GEN_AWPROT,    
    input   [3:0]                           I_AOU_RX_WLAST_GEN_AWQOS,     
    input                                   I_AOU_RX_WLAST_GEN_AWVALID,       
    output                                  O_AOU_RX_WLAST_GEN_AWREADY,     
     
    input   [1:0]                           I_AOU_RX_WLAST_GEN_WDLENGTH,
    input   [AXI_PEER_DIE_MAX_DATA_WD-1:0]  I_AOU_RX_WLAST_GEN_WDATA,    
    input   [AXI_MAX_STRB_WD-1:0]           I_AOU_RX_WLAST_GEN_WSTRB,      
    input                                   I_AOU_RX_WLAST_GEN_WVALID,
    output                                  O_AOU_RX_WLAST_GEN_WREADY,

    //From RX AR_fifo
    input   [AXI_ID_WD-1:0]                 I_AOU_RX_AXI_MM_ARID,        
    input   [AXI_ADDR_WD-1:0]               I_AOU_RX_AXI_MM_ARADDR,
    input   [AXI_LEN_WD-1:0]                I_AOU_RX_AXI_MM_ARLEN,      
    input   [2:0]                           I_AOU_RX_AXI_MM_ARSIZE,          
    input                                   I_AOU_RX_AXI_MM_ARLOCK,      
    input   [3:0]                           I_AOU_RX_AXI_MM_ARCACHE,     
    input   [2:0]                           I_AOU_RX_AXI_MM_ARPROT,      
    input   [3:0]                           I_AOU_RX_AXI_MM_ARQOS,       
    input                                   I_AOU_RX_AXI_MM_ARVALID,     
    output                                  O_AOU_RX_AXI_MM_ARREADY,

    //To Early_BRESP_CTRL B FWD RS
    input   [AXI_ID_WD-1:0]                 I_EARLY_BRESP_CTRL_BID,
    input   [1:0]                           I_EARLY_BRESP_CTRL_BRESP,
    input                                   I_EARLY_BRESP_CTRL_BVALID,
    output                                  O_EARLY_BRESP_CTRL_BREADY,

    //Tx Core I/F
    output  [AXI_ID_WD-1:0]                 O_EARLY_BRESP_CTRL_AWID     ,    
    output  [AXI_ADDR_WD-1:0]               O_EARLY_BRESP_CTRL_AWADDR   ,    
    output  [AXI_LEN_WD-1:0]                O_EARLY_BRESP_CTRL_AWLEN    ,    
    output  [2:0]                           O_EARLY_BRESP_CTRL_AWSIZE   ,    
    output  [1:0]                           O_EARLY_BRESP_CTRL_AWBURST  ,    
    output                                  O_EARLY_BRESP_CTRL_AWLOCK   ,    
    output  [3:0]                           O_EARLY_BRESP_CTRL_AWCACHE  ,    
    output  [2:0]                           O_EARLY_BRESP_CTRL_AWPROT   ,    
    output  [3:0]                           O_EARLY_BRESP_CTRL_AWQOS    ,    
    output                                  O_EARLY_BRESP_CTRL_AWVALID  ,    
    input                                   I_EARLY_BRESP_CTRL_AWREADY  ,        

    output  [AXI_DATA_WD-1:0]               O_EARLY_BRESP_CTRL_WDATA    , 
    output  [AXI_STRB_WD-1:0]               O_EARLY_BRESP_CTRL_WSTRB    , 
    output                                  O_EARLY_BRESP_CTRL_WLAST    , 
    output                                  O_EARLY_BRESP_CTRL_WVALID   , 
    input                                   I_EARLY_BRESP_CTRL_WREADY   ,

    output  [AXI_ID_WD-1:0]                 O_AOU_TX_AXI_BID_256     , 
    output  [1:0]                           O_AOU_TX_AXI_BRESP_256   , 
    output                                  O_AOU_TX_AXI_BVALID_256  , 
    input                                   I_AOU_TX_AXI_BREADY_256  , 

    output  [AXI_ID_WD-1:0]                 O_AOU_TX_AXI_BID_512     , 
    output  [1:0]                           O_AOU_TX_AXI_BRESP_512   , 
    output                                  O_AOU_TX_AXI_BVALID_512  , 
    input                                   I_AOU_TX_AXI_BREADY_512  , 

    output  [AXI_ID_WD-1:0]                 O_AOU_TX_AXI_BID_1024    , 
    output  [1:0]                           O_AOU_TX_AXI_BRESP_1024  , 
    output                                  O_AOU_TX_AXI_BVALID_1024 , 
    input                                   I_AOU_TX_AXI_BREADY_1024 , 

    output  [AXI_ID_WD-1:0]                 O_AOU_TX_AXI_RID    , 
    output  [1:0]                           O_AOU_TX_AXI_RDLEN  , 
    output  [1023:0]                        O_AOU_TX_AXI_RDATA  , 
    output  [1:0]                           O_AOU_TX_AXI_RRESP  , 
    output                                  O_AOU_TX_AXI_RLAST  , 
    output                                  O_AOU_TX_AXI_RVALID , 
    input                                   I_AOU_TX_AXI_RREADY , 

    //SFR I/F
    input   [AXI_LEN_WD-1:0]                I_AXI_SPLIT_TR_MAX_AWBURSTLEN  , 
    input   [AXI_LEN_WD-1:0]                I_AXI_SPLIT_TR_MAX_ARBURSTLEN  , 

    input                                   I_AXI_SLV_ID_MISMATCH_EN,

    output  [AXI_ID_WD-1:0]                 O_ERROR_INFO_SPLIT_BID_MISMATCH_INFO,
    output                                  O_ERROR_INFO_SPLIT_BID_MISMATCH_ERR_SET,

    output  reg [AXI_ID_WD-1:0]             O_ERROR_INFO_RID_MISMATCH_INFO,
    output  reg                             O_ERROR_INFO_RID_MISMATCH_ERR_SET,
   
    output                                  O_EARLY_BRESP_DONE,
    output                                  O_EARLY_BRESP_ERR_SET,
    output  [1:0]                           O_EARLY_BRESP_ERR_TYPE,
    output  [AXI_ID_WD-1:0]                 O_EARLY_BRESP_ERR_ID,
    input                                   I_EARLY_BRESP_EN,
    input                                   I_EARLY_BRESP_ALWAYS_EN,

    input                                   I_EARLY_BRESP_WDT_EN, 
    input   [31:0]                          I_EARLY_BRESP_WDT_THRESHOLD,
    output                                  O_EARLY_BRESP_TRANS_TIMEOUT_ERR,
                                  
    input   [31:0]                          I_DEBUG_ERROR_INFO_UPPER_ADDR,
    input   [31:0]                          I_DEBUG_ERROR_INFO_LOWER_ADDR,
    input                                   I_DEBUG_ERR_ACCESS_ENABLE,
     
    input                                   I_AXI_AGGREGATOR_EN,

    output  [AXI_ID_WD-1:0]                 O_AXI_SLV_BID_MISMATCH_INFO,
    output  [AXI_ID_WD-1:0]                 O_AXI_SLV_RID_MISMATCH_INFO,
    output                                  O_AXI_SLV_BID_MISMATCH_ERR_SET,
    output                                  O_AXI_SLV_RID_MISMATCH_ERR_SET,

    output                                  O_SLV_TR_COMPLETE,
    output                                  O_MST_TR_COMPLETE
     
);
//----------------------------------------------------------------------------
    localparam AOU_CORE_TOP_RCH_RS_EN       = 0;
//----------------------------------------------------------------------------
    
    logic   [AXI_ID_WD-1:0]                 w_early_bresp_ctrl_bid          ;
    logic   [1:0]                           w_early_bresp_ctrl_bresp        ;
    logic                                   w_early_bresp_ctrl_bvalid       ;
    logic                                   w_early_bresp_ctrl_bready       ;
 
//----------------------------------------------------------------------------
    
    wire                                    w_aou_rx_axi_mm_arvalid_256     ;
    wire                                    w_aou_rx_axi_mm_arvalid_512     ;
    wire                                    w_aou_rx_axi_mm_arvalid_1024    ;
    wire                                    w_aou_rx_axi_mm_arready_256     ;
    wire                                    w_aou_rx_axi_mm_arready_512     ;
    wire                                    w_aou_rx_axi_mm_arready_1024    ;

    wire [1:0]                              w_aou_rx_axi_mm_arburst         ; 

    reg [AXI_ID_WD-1:0]                     w_aou_tx_axi_mm_rid             ;
    reg [1:0]                               w_aou_tx_axi_mm_rdlen           ;
    reg [1023:0]                            w_aou_tx_axi_mm_rdata           ;
    reg [1:0]                               w_aou_tx_axi_mm_rresp           ;
    reg                                     w_aou_tx_axi_mm_rlast           ;
    reg                                     w_aou_tx_axi_mm_rvalid          ;
    wire                                    w_aou_tx_axi_mm_rready          ;   
 
    wire [AXI_ID_WD-1:0]                    w_aou_rx_axi_mm_awid            ;
    wire [AXI_ADDR_WD-1:0]                  w_aou_rx_axi_mm_awaddr          ;
    wire [AXI_LEN_WD-1:0]                   w_aou_rx_axi_mm_awlen           ;
    wire [2:0]                              w_aou_rx_axi_mm_awsize          ;
    wire [1:0]                              w_aou_rx_axi_mm_awburst         ;
    wire                                    w_aou_rx_axi_mm_awlock          ;
    wire [3:0]                              w_aou_rx_axi_mm_awcache         ;
    wire [2:0]                              w_aou_rx_axi_mm_awprot          ;
    wire [3:0]                              w_aou_rx_axi_mm_awqos           ;
    wire                                    w_aou_rx_axi_mm_awvalid_256     ;
    wire                                    w_aou_rx_axi_mm_awvalid_512     ;
    wire                                    w_aou_rx_axi_mm_awvalid_1024    ;
    wire                                    w_aou_rx_axi_mm_awready_256     ;
    wire                                    w_aou_rx_axi_mm_awready_512     ;
    wire                                    w_aou_rx_axi_mm_awready_1024    ;

    wire [1023:0]                           w_aou_rx_axi_mm_wdata           ;
    wire [127:0]                            w_aou_rx_axi_mm_wstrb           ;
    wire                                    w_aou_rx_axi_mm_wlast           ;
    wire                                    w_aou_rx_axi_mm_wvalid_256      ;
    wire                                    w_aou_rx_axi_mm_wvalid_512      ;
    wire                                    w_aou_rx_axi_mm_wvalid_1024     ;
    wire                                    w_aou_rx_axi_mm_wready_256      ;
    wire                                    w_aou_rx_axi_mm_wready_512      ;
    wire                                    w_aou_rx_axi_mm_wready_1024     ;
        
//----------------------------------------------------------------------------
    logic [AXI_ID_WD-1:0]       w_aou_err_info_axi_arid;
    logic [AXI_ADDR_WD-1:0]     w_aou_err_info_axi_araddr;
    logic [AXI_LEN_WD-1:0]      w_aou_err_info_axi_arlen;
    logic [2:0]                 w_aou_err_info_axi_arsize;
    logic [1:0]                 w_aou_err_info_axi_arburst;
    logic                       w_aou_err_info_axi_arlock;
    logic [3:0]                 w_aou_err_info_axi_arcache;
    logic [2:0]                 w_aou_err_info_axi_arprot;
    logic [3:0]                 w_aou_err_info_axi_arqos;
    logic                       w_aou_err_info_axi_arvalid;
    logic                       w_aou_err_info_axi_arready;
    
    logic [AXI_ID_WD-1:0]       w_aou_err_info_axi_rid;
    logic [AXI_DATA_WD-1:0]     w_aou_err_info_axi_rdata;
    logic [1:0]                 w_aou_err_info_axi_rresp;
    logic                       w_aou_err_info_axi_rlast;
    logic                       w_aou_err_info_axi_rvalid;
    logic                       w_aou_err_info_axi_rready;
    
    logic [AXI_ID_WD-1:0]       w_aou_err_info_axi_awid;
    logic [AXI_ADDR_WD-1:0]     w_aou_err_info_axi_awaddr;
    logic [AXI_LEN_WD-1:0]      w_aou_err_info_axi_awlen;
    logic [2:0]                 w_aou_err_info_axi_awsize;
    logic [1:0]                 w_aou_err_info_axi_awburst;
    logic                       w_aou_err_info_axi_awlock;
    logic [3:0]                 w_aou_err_info_axi_awcache;
    logic [2:0]                 w_aou_err_info_axi_awprot;
    logic [3:0]                 w_aou_err_info_axi_awqos;
    logic                       w_aou_err_info_axi_awvalid;
    logic                       w_aou_err_info_axi_awready;
    
    logic [AXI_DATA_WD-1:0]     w_aou_err_info_axi_wdata;
    logic [AXI_STRB_WD-1:0]     w_aou_err_info_axi_wstrb;
    logic                       w_aou_err_info_axi_wlast;
    logic                       w_aou_err_info_axi_wvalid;
    logic                       w_aou_err_info_axi_wready;
    
    logic [AXI_ID_WD-1:0]       w_aou_err_info_axi_bid;
    logic [1:0]                 w_aou_err_info_axi_bresp;
    logic                       w_aou_err_info_axi_bvalid;
    logic                       w_aou_err_info_axi_bready;

    logic                       w_slv_axi_r_block;
    logic                       w_slv_axi_b_block;

    logic                       w_early_bresp_ctrl_bvalid_blocked;
    logic                       w_aou_rx_axi_s_rvalid_blocked;

    logic                       w_early_bresp_ctrl_awvalid;
    logic                       w_early_bresp_ctrl_awready;

    logic                       w_early_bresp_ctrl_wvalid;
    logic                       w_early_bresp_ctrl_wready;

    logic                       w_aou_slv_info_aw_hold_flag;
    logic                       w_aou_slv_info_w_hold_flag;
    logic                       w_aou_slv_info_ar_hold_flag;
//---------------------------------------------------------------------------- 
    logic [AXI_ID_WD-1:0]       w_err_info_arid;
    logic [AXI_ADDR_WD-1:0]     w_err_info_araddr;
    logic [2:0]                 w_err_info_arsize;
    logic [1:0]                 w_err_info_arburst;
    logic [3:0]                 w_err_info_arcache;
    logic [2:0]                 w_err_info_arprot;
    logic [AXI_LEN_WD-1:0]      w_err_info_arlen;
    logic                       w_err_info_arlock;
    logic [3:0]                 w_err_info_arqos;
    logic                       w_err_info_arvalid; 
    logic                       w_err_info_arready;
    
    logic [AXI_ID_WD-1:0]       w_err_info_rid;
    logic [AXI_DATA_WD-1:0]     w_err_info_rdata;
    logic [1:0]                 w_err_info_rresp;
    logic                       w_err_info_rlast;
    logic                       w_err_info_rvalid;    
    logic                       w_err_info_rready;
   
    logic [AXI_ID_WD-1:0]       w_err_info_awid;
    logic [AXI_ADDR_WD-1:0]     w_err_info_awaddr;
    logic [2:0]                 w_err_info_awsize;
    logic [1:0]                 w_err_info_awburst;
    logic [3:0]                 w_err_info_awcache;
    logic [2:0]                 w_err_info_awprot;
    logic [AXI_LEN_WD-1:0]      w_err_info_awlen;
    logic                       w_err_info_awlock;
    logic [3:0]                 w_err_info_awqos;
    logic                       w_err_info_awvalid; 
    logic                       w_err_info_awready; 

    logic [AXI_DATA_WD-1:0]     w_err_info_wdata;
    logic [AXI_STRB_WD-1:0]     w_err_info_wstrb;
    logic                       w_err_info_wlast;
    logic                       w_err_info_wvalid; 
    logic                       w_err_info_wready;
    
    logic [AXI_ID_WD-1:0]       w_err_info_bid;
    logic [1:0]                 w_err_info_bresp;
    logic                       w_err_info_bvalid;
    logic                       w_err_info_bready;
    
//----------------------------------------------------------------------------    
    localparam AXIM_RCH_PAYLOAD_WD = AXI_ID_WD + AXI_DATA_WD + 2 + 1; //RESP + LAST
    
    logic [AXI_ID_WD-1:0]               w_aou_tx_axi_m_rid_rs;
    logic [AXI_DATA_WD-1:0]             w_aou_tx_axi_m_rdata_rs;
    logic [1:0]                         w_aou_tx_axi_m_rresp_rs;
    logic                               w_aou_tx_axi_m_rlast_rs;
    logic                               w_aou_tx_axi_m_rvalid_rs;
    logic                               w_aou_tx_axi_m_rready_rs;
    
    logic [AXIM_RCH_PAYLOAD_WD-1:0]     w_aou_tx_axi_m_rch_sdata;
    logic [AXIM_RCH_PAYLOAD_WD-1:0]     w_aou_tx_axi_m_rch_mdata;

//----------------------------------------------------------------------------      
   
    logic [AXI_ID_WD-1:0]          w_axi_bresp_err_id;
    logic [AXI_ADDR_WD-1:0]        w_axi_bresp_err_addr;
    logic [1:0]                    w_axi_bresp_err_bresp;
    logic                          w_axi_bresp_err;
    
    logic [AXI_ID_WD-1:0]          w_axi_rresp_err_id;
    logic [AXI_ADDR_WD-1:0]        w_axi_rresp_err_addr;
    logic [1:0]                    w_axi_rresp_err_bresp;
    logic                          w_axi_rresp_err;
    
    logic  [AXI_ID_WD-1:0]         w_error_info_split_rid_mismatch_info;
    logic                          w_error_info_split_rid_mismatch_err_set;

    logic  [AXI_ID_WD-1:0]         w_error_info_aggre_rid_mismatch_info;
    logic                          w_error_info_aggre_rid_mismatch_err_set;

    logic  [AXI_ID_WD-1:0]         w_error_info_down512_rid_mismatch_info;
    logic                          w_error_info_down512_rid_mismatch_err_set;

    logic  [AXI_ID_WD-1:0]         w_error_info_down1024_rid_mismatch_info;
    logic                          w_error_info_down1024_rid_mismatch_err_set; 
//----------------------------------------------------------------------------    

    assign w_aou_rx_axi_mm_arvalid_256  = (I_AOU_RX_AXI_MM_ARVALID & (I_AOU_RX_AXI_MM_ARSIZE < 3'b110)); 
    assign w_aou_rx_axi_mm_arvalid_512  = (I_AOU_RX_AXI_MM_ARVALID & (I_AOU_RX_AXI_MM_ARSIZE == 3'b110)); 
    assign w_aou_rx_axi_mm_arvalid_1024 = (I_AOU_RX_AXI_MM_ARVALID & (I_AOU_RX_AXI_MM_ARSIZE == 3'b111));
    
    assign w_aou_tx_axi_m_rch_sdata = {I_AOU_TX_AXI_M_RID,
                                       I_AOU_TX_AXI_M_RDATA,
                                       I_AOU_TX_AXI_M_RRESP,
                                       I_AOU_TX_AXI_M_RLAST};
    
    assign {w_aou_tx_axi_m_rid_rs,
            w_aou_tx_axi_m_rdata_rs,
            w_aou_tx_axi_m_rresp_rs,
            w_aou_tx_axi_m_rlast_rs} = w_aou_tx_axi_m_rch_mdata;
    
    generate
    if (AOU_CORE_TOP_RCH_RS_EN == 1) begin
    
        AOU_SYNC_FIFO_REG #(
            .FIFO_WIDTH      ( AXIM_RCH_PAYLOAD_WD          ),
            .FIFO_DEPTH      ( 2                            )
        ) u_axim_rch_rs
        (
            .I_CLK           ( I_CLK                        ),
            .I_RESETN        ( I_RESETN                     ),
        
            .I_SVALID        ( I_AOU_TX_AXI_M_RVALID        ),
            .I_SDATA         ( w_aou_tx_axi_m_rch_sdata     ),
            .O_SREADY        ( O_AOU_TX_AXI_M_RREADY        ),
        
            .I_MREADY        ( w_aou_tx_axi_m_rready_rs     ),
            .O_MDATA         ( w_aou_tx_axi_m_rch_mdata     ),
            .O_MVALID        ( w_aou_tx_axi_m_rvalid_rs     ),
        
            .O_EMPTY_CNT     ( ),
            .O_FULL_CNT      ( )
        );
    
    end else begin
        assign w_aou_tx_axi_m_rch_mdata = w_aou_tx_axi_m_rch_sdata; 
        assign w_aou_tx_axi_m_rvalid_rs = I_AOU_TX_AXI_M_RVALID   ; 
        assign O_AOU_TX_AXI_M_RREADY    = w_aou_tx_axi_m_rready_rs; 
    
    end
    endgenerate

//---------------------------------------------------------------------------- 
   
    AOU_AXIMUX_1XN_SS #(
        .AOU_AXIMUX_1XN_ARCH_RS_EN  ( 0             ),
        .AOU_AXIMUX_1XN_RCH_RS_EN   ( 1             ),
        .AOU_AXIMUX_1XN_AWCH_RS_EN  ( 0             ),
        .AOU_AXIMUX_1XN_WCH_RS_EN   ( 0             ),
        .SA                         ( 20            ),
        .SN                         ( 2             ),
        .AXI_DATA_WD                ( AXI_DATA_WD   ),
        .AXI_ADDR_WD                ( AXI_ADDR_WD   ),
        .AXI_ID_WD                  ( AXI_ID_WD     ),
        .AXI_QOS_WD                 ( 4             ),
        .AXI_LEN_WD                 ( AXI_LEN_WD    )
    )u_aou_aximux_1x2_singleslave
    (
        .I_CLK                      ( I_CLK                             ),
        .I_RESETN                   ( I_RESETN                          ),
    
        //Slave I/F
        .I_S_ARID                   ( w_aou_err_info_axi_arid           ),
        .I_S_ARADDR                 ( w_aou_err_info_axi_araddr         ),
        .I_S_ARLEN                  ( w_aou_err_info_axi_arlen          ),
        .I_S_ARSIZE                 ( w_aou_err_info_axi_arsize         ),
        .I_S_ARBURST                ( w_aou_err_info_axi_arburst        ),
        .I_S_ARCACHE                ( w_aou_err_info_axi_arcache        ),
        .I_S_ARPROT                 ( w_aou_err_info_axi_arprot         ),
        .I_S_ARLOCK                 ( w_aou_err_info_axi_arlock         ),
        .I_S_ARQOS                  ( w_aou_err_info_axi_arqos          ),
        .I_S_ARVALID                ( w_aou_err_info_axi_arvalid        ),
        .O_S_ARREADY                ( w_aou_err_info_axi_arready        ),
    
        .O_S_RID                    ( w_aou_err_info_axi_rid            ),
        .O_S_RDATA                  ( w_aou_err_info_axi_rdata          ),
        .O_S_RRESP                  ( w_aou_err_info_axi_rresp          ),
        .O_S_RLAST                  ( w_aou_err_info_axi_rlast          ),
        .O_S_RVALID                 ( w_aou_err_info_axi_rvalid         ),
        .I_S_RREADY                 ( w_aou_err_info_axi_rready         ),
    
        .I_S_AWID                   ( w_aou_err_info_axi_awid           ),
        .I_S_AWADDR                 ( w_aou_err_info_axi_awaddr         ),
        .I_S_AWLEN                  ( w_aou_err_info_axi_awlen          ),
        .I_S_AWSIZE                 ( w_aou_err_info_axi_awsize         ),
        .I_S_AWBURST                ( w_aou_err_info_axi_awburst        ),
        .I_S_AWLOCK                 ( w_aou_err_info_axi_awlock         ),
        .I_S_AWCACHE                ( w_aou_err_info_axi_awcache        ),
        .I_S_AWPROT                 ( w_aou_err_info_axi_awprot         ),
        .I_S_AWQOS                  ( w_aou_err_info_axi_awqos          ),
        .I_S_AWVALID                ( w_aou_err_info_axi_awvalid        ),
        .O_S_AWREADY                ( w_aou_err_info_axi_awready        ),
    
        .I_S_WDATA                  ( w_aou_err_info_axi_wdata          ),
        .I_S_WSTRB                  ( w_aou_err_info_axi_wstrb          ),
        .I_S_WLAST                  ( w_aou_err_info_axi_wlast          ),
        .I_S_WVALID                 ( w_aou_err_info_axi_wvalid         ),
        .O_S_WREADY                 ( w_aou_err_info_axi_wready         ),
    
        .O_S_BID                    ( w_aou_err_info_axi_bid            ),
        .O_S_BRESP                  ( w_aou_err_info_axi_bresp          ),
        .O_S_BVALID                 ( w_aou_err_info_axi_bvalid         ),
        .I_S_BREADY                 ( w_aou_err_info_axi_bready         ),

        //Master I/F
        .O_M_ARID                   ( {w_err_info_arid, O_AOU_RX_AXI_M_ARID}        ),
        .O_M_ARADDR                 ( {w_err_info_araddr, O_AOU_RX_AXI_M_ARADDR}    ),
        .O_M_ARLEN                  ( {w_err_info_arlen, O_AOU_RX_AXI_M_ARLEN}      ),
        .O_M_ARSIZE                 ( {w_err_info_arsize, O_AOU_RX_AXI_M_ARSIZE}    ),
        .O_M_ARBURST                ( {w_err_info_arburst, O_AOU_RX_AXI_M_ARBURST}  ),
        .O_M_ARLOCK                 ( {w_err_info_arlock, O_AOU_RX_AXI_M_ARLOCK}    ),
        .O_M_ARCACHE                ( {w_err_info_arcache, O_AOU_RX_AXI_M_ARCACHE}  ),
        .O_M_ARPROT                 ( {w_err_info_arprot, O_AOU_RX_AXI_M_ARPROT}    ),
        .O_M_ARQOS                  ( {w_err_info_arqos, O_AOU_RX_AXI_M_ARQOS}      ),
        .O_M_ARVALID                ( {w_err_info_arvalid, O_AOU_RX_AXI_M_ARVALID}  ),
        .I_M_ARREADY                ( {w_err_info_arready, I_AOU_RX_AXI_M_ARREADY}  ),
    
        .I_M_RID                    ( {w_err_info_rid   , w_aou_tx_axi_m_rid_rs   } ),
        .I_M_RDATA                  ( {w_err_info_rdata , w_aou_tx_axi_m_rdata_rs } ),
        .I_M_RRESP                  ( {w_err_info_rresp , w_aou_tx_axi_m_rresp_rs } ),
        .I_M_RLAST                  ( {w_err_info_rlast , w_aou_tx_axi_m_rlast_rs } ),
        .I_M_RVALID                 ( {w_err_info_rvalid, w_aou_tx_axi_m_rvalid_rs} ),
        .O_M_RREADY                 ( {w_err_info_rready, w_aou_tx_axi_m_rready_rs} ),
    
        .O_M_AWID                   ( {w_err_info_awid , O_AOU_RX_AXI_M_AWID}       ),
        .O_M_AWADDR                 ( {w_err_info_awaddr , O_AOU_RX_AXI_M_AWADDR}   ),
        .O_M_AWLEN                  ( {w_err_info_awlen , O_AOU_RX_AXI_M_AWLEN}     ),
        .O_M_AWSIZE                 ( {w_err_info_awsize , O_AOU_RX_AXI_M_AWSIZE}   ),
        .O_M_AWBURST                ( {w_err_info_awburst , O_AOU_RX_AXI_M_AWBURST} ),
        .O_M_AWLOCK                 ( {w_err_info_awlock , O_AOU_RX_AXI_M_AWLOCK}   ),
        .O_M_AWCACHE                ( {w_err_info_awcache , O_AOU_RX_AXI_M_AWCACHE} ),
        .O_M_AWPROT                 ( {w_err_info_awprot , O_AOU_RX_AXI_M_AWPROT}   ),
        .O_M_AWQOS                  ( {w_err_info_awqos , O_AOU_RX_AXI_M_AWQOS}     ),
        .O_M_AWVALID                ( {w_err_info_awvalid, O_AOU_RX_AXI_M_AWVALID}  ),
        .I_M_AWREADY                ( {w_err_info_awready, I_AOU_RX_AXI_M_AWREADY}  ),
    
        .O_M_WDATA                  ( {w_err_info_wdata, O_AOU_RX_AXI_M_WDATA}    ),
        .O_M_WSTRB                  ( {w_err_info_wstrb, O_AOU_RX_AXI_M_WSTRB}    ),
        .O_M_WLAST                  ( {w_err_info_wlast, O_AOU_RX_AXI_M_WLAST}    ),
        .O_M_WVALID                 ( {w_err_info_wvalid, O_AOU_RX_AXI_M_WVALID} ),
        .I_M_WREADY                 ( {w_err_info_wready, I_AOU_RX_AXI_M_WREADY} ),
    
        .I_M_BID                    ( {w_err_info_bid   , I_AOU_TX_AXI_M_BID   }    ),
        .I_M_BRESP                  ( {w_err_info_bresp , I_AOU_TX_AXI_M_BRESP }    ),
        .I_M_BVALID                 ( {w_err_info_bvalid, I_AOU_TX_AXI_M_BVALID}    ),
        .O_M_BREADY                 ( {w_err_info_bready, O_AOU_TX_AXI_M_BREADY}    ),
     
        .I_DEBUG_ERR_UPPER_ADDR     ( I_DEBUG_ERROR_INFO_UPPER_ADDR     ),
        .I_DEBUG_ERR_LOWER_ADDR     ( I_DEBUG_ERROR_INFO_LOWER_ADDR     ),
    
        .I_DEBUG_ERR_ACCESS_ENABLE  ( I_DEBUG_ERR_ACCESS_ENABLE         )
    
    );
    
    AOU_ERROR_INFO #(
        .AXI_ID_WD          ( AXI_ID_WD     ),
        .AXI_DATA_WD        ( AXI_DATA_WD   ),
        .AXI_ADDR_WD        ( AXI_ADDR_WD   ),
        .AXI_LEN_WD         ( AXI_LEN_WD    ),
        .FIFO_DEPTH         ( 4             )
    ) u_aou_error_info 
    (
        .I_CLK              ( I_CLK                     ),
        .I_RESETN           ( I_RESETN                  ),
    
        .I_BRESP_ERR_ID     ( w_axi_bresp_err_id        ),
        .I_BRESP_ERR_ADDR   ( w_axi_bresp_err_addr      ),
        .I_BRESP_ERR_BRESP  ( w_axi_bresp_err_bresp     ),
        .I_BRESP_ERR        ( w_axi_bresp_err           ),
                                                        
        .I_RRESP_ERR_ID     ( w_axi_rresp_err_id        ),
        .I_RRESP_ERR_ADDR   ( w_axi_rresp_err_addr      ),
        .I_RRESP_ERR_RRESP  ( w_axi_rresp_err_bresp     ),
        .I_RRESP_ERR        ( w_axi_rresp_err           ),
                                                        
        .I_S_AWID           ( w_err_info_awid           ),
        .I_S_AWADDR         ( w_err_info_awaddr         ),
        .I_S_AWLEN          ( w_err_info_awlen          ),
        .I_S_AWSIZE         ( w_err_info_awsize         ),
        .I_S_AWBURST        ( w_err_info_awburst        ),
        .I_S_AWLOCK         ( w_err_info_awlock         ),
        .I_S_AWCACHE        ( w_err_info_awcache        ),
        .I_S_AWPROT         ( w_err_info_awprot         ),
        .I_S_AWQOS          ( w_err_info_awqos          ),
        .I_S_AWVALID        ( w_err_info_awvalid        ),
        .O_S_AWREADY        ( w_err_info_awready        ),
                                                        
        .I_S_WDATA          ( w_err_info_wdata          ),
        .I_S_WSTRB          ( w_err_info_wstrb          ),
        .I_S_WLAST          ( w_err_info_wlast          ),
        .I_S_WVALID         ( w_err_info_wvalid         ),
        .O_S_WREADY         ( w_err_info_wready         ),
                                                        
        .O_S_BID            ( w_err_info_bid            ),
        .O_S_BRESP          ( w_err_info_bresp          ),
        .O_S_BVALID         ( w_err_info_bvalid         ),
        .I_S_BREADY         ( w_err_info_bready         ),
                                                        
        .I_S_ARID           ( w_err_info_arid           ),
        .I_S_ARADDR         ( w_err_info_araddr         ),
        .I_S_ARSIZE         ( w_err_info_arsize         ),
        .I_S_ARBURST        ( w_err_info_arburst        ),
        .I_S_ARCACHE        ( w_err_info_arcache        ),
        .I_S_ARPROT         ( w_err_info_arprot         ),
        .I_S_ARLEN          ( w_err_info_arlen          ),
        .I_S_ARLOCK         ( w_err_info_arlock         ),
        .I_S_ARQOS          ( w_err_info_arqos          ),
        .I_S_ARVALID        ( w_err_info_arvalid        ),
        .O_S_ARREADY        ( w_err_info_arready        ),
                                                        
        .O_S_RID            ( w_err_info_rid            ),
        .O_S_RDATA          ( w_err_info_rdata          ),
        .O_S_RRESP          ( w_err_info_rresp          ),
        .O_S_RLAST          ( w_err_info_rlast          ),
        .O_S_RVALID         ( w_err_info_rvalid         ),
        .I_S_RREADY         ( w_err_info_rready         )
    );
    
    AOU_SLV_AXI_INFO # (
        .AXI_ID_WD                  ( AXI_ID_WD                     ),
        .AXI_LEN_WD                 ( AXI_LEN_WD                    ),
        .RD_MO_CNT                  ( S_RD_MO_CNT                   ),
        .WR_MO_CNT                  ( S_WR_MO_CNT                   )
    ) u_aou_slv_axi_info (
        .I_CLK                      ( I_CLK                         ),
        .I_RESETN                   ( I_RESETN                      ),
    
        .I_AWID                     ( O_EARLY_BRESP_CTRL_AWID       ),
        .I_AWVALID                  ( O_EARLY_BRESP_CTRL_AWVALID  && I_AXI_SLV_ID_MISMATCH_EN  ),
        .I_AWREADY                  ( w_early_bresp_ctrl_awready  && I_AXI_SLV_ID_MISMATCH_EN  ),
    
        .I_WLAST                    ( O_EARLY_BRESP_CTRL_WLAST      ),
        .I_WVALID                   ( O_EARLY_BRESP_CTRL_WVALID   && I_AXI_SLV_ID_MISMATCH_EN  ),
        .I_WREADY                   ( w_early_bresp_ctrl_wready   && I_AXI_SLV_ID_MISMATCH_EN  ),
    
        .I_BID                      ( I_EARLY_BRESP_CTRL_BID        ),
        .I_BVALID                   ( I_EARLY_BRESP_CTRL_BVALID   && I_AXI_SLV_ID_MISMATCH_EN  ),
        .I_BREADY                   ( O_EARLY_BRESP_CTRL_BREADY   && I_AXI_SLV_ID_MISMATCH_EN  ),
    
        .I_ARID                     ( I_AOU_TX_AXI_S_ARID           ),
        .I_ARVALID                  ( I_AOU_TX_AXI_S_ARVALID      && I_AXI_SLV_ID_MISMATCH_EN  ),
        .I_ARREADY                  ( I_AOU_TX_AXI_S_ARREADY      && I_AXI_SLV_ID_MISMATCH_EN  ),
    
        .I_RID                      ( I_AOU_RX_AXI_S_RID            ),
        .I_RLAST                    ( I_AOU_RX_AXI_S_RLAST          ),
        .I_RVALID                   ( I_AOU_RX_AXI_S_RVALID       && I_AXI_SLV_ID_MISMATCH_EN  ),
        .I_RREADY                   ( I_AOU_RX_AXI_S_RREADY       && I_AXI_SLV_ID_MISMATCH_EN  ),

        .O_SLV_AXI_MISMATCH_RID     ( O_AXI_SLV_RID_MISMATCH_INFO   ),
        .O_SLV_AXI_MISMATCH_R_ERR   ( O_AXI_SLV_RID_MISMATCH_ERR_SET),
        .O_SLV_AXI_MISMATCH_BID     ( O_AXI_SLV_BID_MISMATCH_INFO   ),
        .O_SLV_AXI_MISMATCH_B_ERR   ( O_AXI_SLV_BID_MISMATCH_ERR_SET),
        .O_SLV_AXI_R_BLOCK          ( w_slv_axi_r_block             ),
        .O_SLV_AXI_B_BLOCK          ( w_slv_axi_b_block             ),

        .O_AW_HOLD_FLAG             ( w_aou_slv_info_aw_hold_flag   ),
        .O_W_HOLD_FLAG              ( w_aou_slv_info_w_hold_flag    ),
        .O_AR_HOLD_FLAG             ( O_AOU_SLV_INFO_AR_HOLD_FLAG   )
    );

    assign w_early_bresp_ctrl_bvalid_blocked    = I_EARLY_BRESP_CTRL_BVALID && (!w_slv_axi_b_block);
    assign w_aou_rx_axi_s_rvalid_blocked        = I_AOU_RX_AXI_S_RVALID && (!w_slv_axi_r_block);
    
    assign O_AOU_RX_AXI_S_RVALID_BLOCKED = w_aou_rx_axi_s_rvalid_blocked;
    assign w_early_bresp_ctrl_awready    = I_EARLY_BRESP_CTRL_AWREADY && ~w_aou_slv_info_aw_hold_flag;
    assign w_early_bresp_ctrl_wready     = I_EARLY_BRESP_CTRL_WREADY && ~w_aou_slv_info_w_hold_flag;
    assign O_EARLY_BRESP_CTRL_AWVALID    = w_early_bresp_ctrl_awvalid && ~w_aou_slv_info_aw_hold_flag;
    assign O_EARLY_BRESP_CTRL_WVALID     = w_early_bresp_ctrl_wvalid && ~w_aou_slv_info_w_hold_flag;
//----------------------------------------------------------------------------

    AOU_ISO_RS #(
        .DATA_WIDTH         (B_FIFO_WIDTH)
    ) u_aou_early_iso_rs
    (
        .I_CLK              (I_CLK                      ),                                          
        .I_RESETN           (I_RESETN                   ),                
    
        .I_SVALID           (w_early_bresp_ctrl_bvalid_blocked),            
        .I_SDATA            ({I_EARLY_BRESP_CTRL_BID, I_EARLY_BRESP_CTRL_BRESP}),
        .O_SREADY           (O_EARLY_BRESP_CTRL_BREADY),
    
        .I_MREADY           (w_early_bresp_ctrl_bready), 
        .O_MDATA            ({w_early_bresp_ctrl_bid, w_early_bresp_ctrl_bresp}),        
        .O_MVALID           (w_early_bresp_ctrl_bvalid)                                
    );

    AOU_EARLY_BRESP_CTRL_AWCACHE #(
        .AXI_DATA_WD                ( AXI_DATA_WD                       ), 
        .AXI_ADDR_WD                ( AXI_ADDR_WD                       ), 
        .AXI_ID_WD                  ( AXI_ID_WD                         ), 
        .AXI_LEN_WD                 ( AXI_LEN_WD                        ), 
                                    
        .AW_W_FIFO_CNT_DEPTH        ( 3                                 ),
        .WR_MO_CNT                  ( S_WR_MO_CNT                       )
    ) u_aou_early_bresp_s_ctrl
    (
        .I_CLK                      ( I_CLK                             ),
        .I_RESETN                   ( I_RESETN                          ),                    
    
        .I_AXI_S_AWID               ( I_AOU_TX_AXI_S_AWID               ),
        .I_AXI_S_AWADDR             ( I_AOU_TX_AXI_S_AWADDR             ),
        .I_AXI_S_AWLEN              ( I_AOU_TX_AXI_S_AWLEN              ),
        .I_AXI_S_AWSIZE             ( I_AOU_TX_AXI_S_AWSIZE             ),
        .I_AXI_S_AWBURST            ( I_AOU_TX_AXI_S_AWBURST            ),      
        .I_AXI_S_AWLOCK             ( I_AOU_TX_AXI_S_AWLOCK             ),
        .I_AXI_S_AWCACHE            ( I_AOU_TX_AXI_S_AWCACHE            ),
        .I_AXI_S_AWPROT             ( I_AOU_TX_AXI_S_AWPROT             ),
        .I_AXI_S_AWQOS              ( I_AOU_TX_AXI_S_AWQOS              ),
        .I_AXI_S_AWVALID            ( I_AOU_TX_AXI_S_AWVALID            ),
        .O_AXI_S_AWREADY            ( O_AOU_TX_AXI_S_AWREADY            ),
                                                    
        .I_AXI_S_WDATA              ( I_AOU_TX_AXI_S_WDATA              ),
        .I_AXI_S_WSTRB              ( I_AOU_TX_AXI_S_WSTRB              ),
        .I_AXI_S_WLAST              ( I_AOU_TX_AXI_S_WLAST              ),
        .I_AXI_S_WVALID             ( I_AOU_TX_AXI_S_WVALID             ),
        .O_AXI_S_WREADY             ( O_AOU_TX_AXI_S_WREADY             ),
                               
        .O_AXI_S_BID                ( O_AOU_RX_AXI_S_BID                ),
        .O_AXI_S_BRESP              ( O_AOU_RX_AXI_S_BRESP              ),
        .O_AXI_S_BVALID             ( O_AOU_RX_AXI_S_BVALID             ),
        .I_AXI_S_BREADY             ( I_AOU_RX_AXI_S_BREADY             ),                       
                               
        .O_AXI_M_AWID               ( O_EARLY_BRESP_CTRL_AWID           ),
        .O_AXI_M_AWADDR             ( O_EARLY_BRESP_CTRL_AWADDR         ),
        .O_AXI_M_AWLEN              ( O_EARLY_BRESP_CTRL_AWLEN          ),
        .O_AXI_M_AWSIZE             ( O_EARLY_BRESP_CTRL_AWSIZE         ),
        .O_AXI_M_AWBURST            ( O_EARLY_BRESP_CTRL_AWBURST        ),
        .O_AXI_M_AWLOCK             ( O_EARLY_BRESP_CTRL_AWLOCK         ),
        .O_AXI_M_AWCACHE            ( O_EARLY_BRESP_CTRL_AWCACHE        ),
        .O_AXI_M_AWPROT             ( O_EARLY_BRESP_CTRL_AWPROT         ),
        .O_AXI_M_AWQOS              ( O_EARLY_BRESP_CTRL_AWQOS          ),
        .O_AXI_M_AWVALID            ( w_early_bresp_ctrl_awvalid        ),
        .I_AXI_M_AWREADY            ( w_early_bresp_ctrl_awready        ),
                                            
        .O_AXI_M_WDATA              ( O_EARLY_BRESP_CTRL_WDATA          ),
        .O_AXI_M_WSTRB              ( O_EARLY_BRESP_CTRL_WSTRB          ),
        .O_AXI_M_WLAST              ( O_EARLY_BRESP_CTRL_WLAST          ),
        .O_AXI_M_WVALID             ( w_early_bresp_ctrl_wvalid         ),
        .I_AXI_M_WREADY             ( w_early_bresp_ctrl_wready         ),
                               
        .I_AXI_M_BID                ( w_early_bresp_ctrl_bid            ),
        .I_AXI_M_BRESP              ( w_early_bresp_ctrl_bresp          ),
        .I_AXI_M_BVALID             ( w_early_bresp_ctrl_bvalid         ),
        .O_AXI_M_BREADY             ( w_early_bresp_ctrl_bready         ),

        .I_EARLY_BRESP_EN           ( I_EARLY_BRESP_EN                  ),
        .I_EARLY_BRESP_ALWAYS_EN    ( I_EARLY_BRESP_ALWAYS_EN           ),
        .O_BRESP_DONE               ( O_EARLY_BRESP_DONE                ),
                               
        .O_BRESP_ERR                ( O_EARLY_BRESP_ERR_SET             ),
        .O_BRESP_ERR_ID             ( O_EARLY_BRESP_ERR_ID              ),
        .O_BRESP_ERR_TYPE           ( O_EARLY_BRESP_ERR_TYPE            ),
        
        .I_SFR_WDT_EN               ( I_EARLY_BRESP_WDT_EN              ), 
        .I_SFR_WDT_THRESHOLD        ( I_EARLY_BRESP_WDT_THRESHOLD       ),
        .O_AXI_WR_TRANS_TIMEOUT_ERR ( O_EARLY_BRESP_TRANS_TIMEOUT_ERR   )                             
    );

//----------------------------------------------------------------------------
    AOU_AXI4MUX_3X1_TOP #(
        .DATA_WD                        ( AXI_DATA_WD                       ),
        .ADDR_WD                        ( AXI_ADDR_WD                       ),
        .ID_WD                          ( AXI_ID_WD                         ),
        .LEN_WD                         ( AXI_LEN_WD                        ),
        .RD_MO_CNT                      ( M_RD_MO_CNT                       ),
        .WR_MO_CNT                      ( M_WR_MO_CNT                       ),
        .AOU_AGG_WCH_FIFO_DEPTH         ( AOU_AGG_WCH_FIFO_DEPTH            )
    ) u_aou_axi4mux_3x1_top
    (
        .I_CLK                          ( I_CLK                             ),
        .I_RESETN                       ( I_RESETN                          ),
    
        .O_S_RDLEN                      ( O_AOU_TX_AXI_RDLEN                ),
        .O_S_RID                        ( O_AOU_TX_AXI_RID                  ),
        .O_S_RDATA                      ( O_AOU_TX_AXI_RDATA                ),
        .O_S_RRESP                      ( O_AOU_TX_AXI_RRESP                ),
        .O_S_RLAST                      ( O_AOU_TX_AXI_RLAST                ),
        .O_S_RVALID                     ( O_AOU_TX_AXI_RVALID               ),
        .I_S_RREADY                     ( I_AOU_TX_AXI_RREADY               ),
    
        .I_S_ARID_0                     ( I_AOU_RX_AXI_MM_ARID              ),
        .I_S_ARADDR_0                   ( I_AOU_RX_AXI_MM_ARADDR            ),
        .I_S_ARLEN_0                    ( I_AOU_RX_AXI_MM_ARLEN             ),
        .I_S_ARSIZE_0                   ( I_AOU_RX_AXI_MM_ARSIZE            ),
        .I_S_ARBURST_0                  ( w_aou_rx_axi_mm_arburst           ),
        .I_S_ARCACHE_0                  ( I_AOU_RX_AXI_MM_ARCACHE           ),
        .I_S_ARPROT_0                   ( I_AOU_RX_AXI_MM_ARPROT            ),
        .I_S_ARLOCK_0                   ( I_AOU_RX_AXI_MM_ARLOCK            ),
        .I_S_ARQOS_0                    ( I_AOU_RX_AXI_MM_ARQOS             ),
        .I_S_ARVALID_0                  ( w_aou_rx_axi_mm_arvalid_256       ),
        .O_S_ARREADY_0                  ( w_aou_rx_axi_mm_arready_256       ),
    
        .I_S_AWID_0                     ( w_aou_rx_axi_mm_awid              ),
        .I_S_AWADDR_0                   ( w_aou_rx_axi_mm_awaddr            ),
        .I_S_AWLEN_0                    ( w_aou_rx_axi_mm_awlen             ),
        .I_S_AWSIZE_0                   ( w_aou_rx_axi_mm_awsize            ),
        .I_S_AWBURST_0                  ( w_aou_rx_axi_mm_awburst           ),
        .I_S_AWCACHE_0                  ( w_aou_rx_axi_mm_awcache           ),
        .I_S_AWPROT_0                   ( w_aou_rx_axi_mm_awprot            ),
        .I_S_AWLOCK_0                   ( w_aou_rx_axi_mm_awlock            ),
        .I_S_AWQOS_0                    ( w_aou_rx_axi_mm_awqos             ),
        .I_S_AWVALID_0                  ( w_aou_rx_axi_mm_awvalid_256       ),
        .O_S_AWREADY_0                  ( w_aou_rx_axi_mm_awready_256       ),
    
        .I_S_WDATA_0                    ( w_aou_rx_axi_mm_wdata[255:0]      ),
        .I_S_WSTRB_0                    ( w_aou_rx_axi_mm_wstrb[31:0]       ),
        .I_S_WLAST_0                    ( w_aou_rx_axi_mm_wlast             ),
        .I_S_WVALID_0                   ( w_aou_rx_axi_mm_wvalid_256        ),
        .O_S_WREADY_0                   ( w_aou_rx_axi_mm_wready_256        ),
    
        .O_S_BID_0                      ( O_AOU_TX_AXI_BID_256              ),
        .O_S_BRESP_0                    ( O_AOU_TX_AXI_BRESP_256            ),
        .O_S_BVALID_0                   ( O_AOU_TX_AXI_BVALID_256           ),
        .I_S_BREADY_0                   ( I_AOU_TX_AXI_BREADY_256           ),
    
        .I_S_ARID_1                     ( I_AOU_RX_AXI_MM_ARID              ),
        .I_S_ARADDR_1                   ( I_AOU_RX_AXI_MM_ARADDR            ),
        .I_S_ARLEN_1                    ( I_AOU_RX_AXI_MM_ARLEN             ),
        .I_S_ARSIZE_1                   ( I_AOU_RX_AXI_MM_ARSIZE            ),
        .I_S_ARBURST_1                  ( w_aou_rx_axi_mm_arburst           ),
        .I_S_ARCACHE_1                  ( I_AOU_RX_AXI_MM_ARCACHE           ),
        .I_S_ARPROT_1                   ( I_AOU_RX_AXI_MM_ARPROT            ),
        .I_S_ARLOCK_1                   ( I_AOU_RX_AXI_MM_ARLOCK            ),
        .I_S_ARQOS_1                    ( I_AOU_RX_AXI_MM_ARQOS             ),
        .I_S_ARVALID_1                  ( w_aou_rx_axi_mm_arvalid_512       ),
        .O_S_ARREADY_1                  ( w_aou_rx_axi_mm_arready_512       ),
    
        .I_S_AWID_1                     ( w_aou_rx_axi_mm_awid              ),
        .I_S_AWADDR_1                   ( w_aou_rx_axi_mm_awaddr            ),
        .I_S_AWLEN_1                    ( w_aou_rx_axi_mm_awlen             ),
        .I_S_AWSIZE_1                   ( w_aou_rx_axi_mm_awsize            ),
        .I_S_AWBURST_1                  ( w_aou_rx_axi_mm_awburst           ),
        .I_S_AWLOCK_1                   ( w_aou_rx_axi_mm_awlock            ),
        .I_S_AWCACHE_1                  ( w_aou_rx_axi_mm_awcache           ),
        .I_S_AWPROT_1                   ( w_aou_rx_axi_mm_awprot            ),
        .I_S_AWQOS_1                    ( w_aou_rx_axi_mm_awqos             ),
        .I_S_AWVALID_1                  ( w_aou_rx_axi_mm_awvalid_512       ),
        .O_S_AWREADY_1                  ( w_aou_rx_axi_mm_awready_512       ),
    
        .I_S_WDATA_1                    ( w_aou_rx_axi_mm_wdata[511:0]      ),
        .I_S_WSTRB_1                    ( w_aou_rx_axi_mm_wstrb[63:0]       ),
        .I_S_WLAST_1                    ( w_aou_rx_axi_mm_wlast             ),
        .I_S_WVALID_1                   ( w_aou_rx_axi_mm_wvalid_512        ),
        .O_S_WREADY_1                   ( w_aou_rx_axi_mm_wready_512        ),
    
        .O_S_BID_1                      ( O_AOU_TX_AXI_BID_512              ),
        .O_S_BRESP_1                    ( O_AOU_TX_AXI_BRESP_512            ),
        .O_S_BVALID_1                   ( O_AOU_TX_AXI_BVALID_512           ),
        .I_S_BREADY_1                   ( I_AOU_TX_AXI_BREADY_512           ),
    
        .I_S_ARID_2                     ( I_AOU_RX_AXI_MM_ARID              ),
        .I_S_ARADDR_2                   ( I_AOU_RX_AXI_MM_ARADDR            ),
        .I_S_ARLEN_2                    ( I_AOU_RX_AXI_MM_ARLEN             ),
        .I_S_ARSIZE_2                   ( I_AOU_RX_AXI_MM_ARSIZE            ),
        .I_S_ARBURST_2                  ( w_aou_rx_axi_mm_arburst           ),
        .I_S_ARCACHE_2                  ( I_AOU_RX_AXI_MM_ARCACHE           ),
        .I_S_ARPROT_2                   ( I_AOU_RX_AXI_MM_ARPROT            ),
        .I_S_ARLOCK_2                   ( I_AOU_RX_AXI_MM_ARLOCK            ),
        .I_S_ARQOS_2                    ( I_AOU_RX_AXI_MM_ARQOS             ),
        .I_S_ARVALID_2                  ( w_aou_rx_axi_mm_arvalid_1024      ),
        .O_S_ARREADY_2                  ( w_aou_rx_axi_mm_arready_1024      ),
    
        .I_S_AWID_2                     ( w_aou_rx_axi_mm_awid              ),
        .I_S_AWADDR_2                   ( w_aou_rx_axi_mm_awaddr            ),
        .I_S_AWLEN_2                    ( w_aou_rx_axi_mm_awlen             ),
        .I_S_AWSIZE_2                   ( w_aou_rx_axi_mm_awsize            ),
        .I_S_AWBURST_2                  ( w_aou_rx_axi_mm_awburst           ),
        .I_S_AWCACHE_2                  ( w_aou_rx_axi_mm_awcache           ),
        .I_S_AWPROT_2                   ( w_aou_rx_axi_mm_awprot            ),
        .I_S_AWLOCK_2                   ( w_aou_rx_axi_mm_awlock            ),
        .I_S_AWQOS_2                    ( w_aou_rx_axi_mm_awqos             ),
        .I_S_AWVALID_2                  ( w_aou_rx_axi_mm_awvalid_1024      ),
        .O_S_AWREADY_2                  ( w_aou_rx_axi_mm_awready_1024      ),
    
        .I_S_WDATA_2                    ( w_aou_rx_axi_mm_wdata             ),
        .I_S_WSTRB_2                    ( w_aou_rx_axi_mm_wstrb             ),
        .I_S_WLAST_2                    ( w_aou_rx_axi_mm_wlast             ),
        .I_S_WVALID_2                   ( w_aou_rx_axi_mm_wvalid_1024       ),
        .O_S_WREADY_2                   ( w_aou_rx_axi_mm_wready_1024       ),
    
        .O_S_BID_2                      ( O_AOU_TX_AXI_BID_1024             ),
        .O_S_BRESP_2                    ( O_AOU_TX_AXI_BRESP_1024           ),
        .O_S_BVALID_2                   ( O_AOU_TX_AXI_BVALID_1024          ),
        .I_S_BREADY_2                   ( I_AOU_TX_AXI_BREADY_1024          ),
    
        .O_M_ARID                       ( w_aou_err_info_axi_arid           ),
        .O_M_ARADDR                     ( w_aou_err_info_axi_araddr         ),
        .O_M_ARLEN                      ( w_aou_err_info_axi_arlen          ),
        .O_M_ARSIZE                     ( w_aou_err_info_axi_arsize         ),
        .O_M_ARBURST                    ( w_aou_err_info_axi_arburst        ),
        .O_M_ARCACHE                    ( w_aou_err_info_axi_arcache        ),
        .O_M_ARPROT                     ( w_aou_err_info_axi_arprot         ),
        .O_M_ARLOCK                     ( w_aou_err_info_axi_arlock         ),
        .O_M_ARQOS                      ( w_aou_err_info_axi_arqos          ),
        .O_M_ARVALID                    ( w_aou_err_info_axi_arvalid        ),
        .I_M_ARREADY                    ( w_aou_err_info_axi_arready        ),
    
        .I_M_RID                        ( w_aou_err_info_axi_rid            ),
        .I_M_RDATA                      ( w_aou_err_info_axi_rdata          ),
        .I_M_RRESP                      ( w_aou_err_info_axi_rresp          ),
        .I_M_RLAST                      ( w_aou_err_info_axi_rlast          ),
        .I_M_RVALID                     ( w_aou_err_info_axi_rvalid         ),
        .O_M_RREADY                     ( w_aou_err_info_axi_rready         ),
    
        .O_M_AWID                       ( w_aou_err_info_axi_awid           ),
        .O_M_AWADDR                     ( w_aou_err_info_axi_awaddr         ),
        .O_M_AWLEN                      ( w_aou_err_info_axi_awlen          ),
        .O_M_AWSIZE                     ( w_aou_err_info_axi_awsize         ),
        .O_M_AWBURST                    ( w_aou_err_info_axi_awburst        ),
        .O_M_AWLOCK                     ( w_aou_err_info_axi_awlock         ),
        .O_M_AWCACHE                    ( w_aou_err_info_axi_awcache        ),
        .O_M_AWPROT                     ( w_aou_err_info_axi_awprot         ),
        .O_M_AWQOS                      ( w_aou_err_info_axi_awqos          ),
        .O_M_AWVALID                    ( w_aou_err_info_axi_awvalid        ),
        .I_M_AWREADY                    ( w_aou_err_info_axi_awready        ),
    
        .O_M_WDATA                      ( w_aou_err_info_axi_wdata          ),
        .O_M_WSTRB                      ( w_aou_err_info_axi_wstrb          ),
        .O_M_WLAST                      ( w_aou_err_info_axi_wlast          ),
        .O_M_WVALID                     ( w_aou_err_info_axi_wvalid         ),
        .I_M_WREADY                     ( w_aou_err_info_axi_wready         ),
    
        .I_M_BID                        ( w_aou_err_info_axi_bid            ),
        .I_M_BRESP                      ( w_aou_err_info_axi_bresp          ),
        .I_M_BVALID                     ( w_aou_err_info_axi_bvalid         ),
        .O_M_BREADY                     ( w_aou_err_info_axi_bready         ),
       
        .I_MAX_AWBURSTLEN               ( I_AXI_SPLIT_TR_MAX_AWBURSTLEN     ),
        .I_MAX_ARBURSTLEN               ( I_AXI_SPLIT_TR_MAX_ARBURSTLEN     ),
    
        .I_AXI_AGGREGATOR_EN            ( I_AXI_AGGREGATOR_EN               ),
    
        .O_BRESP_ERR_ID                 ( w_axi_bresp_err_id                ),
        .O_BRESP_ERR_ADDR               ( w_axi_bresp_err_addr              ),
        .O_BRESP_ERR_BRESP              ( w_axi_bresp_err_bresp             ),
        .O_BRESP_ERR                    ( w_axi_bresp_err                   ),
    
        .O_RRESP_ERR_ID                 ( w_axi_rresp_err_id                ),
        .O_RRESP_ERR_ADDR               ( w_axi_rresp_err_addr              ),
        .O_RRESP_ERR_RRESP              ( w_axi_rresp_err_bresp             ),
        .O_RRESP_ERR                    ( w_axi_rresp_err                   ),

        .O_SPLIT_MISMATCH_BID           (O_ERROR_INFO_SPLIT_BID_MISMATCH_INFO       ),
        .O_SPLIT_MISMATCH_RID           (w_error_info_split_rid_mismatch_info       ), 
        .O_SPLIT_BID_MISMATCH_ERROR     (O_ERROR_INFO_SPLIT_BID_MISMATCH_ERR_SET    ),
        .O_SPLIT_RID_MISMATCH_ERROR     (w_error_info_split_rid_mismatch_err_set    ),
                                       
        .O_AGGRE_MISMATCH_RID           (w_error_info_aggre_rid_mismatch_info       ), 
        .O_AGGRE_RID_MISMATCH_ERROR     (w_error_info_aggre_rid_mismatch_err_set    ),
                                       
        .O_DOWN1024_MISMATCH_RID        (w_error_info_down1024_rid_mismatch_info    ), 
        .O_DOWN1024_RID_MISMATCH_ERROR  (w_error_info_down1024_rid_mismatch_err_set ),
                                       
        .O_DOWN512_MISMATCH_RID         (w_error_info_down512_rid_mismatch_info     ), 
        .O_DOWN512_RID_MISMATCH_ERROR   (w_error_info_down512_rid_mismatch_err_set  )

    );

always_comb begin
    O_ERROR_INFO_RID_MISMATCH_ERR_SET = 1'b0;
    O_ERROR_INFO_RID_MISMATCH_INFO    = {AXI_ID_WD{1'b0}};

    if (w_error_info_split_rid_mismatch_err_set) begin
        O_ERROR_INFO_RID_MISMATCH_ERR_SET = 1'b1;
        O_ERROR_INFO_RID_MISMATCH_INFO    = w_error_info_split_rid_mismatch_info;
    end
    else if (w_error_info_aggre_rid_mismatch_err_set) begin
        O_ERROR_INFO_RID_MISMATCH_ERR_SET = 1'b1;
        O_ERROR_INFO_RID_MISMATCH_INFO    = w_error_info_aggre_rid_mismatch_info;
    end
    else if (w_error_info_down512_rid_mismatch_err_set) begin
        O_ERROR_INFO_RID_MISMATCH_ERR_SET = 1'b1;
        O_ERROR_INFO_RID_MISMATCH_INFO    = w_error_info_down512_rid_mismatch_info;
    end
    else if (w_error_info_down1024_rid_mismatch_err_set) begin
        O_ERROR_INFO_RID_MISMATCH_ERR_SET = 1'b1;
        O_ERROR_INFO_RID_MISMATCH_INFO    = w_error_info_down1024_rid_mismatch_info;
    end
end
//-------------------------------------------------------------
    logic   w_aou_rx_fifo_pending;
    
    assign w_aou_rx_fifo_pending = I_AOU_RX_WLAST_GEN_AWVALID | I_AOU_RX_AXI_MM_ARVALID | I_AOU_RX_WLAST_GEN_WVALID | I_EARLY_BRESP_CTRL_BVALID | I_AOU_RX_AXI_S_RVALID;
    
    //BUS CLEANY MO CNT is 32. Never occurs overflow
    logic [9:0]    r_slv_wr_pending_cnt;
    logic [9:0]    r_slv_rd_pending_cnt;

    always_ff @ (posedge I_CLK or negedge I_RESETN) begin
        if (~I_RESETN) begin
            r_slv_wr_pending_cnt <= 'd0;
        end else if ((I_AOU_TX_AXI_S_AWVALID & O_AOU_TX_AXI_S_AWREADY) & ~(O_AOU_RX_AXI_S_BVALID & I_AOU_RX_AXI_S_BREADY)) begin
            r_slv_wr_pending_cnt <= r_slv_wr_pending_cnt + 1;
        end else if (~(I_AOU_TX_AXI_S_AWVALID & O_AOU_TX_AXI_S_AWREADY) & (O_AOU_RX_AXI_S_BVALID & I_AOU_RX_AXI_S_BREADY)) begin
            r_slv_wr_pending_cnt <= r_slv_wr_pending_cnt - 1;
        end
    end
    
    always_ff @ (posedge I_CLK or negedge I_RESETN) begin
        if (~I_RESETN) begin
            r_slv_rd_pending_cnt <= 'd0;
        end else if ((I_AOU_TX_AXI_S_ARVALID & I_AOU_TX_AXI_S_ARREADY) & ~(I_AOU_RX_AXI_S_RVALID & I_AOU_RX_AXI_S_RREADY & I_AOU_RX_AXI_S_RLAST)) begin
            r_slv_rd_pending_cnt <= r_slv_rd_pending_cnt + 1;
        end else if (~(I_AOU_TX_AXI_S_ARVALID & I_AOU_TX_AXI_S_ARREADY) & (I_AOU_RX_AXI_S_RVALID & I_AOU_RX_AXI_S_RREADY & I_AOU_RX_AXI_S_RLAST)) begin
            r_slv_rd_pending_cnt <= r_slv_rd_pending_cnt - 1;
        end
    end


    //mst pending cnt
    logic [9:0]    r_mst_wr_pending_cnt;
    logic [9:0]    r_mst_rd_pending_cnt;

    logic          w_b_256_hs;
    logic          w_b_512_hs;
    logic          w_b_1024_hs;
    
    logic          w_rdata_256_last_hs;
    logic          w_rdata_512_last_hs;
    logic          w_rdata_1024_last_hs;

    assign w_b_256_hs           = O_AOU_TX_AXI_BVALID_256  & I_AOU_TX_AXI_BREADY_256;
    assign w_b_512_hs           = O_AOU_TX_AXI_BVALID_512  & I_AOU_TX_AXI_BREADY_512;
    assign w_b_1024_hs          = O_AOU_TX_AXI_BVALID_1024 & I_AOU_TX_AXI_BREADY_1024;
    
    assign w_rdata_256_last_hs  = O_AOU_TX_AXI_RVALID & I_AOU_TX_AXI_RREADY & O_AOU_TX_AXI_RLAST & (O_AOU_TX_AXI_RDLEN == 2'b00);
    assign w_rdata_512_last_hs  = O_AOU_TX_AXI_RVALID & I_AOU_TX_AXI_RREADY & O_AOU_TX_AXI_RLAST & (O_AOU_TX_AXI_RDLEN == 2'b01);
    assign w_rdata_1024_last_hs = O_AOU_TX_AXI_RVALID & I_AOU_TX_AXI_RREADY & O_AOU_TX_AXI_RLAST & (O_AOU_TX_AXI_RDLEN == 2'b10);
    
    always_ff @ (posedge I_CLK or negedge I_RESETN) begin
        if (~I_RESETN) begin
            r_mst_wr_pending_cnt <= 'd0;
        end else if ((I_AOU_RX_WLAST_GEN_AWVALID && O_AOU_RX_WLAST_GEN_AWREADY) & ~(w_b_256_hs | w_b_512_hs | w_b_1024_hs)) begin
            r_mst_wr_pending_cnt <= r_mst_wr_pending_cnt + 1;
        end else if (~(I_AOU_RX_WLAST_GEN_AWVALID && O_AOU_RX_WLAST_GEN_AWREADY) & (w_b_256_hs | w_b_512_hs | w_b_1024_hs)) begin
            r_mst_wr_pending_cnt <= r_mst_wr_pending_cnt - 1;
        end
    end

    always_ff @ (posedge I_CLK or negedge I_RESETN) begin
        if (~I_RESETN) begin
            r_mst_rd_pending_cnt <= 'd0;
        end else if ((I_AOU_RX_AXI_MM_ARVALID && O_AOU_RX_AXI_MM_ARREADY) & ~(w_rdata_256_last_hs | w_rdata_512_last_hs | w_rdata_1024_last_hs)) begin
            r_mst_rd_pending_cnt <= r_mst_rd_pending_cnt + 1;
        end else if (~(I_AOU_RX_AXI_MM_ARVALID && O_AOU_RX_AXI_MM_ARREADY) & (w_rdata_256_last_hs | w_rdata_512_last_hs | w_rdata_1024_last_hs)) begin
            r_mst_rd_pending_cnt <= r_mst_rd_pending_cnt - 1;
        end
    end 

    assign O_SLV_TR_COMPLETE = O_EARLY_BRESP_DONE & (~(|r_slv_wr_pending_cnt) & ~(|r_slv_rd_pending_cnt));
    assign O_MST_TR_COMPLETE = (~(|r_mst_wr_pending_cnt) & ~(|r_mst_rd_pending_cnt));
    

//-------------------------------------------------------------

    AOU_AXI_WLAST_GEN #(
        .DATA_WD                    ( AXI_PEER_DIE_MAX_DATA_WD      ),
        .ADDR_WD                    ( AXI_ADDR_WD                   ),
        .ID_WD                      ( AXI_ID_WD                     ),
        .STRB_WD                    ( AXI_PEER_DIE_MAX_DATA_WD/8    ),
        .QOS_WD                     ( 4                             ),
        .LEN_WD                     ( AXI_LEN_WD                    )
    ) u_wlast_gen
    (
        .I_CLK                      ( I_CLK                         ),
        .I_RESETN                   ( I_RESETN                      ),
    
        .I_S_AWID                   ( I_AOU_RX_WLAST_GEN_AWID       ),
        .I_S_AWADDR                 ( I_AOU_RX_WLAST_GEN_AWADDR     ),
        .I_S_AWLEN                  ( I_AOU_RX_WLAST_GEN_AWLEN      ),
        .I_S_AWSIZE                 ( I_AOU_RX_WLAST_GEN_AWSIZE     ),
        .I_S_AWLOCK                 ( I_AOU_RX_WLAST_GEN_AWLOCK     ),
        .I_S_AWCACHE                ( I_AOU_RX_WLAST_GEN_AWCACHE    ),
        .I_S_AWPROT                 ( I_AOU_RX_WLAST_GEN_AWPROT     ),
        .I_S_AWQOS                  ( I_AOU_RX_WLAST_GEN_AWQOS      ),
        .I_S_AWVALID                ( I_AOU_RX_WLAST_GEN_AWVALID    ),
        .O_S_AWREADY                ( O_AOU_RX_WLAST_GEN_AWREADY    ),
    
        .I_S_WDLENGTH               ( I_AOU_RX_WLAST_GEN_WDLENGTH   ),
        .I_S_WDATA                  ( I_AOU_RX_WLAST_GEN_WDATA      ),
        .I_S_WSTRB                  ( I_AOU_RX_WLAST_GEN_WSTRB      ),
        .I_S_WVALID                 ( I_AOU_RX_WLAST_GEN_WVALID     ),
        .O_S_WREADY                 ( O_AOU_RX_WLAST_GEN_WREADY     ),
    
        .O_M_AWID                   ( w_aou_rx_axi_mm_awid          ),
        .O_M_AWADDR                 ( w_aou_rx_axi_mm_awaddr        ),
        .O_M_AWLEN                  ( w_aou_rx_axi_mm_awlen         ),
        .O_M_AWSIZE                 ( w_aou_rx_axi_mm_awsize        ),
        .O_M_AWLOCK                 ( w_aou_rx_axi_mm_awlock        ),
        .O_M_AWCACHE                ( w_aou_rx_axi_mm_awcache       ),
        .O_M_AWPROT                 ( w_aou_rx_axi_mm_awprot        ),
        .O_M_AWQOS                  ( w_aou_rx_axi_mm_awqos         ),
        .O_M_AWVALID_256            ( w_aou_rx_axi_mm_awvalid_256   ),
        .O_M_AWVALID_512            ( w_aou_rx_axi_mm_awvalid_512   ),
        .O_M_AWVALID_1024           ( w_aou_rx_axi_mm_awvalid_1024  ),
        .I_M_AWREADY_256            ( w_aou_rx_axi_mm_awready_256   ),
        .I_M_AWREADY_512            ( w_aou_rx_axi_mm_awready_512   ),
        .I_M_AWREADY_1024           ( w_aou_rx_axi_mm_awready_1024  ),
    
        .O_M_WDLENGTH               (                               ),
        .O_M_WDATA                  ( w_aou_rx_axi_mm_wdata         ),
        .O_M_WSTRB                  ( w_aou_rx_axi_mm_wstrb         ),
        .O_M_WLAST                  ( w_aou_rx_axi_mm_wlast         ),
        .O_M_WVALID_256             ( w_aou_rx_axi_mm_wvalid_256    ),
        .O_M_WVALID_512             ( w_aou_rx_axi_mm_wvalid_512    ),
        .O_M_WVALID_1024            ( w_aou_rx_axi_mm_wvalid_1024   ),
        .I_M_WREADY_256             ( w_aou_rx_axi_mm_wready_256    ),
        .I_M_WREADY_512             ( w_aou_rx_axi_mm_wready_512    ),
        .I_M_WREADY_1024            ( w_aou_rx_axi_mm_wready_1024   )
    );
    
    assign O_AOU_RX_AXI_MM_ARREADY = (w_aou_rx_axi_mm_arready_256 & (I_AOU_RX_AXI_MM_ARSIZE < 3'b110)) | (w_aou_rx_axi_mm_arready_512 & (I_AOU_RX_AXI_MM_ARSIZE == 3'b110)) | (w_aou_rx_axi_mm_arready_1024 & (I_AOU_RX_AXI_MM_ARSIZE == 3'b111));
        
    
    assign  w_aou_rx_axi_mm_arburst  = 2'b01;
    assign  w_aou_rx_axi_mm_awburst  = 2'b01;

endmodule
