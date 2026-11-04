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
//  Module     : AOU_TOP
//  Description: Top-level wrapper integrating AOU_FDI_BRINGUP_CTRL (UCIe 3.0
//               FDI state machine) with AOU_CORE_TOP (AXI-over-UCIe protocol
//               engine). The bringup controller manages FDI handshakes
//               (wake, clock, state, rx-active) and drives I_INT_FSM_IN_ACTIVE
//               (link established: Active, Retrain or L1; falls only on a
//               link loss, which raises INT_FDI_LINK_DOWN) into the AOU
//               core, replacing the former external UCIE_CORE connection.
//               O_FDI_LINK_UP is the narrower "FSM in Active".
//
//               FDI data-plane ports mirror AOU_CORE_TOP's _0/_1 naming and
//               `+define+TWO_PHY gating: PHY0 is always present, PHY1 and
//               I_PHY_TYPE are exposed only when built with `+define+TWO_PHY.
//               The single FDI_CONFIG parameter selects the FDI width pair
//               for both PHYs and is forwarded directly to AOU_CORE_TOP.
//               Local FDI_IF_WD0 / FDI_IF_WD1 localparams are derived from
//               FDI_CONFIG only for sizing this wrapper's own FDI ports.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TOP
import packet_def_pkg::*;
#(
    parameter   RP_COUNT                    = 1,

    // FDI configuration selector. Single integer that picks the FDI data
    // bus widths for both PHYs and (in two-PHY builds) the per-PHY pairing.
    // See packet_def_pkg::FDI_CFG_* for the enumeration. Forwarded
    // unchanged to u_aou_core_top below; the local FDI_IF_WD0 / FDI_IF_WD1
    // localparams are derived from FDI_CONFIG only to size this wrapper's
    // own FDI ports and the FIFO-depth defaults. Default matches the
    // legacy +define+FDI_32B single-PHY configuration. Consistency between
    // FDI_CONFIG and +define+TWO_PHY is the integrator's responsibility.
    parameter int FDI_CONFIG                = FDI_CFG_SP_32B,

    // Derived FDI data bus widths (bits). Local-only; not forwarded.
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

    // TX flit packer output stage: 0 combinational (current state),
    // 1 registered from the look-ahead state. See AOU_TX_CORE.
    parameter   TX_NXT_PACKING_EN           = 0,

    localparam  RP_AXI_DATA_WD_MAX          = max4(RP0_AXI_DATA_WD, RP1_AXI_DATA_WD, RP2_AXI_DATA_WD, RP3_AXI_DATA_WD),
    localparam  RP_AXI_STRB_WD_MAX          = RP_AXI_DATA_WD_MAX / 8,

    localparam  AXI_ADDR_WD                 = 64,
    localparam  AXI_ID_WD                   = 10,
    localparam  AXI_LEN_WD                  = 8
)
(
    input  logic                                        I_CLK,
    input  logic                                        I_RESETN,

    input  logic                                        I_PCLK,
    input  logic                                        I_PRESETN,

    // ================================================================
    // APB slave interface
    // ================================================================
    input  logic                                        I_AOU_APB_SI0_PSEL,
    input  logic                                        I_AOU_APB_SI0_PENABLE,
    input  logic [APB_ADDR_WD-1:0]                      I_AOU_APB_SI0_PADDR,
    input  logic                                        I_AOU_APB_SI0_PWRITE,
    input  logic [APB_DATA_WD-1:0]                      I_AOU_APB_SI0_PWDATA,

    output logic [APB_DATA_WD-1:0]                      O_AOU_APB_SI0_PRDATA,
    output logic                                        O_AOU_APB_SI0_PREADY,
    output logic                                        O_AOU_APB_SI0_PSLVERR,

    // ================================================================
    // AXI master interface (RX → downstream)
    // ================================================================
    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_M_ARID,
    output logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        O_AOU_RX_AXI_M_ARADDR,
    output logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         O_AOU_RX_AXI_M_ARLEN,
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_ARSIZE,
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_M_ARBURST,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_ARLOCK,
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_ARCACHE,
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_ARPROT,
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_ARQOS,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_ARVALID,
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_M_ARREADY,

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_M_RID,
    input  logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] I_AOU_TX_AXI_M_RDATA,
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_M_RRESP,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_M_RLAST,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_M_RVALID,
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_M_RREADY,

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_M_AWID,
    output logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        O_AOU_RX_AXI_M_AWADDR,
    output logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         O_AOU_RX_AXI_M_AWLEN,
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_AWSIZE,
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_M_AWBURST,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_AWLOCK,
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_AWCACHE,
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_AWPROT,
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_AWQOS,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_AWVALID,
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_M_AWREADY,

    output logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] O_AOU_RX_AXI_M_WDATA,
    output logic [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0] O_AOU_RX_AXI_M_WSTRB,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_WLAST,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_WVALID,
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_M_WREADY,

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_M_BID,
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_M_BRESP,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_M_BVALID,
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_M_BREADY,

    // ================================================================
    // AXI slave interface (TX → upstream)
    // ================================================================
    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_S_ARID,
    input  logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        I_AOU_TX_AXI_S_ARADDR,
    input  logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         I_AOU_TX_AXI_S_ARLEN,
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_ARSIZE,
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_S_ARBURST,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_ARLOCK,
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_ARCACHE,
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_ARPROT,
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_ARQOS,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_ARVALID,
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_S_ARREADY,

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_S_RID,
    output logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] O_AOU_RX_AXI_S_RDATA,
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_S_RRESP,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_S_RLAST,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_S_RVALID,
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_S_RREADY,

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_S_AWID,
    input  logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        I_AOU_TX_AXI_S_AWADDR,
    input  logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         I_AOU_TX_AXI_S_AWLEN,
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_AWSIZE,
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_S_AWBURST,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_AWLOCK,
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_AWCACHE,
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_AWPROT,
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_AWQOS,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_AWVALID,
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_S_AWREADY,

    input  logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] I_AOU_TX_AXI_S_WDATA,
    input  logic [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0] I_AOU_TX_AXI_S_WSTRB,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_WLAST,
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_WVALID,
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_S_WREADY,

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_S_BID,
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_S_BRESP,
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_S_BVALID,
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_S_BREADY,

    // ================================================================
    // PHY type select (TWO_PHY only)
    // ================================================================
`ifdef TWO_PHY
    input  logic                                        I_PHY_TYPE,
`endif

    // ================================================================
    // FDI data-path interface - PHY0 (always present)
    // ================================================================
    input  logic                                        I_FDI_PL_0_VALID,
    input  logic [FDI_IF_WD0-1:0]                       I_FDI_PL_0_DATA,
    input  logic                                        I_FDI_PL_0_FLIT_CANCEL,

    input  logic                                        I_FDI_PL_0_TRDY,
    input  logic                                        I_FDI_PL_0_STALLREQ,
    input  logic [3:0]                                  I_FDI_PL_0_STATE_STS,
    output logic [FDI_IF_WD0-1:0]                       O_FDI_LP_0_DATA,
    output logic                                        O_FDI_LP_0_VALID,
    output logic                                        O_FDI_LP_0_IRDY,
    output logic                                        O_FDI_LP_0_STALLACK,

    // ================================================================
    // FDI data-path interface - PHY1 (TWO_PHY only)
    // ================================================================
`ifdef TWO_PHY
    input  logic                                        I_FDI_PL_1_VALID,
    input  logic [FDI_IF_WD1-1:0]                       I_FDI_PL_1_DATA,
    input  logic                                        I_FDI_PL_1_FLIT_CANCEL,

    input  logic                                        I_FDI_PL_1_TRDY,
    input  logic                                        I_FDI_PL_1_STALLREQ,
    input  logic [3:0]                                  I_FDI_PL_1_STATE_STS,
    output logic [FDI_IF_WD1-1:0]                       O_FDI_LP_1_DATA,
    output logic                                        O_FDI_LP_1_VALID,
    output logic                                        O_FDI_LP_1_IRDY,
    output logic                                        O_FDI_LP_1_STALLACK,
`endif

    // ================================================================
    // FDI bringup control interface (to AOU_FDI_BRINGUP_CTRL)
    // ================================================================
    input  logic                                        I_PL_INBAND_PRES,
    input  logic                                        I_PL_CLK_REQ,
    input  logic                                        I_PL_WAKE_ACK,
    input  logic                                        I_PL_RX_ACTIVE_REQ,

    output logic [3:0]                                  O_LP_STATE_REQ,
    output logic                                        O_LP_WAKE_REQ,
    output logic                                        O_LP_CLK_ACK,
    output logic                                        O_LP_RX_ACTIVE_STS,
    output logic                                        O_LP_LINKERROR,

    // ================================================================
    // FDI bringup software control
    // ================================================================
    input  logic                                        I_SW_ACTIVATE_START,
    input  logic                                        I_SW_LINKERROR_INJECT,

    // ================================================================
    // FDI bringup status
    // ================================================================
    output logic [3:0]                                  O_FDI_FSM_STATE,
    output logic                                        O_FDI_LINK_UP,

    // ================================================================
    // Interrupt outputs
    // ================================================================
    output logic                                        INT_REQ_LINKRESET,
    output logic                                        INT_SI0_ID_MISMATCH,
    output logic                                        INT_MI0_ID_MISMATCH,
    output logic                                        INT_EARLY_RESP_ERR,
    output logic                                        INT_EARLY_WDT_ERR,
    output logic                                        INT_ACTIVATE_START,
    output logic                                        INT_DEACTIVATE_START,
    output logic                                        INT_FDI_LINK_DOWN,

    // ================================================================
    // DFT
    // ================================================================
    input  logic                                        TIEL_DFT_MODESCAN
);

    // ================================================================
    // Internal wires between bringup ctrl and core
    // ================================================================
    logic        w_int_fsm_in_active;
    logic        w_aou_activate_st_disabled;   // status only; the bringup FSM has no use for it
    logic        w_aou_activate_st_enabled;
    logic        w_aou_req_linkreset;
    logic        w_int_activate_start;
    logic        w_int_deactivate_start;
    logic        w_sw_reset;

    // Mux pl_state_sts / stallreq based on active PHY. Under TWO_PHY both PHYs
    // are valid and I_PHY_TYPE selects which one drives the bringup
    // controller; in single-PHY builds only PHY0 is present so its signals
    // are wired through directly.
    logic [3:0]  w_pl_state_sts_muxed;
    logic        w_pl_stallreq_muxed;

`ifdef TWO_PHY
    assign w_pl_state_sts_muxed = I_PHY_TYPE ? I_FDI_PL_1_STATE_STS
                                             : I_FDI_PL_0_STATE_STS;

    assign w_pl_stallreq_muxed  = I_PHY_TYPE ? I_FDI_PL_1_STALLREQ
                                             : I_FDI_PL_0_STALLREQ;
`else
    assign w_pl_state_sts_muxed = I_FDI_PL_0_STATE_STS;
    assign w_pl_stallreq_muxed  = I_FDI_PL_0_STALLREQ;
`endif

    // ================================================================
    // FDI Bringup Controller
    // ================================================================
    AOU_FDI_BRINGUP_CTRL u_fdi_bringup_ctrl (
        .I_CLK                      ( I_CLK                         ),
        .I_RESETN                   ( I_RESETN                      ),

        .I_PL_STATE_STS             ( w_pl_state_sts_muxed          ),
        .I_PL_INBAND_PRES           ( I_PL_INBAND_PRES              ),
        .I_PL_CLK_REQ               ( I_PL_CLK_REQ                  ),
        .I_PL_WAKE_ACK              ( I_PL_WAKE_ACK                 ),
        .I_PL_RX_ACTIVE_REQ         ( I_PL_RX_ACTIVE_REQ            ),
        .I_PL_STALLREQ              ( w_pl_stallreq_muxed            ),

        .O_LP_STATE_REQ             ( O_LP_STATE_REQ                ),
        .O_LP_WAKE_REQ              ( O_LP_WAKE_REQ                 ),
        .O_LP_CLK_ACK               ( O_LP_CLK_ACK                  ),
        .O_LP_RX_ACTIVE_STS         ( O_LP_RX_ACTIVE_STS            ),
        .O_LP_LINKERROR             ( O_LP_LINKERROR                ),

        .O_INT_FSM_IN_ACTIVE        ( w_int_fsm_in_active           ),
        .I_AOU_ACTIVATE_ST_ENABLED  ( w_aou_activate_st_enabled     ),
        .I_AOU_REQ_LINKRESET        ( w_aou_req_linkreset           ),
        .I_INT_ACTIVATE_START       ( w_int_activate_start          ),

        .I_SW_ACTIVATE_START        ( I_SW_ACTIVATE_START           ),
        .I_SW_LINKERROR_INJECT      ( I_SW_LINKERROR_INJECT         ),
        .I_SW_RESET                 ( w_sw_reset                    ),

        .O_FSM_STATE                ( O_FDI_FSM_STATE               ),
        .O_LINK_UP                  ( O_FDI_LINK_UP                 )
    );

    // ================================================================
    // AOU Core Top (protocol engine + FIFOs + AXI interfaces)
    // ================================================================
    AOU_CORE_TOP #(
        .RP_COUNT                   ( RP_COUNT                      ),

        .FDI_CONFIG                ( FDI_CONFIG                   ),

        .RP0_RX_AW_FIFO_DEPTH      ( RP0_RX_AW_FIFO_DEPTH         ),
        .RP0_RX_AR_FIFO_DEPTH      ( RP0_RX_AR_FIFO_DEPTH         ),
        .RP0_RX_W_FIFO_DEPTH       ( RP0_RX_W_FIFO_DEPTH          ),
        .RP0_RX_R_FIFO_DEPTH       ( RP0_RX_R_FIFO_DEPTH          ),
        .RP0_RX_B_FIFO_DEPTH       ( RP0_RX_B_FIFO_DEPTH          ),

        .RP1_RX_AW_FIFO_DEPTH      ( RP1_RX_AW_FIFO_DEPTH         ),
        .RP1_RX_AR_FIFO_DEPTH      ( RP1_RX_AR_FIFO_DEPTH         ),
        .RP1_RX_W_FIFO_DEPTH       ( RP1_RX_W_FIFO_DEPTH          ),
        .RP1_RX_R_FIFO_DEPTH       ( RP1_RX_R_FIFO_DEPTH          ),
        .RP1_RX_B_FIFO_DEPTH       ( RP1_RX_B_FIFO_DEPTH          ),

        .RP2_RX_AW_FIFO_DEPTH      ( RP2_RX_AW_FIFO_DEPTH         ),
        .RP2_RX_AR_FIFO_DEPTH      ( RP2_RX_AR_FIFO_DEPTH         ),
        .RP2_RX_W_FIFO_DEPTH       ( RP2_RX_W_FIFO_DEPTH          ),
        .RP2_RX_R_FIFO_DEPTH       ( RP2_RX_R_FIFO_DEPTH          ),
        .RP2_RX_B_FIFO_DEPTH       ( RP2_RX_B_FIFO_DEPTH          ),

        .RP3_RX_AW_FIFO_DEPTH      ( RP3_RX_AW_FIFO_DEPTH         ),
        .RP3_RX_AR_FIFO_DEPTH      ( RP3_RX_AR_FIFO_DEPTH         ),
        .RP3_RX_W_FIFO_DEPTH       ( RP3_RX_W_FIFO_DEPTH          ),
        .RP3_RX_R_FIFO_DEPTH       ( RP3_RX_R_FIFO_DEPTH          ),
        .RP3_RX_B_FIFO_DEPTH       ( RP3_RX_B_FIFO_DEPTH          ),

        .RX_AW_FIFO_RS_EN          ( RX_AW_FIFO_RS_EN             ),
        .RX_AR_FIFO_RS_EN          ( RX_AR_FIFO_RS_EN             ),
        .RX_W_FIFO_RS_EN           ( RX_W_FIFO_RS_EN              ),
        .RX_R_FIFO_RS_EN           ( RX_R_FIFO_RS_EN              ),
        .RX_B_FIFO_RS_EN           ( RX_B_FIFO_RS_EN              ),

        .RP0_AXI_DATA_WD           ( RP0_AXI_DATA_WD              ),
        .RP1_AXI_DATA_WD           ( RP1_AXI_DATA_WD              ),
        .RP2_AXI_DATA_WD           ( RP2_AXI_DATA_WD              ),
        .RP3_AXI_DATA_WD           ( RP3_AXI_DATA_WD              ),

        .APB_ADDR_WD               ( APB_ADDR_WD                  ),
        .APB_DATA_WD               ( APB_DATA_WD                  ),

        .RP0_S_RD_MO_CNT           ( RP0_S_RD_MO_CNT              ),
        .RP0_S_WR_MO_CNT           ( RP0_S_WR_MO_CNT              ),
        .RP0_M_RD_MO_CNT           ( RP0_M_RD_MO_CNT              ),
        .RP0_M_WR_MO_CNT           ( RP0_M_WR_MO_CNT              ),

        .RP1_S_RD_MO_CNT           ( RP1_S_RD_MO_CNT              ),
        .RP1_S_WR_MO_CNT           ( RP1_S_WR_MO_CNT              ),
        .RP1_M_RD_MO_CNT           ( RP1_M_RD_MO_CNT              ),
        .RP1_M_WR_MO_CNT           ( RP1_M_WR_MO_CNT              ),

        .RP2_S_RD_MO_CNT           ( RP2_S_RD_MO_CNT              ),
        .RP2_S_WR_MO_CNT           ( RP2_S_WR_MO_CNT              ),
        .RP2_M_RD_MO_CNT           ( RP2_M_RD_MO_CNT              ),
        .RP2_M_WR_MO_CNT           ( RP2_M_WR_MO_CNT              ),

        .RP3_S_RD_MO_CNT           ( RP3_S_RD_MO_CNT              ),
        .RP3_S_WR_MO_CNT           ( RP3_S_WR_MO_CNT              ),
        .RP3_M_RD_MO_CNT           ( RP3_M_RD_MO_CNT              ),
        .RP3_M_WR_MO_CNT           ( RP3_M_WR_MO_CNT              ),

        .TX_NXT_PACKING_EN         ( TX_NXT_PACKING_EN            )

    ) u_aou_core_top (
        .I_CLK                      ( I_CLK                         ),
        .I_RESETN                   ( I_RESETN                      ),

        .I_PCLK                     ( I_PCLK                        ),
        .I_PRESETN                  ( I_PRESETN                     ),

        .I_AOU_APB_SI0_PSEL         ( I_AOU_APB_SI0_PSEL            ),
        .I_AOU_APB_SI0_PENABLE      ( I_AOU_APB_SI0_PENABLE         ),
        .I_AOU_APB_SI0_PADDR        ( I_AOU_APB_SI0_PADDR           ),
        .I_AOU_APB_SI0_PWRITE       ( I_AOU_APB_SI0_PWRITE          ),
        .I_AOU_APB_SI0_PWDATA       ( I_AOU_APB_SI0_PWDATA          ),

        .O_AOU_APB_SI0_PRDATA       ( O_AOU_APB_SI0_PRDATA          ),
        .O_AOU_APB_SI0_PREADY       ( O_AOU_APB_SI0_PREADY          ),
        .O_AOU_APB_SI0_PSLVERR      ( O_AOU_APB_SI0_PSLVERR         ),

        .O_AOU_RX_AXI_M_ARID        ( O_AOU_RX_AXI_M_ARID           ),
        .O_AOU_RX_AXI_M_ARADDR      ( O_AOU_RX_AXI_M_ARADDR         ),
        .O_AOU_RX_AXI_M_ARLEN       ( O_AOU_RX_AXI_M_ARLEN          ),
        .O_AOU_RX_AXI_M_ARSIZE      ( O_AOU_RX_AXI_M_ARSIZE         ),
        .O_AOU_RX_AXI_M_ARBURST     ( O_AOU_RX_AXI_M_ARBURST        ),
        .O_AOU_RX_AXI_M_ARLOCK      ( O_AOU_RX_AXI_M_ARLOCK         ),
        .O_AOU_RX_AXI_M_ARCACHE     ( O_AOU_RX_AXI_M_ARCACHE        ),
        .O_AOU_RX_AXI_M_ARPROT      ( O_AOU_RX_AXI_M_ARPROT         ),
        .O_AOU_RX_AXI_M_ARQOS       ( O_AOU_RX_AXI_M_ARQOS          ),
        .O_AOU_RX_AXI_M_ARVALID     ( O_AOU_RX_AXI_M_ARVALID        ),
        .I_AOU_RX_AXI_M_ARREADY     ( I_AOU_RX_AXI_M_ARREADY        ),

        .I_AOU_TX_AXI_M_RID         ( I_AOU_TX_AXI_M_RID            ),
        .I_AOU_TX_AXI_M_RDATA       ( I_AOU_TX_AXI_M_RDATA          ),
        .I_AOU_TX_AXI_M_RRESP       ( I_AOU_TX_AXI_M_RRESP          ),
        .I_AOU_TX_AXI_M_RLAST       ( I_AOU_TX_AXI_M_RLAST          ),
        .I_AOU_TX_AXI_M_RVALID      ( I_AOU_TX_AXI_M_RVALID         ),
        .O_AOU_TX_AXI_M_RREADY      ( O_AOU_TX_AXI_M_RREADY         ),

        .O_AOU_RX_AXI_M_AWID        ( O_AOU_RX_AXI_M_AWID           ),
        .O_AOU_RX_AXI_M_AWADDR      ( O_AOU_RX_AXI_M_AWADDR         ),
        .O_AOU_RX_AXI_M_AWLEN       ( O_AOU_RX_AXI_M_AWLEN          ),
        .O_AOU_RX_AXI_M_AWSIZE      ( O_AOU_RX_AXI_M_AWSIZE         ),
        .O_AOU_RX_AXI_M_AWBURST     ( O_AOU_RX_AXI_M_AWBURST        ),
        .O_AOU_RX_AXI_M_AWLOCK      ( O_AOU_RX_AXI_M_AWLOCK         ),
        .O_AOU_RX_AXI_M_AWCACHE     ( O_AOU_RX_AXI_M_AWCACHE        ),
        .O_AOU_RX_AXI_M_AWPROT      ( O_AOU_RX_AXI_M_AWPROT         ),
        .O_AOU_RX_AXI_M_AWQOS       ( O_AOU_RX_AXI_M_AWQOS          ),
        .O_AOU_RX_AXI_M_AWVALID     ( O_AOU_RX_AXI_M_AWVALID        ),
        .I_AOU_RX_AXI_M_AWREADY     ( I_AOU_RX_AXI_M_AWREADY        ),

        .O_AOU_RX_AXI_M_WDATA       ( O_AOU_RX_AXI_M_WDATA          ),
        .O_AOU_RX_AXI_M_WSTRB       ( O_AOU_RX_AXI_M_WSTRB          ),
        .O_AOU_RX_AXI_M_WLAST       ( O_AOU_RX_AXI_M_WLAST          ),
        .O_AOU_RX_AXI_M_WVALID      ( O_AOU_RX_AXI_M_WVALID         ),
        .I_AOU_RX_AXI_M_WREADY      ( I_AOU_RX_AXI_M_WREADY         ),

        .I_AOU_TX_AXI_M_BID         ( I_AOU_TX_AXI_M_BID            ),
        .I_AOU_TX_AXI_M_BRESP       ( I_AOU_TX_AXI_M_BRESP          ),
        .I_AOU_TX_AXI_M_BVALID      ( I_AOU_TX_AXI_M_BVALID         ),
        .O_AOU_TX_AXI_M_BREADY      ( O_AOU_TX_AXI_M_BREADY         ),

        .I_AOU_TX_AXI_S_ARID        ( I_AOU_TX_AXI_S_ARID           ),
        .I_AOU_TX_AXI_S_ARADDR      ( I_AOU_TX_AXI_S_ARADDR         ),
        .I_AOU_TX_AXI_S_ARLEN       ( I_AOU_TX_AXI_S_ARLEN          ),
        .I_AOU_TX_AXI_S_ARSIZE      ( I_AOU_TX_AXI_S_ARSIZE         ),
        .I_AOU_TX_AXI_S_ARBURST     ( I_AOU_TX_AXI_S_ARBURST        ),
        .I_AOU_TX_AXI_S_ARLOCK      ( I_AOU_TX_AXI_S_ARLOCK         ),
        .I_AOU_TX_AXI_S_ARCACHE     ( I_AOU_TX_AXI_S_ARCACHE        ),
        .I_AOU_TX_AXI_S_ARPROT      ( I_AOU_TX_AXI_S_ARPROT         ),
        .I_AOU_TX_AXI_S_ARQOS       ( I_AOU_TX_AXI_S_ARQOS          ),
        .I_AOU_TX_AXI_S_ARVALID     ( I_AOU_TX_AXI_S_ARVALID        ),
        .O_AOU_TX_AXI_S_ARREADY     ( O_AOU_TX_AXI_S_ARREADY        ),

        .O_AOU_RX_AXI_S_RID         ( O_AOU_RX_AXI_S_RID            ),
        .O_AOU_RX_AXI_S_RDATA       ( O_AOU_RX_AXI_S_RDATA          ),
        .O_AOU_RX_AXI_S_RRESP       ( O_AOU_RX_AXI_S_RRESP          ),
        .O_AOU_RX_AXI_S_RLAST       ( O_AOU_RX_AXI_S_RLAST          ),
        .O_AOU_RX_AXI_S_RVALID      ( O_AOU_RX_AXI_S_RVALID         ),
        .I_AOU_RX_AXI_S_RREADY      ( I_AOU_RX_AXI_S_RREADY         ),

        .I_AOU_TX_AXI_S_AWID        ( I_AOU_TX_AXI_S_AWID           ),
        .I_AOU_TX_AXI_S_AWADDR      ( I_AOU_TX_AXI_S_AWADDR         ),
        .I_AOU_TX_AXI_S_AWLEN       ( I_AOU_TX_AXI_S_AWLEN          ),
        .I_AOU_TX_AXI_S_AWSIZE      ( I_AOU_TX_AXI_S_AWSIZE         ),
        .I_AOU_TX_AXI_S_AWBURST     ( I_AOU_TX_AXI_S_AWBURST        ),
        .I_AOU_TX_AXI_S_AWLOCK      ( I_AOU_TX_AXI_S_AWLOCK         ),
        .I_AOU_TX_AXI_S_AWCACHE     ( I_AOU_TX_AXI_S_AWCACHE        ),
        .I_AOU_TX_AXI_S_AWPROT      ( I_AOU_TX_AXI_S_AWPROT         ),
        .I_AOU_TX_AXI_S_AWQOS       ( I_AOU_TX_AXI_S_AWQOS          ),
        .I_AOU_TX_AXI_S_AWVALID     ( I_AOU_TX_AXI_S_AWVALID        ),
        .O_AOU_TX_AXI_S_AWREADY     ( O_AOU_TX_AXI_S_AWREADY        ),

        .I_AOU_TX_AXI_S_WDATA       ( I_AOU_TX_AXI_S_WDATA          ),
        .I_AOU_TX_AXI_S_WSTRB       ( I_AOU_TX_AXI_S_WSTRB          ),
        .I_AOU_TX_AXI_S_WLAST       ( I_AOU_TX_AXI_S_WLAST          ),
        .I_AOU_TX_AXI_S_WVALID      ( I_AOU_TX_AXI_S_WVALID         ),
        .O_AOU_TX_AXI_S_WREADY      ( O_AOU_TX_AXI_S_WREADY         ),

        .O_AOU_RX_AXI_S_BID         ( O_AOU_RX_AXI_S_BID            ),
        .O_AOU_RX_AXI_S_BRESP       ( O_AOU_RX_AXI_S_BRESP          ),
        .O_AOU_RX_AXI_S_BVALID      ( O_AOU_RX_AXI_S_BVALID         ),
        .I_AOU_RX_AXI_S_BREADY      ( I_AOU_RX_AXI_S_BREADY         ),

        .I_FDI_PL_0_VALID            ( I_FDI_PL_0_VALID              ),
        .I_FDI_PL_0_DATA             ( I_FDI_PL_0_DATA               ),
        .I_FDI_PL_0_FLIT_CANCEL      ( I_FDI_PL_0_FLIT_CANCEL        ),

        .I_FDI_PL_0_TRDY             ( I_FDI_PL_0_TRDY               ),
        .I_FDI_PL_0_STALLREQ         ( I_FDI_PL_0_STALLREQ           ),
        .I_FDI_PL_0_STATE_STS        ( I_FDI_PL_0_STATE_STS          ),
        .O_FDI_LP_0_DATA             ( O_FDI_LP_0_DATA               ),
        .O_FDI_LP_0_VALID            ( O_FDI_LP_0_VALID              ),
        .O_FDI_LP_0_IRDY             ( O_FDI_LP_0_IRDY               ),
        .O_FDI_LP_0_STALLACK         ( O_FDI_LP_0_STALLACK           ),

`ifdef TWO_PHY
        .I_PHY_TYPE                  ( I_PHY_TYPE                    ),

        .I_FDI_PL_1_VALID            ( I_FDI_PL_1_VALID              ),
        .I_FDI_PL_1_DATA             ( I_FDI_PL_1_DATA               ),
        .I_FDI_PL_1_FLIT_CANCEL      ( I_FDI_PL_1_FLIT_CANCEL        ),

        .I_FDI_PL_1_TRDY             ( I_FDI_PL_1_TRDY               ),
        .I_FDI_PL_1_STALLREQ         ( I_FDI_PL_1_STALLREQ           ),
        .I_FDI_PL_1_STATE_STS        ( I_FDI_PL_1_STATE_STS          ),
        .O_FDI_LP_1_DATA             ( O_FDI_LP_1_DATA               ),
        .O_FDI_LP_1_VALID            ( O_FDI_LP_1_VALID              ),
        .O_FDI_LP_1_IRDY             ( O_FDI_LP_1_IRDY               ),
        .O_FDI_LP_1_STALLACK         ( O_FDI_LP_1_STALLACK           ),
`endif

        .INT_REQ_LINKRESET           ( INT_REQ_LINKRESET             ),
        .INT_SI0_ID_MISMATCH         ( INT_SI0_ID_MISMATCH           ),
        .INT_MI0_ID_MISMATCH         ( INT_MI0_ID_MISMATCH           ),
        .INT_EARLY_RESP_ERR          ( INT_EARLY_RESP_ERR            ),
        .INT_EARLY_WDT_ERR           ( INT_EARLY_WDT_ERR             ),
        .INT_ACTIVATE_START          ( w_int_activate_start          ),
        .INT_DEACTIVATE_START        ( w_int_deactivate_start        ),
        .INT_FDI_LINK_DOWN           ( INT_FDI_LINK_DOWN             ),

        .I_INT_FSM_IN_ACTIVE         ( w_int_fsm_in_active           ),
        .O_AOU_ACTIVATE_ST_DISABLED  ( w_aou_activate_st_disabled    ),
        .O_AOU_ACTIVATE_ST_ENABLED   ( w_aou_activate_st_enabled     ),
        .O_AOU_REQ_LINKRESET         ( w_aou_req_linkreset           ),
        .O_SW_RESET                  ( w_sw_reset                    ),

        .TIEL_DFT_MODESCAN           ( TIEL_DFT_MODESCAN             )
    );

    // ================================================================
    // Interrupt pass-through
    // ================================================================
    assign INT_ACTIVATE_START   = w_int_activate_start;
    assign INT_DEACTIVATE_START = w_int_deactivate_start;

endmodule
