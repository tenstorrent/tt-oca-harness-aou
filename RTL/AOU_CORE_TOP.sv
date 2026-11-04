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
//  Module     : AOU_CORE_TOP
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_CORE_TOP
import packet_def_pkg::*;
#(
    parameter   RP_COUNT                    = 1,

    // FDI configuration selector. Single integer that picks the FDI data
    // bus widths for both PHYs and (in two-PHY builds) the per-PHY pairing.
    //
    //   FDI_CFG_SP_32B      -> WD0=256,  WD1=512   (single PHY 32B)
    //   FDI_CFG_SP_64B      -> WD0=512,  WD1=512   (single PHY 64B)
    //   FDI_CFG_SP_128B     -> WD0=1024, WD1=1024  (single PHY 128B)
    //   FDI_CFG_TP_32B_64B  -> WD0=256,  WD1=512   (two PHY, requires
    //                                                +define+TWO_PHY)
    //   FDI_CFG_TP_64B_128B -> WD0=512,  WD1=1024  (two PHY, requires
    //                                                +define+TWO_PHY)
    //
    // The internal FDI_IF_WD0 / FDI_IF_WD1 widths are derived as localparams
    // below and forwarded to the AOU_CORE submodule. Default matches the
    // legacy +define+FDI_32B single-PHY configuration so that existing
    // builds remain valid when the FDI_*B defines are removed. Consistency
    // between FDI_CONFIG and +define+TWO_PHY is the integrator's
    // responsibility (use an FDI_CFG_TP_* value if and only if
    // +define+TWO_PHY is set); no in-RTL elaboration check is added.
    parameter int FDI_CONFIG                = FDI_CFG_SP_32B,

    // Derived FDI data bus widths (bits). Single source of truth for both
    // top-level port sizing and the FIFO-depth ternaries below. Forwarded to
    // AOU_CORE via the same .FDI_IF_WD0 / .FDI_IF_WD1 parameters that the
    // internal hierarchy already consumes (no internal-module changes).
    localparam int FDI_IF_WD0 = (FDI_CONFIG == FDI_CFG_SP_32B     ) ? 256  :
                                (FDI_CONFIG == FDI_CFG_SP_64B     ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_SP_128B    ) ? 1024 :
                                (FDI_CONFIG == FDI_CFG_TP_32B_64B ) ? 256  :
                                (FDI_CONFIG == FDI_CFG_TP_64B_128B) ? 512  : 256,
    localparam int FDI_IF_WD1 = (FDI_CONFIG == FDI_CFG_SP_32B     ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_SP_64B     ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_SP_128B    ) ? 1024 :
                                (FDI_CONFIG == FDI_CFG_TP_32B_64B ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_TP_64B_128B) ? 1024 : 512,

    // FIFO depths default to 140 for 1024b (128B) FDI data paths, 88 otherwise.
    // Matches the original +define+FDI_128B branch which applied to both
    // single-PHY (FDI_IF_WD0 == 1024) and two-PHY (FDI_IF_WD1 == 1024) cases.
    parameter   RP0_RX_AW_FIFO_DEPTH        = 44,
    parameter   RP0_RX_AR_FIFO_DEPTH        = 44,
    parameter   RP0_RX_W_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP0_RX_R_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP0_RX_B_FIFO_DEPTH         = 44,

    parameter   RP1_RX_AW_FIFO_DEPTH        = 44,
    parameter   RP1_RX_AR_FIFO_DEPTH        = 44,
    parameter   RP1_RX_W_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP1_RX_R_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP1_RX_B_FIFO_DEPTH         = 44,

    parameter   RP2_RX_AW_FIFO_DEPTH        = 44,
    parameter   RP2_RX_AR_FIFO_DEPTH        = 44,
    parameter   RP2_RX_W_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP2_RX_R_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP2_RX_B_FIFO_DEPTH         = 44,

    parameter   RP3_RX_AW_FIFO_DEPTH        = 44,
    parameter   RP3_RX_AR_FIFO_DEPTH        = 44,
    parameter   RP3_RX_W_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP3_RX_R_FIFO_DEPTH         = ((FDI_IF_WD0 == 1024) || (FDI_IF_WD1 == 1024)) ? 140 : 88,
    parameter   RP3_RX_B_FIFO_DEPTH         = 44,

    parameter   RX_AW_FIFO_RS_EN            = 1,
    parameter   RX_AR_FIFO_RS_EN            = 1,
    parameter   RX_W_FIFO_RS_EN             = 1,
    parameter   RX_R_FIFO_RS_EN             = 1,
    parameter   RX_B_FIFO_RS_EN             = 1,

    parameter   RP0_AXI_DATA_WD             = 512,
    parameter   RP1_AXI_DATA_WD             = 512,
    parameter   RP2_AXI_DATA_WD             = 512,
    parameter   RP3_AXI_DATA_WD             = 512,

    // The widest data message AoU defines (WriteData1024/ReadData1024). The receiver
    // cannot know the remote die's AXI width, so the RX data path is sized for the
    // maximum and this is not an integration parameter.
    localparam  AXI_PEER_DIE_MAX_DATA_WD    = 1024,

    parameter   APB_ADDR_WD                 = 32,
    parameter   APB_DATA_WD                 = 32,


    // TX flit packer output stage: 0 combinational (current state),
    // 1 registered from the look-ahead state. See AOU_TX_CORE.
    parameter   TX_NXT_PACKING_EN           = 0,

    parameter   RP0_S_RD_MO_CNT             = 64,
    parameter   RP0_S_WR_MO_CNT             = 64,
    parameter   RP0_M_RD_MO_CNT             = 32,
    parameter   RP0_M_WR_MO_CNT             = 32,

    parameter   RP1_S_RD_MO_CNT             = 64,
    parameter   RP1_S_WR_MO_CNT             = 64,
    parameter   RP1_M_RD_MO_CNT             = 32,
    parameter   RP1_M_WR_MO_CNT             = 32,

    parameter   RP2_S_RD_MO_CNT             = 64,
    parameter   RP2_S_WR_MO_CNT             = 64,
    parameter   RP2_M_RD_MO_CNT             = 32,
    parameter   RP2_M_WR_MO_CNT             = 32,

    parameter   RP3_S_RD_MO_CNT             = 64,
    parameter   RP3_S_WR_MO_CNT             = 64,
    parameter   RP3_M_RD_MO_CNT             = 32,
    parameter   RP3_M_WR_MO_CNT             = 32,


    localparam  RP_AXI_DATA_WD_MAX          = max4(RP0_AXI_DATA_WD, RP1_AXI_DATA_WD, RP2_AXI_DATA_WD, RP3_AXI_DATA_WD),
    localparam  RP_AXI_STRB_WD_MAX          = RP_AXI_DATA_WD_MAX / 8,

    localparam  AXI_ADDR_WD                 = 64,
    localparam  AXI_ID_WD                   = 10,
    localparam  AXI_LEN_WD                  = 8,

    localparam  AXI_MAX_STRB_WD             = AXI_PEER_DIE_MAX_DATA_WD / 8,

    localparam int unsigned RP_AXI_DATA_WD[4]   = '{
        RP0_AXI_DATA_WD,
        RP1_AXI_DATA_WD,
        RP2_AXI_DATA_WD,
        RP3_AXI_DATA_WD
    },

    localparam int unsigned RP_AW_FIFO_DEPTH[4] = '{
        RP0_RX_AW_FIFO_DEPTH,
        RP1_RX_AW_FIFO_DEPTH,
        RP2_RX_AW_FIFO_DEPTH,
        RP3_RX_AW_FIFO_DEPTH
    },

    localparam int unsigned RP_AR_FIFO_DEPTH[4] = '{
        RP0_RX_AR_FIFO_DEPTH,
        RP1_RX_AR_FIFO_DEPTH,
        RP2_RX_AR_FIFO_DEPTH,
        RP3_RX_AR_FIFO_DEPTH
    },

    localparam int unsigned RP_R_FIFO_DEPTH[4] = '{
        RP0_RX_R_FIFO_DEPTH,
        RP1_RX_R_FIFO_DEPTH,
        RP2_RX_R_FIFO_DEPTH,
        RP3_RX_R_FIFO_DEPTH
    },

    localparam int unsigned RP_W_FIFO_DEPTH[4] = '{
        RP0_RX_W_FIFO_DEPTH,
        RP1_RX_W_FIFO_DEPTH,
        RP2_RX_W_FIFO_DEPTH,
        RP3_RX_W_FIFO_DEPTH
    },

    localparam int unsigned RP_B_FIFO_DEPTH[4] = '{
        RP0_RX_B_FIFO_DEPTH,
        RP1_RX_B_FIFO_DEPTH,
        RP2_RX_B_FIFO_DEPTH,
        RP3_RX_B_FIFO_DEPTH
    }

)
(
    input                                           I_CLK,
    input                                           I_RESETN,

    input                                           I_PCLK,
    input                                           I_PRESETN,

    //APB slave I/F
    input                                           I_AOU_APB_SI0_PSEL,
    input                                           I_AOU_APB_SI0_PENABLE,
    input   [APB_ADDR_WD-1:0]                       I_AOU_APB_SI0_PADDR,
    input                                           I_AOU_APB_SI0_PWRITE,
    input   [APB_DATA_WD-1:0]                       I_AOU_APB_SI0_PWDATA,

    output  [APB_DATA_WD-1:0]                       O_AOU_APB_SI0_PRDATA,
    output                                          O_AOU_APB_SI0_PREADY,
    output                                          O_AOU_APB_SI0_PSLVERR,

    //AXI MI I/F
    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_RX_AXI_M_ARID,
    output  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         O_AOU_RX_AXI_M_ARADDR,
    output  [RP_COUNT-1:0][AXI_LEN_WD-1:0]          O_AOU_RX_AXI_M_ARLEN,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_RX_AXI_M_ARSIZE,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_RX_AXI_M_ARBURST,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_M_ARLOCK,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_RX_AXI_M_ARCACHE,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_RX_AXI_M_ARPROT,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_RX_AXI_M_ARQOS,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_M_ARVALID,
    input   [RP_COUNT-1:0]                          I_AOU_RX_AXI_M_ARREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_TX_AXI_M_RID,
    input   [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]  I_AOU_TX_AXI_M_RDATA,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_TX_AXI_M_RRESP,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_M_RLAST,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_M_RVALID,
    output  [RP_COUNT-1:0]                          O_AOU_TX_AXI_M_RREADY,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_RX_AXI_M_AWID,
    output  [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         O_AOU_RX_AXI_M_AWADDR,
    output  [RP_COUNT-1:0][AXI_LEN_WD-1:0]          O_AOU_RX_AXI_M_AWLEN,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_RX_AXI_M_AWSIZE,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_RX_AXI_M_AWBURST,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_M_AWLOCK,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_RX_AXI_M_AWCACHE,
    output  [RP_COUNT-1:0][2:0]                     O_AOU_RX_AXI_M_AWPROT,
    output  [RP_COUNT-1:0][3:0]                     O_AOU_RX_AXI_M_AWQOS,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_M_AWVALID,
    input   [RP_COUNT-1:0]                          I_AOU_RX_AXI_M_AWREADY,

    output  [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]  O_AOU_RX_AXI_M_WDATA,
    output  [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]  O_AOU_RX_AXI_M_WSTRB,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_M_WLAST,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_M_WVALID,
    input   [RP_COUNT-1:0]                          I_AOU_RX_AXI_M_WREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_TX_AXI_M_BID,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_TX_AXI_M_BRESP,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_M_BVALID,
    output  [RP_COUNT-1:0]                          O_AOU_TX_AXI_M_BREADY,

    //AXI SI I/F
    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_TX_AXI_S_ARID,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         I_AOU_TX_AXI_S_ARADDR,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]          I_AOU_TX_AXI_S_ARLEN,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_TX_AXI_S_ARSIZE,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_TX_AXI_S_ARBURST,       //There is no burst field on AOU
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_S_ARLOCK,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_TX_AXI_S_ARCACHE,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_TX_AXI_S_ARPROT,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_TX_AXI_S_ARQOS,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_S_ARVALID,
    output  [RP_COUNT-1:0]                          O_AOU_TX_AXI_S_ARREADY,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_RX_AXI_S_RID,
    output  [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]  O_AOU_RX_AXI_S_RDATA,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_RX_AXI_S_RRESP,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_S_RLAST,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_S_RVALID,
    input   [RP_COUNT-1:0]                          I_AOU_RX_AXI_S_RREADY,

    input   [RP_COUNT-1:0][AXI_ID_WD-1:0]           I_AOU_TX_AXI_S_AWID,
    input   [RP_COUNT-1:0][AXI_ADDR_WD-1:0]         I_AOU_TX_AXI_S_AWADDR,
    input   [RP_COUNT-1:0][AXI_LEN_WD-1:0]          I_AOU_TX_AXI_S_AWLEN,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_TX_AXI_S_AWSIZE,
    input   [RP_COUNT-1:0][1:0]                     I_AOU_TX_AXI_S_AWBURST,       //There is no burst field on AOU
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_S_AWLOCK,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_TX_AXI_S_AWCACHE,
    input   [RP_COUNT-1:0][2:0]                     I_AOU_TX_AXI_S_AWPROT,
    input   [RP_COUNT-1:0][3:0]                     I_AOU_TX_AXI_S_AWQOS,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_S_AWVALID,
    output  [RP_COUNT-1:0]                          O_AOU_TX_AXI_S_AWREADY,

    input   [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0]  I_AOU_TX_AXI_S_WDATA,
    input   [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0]  I_AOU_TX_AXI_S_WSTRB,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_S_WLAST,
    input   [RP_COUNT-1:0]                          I_AOU_TX_AXI_S_WVALID,
    output  [RP_COUNT-1:0]                          O_AOU_TX_AXI_S_WREADY,

    output  [RP_COUNT-1:0][AXI_ID_WD-1:0]           O_AOU_RX_AXI_S_BID,
    output  [RP_COUNT-1:0][1:0]                     O_AOU_RX_AXI_S_BRESP,
    output  [RP_COUNT-1:0]                          O_AOU_RX_AXI_S_BVALID,
    input   [RP_COUNT-1:0]                          I_AOU_RX_AXI_S_BREADY,

    //Interface for AOU_RX_CORE FDI
    input                                                   I_FDI_PL_0_VALID,
    input   [FDI_IF_WD0-1: 0]                               I_FDI_PL_0_DATA,
    input                                                   I_FDI_PL_0_FLIT_CANCEL,

    //Interface for AOU_TX_CORE FDI
    input                                                   I_FDI_PL_0_TRDY,
    input                                                   I_FDI_PL_0_STALLREQ,
    input   [3:0]                                           I_FDI_PL_0_STATE_STS,
    output  [FDI_IF_WD0-1:0]                                O_FDI_LP_0_DATA,
    output                                                  O_FDI_LP_0_VALID,
    output                                                  O_FDI_LP_0_IRDY,
    output                                                  O_FDI_LP_0_STALLACK,

`ifdef TWO_PHY
    input                                                   I_PHY_TYPE,

    input                                                   I_FDI_PL_1_VALID,
    input   [FDI_IF_WD1-1: 0]                               I_FDI_PL_1_DATA,
    input                                                   I_FDI_PL_1_FLIT_CANCEL,

    input                                                   I_FDI_PL_1_TRDY,
    input                                                   I_FDI_PL_1_STALLREQ,
    input   [3:0]                                           I_FDI_PL_1_STATE_STS,
    output  [FDI_IF_WD1-1:0]                                O_FDI_LP_1_DATA,
    output                                                  O_FDI_LP_1_VALID,
    output                                                  O_FDI_LP_1_IRDY,
    output                                                  O_FDI_LP_1_STALLACK,
`endif
    //Interface for Error Handler
    output                                          INT_REQ_LINKRESET,
    output                                          INT_FDI_LINK_DOWN,

    output                                          INT_SI0_ID_MISMATCH,
    output                                          INT_MI0_ID_MISMATCH,

    output                                          INT_EARLY_RESP_ERR,
    output                                          INT_EARLY_WDT_ERR,

    output                                          INT_ACTIVATE_START,
    output                                          INT_DEACTIVATE_START,

    //Interface for UCIE_CORE
    input                                           I_INT_FSM_IN_ACTIVE,
    output                                          O_AOU_ACTIVATE_ST_DISABLED,
    output                                          O_AOU_ACTIVATE_ST_ENABLED,
    output                                          O_AOU_REQ_LINKRESET,
    // AOU_CON0.AOU_SW_RESET in effect: AOU_CORE is held in reset this cycle.
    // The FDI bringup controller releases a LinkError hold on it.
    output                                          O_SW_RESET,

    //DFT signal
    input                                           TIEL_DFT_MODESCAN
);
//----------------------------------------------------------------------------
    // Active FDI width for RX decode and PHY classification.
    // In both TWO_PHY and single-PHY configurations the relevant width is
    // max(FDI_IF_WD0, FDI_IF_WD1). This matches the original ifdef branches:
    //   TWO_PHY+FDI_32B   -> max(256,512)  = 512
    //   TWO_PHY+FDI_128B  -> max(512,1024) = 1024
    //   SP+FDI_32B        -> max(256,512)  = 512
    //   SP+FDI_64B        -> max(512,512)  = 512
    //   SP+FDI_128B       -> max(1024,512) = 1024
    localparam  FDI_ACTIVE_WD               = (FDI_IF_WD0 > FDI_IF_WD1) ? FDI_IF_WD0 : FDI_IF_WD1;
    localparam  PHY_TYPE                    = (FDI_ACTIVE_WD == 32*8)  ? 0:
                                              (FDI_ACTIVE_WD == 64*8)  ? 1:
                                              (FDI_ACTIVE_WD == 128*8) ? 2: 0;
    localparam  PHASE_CNT                   = 256*8/FDI_ACTIVE_WD;

    localparam  DEC_MULTI                   = (PHY_TYPE == 0) ? 1 : 4/PHASE_CNT;

    localparam  AW_AR_FIFO_WIDTH            = AXI_ID_WD + AXI_ADDR_WD + AXI_LEN_WD + 3 + 1 + 4 + 3 + 4;
    localparam  B_FIFO_WIDTH                = AXI_ID_WD + 2;
    localparam  R_FIFO_EXT_DATA_WIDTH       = AXI_ID_WD + 2 + 1;

    localparam  MAX_REQ_COUNT               = 4;
    localparam  MAX_WR_RESP_COUNT           = 12;
    localparam  DATA_DEC_CNT                = 4;
    //It should be configured to a value greater than the maximum burst length of the local bus.
    localparam  RP0_AGG_WCH_FIFO_DEPTH      = 16;
    localparam  RP1_AGG_WCH_FIFO_DEPTH      = 16; 
    localparam  RP2_AGG_WCH_FIFO_DEPTH      = 16; 
    localparam  RP3_AGG_WCH_FIFO_DEPTH      = 16;
//----------------------------------------------------------------------------
    logic                                   w_aou_apb_si0_psel       ;
    logic                                   w_aou_apb_si0_penable    ;
    logic  [APB_ADDR_WD-1:0]                w_aou_apb_si0_paddr      ;
    logic                                   w_aou_apb_si0_pwrite     ;
    logic  [APB_DATA_WD-1:0]                w_aou_apb_si0_pwdata     ;

    logic  [APB_DATA_WD-1:0]                w_aou_apb_si0_prdata     ;
    logic                                   w_aou_apb_si0_pready     ;
    logic                                   w_aou_apb_si0_pslverr    ;

//----------------------------------------------------------------------------
    logic    [RP_COUNT-1:0][AXI_ID_WD-1:0]  w_aou_rx_wlast_gen_awid         ;
    logic    [RP_COUNT-1:0][AXI_ADDR_WD-1:0]w_aou_rx_wlast_gen_awaddr       ;
    logic    [RP_COUNT-1:0][AXI_LEN_WD-1:0] w_aou_rx_wlast_gen_awlen        ;
    logic    [RP_COUNT-1:0][2:0]            w_aou_rx_wlast_gen_awsize       ;
    logic    [RP_COUNT-1:0]                 w_aou_rx_wlast_gen_awlock       ;
    logic    [RP_COUNT-1:0][3:0]            w_aou_rx_wlast_gen_awcache      ;
    logic    [RP_COUNT-1:0][2:0]            w_aou_rx_wlast_gen_awprot       ;
    logic    [RP_COUNT-1:0][3:0]            w_aou_rx_wlast_gen_awqos        ;
    logic    [RP_COUNT-1:0]                 w_aou_rx_wlast_gen_awvalid      ;
    logic    [RP_COUNT-1:0]                 w_aou_rx_wlast_gen_awready      ;

    logic    [RP_COUNT-1:0][1024-1:0]       w_aou_rx_wlast_gen_wdata        ;
    logic    [RP_COUNT-1:0][128-1:0]        w_aou_rx_wlast_gen_wstrb        ;
    logic    [RP_COUNT-1:0]                 w_aou_rx_wlast_gen_wvalid       ;
    logic    [RP_COUNT-1:0]                 w_aou_rx_wlast_gen_wready       ;

    logic    [RP_COUNT-1:0][1:0]            w_aou_rx_wlast_gen_wdlength     ;
    logic    [RP_COUNT-1:0]                 w_aou_rx_wlast_gen_wdataf       ;
    logic    [RP_COUNT-1:0][1:0]            w_aou_rx_axi_s_rdlength         ;

    logic    [RP_COUNT-1:0][AXI_ID_WD-1:0]  w_early_bresp_ctrl_bid          ;
    logic    [RP_COUNT-1:0][1:0]            w_early_bresp_ctrl_bresp        ;
    logic    [RP_COUNT-1:0]                 w_early_bresp_ctrl_bvalid       ;
    logic    [RP_COUNT-1:0]                 w_early_bresp_ctrl_bready       ;

//----------------------------------------------------------------------------
    logic   [RP_COUNT-1:0][AXI_ID_WD-1:0]   w_aou_rx_axi_mm_arid            ;
    logic   [RP_COUNT-1:0][AXI_ADDR_WD-1:0] w_aou_rx_axi_mm_araddr          ;
    logic   [RP_COUNT-1:0][AXI_LEN_WD-1:0]  w_aou_rx_axi_mm_arlen           ;
    logic   [RP_COUNT-1:0][2:0]             w_aou_rx_axi_mm_arsize          ;
    logic   [RP_COUNT-1:0][1:0]             w_aou_rx_axi_mm_arburst         ;
    logic   [RP_COUNT-1:0]                  w_aou_rx_axi_mm_arlock          ;
    logic   [RP_COUNT-1:0][3:0]             w_aou_rx_axi_mm_arcache         ;
    logic   [RP_COUNT-1:0][2:0]             w_aou_rx_axi_mm_arprot          ;
    logic   [RP_COUNT-1:0][3:0]             w_aou_rx_axi_mm_arqos           ;
    logic   [RP_COUNT-1:0]                  w_aou_rx_axi_mm_arvalid         ;
    logic   [RP_COUNT-1:0]                  w_aou_rx_axi_mm_arready         ;

//----------------------------------------------------------------------------
    logic                                   w_aou_rp0_aw_fifo_parity_error      ;
    logic                                   w_aou_rp0_w_fifo_parity_error       ;
    logic                                   w_aou_rp0_ar_fifo_parity_error      ;
    logic                                   w_aou_rp0_r_fifo_parity_error       ;
    logic                                   w_aou_rp0_b_fifo_parity_error       ;
//----------------------------------------------------------------------------
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0][AW_AR_FIFO_WIDTH-1:0]       w_rd_req_fifo_sdata;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0]                             w_rd_req_fifo_svalid;

    logic [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0][AW_AR_FIFO_WIDTH-1:0]       w_wr_req_fifo_sdata;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT -1:0]                             w_wr_req_fifo_svalid;

    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0] w_wr_data_fifo_sdata;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_MAX_STRB_WD -1:0]         w_wr_data_fifo_sdata_strb;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                               w_wr_data_fifo_sdata_wdataf;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][1:0]                          w_wr_data_fifo_sdlen;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                               w_wr_data_fifo_svalid;

    logic [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_WR_RESP_COUNT -1:0][B_FIFO_WIDTH-1:0]       w_wr_resp_fifo_sdata;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_WR_RESP_COUNT -1:0]                         w_wr_resp_fifo_svalid;

    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0] w_rd_data_fifo_sdata;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][R_FIFO_EXT_DATA_WIDTH -1:0]   w_rd_data_fifo_ext_sdata;
    logic [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                               w_rd_data_fifo_svalid;

//----------------------------------------------------------------------------
    logic                                   w_err_info_rid_mismatch_err;
    logic                                   w_err_info_split_bid_mismatch_err;
    logic                                   w_axi_slv_bid_mismatch_error;
    logic                                   w_axi_slv_rid_mismatch_error;

    logic                                   w_int_early_resp_err;
    logic                                   w_int_early_wdt_err;
    logic                                   w_int_fdi_link_down;
    logic                                   w_int_activate_start_level;
    logic                                   w_int_deactivate_start_level;

    logic                                   w_int_aou_req_linkreset;
//----------------------------------------------------------------------------
    logic                                   w_sw_reset;
    logic                                   r_sw_reset;
    logic                                   w_DFTED_sw_resetn;
    logic                                   w_aou_sw_reset_scan_buf;

    logic [RP_COUNT-1:0]                    w_aou_rx_fifo_rready;
    logic [RP_COUNT-1:0][AXI_ID_WD-1:0]     w_aou_rx_axi_s_rid;
    logic [RP_COUNT-1:0][1:0]               w_aou_rx_axi_s_rresp;
    logic [RP_COUNT-1:0]                    w_aou_rx_axi_s_rlast;
    logic [RP_COUNT-1:0]                    w_aou_rx_axi_s_rvalid;
    logic [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]    w_rd_data_fifo_mdata;
    logic [RP_COUNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]    w_aou_rx_axi_s_rdata;

    AOU_SOC_BUF dft_persistent_buf_scan_resetn_sw (
        .I_A   ( 1'b1                       ),
        .O_Y   ( w_aou_sw_reset_scan_buf    )
    );

    AOU_SOC_GFMUX_LVT u_sw_reset_mux (
        .I_SEL ( TIEL_DFT_MODESCAN          ),

        .I_A   ( ~r_sw_reset & I_RESETN     ),
        .I_B   ( w_aou_sw_reset_scan_buf    ),

        .O_Y   ( w_DFTED_sw_resetn          )
    );

    always @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_sw_reset <= 1'b0;
        end else begin
            r_sw_reset <= w_sw_reset;
        end
    end

//----------------------------------------------------------------------------

    ASYNC_APB_BRIDGE #(
        .APB_ADDR_WD      ( APB_ADDR_WD                 )
    )u_async_apb_bridge
    (
        .I_S_PCLK         ( I_PCLK                      ),
        .I_S_PRESETN      ( I_PRESETN                   ),

        .I_S_PSEL         ( I_AOU_APB_SI0_PSEL          ),
        .I_S_PENABLE      ( I_AOU_APB_SI0_PENABLE       ),
        .I_S_PADDR        ( I_AOU_APB_SI0_PADDR         ),
        .I_S_PWRITE       ( I_AOU_APB_SI0_PWRITE        ),
        .I_S_PWDATA       ( I_AOU_APB_SI0_PWDATA        ),

        .O_S_PRDATA       ( O_AOU_APB_SI0_PRDATA        ),
        .O_S_PREADY       ( O_AOU_APB_SI0_PREADY        ),
        .O_S_PSLVERR      ( O_AOU_APB_SI0_PSLVERR       ),

        .I_M_PCLK         ( I_CLK                       ),
        .I_M_PRESETN      ( I_RESETN                    ),

        .O_M_PSEL         ( w_aou_apb_si0_psel          ),
        .O_M_PENABLE      ( w_aou_apb_si0_penable       ),
        .O_M_PADDR        ( w_aou_apb_si0_paddr         ),
        .O_M_PWRITE       ( w_aou_apb_si0_pwrite        ),
        .O_M_PWDATA       ( w_aou_apb_si0_pwdata        ),

        .I_M_PRDATA       ( w_aou_apb_si0_prdata        ),
        .I_M_PREADY       ( w_aou_apb_si0_pready        ),
        .I_M_PSLVERR      ( w_aou_apb_si0_pslverr       )
    );

//----------------------------------------------------------------------------
    AOU_CORE #(
        .RP0_RX_AW_FIFO_DEPTH       ( RP0_RX_AW_FIFO_DEPTH      ),
        .RP0_RX_AR_FIFO_DEPTH       ( RP0_RX_AR_FIFO_DEPTH      ),
        .RP0_RX_W_FIFO_DEPTH        ( RP0_RX_W_FIFO_DEPTH       ),
        .RP0_RX_R_FIFO_DEPTH        ( RP0_RX_R_FIFO_DEPTH       ),
        .RP0_RX_B_FIFO_DEPTH        ( RP0_RX_B_FIFO_DEPTH       ),

        .RP1_RX_AW_FIFO_DEPTH       ( RP1_RX_AW_FIFO_DEPTH      ),
        .RP1_RX_AR_FIFO_DEPTH       ( RP1_RX_AR_FIFO_DEPTH      ),
        .RP1_RX_W_FIFO_DEPTH        ( RP1_RX_W_FIFO_DEPTH       ),
        .RP1_RX_R_FIFO_DEPTH        ( RP1_RX_R_FIFO_DEPTH       ),
        .RP1_RX_B_FIFO_DEPTH        ( RP1_RX_B_FIFO_DEPTH       ),

        .RP2_RX_AW_FIFO_DEPTH       ( RP2_RX_AW_FIFO_DEPTH      ),
        .RP2_RX_AR_FIFO_DEPTH       ( RP2_RX_AR_FIFO_DEPTH      ),
        .RP2_RX_W_FIFO_DEPTH        ( RP2_RX_W_FIFO_DEPTH       ),
        .RP2_RX_R_FIFO_DEPTH        ( RP2_RX_R_FIFO_DEPTH       ),
        .RP2_RX_B_FIFO_DEPTH        ( RP2_RX_B_FIFO_DEPTH       ),

        .RP3_RX_AW_FIFO_DEPTH       ( RP3_RX_AW_FIFO_DEPTH      ),
        .RP3_RX_AR_FIFO_DEPTH       ( RP3_RX_AR_FIFO_DEPTH      ),
        .RP3_RX_W_FIFO_DEPTH        ( RP3_RX_W_FIFO_DEPTH       ),
        .RP3_RX_R_FIFO_DEPTH        ( RP3_RX_R_FIFO_DEPTH       ),
        .RP3_RX_B_FIFO_DEPTH        ( RP3_RX_B_FIFO_DEPTH       ),

        .RP0_AXI_DATA_WD            ( RP0_AXI_DATA_WD           ),
        .RP1_AXI_DATA_WD            ( RP1_AXI_DATA_WD           ),
        .RP2_AXI_DATA_WD            ( RP2_AXI_DATA_WD           ),
        .RP3_AXI_DATA_WD            ( RP3_AXI_DATA_WD           ),

        .RP0_AGG_WCH_FIFO_DEPTH     ( RP0_AGG_WCH_FIFO_DEPTH    ), 
        .RP1_AGG_WCH_FIFO_DEPTH     ( RP1_AGG_WCH_FIFO_DEPTH    ), 
        .RP2_AGG_WCH_FIFO_DEPTH     ( RP2_AGG_WCH_FIFO_DEPTH    ), 
        .RP3_AGG_WCH_FIFO_DEPTH     ( RP3_AGG_WCH_FIFO_DEPTH    ),

        .APB_ADDR_WD                ( APB_ADDR_WD               ),
        .APB_DATA_WD                ( APB_DATA_WD               ),


        .TX_NXT_PACKING_EN          ( TX_NXT_PACKING_EN         ),

        .RP0_S_RD_MO_CNT            ( RP0_S_RD_MO_CNT           ),
        .RP0_S_WR_MO_CNT            ( RP0_S_WR_MO_CNT           ),
        .RP0_M_RD_MO_CNT            ( RP0_M_RD_MO_CNT           ),
        .RP0_M_WR_MO_CNT            ( RP0_M_WR_MO_CNT           ),

        .RP1_S_RD_MO_CNT            ( RP1_S_RD_MO_CNT           ),
        .RP1_S_WR_MO_CNT            ( RP1_S_WR_MO_CNT           ),
        .RP1_M_RD_MO_CNT            ( RP1_M_RD_MO_CNT           ),
        .RP1_M_WR_MO_CNT            ( RP1_M_WR_MO_CNT           ),

        .RP2_S_RD_MO_CNT            ( RP2_S_RD_MO_CNT           ),
        .RP2_S_WR_MO_CNT            ( RP2_S_WR_MO_CNT           ),
        .RP2_M_RD_MO_CNT            ( RP2_M_RD_MO_CNT           ),
        .RP2_M_WR_MO_CNT            ( RP2_M_WR_MO_CNT           ),

        .RP3_S_RD_MO_CNT            ( RP3_S_RD_MO_CNT           ),
        .RP3_S_WR_MO_CNT            ( RP3_S_WR_MO_CNT           ),
        .RP3_M_RD_MO_CNT            ( RP3_M_RD_MO_CNT           ),
        .RP3_M_WR_MO_CNT            ( RP3_M_WR_MO_CNT           ),

        .AW_AR_FIFO_WIDTH           ( AW_AR_FIFO_WIDTH          ),
        .B_FIFO_WIDTH               ( B_FIFO_WIDTH              ),
        .R_FIFO_EXT_DATA_WIDTH      ( R_FIFO_EXT_DATA_WIDTH     ),

        .FDI_IF_WD0                 ( FDI_IF_WD0                ),
        .FDI_IF_WD1                 ( FDI_IF_WD1                ),
        .RP_COUNT                   ( RP_COUNT                  ),
        .DEC_MULTI                  ( DEC_MULTI                 ),
        .PHY_TYPE                   ( PHY_TYPE                  )

    ) u_aou_core
    (
        .I_CLK                              ( I_CLK                             ),
        .I_RESETN                           ( w_DFTED_sw_resetn                 ),

        .I_AOU_APB_SI0_PSEL                 ( w_aou_apb_si0_psel                ),
        .I_AOU_APB_SI0_PENABLE              ( w_aou_apb_si0_penable             ),
        .I_AOU_APB_SI0_PADDR                ( w_aou_apb_si0_paddr               ),
        .I_AOU_APB_SI0_PWRITE               ( w_aou_apb_si0_pwrite              ),
        .I_AOU_APB_SI0_PWDATA               ( w_aou_apb_si0_pwdata              ),

        .O_AOU_APB_SI0_PRDATA               ( w_aou_apb_si0_prdata              ),
        .O_AOU_APB_SI0_PREADY               ( w_aou_apb_si0_pready              ),
        .O_AOU_APB_SI0_PSLVERR              ( w_aou_apb_si0_pslverr             ),

        .O_AOU_RX_AXI_M_ARID                ( O_AOU_RX_AXI_M_ARID               ),
        .O_AOU_RX_AXI_M_ARADDR              ( O_AOU_RX_AXI_M_ARADDR             ),
        .O_AOU_RX_AXI_M_ARLEN               ( O_AOU_RX_AXI_M_ARLEN              ),
        .O_AOU_RX_AXI_M_ARSIZE              ( O_AOU_RX_AXI_M_ARSIZE             ),
        .O_AOU_RX_AXI_M_ARBURST             ( O_AOU_RX_AXI_M_ARBURST            ),
        .O_AOU_RX_AXI_M_ARLOCK              ( O_AOU_RX_AXI_M_ARLOCK             ),
        .O_AOU_RX_AXI_M_ARCACHE             ( O_AOU_RX_AXI_M_ARCACHE            ),
        .O_AOU_RX_AXI_M_ARPROT              ( O_AOU_RX_AXI_M_ARPROT             ),
        .O_AOU_RX_AXI_M_ARQOS               ( O_AOU_RX_AXI_M_ARQOS              ),
        .O_AOU_RX_AXI_M_ARVALID             ( O_AOU_RX_AXI_M_ARVALID            ),
        .I_AOU_RX_AXI_M_ARREADY             ( I_AOU_RX_AXI_M_ARREADY            ),

        .I_AOU_TX_AXI_M_RID                 ( I_AOU_TX_AXI_M_RID                ),
        .I_AOU_TX_AXI_M_RDATA               ( I_AOU_TX_AXI_M_RDATA              ),
        .I_AOU_TX_AXI_M_RRESP               ( I_AOU_TX_AXI_M_RRESP              ),
        .I_AOU_TX_AXI_M_RLAST               ( I_AOU_TX_AXI_M_RLAST              ),
        .I_AOU_TX_AXI_M_RVALID              ( I_AOU_TX_AXI_M_RVALID             ),
        .O_AOU_TX_AXI_M_RREADY              ( O_AOU_TX_AXI_M_RREADY             ),

        .O_AOU_RX_AXI_M_AWID                ( O_AOU_RX_AXI_M_AWID               ),
        .O_AOU_RX_AXI_M_AWADDR              ( O_AOU_RX_AXI_M_AWADDR             ),
        .O_AOU_RX_AXI_M_AWLEN               ( O_AOU_RX_AXI_M_AWLEN              ),
        .O_AOU_RX_AXI_M_AWSIZE              ( O_AOU_RX_AXI_M_AWSIZE             ),
        .O_AOU_RX_AXI_M_AWBURST             ( O_AOU_RX_AXI_M_AWBURST            ),
        .O_AOU_RX_AXI_M_AWLOCK              ( O_AOU_RX_AXI_M_AWLOCK             ),
        .O_AOU_RX_AXI_M_AWCACHE             ( O_AOU_RX_AXI_M_AWCACHE            ),
        .O_AOU_RX_AXI_M_AWPROT              ( O_AOU_RX_AXI_M_AWPROT             ),
        .O_AOU_RX_AXI_M_AWQOS               ( O_AOU_RX_AXI_M_AWQOS              ),
        .O_AOU_RX_AXI_M_AWVALID             ( O_AOU_RX_AXI_M_AWVALID            ),
        .I_AOU_RX_AXI_M_AWREADY             ( I_AOU_RX_AXI_M_AWREADY            ),

        .O_AOU_RX_AXI_M_WDATA               ( O_AOU_RX_AXI_M_WDATA              ),
        .O_AOU_RX_AXI_M_WSTRB               ( O_AOU_RX_AXI_M_WSTRB              ),
        .O_AOU_RX_AXI_M_WLAST               ( O_AOU_RX_AXI_M_WLAST              ),
        .O_AOU_RX_AXI_M_WVALID              ( O_AOU_RX_AXI_M_WVALID             ),
        .I_AOU_RX_AXI_M_WREADY              ( I_AOU_RX_AXI_M_WREADY             ),

        .I_AOU_TX_AXI_M_BID                 ( I_AOU_TX_AXI_M_BID                ),
        .I_AOU_TX_AXI_M_BRESP               ( I_AOU_TX_AXI_M_BRESP              ),
        .I_AOU_TX_AXI_M_BVALID              ( I_AOU_TX_AXI_M_BVALID             ),
        .O_AOU_TX_AXI_M_BREADY              ( O_AOU_TX_AXI_M_BREADY             ),

        .I_AOU_TX_AXI_S_ARID                ( I_AOU_TX_AXI_S_ARID               ),
        .I_AOU_TX_AXI_S_ARADDR              ( I_AOU_TX_AXI_S_ARADDR             ),
        .I_AOU_TX_AXI_S_ARLEN               ( I_AOU_TX_AXI_S_ARLEN              ),
        .I_AOU_TX_AXI_S_ARSIZE              ( I_AOU_TX_AXI_S_ARSIZE             ),
        .I_AOU_TX_AXI_S_ARBURST             ( I_AOU_TX_AXI_S_ARBURST            ),
        .I_AOU_TX_AXI_S_ARLOCK              ( I_AOU_TX_AXI_S_ARLOCK             ),
        .I_AOU_TX_AXI_S_ARCACHE             ( I_AOU_TX_AXI_S_ARCACHE            ),
        .I_AOU_TX_AXI_S_ARPROT              ( I_AOU_TX_AXI_S_ARPROT             ),
        .I_AOU_TX_AXI_S_ARQOS               ( I_AOU_TX_AXI_S_ARQOS              ),
        .I_AOU_TX_AXI_S_ARVALID             ( I_AOU_TX_AXI_S_ARVALID            ),
        .O_AOU_TX_AXI_S_ARREADY             ( O_AOU_TX_AXI_S_ARREADY            ),
             
        .I_AOU_RX_AXI_S_RID                 ( w_aou_rx_axi_s_rid                ),
        .I_AOU_RX_AXI_S_RDATA               ( w_rd_data_fifo_mdata              ),
        .I_AOU_RX_AXI_S_RRESP               ( w_aou_rx_axi_s_rresp              ),
        .I_AOU_RX_AXI_S_RLAST               ( w_aou_rx_axi_s_rlast              ),
        .I_AOU_RX_AXI_S_RDLENGTH            ( w_aou_rx_axi_s_rdlength           ),
        .I_AOU_RX_AXI_S_RVALID              ( w_aou_rx_axi_s_rvalid             ),
        .I_AOU_RX_AXI_S_RREADY              ( I_AOU_RX_AXI_S_RREADY             ),
        .O_AOU_RX_AXI_S_RID                 ( O_AOU_RX_AXI_S_RID                ),
        .O_AOU_RX_AXI_S_RRESP               ( O_AOU_RX_AXI_S_RRESP              ),
        .O_AOU_RX_AXI_S_RLAST               ( O_AOU_RX_AXI_S_RLAST              ),
        .O_AOU_RX_AXI_S_RDATA               ( w_aou_rx_axi_s_rdata              ),
        .O_AOU_RX_FIFO_RREADY               ( w_aou_rx_fifo_rready              ),
 
        .I_AOU_TX_AXI_S_AWID                ( I_AOU_TX_AXI_S_AWID               ),
        .I_AOU_TX_AXI_S_AWADDR              ( I_AOU_TX_AXI_S_AWADDR             ),
        .I_AOU_TX_AXI_S_AWLEN               ( I_AOU_TX_AXI_S_AWLEN              ),
        .I_AOU_TX_AXI_S_AWSIZE              ( I_AOU_TX_AXI_S_AWSIZE             ),
        .I_AOU_TX_AXI_S_AWBURST             ( I_AOU_TX_AXI_S_AWBURST            ),
        .I_AOU_TX_AXI_S_AWLOCK              ( I_AOU_TX_AXI_S_AWLOCK             ),
        .I_AOU_TX_AXI_S_AWCACHE             ( I_AOU_TX_AXI_S_AWCACHE            ),
        .I_AOU_TX_AXI_S_AWPROT              ( I_AOU_TX_AXI_S_AWPROT             ),
        .I_AOU_TX_AXI_S_AWQOS               ( I_AOU_TX_AXI_S_AWQOS              ),
        .I_AOU_TX_AXI_S_AWVALID             ( I_AOU_TX_AXI_S_AWVALID            ),
        .O_AOU_TX_AXI_S_AWREADY             ( O_AOU_TX_AXI_S_AWREADY            ),

        .I_AOU_TX_AXI_S_WDATA               ( I_AOU_TX_AXI_S_WDATA              ),
        .I_AOU_TX_AXI_S_WSTRB               ( I_AOU_TX_AXI_S_WSTRB              ),
        .I_AOU_TX_AXI_S_WLAST               ( I_AOU_TX_AXI_S_WLAST              ),
        .I_AOU_TX_AXI_S_WVALID              ( I_AOU_TX_AXI_S_WVALID             ),
        .O_AOU_TX_AXI_S_WREADY              ( O_AOU_TX_AXI_S_WREADY             ),

        .O_AOU_RX_AXI_S_BID                 ( O_AOU_RX_AXI_S_BID                ),
        .O_AOU_RX_AXI_S_BRESP               ( O_AOU_RX_AXI_S_BRESP              ),
        .O_AOU_RX_AXI_S_BVALID              ( O_AOU_RX_AXI_S_BVALID             ),
        .I_AOU_RX_AXI_S_BREADY              ( I_AOU_RX_AXI_S_BREADY             ),

        .I_AOU_RX_WLAST_GEN_AWID            ( w_aou_rx_wlast_gen_awid           ),
        .I_AOU_RX_WLAST_GEN_AWADDR          ( w_aou_rx_wlast_gen_awaddr         ),
        .I_AOU_RX_WLAST_GEN_AWLEN           ( w_aou_rx_wlast_gen_awlen          ),
        .I_AOU_RX_WLAST_GEN_AWSIZE          ( w_aou_rx_wlast_gen_awsize         ),
        .I_AOU_RX_WLAST_GEN_AWLOCK          ( w_aou_rx_wlast_gen_awlock         ),
        .I_AOU_RX_WLAST_GEN_AWCACHE         ( w_aou_rx_wlast_gen_awcache        ),
        .I_AOU_RX_WLAST_GEN_AWPROT          ( w_aou_rx_wlast_gen_awprot         ),
        .I_AOU_RX_WLAST_GEN_AWQOS           ( w_aou_rx_wlast_gen_awqos          ),
        .I_AOU_RX_WLAST_GEN_AWVALID         ( w_aou_rx_wlast_gen_awvalid        ),
        .O_AOU_RX_WLAST_GEN_AWREADY         ( w_aou_rx_wlast_gen_awready        ),

        .I_AOU_RX_WLAST_GEN_WDLENGTH        ( w_aou_rx_wlast_gen_wdlength       ),
        .I_AOU_RX_WLAST_GEN_WDATAF          ( w_aou_rx_wlast_gen_wdataf         ),
        .I_AOU_RX_WLAST_GEN_WDATA           ( w_aou_rx_wlast_gen_wdata          ),
        .I_AOU_RX_WLAST_GEN_WSTRB           ( w_aou_rx_wlast_gen_wstrb          ),
        .I_AOU_RX_WLAST_GEN_WVALID          ( w_aou_rx_wlast_gen_wvalid         ),
        .O_AOU_RX_WLAST_GEN_WREADY          ( w_aou_rx_wlast_gen_wready         ),

        .I_EARLY_BRESP_CTRL_BID             ( w_early_bresp_ctrl_bid            ),
        .I_EARLY_BRESP_CTRL_BRESP           ( w_early_bresp_ctrl_bresp          ),
        .I_EARLY_BRESP_CTRL_BVALID          ( w_early_bresp_ctrl_bvalid         ),
        .O_EARLY_BRESP_CTRL_BREADY          ( w_early_bresp_ctrl_bready         ),

        .I_AOU_RX_AXI_MM_ARID               ( w_aou_rx_axi_mm_arid              ),
        .I_AOU_RX_AXI_MM_ARADDR             ( w_aou_rx_axi_mm_araddr            ),
        .I_AOU_RX_AXI_MM_ARLEN              ( w_aou_rx_axi_mm_arlen             ),
        .I_AOU_RX_AXI_MM_ARSIZE             ( w_aou_rx_axi_mm_arsize            ),
        .I_AOU_RX_AXI_MM_ARLOCK             ( w_aou_rx_axi_mm_arlock            ),
        .I_AOU_RX_AXI_MM_ARCACHE            ( w_aou_rx_axi_mm_arcache           ),
        .I_AOU_RX_AXI_MM_ARPROT             ( w_aou_rx_axi_mm_arprot            ),
        .I_AOU_RX_AXI_MM_ARQOS              ( w_aou_rx_axi_mm_arqos             ),
        .I_AOU_RX_AXI_MM_ARVALID            ( w_aou_rx_axi_mm_arvalid           ),
        .O_AOU_RX_AXI_MM_ARREADY            ( w_aou_rx_axi_mm_arready           ),

        .I_FDI_PL_0_VALID                   ( I_FDI_PL_0_VALID                    ),
        .I_FDI_PL_0_DATA                    ( I_FDI_PL_0_DATA                     ),
        .I_FDI_PL_0_FLIT_CANCEL             ( I_FDI_PL_0_FLIT_CANCEL              ),

        .I_FDI_PL_0_TRDY                    ( I_FDI_PL_0_TRDY                     ),
        .I_FDI_PL_0_STALLREQ                ( I_FDI_PL_0_STALLREQ                 ),
        .I_FDI_PL_0_STATE_STS               ( I_FDI_PL_0_STATE_STS                ),
        .O_FDI_LP_0_DATA                    ( O_FDI_LP_0_DATA                     ),
        .O_FDI_LP_0_VALID                   ( O_FDI_LP_0_VALID                    ),
        .O_FDI_LP_0_IRDY                    ( O_FDI_LP_0_IRDY                     ),
        .O_FDI_LP_0_STALLACK                ( O_FDI_LP_0_STALLACK                 ),

`ifdef TWO_PHY
        .I_PHY_TYPE                         ( I_PHY_TYPE                        ),

        .I_FDI_PL_1_VALID                   ( I_FDI_PL_1_VALID                    ),
        .I_FDI_PL_1_DATA                    ( I_FDI_PL_1_DATA                     ),
        .I_FDI_PL_1_FLIT_CANCEL             ( I_FDI_PL_1_FLIT_CANCEL              ),

        .I_FDI_PL_1_TRDY                    ( I_FDI_PL_1_TRDY                     ),
        .I_FDI_PL_1_STALLREQ                ( I_FDI_PL_1_STALLREQ                 ),
        .I_FDI_PL_1_STATE_STS               ( I_FDI_PL_1_STATE_STS                ),
        .O_FDI_LP_1_DATA                    ( O_FDI_LP_1_DATA                     ),
        .O_FDI_LP_1_VALID                   ( O_FDI_LP_1_VALID                    ),
        .O_FDI_LP_1_IRDY                    ( O_FDI_LP_1_IRDY                     ),
        .O_FDI_LP_1_STALLACK                ( O_FDI_LP_1_STALLACK                 ),

`endif

        .O_RD_REQ_FIFO_SDATA                ( w_rd_req_fifo_sdata               ),
        .O_RD_REQ_FIFO_SVALID               ( w_rd_req_fifo_svalid              ),

        .O_WR_REQ_FIFO_SDATA                ( w_wr_req_fifo_sdata               ),
        .O_WR_REQ_FIFO_SVALID               ( w_wr_req_fifo_svalid              ),

        .O_WR_DATA_FIFO_SDATA               ( w_wr_data_fifo_sdata              ),
        .O_WR_DATA_FIFO_SDATA_STRB          ( w_wr_data_fifo_sdata_strb         ),
        .O_WR_DATA_FIFO_SDATA_WDATAF        ( w_wr_data_fifo_sdata_wdataf       ),
        .O_WR_DATA_FIFO_SVALID              ( w_wr_data_fifo_svalid             ),

        .O_WR_RESP_FIFO_SDATA               ( w_wr_resp_fifo_sdata              ),
        .O_WR_RESP_FIFO_SVALID              ( w_wr_resp_fifo_svalid             ),

        .O_RD_DATA_FIFO_SDATA               ( w_rd_data_fifo_sdata              ),
        .O_RD_DATA_FIFO_EXT_SDATA           ( w_rd_data_fifo_ext_sdata          ),
        .O_RD_DATA_FIFO_SVALID              ( w_rd_data_fifo_svalid             ),

        .O_ERR_INFO_RID_MISMATCH_ERR        ( w_err_info_rid_mismatch_err       ),
        .O_ERR_INFO_SPLIT_BID_MISMATCH_ERR  ( w_err_info_split_bid_mismatch_err ),

        .O_AXI_SLV_RID_MISMATCH_ERROR       ( w_axi_slv_rid_mismatch_error      ),
        .O_AXI_SLV_BID_MISMATCH_ERROR       ( w_axi_slv_bid_mismatch_error      ),

        .O_INT_EARLY_RESP_ERR               ( w_int_early_resp_err              ),
        .O_INT_EARLY_WDT_ERR                ( w_int_early_wdt_err               ),

        .O_INT_ACTIVATE_START               ( w_int_activate_start_level        ),
        .O_INT_DEACTIVATE_START             ( w_int_deactivate_start_level      ),
        .O_INT_FDI_LINK_DOWN                ( w_int_fdi_link_down               ),

        .I_INT_FSM_IN_ACTIVE                ( I_INT_FSM_IN_ACTIVE               ),
        .O_AOU_ACTIVATE_ST_DISABLED         ( O_AOU_ACTIVATE_ST_DISABLED        ),
        .O_AOU_ACTIVATE_ST_ENABLED          ( O_AOU_ACTIVATE_ST_ENABLED         ),
        .O_AOU_REQ_LINKRESET                ( w_int_aou_req_linkreset           ),

        .O_SW_RESET                         ( w_sw_reset                        ),
        .O_SLV_TR_COMPLETE                  (                                   ),
        .O_MST_TR_COMPLETE                  (                                   ),
        .O_AOU_RX_AXI_S_RVALID_BLOCKED      ( O_AOU_RX_AXI_S_RVALID             )
    );
//----------------------------------------------------------------------------
    // The RX FIFOs share the core reset (I_RESETN and AOU_SW_RESET). Every
    // message they hold belongs to a transaction the core tracks, so a reset
    // that clears the core must clear them too: an entry kept across
    // AOU_SW_RESET would hold I_AOU_RX_FIFO_PENDING and block the next
    // activation, be presented on an AXI port as part of the wrong
    // transaction, and return credit on top of the full re-advertisement.
    genvar i;
    generate
        for(i = 0; i < RP_COUNT; i++) begin : gen_aou_fifo_rp

            AOU_FIFO_RP #(
                .AXI_PEER_DIE_MAX_DATA_WD           ( AXI_PEER_DIE_MAX_DATA_WD              ),
                .AXI_ID_WD                          ( AXI_ID_WD                             ),
                .AW_AR_FIFO_WIDTH                   ( AW_AR_FIFO_WIDTH                      ),
                .B_FIFO_WIDTH                       ( B_FIFO_WIDTH                          ),
                .R_FIFO_EXT_DATA_WIDTH              ( R_FIFO_EXT_DATA_WIDTH                 ),

                .AW_FIFO_DEPTH                      ( RP_AW_FIFO_DEPTH[i]                   ),
                .AR_FIFO_DEPTH                      ( RP_AR_FIFO_DEPTH[i]                   ),
                .W_FIFO_DEPTH                       ( RP_W_FIFO_DEPTH[i]                    ),
                .R_FIFO_DEPTH                       ( RP_R_FIFO_DEPTH[i]                    ),
                .B_FIFO_DEPTH                       ( RP_B_FIFO_DEPTH[i]                    ),

                .DEC_MULTI                          ( DEC_MULTI                             ),

                .AW_FWD_RS_EN                       ( RX_AW_FIFO_RS_EN                      ),
                .W_FWD_RS_EN                        ( RX_W_FIFO_RS_EN                       ),
                .B_FWD_RS_EN                        ( RX_B_FIFO_RS_EN                       ),
                .AR_FWD_RS_EN                       ( RX_AR_FIFO_RS_EN                      ),
                .R_FWD_RS_EN                        ( RX_R_FIFO_RS_EN                       )

            ) u_aou_fifo_rp
            (
                .I_CLK                              ( I_CLK                                 ),
                .I_RESETN                           ( w_DFTED_sw_resetn                     ),

                .I_WR_REQ_FIFO_SVALID               ( w_wr_req_fifo_svalid[i]               ),
                .I_WR_REQ_FIFO_SDATA                ( w_wr_req_fifo_sdata[i]                ),

                .I_WR_REQ_FIFO_MREADY               ( w_aou_rx_wlast_gen_awready[i]         ),
                .O_WR_REQ_FIFO_MDATA                ( {w_aou_rx_wlast_gen_awid[i], w_aou_rx_wlast_gen_awaddr[i], w_aou_rx_wlast_gen_awlen[i], w_aou_rx_wlast_gen_awsize[i], w_aou_rx_wlast_gen_awlock[i], w_aou_rx_wlast_gen_awcache[i], w_aou_rx_wlast_gen_awprot[i], w_aou_rx_wlast_gen_awqos[i]} ),
                .O_WR_REQ_FIFO_MVALID               ( w_aou_rx_wlast_gen_awvalid[i]         ),

                .I_WR_DATA_FIFO_SVALID              ( w_wr_data_fifo_svalid[i]              ),
                .I_WR_DATA_FIFO_SDATA               ( w_wr_data_fifo_sdata[i]               ),
                .I_WR_DATA_FIFO_STRB                ( w_wr_data_fifo_sdata_strb[i]          ),
                .I_WR_DATA_FIFO_WDATAF              ( w_wr_data_fifo_sdata_wdataf[i]        ),

                .I_WR_DATA_FIFO_MREADY              ( w_aou_rx_wlast_gen_wready[i]          ),
                .O_WR_DATA_FIFO_MDATA               ( w_aou_rx_wlast_gen_wdata[i]           ),
                .O_WR_DATA_FIFO_MSTRB               ( w_aou_rx_wlast_gen_wstrb[i]           ),
                .O_WR_DATA_FIFO_MDLEN               ( w_aou_rx_wlast_gen_wdlength[i]        ),
                .O_WR_DATA_FIFO_WDATAF              ( w_aou_rx_wlast_gen_wdataf[i]          ),
                .O_WR_DATA_FIFO_MVALID              ( w_aou_rx_wlast_gen_wvalid[i]          ),

                .I_RD_REQ_FIFO_SVALID               ( w_rd_req_fifo_svalid[i]               ),
                .I_RD_REQ_FIFO_SDATA                ( w_rd_req_fifo_sdata[i]                ),

                .I_RD_REQ_FIFO_MREADY               ( w_aou_rx_axi_mm_arready[i]            ),
                .O_RD_REQ_FIFO_MDATA                ( {w_aou_rx_axi_mm_arid[i], w_aou_rx_axi_mm_araddr[i], w_aou_rx_axi_mm_arlen[i], w_aou_rx_axi_mm_arsize[i], w_aou_rx_axi_mm_arlock[i], w_aou_rx_axi_mm_arcache[i], w_aou_rx_axi_mm_arprot[i], w_aou_rx_axi_mm_arqos[i]} ),
                .O_RD_REQ_FIFO_MVALID               ( w_aou_rx_axi_mm_arvalid[i]            ),

                .I_RD_DATA_FIFO_SVALID              ( w_rd_data_fifo_svalid[i]              ),
                .I_RD_DATA_FIFO_SDATA               ( w_rd_data_fifo_sdata[i]               ),
                .I_RD_DATA_FIFO_EXT_SDATA           ( w_rd_data_fifo_ext_sdata[i]           ),
                                                 
                .I_RD_DATA_FIFO_MREADY              ( w_aou_rx_fifo_rready[i]               ),
                .O_RD_DATA_FIFO_MDATA               ( w_rd_data_fifo_mdata[i]               ),
                .O_RD_DATA_FIFO_EXT_MDATA           ( {w_aou_rx_axi_s_rid[i], w_aou_rx_axi_s_rresp[i], w_aou_rx_axi_s_rlast[i]} ),
                .O_RD_DATA_FIFO_MDLEN               ( w_aou_rx_axi_s_rdlength[i]            ),
                .O_RD_DATA_FIFO_MVALID              ( w_aou_rx_axi_s_rvalid[i]              ),

                .I_WR_RESP_FIFO_SVALID              ( w_wr_resp_fifo_svalid[i]              ),
                .I_WR_RESP_FIFO_SDATA               ( w_wr_resp_fifo_sdata[i]               ),

                .I_WR_RESP_FIFO_MREADY              ( w_early_bresp_ctrl_bready[i]          ),
                .O_WR_RESP_FIFO_MDATA               ( {w_early_bresp_ctrl_bid[i], w_early_bresp_ctrl_bresp[i]}  ),
                .O_WR_RESP_FIFO_MVALID              ( w_early_bresp_ctrl_bvalid[i]          )

            );

            assign  O_AOU_RX_AXI_S_RDATA[i] = w_aou_rx_axi_s_rdata[i][RP_AXI_DATA_WD_MAX-1:0];

        end
    endgenerate
//----------------------------------------------------------------------------

    assign INT_DEACTIVATE_START = w_int_deactivate_start_level;
    assign INT_ACTIVATE_START   = w_int_activate_start_level;
    assign INT_EARLY_RESP_ERR   = w_int_early_resp_err;
    assign INT_EARLY_WDT_ERR    = w_int_early_wdt_err;
    assign INT_FDI_LINK_DOWN    = w_int_fdi_link_down;
    assign INT_REQ_LINKRESET    = w_int_aou_req_linkreset;
    assign INT_SI0_ID_MISMATCH  = w_axi_slv_rid_mismatch_error || w_axi_slv_bid_mismatch_error;
    assign INT_MI0_ID_MISMATCH  = w_err_info_rid_mismatch_err || w_err_info_split_bid_mismatch_err;
    assign O_AOU_REQ_LINKRESET  = w_int_aou_req_linkreset;
    assign O_SW_RESET           = r_sw_reset;

endmodule
