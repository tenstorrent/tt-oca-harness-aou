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
// Connect the UCIe 3.0 FDI bringup controller to the AXI-over-UCIe protocol engine.
//
// AOU_TOP is the top-level wrapper around AOU_FDI_BRINGUP_CTRL, the UCIe 3.0 FDI state
// machine, and AOU_CORE_TOP, the AXI-over-UCIe protocol engine. The bringup controller
// manages the FDI handshakes (wake, clock, state, and rx-active) and drives
// I_INT_FSM_IN_ACTIVE into the AOU core, so the core needs no external UCIE_CORE
// connection. I_INT_FSM_IN_ACTIVE means the link is established (Active, Retrain, or
// L1) and falls only on a link loss, which raises INT_FDI_LINK_DOWN. O_FDI_LINK_UP is
// narrower and is set only while the FSM is in Active.
//
// The FDI data-plane ports mirror the _0/_1 naming and the +define+TWO_PHY gating of
// AOU_CORE_TOP. PHY0 is always present. PHY1 and I_PHY_TYPE are exposed only when the
// design is built with +define+TWO_PHY.
//
// The single FDI_CONFIG parameter is an integer that picks the FDI data bus widths for
// both PHYs and, in two-PHY builds, the per-PHY pairing; packet_def_pkg::FDI_CFG_*
// enumerates its values. FDI_CONFIG is forwarded unchanged to AOU_CORE_TOP. Its default
// matches the legacy +define+FDI_32B single-PHY configuration. Keeping FDI_CONFIG
// consistent with +define+TWO_PHY is the integrator's responsibility. The local
// FDI_IF_WD0 and FDI_IF_WD1 localparams are derived from FDI_CONFIG only to size this
// wrapper's own FDI ports and the FIFO-depth defaults, and are not forwarded.
//
// The RX W and R granule-store depths are given in granules. They default to 960 with the
// 256B FDI (FDI_IF_WD0 == 2048) and to 600 otherwise.
//
// The ports fall into these groups:
//
// - APB slave interface.
// - AXI master interface (O_AOU_RX_AXI_M_*, I_AOU_TX_AXI_M_*): the RX side, facing the
//   downstream bus.
// - AXI slave interface (I_AOU_TX_AXI_S_*, O_AOU_RX_AXI_S_*): the TX side, facing the
//   upstream bus.
// - PHY type select (I_PHY_TYPE), present only with +define+TWO_PHY.
// - FDI data path for PHY0, always present, and for PHY1, present only with
//   +define+TWO_PHY.
// - FDI bringup control (I_PL_*, O_LP_*), connected to AOU_FDI_BRINGUP_CTRL.
// - FDI bringup software control (I_SW_*) and status (O_FDI_FSM_STATE, O_FDI_LINK_UP).
// - Interrupt outputs (INT_*).
// - DFT.

`timescale 1ns/1ps

module AOU_TOP
import packet_def_pkg::*;
#(
    parameter   RP_COUNT                    = 1,  // Number of receive ports (AXI master/slave
                                                  // pairs), up to 4.

    parameter int FDI_CONFIG                = FDI_CFG_SP_32B,  // FDI configuration, one of
                                                               // packet_def_pkg::FDI_CFG_*.

    localparam int FDI_IF_WD0 = (FDI_CONFIG == FDI_CFG_SP_32B     ) ? 256  :  // PHY0 FDI data bus width, in bits. Local only.
                                (FDI_CONFIG == FDI_CFG_SP_64B     ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_SP_128B    ) ? 1024 :
                                (FDI_CONFIG == FDI_CFG_TP_32B_64B ) ? 256  :
                                (FDI_CONFIG == FDI_CFG_TP_64B_128B) ? 512  :
                                (FDI_CONFIG == FDI_CFG_SP_256B    ) ? 2048 : 256,
    localparam int FDI_IF_WD1 = (FDI_CONFIG == FDI_CFG_SP_32B     ) ? 512  :  // PHY1 FDI data bus width, in bits. Local only.
                                (FDI_CONFIG == FDI_CFG_SP_64B     ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_SP_128B    ) ? 1024 :
                                (FDI_CONFIG == FDI_CFG_TP_32B_64B ) ? 512  :
                                (FDI_CONFIG == FDI_CFG_TP_64B_128B) ? 1024 :
                                (FDI_CONFIG == FDI_CFG_SP_256B    ) ? 2048 : 512,

    parameter   RP0_RX_AW_FIFO_DEPTH        = 44,  // RP0 RX write-address FIFO depth.
    parameter   RP0_RX_AR_FIFO_DEPTH        = 44,  // RP0 RX read-address FIFO depth.
    parameter   RP0_RX_W_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP0 RX write-data granule-store depth, in granules.
    parameter   RP0_RX_R_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP0 RX read-data granule-store depth, in granules.
    parameter   RP0_RX_B_FIFO_DEPTH         = 44,  // RP0 RX write-response FIFO depth.

    parameter   RP1_RX_AW_FIFO_DEPTH        = 44,  // RP1 RX write-address FIFO depth.
    parameter   RP1_RX_AR_FIFO_DEPTH        = 44,  // RP1 RX read-address FIFO depth.
    parameter   RP1_RX_W_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP1 RX write-data granule-store depth, in granules.
    parameter   RP1_RX_R_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP1 RX read-data granule-store depth, in granules.
    parameter   RP1_RX_B_FIFO_DEPTH         = 44,  // RP1 RX write-response FIFO depth.

    parameter   RP2_RX_AW_FIFO_DEPTH        = 44,  // RP2 RX write-address FIFO depth.
    parameter   RP2_RX_AR_FIFO_DEPTH        = 44,  // RP2 RX read-address FIFO depth.
    parameter   RP2_RX_W_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP2 RX write-data granule-store depth, in granules.
    parameter   RP2_RX_R_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP2 RX read-data granule-store depth, in granules.
    parameter   RP2_RX_B_FIFO_DEPTH         = 44,  // RP2 RX write-response FIFO depth.

    parameter   RP3_RX_AW_FIFO_DEPTH        = 44,  // RP3 RX write-address FIFO depth.
    parameter   RP3_RX_AR_FIFO_DEPTH        = 44,  // RP3 RX read-address FIFO depth.
    parameter   RP3_RX_W_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP3 RX write-data granule-store depth, in granules.
    parameter   RP3_RX_R_FIFO_DEPTH         = (FDI_IF_WD0 == 2048) ? 960 : 600,  // RP3 RX read-data granule-store depth, in granules.
    parameter   RP3_RX_B_FIFO_DEPTH         = 44,  // RP3 RX write-response FIFO depth.

    parameter   RX_AW_FIFO_RS_EN            = 1,  // Register slice on the RX write-address FIFO
                                                  // output.
    parameter   RX_AR_FIFO_RS_EN            = 1,  // Register slice on the RX read-address FIFO
                                                  // output.
    parameter   RX_B_FIFO_RS_EN             = 1,  // Register slice on the RX write-response FIFO
                                                  // output.

    parameter   RP0_AXI_DATA_WD             = 512,  // RP0 AXI data width, in bits.
    parameter   RP1_AXI_DATA_WD             = 512,  // RP1 AXI data width, in bits.
    parameter   RP2_AXI_DATA_WD             = 512,  // RP2 AXI data width, in bits.
    parameter   RP3_AXI_DATA_WD             = 512,  // RP3 AXI data width, in bits.

    localparam  AXI_PEER_DIE_MAX_DATA_WD    = 1024,  // Widest AoU data message (WriteData1024,
                                                     // ReadData1024). The RX data path is sized
                                                     // for it because the peer die's AXI width
                                                     // is unknown.

    parameter   APB_ADDR_WD                 = 32,  // APB address width.
    parameter   APB_DATA_WD                 = 32,  // APB data width.

    parameter   RP0_S_RD_MO_CNT             = 32,  // RP0 outstanding reads on the AXI slave interface.
    parameter   RP0_S_WR_MO_CNT             = 32,  // RP0 outstanding writes on the AXI slave interface.
    parameter   RP0_M_RD_MO_CNT             = 32,  // RP0 outstanding reads on the AXI master interface.
    parameter   RP0_M_WR_MO_CNT             = 32,  // RP0 outstanding writes on the AXI master interface.

    parameter   RP1_S_RD_MO_CNT             = 32,  // RP1 outstanding reads on the AXI slave interface.
    parameter   RP1_S_WR_MO_CNT             = 32,  // RP1 outstanding writes on the AXI slave interface.
    parameter   RP1_M_RD_MO_CNT             = 32,  // RP1 outstanding reads on the AXI master interface.
    parameter   RP1_M_WR_MO_CNT             = 32,  // RP1 outstanding writes on the AXI master interface.

    parameter   RP2_S_RD_MO_CNT             = 32,  // RP2 outstanding reads on the AXI slave interface.
    parameter   RP2_S_WR_MO_CNT             = 32,  // RP2 outstanding writes on the AXI slave interface.
    parameter   RP2_M_RD_MO_CNT             = 32,  // RP2 outstanding reads on the AXI master interface.
    parameter   RP2_M_WR_MO_CNT             = 32,  // RP2 outstanding writes on the AXI master interface.

    parameter   RP3_S_RD_MO_CNT             = 32,  // RP3 outstanding reads on the AXI slave interface.
    parameter   RP3_S_WR_MO_CNT             = 32,  // RP3 outstanding writes on the AXI slave interface.
    parameter   RP3_M_RD_MO_CNT             = 32,  // RP3 outstanding reads on the AXI master interface.
    parameter   RP3_M_WR_MO_CNT             = 32,  // RP3 outstanding writes on the AXI master interface.

    parameter   TX_NXT_PACKING_EN           = 0,  // TX flit packer output stage: 0 combinational
                                                  // from the current state, 1 registered from the
                                                  // look-ahead state.

    localparam  RP_AXI_DATA_WD_MAX          = max4(RP0_AXI_DATA_WD, RP1_AXI_DATA_WD, RP2_AXI_DATA_WD, RP3_AXI_DATA_WD),  // Widest RPn AXI data width; sizes the AXI data ports.
    localparam  RP_AXI_STRB_WD_MAX          = RP_AXI_DATA_WD_MAX / 8,  // AXI write-strobe width for that data width.

    localparam  AXI_ADDR_WD                 = 64,  // AXI address width.
    localparam  AXI_ID_WD                   = 10,  // AXI ID width.
    localparam  AXI_LEN_WD                  = 8  // AXI burst-length width.
)
(
    input  logic                                        I_CLK,  // Clock for the AOU core and the FDI bringup controller.
    input  logic                                        I_RESETN,  // Active-low asynchronous reset for the I_CLK domain.

    input  logic                                        I_PCLK,  // APB clock, asynchronous to I_CLK.
    input  logic                                        I_PRESETN,  // Active-low reset for the I_PCLK domain.

    input  logic                                        I_AOU_APB_SI0_PSEL,  // APB select.
    input  logic                                        I_AOU_APB_SI0_PENABLE,  // APB enable.
    input  logic [APB_ADDR_WD-1:0]                      I_AOU_APB_SI0_PADDR,  // APB address.
    input  logic                                        I_AOU_APB_SI0_PWRITE,  // APB write.
    input  logic [APB_DATA_WD-1:0]                      I_AOU_APB_SI0_PWDATA,  // APB write data.

    output logic [APB_DATA_WD-1:0]                      O_AOU_APB_SI0_PRDATA,  // APB read data.
    output logic                                        O_AOU_APB_SI0_PREADY,  // APB ready.
    output logic                                        O_AOU_APB_SI0_PSLVERR,  // APB slave error.

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_M_ARID,  // AXI master read-address ID.
    output logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        O_AOU_RX_AXI_M_ARADDR,  // AXI master read address.
    output logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         O_AOU_RX_AXI_M_ARLEN,  // AXI master read burst length.
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_ARSIZE,  // AXI master read transfer size.
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_M_ARBURST,  // AXI master read burst type.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_ARLOCK,  // AXI master read lock.
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_ARCACHE,  // AXI master read cache attributes.
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_ARPROT,  // AXI master read protection.
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_ARQOS,  // AXI master read QoS.
    output logic [RP_COUNT-1:0][15:0]                   O_AOU_RX_AXI_M_ARUSER,  // AXI master read-address user: the ReadReq FLEX field.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_ARVALID,  // AXI master read-address valid.
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_M_ARREADY,  // AXI master read-address ready.

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_M_RID,  // AXI master read-data ID.
    input  logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] I_AOU_TX_AXI_M_RDATA,  // AXI master read data.
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_M_RRESP,  // AXI master read response.
    input  logic [RP_COUNT-1:0][15:0]                   I_AOU_TX_AXI_M_RUSER,  // AXI master read-data user, sent as the ReadData FLEX field.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_M_RLAST,  // AXI master last read beat.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_M_RVALID,  // AXI master read-data valid.
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_M_RREADY,  // AXI master read-data ready.

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_M_AWID,  // AXI master write-address ID.
    output logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        O_AOU_RX_AXI_M_AWADDR,  // AXI master write address.
    output logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         O_AOU_RX_AXI_M_AWLEN,  // AXI master write burst length.
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_AWSIZE,  // AXI master write transfer size.
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_M_AWBURST,  // AXI master write burst type.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_AWLOCK,  // AXI master write lock.
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_AWCACHE,  // AXI master write cache attributes.
    output logic [RP_COUNT-1:0][2:0]                    O_AOU_RX_AXI_M_AWPROT,  // AXI master write protection.
    output logic [RP_COUNT-1:0][3:0]                    O_AOU_RX_AXI_M_AWQOS,  // AXI master write QoS.
    output logic [RP_COUNT-1:0][15:0]                   O_AOU_RX_AXI_M_AWUSER,  // AXI master write-address user: the WriteReq FLEX field.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_AWVALID,  // AXI master write-address valid.
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_M_AWREADY,  // AXI master write-address ready.

    output logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] O_AOU_RX_AXI_M_WDATA,  // AXI master write data.
    output logic [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0] O_AOU_RX_AXI_M_WSTRB,  // AXI master write strobes.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_WLAST,  // AXI master last write beat.
    output logic [RP_COUNT-1:0][15:0]                   O_AOU_RX_AXI_M_WUSER,  // AXI master write-data user: the WriteData FLEX field.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_M_WVALID,  // AXI master write-data valid.
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_M_WREADY,  // AXI master write-data ready.

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_M_BID,  // AXI master write-response ID.
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_M_BRESP,  // AXI master write response.
    input  logic [RP_COUNT-1:0][15:0]                   I_AOU_TX_AXI_M_BUSER,  // AXI master write-response user, sent as the WriteResp FLEX field.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_M_BVALID,  // AXI master write-response valid.
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_M_BREADY,  // AXI master write-response ready.

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_S_ARID,  // AXI slave read-address ID.
    input  logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        I_AOU_TX_AXI_S_ARADDR,  // AXI slave read address.
    input  logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         I_AOU_TX_AXI_S_ARLEN,  // AXI slave read burst length.
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_ARSIZE,  // AXI slave read transfer size.
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_S_ARBURST,  // AXI slave read burst type.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_ARLOCK,  // AXI slave read lock.
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_ARCACHE,  // AXI slave read cache attributes.
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_ARPROT,  // AXI slave read protection.
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_ARQOS,  // AXI slave read QoS.
    input  logic [RP_COUNT-1:0][15:0]                   I_AOU_TX_AXI_S_ARUSER,  // AXI slave read-address user, sent as the ReadReq FLEX field.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_ARVALID,  // AXI slave read-address valid.
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_S_ARREADY,  // AXI slave read-address ready.

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_S_RID,  // AXI slave read-data ID.
    output logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] O_AOU_RX_AXI_S_RDATA,  // AXI slave read data.
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_S_RRESP,  // AXI slave read response.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_S_RLAST,  // AXI slave last read beat.
    output logic [RP_COUNT-1:0][15:0]                   O_AOU_RX_AXI_S_RUSER,  // AXI slave read-data user: the ReadData FLEX field.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_S_RVALID,  // AXI slave read-data valid.
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_S_RREADY,  // AXI slave read-data ready.

    input  logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          I_AOU_TX_AXI_S_AWID,  // AXI slave write-address ID.
    input  logic [RP_COUNT-1:0][AXI_ADDR_WD-1:0]        I_AOU_TX_AXI_S_AWADDR,  // AXI slave write address.
    input  logic [RP_COUNT-1:0][AXI_LEN_WD-1:0]         I_AOU_TX_AXI_S_AWLEN,  // AXI slave write burst length.
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_AWSIZE,  // AXI slave write transfer size.
    input  logic [RP_COUNT-1:0][1:0]                    I_AOU_TX_AXI_S_AWBURST,  // AXI slave write burst type.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_AWLOCK,  // AXI slave write lock.
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_AWCACHE,  // AXI slave write cache attributes.
    input  logic [RP_COUNT-1:0][2:0]                    I_AOU_TX_AXI_S_AWPROT,  // AXI slave write protection.
    input  logic [RP_COUNT-1:0][3:0]                    I_AOU_TX_AXI_S_AWQOS,  // AXI slave write QoS.
    input  logic [RP_COUNT-1:0][15:0]                   I_AOU_TX_AXI_S_AWUSER,  // AXI slave write-address user, sent as the WriteReq FLEX field.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_AWVALID,  // AXI slave write-address valid.
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_S_AWREADY,  // AXI slave write-address ready.

    input  logic [RP_COUNT-1:0][RP_AXI_DATA_WD_MAX-1:0] I_AOU_TX_AXI_S_WDATA,  // AXI slave write data.
    input  logic [RP_COUNT-1:0][RP_AXI_STRB_WD_MAX-1:0] I_AOU_TX_AXI_S_WSTRB,  // AXI slave write strobes.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_WLAST,  // AXI slave last write beat.
    input  logic [RP_COUNT-1:0][15:0]                   I_AOU_TX_AXI_S_WUSER,  // AXI slave write-data user, sent as the WriteData FLEX field.
    input  logic [RP_COUNT-1:0]                         I_AOU_TX_AXI_S_WVALID,  // AXI slave write-data valid.
    output logic [RP_COUNT-1:0]                         O_AOU_TX_AXI_S_WREADY,  // AXI slave write-data ready.

    output logic [RP_COUNT-1:0][AXI_ID_WD-1:0]          O_AOU_RX_AXI_S_BID,  // AXI slave write-response ID.
    output logic [RP_COUNT-1:0][1:0]                    O_AOU_RX_AXI_S_BRESP,  // AXI slave write response.
    output logic [RP_COUNT-1:0][15:0]                   O_AOU_RX_AXI_S_BUSER,  // AXI slave write-response user: the WriteResp FLEX field, 0 for an early response.
    output logic [RP_COUNT-1:0]                         O_AOU_RX_AXI_S_BVALID,  // AXI slave write-response valid.
    input  logic [RP_COUNT-1:0]                         I_AOU_RX_AXI_S_BREADY,  // AXI slave write-response ready.

`ifdef TWO_PHY
    input  logic                                        I_PHY_TYPE,  // Active PHY: 0 selects PHY0, 1 selects PHY1.
                                                                     // Routes the flit data path through that PHY; PHY0
                                                                     // carries each core flit as two half-width beats.
                                                                     // Also picks the PHY whose state status and stall
                                                                     // request reach the bringup controller.
`endif

    input  logic                                        I_FDI_PL_0_VALID,  // PHY0 received-flit valid.
    input  logic [FDI_IF_WD0-1:0]                       I_FDI_PL_0_DATA,  // PHY0 received-flit data.
    input  logic                                        I_FDI_PL_0_FLIT_CANCEL,  // PHY0 flit cancel.

    input  logic                                        I_FDI_PL_0_TRDY,  // PHY0 ready for transmit-flit data.
    input  logic                                        I_FDI_PL_0_STALLREQ,  // PHY0 stall request.
    input  logic [3:0]                                  I_FDI_PL_0_STATE_STS,  // PHY0 state status.
    output logic [FDI_IF_WD0-1:0]                       O_FDI_LP_0_DATA,  // PHY0 transmit-flit data.
    output logic                                        O_FDI_LP_0_VALID,  // PHY0 transmit-flit valid.
    output logic                                        O_FDI_LP_0_IRDY,  // PHY0 transmit initiator ready.
    output logic                                        O_FDI_LP_0_STALLACK,  // PHY0 stall acknowledge.

`ifdef TWO_PHY
    input  logic                                        I_FDI_PL_1_VALID,  // PHY1 received-flit valid.
    input  logic [FDI_IF_WD1-1:0]                       I_FDI_PL_1_DATA,  // PHY1 received-flit data.
    input  logic                                        I_FDI_PL_1_FLIT_CANCEL,  // PHY1 flit cancel.

    input  logic                                        I_FDI_PL_1_TRDY,  // PHY1 ready for transmit-flit data.
    input  logic                                        I_FDI_PL_1_STALLREQ,  // PHY1 stall request.
    input  logic [3:0]                                  I_FDI_PL_1_STATE_STS,  // PHY1 state status.
    output logic [FDI_IF_WD1-1:0]                       O_FDI_LP_1_DATA,  // PHY1 transmit-flit data.
    output logic                                        O_FDI_LP_1_VALID,  // PHY1 transmit-flit valid.
    output logic                                        O_FDI_LP_1_IRDY,  // PHY1 transmit initiator ready.
    output logic                                        O_FDI_LP_1_STALLACK,  // PHY1 stall acknowledge.
`endif

    input  logic                                        I_PL_INBAND_PRES,  // PHY in-band presence.
    input  logic                                        I_PL_CLK_REQ,  // PHY clock request.
    input  logic                                        I_PL_WAKE_ACK,  // PHY wake acknowledge.
    input  logic                                        I_PL_RX_ACTIVE_REQ,  // PHY rx-active request.

    output logic [3:0]                                  O_LP_STATE_REQ,  // Link state request to the PHY.
    output logic                                        O_LP_WAKE_REQ,  // Wake request to the PHY.
    output logic                                        O_LP_CLK_ACK,  // Clock acknowledge to the PHY.
    output logic                                        O_LP_RX_ACTIVE_STS,  // Rx-active status to the PHY.
    output logic                                        O_LP_LINKERROR,  // Link error request to the PHY.

    input  logic                                        I_SW_ACTIVATE_START,  // Software request to start activation.
    input  logic                                        I_SW_LINKERROR_INJECT,  // Software request to inject a link error.

    output logic [3:0]                                  O_FDI_FSM_STATE,  // FDI bringup FSM state.
    output logic                                        O_FDI_LINK_UP,  // FDI link is up.

    output logic                                        INT_REQ_LINKRESET,  // Link reset request interrupt.
    output logic                                        INT_SI0_ID_MISMATCH,  // AXI slave ID mismatch interrupt.
    output logic                                        INT_MI0_ID_MISMATCH,  // AXI master ID mismatch interrupt.
    output logic                                        INT_EARLY_RESP_ERR,  // Early-response error interrupt.
    output logic                                        INT_EARLY_WDT_ERR,  // Write-transaction watchdog timeout interrupt.
    output logic                                        INT_ACTIVATE_START,  // Activation start interrupt from the AOU core.
                                                                             // Also drives the bringup controller.
    output logic                                        INT_DEACTIVATE_START,  // Deactivation start interrupt from the AOU core.
    output logic                                        INT_FDI_LINK_DOWN,  // FDI link lost while AoU was in use.

    input  logic                                        TIEL_DFT_MODESCAN  // DFT scan mode. Tie low for functional operation.
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
        .O_AOU_RX_AXI_M_ARUSER      ( O_AOU_RX_AXI_M_ARUSER         ),
        .O_AOU_RX_AXI_M_ARVALID     ( O_AOU_RX_AXI_M_ARVALID        ),
        .I_AOU_RX_AXI_M_ARREADY     ( I_AOU_RX_AXI_M_ARREADY        ),

        .I_AOU_TX_AXI_M_RID         ( I_AOU_TX_AXI_M_RID            ),
        .I_AOU_TX_AXI_M_RDATA       ( I_AOU_TX_AXI_M_RDATA          ),
        .I_AOU_TX_AXI_M_RRESP       ( I_AOU_TX_AXI_M_RRESP          ),
        .I_AOU_TX_AXI_M_RUSER       ( I_AOU_TX_AXI_M_RUSER          ),
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
        .O_AOU_RX_AXI_M_AWUSER      ( O_AOU_RX_AXI_M_AWUSER         ),
        .O_AOU_RX_AXI_M_AWVALID     ( O_AOU_RX_AXI_M_AWVALID        ),
        .I_AOU_RX_AXI_M_AWREADY     ( I_AOU_RX_AXI_M_AWREADY        ),

        .O_AOU_RX_AXI_M_WDATA       ( O_AOU_RX_AXI_M_WDATA          ),
        .O_AOU_RX_AXI_M_WSTRB       ( O_AOU_RX_AXI_M_WSTRB          ),
        .O_AOU_RX_AXI_M_WLAST       ( O_AOU_RX_AXI_M_WLAST          ),
        .O_AOU_RX_AXI_M_WUSER       ( O_AOU_RX_AXI_M_WUSER          ),
        .O_AOU_RX_AXI_M_WVALID      ( O_AOU_RX_AXI_M_WVALID         ),
        .I_AOU_RX_AXI_M_WREADY      ( I_AOU_RX_AXI_M_WREADY         ),

        .I_AOU_TX_AXI_M_BID         ( I_AOU_TX_AXI_M_BID            ),
        .I_AOU_TX_AXI_M_BRESP       ( I_AOU_TX_AXI_M_BRESP          ),
        .I_AOU_TX_AXI_M_BUSER       ( I_AOU_TX_AXI_M_BUSER          ),
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
        .I_AOU_TX_AXI_S_ARUSER      ( I_AOU_TX_AXI_S_ARUSER         ),
        .I_AOU_TX_AXI_S_ARVALID     ( I_AOU_TX_AXI_S_ARVALID        ),
        .O_AOU_TX_AXI_S_ARREADY     ( O_AOU_TX_AXI_S_ARREADY        ),

        .O_AOU_RX_AXI_S_RID         ( O_AOU_RX_AXI_S_RID            ),
        .O_AOU_RX_AXI_S_RDATA       ( O_AOU_RX_AXI_S_RDATA          ),
        .O_AOU_RX_AXI_S_RRESP       ( O_AOU_RX_AXI_S_RRESP          ),
        .O_AOU_RX_AXI_S_RLAST       ( O_AOU_RX_AXI_S_RLAST          ),
        .O_AOU_RX_AXI_S_RUSER       ( O_AOU_RX_AXI_S_RUSER          ),
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
        .I_AOU_TX_AXI_S_AWUSER      ( I_AOU_TX_AXI_S_AWUSER         ),
        .I_AOU_TX_AXI_S_AWVALID     ( I_AOU_TX_AXI_S_AWVALID        ),
        .O_AOU_TX_AXI_S_AWREADY     ( O_AOU_TX_AXI_S_AWREADY        ),

        .I_AOU_TX_AXI_S_WDATA       ( I_AOU_TX_AXI_S_WDATA          ),
        .I_AOU_TX_AXI_S_WSTRB       ( I_AOU_TX_AXI_S_WSTRB          ),
        .I_AOU_TX_AXI_S_WLAST       ( I_AOU_TX_AXI_S_WLAST          ),
        .I_AOU_TX_AXI_S_WUSER       ( I_AOU_TX_AXI_S_WUSER          ),
        .I_AOU_TX_AXI_S_WVALID      ( I_AOU_TX_AXI_S_WVALID         ),
        .O_AOU_TX_AXI_S_WREADY      ( O_AOU_TX_AXI_S_WREADY         ),

        .O_AOU_RX_AXI_S_BID         ( O_AOU_RX_AXI_S_BID            ),
        .O_AOU_RX_AXI_S_BRESP       ( O_AOU_RX_AXI_S_BRESP          ),
        .O_AOU_RX_AXI_S_BUSER       ( O_AOU_RX_AXI_S_BUSER          ),
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
