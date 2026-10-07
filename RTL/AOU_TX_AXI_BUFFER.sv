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
//  Module     : AOU_TX_AXI_BUFFER
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TX_AXI_BUFFER
import packet_def_pkg::*;
#(
    parameter   RP_CNT                  = 4,
    parameter   RP0_AXI_DATA_WD         = 512,
    parameter   RP1_AXI_DATA_WD         = 512,
    parameter   RP2_AXI_DATA_WD         = 512,
    parameter   RP3_AXI_DATA_WD         = 512,
    parameter   MAX_AXI_DATA_WD         = 1024,
    parameter   AXI_ADDR_WD             = 64,
    parameter   AXI_ID_WD               = 10,
    parameter   AXI_LEN_WD              = 8,

    localparam  RP0_AXI_STRB_WD         = RP0_AXI_DATA_WD / 8,
    localparam  RP1_AXI_STRB_WD         = RP1_AXI_DATA_WD / 8,
    localparam  RP2_AXI_STRB_WD         = RP2_AXI_DATA_WD / 8,
    localparam  RP3_AXI_STRB_WD         = RP3_AXI_DATA_WD / 8,
    localparam  MAX_AXI_STRB_WD         = MAX_AXI_DATA_WD / 8,

    parameter   CNT_RP0_AW_MAX_CREDIT = 8,
    parameter   CNT_RP0_W_MAX_CREDIT  = 8,
    parameter   CNT_RP0_B_MAX_CREDIT  = 8,
    parameter   CNT_RP0_AR_MAX_CREDIT = 8,
    parameter   CNT_RP0_R_MAX_CREDIT  = 8,

    parameter   CNT_RP1_AW_MAX_CREDIT = 8,
    parameter   CNT_RP1_W_MAX_CREDIT  = 8,
    parameter   CNT_RP1_B_MAX_CREDIT  = 8,
    parameter   CNT_RP1_AR_MAX_CREDIT = 8,
    parameter   CNT_RP1_R_MAX_CREDIT  = 8,

    parameter   CNT_RP2_AW_MAX_CREDIT = 8,
    parameter   CNT_RP2_W_MAX_CREDIT  = 8,
    parameter   CNT_RP2_B_MAX_CREDIT  = 8,
    parameter   CNT_RP2_AR_MAX_CREDIT = 8,
    parameter   CNT_RP2_R_MAX_CREDIT  = 8,

    parameter   CNT_RP3_AW_MAX_CREDIT = 8,
    parameter   CNT_RP3_W_MAX_CREDIT  = 8,
    parameter   CNT_RP3_B_MAX_CREDIT  = 8,
    parameter   CNT_RP3_AR_MAX_CREDIT = 8,
    parameter   CNT_RP3_R_MAX_CREDIT  = 8,


    parameter   AXI_AW_FIFO_DEPTH   = 8,
    parameter   AXI_W_FIFO_DEPTH    = 8,
    parameter   AXI_B_FIFO_DEPTH    = 8,
    parameter   AXI_AR_FIFO_DEPTH   = 8,
    parameter   AXI_R_FIFO_DEPTH    = 8,

    parameter   USE_AOU_TX_BUF_HIGH_SPEED = 1,

    localparam  CNT_RP_AW_MAX_CREDIT_MAX = max4(CNT_RP0_AW_MAX_CREDIT, CNT_RP1_AW_MAX_CREDIT, CNT_RP2_AW_MAX_CREDIT, CNT_RP3_AW_MAX_CREDIT),
    localparam  CNT_RP_AR_MAX_CREDIT_MAX = max4(CNT_RP0_AR_MAX_CREDIT, CNT_RP1_AR_MAX_CREDIT, CNT_RP2_AR_MAX_CREDIT, CNT_RP3_AR_MAX_CREDIT),
    localparam  CNT_RP_W_MAX_CREDIT_MAX  = max4(CNT_RP0_W_MAX_CREDIT,  CNT_RP1_W_MAX_CREDIT,  CNT_RP2_W_MAX_CREDIT,  CNT_RP3_W_MAX_CREDIT),
    localparam  CNT_RP_R_MAX_CREDIT_MAX  = max4(CNT_RP0_R_MAX_CREDIT,  CNT_RP1_R_MAX_CREDIT,  CNT_RP2_R_MAX_CREDIT,  CNT_RP3_R_MAX_CREDIT),
    localparam  CNT_RP_B_MAX_CREDIT_MAX  = max4(CNT_RP0_B_MAX_CREDIT,  CNT_RP1_B_MAX_CREDIT,  CNT_RP2_B_MAX_CREDIT,  CNT_RP3_B_MAX_CREDIT)


)
( 
    input  logic                             I_CLK,
    input  logic                             I_RESETN,

    //Interface for RP0 input
    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_S_AXI_AWID,
    input  logic    [RP_CNT-1:0][AXI_ADDR_WD-1:0]        I_AOU_TX_S_AXI_AWADDR,
    input  logic    [RP_CNT-1:0][AXI_LEN_WD-1:0]         I_AOU_TX_S_AXI_AWLEN,
    input  logic    [RP_CNT-1:0][2:0]                    I_AOU_TX_S_AXI_AWSIZE,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_AWBURST,       //There is no burst field on AOU
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_AWLOCK,
    input  logic    [RP_CNT-1:0][3:0]                    I_AOU_TX_S_AXI_AWCACHE,
    input  logic    [RP_CNT-1:0][2:0]                    I_AOU_TX_S_AXI_AWPROT,
    input  logic    [RP_CNT-1:0][3:0]                    I_AOU_TX_S_AXI_AWQOS,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_AWVALID,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_AWREADY,      

    input  logic    [RP_CNT-1:0][MAX_AXI_DATA_WD-1:0]    I_AOU_TX_S_AXI_WDATA,
    input  logic    [RP_CNT-1:0][MAX_AXI_STRB_WD-1:0]    I_AOU_TX_S_AXI_WSTRB,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_WLAST,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_WVALID,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_WREADY,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_S_AXI_ARID,
    input  logic    [RP_CNT-1:0][AXI_ADDR_WD-1:0]        I_AOU_TX_S_AXI_ARADDR,
    input  logic    [RP_CNT-1:0][AXI_LEN_WD-1:0]         I_AOU_TX_S_AXI_ARLEN,
    input  logic    [RP_CNT-1:0][2:0]                    I_AOU_TX_S_AXI_ARSIZE,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_ARBURST,       //There is no burst field on AOU
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_ARLOCK,
    input  logic    [RP_CNT-1:0][3:0]                    I_AOU_TX_S_AXI_ARCACHE,
    input  logic    [RP_CNT-1:0][2:0]                    I_AOU_TX_S_AXI_ARPROT,
    input  logic    [RP_CNT-1:0][3:0]                    I_AOU_TX_S_AXI_ARQOS,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_ARVALID,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_ARREADY,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_S_AXI_BID_256,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_BRESP_256,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_BVALID_256,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_BREADY_256,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_S_AXI_BID_512,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_BRESP_512,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_BVALID_512,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_BREADY_512,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_S_AXI_BID_1024,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_BRESP_1024,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_BVALID_1024,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_BREADY_1024,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_S_AXI_RID,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_RDLEN,
    input  logic    [RP_CNT-1:0][1024-1:0]               I_AOU_TX_S_AXI_RDATA,
    input  logic    [RP_CNT-1:0][1:0]                    I_AOU_TX_S_AXI_RRESP,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_RLAST,
    input  logic    [RP_CNT-1:0]                         I_AOU_TX_S_AXI_RVALID,
    output logic    [RP_CNT-1:0]                         O_AOU_TX_S_AXI_RREADY,

    //AXI output port
    output logic    [40*AW_G-1:0]                        O_AOU_TX_M_AXI_AW_MESSAGE,
    output logic                                         O_AOU_TX_M_AXI_AWVALID,
    input  logic                                         I_AOU_TX_M_AXI_AWREADY,

    output logic    [1:0]                                O_AOU_TX_M_AXI_W_RP,
    output logic    [40*W1024b_G-1:0]                    O_AOU_TX_M_AXI_W_MESSAGE,
    output logic                                         O_AOU_TX_M_AXI_WSTRB_FULL,
    output logic                                         O_AOU_TX_M_AXI_WVALID,
    input  logic                                         I_AOU_TX_M_AXI_WREADY,

    output logic    [40*B_G-1:0]                         O_AOU_TX_M_AXI_B_MESSAGE,
    output logic                                         O_AOU_TX_M_AXI_BVALID,
    input  logic                                         I_AOU_TX_M_AXI_BREADY,

    output logic    [40*AR_G-1:0]                        O_AOU_TX_M_AXI_AR_MESSAGE,
    output logic                                         O_AOU_TX_M_AXI_ARVALID,
    input  logic                                         I_AOU_TX_M_AXI_ARREADY,

    output logic    [1:0]                                O_AOU_TX_M_AXI_RDLEN,
    output logic    [40*R1024b_G-1:0]                    O_AOU_TX_M_AXI_R_MESSAGE,
    output logic                                         O_AOU_TX_M_AXI_RVALID,
    input  logic                                         I_AOU_TX_M_AXI_RREADY,

    //Credit for TX 
    input  logic    [RP_CNT-1:0][CNT_RP_AW_MAX_CREDIT_MAX-1:0]  I_AOU_TX_WREQCRED,
    input  logic    [RP_CNT-1:0][CNT_RP_AR_MAX_CREDIT_MAX-1:0]  I_AOU_TX_RREQCRED,
    input  logic    [RP_CNT-1:0][CNT_RP_W_MAX_CREDIT_MAX -1:0]  I_AOU_TX_WDATACRED,
    input  logic    [RP_CNT-1:0][CNT_RP_R_MAX_CREDIT_MAX -1:0]  I_AOU_TX_RDATACRED,
    input  logic    [RP_CNT-1:0][CNT_RP_B_MAX_CREDIT_MAX -1:0]  I_AOU_TX_WRESPCRED,


    //Interface for TX Credit - transaction valid
    output logic    [RP_CNT-1:0]                            O_AOU_TX_WREQVALID,
    output logic    [RP_CNT-1:0]                            O_AOU_TX_RREQVALID, 
    output logic    [RP_CNT-1:0]                            O_AOU_TX_WDATAVALID,
    output logic    [RP_CNT-1:0]                            O_AOU_TX_WFDATA,
    output logic    [RP_CNT-1:0]                            O_AOU_TX_RDATAVALID,
    output logic    [RP_CNT-1:0][1:0]                       O_AOU_TX_RDATA_DLENGTH,
    output logic    [RP_CNT-1:0]                            O_AOU_TX_WRESPVALID,

    input  logic    [3:0][1:0]                              I_RP_DEST_RP,

    input  logic    [3:0]                                   I_PRIOR_RP_AXI_AXI_QOS_TO_NP    ,    
    input  logic    [3:0]                                   I_PRIOR_RP_AXI_AXI_QOS_TO_HP    ,    
    input  logic    [1:0]                                   I_PRIOR_RP_AXI_RP3_PRIOR        ,    
    input  logic    [1:0]                                   I_PRIOR_RP_AXI_RP2_PRIOR        ,    
    input  logic    [1:0]                                   I_PRIOR_RP_AXI_RP1_PRIOR        ,    
    input  logic    [1:0]                                   I_PRIOR_RP_AXI_RP0_PRIOR        ,    
    input  logic    [1:0]                                   I_PRIOR_RP_AXI_ARB_MODE         ,    
    input  logic    [15:0]                                  I_PRIOR_TIMER_TIMER_RESOLUTION  ,    
    input  logic    [15:0]                                  I_PRIOR_TIMER_TIMER_THRESHOLD   ,
    
    input  logic                                            I_AOU_WRITEFULL_MSGTYPE_EN

);

// parameter                
localparam RP0_W_G_SIZE          = (RP0_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP0_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP0_AXI_DATA_WD == 1024)? W1024b_G : 0;
                            
localparam RP1_W_G_SIZE          = (RP1_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP1_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP1_AXI_DATA_WD == 1024)? W1024b_G : 0;

localparam RP2_W_G_SIZE          = (RP2_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP2_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP2_AXI_DATA_WD == 1024)? W1024b_G : 0;
                            
localparam RP3_W_G_SIZE          = (RP3_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP3_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP3_AXI_DATA_WD == 1024)? W1024b_G : 0;

localparam RP0_WF_G_SIZE         = (RP0_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP0_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP0_AXI_DATA_WD == 1024)? WF1024b_G : 0;
                            
localparam RP1_WF_G_SIZE         = (RP1_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP1_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP1_AXI_DATA_WD == 1024)? WF1024b_G : 0;

localparam RP2_WF_G_SIZE         = (RP2_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP2_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP2_AXI_DATA_WD == 1024)? WF1024b_G : 0;
                            
localparam RP3_WF_G_SIZE         = (RP3_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP3_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP3_AXI_DATA_WD == 1024)? WF1024b_G : 0;


localparam int RP_W_G_SIZE  [4] = '{RP0_W_G_SIZE, RP1_W_G_SIZE, RP2_W_G_SIZE, RP3_W_G_SIZE};
localparam int RP_WF_G_SIZE [4] = '{RP0_WF_G_SIZE, RP1_WF_G_SIZE, RP2_WF_G_SIZE, RP3_WF_G_SIZE};

localparam int RP_AXI_DATA_WD [4] = '{RP0_AXI_DATA_WD, RP1_AXI_DATA_WD, RP2_AXI_DATA_WD, RP3_AXI_DATA_WD};
localparam int RP_AXI_STRB_WD [4] = '{RP0_AXI_STRB_WD, RP1_AXI_STRB_WD, RP2_AXI_STRB_WD, RP3_AXI_STRB_WD};

logic       [RP_CNT-1:0][AXI_ID_WD-1:0]         w_aou_tx_m_axi_awid;
logic       [RP_CNT-1:0][AXI_ADDR_WD-1:0]       w_aou_tx_m_axi_awaddr;
logic       [RP_CNT-1:0][AXI_LEN_WD-1:0]        w_aou_tx_m_axi_awlen;
logic       [RP_CNT-1:0][2:0]                   w_aou_tx_m_axi_awsize;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_awlock;
logic       [RP_CNT-1:0][3:0]                   w_aou_tx_m_axi_awcache;
logic       [RP_CNT-1:0][2:0]                   w_aou_tx_m_axi_awprot;
logic       [RP_CNT-1:0][3:0]                   w_aou_tx_m_axi_awqos;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_awvalid;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_awready;

logic       [RP_CNT-1:0][MAX_AXI_DATA_WD-1:0]   w_aou_tx_m_axi_wdata;
logic       [RP_CNT-1:0][MAX_AXI_STRB_WD-1:0]   w_aou_tx_m_axi_wstrb;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_wlast;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_wstrb_full;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_wvalid;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_wready;

logic       [RP_CNT-1:0][AXI_ID_WD-1:0]         w_granted_fifo_bid;
logic       [RP_CNT-1:0][1:0]                   w_granted_fifo_bresp;
logic       [RP_CNT-1:0]                        w_granted_fifo_bvalid;
logic       [RP_CNT-1:0]                        w_granted_fifo_bready;

logic       [RP_CNT-1:0][AXI_ID_WD-1:0]         w_aou_tx_s_axi_bid;
logic       [RP_CNT-1:0][1:0]                   w_aou_tx_s_axi_bresp;
logic       [RP_CNT-1:0]                        w_aou_tx_s_axi_bvalid;
logic       [RP_CNT-1:0]                        w_aou_tx_s_axi_bready;

logic       [RP_CNT-1:0][AXI_ID_WD-1:0]         w_aou_tx_m_axi_arid;
logic       [RP_CNT-1:0][AXI_ADDR_WD-1:0]       w_aou_tx_m_axi_araddr;
logic       [RP_CNT-1:0][AXI_LEN_WD-1:0]        w_aou_tx_m_axi_arlen;
logic       [RP_CNT-1:0][2:0]                   w_aou_tx_m_axi_arsize;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_arlock;
logic       [RP_CNT-1:0][3:0]                   w_aou_tx_m_axi_arcache;
logic       [RP_CNT-1:0][2:0]                   w_aou_tx_m_axi_arprot;
logic       [RP_CNT-1:0][3:0]                   w_aou_tx_m_axi_arqos;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_arvalid;
logic       [RP_CNT-1:0]                        w_aou_tx_m_axi_arready;

logic       [RP_CNT-1:0][AXI_ID_WD-1:0]         w_aou_tx_s_axi_rid;
logic       [RP_CNT-1:0][1:0]                   w_aou_tx_s_axi_rdlen;
logic       [RP_CNT-1:0][1024-1:0]              w_aou_tx_s_axi_rdata;
logic       [RP_CNT-1:0][1:0]                   w_aou_tx_s_axi_rresp;
logic       [RP_CNT-1:0]                        w_aou_tx_s_axi_rlast;
logic       [RP_CNT-1:0]                        w_aou_tx_s_axi_rvalid;
logic       [RP_CNT-1:0]                        w_aou_tx_s_axi_rready;

// FIFO ==============================================================
logic     [1:0]                   w_aou_tx_fifo_m_axi_aw_rp;
logic     [AXI_ID_WD-1:0]         w_aou_tx_fifo_m_axi_awid;
logic     [AXI_ADDR_WD-1:0]       w_aou_tx_fifo_m_axi_awaddr;
logic     [AXI_LEN_WD-1:0]        w_aou_tx_fifo_m_axi_awlen;
logic     [2:0]                   w_aou_tx_fifo_m_axi_awsize;
logic                             w_aou_tx_fifo_m_axi_awlock;
logic     [3:0]                   w_aou_tx_fifo_m_axi_awcache;
logic     [2:0]                   w_aou_tx_fifo_m_axi_awprot;
logic     [3:0]                   w_aou_tx_fifo_m_axi_awqos;
logic                             w_aou_tx_fifo_m_axi_awvalid;
logic                             w_aou_tx_fifo_m_axi_awready;

logic     [MAX_AXI_DATA_WD-1:0]   w_aou_tx_fifo_m_axi_wdata;
logic     [MAX_AXI_STRB_WD-1:0]   w_aou_tx_fifo_m_axi_wstrb;
logic                             w_aou_tx_fifo_m_axi_wlast;
logic                             w_aou_tx_fifo_m_axi_wstrb_full;
logic                             w_aou_tx_fifo_m_axi_wvalid;
logic                             w_aou_tx_fifo_m_axi_wready;

logic     [1:0]                   w_aou_tx_fifo_m_axi_aw_rp_tmp  ;
logic     [AXI_ID_WD-1:0]         w_aou_tx_fifo_m_axi_awid_tmp;
logic     [AXI_ADDR_WD-1:0]       w_aou_tx_fifo_m_axi_awaddr_tmp;
logic     [AXI_LEN_WD-1:0]        w_aou_tx_fifo_m_axi_awlen_tmp;
logic     [2:0]                   w_aou_tx_fifo_m_axi_awsize_tmp;
logic                             w_aou_tx_fifo_m_axi_awlock_tmp;
logic     [3:0]                   w_aou_tx_fifo_m_axi_awcache_tmp;
logic     [2:0]                   w_aou_tx_fifo_m_axi_awprot_tmp;
logic     [3:0]                   w_aou_tx_fifo_m_axi_awqos_tmp;
logic                             w_aou_tx_fifo_m_axi_awvalid_tmp;
logic                             w_aou_tx_fifo_m_axi_awready_tmp;

logic     [1:0]                   w_aou_tx_fifo_m_axi_w_rp_tmp;
logic     [MAX_AXI_DATA_WD-1:0]   w_aou_tx_fifo_m_axi_wdata_tmp;
logic     [MAX_AXI_STRB_WD-1:0]   w_aou_tx_fifo_m_axi_wstrb_tmp;
logic                             w_aou_tx_fifo_m_axi_wlast_tmp;
logic                             w_aou_tx_fifo_m_axi_wstrb_full_tmp;
logic                             w_aou_tx_fifo_m_axi_wvalid_tmp;
logic                             w_aou_tx_fifo_m_axi_wready_tmp;

logic     [1:0]                   w_aou_tx_fifo_s_axi_b_rp;
logic     [AXI_ID_WD-1:0]         w_aou_tx_fifo_s_axi_bid;
logic     [1:0]                   w_aou_tx_fifo_s_axi_bresp;
logic                             w_aou_tx_fifo_s_axi_bvalid;
logic                             w_aou_tx_fifo_s_axi_bready;

logic     [1:0]                   w_aou_tx_fifo_m_axi_ar_rp;
logic     [AXI_ID_WD-1:0]         w_aou_tx_fifo_m_axi_arid;
logic     [AXI_ADDR_WD-1:0]       w_aou_tx_fifo_m_axi_araddr;
logic     [AXI_LEN_WD-1:0]        w_aou_tx_fifo_m_axi_arlen;
logic     [2:0]                   w_aou_tx_fifo_m_axi_arsize;
logic                             w_aou_tx_fifo_m_axi_arlock;
logic     [3:0]                   w_aou_tx_fifo_m_axi_arcache;
logic     [2:0]                   w_aou_tx_fifo_m_axi_arprot;
logic     [3:0]                   w_aou_tx_fifo_m_axi_arqos;
logic                             w_aou_tx_fifo_m_axi_arvalid;
logic                             w_aou_tx_fifo_m_axi_arready;

logic     [1:0]                   w_aou_tx_fifo_m_axi_r_rp;
logic     [AXI_ID_WD-1:0]         w_aou_tx_fifo_s_axi_rid;
logic     [1:0]                   w_aou_tx_fifo_s_axi_rdlen;
logic     [1024-1:0]              w_aou_tx_fifo_s_axi_rdata;
logic     [1:0]                   w_aou_tx_fifo_s_axi_rresp;
logic                             w_aou_tx_fifo_s_axi_rlast;
logic                             w_aou_tx_fifo_s_axi_rvalid;
logic                             w_aou_tx_fifo_s_axi_rready;

// byte swap

logic   [11:0]                 w_aou_writereq_prof  ;
logic   [11:0]                 w_aou_readreq_prof   ;
logic   [11:0]                 w_aou_writedata_prof ;
logic   [11:0]                 w_aou_readdata_prof  ;
logic   [11:0]                 w_aou_writeresp_prof ;

logic [40*AW_G-1:0            ]  w_writereq_message_byteswap;
logic [40*W1024b_G-1:0        ]  w_writedata_message_byteswap;
logic [40*WF1024b_G-1:0       ]  w_writedata_wo_strb_message_byteswap;
logic [40*B_G-1:0             ]  w_writeresp_message_byteswap;
logic [40*AR_G-1:0            ]  w_readreq_message_byteswap;
logic [40*R256b_G-1:0         ]  w_readdata256b_message_byteswap;
logic [40*R512b_G-1:0         ]  w_readdata512b_message_byteswap;
logic [40*R1024b_G-1:0        ]  w_readdata1024b_message_byteswap;

logic [40*AW_G-1:0            ]  w_writereq_message;
logic [40*W1024b_G-1:0        ]  w_writedata_message;
logic [40*WF1024b_G-1:0       ]  w_writedata_wo_strb_message;
logic [40*B_G-1:0             ]  w_writeresp_message;
logic [40*AR_G-1:0            ]  w_readreq_message;
logic [40*R256b_G-1:0         ]  w_readdata256b_message;
logic [40*R512b_G-1:0         ]  w_readdata512b_message;
logic [40*R1024b_G-1:0        ]  w_readdata1024b_message;


// Credit Control
logic      [RP_CNT-1:0]           w_aou_tx_aw_credit_valid;
logic      [RP_CNT-1:0]           w_aou_tx_w_credit_valid;
logic      [RP_CNT-1:0]           w_aou_tx_b_credit_valid;
logic      [RP_CNT-1:0]           w_aou_tx_ar_credit_valid;
logic      [RP_CNT-1:0]           w_aou_tx_r_credit_valid;

// QoS Parameter
logic      [3:0][1:0]             w_aou_aw_port_qos;
logic      [RP_CNT-1:0][1:0]      w_aou_aw_axi_qos;
logic      [RP_CNT-1:0][1:0]      w_aou_aw_fifo_qos;
logic      [RP_CNT-1:0][1:0]      w_aou_aw_rp_qos;
logic      [3:0][1:0]             w_aou_ar_port_qos;
logic      [RP_CNT-1:0][1:0]      w_aou_ar_axi_qos;
logic      [RP_CNT-1:0][1:0]      w_aou_ar_fifo_qos;
logic      [RP_CNT-1:0][1:0]      w_aou_ar_rp_qos;

logic      [1:0]                  w_arb_mode;

logic w_port_qos_enable;

//00 : RoundRobin / 01 : Port QoS / 10 : Current QoS
assign w_arb_mode        = I_PRIOR_RP_AXI_ARB_MODE;
assign w_port_qos_enable = (w_arb_mode == 2'b01);

logic       [3:0][1:0]   w_aou_rp_port_qos;

assign w_aou_rp_port_qos[0] = (I_PRIOR_RP_AXI_RP0_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP0_PRIOR;
assign w_aou_rp_port_qos[1] = (I_PRIOR_RP_AXI_RP1_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP1_PRIOR;
assign w_aou_rp_port_qos[2] = (I_PRIOR_RP_AXI_RP2_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP2_PRIOR;
assign w_aou_rp_port_qos[3] = (I_PRIOR_RP_AXI_RP3_PRIOR == 2'b00) ? 2'b01 : I_PRIOR_RP_AXI_RP3_PRIOR;

assign w_aou_aw_port_qos = {w_aou_rp_port_qos[3], w_aou_rp_port_qos[2], w_aou_rp_port_qos[1], w_aou_rp_port_qos[0]};
assign w_aou_ar_port_qos = {w_aou_rp_port_qos[3], w_aou_rp_port_qos[2], w_aou_rp_port_qos[1], w_aou_rp_port_qos[0]};

always_comb begin
    for (int unsigned i = 0; i < RP_CNT ; i++) begin
        w_aou_aw_axi_qos[i] = (I_AOU_TX_S_AXI_AWQOS[i] >= I_PRIOR_RP_AXI_AXI_QOS_TO_HP) ? 2'b11 :
                              (I_AOU_TX_S_AXI_AWQOS[i] >= I_PRIOR_RP_AXI_AXI_QOS_TO_NP) ? 2'b10 : 2'b01;
        w_aou_ar_axi_qos[i] = (I_AOU_TX_S_AXI_ARQOS[i] >= I_PRIOR_RP_AXI_AXI_QOS_TO_HP) ? 2'b11 :
                              (I_AOU_TX_S_AXI_ARQOS[i] >= I_PRIOR_RP_AXI_AXI_QOS_TO_NP) ? 2'b10 : 2'b01;
    end
end

always_comb begin
    for (int unsigned i = 0; i < RP_CNT ; i++) begin
        w_aou_aw_fifo_qos[i] = w_port_qos_enable ? w_aou_aw_port_qos[i] : w_aou_aw_axi_qos[i];
        w_aou_ar_fifo_qos[i] = w_port_qos_enable ? w_aou_ar_port_qos[i] : w_aou_ar_axi_qos[i];
    end
end

//-------------------------------------------------------------------------
//  AW FIFO 
//-------------------------------------------------------------------------
genvar i;

generate
    for (i = 0 ; i < RP_CNT ; i++) begin : g_aw_rp_fifo
        AOU_TX_QOS_BUFFER
        #(
            .FIFO_WIDTH                     (AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 1 + 4 + 3 + 4),
            .FIFO_DEPTH                     (AXI_AW_FIFO_DEPTH)        
        )
        u_axi_slave_aw_rp0_fifo(
            .I_CLK                          (I_CLK),
            .I_RESETN                       (I_RESETN),

            .I_SVALID                       (I_AOU_TX_S_AXI_AWVALID[i]),
            .I_TRANS_QOS                    ( w_aou_aw_fifo_qos[i]      ),
            .I_SDATA                        ({I_AOU_TX_S_AXI_AWID[i], I_AOU_TX_S_AXI_AWADDR[i], I_AOU_TX_S_AXI_AWLEN[i], I_AOU_TX_S_AXI_AWSIZE[i],
                                            I_AOU_TX_S_AXI_AWLOCK[i], I_AOU_TX_S_AXI_AWCACHE[i], I_AOU_TX_S_AXI_AWPROT[i], I_AOU_TX_S_AXI_AWQOS[i]}),
            .O_SREADY                       (O_AOU_TX_S_AXI_AWREADY[i]),

            .I_MREADY                       (w_aou_tx_m_axi_awready[i] && w_aou_tx_aw_credit_valid[i]),
            .O_MDATA                        ({w_aou_tx_m_axi_awid[i], w_aou_tx_m_axi_awaddr[i], w_aou_tx_m_axi_awlen[i], w_aou_tx_m_axi_awsize[i],
                                            w_aou_tx_m_axi_awlock[i], w_aou_tx_m_axi_awcache[i], w_aou_tx_m_axi_awprot[i], w_aou_tx_m_axi_awqos[i]}),
            .O_TRANS_QOS                    ( w_aou_aw_rp_qos[i]     ),
            .O_MVALID                       (w_aou_tx_m_axi_awvalid[i]),

            .I_PRIOR_TIMER_TIMER_RESOLUTION (I_PRIOR_TIMER_TIMER_RESOLUTION),
            .I_PRIOR_TIMER_TIMER_THRESHOLD  (I_PRIOR_TIMER_TIMER_THRESHOLD)
        );
    end
endgenerate


logic [RP_CNT-1:0]  w_granted_aw_rp;

AOU_TX_QOS_ARBITER #(
    .RP_CNT                         ( RP_CNT )
) u_aou_aw_rp_arbiter (
    .I_CLK                          ( I_CLK  ),
    .I_RESETN                       ( I_RESETN  ),

    .I_ARB_MODE                     ( w_arb_mode        ),
    .I_QOS                          ( w_aou_aw_rp_qos   ),
    .I_REQ                          ( w_aou_tx_m_axi_awvalid ),
    .I_ARB_EN                       ( |(w_aou_tx_m_axi_awvalid & w_aou_tx_m_axi_awready & w_aou_tx_aw_credit_valid)),
    
    .O_GRANTED_AGENT                ( w_granted_aw_rp )
);

always_comb begin
    w_aou_tx_fifo_m_axi_aw_rp   = 2'b00;
    w_aou_tx_fifo_m_axi_awid    = 'b0;
    w_aou_tx_fifo_m_axi_awaddr  = 'b0;
    w_aou_tx_fifo_m_axi_awlen   = 'b0;
    w_aou_tx_fifo_m_axi_awsize  = 'b0;
    w_aou_tx_fifo_m_axi_awlock  = 'b0;
    w_aou_tx_fifo_m_axi_awcache = 'b0;
    w_aou_tx_fifo_m_axi_awprot  = 'b0;
    w_aou_tx_fifo_m_axi_awqos   = 'b0;
    w_aou_tx_fifo_m_axi_awvalid = 'b0;
    w_aou_tx_m_axi_awready  = 'b0;

    for (int unsigned i = 0; i < RP_CNT ; i ++) begin
        if (w_granted_aw_rp[i] == 1'b1) begin
            w_aou_tx_fifo_m_axi_aw_rp   = i;
            w_aou_tx_fifo_m_axi_awid    = w_aou_tx_m_axi_awid[i];
            w_aou_tx_fifo_m_axi_awaddr  = w_aou_tx_m_axi_awaddr[i];
            w_aou_tx_fifo_m_axi_awlen   = w_aou_tx_m_axi_awlen[i];
            w_aou_tx_fifo_m_axi_awsize  = w_aou_tx_m_axi_awsize[i];
            w_aou_tx_fifo_m_axi_awlock  = w_aou_tx_m_axi_awlock[i];
            w_aou_tx_fifo_m_axi_awcache = w_aou_tx_m_axi_awcache[i];
            w_aou_tx_fifo_m_axi_awprot  = w_aou_tx_m_axi_awprot[i];
            w_aou_tx_fifo_m_axi_awqos   = w_aou_tx_m_axi_awqos[i];
            w_aou_tx_fifo_m_axi_awvalid = w_aou_tx_m_axi_awvalid[i] && w_aou_tx_aw_credit_valid[i];
            w_aou_tx_m_axi_awready[i]  = w_aou_tx_fifo_m_axi_awready;
        end
    end
end

assign w_writereq_message_byteswap           = {MSG_WR_REQ, I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 1'b0, w_aou_tx_fifo_m_axi_awlock_tmp, 4'b0, w_aou_writereq_prof, w_aou_tx_fifo_m_axi_awid_tmp, w_aou_tx_fifo_m_axi_awsize_tmp,
                                            w_aou_tx_fifo_m_axi_awprot_tmp, w_aou_tx_fifo_m_axi_awlen_tmp, w_aou_tx_fifo_m_axi_awcache_tmp, w_aou_tx_fifo_m_axi_awqos_tmp, w_aou_tx_fifo_m_axi_awaddr_tmp};


assign w_writereq_message = {<<8{w_writereq_message_byteswap}};


AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (40*AW_G),
    .FIFO_DEPTH                     (AXI_AW_FIFO_DEPTH)        
)
u_axi_slave_aw_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (w_aou_tx_fifo_m_axi_awvalid_tmp),
    .I_SDATA                        (w_writereq_message),
    .O_SREADY                       (w_aou_tx_fifo_m_axi_awready_tmp),

    .I_MREADY                       (I_AOU_TX_M_AXI_AWREADY),
    .O_MDATA                        (O_AOU_TX_M_AXI_AW_MESSAGE),
    .O_MVALID                       (O_AOU_TX_M_AXI_AWVALID),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);

//-------------------------------------------------------------------------
//  W FIFO w/ RS
//--------------------------------------------------------------------
logic w_w_full_strb [RP_CNT];

genvar j;
generate
    for (j = 0; j < RP_CNT; j++) begin
        always_comb begin
            w_w_full_strb[j] = &(I_AOU_TX_S_AXI_WSTRB[j][0+:RP_AXI_STRB_WD[j]]);
        end
    end
endgenerate

logic [RP0_AXI_DATA_WD-1:0] w_aou_tx_rp0_wdata;
logic [RP1_AXI_DATA_WD-1:0] w_aou_tx_rp1_wdata;
logic [RP2_AXI_DATA_WD-1:0] w_aou_tx_rp2_wdata;
logic [RP3_AXI_DATA_WD-1:0] w_aou_tx_rp3_wdata;


logic [RP0_AXI_STRB_WD-1:0] w_aou_tx_rp_wstrb_tmp;
logic [RP1_AXI_STRB_WD-1:0] w_aou_tx_rp1_wstrb;
logic [RP2_AXI_STRB_WD-1:0] w_aou_tx_rp2_wstrb;
logic [RP3_AXI_STRB_WD-1:0] w_aou_tx_rp3_wstrb;

generate 
    for (i = 0; i < RP_CNT ; i ++) begin : g_w_rp_fifo
        localparam int DATA_WD = RP_AXI_DATA_WD[i];
        localparam int STRB_WD = RP_AXI_STRB_WD[i];
        logic [DATA_WD-1:0] w_tx_axi_data_tmp;
        logic [STRB_WD-1:0] w_tx_axi_strb_tmp;

        AOU_SYNC_FIFO_REG
        #(
            .FIFO_WIDTH                     (RP_AXI_DATA_WD[i] + RP_AXI_STRB_WD[i] + 1 + 1),
            .FIFO_DEPTH                     (AXI_W_FIFO_DEPTH)        
        )
        u_axi_slave_w_rp_fifo(
            .I_CLK                          (I_CLK),
            .I_RESETN                       (I_RESETN),

            .I_SVALID                       (I_AOU_TX_S_AXI_WVALID[i]),
            .I_SDATA                        ({I_AOU_TX_S_AXI_WDATA[i][0 +: RP_AXI_DATA_WD[i]], I_AOU_TX_S_AXI_WSTRB[i][0 +: RP_AXI_STRB_WD[i]], I_AOU_TX_S_AXI_WLAST[i], w_w_full_strb[i]}),
            .O_SREADY                       (O_AOU_TX_S_AXI_WREADY[i]),

            .I_MREADY                       (w_aou_tx_m_axi_wready[i] && w_aou_tx_w_credit_valid[i]),
            .O_MDATA                        ({w_tx_axi_data_tmp, w_tx_axi_strb_tmp, w_aou_tx_m_axi_wlast[i], w_aou_tx_m_axi_wstrb_full[i]}),
            .O_MVALID                       (w_aou_tx_m_axi_wvalid[i]),

            .O_EMPTY_CNT                    (),
            .O_FULL_CNT                     ()
        );

        always_comb begin
            w_aou_tx_m_axi_wdata[i] = '0;
            w_aou_tx_m_axi_wdata[i][0 +: RP_AXI_DATA_WD[i]] = w_tx_axi_data_tmp;
            w_aou_tx_m_axi_wstrb[i] = '0;
            w_aou_tx_m_axi_wstrb[i][0 +: RP_AXI_STRB_WD[i]] = w_tx_axi_strb_tmp;
        end

    end
endgenerate

AOU_AW_W_ALIGNER #(
    .AXI_SLV_NUM    ( RP_CNT ),
    .AXI_DATA_WD    ( MAX_AXI_DATA_WD ),
    .AXI_ADDR_WD    ( AXI_ADDR_WD ),
    .AXI_ID_WD      ( AXI_ID_WD ),
    .AXI_QOS_WD     ( 4 ),
    .AXI_LEN_WD     ( AXI_LEN_WD )
) u_aou_aw_w_aligner 
(
    .I_CLK                          ( I_CLK  ),
    .I_RESETN                       ( I_RESETN  ),

    .I_S_AW_RP_SEL  ( w_aou_tx_fifo_m_axi_aw_rp         ),
    .I_S_AWID       ( w_aou_tx_fifo_m_axi_awid          ),
    .I_S_AWADDR     ( w_aou_tx_fifo_m_axi_awaddr        ),
    .I_S_AWLEN      ( w_aou_tx_fifo_m_axi_awlen         ),
    .I_S_AWSIZE     ( w_aou_tx_fifo_m_axi_awsize        ),
    .I_S_AWLOCK     ( w_aou_tx_fifo_m_axi_awlock        ),
    .I_S_AWCACHE    ( w_aou_tx_fifo_m_axi_awcache       ),
    .I_S_AWPROT     ( w_aou_tx_fifo_m_axi_awprot        ),
    .I_S_AWQOS      ( w_aou_tx_fifo_m_axi_awqos         ),
    .I_S_AWVALID    ( w_aou_tx_fifo_m_axi_awvalid       ),
    .O_S_AWREADY    ( w_aou_tx_fifo_m_axi_awready       ),

    .I_S_WDATA      ( w_aou_tx_m_axi_wdata              ),
    .I_S_WSTRB      ( w_aou_tx_m_axi_wstrb              ),
    .I_S_WSTRB_FULL ( w_aou_tx_m_axi_wstrb_full         ),
    .I_S_WLAST      ( w_aou_tx_m_axi_wlast              ),
    .I_S_WVALID     ( w_aou_tx_m_axi_wvalid & w_aou_tx_w_credit_valid),
    .O_S_WREADY     ( w_aou_tx_m_axi_wready             ),

    .O_M_AW_RP_SEL  ( w_aou_tx_fifo_m_axi_aw_rp_tmp     ),
    .O_M_AWID       ( w_aou_tx_fifo_m_axi_awid_tmp      ),
    .O_M_AWADDR     ( w_aou_tx_fifo_m_axi_awaddr_tmp    ),
    .O_M_AWLEN      ( w_aou_tx_fifo_m_axi_awlen_tmp     ),
    .O_M_AWSIZE     ( w_aou_tx_fifo_m_axi_awsize_tmp    ),
    .O_M_AWLOCK     ( w_aou_tx_fifo_m_axi_awlock_tmp    ),
    .O_M_AWCACHE    ( w_aou_tx_fifo_m_axi_awcache_tmp   ),
    .O_M_AWPROT     ( w_aou_tx_fifo_m_axi_awprot_tmp    ),
    .O_M_AWQOS      ( w_aou_tx_fifo_m_axi_awqos_tmp     ),
    .O_M_AWVALID    ( w_aou_tx_fifo_m_axi_awvalid_tmp   ),
    .I_M_AWREADY    ( w_aou_tx_fifo_m_axi_awready_tmp   ),      

    .O_M_WDATA      ( w_aou_tx_fifo_m_axi_wdata         ),
    .O_M_WSTRB      ( w_aou_tx_fifo_m_axi_wstrb         ),
    .O_M_WSTRB_FULL ( w_aou_tx_fifo_m_axi_wstrb_full    ),
    .O_M_WLAST      ( w_aou_tx_fifo_m_axi_wlast         ),
    .O_M_WVALID     ( w_aou_tx_fifo_m_axi_wvalid        ),
    .I_M_WREADY     ( w_aou_tx_fifo_m_axi_wready        )
);


logic [1:0] w_writedata_message_dlen;

logic [1024-1:0]    w_fifo_wdata_ext;
logic [128-1:0]     w_fifo_wstrb_ext;


always_comb begin
    w_fifo_wdata_ext = '0;
    w_fifo_wstrb_ext = '0;

    w_fifo_wdata_ext[$bits(w_aou_tx_fifo_m_axi_wdata)-1:0] = w_aou_tx_fifo_m_axi_wdata;
    w_fifo_wstrb_ext[$bits(w_aou_tx_fifo_m_axi_wstrb)-1:0] = w_aou_tx_fifo_m_axi_wstrb;

    case (RP_AXI_DATA_WD[w_aou_tx_fifo_m_axi_aw_rp_tmp])
        256 : begin
            w_writedata_wo_strb_message_byteswap = {MSG_WRF_DATA, I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 2'b00, 4'b0, w_aou_writedata_prof, w_fifo_wdata_ext[255:0], 768'b0, 32'b0};
            w_writedata_message_byteswap         = {MSG_WR_DATA,  I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 2'b00, 4'b0, w_aou_writedata_prof, w_fifo_wdata_ext[255:0], w_fifo_wstrb_ext[31:0], 768'b0, 96'b0, 24'b0};
        end
        512 : begin 
            w_writedata_wo_strb_message_byteswap = {MSG_WRF_DATA, I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 2'b01, 4'b0, w_aou_writedata_prof, w_fifo_wdata_ext[511:0], 512'b0, 32'b0};
            w_writedata_message_byteswap         = {MSG_WR_DATA,  I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 2'b01, 4'b0, w_aou_writedata_prof, w_fifo_wdata_ext[511:0], w_fifo_wstrb_ext[63:0], 512'b0, 64'b0, 24'b0};
        end
        1024 : begin 
            w_writedata_wo_strb_message_byteswap = {MSG_WRF_DATA, I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 2'b10, 4'b0, w_aou_writedata_prof, w_fifo_wdata_ext, 32'b0};
            w_writedata_message_byteswap         = {MSG_WR_DATA,  I_RP_DEST_RP[w_aou_tx_fifo_m_axi_aw_rp_tmp], 2'b10, 4'b0, w_aou_writedata_prof, w_fifo_wdata_ext, w_fifo_wstrb_ext, 24'b0};
        end
        default : begin
            w_writedata_wo_strb_message_byteswap = '0;
            w_writedata_message_byteswap         = '0;
        end
    endcase
end

assign w_writedata_message = {<<8{w_writedata_message_byteswap}};
assign w_writedata_wo_strb_message = {<<8{w_writedata_wo_strb_message_byteswap}};

logic [40*W1024b_G-1:0] w_writedata_wf_message_en;

assign w_writedata_wf_message_en = (I_AOU_WRITEFULL_MSGTYPE_EN && w_aou_tx_fifo_m_axi_wstrb_full) ? {{(40*(W1024b_G-WF1024b_G)){1'b0}} , w_writedata_wo_strb_message} : w_writedata_message; 


AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (2 + 40*W1024b_G + 1),
    .FIFO_DEPTH                     (AXI_W_FIFO_DEPTH)        
)
u_axi_slave_w_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (w_aou_tx_fifo_m_axi_wvalid),
    .I_SDATA                        ({w_aou_tx_fifo_m_axi_aw_rp_tmp, w_writedata_wf_message_en, w_aou_tx_fifo_m_axi_wstrb_full}),
    .O_SREADY                       (w_aou_tx_fifo_m_axi_wready),

    .I_MREADY                       (I_AOU_TX_M_AXI_WREADY),
    .O_MDATA                        ({O_AOU_TX_M_AXI_W_RP, O_AOU_TX_M_AXI_W_MESSAGE, O_AOU_TX_M_AXI_WSTRB_FULL}),
    .O_MVALID                       (O_AOU_TX_M_AXI_WVALID),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);


//-------------------------------------------------------------------------
//  AR channel
//--------------------------------------------------------------------
generate
    for (i =0; i < RP_CNT ; i++) begin :g_ar_rp_fifo
        AOU_TX_QOS_BUFFER
        #(
            .FIFO_WIDTH                     (AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 1 + 4 + 3 + 4),
            .FIFO_DEPTH                     (AXI_AR_FIFO_DEPTH)        
        )
        u_axi_slave_ar_rp_fifo(
            .I_CLK                          ( I_CLK                     ),
            .I_RESETN                       ( I_RESETN                  ),

            .I_SVALID                       ( I_AOU_TX_S_AXI_ARVALID[i] ),
            .I_TRANS_QOS                    ( w_aou_ar_fifo_qos[i]      ),
            .I_SDATA                        ( {I_AOU_TX_S_AXI_ARID[i], I_AOU_TX_S_AXI_ARADDR[i], I_AOU_TX_S_AXI_ARLEN[i], I_AOU_TX_S_AXI_ARSIZE[i], 
                                              I_AOU_TX_S_AXI_ARLOCK[i], I_AOU_TX_S_AXI_ARCACHE[i], I_AOU_TX_S_AXI_ARPROT[i], I_AOU_TX_S_AXI_ARQOS[i]}   ),
            .O_SREADY                       ( O_AOU_TX_S_AXI_ARREADY[i] ),

            .I_MREADY                       ( w_aou_tx_m_axi_arready[i] && w_aou_tx_ar_credit_valid[i]  ),
            .O_MDATA                        ( {w_aou_tx_m_axi_arid[i], w_aou_tx_m_axi_araddr[i], w_aou_tx_m_axi_arlen[i], w_aou_tx_m_axi_arsize[i], 
                                              w_aou_tx_m_axi_arlock[i], w_aou_tx_m_axi_arcache[i], w_aou_tx_m_axi_arprot[i], w_aou_tx_m_axi_arqos[i]}   ),
            .O_TRANS_QOS                    ( w_aou_ar_rp_qos[i]        ),
            .O_MVALID                       ( w_aou_tx_m_axi_arvalid[i] ),
            
            .I_PRIOR_TIMER_TIMER_RESOLUTION ( I_PRIOR_TIMER_TIMER_RESOLUTION),
            .I_PRIOR_TIMER_TIMER_THRESHOLD  ( I_PRIOR_TIMER_TIMER_THRESHOLD )
        );
    end
endgenerate

logic [RP_CNT-1:0]  w_granted_ar_rp;

AOU_TX_QOS_ARBITER #(
    .RP_CNT                         ( RP_CNT )
) u_aou_ar_rp_arbiter (
    .I_CLK                          ( I_CLK  ),
    .I_RESETN                       ( I_RESETN  ),

    .I_ARB_MODE                     ( w_arb_mode                ),
    .I_QOS                          ( w_aou_ar_rp_qos           ),
    .I_REQ                          ( w_aou_tx_m_axi_arvalid    ),
    .I_ARB_EN                       ( |(w_aou_tx_m_axi_arvalid & w_aou_tx_m_axi_arready & w_aou_tx_ar_credit_valid) ),
    
    .O_GRANTED_AGENT                ( w_granted_ar_rp )
);

always_comb begin
    w_aou_tx_fifo_m_axi_ar_rp   = 2'b00;
    w_aou_tx_fifo_m_axi_arid    = 'b0;
    w_aou_tx_fifo_m_axi_araddr  = 'b0;
    w_aou_tx_fifo_m_axi_arlen   = 'b0;
    w_aou_tx_fifo_m_axi_arsize  = 'b0;
    w_aou_tx_fifo_m_axi_arlock  = 'b0;
    w_aou_tx_fifo_m_axi_arcache = 'b0;
    w_aou_tx_fifo_m_axi_arprot  = 'b0;
    w_aou_tx_fifo_m_axi_arqos   = 'b0;
    w_aou_tx_fifo_m_axi_arvalid = 'b0;
    w_aou_tx_m_axi_arready  = 'b0;

    for (int unsigned i = 0 ; i < RP_CNT ; i++) begin
        if (w_granted_ar_rp[i] == 1'b1) begin
            w_aou_tx_fifo_m_axi_ar_rp   = I_RP_DEST_RP[i];
            w_aou_tx_fifo_m_axi_arid    = w_aou_tx_m_axi_arid[i];
            w_aou_tx_fifo_m_axi_araddr  = w_aou_tx_m_axi_araddr[i];
            w_aou_tx_fifo_m_axi_arlen   = w_aou_tx_m_axi_arlen[i];
            w_aou_tx_fifo_m_axi_arsize  = w_aou_tx_m_axi_arsize[i];
            w_aou_tx_fifo_m_axi_arlock  = w_aou_tx_m_axi_arlock[i];
            w_aou_tx_fifo_m_axi_arcache = w_aou_tx_m_axi_arcache[i];
            w_aou_tx_fifo_m_axi_arprot  = w_aou_tx_m_axi_arprot[i];
            w_aou_tx_fifo_m_axi_arqos   = w_aou_tx_m_axi_arqos[i];
            w_aou_tx_fifo_m_axi_arvalid = w_aou_tx_m_axi_arvalid[i] && w_aou_tx_ar_credit_valid[i];
            w_aou_tx_m_axi_arready[i]  = w_aou_tx_fifo_m_axi_arready;
        end
    end
end


assign w_readreq_message_byteswap  = {MSG_RD_REQ, w_aou_tx_fifo_m_axi_ar_rp, 1'b0, w_aou_tx_fifo_m_axi_arlock, 4'b0, w_aou_readreq_prof, w_aou_tx_fifo_m_axi_arid, w_aou_tx_fifo_m_axi_arsize, w_aou_tx_fifo_m_axi_arprot,
                            w_aou_tx_fifo_m_axi_arlen, w_aou_tx_fifo_m_axi_arcache, w_aou_tx_fifo_m_axi_arqos, w_aou_tx_fifo_m_axi_araddr};


assign w_readreq_message = {<<8{w_readreq_message_byteswap}};


AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (40*AR_G),
    .FIFO_DEPTH                     (AXI_AW_FIFO_DEPTH)        
)
u_axi_slave_ar_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (w_aou_tx_fifo_m_axi_arvalid),
    .I_SDATA                        (w_readreq_message),
    .O_SREADY                       (w_aou_tx_fifo_m_axi_arready),

    .I_MREADY                       (I_AOU_TX_M_AXI_ARREADY),
    .O_MDATA                        (O_AOU_TX_M_AXI_AR_MESSAGE),
    .O_MVALID                       (O_AOU_TX_M_AXI_ARVALID),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);
//-------------------------------------------------------------------------
//  B channel
//--------------------------------------------------------------------
logic w_granted_b_1024 [RP_CNT];  
logic w_granted_b_512 [RP_CNT];    
logic w_granted_b_256 [RP_CNT];
logic w_granted_fifo_valid [RP_CNT];
logic w_granted_fifo_ready [RP_CNT];

generate 
    for (i = 0; i < RP_CNT; i ++) begin : g_b_rp_fifo
        AOU_3X1_ARBITER u_aou_tx_rp_b_arbiter (
            .I_CLK                              ( I_CLK  ),
            .I_RESETN                           ( I_RESETN  ),

            .I_REQ                              ( {I_AOU_TX_S_AXI_BVALID_1024[i], I_AOU_TX_S_AXI_BVALID_512[i], I_AOU_TX_S_AXI_BVALID_256[i]}  ),
            .I_ARB_EN                           ( (I_AOU_TX_S_AXI_BVALID_1024[i] & O_AOU_TX_S_AXI_BREADY_1024[i]) || (I_AOU_TX_S_AXI_BVALID_512[i] & O_AOU_TX_S_AXI_BREADY_512[i]) || (I_AOU_TX_S_AXI_BVALID_256[i] & O_AOU_TX_S_AXI_BREADY_256[i]) ),
            
            .O_GRANTED_AGENT                    ( {w_granted_b_1024[i], w_granted_b_512[i], w_granted_b_256[i]} )
        );

        always_comb begin
            O_AOU_TX_S_AXI_BREADY_1024[i] = 'b0;
            O_AOU_TX_S_AXI_BREADY_512[i]  = 'b0;
            O_AOU_TX_S_AXI_BREADY_256[i]  = 'b0;
            case ({w_granted_b_1024[i], w_granted_b_512[i], w_granted_b_256[i]})
                3'b001 : begin
                    w_granted_fifo_bvalid[i]  = I_AOU_TX_S_AXI_BVALID_256[i];
                    w_granted_fifo_bid[i]    = I_AOU_TX_S_AXI_BID_256[i];
                    w_granted_fifo_bresp[i]  = I_AOU_TX_S_AXI_BRESP_256[i];
                    O_AOU_TX_S_AXI_BREADY_256[i] = w_granted_fifo_bready[i];
                end
                3'b010 : begin 
                    w_granted_fifo_bvalid[i]  = I_AOU_TX_S_AXI_BVALID_512[i];
                    w_granted_fifo_bid[i]    = I_AOU_TX_S_AXI_BID_512[i];
                    w_granted_fifo_bresp[i]  = I_AOU_TX_S_AXI_BRESP_512[i];
                    O_AOU_TX_S_AXI_BREADY_512[i] = w_granted_fifo_bready[i];
                end
                3'b100 : begin 
                    w_granted_fifo_bvalid[i]  = I_AOU_TX_S_AXI_BVALID_1024[i];
                    w_granted_fifo_bid[i]    = I_AOU_TX_S_AXI_BID_1024[i];
                    w_granted_fifo_bresp[i]  = I_AOU_TX_S_AXI_BRESP_1024[i];
                    O_AOU_TX_S_AXI_BREADY_1024[i] = w_granted_fifo_bready[i];
                end
                default : begin 
                    w_granted_fifo_bvalid[i]  = 1'b0;
                    w_granted_fifo_bid[i]    = {(AXI_ID_WD){1'b0}};
                    w_granted_fifo_bresp[i]  = 2'b0;
                end
            endcase
        end

        AOU_SYNC_FIFO_REG
        #(
            .FIFO_WIDTH                     (AXI_ID_WD + 2),
            .FIFO_DEPTH                     (AXI_B_FIFO_DEPTH)        
        )
        u_axi_master_rp_b_fifo(
            .I_CLK                          (I_CLK),
            .I_RESETN                       (I_RESETN),

            .I_SVALID                       (w_granted_fifo_bvalid[i]),
            .I_SDATA                        ({w_granted_fifo_bid[i], w_granted_fifo_bresp[i]}),
            .O_SREADY                       (w_granted_fifo_bready[i]),

            .I_MREADY                       (w_aou_tx_s_axi_bready[i] && w_aou_tx_b_credit_valid[i]),
            .O_MDATA                        ({w_aou_tx_s_axi_bid[i], w_aou_tx_s_axi_bresp[i]}),  
            .O_MVALID                       (w_aou_tx_s_axi_bvalid[i]),

            .O_EMPTY_CNT                    (),
            .O_FULL_CNT                     ()
        );
    end

endgenerate

logic [RP_CNT-1:0]  w_granted_b_rp;

AOU_TX_ARBITER #(
    .RP_CNT                         ( RP_CNT )
) u_aou_b_rp_arbiter (
    .I_CLK                          ( I_CLK  ),
    .I_RESETN                       ( I_RESETN  ),

    .I_REQ                          ( w_aou_tx_s_axi_bvalid ),
    .I_ARB_EN                       ( |(w_aou_tx_s_axi_bvalid & w_aou_tx_s_axi_bready & w_aou_tx_b_credit_valid) ),
    
    .O_GRANTED_AGENT                ( w_granted_b_rp )
);


always_comb begin
    w_aou_tx_fifo_s_axi_b_rp        = 2'b00;
    w_aou_tx_fifo_s_axi_bid         = 'b0;
    w_aou_tx_fifo_s_axi_bresp       = 'b0;
    w_aou_tx_fifo_s_axi_bvalid      = 'b0;
    w_aou_tx_s_axi_bready           = 'b0;

    for (int unsigned i = 0; i < RP_CNT ; i ++) begin
        if (w_granted_b_rp[i] == 1'b1) begin
            w_aou_tx_fifo_s_axi_b_rp        = I_RP_DEST_RP[i];
            w_aou_tx_fifo_s_axi_bid         = w_aou_tx_s_axi_bid[i];
            w_aou_tx_fifo_s_axi_bresp       = w_aou_tx_s_axi_bresp[i];
            w_aou_tx_fifo_s_axi_bvalid      = w_aou_tx_s_axi_bvalid[i] && w_aou_tx_b_credit_valid[i];
            w_aou_tx_s_axi_bready[i]        = w_aou_tx_fifo_s_axi_bready;
        end
    end
end


logic [AXI_ID_WD-1:0]   w_aou_tx_m_axi_bid;
logic [1:0]             w_aou_tx_m_axi_bresp;
logic [1:0]             w_aou_tx_m_axi_b_rp;


AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (2+ AXI_ID_WD + 2),
    .FIFO_DEPTH                     (AXI_B_FIFO_DEPTH)        
)
u_axi_master_b_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (w_aou_tx_fifo_s_axi_bvalid),
    .I_SDATA                        ({w_aou_tx_fifo_s_axi_b_rp, w_aou_tx_fifo_s_axi_bid, w_aou_tx_fifo_s_axi_bresp}),
    .O_SREADY                       (w_aou_tx_fifo_s_axi_bready),

    .I_MREADY                       (I_AOU_TX_M_AXI_BREADY),
    .O_MDATA                        ({w_aou_tx_m_axi_b_rp, w_aou_tx_m_axi_bid, w_aou_tx_m_axi_bresp}),
    .O_MVALID                       (O_AOU_TX_M_AXI_BVALID),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);

assign w_writeresp_message_byteswap      = {MSG_WR_RESP, w_aou_tx_m_axi_b_rp, 2'b0, 4'b0, w_aou_writeresp_prof, w_aou_tx_m_axi_bid, w_aou_tx_m_axi_bresp, 4'b0};

assign w_writeresp_message = {<<8{w_writeresp_message_byteswap}};

assign O_AOU_TX_M_AXI_B_MESSAGE = w_writeresp_message;

//-------------------------------------------------------------------------
//  R channel
//--------------------------------------------------------------------
generate
    for (i = 0; i < RP_CNT ; i ++) begin : g_r_rp_fifo
        AOU_SYNC_FIFO_REG
        #(
            .FIFO_WIDTH                     (AXI_ID_WD +2 +  1024 + 2 + 1),
            .FIFO_DEPTH                     (AXI_R_FIFO_DEPTH)        
        )
        u_axi_slave_r_rp0_fifo(
            .I_CLK                          (I_CLK),
            .I_RESETN                       (I_RESETN),

            .I_SVALID                       (I_AOU_TX_S_AXI_RVALID[i]),
            .I_SDATA                        ({I_AOU_TX_S_AXI_RID[i], I_AOU_TX_S_AXI_RDLEN[i], I_AOU_TX_S_AXI_RDATA[i], I_AOU_TX_S_AXI_RRESP[i], I_AOU_TX_S_AXI_RLAST[i]}),
            .O_SREADY                       (O_AOU_TX_S_AXI_RREADY[i]),

            .I_MREADY                       (w_aou_tx_s_axi_rready[i] && w_aou_tx_r_credit_valid[i]),
            .O_MDATA                        ({w_aou_tx_s_axi_rid[i], w_aou_tx_s_axi_rdlen[i], w_aou_tx_s_axi_rdata[i], w_aou_tx_s_axi_rresp[i], w_aou_tx_s_axi_rlast[i]}),
            .O_MVALID                       (w_aou_tx_s_axi_rvalid[i]),

            .O_EMPTY_CNT                    (),
            .O_FULL_CNT                     ()
        );
    end
endgenerate


logic [RP_CNT-1:0]  w_granted_r_rp;

AOU_TX_ARBITER 
#(
    .RP_CNT (RP_CNT)
) u_aou_r_rp_arbiter (
    .I_CLK                          ( I_CLK  ),
    .I_RESETN                       ( I_RESETN  ),

    .I_REQ                          ( w_aou_tx_s_axi_rvalid ),
    .I_ARB_EN                       (|(w_aou_tx_s_axi_rvalid & w_aou_tx_s_axi_rready & w_aou_tx_r_credit_valid)),
    
    .O_GRANTED_AGENT                ( w_granted_r_rp )
);

always_comb begin
    w_aou_tx_fifo_m_axi_r_rp    = 2'b00;
    w_aou_tx_fifo_s_axi_rid     = 'd0; 
    w_aou_tx_fifo_s_axi_rdlen   = 'd0; 
    w_aou_tx_fifo_s_axi_rdata   = 'd0; 
    w_aou_tx_fifo_s_axi_rresp   = 'd0; 
    w_aou_tx_fifo_s_axi_rlast   = 'd0; 
    w_aou_tx_fifo_s_axi_rvalid  = 'd0; 
    w_aou_tx_s_axi_rready   = 'b0;

    for (int unsigned i = 0; i < RP_CNT ; i ++) begin
        if (w_granted_r_rp[i] == 1'b1) begin
            w_aou_tx_fifo_m_axi_r_rp    = I_RP_DEST_RP[i];
            w_aou_tx_fifo_s_axi_rid     = w_aou_tx_s_axi_rid[i];
            w_aou_tx_fifo_s_axi_rdlen   = w_aou_tx_s_axi_rdlen[i];
            w_aou_tx_fifo_s_axi_rdata   = w_aou_tx_s_axi_rdata[i];
            w_aou_tx_fifo_s_axi_rresp   = w_aou_tx_s_axi_rresp[i];
            w_aou_tx_fifo_s_axi_rlast   = w_aou_tx_s_axi_rlast[i];
            w_aou_tx_fifo_s_axi_rvalid  = w_aou_tx_s_axi_rvalid[i] && w_aou_tx_r_credit_valid[i];
            w_aou_tx_s_axi_rready[i]   = w_aou_tx_fifo_s_axi_rready;
        end
    end
end

// Problem RTL ==========================================
//assign w_readdata256b_message_byteswap   = {MSG_RD_DATA, w_aou_tx_fifo_m_axi_r_rp, 2'b00, 4'b0, w_aou_readdata_prof, w_aou_tx_fifo_s_axi_rid, w_aou_tx_fifo_s_axi_rresp, w_aou_tx_fifo_s_axi_rlast, 3'b0, w_aou_tx_fifo_s_axi_rdata[255:0], 24'b0};
//assign w_readdata512b_message_byteswap   = {MSG_RD_DATA, w_aou_tx_fifo_m_axi_r_rp, 2'b01, 4'b0, w_aou_readdata_prof, w_aou_tx_fifo_s_axi_rid, w_aou_tx_fifo_s_axi_rresp, w_aou_tx_fifo_s_axi_rlast, 3'b0, w_aou_tx_fifo_s_axi_rdata[511:0], 8'b0};
//assign w_readdata1024b_message_byteswap  = {MSG_RD_DATA, w_aou_tx_fifo_m_axi_r_rp, 2'b10, 4'b0, w_aou_readdata_prof, w_aou_tx_fifo_s_axi_rid, w_aou_tx_fifo_s_axi_rresp, w_aou_tx_fifo_s_axi_rlast, 3'b0, w_aou_tx_fifo_s_axi_rdata, 16'b0};

//assign w_readdata256b_message = {<<8{w_readdata256b_message_byteswap}};
//assign w_readdata512b_message = {<<8{w_readdata512b_message_byteswap}};
//assign w_readdata1024b_message = {<<8{w_readdata1024b_message_byteswap}};

//logic [40*R1024b_G-1:0        ]  w_readdata_message_sel;

//always_comb begin
//    case (w_aou_tx_fifo_s_axi_rdlen)
//        2'b00: w_readdata_message_sel = {{(R1024b_G-R256b_G){40'b0}}, w_readdata256b_message};
//        2'b01: w_readdata_message_sel = {{(R1024b_G-R512b_G){40'b0}}, w_readdata512b_message};
//        2'b10: w_readdata_message_sel = {w_readdata1024b_message};
//        default: w_readdata_message_sel = '0;
//    endcase
//end

// Proposal RTL ==========================================
logic [40*R1024b_G-1:0]     w_readdata_message_raw;

logic [(4+2+2+4+12+AXI_ID_WD+2+1+3)-1:0] w_readdata_message_header;

assign w_readdata_message_header = {MSG_RD_DATA, w_aou_tx_fifo_m_axi_r_rp, w_aou_tx_fifo_s_axi_rdlen, 4'b0, w_aou_readdata_prof, w_aou_tx_fifo_s_axi_rid, w_aou_tx_fifo_s_axi_rresp, w_aou_tx_fifo_s_axi_rlast, 3'b0};

always_comb begin
    w_readdata_message_raw = '0;
    case (w_aou_tx_fifo_s_axi_rdlen) 
        2'b00: w_readdata_message_raw[40*R1024b_G-1 -: 40*R256b_G]  = {w_readdata_message_header, w_aou_tx_fifo_s_axi_rdata[255:0], 24'b0};
        2'b01: w_readdata_message_raw[40*R1024b_G-1 -: 40*R512b_G]  = {w_readdata_message_header, w_aou_tx_fifo_s_axi_rdata[511:0], 8'b0};
        2'b10: w_readdata_message_raw[40*R1024b_G-1:0]              = {w_readdata_message_header, w_aou_tx_fifo_s_axi_rdata, 16'b0};
        default: w_readdata_message_raw = '0;
    endcase
end

logic [40*R1024b_G-1:0]     w_readdata_message_sel;
assign w_readdata_message_sel = {<<8{w_readdata_message_raw}};

AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (2 + 40*R1024b_G),
    .FIFO_DEPTH                     (AXI_R_FIFO_DEPTH)        
)
u_axi_master_r_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (w_aou_tx_fifo_s_axi_rvalid),
    .I_SDATA                        ({w_aou_tx_fifo_s_axi_rdlen, w_readdata_message_sel}),
    .O_SREADY                       (w_aou_tx_fifo_s_axi_rready),

    .I_MREADY                       (I_AOU_TX_M_AXI_RREADY),
    .O_MDATA                        ({O_AOU_TX_M_AXI_RDLEN, O_AOU_TX_M_AXI_R_MESSAGE}),
    .O_MVALID                       (O_AOU_TX_M_AXI_RVALID),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);


//-------------------------------------------------------------------------
//  Credit control (TX packing)
//-------------------------------------------------------------------------
logic [5:0]  w_rdata_granule_size   [RP_CNT];
logic [5:0]  w_wdata_granule_size   [RP_CNT];

always_comb begin
    for (int unsigned i = 0 ; i < RP_CNT ; i ++) begin
        case (w_aou_tx_s_axi_rdlen[i])
            2'b00 : w_rdata_granule_size[i] = R256b_G;
            2'b01: w_rdata_granule_size[i] = R512b_G;
            2'b10: w_rdata_granule_size[i] = R1024b_G;
            default: w_rdata_granule_size[i] = 0;
        endcase
    end
end

always_comb begin
    for (int unsigned i = 0 ; i < RP_CNT ; i ++) begin
        case (w_aou_tx_m_axi_wstrb_full[i])
            1'b0 : w_wdata_granule_size[i] = RP_W_G_SIZE[i];
            1'b1 : w_wdata_granule_size[i] = RP_WF_G_SIZE[i];
            default: w_wdata_granule_size[i] = 0;
        endcase
    end
end

always_comb begin
    for (int unsigned i = 0 ; i < RP_CNT ; i ++) begin
        w_aou_tx_aw_credit_valid[i] = (I_AOU_TX_WREQCRED[i]  >= AW_G);
        w_aou_tx_w_credit_valid[i]  = (I_AOU_TX_WDATACRED[i]  >= {6'b0, w_wdata_granule_size[i]});
        w_aou_tx_b_credit_valid[i]  = (I_AOU_TX_WRESPCRED[i] >= B_G);
        w_aou_tx_ar_credit_valid[i] = (I_AOU_TX_RREQCRED[i] >= AR_G);
        w_aou_tx_r_credit_valid[i]  = (I_AOU_TX_RDATACRED[i] >= {6'b0, w_rdata_granule_size[i]});
    end
end

always_comb begin
    for (int unsigned i = 0; i < RP_CNT ; i ++ ) begin
        O_AOU_TX_WREQVALID     [i] = w_aou_tx_m_axi_awvalid[i] && w_aou_tx_m_axi_awready[i] && w_aou_tx_aw_credit_valid [i];
        O_AOU_TX_RREQVALID     [i] = w_aou_tx_m_axi_arvalid[i] && w_aou_tx_m_axi_arready[i] && w_aou_tx_ar_credit_valid [i];
        O_AOU_TX_WDATAVALID    [i] = w_aou_tx_m_axi_wvalid [i] && w_aou_tx_m_axi_wready [i] && w_aou_tx_w_credit_valid  [i];
        O_AOU_TX_WFDATA        [i] = I_AOU_WRITEFULL_MSGTYPE_EN && w_aou_tx_m_axi_wstrb_full[i];
        O_AOU_TX_RDATAVALID    [i] = w_aou_tx_s_axi_rvalid [i] && w_aou_tx_s_axi_rready [i] && w_aou_tx_r_credit_valid  [i];
        O_AOU_TX_RDATA_DLENGTH [i] = w_aou_tx_s_axi_rdlen[i];
        O_AOU_TX_WRESPVALID    [i] = w_aou_tx_s_axi_bvalid [i] && w_aou_tx_s_axi_bready [i] && w_aou_tx_b_credit_valid  [i];

    end
end


assign  w_aou_writereq_prof  = 12'd0;
assign  w_aou_readreq_prof   = 12'd0;
assign  w_aou_writedata_prof = 12'd0;
assign  w_aou_readdata_prof  = 12'd0;
assign  w_aou_writeresp_prof = 12'd0;
endmodule
