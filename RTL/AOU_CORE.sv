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
//  Module     : AOU_CORE
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_CORE
import packet_def_pkg::*;
#(
    parameter   RP0_RX_AW_FIFO_DEPTH        = 40,
    parameter   RP0_RX_AR_FIFO_DEPTH        = 40,
    parameter   RP0_RX_W_FIFO_DEPTH         = 80,
    parameter   RP0_RX_R_FIFO_DEPTH         = 80,
    parameter   RP0_RX_B_FIFO_DEPTH         = 40,

    parameter   RP1_RX_AW_FIFO_DEPTH        = 256,
    parameter   RP1_RX_AR_FIFO_DEPTH        = 256,
    parameter   RP1_RX_W_FIFO_DEPTH         = 256,
    parameter   RP1_RX_R_FIFO_DEPTH         = 256,
    parameter   RP1_RX_B_FIFO_DEPTH         = 256,

    parameter   RP2_RX_AW_FIFO_DEPTH        = 256,
    parameter   RP2_RX_AR_FIFO_DEPTH        = 256,
    parameter   RP2_RX_W_FIFO_DEPTH         = 256,
    parameter   RP2_RX_R_FIFO_DEPTH         = 256,
    parameter   RP2_RX_B_FIFO_DEPTH         = 256,

    parameter   RP3_RX_AW_FIFO_DEPTH        = 256,
    parameter   RP3_RX_AR_FIFO_DEPTH        = 256,
    parameter   RP3_RX_W_FIFO_DEPTH         = 256,
    parameter   RP3_RX_R_FIFO_DEPTH         = 256,
    parameter   RP3_RX_B_FIFO_DEPTH         = 256,

    //Must be set all of the RP's TX MAX Credit with same value
    parameter   RP0_TX_AW_MAX_CREDIT        = 2048,
    parameter   RP0_TX_AR_MAX_CREDIT        = 2048,
    parameter   RP0_TX_W_MAX_CREDIT         = 2048,
    parameter   RP0_TX_R_MAX_CREDIT         = 2048,
    parameter   RP0_TX_B_MAX_CREDIT         = 2048,

    parameter   RP1_TX_AW_MAX_CREDIT        = 2048,
    parameter   RP1_TX_AR_MAX_CREDIT        = 2048,
    parameter   RP1_TX_W_MAX_CREDIT         = 2048,
    parameter   RP1_TX_R_MAX_CREDIT         = 2048,
    parameter   RP1_TX_B_MAX_CREDIT         = 2048,

    parameter   RP2_TX_AW_MAX_CREDIT        = 2048,
    parameter   RP2_TX_AR_MAX_CREDIT        = 2048,
    parameter   RP2_TX_W_MAX_CREDIT         = 2048,
    parameter   RP2_TX_R_MAX_CREDIT         = 2048,
    parameter   RP2_TX_B_MAX_CREDIT         = 2048,

    parameter   RP3_TX_AW_MAX_CREDIT        = 2048,
    parameter   RP3_TX_AR_MAX_CREDIT        = 2048,
    parameter   RP3_TX_W_MAX_CREDIT         = 2048,
    parameter   RP3_TX_R_MAX_CREDIT         = 2048,
    parameter   RP3_TX_B_MAX_CREDIT         = 2048,

    parameter   RP0_AXI_DATA_WD             = 512,
    parameter   RP1_AXI_DATA_WD             = 512,
    parameter   RP2_AXI_DATA_WD             = 512,
    parameter   RP3_AXI_DATA_WD             = 512,
    
    parameter   RP0_AGG_WCH_FIFO_DEPTH      = 16,
    parameter   RP1_AGG_WCH_FIFO_DEPTH      = 16,
    parameter   RP2_AGG_WCH_FIFO_DEPTH      = 16,
    parameter   RP3_AGG_WCH_FIFO_DEPTH      = 16,

    // The widest data message AoU defines (WriteData1024/ReadData1024). The receiver
    // cannot know the remote die's AXI width, so the RX data path is sized for the
    // maximum and this is not an integration parameter.
    localparam  AXI_PEER_DIE_MAX_DATA_WD    = 1024,

    parameter   APB_ADDR_WD                 = 32,
    parameter   APB_DATA_WD                 = 32,

    // TX flit packer output stage: 0 combinational (current state),
    // 1 registered from the look-ahead state. See AOU_TX_CORE.
    parameter   TX_NXT_PACKING_EN           = 0,

    parameter   RP0_S_RD_MO_CNT             = 32,
    parameter   RP0_S_WR_MO_CNT             = 32,
    parameter   RP0_M_RD_MO_CNT             = 32,
    parameter   RP0_M_WR_MO_CNT             = 32,

    parameter   RP1_S_RD_MO_CNT             = 32,
    parameter   RP1_S_WR_MO_CNT             = 32,
    parameter   RP1_M_RD_MO_CNT             = 32,
    parameter   RP1_M_WR_MO_CNT             = 32,

    parameter   RP2_S_RD_MO_CNT             = 32,
    parameter   RP2_S_WR_MO_CNT             = 32,
    parameter   RP2_M_RD_MO_CNT             = 32,
    parameter   RP2_M_WR_MO_CNT             = 32,

    parameter   RP3_S_RD_MO_CNT             = 32,
    parameter   RP3_S_WR_MO_CNT             = 32,
    parameter   RP3_M_RD_MO_CNT             = 32,
    parameter   RP3_M_WR_MO_CNT             = 32,

    parameter   FDI_IF_WD0                  = 512,
    parameter   FDI_IF_WD1                  = 512,
    parameter   RP_COUNT                    = 1,
    parameter   DEC_MULTI                   = 2,
    parameter   PHY_TYPE                    = 1,

    // Active FDI width for RX decode: max of the two PHY widths. In both
    // TWO_PHY and single-PHY configurations this matches the width the
    // AOU_RX_CORE expects on its I_FDI_PL_DATA bus.
    localparam  FDI_DEC_WD                  = (FDI_IF_WD0 > FDI_IF_WD1) ? FDI_IF_WD0 : FDI_IF_WD1,

    localparam  RP0_AXI_STRB_WD             = RP0_AXI_DATA_WD / 8,
    localparam  RP1_AXI_STRB_WD             = RP1_AXI_DATA_WD / 8,
    localparam  RP2_AXI_STRB_WD             = RP2_AXI_DATA_WD / 8,
    localparam  RP3_AXI_STRB_WD             = RP3_AXI_DATA_WD / 8,

    localparam  RP_AXI_DATA_WD_MAX          = max4(RP0_AXI_DATA_WD, RP1_AXI_DATA_WD, RP2_AXI_DATA_WD, RP3_AXI_DATA_WD),
    localparam  RP_AXI_STRB_WD_MAX          = RP_AXI_DATA_WD_MAX / 8,

    localparam  AXI_ADDR_WD                 = 64,
    localparam  AXI_ID_WD                   = 10,
    localparam  AXI_LEN_WD                  = 8,

    localparam  AXI_MAX_STRB_WD             = AXI_PEER_DIE_MAX_DATA_WD / 8,

    localparam  MAX_MISC_COUNT              = 2,
    localparam  MAX_REQ_COUNT               = 4,
    localparam  MAX_WR_RESP_COUNT           = 12,
    localparam  DATA_DEC_CNT                = 4,

    parameter   AW_AR_FIFO_WIDTH            = AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 1 + 4 + 3 + 4,
    parameter   B_FIFO_WIDTH                = AXI_ID_WD + 2,
    parameter   R_FIFO_EXT_DATA_WIDTH       = AXI_ID_WD + 2 + 1,

    localparam int unsigned RP_AXI_DATA_WD[4]  = '{
        RP0_AXI_DATA_WD,
        RP1_AXI_DATA_WD,
        RP2_AXI_DATA_WD,
        RP3_AXI_DATA_WD
    },

    localparam int unsigned RP_AXI_STRB_WD[4]  = '{
        RP0_AXI_STRB_WD,
        RP1_AXI_STRB_WD,
        RP2_AXI_STRB_WD,
        RP3_AXI_STRB_WD
    },

    localparam int unsigned AGG_WCH_FIFO_DEPTH[4]  = '{
        RP0_AGG_WCH_FIFO_DEPTH,
        RP1_AGG_WCH_FIFO_DEPTH,
        RP2_AGG_WCH_FIFO_DEPTH,
        RP3_AGG_WCH_FIFO_DEPTH
    },

    localparam int unsigned RP_S_RD_MO_CNT[4]  = '{
        RP0_S_RD_MO_CNT,
        RP1_S_RD_MO_CNT,
        RP2_S_RD_MO_CNT,
        RP3_S_RD_MO_CNT
    },

    localparam int unsigned RP_S_WR_MO_CNT[4]  = '{
        RP0_S_WR_MO_CNT,
        RP1_S_WR_MO_CNT,
        RP2_S_WR_MO_CNT,
        RP3_S_WR_MO_CNT
    },

    localparam int unsigned RP_M_RD_MO_CNT[4]  = '{
        RP0_M_RD_MO_CNT,
        RP1_M_RD_MO_CNT,
        RP2_M_RD_MO_CNT,
        RP3_M_RD_MO_CNT
    },

    localparam int unsigned RP_M_WR_MO_CNT[4]  = '{
        RP0_M_WR_MO_CNT,
        RP1_M_WR_MO_CNT,
        RP2_M_WR_MO_CNT,
        RP3_M_WR_MO_CNT
    }


)
(
    input                                                   I_CLK,
    input                                                   I_RESETN,

    //APB slave I/F
    input                                                   I_AOU_APB_SI0_PSEL,
    input                                                   I_AOU_APB_SI0_PENABLE,
    input   [APB_ADDR_WD-1:0]                               I_AOU_APB_SI0_PADDR,
    input                                                   I_AOU_APB_SI0_PWRITE,
    input   [APB_DATA_WD-1:0]                               I_AOU_APB_SI0_PWDATA,

    output  [APB_DATA_WD-1:0]                               O_AOU_APB_SI0_PRDATA,
    output                                                  O_AOU_APB_SI0_PREADY,
    output                                                  O_AOU_APB_SI0_PSLVERR,

    //AXI MI I/F
    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]                   O_AOU_RX_AXI_M_ARID,
    output  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                 O_AOU_RX_AXI_M_ARADDR,
    output  [RP_COUNT-1:0][AXI_LEN_WD-1:0]                  O_AOU_RX_AXI_M_ARLEN,
    output  [RP_COUNT-1:0][2:0]                             O_AOU_RX_AXI_M_ARSIZE,
    output  [RP_COUNT-1:0][1:0]                             O_AOU_RX_AXI_M_ARBURST,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_M_ARLOCK,
    output  [RP_COUNT-1:0][3:0]                             O_AOU_RX_AXI_M_ARCACHE,
    output  [RP_COUNT-1:0][2:0]                             O_AOU_RX_AXI_M_ARPROT,
    output  [RP_COUNT-1:0][3:0]                             O_AOU_RX_AXI_M_ARQOS,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_M_ARVALID,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_M_ARREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_TX_AXI_M_RID,
    input   [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]          I_AOU_TX_AXI_M_RDATA,
    input   [RP_COUNT-1:0][1:0]                             I_AOU_TX_AXI_M_RRESP,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_M_RLAST,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_M_RVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_TX_AXI_M_RREADY,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]                   O_AOU_RX_AXI_M_AWID,
    output  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                 O_AOU_RX_AXI_M_AWADDR,
    output  [RP_COUNT-1:0][AXI_LEN_WD-1:0]                  O_AOU_RX_AXI_M_AWLEN,
    output  [RP_COUNT-1:0][2:0]                             O_AOU_RX_AXI_M_AWSIZE,
    output  [RP_COUNT-1:0][1:0]                             O_AOU_RX_AXI_M_AWBURST,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_M_AWLOCK,
    output  [RP_COUNT-1:0][3:0]                             O_AOU_RX_AXI_M_AWCACHE,
    output  [RP_COUNT-1:0][2:0]                             O_AOU_RX_AXI_M_AWPROT,
    output  [RP_COUNT-1:0][3:0]                             O_AOU_RX_AXI_M_AWQOS,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_M_AWVALID,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_M_AWREADY,

    output  [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]          O_AOU_RX_AXI_M_WDATA,
    output  [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]          O_AOU_RX_AXI_M_WSTRB,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_M_WLAST,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_M_WVALID,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_M_WREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_TX_AXI_M_BID,
    input   [RP_COUNT-1:0][1:0]                             I_AOU_TX_AXI_M_BRESP,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_M_BVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_TX_AXI_M_BREADY,

    //AXI SI I/F
    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_TX_AXI_S_ARID,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                 I_AOU_TX_AXI_S_ARADDR,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]                  I_AOU_TX_AXI_S_ARLEN,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_TX_AXI_S_ARSIZE,
    input   [RP_COUNT-1:0][1:0]                             I_AOU_TX_AXI_S_ARBURST,       //There is no burst field on AOU
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_S_ARLOCK,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_TX_AXI_S_ARCACHE,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_TX_AXI_S_ARPROT,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_TX_AXI_S_ARQOS,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_S_ARVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_TX_AXI_S_ARREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_RX_AXI_S_RID,
    input   [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]    I_AOU_RX_AXI_S_RDATA,
    input   [RP_COUNT-1:0][1:0]                             I_AOU_RX_AXI_S_RRESP,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_S_RLAST,
    input   [RP_COUNT-1:0][1:0]                             I_AOU_RX_AXI_S_RDLENGTH,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_S_RVALID,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_S_RREADY,
    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]                   O_AOU_RX_AXI_S_RID,
    output  [RP_COUNT-1:0][1:0]                             O_AOU_RX_AXI_S_RRESP,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_S_RLAST,
    output  [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]    O_AOU_RX_AXI_S_RDATA,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_FIFO_RREADY,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_S_RVALID_BLOCKED,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_TX_AXI_S_AWID,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                 I_AOU_TX_AXI_S_AWADDR,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]                  I_AOU_TX_AXI_S_AWLEN,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_TX_AXI_S_AWSIZE,
    input   [RP_COUNT-1:0][1:0]                             I_AOU_TX_AXI_S_AWBURST,       //There is no burst field on AOU
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_S_AWLOCK,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_TX_AXI_S_AWCACHE,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_TX_AXI_S_AWPROT,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_TX_AXI_S_AWQOS,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_S_AWVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_TX_AXI_S_AWREADY,

    input   [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]          I_AOU_TX_AXI_S_WDATA,
    input   [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]          I_AOU_TX_AXI_S_WSTRB,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_S_WLAST,
    input   [RP_COUNT-1:0]                                  I_AOU_TX_AXI_S_WVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_TX_AXI_S_WREADY,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]                   O_AOU_RX_AXI_S_BID,
    output  [RP_COUNT-1:0][1:0]                             O_AOU_RX_AXI_S_BRESP,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_S_BVALID,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_S_BREADY,

    //From W_FIFO_NS1M_safety
    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_RX_WLAST_GEN_AWID,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                 I_AOU_RX_WLAST_GEN_AWADDR,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]                  I_AOU_RX_WLAST_GEN_AWLEN,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_RX_WLAST_GEN_AWSIZE,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_WLAST_GEN_AWLOCK,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_RX_WLAST_GEN_AWCACHE,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_RX_WLAST_GEN_AWPROT,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_RX_WLAST_GEN_AWQOS,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_WLAST_GEN_AWVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_WLAST_GEN_AWREADY,

    input   [RP_COUNT-1:0][1:0]                             I_AOU_RX_WLAST_GEN_WDLENGTH,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_WLAST_GEN_WDATAF,
    input   [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]    I_AOU_RX_WLAST_GEN_WDATA,
    input   [RP_COUNT-1:0][AXI_MAX_STRB_WD-1:0]             I_AOU_RX_WLAST_GEN_WSTRB,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_WLAST_GEN_WVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_WLAST_GEN_WREADY,

    //To Early_BRESP_CTRL_AWCACHE
    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_EARLY_BRESP_CTRL_BID,
    input   [RP_COUNT-1:0][1:0]                             I_EARLY_BRESP_CTRL_BRESP,
    input   [RP_COUNT-1:0]                                  I_EARLY_BRESP_CTRL_BVALID,
    output  [RP_COUNT-1:0]                                  O_EARLY_BRESP_CTRL_BREADY,

    //From aou_rx_ar_fifo
    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]                   I_AOU_RX_AXI_MM_ARID,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                 I_AOU_RX_AXI_MM_ARADDR,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]                  I_AOU_RX_AXI_MM_ARLEN,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_RX_AXI_MM_ARSIZE,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_MM_ARLOCK,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_RX_AXI_MM_ARCACHE,
    input   [RP_COUNT-1:0][2:0]                             I_AOU_RX_AXI_MM_ARPROT,
    input   [RP_COUNT-1:0][3:0]                             I_AOU_RX_AXI_MM_ARQOS,
    input   [RP_COUNT-1:0]                                  I_AOU_RX_AXI_MM_ARVALID,
    output  [RP_COUNT-1:0]                                  O_AOU_RX_AXI_MM_ARREADY,

    //Interface for AOU_RX_CORE FDI
    input                                                   I_FDI_PL_0_VALID,
    input   [FDI_IF_WD0-1: 0]                               I_FDI_PL_0_DATA,
    input                                                   I_FDI_PL_0_FLIT_CANCEL,

`ifdef TWO_PHY
    input                                                   I_PHY_TYPE,

    input                                                   I_FDI_PL_1_VALID,
    input   [FDI_IF_WD1-1: 0]                               I_FDI_PL_1_DATA,
    input                                                   I_FDI_PL_1_FLIT_CANCEL,
`endif

    //Interface for AOU_TX_CORE FDI
    input                                                   I_FDI_PL_0_TRDY,
    input                                                   I_FDI_PL_0_STALLREQ,
    input   [3:0]                                           I_FDI_PL_0_STATE_STS,
    output  [FDI_IF_WD0-1:0]                                O_FDI_LP_0_DATA,
    output                                                  O_FDI_LP_0_VALID,
    output                                                  O_FDI_LP_0_IRDY,
    output                                                  O_FDI_LP_0_STALLACK,

`ifdef TWO_PHY
    input                                                   I_FDI_PL_1_TRDY,
    input                                                   I_FDI_PL_1_STALLREQ,
    input   [3:0]                                           I_FDI_PL_1_STATE_STS,
    output  [FDI_IF_WD1-1:0]                                O_FDI_LP_1_DATA,
    output                                                  O_FDI_LP_1_VALID,
    output                                                  O_FDI_LP_1_IRDY,
    output                                                  O_FDI_LP_1_STALLACK,
`endif

    //From RX_CORE
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0][AW_AR_FIFO_WIDTH-1:0]         O_RD_REQ_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0]                               O_RD_REQ_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0][AW_AR_FIFO_WIDTH-1:0]         O_WR_REQ_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0]                               O_WR_REQ_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]   O_WR_DATA_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                                 O_WR_DATA_FIFO_SDATA_WDATAF,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_MAX_STRB_WD -1:0]           O_WR_DATA_FIFO_SDATA_STRB,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                                 O_WR_DATA_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_WR_RESP_COUNT -1:0][B_FIFO_WIDTH-1:0]         O_WR_RESP_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_WR_RESP_COUNT -1:0]                           O_WR_RESP_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]   O_RD_DATA_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][R_FIFO_EXT_DATA_WIDTH -1:0]     O_RD_DATA_FIFO_EXT_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                                 O_RD_DATA_FIFO_SVALID,

    //Interface for Error Handler
    output                                                  O_ERR_INFO_RID_MISMATCH_ERR,
    output                                                  O_ERR_INFO_SPLIT_BID_MISMATCH_ERR,

    output                                                  O_AXI_SLV_RID_MISMATCH_ERROR,
    output                                                  O_AXI_SLV_BID_MISMATCH_ERROR,

    output                                                  O_INT_EARLY_RESP_ERR,
    output                                                  O_INT_EARLY_WDT_ERR,

    output                                                  O_INT_ACTIVATE_START,
    output                                                  O_INT_DEACTIVATE_START,
    output                                                  O_INT_FDI_LINK_DOWN,

    //Interface for UCIE_CORE
    input                                                   I_INT_FSM_IN_ACTIVE,
    output                                                  O_AOU_ACTIVATE_ST_DISABLED,
    output                                                  O_AOU_ACTIVATE_ST_ENABLED,
    output                                                  O_AOU_REQ_LINKRESET,

    //sw_reset
    output                                                  O_SW_RESET,
    output                                                  O_SLV_TR_COMPLETE,
    output                                                  O_MST_TR_COMPLETE

);

//----------------------------------------------------------------------------
    localparam  RP0_RDATA_G_SIZE                 =  (RP0_AXI_DATA_WD == 256) ? R256b_G  :
                                                    (RP0_AXI_DATA_WD == 512) ? R512b_G  :
                                                    (RP0_AXI_DATA_WD == 1024)? R1024b_G : 0;
    localparam  RP0_RDATA_FIFO_USAGE_PER_MSG     =  (RP0_AXI_DATA_WD == 256) ? 1  :
                                                    (RP0_AXI_DATA_WD == 512) ? 2  :
                                                    (RP0_AXI_DATA_WD == 1024)? 4 : 0;

    localparam  RP1_RDATA_G_SIZE                 =  (RP1_AXI_DATA_WD == 256) ? R256b_G  :
                                                    (RP1_AXI_DATA_WD == 512) ? R512b_G  :
                                                    (RP1_AXI_DATA_WD == 1024)? R1024b_G : 0;
    localparam  RP1_RDATA_FIFO_USAGE_PER_MSG     =  (RP1_AXI_DATA_WD == 256) ? 1  :
                                                    (RP1_AXI_DATA_WD == 512) ? 2  :
                                                    (RP1_AXI_DATA_WD == 1024)? 4 : 0;

    localparam  RP2_RDATA_G_SIZE                 =  (RP2_AXI_DATA_WD == 256) ? R256b_G  :
                                                    (RP2_AXI_DATA_WD == 512) ? R512b_G  :
                                                    (RP2_AXI_DATA_WD == 1024)? R1024b_G : 0;
    localparam  RP2_RDATA_FIFO_USAGE_PER_MSG     =  (RP2_AXI_DATA_WD == 256) ? 1  :
                                                    (RP2_AXI_DATA_WD == 512) ? 2  :
                                                    (RP2_AXI_DATA_WD == 1024)? 4 : 0;

    localparam  RP3_RDATA_G_SIZE                 =  (RP3_AXI_DATA_WD == 256) ? R256b_G  :
                                                    (RP3_AXI_DATA_WD == 512) ? R512b_G  :
                                                    (RP3_AXI_DATA_WD == 1024)? R1024b_G : 0;
    localparam  RP3_RDATA_FIFO_USAGE_PER_MSG     =  (RP3_AXI_DATA_WD == 256) ? 1  :
                                                    (RP3_AXI_DATA_WD == 512) ? 2  :
                                                    (RP3_AXI_DATA_WD == 1024)? 4 : 0;

    localparam  CNT_RP0_TX_AW_MAX_CREDIT    = $clog2(RP0_TX_AW_MAX_CREDIT +1);
    localparam  CNT_RP0_TX_AR_MAX_CREDIT    = $clog2(RP0_TX_AR_MAX_CREDIT +1);
    localparam  CNT_RP0_TX_W_MAX_CREDIT     = $clog2(RP0_TX_W_MAX_CREDIT  +1);
    localparam  CNT_RP0_TX_R_MAX_CREDIT     = $clog2(RP0_TX_R_MAX_CREDIT  +1);
    localparam  CNT_RP0_TX_B_MAX_CREDIT     = $clog2(RP0_TX_B_MAX_CREDIT  +1);

    localparam  CNT_RP1_TX_AW_MAX_CREDIT    = $clog2(RP1_TX_AW_MAX_CREDIT +1);
    localparam  CNT_RP1_TX_AR_MAX_CREDIT    = $clog2(RP1_TX_AR_MAX_CREDIT +1);
    localparam  CNT_RP1_TX_W_MAX_CREDIT     = $clog2(RP1_TX_W_MAX_CREDIT  +1);
    localparam  CNT_RP1_TX_R_MAX_CREDIT     = $clog2(RP1_TX_R_MAX_CREDIT  +1);
    localparam  CNT_RP1_TX_B_MAX_CREDIT     = $clog2(RP1_TX_B_MAX_CREDIT  +1);

    localparam  CNT_RP2_TX_AW_MAX_CREDIT    = $clog2(RP2_TX_AW_MAX_CREDIT +1);
    localparam  CNT_RP2_TX_AR_MAX_CREDIT    = $clog2(RP2_TX_AR_MAX_CREDIT +1);
    localparam  CNT_RP2_TX_W_MAX_CREDIT     = $clog2(RP2_TX_W_MAX_CREDIT  +1);
    localparam  CNT_RP2_TX_R_MAX_CREDIT     = $clog2(RP2_TX_R_MAX_CREDIT  +1);
    localparam  CNT_RP2_TX_B_MAX_CREDIT     = $clog2(RP2_TX_B_MAX_CREDIT  +1);

    localparam  CNT_RP3_TX_AW_MAX_CREDIT    = $clog2(RP3_TX_AW_MAX_CREDIT +1);
    localparam  CNT_RP3_TX_AR_MAX_CREDIT    = $clog2(RP3_TX_AR_MAX_CREDIT +1);
    localparam  CNT_RP3_TX_W_MAX_CREDIT     = $clog2(RP3_TX_W_MAX_CREDIT  +1);
    localparam  CNT_RP3_TX_R_MAX_CREDIT     = $clog2(RP3_TX_R_MAX_CREDIT  +1);
    localparam  CNT_RP3_TX_B_MAX_CREDIT     = $clog2(RP3_TX_B_MAX_CREDIT  +1);

    localparam  RP0_RX_AW_MAX_CREDIT        = RP0_RX_AW_FIFO_DEPTH     * AW_G;
    localparam  RP0_RX_AR_MAX_CREDIT        = RP0_RX_AR_FIFO_DEPTH     * AR_G;
    localparam  RP0_RX_W_MAX_CREDIT         = (RP0_RX_W_FIFO_DEPTH/4)  * WF1024b_G;
    localparam  RP0_RX_R_MAX_CREDIT         = (RP0_RX_R_FIFO_DEPTH/RP0_RDATA_FIFO_USAGE_PER_MSG)  * RP0_RDATA_G_SIZE;
    localparam  RP0_RX_B_MAX_CREDIT         = RP0_RX_B_FIFO_DEPTH      * B_G;

    localparam  RP1_RX_AW_MAX_CREDIT        = RP1_RX_AW_FIFO_DEPTH     * AW_G;
    localparam  RP1_RX_AR_MAX_CREDIT        = RP1_RX_AR_FIFO_DEPTH     * AR_G;
    localparam  RP1_RX_W_MAX_CREDIT         = (RP1_RX_W_FIFO_DEPTH/4)  * WF1024b_G;
    localparam  RP1_RX_R_MAX_CREDIT         = (RP1_RX_R_FIFO_DEPTH/RP1_RDATA_FIFO_USAGE_PER_MSG)  * RP1_RDATA_G_SIZE;
    localparam  RP1_RX_B_MAX_CREDIT         = RP1_RX_B_FIFO_DEPTH      * B_G;

    localparam  RP2_RX_AW_MAX_CREDIT        = RP2_RX_AW_FIFO_DEPTH     * AW_G;
    localparam  RP2_RX_AR_MAX_CREDIT        = RP2_RX_AR_FIFO_DEPTH     * AR_G;
    localparam  RP2_RX_W_MAX_CREDIT         = (RP2_RX_W_FIFO_DEPTH/4)  * WF1024b_G;
    localparam  RP2_RX_R_MAX_CREDIT         = (RP2_RX_R_FIFO_DEPTH/RP2_RDATA_FIFO_USAGE_PER_MSG)  * RP2_RDATA_G_SIZE;
    localparam  RP2_RX_B_MAX_CREDIT         = RP2_RX_B_FIFO_DEPTH      * B_G;

    localparam  RP3_RX_AW_MAX_CREDIT        = RP3_RX_AW_FIFO_DEPTH     * AW_G;
    localparam  RP3_RX_AR_MAX_CREDIT        = RP3_RX_AR_FIFO_DEPTH     * AR_G;
    localparam  RP3_RX_W_MAX_CREDIT         = (RP3_RX_W_FIFO_DEPTH/4)  * WF1024b_G;
    localparam  RP3_RX_R_MAX_CREDIT         = (RP3_RX_R_FIFO_DEPTH/RP3_RDATA_FIFO_USAGE_PER_MSG)  * RP3_RDATA_G_SIZE;
    localparam  RP3_RX_B_MAX_CREDIT         = RP3_RX_B_FIFO_DEPTH      * B_G;

    localparam  CNT_RP_TX_AW_MAX_CREDIT_MAX = max4(CNT_RP0_TX_AW_MAX_CREDIT, CNT_RP1_TX_AW_MAX_CREDIT, CNT_RP2_TX_AW_MAX_CREDIT, CNT_RP3_TX_AW_MAX_CREDIT);
    localparam  CNT_RP_TX_AR_MAX_CREDIT_MAX = max4(CNT_RP0_TX_AR_MAX_CREDIT, CNT_RP1_TX_AR_MAX_CREDIT, CNT_RP2_TX_AR_MAX_CREDIT, CNT_RP3_TX_AR_MAX_CREDIT);
    localparam  CNT_RP_TX_W_MAX_CREDIT_MAX  = max4(CNT_RP0_TX_W_MAX_CREDIT,  CNT_RP1_TX_W_MAX_CREDIT,  CNT_RP2_TX_W_MAX_CREDIT,  CNT_RP3_TX_W_MAX_CREDIT);
    localparam  CNT_RP_TX_R_MAX_CREDIT_MAX  = max4(CNT_RP0_TX_R_MAX_CREDIT,  CNT_RP1_TX_R_MAX_CREDIT,  CNT_RP2_TX_R_MAX_CREDIT,  CNT_RP3_TX_R_MAX_CREDIT);
    localparam  CNT_RP_TX_B_MAX_CREDIT_MAX  = max4(CNT_RP0_TX_B_MAX_CREDIT,  CNT_RP1_TX_B_MAX_CREDIT,  CNT_RP2_TX_B_MAX_CREDIT,  CNT_RP3_TX_B_MAX_CREDIT);

//----------------------------------------------------------------------------
    logic    [RP_COUNT-1:0]                             w_aou_slv_info_ar_hold_flag     ;

    logic    [RP_COUNT-1:0][AXI_ID_WD-1:0]              w_early_bresp_ctrl_awid         ;
    logic    [RP_COUNT-1:0][AXI_ADDR_WD-1:0]            w_early_bresp_ctrl_awaddr       ;
    logic    [RP_COUNT-1:0][AXI_LEN_WD-1:0]             w_early_bresp_ctrl_awlen        ;
    logic    [RP_COUNT-1:0][2:0]                        w_early_bresp_ctrl_awsize       ;
    logic    [RP_COUNT-1:0][1:0]                        w_early_bresp_ctrl_awburst      ;
    logic    [RP_COUNT-1:0]                             w_early_bresp_ctrl_awlock       ;
    logic    [RP_COUNT-1:0][3:0]                        w_early_bresp_ctrl_awcache      ;
    logic    [RP_COUNT-1:0][2:0]                        w_early_bresp_ctrl_awprot       ;
    logic    [RP_COUNT-1:0][3:0]                        w_early_bresp_ctrl_awqos        ;
    logic    [RP_COUNT-1:0]                             w_early_bresp_ctrl_awvalid      ;
    logic    [RP_COUNT-1:0]                             w_early_bresp_ctrl_awready      ;

    logic    [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]     w_early_bresp_ctrl_wdata        ;
    logic    [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]     w_early_bresp_ctrl_wstrb        ;
    logic    [RP_COUNT-1:0]                             w_early_bresp_ctrl_wlast        ;
    logic    [RP_COUNT-1:0][1:0]                        w_early_bresp_ctrl_wdlen        ;
    logic    [RP_COUNT-1:0]                             w_early_bresp_ctrl_wvalid       ;
    logic    [RP_COUNT-1:0]                             w_early_bresp_ctrl_wready       ;

    logic    [3:0]                                      w_early_bresp_wdt_timeout_err   ;
    logic    [31:0]                                     w_early_bresp_wdt_threshold     ;
    logic    [3:0]                                      w_early_bresp_wdt_en            ;
    logic    [3:0]                                      w_early_bresp_always_en         ;
    logic    [3:0]                                      w_early_bresp_en                ;
    logic    [3:0]                                      w_early_bresp_done              ;
    logic    [3:0]                                      w_bresp_err                     ;
    logic    [3:0][AXI_ID_WD-1:0]                       w_bresp_err_id                  ;
    logic    [3:0][1:0]                                 w_bresp_err_type                ;

    logic    [3:0][1:0]                                 w_rp_dest_rp                    ;

    logic    [3:0]                                      w_prior_rp_axi_axi_qos_to_np    ;
    logic    [3:0]                                      w_prior_rp_axi_axi_qos_to_hp    ;
    logic    [1:0]                                      w_prior_rp_axi_rp3_prior        ;
    logic    [1:0]                                      w_prior_rp_axi_rp2_prior        ;
    logic    [1:0]                                      w_prior_rp_axi_rp1_prior        ;
    logic    [1:0]                                      w_prior_rp_axi_rp0_prior        ;
    logic    [1:0]                                      w_prior_rp_axi_arb_mode         ;
    logic    [15:0]                                     w_prior_timer_timer_resolution  ;
    logic    [15:0]                                     w_prior_timer_timer_threshold   ;

    logic    [3:0]                                      w_axi_slv_id_mismatch_en        ;
    
    logic    [1:0]                                      w_rp0_tx_rp_sel                 ;
    logic    [1:0]                                      w_rp1_tx_rp_sel                 ;
    logic    [1:0]                                      w_rp2_tx_rp_sel                 ;
    logic    [1:0]                                      w_rp3_tx_rp_sel                 ;
    logic                                               w_asymmetric_rp_sel             ;    
//----------------------------------------------------------------------------
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][1:0]  w_rxcore_crdtgrant_wrespcred3   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][1:0]  w_rxcore_crdtgrant_wrespcred2   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][1:0]  w_rxcore_crdtgrant_wrespcred1   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][1:0]  w_rxcore_crdtgrant_wrespcred0   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rdatacred3   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rdatacred2   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rdatacred1   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rdatacred0   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wdatacred3   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wdatacred2   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wdatacred1   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wdatacred0   ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rreqcred3    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rreqcred2    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rreqcred1    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_rreqcred0    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wreqcred3    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wreqcred2    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wreqcred1    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0][2:0]  w_rxcore_crdtgrant_wreqcred0    ;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT-1:0]       w_rxcore_crdtgrant_valid        ;

    logic [1:0]                             w_rxcore_msgcrdt_wrespcred      ;
    logic [2:0]                             w_rxcore_msgcrdt_rdatacred      ;
    logic [2:0]                             w_rxcore_msgcrdt_wdatacred      ;
    logic [2:0]                             w_rxcore_msgcrdt_rreqcred       ;
    logic [2:0]                             w_rxcore_msgcrdt_wreqcred       ;
    logic [1:0]                             w_rxcore_msgcrdt_rp             ;
    logic                                   w_rxcore_msgcrdt_valid          ;

    logic [2:0]                             w_txcore_msgcredit_wreqcred     ;
    logic [2:0]                             w_txcore_msgcredit_rreqcred     ;
    logic [2:0]                             w_txcore_msgcredit_wdatacred    ;
    logic [2:0]                             w_txcore_msgcredit_rdatacred    ;
    logic [1:0]                             w_txcore_msgcredit_wrespcred    ;
    logic [1:0]                             w_txcore_msgcredit_rp           ;
    logic                                   w_txcore_msgcredit_cred_valid   ;
    logic                                   w_txcore_msgcredit_cred_ready   ;

    logic [1:0]                             w_txcore_crdtgrant_wrespcred3   ;
    logic [1:0]                             w_txcore_crdtgrant_wrespcred2   ;
    logic [1:0]                             w_txcore_crdtgrant_wrespcred1   ;
    logic [1:0]                             w_txcore_crdtgrant_wrespcred0   ;
    logic [2:0]                             w_txcore_crdtgrant_rdatacred3   ;
    logic [2:0]                             w_txcore_crdtgrant_rdatacred2   ;
    logic [2:0]                             w_txcore_crdtgrant_rdatacred1   ;
    logic [2:0]                             w_txcore_crdtgrant_rdatacred0   ;
    logic [2:0]                             w_txcore_crdtgrant_wdatacred3   ;
    logic [2:0]                             w_txcore_crdtgrant_wdatacred2   ;
    logic [2:0]                             w_txcore_crdtgrant_wdatacred1   ;
    logic [2:0]                             w_txcore_crdtgrant_wdatacred0   ;
    logic [2:0]                             w_txcore_crdtgrant_rreqcred3    ;
    logic [2:0]                             w_txcore_crdtgrant_rreqcred2    ;
    logic [2:0]                             w_txcore_crdtgrant_rreqcred1    ;
    logic [2:0]                             w_txcore_crdtgrant_rreqcred0    ;
    logic [2:0]                             w_txcore_crdtgrant_wreqcred3    ;
    logic [2:0]                             w_txcore_crdtgrant_wreqcred2    ;
    logic [2:0]                             w_txcore_crdtgrant_wreqcred1    ;
    logic [2:0]                             w_txcore_crdtgrant_wreqcred0    ;
    logic                                   w_txcore_crdtgrant_valid        ;
    logic                                   w_txcore_crdtgrant_ready        ;

    logic                                   w_tx_req_credit_blockn          ;
    logic                                   w_tx_rsp_credit_blockn          ;

    //interface
    logic [RP_COUNT-1:0][CNT_RP_TX_AW_MAX_CREDIT_MAX-1:0] w_aou_tx_wreqcred ;
    logic [RP_COUNT-1:0][CNT_RP_TX_AR_MAX_CREDIT_MAX-1:0] w_aou_tx_rreqcred ;
    logic [RP_COUNT-1:0][CNT_RP_TX_W_MAX_CREDIT_MAX-1:0]  w_aou_tx_wdatacred;
    logic [RP_COUNT-1:0][CNT_RP_TX_R_MAX_CREDIT_MAX-1:0]  w_aou_tx_rdatacred;
    logic [RP_COUNT-1:0][CNT_RP_TX_B_MAX_CREDIT_MAX-1:0]  w_aou_tx_wrespcred;

    logic [RP_COUNT-1:0]                    w_aou_tx_wreqvalid              ;
    logic [RP_COUNT-1:0]                    w_aou_tx_rreqvalid              ;
    logic [RP_COUNT-1:0]                    w_aou_tx_wdatavalid             ;
    logic [RP_COUNT-1:0]                    w_aou_tx_wfdata                 ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_wdata_dlength          ;
    logic [RP_COUNT-1:0]                    w_aou_tx_rdatavalid             ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_rdata_dlength          ;
    logic [RP_COUNT-1:0]                    w_aou_tx_wrespvalid             ;

    logic                                   w_crd_count_en                  ;
    logic                                   w_req_crd_advertise_en          ;
    logic                                   w_tx_req_credited_message_en    ;
    logic                                   w_rsp_crd_advertise_en          ;
    logic                                   w_tx_rsp_credited_message_en    ;

    logic                                   w_tx_credited_message_en        ;
    logic                                   w_status_disabled               ;
    logic                                   w_status_deactivate             ;

    logic [3:0]                             w_txcore_activation_op          ;
    logic                                   w_txcore_activation_prop_req    ;
    logic                                   w_txcore_activation_valid       ;
    logic                                   w_txcore_activation_ready       ;
    logic                                   w_tx_pending                    ;
    logic                                   w_tx_axi_tr_pending             ;

    logic [3:0]                             w_rxcore_activation_op          ;
    logic                                   w_rxcore_activation_prop_req    ;
    logic                                   w_rxcore_activation_valid       ;

    logic [RP_COUNT-1:0][AXI_ID_WD-1:0]     w_aou_tx_axi_mm_rid             ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_axi_mm_rdlen           ;
    logic [RP_COUNT-1:0][1023:0]            w_aou_tx_axi_mm_rdata           ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_axi_mm_rresp           ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_rlast           ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_rvalid          ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_rready          ;

    logic [RP_COUNT-1:0][AXI_ID_WD-1:0]     w_aou_tx_axi_mm_bid_256         ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_axi_mm_bresp_256       ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_bvalid_256      ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_bready_256      ;

    logic [RP_COUNT-1:0][AXI_ID_WD-1:0]     w_aou_tx_axi_mm_bid_512         ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_axi_mm_bresp_512       ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_bvalid_512      ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_bready_512      ;

    logic [RP_COUNT-1:0][AXI_ID_WD-1:0]     w_aou_tx_axi_mm_bid_1024        ;
    logic [RP_COUNT-1:0][1:0]               w_aou_tx_axi_mm_bresp_1024      ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_bvalid_1024     ;
    logic [RP_COUNT-1:0]                    w_aou_tx_axi_mm_bready_1024     ;

    wire                                    w_deactivate_property           ;
    logic [3:0][AXI_LEN_WD-1:0]             w_axi_split_tr_max_awburstlen   ;
    logic [3:0][AXI_LEN_WD-1:0]             w_axi_split_tr_max_arburstlen   ;
    logic [7:0]                             w_tx_lp_mode_threshold          ;
    logic                                   w_tx_lp_mode                    ;
    logic                                   w_activate_start                ;
    logic [2:0]                             w_deactivate_time_out_value     ;
    logic                                   w_deactivate_start              ;
    wire                                    w_deactivate_force              ;
    logic                                   w_int_activate_start            ;
    logic                                   w_int_deactivate_start          ;
    logic                                   w_int_fdi_link_down_set         ;
    logic                                   w_int_fdi_link_down             ;

    logic [2:0]                             w_ack_time_out_value            ;
    logic [2:0]                             w_msgcredit_time_out_value      ;
    logic                                   w_act_ack_err_set               ;
    logic                                   w_deact_ack_err_set             ;
    logic [3:0]                             w_invalid_actmsg_opcode         ;
    logic                                   w_invalid_actmsg_err_set        ;
    logic                                   w_msgcredit_err_set             ;

//----------------------------------------------------------------------------

    logic [3:0][31:0]           w_debug_error_info_upper_addr;
    logic [3:0][31:0]           w_debug_error_info_lower_addr;
    logic [3:0]                 w_debug_error_info_access_enable;
    logic [3:0]                 w_axi_aggregator_en;

//----------------------------------------------------------------------------
    logic [3:0][AXI_ID_WD-1:0]  w_err_info_split_bid_mismatch, w_err_info_rid_mismatch;
    logic [3:0]                 w_err_split_bid_mismatch_set, w_err_rid_mismatch_set;
    logic [3:0][AXI_ID_WD-1:0]  w_axi_slv_bid_mismatch_info, w_axi_slv_rid_mismatch_info;
    logic [3:0]                 w_axi_slv_bid_mismatch_err_set, w_axi_slv_rid_mismatch_err_set;

    logic [3:0]                 w_slv_tr_complete;
    logic [3:0]                 w_mst_tr_complete;

    logic                       r_fdi_pl_0_stallreq;
`ifdef TWO_PHY
    logic                       r_fdi_pl_1_stallreq;
`endif

    logic                       w_invalid_actmsg_mask;
    logic                       w_msgcredit_timeout_mask;
    logic                       w_act_timeout_mask;
    logic                       w_deact_timeout_mask;
    logic                       w_early_resp_mask;
    logic                       w_early_wdt_mask;
    logic                       w_fdi_link_down_mask;
    logic                       w_mi0_id_mismatch_mask;
    logic                       w_si0_id_mismatch_mask;

    logic                       w_err_info_rid_mismatch_err;
    logic                       w_err_info_split_bid_mismatch_err;
    logic                       w_axi_slv_rid_mismatch_error;
    logic                       w_axi_slv_bid_mismatch_error;
    logic                       w_int_early_resp_err;
    logic                       w_int_early_wdt_err;

    logic                       w_act_ack_err;
    logic                       w_deact_ack_err;
    logic                       w_invalid_actmsg_err;
    logic                       w_msgcredit_err;
    logic                       w_act_ack_err_b;
    logic                       w_deact_ack_err_b;
    logic                       w_invalid_actmsg_err_b;
    logic                       w_msgcredit_err_b;

    logic  [RP_COUNT-1:0]                                 w_aou_tx_axi_s_arvalid_tmp          ;
    logic  [RP_COUNT-1:0]                                 w_aou_tx_axi_s_arready_tmp          ;

    logic  [RP_COUNT-1:0][AXI_ID_WD-1:0]                  w_aou_tx_axi_s_arid                 ;
    logic  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                w_aou_tx_axi_s_araddr               ;
    logic  [RP_COUNT-1:0][AXI_LEN_WD-1:0]                 w_aou_tx_axi_s_arlen                ;
    logic  [RP_COUNT-1:0][2:0]                            w_aou_tx_axi_s_arsize               ;
    logic  [RP_COUNT-1:0][1:0]                            w_aou_tx_axi_s_arburst              ;//there is no burst field on aou
    logic  [RP_COUNT-1:0]                                 w_aou_tx_axi_s_arlock               ;
    logic  [RP_COUNT-1:0][3:0]                            w_aou_tx_axi_s_arcache              ;
    logic  [RP_COUNT-1:0][2:0]                            w_aou_tx_axi_s_arprot               ;
    logic  [RP_COUNT-1:0][3:0]                            w_aou_tx_axi_s_arqos                ;
    logic  [RP_COUNT-1:0]                                 w_aou_tx_axi_s_arvalid              ;
    logic  [RP_COUNT-1:0]                                 w_aou_tx_axi_s_arready              ;

    logic  [RP_COUNT-1:0][AXI_ID_WD-1:0]                  w_tmp_early_bresp_ctrl_awid         ;
    logic  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]                w_tmp_early_bresp_ctrl_awaddr       ;
    logic  [RP_COUNT-1:0][AXI_LEN_WD-1:0]                 w_tmp_early_bresp_ctrl_awlen        ;
    logic  [RP_COUNT-1:0][2:0]                            w_tmp_early_bresp_ctrl_awsize       ;
    logic  [RP_COUNT-1:0][1:0]                            w_tmp_early_bresp_ctrl_awburst      ;
    logic  [RP_COUNT-1:0]                                 w_tmp_early_bresp_ctrl_awlock       ;
    logic  [RP_COUNT-1:0][3:0]                            w_tmp_early_bresp_ctrl_awcache      ;
    logic  [RP_COUNT-1:0][2:0]                            w_tmp_early_bresp_ctrl_awprot       ;
    logic  [RP_COUNT-1:0][3:0]                            w_tmp_early_bresp_ctrl_awqos        ;
    logic  [RP_COUNT-1:0]                                 w_tmp_early_bresp_ctrl_awvalid      ;
    logic  [RP_COUNT-1:0]                                 w_tmp_early_bresp_ctrl_awready      ;
    
    logic  [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]         w_tmp_early_bresp_ctrl_wdata        ;
    logic  [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]         w_tmp_early_bresp_ctrl_wstrb        ;
    logic  [RP_COUNT-1:0]                                 w_tmp_early_bresp_ctrl_wlast        ;
    logic  [RP_COUNT-1:0][1:0]                            w_tmp_early_bresp_ctrl_wdlen        ;
    logic  [RP_COUNT-1:0]                                 w_tmp_early_bresp_ctrl_wvalid       ;
    logic  [RP_COUNT-1:0]                                 w_tmp_early_bresp_ctrl_wready       ;
    
    logic  [RP_COUNT-1:0]                                 w_aou_rx_axi_s_rvalid               ;

    logic  [RP_COUNT-1:0][AXI_ID_WD-1:0]                  w_early_bresp_ctrl_bid              ; 
    logic  [RP_COUNT-1:0][1:0]                            w_early_bresp_ctrl_bresp            ; 
    logic  [RP_COUNT-1:0]                                 w_early_bresp_ctrl_bvalid           ; 
    logic  [RP_COUNT-1:0]                                 w_early_bresp_ctrl_bready           ; 

//----------------------------------------------------------------------------
     always_ff @ (posedge I_CLK or negedge I_RESETN) begin
        if (~I_RESETN) begin
            r_fdi_pl_0_stallreq <= 1'b0;
        end else begin
            r_fdi_pl_0_stallreq <= I_FDI_PL_0_STALLREQ;
        end
    end

`ifdef TWO_PHY
    always_ff @ (posedge I_CLK or negedge I_RESETN) begin
        if (~I_RESETN) begin
            r_fdi_pl_1_stallreq <= 1'b0;
        end else begin
            r_fdi_pl_1_stallreq <= I_FDI_PL_1_STALLREQ;
        end
    end
`endif


    AOU_CORE_SFR #(
        .APB_ADDR_WD    ( APB_ADDR_WD   )
    ) u_aou_core_sfr
    (
        .I_PCLK                                                         ( I_CLK                                 ),
        .I_PRESETN                                                      ( I_RESETN                              ),

        .I_PSEL                                                         ( I_AOU_APB_SI0_PSEL                    ),
        .I_PENABLE                                                      ( I_AOU_APB_SI0_PENABLE                 ),
        .I_PADDR                                                        ( I_AOU_APB_SI0_PADDR                   ),
        .I_PWRITE                                                       ( I_AOU_APB_SI0_PWRITE                  ),
        .I_PWDATA                                                       ( I_AOU_APB_SI0_PWDATA                  ),

        .O_PRDATA                                                       ( O_AOU_APB_SI0_PRDATA                  ),
        .O_PREADY                                                       ( O_AOU_APB_SI0_PREADY                  ),
        .O_PSLVERR                                                      ( O_AOU_APB_SI0_PSLVERR                 ),

        .I_IP_VERSION_MAJOR_VERSION                                     ( 16'd1                                 ),
        .I_IP_VERSION_MINOR_VERSION                                     ( 16'b0                                 ),

        .O_AOU_CON0_AOU_SW_RESET                                        ( O_SW_RESET                            ),
        .O_AOU_CON0_DEACTIVATE_FORCE                                    ( w_deactivate_force                    ),
        .I_AOU_INIT_INT_DEACTIVATE_PROPERTY                             ( w_deactivate_property                 ),

        .O_AXI_SPLIT_TR_RP0_MAX_AWBURSTLEN                              ( w_axi_split_tr_max_awburstlen[0]      ),
        .O_AXI_SPLIT_TR_RP0_MAX_ARBURSTLEN                              ( w_axi_split_tr_max_arburstlen[0]      ),
        .O_AOU_CON0_TX_LP_MODE_THRESHOLD                                (  w_tx_lp_mode_threshold               ),
        .O_AOU_CON0_TX_LP_MODE                                          (  w_tx_lp_mode                         ),

        .I_AOU_INIT_MST_TR_COMPLETE                                     ( O_MST_TR_COMPLETE                     ),
        .I_AOU_INIT_SLV_TR_COMPLETE                                     ( O_SLV_TR_COMPLETE                     ),
        .I_AOU_INIT_INT_ACTIVATE_START_SET                              ( w_int_activate_start                  ),
        .I_AOU_INIT_INT_DEACTIVATE_START_SET                            ( w_int_deactivate_start                ),
        .I_AOU_INIT_INT_FDI_LINK_DOWN_SET                               ( w_int_fdi_link_down_set               ),
        .O_AOU_INIT_DEACTIVATE_TIME_OUT_VALUE                           ( w_deactivate_time_out_value           ),
        .I_AOU_INIT_ACTIVATE_STATE_DISABLED                             ( w_status_disabled                     ),
        .I_AOU_INIT_ACTIVATE_STATE_ENABLED                              ( O_AOU_ACTIVATE_ST_ENABLED             ),
        .O_AOU_INIT_DEACTIVATE_START                                    ( w_deactivate_start                    ),
        .O_AOU_INIT_ACTIVATE_START                                      ( w_activate_start                      ),

        .I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_INFO                       ( w_err_info_split_bid_mismatch[0]      ),
        .I_ERROR_INFO_RP0_RID_MISMATCH_INFO                             ( w_err_info_rid_mismatch[0]            ),
        .I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_ERR_SET                    ( w_err_split_bid_mismatch_set[0]       ),
        .I_ERROR_INFO_RP0_RID_MISMATCH_ERR_SET                          ( w_err_rid_mismatch_set[0]             ),

        .O_WRITE_EARLY_RESPONSE_WDT_THRESHOLD                           ( w_early_bresp_wdt_threshold           ),
        .I_WRITE_EARLY_RESPONSE_RP0_WDT_TRANS_TIMEOUT_ERR               ( w_early_bresp_wdt_timeout_err[0]      ),
        .I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_DONE                     ( w_early_bresp_done[0]                 ),
        .I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_SET                  ( w_bresp_err[0]                        ),
        .I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_TYPE_INFO            ( w_bresp_err_type[0]                   ),
        .I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_ID_INFO              ( w_bresp_err_id[0]                     ),
        .O_WRITE_EARLY_RESPONSE_RP0_EARLY_BRESP_EN                      ( w_early_bresp_en[0]                   ),
        .O_WRITE_EARLY_RESPONSE_RP0_EARLY_ALWAYS_EN                     ( w_early_bresp_always_en[0]            ),
        .O_WRITE_EARLY_RESPONSE_RP0_WDT_EN                              ( w_early_bresp_wdt_en[0]               ),

        .O_LP_LINKRESET_ACK_TIME_OUT_VALUE                              ( w_ack_time_out_value                  ),
        .O_LP_LINKRESET_MSGCREDIT_TIME_OUT_VALUE                        ( w_msgcredit_time_out_value            ),
        .I_LP_LINKRESET_ACT_ACK_ERR_SET                                 ( w_act_ack_err_set                     ),
        .I_LP_LINKRESET_DEACT_ACK_ERR_SET                               ( w_deact_ack_err_set                   ),
        .I_LP_LINKRESET_INVALID_ACTMSG_INFO                             ( w_invalid_actmsg_opcode               ),
        .I_LP_LINKRESET_INVALID_ACTMSG_ERR_SET                          ( w_invalid_actmsg_err_set              ),
        .I_LP_LINKRESET_MSGCREDIT_ERR_SET                               ( w_msgcredit_err_set                   ),

        .O_AXI_ERROR_INFO0_RP0_DEBUG_UPPER_ADDR                         ( w_debug_error_info_upper_addr[0]      ),
        .O_AXI_ERROR_INFO1_RP0_DEBUG_LOWER_ADDR                         ( w_debug_error_info_lower_addr[0]      ),
        .O_AOU_CON0_RP0_ERROR_INFO_ACCESS_EN                            ( w_debug_error_info_access_enable[0]   ),

        .O_AOU_CON0_RP0_AXI_AGGREGATOR_EN                               ( w_axi_aggregator_en[0]                ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_INFO        ( w_axi_slv_bid_mismatch_info[0]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_INFO        ( w_axi_slv_rid_mismatch_info[0]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_ERR_SET     ( w_axi_slv_bid_mismatch_err_set[0]     ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_ERR_SET     ( w_axi_slv_rid_mismatch_err_set[0]     ),
        .O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_ACT_ACK_MASK            ( w_act_timeout_mask                    ),
        .O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_DEACT_ACK_MASK          ( w_deact_timeout_mask                  ),
        .O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_INVALID_ACTMSG_MASK     ( w_invalid_actmsg_mask                 ),
        .O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_MSGCREDIT_TIMEOUT_MASK  ( w_msgcredit_timeout_mask              ),
        .O_AOU_INTERRUPT_MASK_INT_EARLY_RESP_MASK                       ( w_early_resp_mask                     ),
        .O_AOU_INTERRUPT_MASK_INT_EARLY_WDT_MASK                        ( w_early_wdt_mask                      ),
        .O_AOU_INTERRUPT_MASK_INT_FDI_LINK_DOWN_MASK                    ( w_fdi_link_down_mask                  ),
        .O_AOU_INTERRUPT_MASK_INT_MI0_ID_MISMATCH_MASK                  ( w_mi0_id_mismatch_mask                ),
        .O_AOU_INTERRUPT_MASK_INT_SI0_ID_MISMATCH_MASK                  ( w_si0_id_mismatch_mask                ),

        .O_RID_MISMATCH_ERROR                                           ( w_err_info_rid_mismatch_err           ),
        .O_SPLIT_BID_MISMATCH_ERROR                                     ( w_err_info_split_bid_mismatch_err     ),

        .O_ACT_ACK_ERR                                                  ( w_act_ack_err                         ),
        .O_DEACT_ACK_ERR                                                ( w_deact_ack_err                       ),
        .O_INVALID_ACTMSG_ERR                                           ( w_invalid_actmsg_err                  ),
        .O_MSGCREDIT_ERR                                                ( w_msgcredit_err                       ),

        .O_AXI_SLV_RID_MISMATCH_ERROR                                   ( w_axi_slv_rid_mismatch_error          ),
        .O_AXI_SLV_BID_MISMATCH_ERROR                                   ( w_axi_slv_bid_mismatch_error          ),

        .ERR_EARLY_RESP_ERR                                             ( w_int_early_resp_err                  ),
        .ERR_EARLY_WDT_ERR                                              ( w_int_early_wdt_err                   ),

        .INT_ACTIVATE_START                                             ( O_INT_ACTIVATE_START                  ),
        .INT_DEACTIVATE_START                                           ( O_INT_DEACTIVATE_START                ),
        .INT_FDI_LINK_DOWN                                              ( w_int_fdi_link_down                   ),

        .O_AXI_SPLIT_TR_RP1_MAX_AWBURSTLEN                              ( w_axi_split_tr_max_awburstlen[1]      ),
        .O_AXI_SPLIT_TR_RP1_MAX_ARBURSTLEN                              ( w_axi_split_tr_max_arburstlen[1]      ),
        .O_AXI_SPLIT_TR_RP2_MAX_AWBURSTLEN                              ( w_axi_split_tr_max_awburstlen[2]      ),
        .O_AXI_SPLIT_TR_RP2_MAX_ARBURSTLEN                              ( w_axi_split_tr_max_arburstlen[2]      ),
        .O_AXI_SPLIT_TR_RP3_MAX_AWBURSTLEN                              ( w_axi_split_tr_max_awburstlen[3]      ),
        .O_AXI_SPLIT_TR_RP3_MAX_ARBURSTLEN                              ( w_axi_split_tr_max_arburstlen[3]      ),
        .I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_INFO                       ( w_err_info_split_bid_mismatch[1]      ),
        .I_ERROR_INFO_RP1_RID_MISMATCH_INFO                             ( w_err_info_rid_mismatch[1]            ),
        .I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_ERR_SET                    ( w_err_split_bid_mismatch_set[1]       ),
        .I_ERROR_INFO_RP1_RID_MISMATCH_ERR_SET                          ( w_err_rid_mismatch_set[1]             ),
        .I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_INFO                       ( w_err_info_split_bid_mismatch[2]      ),
        .I_ERROR_INFO_RP2_RID_MISMATCH_INFO                             ( w_err_info_rid_mismatch[2]            ),
        .I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_ERR_SET                    ( w_err_split_bid_mismatch_set[2]       ),
        .I_ERROR_INFO_RP2_RID_MISMATCH_ERR_SET                          ( w_err_rid_mismatch_set[2]             ),
        .I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_INFO                       ( w_err_info_split_bid_mismatch[3]      ),
        .I_ERROR_INFO_RP3_RID_MISMATCH_INFO                             ( w_err_info_rid_mismatch[3]            ),
        .I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_ERR_SET                    ( w_err_split_bid_mismatch_set[3]       ),
        .I_ERROR_INFO_RP3_RID_MISMATCH_ERR_SET                          ( w_err_rid_mismatch_set[3]             ),
        .I_WRITE_EARLY_RESPONSE_RP1_WDT_TRANS_TIMEOUT_ERR               ( w_early_bresp_wdt_timeout_err[1]      ),
        .I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_DONE                     ( w_early_bresp_done[1]                 ),
        .I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_SET                  ( w_bresp_err[1]                        ),
        .I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_TYPE_INFO            ( w_bresp_err_type[1]                   ),
        .I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_ID_INFO              ( w_bresp_err_id[1]                     ),
        .O_WRITE_EARLY_RESPONSE_RP1_EARLY_BRESP_EN                      ( w_early_bresp_en[1]                   ),
        .O_WRITE_EARLY_RESPONSE_RP1_EARLY_ALWAYS_EN                     ( w_early_bresp_always_en[1]            ),
        .O_WRITE_EARLY_RESPONSE_RP1_WDT_EN                              ( w_early_bresp_wdt_en[1]               ),
        .I_WRITE_EARLY_RESPONSE_RP2_WDT_TRANS_TIMEOUT_ERR               ( w_early_bresp_wdt_timeout_err[2]      ),
        .I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_DONE                     ( w_early_bresp_done[2]                 ),
        .I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_SET                  ( w_bresp_err[2]                        ),
        .I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_TYPE_INFO            ( w_bresp_err_type[2]                   ),
        .I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_ID_INFO              ( w_bresp_err_id[2]                     ),
        .O_WRITE_EARLY_RESPONSE_RP2_EARLY_BRESP_EN                      ( w_early_bresp_en[2]                   ),
        .O_WRITE_EARLY_RESPONSE_RP2_EARLY_ALWAYS_EN                     ( w_early_bresp_always_en[2]            ),
        .O_WRITE_EARLY_RESPONSE_RP2_WDT_EN                              ( w_early_bresp_wdt_en[2]               ),
        .I_WRITE_EARLY_RESPONSE_RP3_WDT_TRANS_TIMEOUT_ERR               ( w_early_bresp_wdt_timeout_err[3]      ),
        .I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_DONE                     ( w_early_bresp_done[3]                 ),
        .I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_SET                  ( w_bresp_err[3]                        ),
        .I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_TYPE_INFO            ( w_bresp_err_type[3]                   ),
        .I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_ID_INFO              ( w_bresp_err_id[3]                     ),
        .O_WRITE_EARLY_RESPONSE_RP3_EARLY_BRESP_EN                      ( w_early_bresp_en[3]                   ),
        .O_WRITE_EARLY_RESPONSE_RP3_EARLY_ALWAYS_EN                     ( w_early_bresp_always_en[3]            ),
        .O_WRITE_EARLY_RESPONSE_RP3_WDT_EN                              ( w_early_bresp_wdt_en[3]               ),

        .O_AXI_ERROR_INFO0_RP1_DEBUG_UPPER_ADDR                         ( w_debug_error_info_upper_addr[1]      ),
        .O_AXI_ERROR_INFO1_RP1_DEBUG_LOWER_ADDR                         ( w_debug_error_info_lower_addr[1]      ),
        .O_AOU_CON0_RP1_ERROR_INFO_ACCESS_EN                            ( w_debug_error_info_access_enable[1]   ),
        .O_AXI_ERROR_INFO0_RP2_DEBUG_UPPER_ADDR                         ( w_debug_error_info_upper_addr[2]      ),
        .O_AXI_ERROR_INFO1_RP2_DEBUG_LOWER_ADDR                         ( w_debug_error_info_lower_addr[2]      ),
        .O_AOU_CON0_RP2_ERROR_INFO_ACCESS_EN                            ( w_debug_error_info_access_enable[2]   ),
        .O_AXI_ERROR_INFO0_RP3_DEBUG_UPPER_ADDR                         ( w_debug_error_info_upper_addr[3]      ),
        .O_AXI_ERROR_INFO1_RP3_DEBUG_LOWER_ADDR                         ( w_debug_error_info_lower_addr[3]      ),
        .O_AOU_CON0_RP3_ERROR_INFO_ACCESS_EN                            ( w_debug_error_info_access_enable[3]   ),
        .O_AOU_CON0_RP1_AXI_AGGREGATOR_EN                               ( w_axi_aggregator_en[1]                ),
        .O_AOU_CON0_RP2_AXI_AGGREGATOR_EN                               ( w_axi_aggregator_en[2]                ),
        .O_AOU_CON0_RP3_AXI_AGGREGATOR_EN                               ( w_axi_aggregator_en[3]                ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_INFO        ( w_axi_slv_bid_mismatch_info[1]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_INFO        ( w_axi_slv_rid_mismatch_info[1]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_ERR_SET     ( w_axi_slv_bid_mismatch_err_set[1]     ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_ERR_SET     ( w_axi_slv_rid_mismatch_err_set[1]     ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_INFO        ( w_axi_slv_bid_mismatch_info[2]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_INFO        ( w_axi_slv_rid_mismatch_info[2]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_ERR_SET     ( w_axi_slv_bid_mismatch_err_set[2]     ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_ERR_SET     ( w_axi_slv_rid_mismatch_err_set[2]     ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_INFO        ( w_axi_slv_bid_mismatch_info[3]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_INFO        ( w_axi_slv_rid_mismatch_info[3]        ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_ERR_SET     ( w_axi_slv_bid_mismatch_err_set[3]     ),
        .I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_ERR_SET     ( w_axi_slv_rid_mismatch_err_set[3]     ),
        .O_DEST_RP_RP3_DEST                                             ( w_rp_dest_rp[3]                       ),
        .O_DEST_RP_RP2_DEST                                             ( w_rp_dest_rp[2]                       ),
        .O_DEST_RP_RP1_DEST                                             ( w_rp_dest_rp[1]                       ),
        .O_DEST_RP_RP0_DEST                                             ( w_rp_dest_rp[0]                       ),
        .O_PRIOR_RP_AXI_AXI_QOS_TO_NP                                   ( w_prior_rp_axi_axi_qos_to_np          ),
        .O_PRIOR_RP_AXI_AXI_QOS_TO_HP                                   ( w_prior_rp_axi_axi_qos_to_hp          ),
        .O_PRIOR_RP_AXI_RP3_PRIOR                                       ( w_prior_rp_axi_rp3_prior              ),
        .O_PRIOR_RP_AXI_RP2_PRIOR                                       ( w_prior_rp_axi_rp2_prior              ),
        .O_PRIOR_RP_AXI_RP1_PRIOR                                       ( w_prior_rp_axi_rp1_prior              ),
        .O_PRIOR_RP_AXI_RP0_PRIOR                                       ( w_prior_rp_axi_rp0_prior              ),
        .O_PRIOR_RP_AXI_ARB_MODE                                        ( w_prior_rp_axi_arb_mode               ),
        .O_PRIOR_TIMER_TIMER_RESOLUTION                                 ( w_prior_timer_timer_resolution        ),
        .O_PRIOR_TIMER_TIMER_THRESHOLD                                  ( w_prior_timer_timer_threshold         ),

        .O_AXI_SLV_ID_MISMATCH_RP0_EN                                   ( w_axi_slv_id_mismatch_en[0]           ),
        .O_AXI_SLV_ID_MISMATCH_RP1_EN                                   ( w_axi_slv_id_mismatch_en[1]           ),
        .O_AXI_SLV_ID_MISMATCH_RP2_EN                                   ( w_axi_slv_id_mismatch_en[2]           ),
        .O_AXI_SLV_ID_MISMATCH_RP3_EN                                   ( w_axi_slv_id_mismatch_en[3]           ),

        .O_RP0_TX_RP_SEL                                                ( w_rp0_tx_rp_sel                       ), 
        .O_RP1_TX_RP_SEL                                                ( w_rp1_tx_rp_sel                       ), 
        .O_RP2_TX_RP_SEL                                                ( w_rp2_tx_rp_sel                       ), 
        .O_RP3_TX_RP_SEL                                                ( w_rp3_tx_rp_sel                       ), 
        .O_ASYMMETRIC_RP_EN                                             ( w_asymmetric_rp_sel                   ) 
    );

    assign O_ERR_INFO_RID_MISMATCH_ERR          = w_mi0_id_mismatch_mask ? 1'b0 : w_err_info_rid_mismatch_err;
    assign O_ERR_INFO_SPLIT_BID_MISMATCH_ERR    = w_mi0_id_mismatch_mask ? 1'b0 : w_err_info_split_bid_mismatch_err;
    assign O_AXI_SLV_RID_MISMATCH_ERROR         = w_si0_id_mismatch_mask ? 1'b0 : w_axi_slv_rid_mismatch_error;
    assign O_AXI_SLV_BID_MISMATCH_ERROR         = w_si0_id_mismatch_mask ? 1'b0 : w_axi_slv_bid_mismatch_error;
    assign O_INT_EARLY_RESP_ERR                 = w_early_resp_mask ? 1'b0 : w_int_early_resp_err;
    assign O_INT_EARLY_WDT_ERR                  = w_early_wdt_mask ? 1'b0 : w_int_early_wdt_err;
    assign O_INT_FDI_LINK_DOWN                  = w_fdi_link_down_mask ? 1'b0 : w_int_fdi_link_down;

    assign w_act_ack_err_b          = w_act_timeout_mask ? 1'b0 : w_act_ack_err;
    assign w_deact_ack_err_b        = w_deact_timeout_mask ? 1'b0 : w_deact_ack_err;
    assign w_invalid_actmsg_err_b   = w_invalid_actmsg_mask ? 1'b0 : w_invalid_actmsg_err;
    assign w_msgcredit_err_b        = w_msgcredit_timeout_mask ? 1'b0 : w_msgcredit_err;

    assign O_AOU_REQ_LINKRESET = w_act_ack_err_b || w_deact_ack_err_b || w_invalid_actmsg_err_b || w_msgcredit_err_b;

//----------------------------------------------------------------------------
    AOU_CRD_CTRL #(
        .RP_COUNT               ( RP_COUNT              ),

        .RP0_RX_AW_MAX_CREDIT   ( RP0_RX_AW_MAX_CREDIT  ),
        .RP0_RX_AR_MAX_CREDIT   ( RP0_RX_AR_MAX_CREDIT  ),
        .RP0_RX_W_MAX_CREDIT    ( RP0_RX_W_MAX_CREDIT   ),
        .RP0_RX_R_MAX_CREDIT    ( RP0_RX_R_MAX_CREDIT   ),
        .RP0_RX_B_MAX_CREDIT    ( RP0_RX_B_MAX_CREDIT   ),

        .RP1_RX_AW_MAX_CREDIT   ( RP1_RX_AW_MAX_CREDIT  ),
        .RP1_RX_AR_MAX_CREDIT   ( RP1_RX_AR_MAX_CREDIT  ),
        .RP1_RX_W_MAX_CREDIT    ( RP1_RX_W_MAX_CREDIT   ),
        .RP1_RX_R_MAX_CREDIT    ( RP1_RX_R_MAX_CREDIT   ),
        .RP1_RX_B_MAX_CREDIT    ( RP1_RX_B_MAX_CREDIT   ),

        .RP2_RX_AW_MAX_CREDIT   ( RP2_RX_AW_MAX_CREDIT  ),
        .RP2_RX_AR_MAX_CREDIT   ( RP2_RX_AR_MAX_CREDIT  ),
        .RP2_RX_W_MAX_CREDIT    ( RP2_RX_W_MAX_CREDIT   ),
        .RP2_RX_R_MAX_CREDIT    ( RP2_RX_R_MAX_CREDIT   ),
        .RP2_RX_B_MAX_CREDIT    ( RP2_RX_B_MAX_CREDIT   ),

        .RP3_RX_AW_MAX_CREDIT   ( RP3_RX_AW_MAX_CREDIT  ),
        .RP3_RX_AR_MAX_CREDIT   ( RP3_RX_AR_MAX_CREDIT  ),
        .RP3_RX_W_MAX_CREDIT    ( RP3_RX_W_MAX_CREDIT   ),
        .RP3_RX_R_MAX_CREDIT    ( RP3_RX_R_MAX_CREDIT   ),
        .RP3_RX_B_MAX_CREDIT    ( RP3_RX_B_MAX_CREDIT   ),

        .RP0_TX_AW_MAX_CREDIT   ( RP0_TX_AW_MAX_CREDIT  ),
        .RP0_TX_AR_MAX_CREDIT   ( RP0_TX_AR_MAX_CREDIT  ),
        .RP0_TX_W_MAX_CREDIT    ( RP0_TX_W_MAX_CREDIT   ),
        .RP0_TX_R_MAX_CREDIT    ( RP0_TX_R_MAX_CREDIT   ),
        .RP0_TX_B_MAX_CREDIT    ( RP0_TX_B_MAX_CREDIT   ),

        .RP1_TX_AW_MAX_CREDIT   ( RP1_TX_AW_MAX_CREDIT  ),
        .RP1_TX_AR_MAX_CREDIT   ( RP1_TX_AR_MAX_CREDIT  ),
        .RP1_TX_W_MAX_CREDIT    ( RP1_TX_W_MAX_CREDIT   ),
        .RP1_TX_R_MAX_CREDIT    ( RP1_TX_R_MAX_CREDIT   ),
        .RP1_TX_B_MAX_CREDIT    ( RP1_TX_B_MAX_CREDIT   ),

        .RP2_TX_AW_MAX_CREDIT   ( RP2_TX_AW_MAX_CREDIT  ),
        .RP2_TX_AR_MAX_CREDIT   ( RP2_TX_AR_MAX_CREDIT  ),
        .RP2_TX_W_MAX_CREDIT    ( RP2_TX_W_MAX_CREDIT   ),
        .RP2_TX_R_MAX_CREDIT    ( RP2_TX_R_MAX_CREDIT   ),
        .RP2_TX_B_MAX_CREDIT    ( RP2_TX_B_MAX_CREDIT   ),

        .RP3_TX_AW_MAX_CREDIT   ( RP3_TX_AW_MAX_CREDIT  ),
        .RP3_TX_AR_MAX_CREDIT   ( RP3_TX_AR_MAX_CREDIT  ),
        .RP3_TX_W_MAX_CREDIT    ( RP3_TX_W_MAX_CREDIT   ),
        .RP3_TX_R_MAX_CREDIT    ( RP3_TX_R_MAX_CREDIT   ),
        .RP3_TX_B_MAX_CREDIT    ( RP3_TX_B_MAX_CREDIT   ),

        .RP0_AXI_DATA_WD        ( RP0_AXI_DATA_WD       ),
        .RP1_AXI_DATA_WD        ( RP1_AXI_DATA_WD       ),
        .RP2_AXI_DATA_WD        ( RP2_AXI_DATA_WD       ),
        .RP3_AXI_DATA_WD        ( RP3_AXI_DATA_WD       ),

        .DEC_MULTI              ( DEC_MULTI             )

    ) u_aou_crd_ctrl
    (
        .I_CLK                          ( I_CLK                         ),
        .I_RESETN                       ( I_RESETN                      ),

        .O_AOU_MSGCREDIT_WREQCRED       ( w_txcore_msgcredit_wreqcred   ),
        .O_AOU_MSGCREDIT_RREQCRED       ( w_txcore_msgcredit_rreqcred   ),
        .O_AOU_MSGCREDIT_WDATACRED      ( w_txcore_msgcredit_wdatacred  ),
        .O_AOU_MSGCREDIT_RDATACRED      ( w_txcore_msgcredit_rdatacred  ),
        .O_AOU_MSGCREDIT_WRESPCRED      ( w_txcore_msgcredit_wrespcred  ),
        .O_AOU_MSGCREDIT_RP             ( w_txcore_msgcredit_rp         ),
        .O_AOU_MSGCREDIT_CRED_VALID     ( w_txcore_msgcredit_cred_valid ),
        .I_AOU_MSGCREDIT_CRED_READY     ( w_txcore_msgcredit_cred_ready ),

        .O_AOU_CRDTGRANT_WRESPCRED3     ( w_txcore_crdtgrant_wrespcred3 ),
        .O_AOU_CRDTGRANT_WRESPCRED2     ( w_txcore_crdtgrant_wrespcred2 ),
        .O_AOU_CRDTGRANT_WRESPCRED1     ( w_txcore_crdtgrant_wrespcred1 ),
        .O_AOU_CRDTGRANT_WRESPCRED0     ( w_txcore_crdtgrant_wrespcred0 ),
        .O_AOU_CRDTGRANT_RDATACRED3     ( w_txcore_crdtgrant_rdatacred3 ),
        .O_AOU_CRDTGRANT_RDATACRED2     ( w_txcore_crdtgrant_rdatacred2 ),
        .O_AOU_CRDTGRANT_RDATACRED1     ( w_txcore_crdtgrant_rdatacred1 ),
        .O_AOU_CRDTGRANT_RDATACRED0     ( w_txcore_crdtgrant_rdatacred0 ),
        .O_AOU_CRDTGRANT_WDATACRED3     ( w_txcore_crdtgrant_wdatacred3 ),
        .O_AOU_CRDTGRANT_WDATACRED2     ( w_txcore_crdtgrant_wdatacred2 ),
        .O_AOU_CRDTGRANT_WDATACRED1     ( w_txcore_crdtgrant_wdatacred1 ),
        .O_AOU_CRDTGRANT_WDATACRED0     ( w_txcore_crdtgrant_wdatacred0 ),
        .O_AOU_CRDTGRANT_RREQCRED3      ( w_txcore_crdtgrant_rreqcred3  ),
        .O_AOU_CRDTGRANT_RREQCRED2      ( w_txcore_crdtgrant_rreqcred2  ),
        .O_AOU_CRDTGRANT_RREQCRED1      ( w_txcore_crdtgrant_rreqcred1  ),
        .O_AOU_CRDTGRANT_RREQCRED0      ( w_txcore_crdtgrant_rreqcred0  ),
        .O_AOU_CRDTGRANT_WREQCRED3      ( w_txcore_crdtgrant_wreqcred3  ),
        .O_AOU_CRDTGRANT_WREQCRED2      ( w_txcore_crdtgrant_wreqcred2  ),
        .O_AOU_CRDTGRANT_WREQCRED1      ( w_txcore_crdtgrant_wreqcred1  ),
        .O_AOU_CRDTGRANT_WREQCRED0      ( w_txcore_crdtgrant_wreqcred0  ),
        .O_AOU_CRDTGRANT_VALID          ( w_txcore_crdtgrant_valid      ),
        .I_AOU_CRDTGRANT_READY          ( w_txcore_crdtgrant_ready      ),

        .I_AOU_RX_WREQVALID             ( I_AOU_RX_WLAST_GEN_AWVALID & O_AOU_RX_WLAST_GEN_AWREADY & {RP_COUNT{(O_AOU_ACTIVATE_ST_ENABLED | w_status_deactivate)}}),
        .I_AOU_RX_RREQVALID             ( O_AOU_RX_AXI_MM_ARREADY & I_AOU_RX_AXI_MM_ARVALID & {RP_COUNT{(O_AOU_ACTIVATE_ST_ENABLED | w_status_deactivate)}}),
        .I_AOU_RX_WDATAVALID            ( I_AOU_RX_WLAST_GEN_WVALID & O_AOU_RX_WLAST_GEN_WREADY & {RP_COUNT{(O_AOU_ACTIVATE_ST_ENABLED | w_status_deactivate)}}),
        .I_AOU_RX_WDATA_DLENGTH         ( I_AOU_RX_WLAST_GEN_WDLENGTH   ),
        .I_AOU_RX_WDATAF                ( I_AOU_RX_WLAST_GEN_WDATAF     ),
        .I_AOU_RX_RDATAVALID            ( O_AOU_RX_FIFO_RREADY & I_AOU_RX_AXI_S_RVALID           ),
        .I_AOU_RX_RDATA_DLENGTH         ( I_AOU_RX_AXI_S_RDLENGTH       ),
        .I_AOU_RX_WRESPVALID            ( I_EARLY_BRESP_CTRL_BVALID & O_EARLY_BRESP_CTRL_BREADY   ),

        .O_AOU_TX_WREQCRED              ( w_aou_tx_wreqcred             ),
        .O_AOU_TX_RREQCRED              ( w_aou_tx_rreqcred             ),
        .O_AOU_TX_WDATACRED             ( w_aou_tx_wdatacred            ),
        .O_AOU_TX_RDATACRED             ( w_aou_tx_rdatacred            ),
        .O_AOU_TX_WRESPCRED             ( w_aou_tx_wrespcred            ),

        .I_AOU_TX_WREQVALID             ( w_aou_tx_wreqvalid            ),
        .I_AOU_TX_RREQVALID             ( w_aou_tx_rreqvalid            ),
        .I_AOU_TX_WDATAVALID            ( w_aou_tx_wdatavalid           ),
        .I_AOU_TX_WFDATA                ( w_aou_tx_wfdata               ),
        .I_AOU_TX_WDATA_DLENGTH         ( w_aou_tx_wdata_dlength        ),
        .I_AOU_TX_RDATAVALID            ( w_aou_tx_rdatavalid           ),
        .I_AOU_TX_RDATA_DLENGTH         ( w_aou_tx_rdata_dlength        ),
        .I_AOU_TX_WRESPVALID            ( w_aou_tx_wrespvalid           ),

        .I_AOU_CRDTGRANT_WRESPCRED3     ( w_rxcore_crdtgrant_wrespcred3 ),
        .I_AOU_CRDTGRANT_WRESPCRED2     ( w_rxcore_crdtgrant_wrespcred2 ),
        .I_AOU_CRDTGRANT_WRESPCRED1     ( w_rxcore_crdtgrant_wrespcred1 ),
        .I_AOU_CRDTGRANT_WRESPCRED0     ( w_rxcore_crdtgrant_wrespcred0 ),
        .I_AOU_CRDTGRANT_RDATACRED3     ( w_rxcore_crdtgrant_rdatacred3 ),
        .I_AOU_CRDTGRANT_RDATACRED2     ( w_rxcore_crdtgrant_rdatacred2 ),
        .I_AOU_CRDTGRANT_RDATACRED1     ( w_rxcore_crdtgrant_rdatacred1 ),
        .I_AOU_CRDTGRANT_RDATACRED0     ( w_rxcore_crdtgrant_rdatacred0 ),
        .I_AOU_CRDTGRANT_WDATACRED3     ( w_rxcore_crdtgrant_wdatacred3 ),
        .I_AOU_CRDTGRANT_WDATACRED2     ( w_rxcore_crdtgrant_wdatacred2 ),
        .I_AOU_CRDTGRANT_WDATACRED1     ( w_rxcore_crdtgrant_wdatacred1 ),
        .I_AOU_CRDTGRANT_WDATACRED0     ( w_rxcore_crdtgrant_wdatacred0 ),
        .I_AOU_CRDTGRANT_RREQCRED3      ( w_rxcore_crdtgrant_rreqcred3  ),
        .I_AOU_CRDTGRANT_RREQCRED2      ( w_rxcore_crdtgrant_rreqcred2  ),
        .I_AOU_CRDTGRANT_RREQCRED1      ( w_rxcore_crdtgrant_rreqcred1  ),
        .I_AOU_CRDTGRANT_RREQCRED0      ( w_rxcore_crdtgrant_rreqcred0  ),
        .I_AOU_CRDTGRANT_WREQCRED3      ( w_rxcore_crdtgrant_wreqcred3  ),
        .I_AOU_CRDTGRANT_WREQCRED2      ( w_rxcore_crdtgrant_wreqcred2  ),
        .I_AOU_CRDTGRANT_WREQCRED1      ( w_rxcore_crdtgrant_wreqcred1  ),
        .I_AOU_CRDTGRANT_WREQCRED0      ( w_rxcore_crdtgrant_wreqcred0  ),
        .I_AOU_CRDTGRANT_VALID          ( w_rxcore_crdtgrant_valid      ),

        .I_AOU_MSGCRDT_WRESPCRED        ( w_rxcore_msgcrdt_wrespcred    ),
        .I_AOU_MSGCRDT_RDATACRED        ( w_rxcore_msgcrdt_rdatacred    ),
        .I_AOU_MSGCRDT_WDATACRED        ( w_rxcore_msgcrdt_wdatacred    ),
        .I_AOU_MSGCRDT_RREQCRED         ( w_rxcore_msgcrdt_rreqcred     ),
        .I_AOU_MSGCRDT_WREQCRED         ( w_rxcore_msgcrdt_wreqcred     ),
        .I_AOU_MSGCRDT_RP               ( w_rxcore_msgcrdt_rp           ),
        .I_AOU_MSGCRDT_VALID            ( w_rxcore_msgcrdt_valid        ),

        .I_CRD_COUNT_EN                 ( w_crd_count_en                ),

        .I_REQ_CRD_ADVERTISE_EN         ( w_req_crd_advertise_en        ),
        .I_TX_REQ_CREDITED_MESSAGE_EN   ( w_tx_req_credited_message_en  ),
        .I_RSP_CRD_ADVERTISE_EN         ( w_rsp_crd_advertise_en        ),
        .I_TX_RSP_CREDITED_MESSAGE_EN   ( w_tx_rsp_credited_message_en  ),

        .I_STATUS_DISABLE               ( w_status_disabled             ),

        .I_RP_DEST_RP                   ( w_rp_dest_rp                  ),

        .I_CREDIT_BLOCK                 ( w_err_info_rid_mismatch_err | w_err_info_split_bid_mismatch_err | (|w_err_split_bid_mismatch_set) | (|w_err_rid_mismatch_set)),
        .O_TX_REQ_CREDIT_BLOCKn         ( w_tx_req_credit_blockn        ),
        .O_TX_RSP_CREDIT_BLOCKn         ( w_tx_rsp_credit_blockn        )

    );
    AOU_ASYMMETRIC_RP_PROC #(
    
        .RP_COUNT                   ( RP_COUNT                  ), 
        .AXI_ADDR_WD                ( AXI_ADDR_WD               ), 
        .AXI_ID_WD                  ( AXI_ID_WD                 ), 
        .AXI_LEN_WD                 ( AXI_LEN_WD                ), 
        .RP_AXI_DATA_WD_MAX         ( RP_AXI_DATA_WD_MAX        ),
        .AXI_PEER_DIE_MAX_DATA_WD   ( AXI_PEER_DIE_MAX_DATA_WD  ),

        .RP0_S_RD_MO_CNT            ( RP0_S_RD_MO_CNT           ), 
        .RP0_S_WR_MO_CNT            ( RP0_S_WR_MO_CNT           ), 
    
        .RP1_S_RD_MO_CNT            ( RP1_S_RD_MO_CNT           ), 
        .RP1_S_WR_MO_CNT            ( RP1_S_WR_MO_CNT           ), 
    
        .RP2_S_RD_MO_CNT            ( RP2_S_RD_MO_CNT           ), 
        .RP2_S_WR_MO_CNT            ( RP2_S_WR_MO_CNT           ), 
    
        .RP3_S_RD_MO_CNT            ( RP3_S_RD_MO_CNT           ), 
        .RP3_S_WR_MO_CNT            ( RP3_S_WR_MO_CNT           ) 
    
    
    ) u_aou_asymmetric_rp_proc
    (
        .I_CLK                          ( I_CLK                             ),
        .I_RESETN                       ( I_RESETN                          ),
                            
                            
        .I_AOU_AXI_S_ARID               ( I_AOU_TX_AXI_S_ARID               ),
        .I_AOU_AXI_S_ARADDR             ( I_AOU_TX_AXI_S_ARADDR             ),
        .I_AOU_AXI_S_ARLEN              ( I_AOU_TX_AXI_S_ARLEN              ),
        .I_AOU_AXI_S_ARSIZE             ( I_AOU_TX_AXI_S_ARSIZE             ),
        .I_AOU_AXI_S_ARBURST            ( I_AOU_TX_AXI_S_ARBURST            ),
        .I_AOU_AXI_S_ARLOCK             ( I_AOU_TX_AXI_S_ARLOCK             ),
        .I_AOU_AXI_S_ARCACHE            ( I_AOU_TX_AXI_S_ARCACHE            ),
        .I_AOU_AXI_S_ARPROT             ( I_AOU_TX_AXI_S_ARPROT             ),
        .I_AOU_AXI_S_ARQOS              ( I_AOU_TX_AXI_S_ARQOS              ),
        .I_AOU_AXI_S_ARVALID            ( w_aou_tx_axi_s_arvalid_tmp        ),
        .O_AOU_AXI_S_ARREADY            ( w_aou_tx_axi_s_arready_tmp        ),
                            
        .O_AOU_AXI_S_RID                ( O_AOU_RX_AXI_S_RID                ),
        .O_AOU_AXI_S_RDATA              ( O_AOU_RX_AXI_S_RDATA              ),
        .O_AOU_AXI_S_RRESP              ( O_AOU_RX_AXI_S_RRESP              ),
        .O_AOU_AXI_S_RLAST              ( O_AOU_RX_AXI_S_RLAST              ),
        .O_AOU_AXI_S_RVALID             ( w_aou_rx_axi_s_rvalid             ),
        .I_AOU_AXI_S_RREADY             ( I_AOU_RX_AXI_S_RREADY             ),
                            
        .I_AOU_AXI_S_AWID               ( w_early_bresp_ctrl_awid           ),
        .I_AOU_AXI_S_AWADDR             ( w_early_bresp_ctrl_awaddr         ),
        .I_AOU_AXI_S_AWLEN              ( w_early_bresp_ctrl_awlen          ),
        .I_AOU_AXI_S_AWSIZE             ( w_early_bresp_ctrl_awsize         ),
        .I_AOU_AXI_S_AWBURST            ( w_early_bresp_ctrl_awburst        ),
        .I_AOU_AXI_S_AWLOCK             ( w_early_bresp_ctrl_awlock         ),
        .I_AOU_AXI_S_AWCACHE            ( w_early_bresp_ctrl_awcache        ),
        .I_AOU_AXI_S_AWPROT             ( w_early_bresp_ctrl_awprot         ),
        .I_AOU_AXI_S_AWQOS              ( w_early_bresp_ctrl_awqos          ),
        .I_AOU_AXI_S_AWVALID            ( w_early_bresp_ctrl_awvalid        ),
        .O_AOU_AXI_S_AWREADY            ( w_early_bresp_ctrl_awready        ),
                                               
        .I_AOU_AXI_S_WDATA              ( w_early_bresp_ctrl_wdata          ),
        .I_AOU_AXI_S_WSTRB              ( w_early_bresp_ctrl_wstrb          ),
        .I_AOU_AXI_S_WLAST              ( w_early_bresp_ctrl_wlast          ),
        .I_AOU_AXI_S_WDLEN              ( w_early_bresp_ctrl_wdlen          ),
        .I_AOU_AXI_S_WVALID             ( w_early_bresp_ctrl_wvalid         ),
        .O_AOU_AXI_S_WREADY             ( w_early_bresp_ctrl_wready         ),
                            
        .O_AOU_AXI_S_BID                ( w_early_bresp_ctrl_bid            ),
        .O_AOU_AXI_S_BRESP              ( w_early_bresp_ctrl_bresp          ),
        .O_AOU_AXI_S_BVALID             ( w_early_bresp_ctrl_bvalid         ),
        .I_AOU_AXI_S_BREADY             ( w_early_bresp_ctrl_bready         ),                    
                            
        .O_AOU_AXI_M_ARID               ( w_aou_tx_axi_s_arid               ),
        .O_AOU_AXI_M_ARADDR             ( w_aou_tx_axi_s_araddr             ),
        .O_AOU_AXI_M_ARLEN              ( w_aou_tx_axi_s_arlen              ),
        .O_AOU_AXI_M_ARSIZE             ( w_aou_tx_axi_s_arsize             ),
        .O_AOU_AXI_M_ARBURST            ( w_aou_tx_axi_s_arburst            ),
        .O_AOU_AXI_M_ARLOCK             ( w_aou_tx_axi_s_arlock             ),
        .O_AOU_AXI_M_ARCACHE            ( w_aou_tx_axi_s_arcache            ),
        .O_AOU_AXI_M_ARPROT             ( w_aou_tx_axi_s_arprot             ),
        .O_AOU_AXI_M_ARQOS              ( w_aou_tx_axi_s_arqos              ),
        .O_AOU_AXI_M_ARVALID            ( w_aou_tx_axi_s_arvalid            ),
        .I_AOU_AXI_M_ARREADY            ( w_aou_tx_axi_s_arready            ),
                            
        .I_AOU_AXI_M_RID                ( I_AOU_RX_AXI_S_RID                ),
        .I_AOU_AXI_M_RDATA              ( I_AOU_RX_AXI_S_RDATA              ),
        .I_AOU_AXI_M_RRESP              ( I_AOU_RX_AXI_S_RRESP              ),
        .I_AOU_AXI_M_RLAST              ( I_AOU_RX_AXI_S_RLAST              ),
        .I_AOU_AXI_M_RVALID             ( I_AOU_RX_AXI_S_RVALID             ),
        .O_AOU_AXI_M_RREADY             ( O_AOU_RX_FIFO_RREADY              ),
                            
        .O_AOU_AXI_M_AWID               ( w_tmp_early_bresp_ctrl_awid       ),
        .O_AOU_AXI_M_AWADDR             ( w_tmp_early_bresp_ctrl_awaddr     ),
        .O_AOU_AXI_M_AWLEN              ( w_tmp_early_bresp_ctrl_awlen      ),
        .O_AOU_AXI_M_AWSIZE             ( w_tmp_early_bresp_ctrl_awsize     ),
        .O_AOU_AXI_M_AWBURST            ( w_tmp_early_bresp_ctrl_awburst    ),
        .O_AOU_AXI_M_AWLOCK             ( w_tmp_early_bresp_ctrl_awlock     ),
        .O_AOU_AXI_M_AWCACHE            ( w_tmp_early_bresp_ctrl_awcache    ),
        .O_AOU_AXI_M_AWPROT             ( w_tmp_early_bresp_ctrl_awprot     ),
        .O_AOU_AXI_M_AWQOS              ( w_tmp_early_bresp_ctrl_awqos      ),
        .O_AOU_AXI_M_AWVALID            ( w_tmp_early_bresp_ctrl_awvalid    ),
        .I_AOU_AXI_M_AWREADY            ( w_tmp_early_bresp_ctrl_awready    ),
                                               
        .O_AOU_AXI_M_WDATA              ( w_tmp_early_bresp_ctrl_wdata      ),
        .O_AOU_AXI_M_WSTRB              ( w_tmp_early_bresp_ctrl_wstrb      ),
        .O_AOU_AXI_M_WLAST              ( w_tmp_early_bresp_ctrl_wlast      ),
        .O_AOU_AXI_M_WDLEN              ( w_tmp_early_bresp_ctrl_wdlen      ),
        .O_AOU_AXI_M_WVALID             ( w_tmp_early_bresp_ctrl_wvalid     ),
        .I_AOU_AXI_M_WREADY             ( w_tmp_early_bresp_ctrl_wready     ),
                            
        .I_AOU_AXI_M_BID                ( I_EARLY_BRESP_CTRL_BID            ),
        .I_AOU_AXI_M_BRESP              ( I_EARLY_BRESP_CTRL_BRESP          ),
        .I_AOU_AXI_M_BVALID             ( I_EARLY_BRESP_CTRL_BVALID         ),
        .O_AOU_AXI_M_BREADY             ( O_EARLY_BRESP_CTRL_BREADY         ),

        .I_PRIOR_RP_AXI_AXI_QOS_TO_NP   ( w_prior_rp_axi_axi_qos_to_np      ),
        .I_PRIOR_RP_AXI_AXI_QOS_TO_HP   ( w_prior_rp_axi_axi_qos_to_hp      ),
        .I_PRIOR_RP_AXI_RP3_PRIOR       ( w_prior_rp_axi_rp3_prior          ),
        .I_PRIOR_RP_AXI_RP2_PRIOR       ( w_prior_rp_axi_rp2_prior          ),
        .I_PRIOR_RP_AXI_RP1_PRIOR       ( w_prior_rp_axi_rp1_prior          ),
        .I_PRIOR_RP_AXI_RP0_PRIOR       ( w_prior_rp_axi_rp0_prior          ),
        .I_PRIOR_RP_AXI_ARB_MODE        ( w_prior_rp_axi_arb_mode           ),
        .I_PRIOR_TIMER_TIMER_RESOLUTION ( w_prior_timer_timer_resolution    ),
        .I_PRIOR_TIMER_TIMER_THRESHOLD  ( w_prior_timer_timer_threshold     ),
                            
        .I_TX_RP_SEL                    ({w_rp3_tx_rp_sel, w_rp2_tx_rp_sel, w_rp1_tx_rp_sel, w_rp0_tx_rp_sel}),
        .I_ASYMMETRIC_RP_EN             ( w_asymmetric_rp_sel               )
    
    );

//----------------------------------------------------------------------------
    logic   w_aou_rx_fifo_pending;

    assign w_aou_rx_fifo_pending = (|I_AOU_RX_WLAST_GEN_AWVALID) | (|I_AOU_RX_AXI_MM_ARVALID) | (|I_AOU_RX_WLAST_GEN_WVALID) | (|I_EARLY_BRESP_CTRL_BVALID) | (|I_AOU_RX_AXI_S_RVALID);

    AOU_ACTIVATION_CTRL u_aou_activation_ctrl
    (
        .I_CLK                             ( I_CLK                          ),
        .I_RESETN                          ( I_RESETN                       ),

        .I_UCIE_INIT_DONE                  ( I_INT_FSM_IN_ACTIVE            ),
        .I_ACTIVATE_START                  ( w_activate_start               ),

        .I_ACTMSG_ACTIVATION_OP            ( w_rxcore_activation_op         ),
        .I_ACTMSG_PROPERTYREQ              ( w_rxcore_activation_prop_req   ),
        .I_ACTMSG_VALID                    ( w_rxcore_activation_valid      ),

        .O_ACTMSG_ACTIVATION_OP            ( w_txcore_activation_op         ),
        .O_ACTMSG_PROPERTYREQ              ( w_txcore_activation_prop_req   ),
        .O_ACTMSG_VALID                    ( w_txcore_activation_valid      ),
        .I_ACTMSG_READY                    ( w_txcore_activation_ready      ),

        .I_DEACTIVATE_TIME_OUT_VALUE       ( w_deactivate_time_out_value    ),
        .I_DEACTIVATE_START                ( w_deactivate_start             ),
        .I_DEACTIVATE_FORCE                ( w_deactivate_force             ),
        .I_TX_PENDING                      ( w_tx_pending                   ),
        .I_TX_AXI_TR_PENDING               ( w_tx_axi_tr_pending            ),
        .I_SLV_BUS_CLEANY_COMPLETE         ( O_SLV_TR_COMPLETE              ),
        .I_AOU_RX_FIFO_PENDING             ( w_aou_rx_fifo_pending          ),

        .I_CRDTGRANT_VALID                 ( |w_rxcore_crdtgrant_valid      ),

        .I_ACK_TIME_OUT_VALUE              (  w_ack_time_out_value          ),
        .I_MSGCREDIT_TIME_OUT_VALUE        (  w_msgcredit_time_out_value    ),

        .O_ACT_ACK_ERR                     (  w_act_ack_err_set             ),
        .O_DEACT_ACK_ERR                   (  w_deact_ack_err_set           ),
        .O_INVALID_ACTMSG_INFO             (  w_invalid_actmsg_opcode       ),
        .O_INVALID_ACTMSG_ERR              (  w_invalid_actmsg_err_set      ),
        .O_MSGCREDIT_ERR                   (  w_msgcredit_err_set           ),

        .O_CRD_COUNT_EN                    ( w_crd_count_en                 ),

        .O_REQ_CRD_ADVERTISE_EN            ( w_req_crd_advertise_en         ),
        .O_TX_REQ_CREDITED_MESSAGE_EN      ( w_tx_req_credited_message_en   ),
        .O_RSP_CRD_ADVERTISE_EN            ( w_rsp_crd_advertise_en         ),
        .O_TX_RSP_CREDITED_MESSAGE_EN      ( w_tx_rsp_credited_message_en   ),


        .O_STATUS_DISABLED                 ( w_status_disabled              ),
        .O_STATUS_ENABLED                  ( O_AOU_ACTIVATE_ST_ENABLED      ),
        .O_STATUS_DEACTIVATE               ( w_status_deactivate            ),

        .O_INT_ACTIVATE_START              ( w_int_activate_start           ),
        .O_INT_DEACTIVATE_START            ( w_int_deactivate_start         ),
        .O_INT_FDI_LINK_DOWN               ( w_int_fdi_link_down_set        ),
        .O_DEACTIVATE_PROPERTY             ( w_deactivate_property          )

    );

//-------------------------------------------------------------
    logic                                w_fdi_pl_trdy_0;
    logic [FDI_IF_WD0-1:0]               w_fdi_lp_data_0;
    logic                                w_fdi_lp_valid_0;

`ifdef TWO_PHY
    logic                                w_fdi_pl_trdy_1;
    logic [FDI_IF_WD1-1:0]               w_fdi_lp_data_1;
    logic                                w_fdi_lp_valid_1;
`endif

    AOU_TX_CORE #(
        .RP_CNT                         ( RP_COUNT                      ),

        .FDI_IF_WD0                     ( FDI_IF_WD0                    ),
        .FDI_IF_WD1                     ( FDI_IF_WD1                    ),
        .TX_NXT_PACKING_EN              ( TX_NXT_PACKING_EN             ),
        .RP0_AXI_DATA_WD                ( RP0_AXI_DATA_WD               ),
        .RP1_AXI_DATA_WD                ( RP1_AXI_DATA_WD               ),
        .RP2_AXI_DATA_WD                ( RP2_AXI_DATA_WD               ),
        .RP3_AXI_DATA_WD                ( RP3_AXI_DATA_WD               ),
        .MAX_AXI_DATA_WD                ( RP_AXI_DATA_WD_MAX            ),

        .AXI_ADDR_WD                    ( AXI_ADDR_WD                   ),
        .AXI_ID_WD                      ( AXI_ID_WD                     ),
        .AXI_LEN_WD                     ( AXI_LEN_WD                    ),

        .CNT_RP0_AW_MAX_CREDIT          ( CNT_RP0_TX_AW_MAX_CREDIT      ),
        .CNT_RP0_AR_MAX_CREDIT          ( CNT_RP0_TX_AR_MAX_CREDIT      ),
        .CNT_RP0_W_MAX_CREDIT           ( CNT_RP0_TX_W_MAX_CREDIT       ),
        .CNT_RP0_R_MAX_CREDIT           ( CNT_RP0_TX_R_MAX_CREDIT       ),
        .CNT_RP0_B_MAX_CREDIT           ( CNT_RP0_TX_B_MAX_CREDIT       ),

        .CNT_RP1_AW_MAX_CREDIT          ( CNT_RP1_TX_AW_MAX_CREDIT      ),
        .CNT_RP1_AR_MAX_CREDIT          ( CNT_RP1_TX_AR_MAX_CREDIT      ),
        .CNT_RP1_W_MAX_CREDIT           ( CNT_RP1_TX_W_MAX_CREDIT       ),
        .CNT_RP1_R_MAX_CREDIT           ( CNT_RP1_TX_R_MAX_CREDIT       ),
        .CNT_RP1_B_MAX_CREDIT           ( CNT_RP1_TX_B_MAX_CREDIT       ),

        .CNT_RP2_AW_MAX_CREDIT          ( CNT_RP2_TX_AW_MAX_CREDIT      ),
        .CNT_RP2_AR_MAX_CREDIT          ( CNT_RP2_TX_AR_MAX_CREDIT      ),
        .CNT_RP2_W_MAX_CREDIT           ( CNT_RP2_TX_W_MAX_CREDIT       ),
        .CNT_RP2_R_MAX_CREDIT           ( CNT_RP2_TX_R_MAX_CREDIT       ),
        .CNT_RP2_B_MAX_CREDIT           ( CNT_RP2_TX_B_MAX_CREDIT       ),

        .CNT_RP3_AW_MAX_CREDIT          ( CNT_RP3_TX_AW_MAX_CREDIT      ),
        .CNT_RP3_AR_MAX_CREDIT          ( CNT_RP3_TX_AR_MAX_CREDIT      ),
        .CNT_RP3_W_MAX_CREDIT           ( CNT_RP3_TX_W_MAX_CREDIT       ),
        .CNT_RP3_R_MAX_CREDIT           ( CNT_RP3_TX_R_MAX_CREDIT       ),
        .CNT_RP3_B_MAX_CREDIT           ( CNT_RP3_TX_B_MAX_CREDIT       )


    ) u_aou_tx_core
    (
        .I_CLK                          ( I_CLK                         ),
        .I_RESETN                       ( I_RESETN                      ),
    
        .I_AOU_TX_AXI_AWID              ( w_tmp_early_bresp_ctrl_awid   ),
        .I_AOU_TX_AXI_AWADDR            ( w_tmp_early_bresp_ctrl_awaddr ),
        .I_AOU_TX_AXI_AWLEN             ( w_tmp_early_bresp_ctrl_awlen  ),
        .I_AOU_TX_AXI_AWSIZE            ( w_tmp_early_bresp_ctrl_awsize ),
        .I_AOU_TX_AXI_AWBURST           ( w_tmp_early_bresp_ctrl_awburst),
        .I_AOU_TX_AXI_AWLOCK            ( w_tmp_early_bresp_ctrl_awlock ),
        .I_AOU_TX_AXI_AWCACHE           ( w_tmp_early_bresp_ctrl_awcache),
        .I_AOU_TX_AXI_AWPROT            ( w_tmp_early_bresp_ctrl_awprot ),
        .I_AOU_TX_AXI_AWQOS             ( w_tmp_early_bresp_ctrl_awqos  ),
        .I_AOU_TX_AXI_AWVALID           ( w_tmp_early_bresp_ctrl_awvalid),
        .O_AOU_TX_AXI_AWREADY           ( w_tmp_early_bresp_ctrl_awready),
                                               
        .I_AOU_TX_AXI_WDATA             ( w_tmp_early_bresp_ctrl_wdata  ),
        .I_AOU_TX_AXI_WSTRB             ( w_tmp_early_bresp_ctrl_wstrb  ),
        .I_AOU_TX_AXI_WLAST             ( w_tmp_early_bresp_ctrl_wlast  ),
        .I_AOU_TX_AXI_WDLEN             ( w_tmp_early_bresp_ctrl_wdlen  ),
        .I_AOU_TX_AXI_WVALID            ( w_tmp_early_bresp_ctrl_wvalid ),
        .O_AOU_TX_AXI_WREADY            ( w_tmp_early_bresp_ctrl_wready ),
    
        .I_AOU_TX_AXI_ARID              ( w_aou_tx_axi_s_arid           ),
        .I_AOU_TX_AXI_ARADDR            ( w_aou_tx_axi_s_araddr         ),
        .I_AOU_TX_AXI_ARLEN             ( w_aou_tx_axi_s_arlen          ),
        .I_AOU_TX_AXI_ARSIZE            ( w_aou_tx_axi_s_arsize         ),
        .I_AOU_TX_AXI_ARBURST           ( w_aou_tx_axi_s_arburst        ),
        .I_AOU_TX_AXI_ARLOCK            ( w_aou_tx_axi_s_arlock         ),
        .I_AOU_TX_AXI_ARCACHE           ( w_aou_tx_axi_s_arcache        ),
        .I_AOU_TX_AXI_ARPROT            ( w_aou_tx_axi_s_arprot         ),
        .I_AOU_TX_AXI_ARQOS             ( w_aou_tx_axi_s_arqos          ),
        .I_AOU_TX_AXI_ARVALID           ( w_aou_tx_axi_s_arvalid        ),
        .O_AOU_TX_AXI_ARREADY           ( w_aou_tx_axi_s_arready        ),

        .I_AOU_TX_AXI_BID_256           ( w_aou_tx_axi_mm_bid_256       ),
        .I_AOU_TX_AXI_BRESP_256         ( w_aou_tx_axi_mm_bresp_256     ),
        .I_AOU_TX_AXI_BVALID_256        ( w_aou_tx_axi_mm_bvalid_256    ),
        .O_AOU_TX_AXI_BREADY_256        ( w_aou_tx_axi_mm_bready_256    ),

        .I_AOU_TX_AXI_BID_512           ( w_aou_tx_axi_mm_bid_512       ),
        .I_AOU_TX_AXI_BRESP_512         ( w_aou_tx_axi_mm_bresp_512     ),
        .I_AOU_TX_AXI_BVALID_512        ( w_aou_tx_axi_mm_bvalid_512    ),
        .O_AOU_TX_AXI_BREADY_512        ( w_aou_tx_axi_mm_bready_512    ),

        .I_AOU_TX_AXI_BID_1024          ( w_aou_tx_axi_mm_bid_1024      ),
        .I_AOU_TX_AXI_BRESP_1024        ( w_aou_tx_axi_mm_bresp_1024    ),
        .I_AOU_TX_AXI_BVALID_1024       ( w_aou_tx_axi_mm_bvalid_1024   ),
        .O_AOU_TX_AXI_BREADY_1024       ( w_aou_tx_axi_mm_bready_1024   ),

        .I_AOU_TX_AXI_RID               ( w_aou_tx_axi_mm_rid           ),
        .I_AOU_TX_AXI_RDLEN             ( w_aou_tx_axi_mm_rdlen         ),
        .I_AOU_TX_AXI_RDATA             ( w_aou_tx_axi_mm_rdata         ),
        .I_AOU_TX_AXI_RRESP             ( w_aou_tx_axi_mm_rresp         ),
        .I_AOU_TX_AXI_RLAST             ( w_aou_tx_axi_mm_rlast         ),
        .I_AOU_TX_AXI_RVALID            ( w_aou_tx_axi_mm_rvalid        ),
        .O_AOU_TX_AXI_RREADY            ( w_aou_tx_axi_mm_rready        ),

        .I_AOU_MSGCREDIT_WREQCRED       ( w_txcore_msgcredit_wreqcred   ),
        .I_AOU_MSGCREDIT_RREQCRED       ( w_txcore_msgcredit_rreqcred   ),
        .I_AOU_MSGCREDIT_WDATACRED      ( w_txcore_msgcredit_wdatacred  ),
        .I_AOU_MSGCREDIT_RDATACRED      ( w_txcore_msgcredit_rdatacred  ),
        .I_AOU_MSGCREDIT_WRESPCRED      ( w_txcore_msgcredit_wrespcred  ),
        .I_AOU_MSGCREDIT_RP             ( w_txcore_msgcredit_rp         ),
        .I_AOU_MSGCREDIT_CRED_VALID     ( w_txcore_msgcredit_cred_valid ),
        .O_AOU_MSGCREDIT_CRED_READY     ( w_txcore_msgcredit_cred_ready ),

        .I_AOU_CRDTGRANT_WRESPCRED3     ( w_txcore_crdtgrant_wrespcred3 ),
        .I_AOU_CRDTGRANT_WRESPCRED2     ( w_txcore_crdtgrant_wrespcred2 ),
        .I_AOU_CRDTGRANT_WRESPCRED1     ( w_txcore_crdtgrant_wrespcred1 ),
        .I_AOU_CRDTGRANT_WRESPCRED0     ( w_txcore_crdtgrant_wrespcred0 ),
        .I_AOU_CRDTGRANT_RDATACRED3     ( w_txcore_crdtgrant_rdatacred3 ),
        .I_AOU_CRDTGRANT_RDATACRED2     ( w_txcore_crdtgrant_rdatacred2 ),
        .I_AOU_CRDTGRANT_RDATACRED1     ( w_txcore_crdtgrant_rdatacred1 ),
        .I_AOU_CRDTGRANT_RDATACRED0     ( w_txcore_crdtgrant_rdatacred0 ),
        .I_AOU_CRDTGRANT_WDATACRED3     ( w_txcore_crdtgrant_wdatacred3 ),
        .I_AOU_CRDTGRANT_WDATACRED2     ( w_txcore_crdtgrant_wdatacred2 ),
        .I_AOU_CRDTGRANT_WDATACRED1     ( w_txcore_crdtgrant_wdatacred1 ),
        .I_AOU_CRDTGRANT_WDATACRED0     ( w_txcore_crdtgrant_wdatacred0 ),
        .I_AOU_CRDTGRANT_RREQCRED3      ( w_txcore_crdtgrant_rreqcred3  ),
        .I_AOU_CRDTGRANT_RREQCRED2      ( w_txcore_crdtgrant_rreqcred2  ),
        .I_AOU_CRDTGRANT_RREQCRED1      ( w_txcore_crdtgrant_rreqcred1  ),
        .I_AOU_CRDTGRANT_RREQCRED0      ( w_txcore_crdtgrant_rreqcred0  ),
        .I_AOU_CRDTGRANT_WREQCRED3      ( w_txcore_crdtgrant_wreqcred3  ),
        .I_AOU_CRDTGRANT_WREQCRED2      ( w_txcore_crdtgrant_wreqcred2  ),
        .I_AOU_CRDTGRANT_WREQCRED1      ( w_txcore_crdtgrant_wreqcred1  ),
        .I_AOU_CRDTGRANT_WREQCRED0      ( w_txcore_crdtgrant_wreqcred0  ),
        .I_AOU_CRDTGRANT_VALID          ( w_txcore_crdtgrant_valid      ),
        .O_AOU_CRDTGRANT_READY          ( w_txcore_crdtgrant_ready      ),

        .I_AOU_ACTIVATION_OP            ( w_txcore_activation_op        ),
        .I_AOU_ACTIVATION_PROP_REQ      ( w_txcore_activation_prop_req  ),
        .I_AOU_ACTIVATION_VALID         ( w_txcore_activation_valid     ),
        .O_AOU_ACTIVATION_READY         ( w_txcore_activation_ready     ),
        .O_AOU_TX_PENDING               ( w_tx_pending                  ),
        .O_AOU_TX_AXI_TR_PENDING        ( w_tx_axi_tr_pending           ),

        .I_AOU_TX_WREQCRED              ( w_aou_tx_wreqcred             ),
        .I_AOU_TX_RREQCRED              ( w_aou_tx_rreqcred             ),
        .I_AOU_TX_WDATACRED             ( w_aou_tx_wdatacred            ),
        .I_AOU_TX_RDATACRED             ( w_aou_tx_rdatacred            ),
        .I_AOU_TX_WRESPCRED             ( w_aou_tx_wrespcred            ),

        .O_AOU_TX_WREQVALID             ( w_aou_tx_wreqvalid            ),
        .O_AOU_TX_RREQVALID             ( w_aou_tx_rreqvalid            ),
        .O_AOU_TX_WDATAVALID            ( w_aou_tx_wdatavalid           ),
        .O_AOU_TX_WDATA_DLENGTH         ( w_aou_tx_wdata_dlength        ),
        .O_AOU_TX_WFDATA                ( w_aou_tx_wfdata               ),
        .O_AOU_TX_RDATAVALID            ( w_aou_tx_rdatavalid           ),
        .O_AOU_TX_RDATA_DLENGTH         ( w_aou_tx_rdata_dlength        ),
        .O_AOU_TX_WRESPVALID            ( w_aou_tx_wrespvalid           ),

        .I_AOU_TX_LP_MODE_THRESHOLD     ( w_tx_lp_mode_threshold        ),
        .I_AOU_TX_LP_MODE               ( w_tx_lp_mode                  ),

        .I_FDI_PL_TRDY_0                ( w_fdi_pl_trdy_0               ),
        .O_FDI_LP_DATA_0                ( w_fdi_lp_data_0               ),
        .O_FDI_LP_VALID_0               ( w_fdi_lp_valid_0              ),

`ifdef TWO_PHY
        .I_PHY_TYPE                     ( I_PHY_TYPE                    ),

        .I_FDI_PL_TRDY_1                ( w_fdi_pl_trdy_1               ),
        .O_FDI_LP_DATA_1                ( w_fdi_lp_data_1               ),
        .O_FDI_LP_VALID_1               ( w_fdi_lp_valid_1              ),
`endif

        .I_STATUS_DISABLED              ( w_status_disabled             ),
        .I_STATUS_ENABLED               ( O_AOU_ACTIVATE_ST_ENABLED     ),
        .I_RP_DEST_RP                   ( w_rp_dest_rp                  ),

        .I_PRIOR_RP_AXI_AXI_QOS_TO_NP   ( w_prior_rp_axi_axi_qos_to_np  ),
        .I_PRIOR_RP_AXI_AXI_QOS_TO_HP   ( w_prior_rp_axi_axi_qos_to_hp  ),
        .I_PRIOR_RP_AXI_RP3_PRIOR       ( w_prior_rp_axi_rp3_prior      ),
        .I_PRIOR_RP_AXI_RP2_PRIOR       ( w_prior_rp_axi_rp2_prior      ),
        .I_PRIOR_RP_AXI_RP1_PRIOR       ( w_prior_rp_axi_rp1_prior      ),
        .I_PRIOR_RP_AXI_RP0_PRIOR       ( w_prior_rp_axi_rp0_prior      ),
        .I_PRIOR_RP_AXI_ARB_MODE        ( w_prior_rp_axi_arb_mode       ),
        .I_PRIOR_TIMER_TIMER_RESOLUTION ( w_prior_timer_timer_resolution),
        .I_PRIOR_TIMER_TIMER_THRESHOLD  ( w_prior_timer_timer_threshold ),
        .I_TX_REQ_CREDIT_BLOCKn         ( w_tx_req_credit_blockn        ),
        .I_TX_RSP_CREDIT_BLOCKn         ( w_tx_rsp_credit_blockn        )


    );

    AOU_TX_FDI_IF # (
        .FDI_DATA_WD    ( FDI_IF_WD0   )
    ) u_aou_tx_fdi_if0 (
        .I_CLK                          ( I_CLK                     ),
        .I_RESETN                       ( I_RESETN                  ),

        .I_AOU_TX_FLIT_DATA_VALID       ( w_fdi_lp_valid_0            ),
        .I_AOU_TX_FLIT_DATA             ( w_fdi_lp_data_0             ),
        .O_AOU_TX_FLIT_READY            ( w_fdi_pl_trdy_0             ),

        .I_FDI_PL_TRDY                  ( I_FDI_PL_0_TRDY             ),
        .I_FDI_PL_STALLREQ              ( r_fdi_pl_0_stallreq         ),
        .I_FDI_PL_STATE_STS             ( I_FDI_PL_0_STATE_STS        ),
        .O_FDI_LP_DATA                  ( O_FDI_LP_0_DATA             ),
        .O_FDI_LP_VALID                 ( O_FDI_LP_0_VALID            ),
        .O_FDI_LP_IRDY                  ( O_FDI_LP_0_IRDY             ),
        .O_FDI_LP_STALLACK              ( O_FDI_LP_0_STALLACK         )
    );

`ifdef TWO_PHY
    AOU_TX_FDI_IF # (
        .FDI_DATA_WD    ( FDI_IF_WD1   )
    ) u_aou_tx_fdi_if1 (
        .I_CLK                          ( I_CLK                     ),
        .I_RESETN                       ( I_RESETN                  ),

        .I_AOU_TX_FLIT_DATA_VALID       ( w_fdi_lp_valid_1            ),
        .I_AOU_TX_FLIT_DATA             ( w_fdi_lp_data_1             ),
        .O_AOU_TX_FLIT_READY            ( w_fdi_pl_trdy_1             ),

        .I_FDI_PL_TRDY                  ( I_FDI_PL_1_TRDY             ),
        .I_FDI_PL_STALLREQ              ( r_fdi_pl_1_stallreq         ),
        .I_FDI_PL_STATE_STS             ( I_FDI_PL_1_STATE_STS        ),
        .O_FDI_LP_DATA                  ( O_FDI_LP_1_DATA             ),
        .O_FDI_LP_VALID                 ( O_FDI_LP_1_VALID            ),
        .O_FDI_LP_IRDY                  ( O_FDI_LP_1_IRDY             ),
        .O_FDI_LP_STALLACK              ( O_FDI_LP_1_STALLACK         )
    );


`endif

//-------------------------------------------------------------

    // RX PHY->decode width adapter: instantiate a mux when TWO_PHY is
    // enabled (mux both PHY streams) or when the single PHY is narrower than
    // the decode width (the 32B primary-width case). Otherwise PHY0 data
    // matches the decode width and is wired through directly.
    logic                           w_fdi_pl_valid;
    logic   [FDI_DEC_WD-1:0]        w_fdi_pl_data;
    logic                           w_fdi_pl_flit_cancel;

`ifdef TWO_PHY
    AOU_RX_CORE_IN_MUX #(
        .FDI_IF_WD                  ( FDI_DEC_WD                )
    ) u_aou_rx_core_in_mux
    (
        .I_CLK                      ( I_CLK                     ),
        .I_RESETN                   ( I_RESETN                  ),
        .I_PHY_TYPE                 ( I_PHY_TYPE                ),
        .I_FDI_PL_1_VALID           ( I_FDI_PL_1_VALID          ),
        .I_FDI_PL_1_DATA            ( I_FDI_PL_1_DATA           ),
        .I_FDI_PL_1_FLIT_CANCEL     ( I_FDI_PL_1_FLIT_CANCEL    ),

        .I_FDI_PL_0_VALID           ( I_FDI_PL_0_VALID          ),
        .I_FDI_PL_0_DATA            ( I_FDI_PL_0_DATA           ),
        .I_FDI_PL_0_FLIT_CANCEL     ( I_FDI_PL_0_FLIT_CANCEL    ),

        .O_FDI_PL_VALID             ( w_fdi_pl_valid            ),
        .O_FDI_PL_DATA              ( w_fdi_pl_data             ),
        .O_FDI_PL_FLIT_CANCEL       ( w_fdi_pl_flit_cancel      )
    );
`else
    generate if (FDI_IF_WD0 < FDI_DEC_WD) begin : g_rx_mux_sp
        AOU_RX_CORE_IN_MUX #(
            .FDI_IF_WD              ( FDI_DEC_WD                )
        ) u_aou_rx_core_in_mux
        (
            .I_CLK                  ( I_CLK                     ),
            .I_RESETN               ( I_RESETN                  ),
            .I_PHY_TYPE             ( 1'b0                      ),
            .I_FDI_PL_1_VALID       ( '0                        ),
            .I_FDI_PL_1_DATA        ( '0                        ),
            .I_FDI_PL_1_FLIT_CANCEL ( '0                        ),

            .I_FDI_PL_0_VALID       ( I_FDI_PL_0_VALID          ),
            .I_FDI_PL_0_DATA        ( I_FDI_PL_0_DATA           ),
            .I_FDI_PL_0_FLIT_CANCEL ( I_FDI_PL_0_FLIT_CANCEL    ),

            .O_FDI_PL_VALID         ( w_fdi_pl_valid            ),
            .O_FDI_PL_DATA          ( w_fdi_pl_data             ),
            .O_FDI_PL_FLIT_CANCEL   ( w_fdi_pl_flit_cancel      )
        );
    end else begin : g_rx_direct
        assign w_fdi_pl_valid       = I_FDI_PL_0_VALID;
        assign w_fdi_pl_data        = I_FDI_PL_0_DATA;
        assign w_fdi_pl_flit_cancel = I_FDI_PL_0_FLIT_CANCEL;
    end endgenerate
`endif

    AOU_RX_CORE #(
        .DEC_MULTI                        ( DEC_MULTI                         ),
        .PHY_TYPE                         ( PHY_TYPE                          ),
        .FDI_IF_WD                        ( FDI_DEC_WD                        ),

        .AXI_PEER_DIE_MAX_DATA_WD           ( AXI_PEER_DIE_MAX_DATA_WD          ),
        .AXI_ADDR_WD                        ( AXI_ADDR_WD                       ),
        .AXI_ID_WD                          ( AXI_ID_WD                         ),
        .AXI_LEN_WD                         ( AXI_LEN_WD                        ),

        .RP_COUNT                           ( RP_COUNT                          ),
        .AW_AR_FIFO_DATA_WIDTH              ( AW_AR_FIFO_WIDTH                  ),
        .B_FIFO_DATA_WIDTH                  ( B_FIFO_WIDTH                      ),
        .R_FIFO_EXT_DATA_WIDTH              ( R_FIFO_EXT_DATA_WIDTH             )

    ) u_aou_rx_core
    (
        .I_CLK                              ( I_CLK                             ),
        .I_RESETN                           ( I_RESETN                          ),

        .I_FDI_PL_VALID                     ( w_fdi_pl_valid                    ),
        .I_FDI_PL_DATA                      ( w_fdi_pl_data                     ),
        .I_FDI_PL_FLIT_CANCEL               ( w_fdi_pl_flit_cancel              ),

        .O_RD_REQ_FIFO_SDATA                ( O_RD_REQ_FIFO_SDATA               ),
        .O_RD_REQ_FIFO_SVALID               ( O_RD_REQ_FIFO_SVALID              ),

        .O_WR_REQ_FIFO_SDATA                ( O_WR_REQ_FIFO_SDATA               ),
        .O_WR_REQ_FIFO_SVALID               ( O_WR_REQ_FIFO_SVALID              ),

        .O_WR_DATA_FIFO_SDATA               ( O_WR_DATA_FIFO_SDATA              ),
        .O_WR_DATA_FIFO_SDATA_STRB          ( O_WR_DATA_FIFO_SDATA_STRB         ),
        .O_WR_DATA_FIFO_SDATA_WDATAF        ( O_WR_DATA_FIFO_SDATA_WDATAF       ),
        .O_WR_DATA_FIFO_SVALID              ( O_WR_DATA_FIFO_SVALID             ),

        .O_WR_RESP_FIFO_SDATA               ( O_WR_RESP_FIFO_SDATA              ),
        .O_WR_RESP_FIFO_SVALID              ( O_WR_RESP_FIFO_SVALID             ),

        .O_RD_DATA_FIFO_SDATA               ( O_RD_DATA_FIFO_SDATA              ),
        .O_RD_DATA_FIFO_EXT_SDATA           ( O_RD_DATA_FIFO_EXT_SDATA          ),
        .O_RD_DATA_FIFO_SVALID              ( O_RD_DATA_FIFO_SVALID             ),

        .O_CRDTGRANT_WRESPCRED3             ( w_rxcore_crdtgrant_wrespcred3     ),
        .O_CRDTGRANT_WRESPCRED2             ( w_rxcore_crdtgrant_wrespcred2     ),
        .O_CRDTGRANT_WRESPCRED1             ( w_rxcore_crdtgrant_wrespcred1     ),
        .O_CRDTGRANT_WRESPCRED0             ( w_rxcore_crdtgrant_wrespcred0     ),
        .O_CRDTGRANT_RDATACRED3             ( w_rxcore_crdtgrant_rdatacred3     ),
        .O_CRDTGRANT_RDATACRED2             ( w_rxcore_crdtgrant_rdatacred2     ),
        .O_CRDTGRANT_RDATACRED1             ( w_rxcore_crdtgrant_rdatacred1     ),
        .O_CRDTGRANT_RDATACRED0             ( w_rxcore_crdtgrant_rdatacred0     ),
        .O_CRDTGRANT_WDATACRED3             ( w_rxcore_crdtgrant_wdatacred3     ),
        .O_CRDTGRANT_WDATACRED2             ( w_rxcore_crdtgrant_wdatacred2     ),
        .O_CRDTGRANT_WDATACRED1             ( w_rxcore_crdtgrant_wdatacred1     ),
        .O_CRDTGRANT_WDATACRED0             ( w_rxcore_crdtgrant_wdatacred0     ),
        .O_CRDTGRANT_RREQCRED3              ( w_rxcore_crdtgrant_rreqcred3      ),
        .O_CRDTGRANT_RREQCRED2              ( w_rxcore_crdtgrant_rreqcred2      ),
        .O_CRDTGRANT_RREQCRED1              ( w_rxcore_crdtgrant_rreqcred1      ),
        .O_CRDTGRANT_RREQCRED0              ( w_rxcore_crdtgrant_rreqcred0      ),
        .O_CRDTGRANT_WREQCRED3              ( w_rxcore_crdtgrant_wreqcred3      ),
        .O_CRDTGRANT_WREQCRED2              ( w_rxcore_crdtgrant_wreqcred2      ),
        .O_CRDTGRANT_WREQCRED1              ( w_rxcore_crdtgrant_wreqcred1      ),
        .O_CRDTGRANT_WREQCRED0              ( w_rxcore_crdtgrant_wreqcred0      ),
        .O_CRDTGRANT_VALID                  ( w_rxcore_crdtgrant_valid          ),

        .O_MSGCRDT_WRESPCRED                ( w_rxcore_msgcrdt_wrespcred        ),
        .O_MSGCRDT_RDATACRED                ( w_rxcore_msgcrdt_rdatacred        ),
        .O_MSGCRDT_WDATACRED                ( w_rxcore_msgcrdt_wdatacred        ),
        .O_MSGCRDT_RREQCRED                 ( w_rxcore_msgcrdt_rreqcred         ),
        .O_MSGCRDT_WREQCRED                 ( w_rxcore_msgcrdt_wreqcred         ),
        .O_MSGCRDT_RP                       ( w_rxcore_msgcrdt_rp               ),
        .O_MSGCRDT_VALID                    ( w_rxcore_msgcrdt_valid            ),

        .O_ACTIVATION_OP                    ( w_rxcore_activation_op            ),
        .O_ACTIVATION_PROP_REQ              ( w_rxcore_activation_prop_req      ),
        .O_ACTIVATION_VALID                 ( w_rxcore_activation_valid         )
    );

//-------------------------------------------------------------

    assign O_AOU_ACTIVATE_ST_DISABLED = w_status_disabled;

    genvar i;
    generate 
        for(i = 0; i < RP_COUNT; i++) begin : gen_wdlen
            assign w_early_bresp_ctrl_wdlen[i] = (RP_AXI_DATA_WD[i] == 256) ? 2'b00 :
                                                 (RP_AXI_DATA_WD[i] == 512) ? 2'b01 :   
                                                 (RP_AXI_DATA_WD[i] == 1024)? 2'b10 :   
                                                                              2'b00 ;
        end

        for(i = 0; i < RP_COUNT; i++) begin : gen_aou_core_rp
            if(RP_AXI_DATA_WD_MAX > RP_AXI_DATA_WD[i]) begin: GEN_PAD
                assign O_AOU_RX_AXI_M_WDATA[i][RP_AXI_DATA_WD_MAX-1:RP_AXI_DATA_WD[i]]      = 'd0;
                assign O_AOU_RX_AXI_M_WSTRB[i][RP_AXI_STRB_WD_MAX-1:RP_AXI_STRB_WD[i]]      = 'd0;
                assign w_early_bresp_ctrl_wdata[i][RP_AXI_DATA_WD_MAX-1:RP_AXI_DATA_WD[i]]  = 'd0;
                assign w_early_bresp_ctrl_wstrb[i][RP_AXI_STRB_WD_MAX-1:RP_AXI_STRB_WD[i]]  = 'd0;
            end

            assign O_AOU_TX_AXI_S_ARREADY[i]     = w_aou_tx_axi_s_arready_tmp[i] && ~w_aou_slv_info_ar_hold_flag[i];
            assign w_aou_tx_axi_s_arvalid_tmp[i] = I_AOU_TX_AXI_S_ARVALID[i] && ~w_aou_slv_info_ar_hold_flag[i];

            AOU_CORE_RP #(
                .AXI_DATA_WD                ( RP_AXI_DATA_WD[i]             ),
                .AXI_PEER_DIE_MAX_DATA_WD   ( AXI_PEER_DIE_MAX_DATA_WD      ),

                .S_RD_MO_CNT                ( RP_S_RD_MO_CNT[i]             ),
                .S_WR_MO_CNT                ( RP_S_WR_MO_CNT[i]             ),

                .M_RD_MO_CNT                ( RP_M_RD_MO_CNT[i]             ),
                .M_WR_MO_CNT                ( RP_M_WR_MO_CNT[i]             ),
                .AOU_AGG_WCH_FIFO_DEPTH     ( AGG_WCH_FIFO_DEPTH[i]         )

            ) u_aou_core_rp
            (
                .I_CLK                                     ( I_CLK                              ),
                .I_RESETN                                  ( I_RESETN                           ),

                .O_AOU_RX_AXI_M_ARID                       ( O_AOU_RX_AXI_M_ARID[i]             ),
                .O_AOU_RX_AXI_M_ARADDR                     ( O_AOU_RX_AXI_M_ARADDR[i]           ),
                .O_AOU_RX_AXI_M_ARLEN                      ( O_AOU_RX_AXI_M_ARLEN[i]            ),
                .O_AOU_RX_AXI_M_ARSIZE                     ( O_AOU_RX_AXI_M_ARSIZE[i]           ),
                .O_AOU_RX_AXI_M_ARBURST                    ( O_AOU_RX_AXI_M_ARBURST[i]          ),
                .O_AOU_RX_AXI_M_ARLOCK                     ( O_AOU_RX_AXI_M_ARLOCK[i]           ),
                .O_AOU_RX_AXI_M_ARCACHE                    ( O_AOU_RX_AXI_M_ARCACHE[i]          ),
                .O_AOU_RX_AXI_M_ARPROT                     ( O_AOU_RX_AXI_M_ARPROT[i]           ),
                .O_AOU_RX_AXI_M_ARQOS                      ( O_AOU_RX_AXI_M_ARQOS[i]            ),
                .O_AOU_RX_AXI_M_ARVALID                    ( O_AOU_RX_AXI_M_ARVALID[i]          ),
                .I_AOU_RX_AXI_M_ARREADY                    ( I_AOU_RX_AXI_M_ARREADY[i]          ),

                .I_AOU_TX_AXI_M_RID                        ( I_AOU_TX_AXI_M_RID[i]              ),
                .I_AOU_TX_AXI_M_RDATA                      ( I_AOU_TX_AXI_M_RDATA[i][RP_AXI_DATA_WD[i]-1:0] ),
                .I_AOU_TX_AXI_M_RRESP                      ( I_AOU_TX_AXI_M_RRESP[i]            ),
                .I_AOU_TX_AXI_M_RLAST                      ( I_AOU_TX_AXI_M_RLAST[i]            ),
                .I_AOU_TX_AXI_M_RVALID                     ( I_AOU_TX_AXI_M_RVALID[i]           ),
                .O_AOU_TX_AXI_M_RREADY                     ( O_AOU_TX_AXI_M_RREADY[i]           ),

                .O_AOU_RX_AXI_M_AWID                       ( O_AOU_RX_AXI_M_AWID[i]             ),
                .O_AOU_RX_AXI_M_AWADDR                     ( O_AOU_RX_AXI_M_AWADDR[i]           ),
                .O_AOU_RX_AXI_M_AWLEN                      ( O_AOU_RX_AXI_M_AWLEN[i]            ),
                .O_AOU_RX_AXI_M_AWSIZE                     ( O_AOU_RX_AXI_M_AWSIZE[i]           ),
                .O_AOU_RX_AXI_M_AWBURST                    ( O_AOU_RX_AXI_M_AWBURST[i]          ),
                .O_AOU_RX_AXI_M_AWLOCK                     ( O_AOU_RX_AXI_M_AWLOCK[i]           ),
                .O_AOU_RX_AXI_M_AWCACHE                    ( O_AOU_RX_AXI_M_AWCACHE[i]          ),
                .O_AOU_RX_AXI_M_AWPROT                     ( O_AOU_RX_AXI_M_AWPROT[i]           ),
                .O_AOU_RX_AXI_M_AWQOS                      ( O_AOU_RX_AXI_M_AWQOS[i]            ),
                .O_AOU_RX_AXI_M_AWVALID                    ( O_AOU_RX_AXI_M_AWVALID[i]          ),
                .I_AOU_RX_AXI_M_AWREADY                    ( I_AOU_RX_AXI_M_AWREADY[i]          ),

                .O_AOU_RX_AXI_M_WDATA                      ( O_AOU_RX_AXI_M_WDATA[i][RP_AXI_DATA_WD[i]-1:0] ),
                .O_AOU_RX_AXI_M_WSTRB                      ( O_AOU_RX_AXI_M_WSTRB[i][RP_AXI_STRB_WD[i]-1:0] ),
                .O_AOU_RX_AXI_M_WLAST                      ( O_AOU_RX_AXI_M_WLAST[i]           ),
                .O_AOU_RX_AXI_M_WVALID                     ( O_AOU_RX_AXI_M_WVALID[i]          ),
                .I_AOU_RX_AXI_M_WREADY                     ( I_AOU_RX_AXI_M_WREADY[i]          ),

                .I_AOU_TX_AXI_M_BID                        ( I_AOU_TX_AXI_M_BID[i]             ),
                .I_AOU_TX_AXI_M_BRESP                      ( I_AOU_TX_AXI_M_BRESP[i]           ),
                .I_AOU_TX_AXI_M_BVALID                     ( I_AOU_TX_AXI_M_BVALID[i]          ),
                .O_AOU_TX_AXI_M_BREADY                     ( O_AOU_TX_AXI_M_BREADY[i]          ),

                .I_AOU_TX_AXI_S_ARID                       ( I_AOU_TX_AXI_S_ARID[i]            ),
                .I_AOU_TX_AXI_S_ARVALID                    ( I_AOU_TX_AXI_S_ARVALID[i]         ),
                .I_AOU_TX_AXI_S_ARREADY                    ( O_AOU_TX_AXI_S_ARREADY[i]         ),    
                .O_AOU_SLV_INFO_AR_HOLD_FLAG               ( w_aou_slv_info_ar_hold_flag[i]    ),
                                                                                            
                .I_AOU_RX_AXI_S_RID                        ( O_AOU_RX_AXI_S_RID[i]             ),
                .I_AOU_RX_AXI_S_RLAST                      ( O_AOU_RX_AXI_S_RLAST[i]           ),
                .I_AOU_RX_AXI_S_RVALID                     ( w_aou_rx_axi_s_rvalid[i]          ),
                .I_AOU_RX_AXI_S_RREADY                     ( I_AOU_RX_AXI_S_RREADY[i]          ),
                .O_AOU_RX_AXI_S_RVALID_BLOCKED             ( O_AOU_RX_AXI_S_RVALID_BLOCKED[i]  ),

                .I_AOU_TX_AXI_S_AWID                       ( I_AOU_TX_AXI_S_AWID[i]            ),
                .I_AOU_TX_AXI_S_AWADDR                     ( I_AOU_TX_AXI_S_AWADDR[i]          ),
                .I_AOU_TX_AXI_S_AWLEN                      ( I_AOU_TX_AXI_S_AWLEN[i]           ),
                .I_AOU_TX_AXI_S_AWSIZE                     ( I_AOU_TX_AXI_S_AWSIZE[i]          ),
                .I_AOU_TX_AXI_S_AWBURST                    ( I_AOU_TX_AXI_S_AWBURST[i]         ),       //There is no burst field on AOU
                .I_AOU_TX_AXI_S_AWLOCK                     ( I_AOU_TX_AXI_S_AWLOCK[i]          ),
                .I_AOU_TX_AXI_S_AWCACHE                    ( I_AOU_TX_AXI_S_AWCACHE[i]         ),
                .I_AOU_TX_AXI_S_AWPROT                     ( I_AOU_TX_AXI_S_AWPROT[i]          ),
                .I_AOU_TX_AXI_S_AWQOS                      ( I_AOU_TX_AXI_S_AWQOS[i]           ),
                .I_AOU_TX_AXI_S_AWVALID                    ( I_AOU_TX_AXI_S_AWVALID[i]         ),
                .O_AOU_TX_AXI_S_AWREADY                    ( O_AOU_TX_AXI_S_AWREADY[i]         ),

                .I_AOU_TX_AXI_S_WDATA                      ( I_AOU_TX_AXI_S_WDATA[i][RP_AXI_DATA_WD[i]-1:0] ),
                .I_AOU_TX_AXI_S_WSTRB                      ( I_AOU_TX_AXI_S_WSTRB[i][RP_AXI_STRB_WD[i]-1:0] ),
                .I_AOU_TX_AXI_S_WLAST                      ( I_AOU_TX_AXI_S_WLAST[i]           ),
                .I_AOU_TX_AXI_S_WVALID                     ( I_AOU_TX_AXI_S_WVALID[i]          ),
                .O_AOU_TX_AXI_S_WREADY                     ( O_AOU_TX_AXI_S_WREADY[i]          ),

                .O_AOU_RX_AXI_S_BID                        ( O_AOU_RX_AXI_S_BID[i]             ),
                .O_AOU_RX_AXI_S_BRESP                      ( O_AOU_RX_AXI_S_BRESP[i]           ),
                .O_AOU_RX_AXI_S_BVALID                     ( O_AOU_RX_AXI_S_BVALID[i]          ),
                .I_AOU_RX_AXI_S_BREADY                     ( I_AOU_RX_AXI_S_BREADY[i]          ),

                .I_AOU_RX_WLAST_GEN_AWID                   ( I_AOU_RX_WLAST_GEN_AWID[i]        ),
                .I_AOU_RX_WLAST_GEN_AWADDR                 ( I_AOU_RX_WLAST_GEN_AWADDR[i]      ),
                .I_AOU_RX_WLAST_GEN_AWLEN                  ( I_AOU_RX_WLAST_GEN_AWLEN[i]       ),
                .I_AOU_RX_WLAST_GEN_AWSIZE                 ( I_AOU_RX_WLAST_GEN_AWSIZE[i]      ),
                .I_AOU_RX_WLAST_GEN_AWLOCK                 ( I_AOU_RX_WLAST_GEN_AWLOCK[i]      ),
                .I_AOU_RX_WLAST_GEN_AWCACHE                ( I_AOU_RX_WLAST_GEN_AWCACHE[i]     ),
                .I_AOU_RX_WLAST_GEN_AWPROT                 ( I_AOU_RX_WLAST_GEN_AWPROT[i]      ),
                .I_AOU_RX_WLAST_GEN_AWQOS                  ( I_AOU_RX_WLAST_GEN_AWQOS[i]       ),
                .I_AOU_RX_WLAST_GEN_AWVALID                ( I_AOU_RX_WLAST_GEN_AWVALID[i]     ),
                .O_AOU_RX_WLAST_GEN_AWREADY                ( O_AOU_RX_WLAST_GEN_AWREADY[i]     ),

                .I_AOU_RX_WLAST_GEN_WDLENGTH               ( I_AOU_RX_WLAST_GEN_WDLENGTH[i]    ),
                .I_AOU_RX_WLAST_GEN_WDATA                  ( I_AOU_RX_WLAST_GEN_WDATA[i]       ),
                .I_AOU_RX_WLAST_GEN_WSTRB                  ( I_AOU_RX_WLAST_GEN_WSTRB[i]       ),
                .I_AOU_RX_WLAST_GEN_WVALID                 ( I_AOU_RX_WLAST_GEN_WVALID[i]      ),
                .O_AOU_RX_WLAST_GEN_WREADY                 ( O_AOU_RX_WLAST_GEN_WREADY[i]      ),

                .I_AOU_RX_AXI_MM_ARID                      ( I_AOU_RX_AXI_MM_ARID[i]           ),
                .I_AOU_RX_AXI_MM_ARADDR                    ( I_AOU_RX_AXI_MM_ARADDR[i]         ),
                .I_AOU_RX_AXI_MM_ARLEN                     ( I_AOU_RX_AXI_MM_ARLEN[i]          ),
                .I_AOU_RX_AXI_MM_ARSIZE                    ( I_AOU_RX_AXI_MM_ARSIZE[i]         ),
                .I_AOU_RX_AXI_MM_ARLOCK                    ( I_AOU_RX_AXI_MM_ARLOCK[i]         ),
                .I_AOU_RX_AXI_MM_ARCACHE                   ( I_AOU_RX_AXI_MM_ARCACHE[i]        ),
                .I_AOU_RX_AXI_MM_ARPROT                    ( I_AOU_RX_AXI_MM_ARPROT[i]         ),
                .I_AOU_RX_AXI_MM_ARQOS                     ( I_AOU_RX_AXI_MM_ARQOS[i]          ),
                .I_AOU_RX_AXI_MM_ARVALID                   ( I_AOU_RX_AXI_MM_ARVALID[i]        ),
                .O_AOU_RX_AXI_MM_ARREADY                   ( O_AOU_RX_AXI_MM_ARREADY[i]        ),
                
                .I_EARLY_BRESP_CTRL_BID                    ( w_early_bresp_ctrl_bid[i]         ),
                .I_EARLY_BRESP_CTRL_BRESP                  ( w_early_bresp_ctrl_bresp[i]       ),
                .I_EARLY_BRESP_CTRL_BVALID                 ( w_early_bresp_ctrl_bvalid[i]      ),
                .O_EARLY_BRESP_CTRL_BREADY                 ( w_early_bresp_ctrl_bready[i]      ),
                
                .O_EARLY_BRESP_CTRL_AWID                   ( w_early_bresp_ctrl_awid[i]        ),    
                .O_EARLY_BRESP_CTRL_AWADDR                 ( w_early_bresp_ctrl_awaddr[i]      ),    
                .O_EARLY_BRESP_CTRL_AWLEN                  ( w_early_bresp_ctrl_awlen[i]       ),    
                .O_EARLY_BRESP_CTRL_AWSIZE                 ( w_early_bresp_ctrl_awsize[i]      ),    
                .O_EARLY_BRESP_CTRL_AWBURST                ( w_early_bresp_ctrl_awburst[i]     ),    
                .O_EARLY_BRESP_CTRL_AWLOCK                 ( w_early_bresp_ctrl_awlock[i]      ),    
                .O_EARLY_BRESP_CTRL_AWCACHE                ( w_early_bresp_ctrl_awcache[i]     ),    
                .O_EARLY_BRESP_CTRL_AWPROT                 ( w_early_bresp_ctrl_awprot[i]      ),    
                .O_EARLY_BRESP_CTRL_AWQOS                  ( w_early_bresp_ctrl_awqos[i]       ),    
                .O_EARLY_BRESP_CTRL_AWVALID                ( w_early_bresp_ctrl_awvalid[i]     ),    
                .I_EARLY_BRESP_CTRL_AWREADY                ( w_early_bresp_ctrl_awready[i]     ),        
                                                                  
                .O_EARLY_BRESP_CTRL_WDATA                  ( w_early_bresp_ctrl_wdata[i][RP_AXI_DATA_WD[i]-1:0] ), 
                .O_EARLY_BRESP_CTRL_WSTRB                  ( w_early_bresp_ctrl_wstrb[i][RP_AXI_STRB_WD[i]-1:0] ),
                .O_EARLY_BRESP_CTRL_WLAST                  ( w_early_bresp_ctrl_wlast[i]        ),
                .O_EARLY_BRESP_CTRL_WVALID                 ( w_early_bresp_ctrl_wvalid[i]       ),
                .I_EARLY_BRESP_CTRL_WREADY                 ( w_early_bresp_ctrl_wready[i]       ),

                .O_AOU_TX_AXI_BID_256                      ( w_aou_tx_axi_mm_bid_256[i]         ),
                .O_AOU_TX_AXI_BRESP_256                    ( w_aou_tx_axi_mm_bresp_256[i]       ),
                .O_AOU_TX_AXI_BVALID_256                   ( w_aou_tx_axi_mm_bvalid_256[i]      ),
                .I_AOU_TX_AXI_BREADY_256                   ( w_aou_tx_axi_mm_bready_256[i]      ),

                .O_AOU_TX_AXI_BID_512                      ( w_aou_tx_axi_mm_bid_512[i]         ),
                .O_AOU_TX_AXI_BRESP_512                    ( w_aou_tx_axi_mm_bresp_512[i]       ),
                .O_AOU_TX_AXI_BVALID_512                   ( w_aou_tx_axi_mm_bvalid_512[i]      ),
                .I_AOU_TX_AXI_BREADY_512                   ( w_aou_tx_axi_mm_bready_512[i]      ),

                .O_AOU_TX_AXI_BID_1024                     ( w_aou_tx_axi_mm_bid_1024[i]        ),
                .O_AOU_TX_AXI_BRESP_1024                   ( w_aou_tx_axi_mm_bresp_1024[i]      ),
                .O_AOU_TX_AXI_BVALID_1024                  ( w_aou_tx_axi_mm_bvalid_1024[i]     ),
                .I_AOU_TX_AXI_BREADY_1024                  ( w_aou_tx_axi_mm_bready_1024[i]     ),

                .O_AOU_TX_AXI_RID                          ( w_aou_tx_axi_mm_rid[i]             ),
                .O_AOU_TX_AXI_RDLEN                        ( w_aou_tx_axi_mm_rdlen[i]           ),
                .O_AOU_TX_AXI_RDATA                        ( w_aou_tx_axi_mm_rdata[i]           ),
                .O_AOU_TX_AXI_RRESP                        ( w_aou_tx_axi_mm_rresp[i]           ),
                .O_AOU_TX_AXI_RLAST                        ( w_aou_tx_axi_mm_rlast[i]           ),
                .O_AOU_TX_AXI_RVALID                       ( w_aou_tx_axi_mm_rvalid[i]          ),
                .I_AOU_TX_AXI_RREADY                       ( w_aou_tx_axi_mm_rready[i]          ),

                .I_AXI_SPLIT_TR_MAX_AWBURSTLEN             ( w_axi_split_tr_max_awburstlen[i]   ),
                .I_AXI_SPLIT_TR_MAX_ARBURSTLEN             ( w_axi_split_tr_max_arburstlen[i]   ),

                .I_AXI_SLV_ID_MISMATCH_EN                  ( w_axi_slv_id_mismatch_en[i]        ),

                .O_ERROR_INFO_SPLIT_BID_MISMATCH_INFO      ( w_err_info_split_bid_mismatch[i]   ),
                .O_ERROR_INFO_RID_MISMATCH_INFO            ( w_err_info_rid_mismatch[i]         ),
                .O_ERROR_INFO_SPLIT_BID_MISMATCH_ERR_SET   ( w_err_split_bid_mismatch_set[i]    ),
                .O_ERROR_INFO_RID_MISMATCH_ERR_SET         ( w_err_rid_mismatch_set[i]          ),

                .O_EARLY_BRESP_DONE                        ( w_early_bresp_done[i]              ),
                .O_EARLY_BRESP_ERR_SET                     ( w_bresp_err[i]                     ),
                .O_EARLY_BRESP_ERR_TYPE                    ( w_bresp_err_type[i]                ),
                .O_EARLY_BRESP_ERR_ID                      ( w_bresp_err_id[i]                  ),
                .I_EARLY_BRESP_EN                          ( w_early_bresp_en[i]                ),
                .I_EARLY_BRESP_ALWAYS_EN                   ( w_early_bresp_always_en[i]         ),

                .I_EARLY_BRESP_WDT_EN                      ( w_early_bresp_wdt_en[i]            ), 
                .I_EARLY_BRESP_WDT_THRESHOLD               ( w_early_bresp_wdt_threshold        ),
                .O_EARLY_BRESP_TRANS_TIMEOUT_ERR           ( w_early_bresp_wdt_timeout_err[i]   ),

                .I_DEBUG_ERROR_INFO_UPPER_ADDR             ( w_debug_error_info_upper_addr[i]   ),
                .I_DEBUG_ERROR_INFO_LOWER_ADDR             ( w_debug_error_info_lower_addr[i]   ),
                .I_DEBUG_ERR_ACCESS_ENABLE                 ( w_debug_error_info_access_enable[i]),

                .I_AXI_AGGREGATOR_EN                       ( w_axi_aggregator_en[i]             ),

                .O_AXI_SLV_BID_MISMATCH_INFO               ( w_axi_slv_bid_mismatch_info[i]     ),
                .O_AXI_SLV_RID_MISMATCH_INFO               ( w_axi_slv_rid_mismatch_info[i]     ),
                .O_AXI_SLV_BID_MISMATCH_ERR_SET            ( w_axi_slv_bid_mismatch_err_set[i]  ),
                .O_AXI_SLV_RID_MISMATCH_ERR_SET            ( w_axi_slv_rid_mismatch_err_set[i]  ),

                .O_SLV_TR_COMPLETE                         ( w_slv_tr_complete[i]               ),
                .O_MST_TR_COMPLETE                         ( w_mst_tr_complete[i]               )
            );
        end
    endgenerate

    genvar j;
    generate
        for(j = RP_COUNT ; j < 4; j++) begin: gen_unused_sfr_tie
            assign  w_err_info_split_bid_mismatch[j]  = 1'b0;
            assign  w_err_info_rid_mismatch[j]        = 1'b0;
            assign  w_err_split_bid_mismatch_set[j]   = 1'b0;
            assign  w_err_rid_mismatch_set[j]         = 1'b0;

            assign  w_early_bresp_done[j]             = 1'b0;
            assign  w_early_bresp_wdt_timeout_err[j]  = 1'b0;
            assign  w_bresp_err[j]                    = 1'b0;
            assign  w_bresp_err_type[j]               = 1'b0;
            assign  w_bresp_err_id[j]                 = 1'b0;

            assign  w_axi_slv_bid_mismatch_info[j]    = 1'b0;
            assign  w_axi_slv_rid_mismatch_info[j]    = 1'b0;
            assign  w_axi_slv_bid_mismatch_err_set[j] = 1'b0;
            assign  w_axi_slv_rid_mismatch_err_set[j] = 1'b0;

            assign  w_slv_tr_complete[j]              = 1'b1;
            assign  w_mst_tr_complete[j]              = 1'b1;
        end
    endgenerate

    assign O_SLV_TR_COMPLETE = &w_slv_tr_complete;
    assign O_MST_TR_COMPLETE = &w_mst_tr_complete;

endmodule
