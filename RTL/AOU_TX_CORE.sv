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
//  Module     : AOU_TX_CORE
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TX_CORE
import packet_def_pkg::*;
#(
    parameter   RP_CNT              = 4,
    parameter   RP0_AXI_DATA_WD     = 512,
    parameter   RP1_AXI_DATA_WD     = 512,
    parameter   RP2_AXI_DATA_WD     = 512,
    parameter   RP3_AXI_DATA_WD     = 512,
    parameter   MAX_AXI_DATA_WD     = 1024,
    parameter   AXI_ADDR_WD         = 64,
    parameter   AXI_ID_WD           = 10,
    parameter   AXI_LEN_WD          = 8,
    localparam  RP0_AXI_STRB_WD     = RP0_AXI_DATA_WD / 8,
    localparam  RP1_AXI_STRB_WD     = RP1_AXI_DATA_WD / 8,
    localparam  RP2_AXI_STRB_WD     = RP2_AXI_DATA_WD / 8,
    localparam  RP3_AXI_STRB_WD     = RP3_AXI_DATA_WD / 8,
    localparam  MAX_AXI_STRB_WD     = MAX_AXI_DATA_WD / 8,

    parameter   FDI_IF_WD0          = 512,
    parameter   FDI_IF_WD1          = 512,

    // TX flit packer output stage. 0: the flit chunk is driven combinationally
    // from the granule ring (current packing state). 1: the chunk is computed
    // from the look-ahead (next) packing state and registered before the FDI
    // output mux.
    parameter   TX_NXT_PACKING_EN   = 0,

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

    localparam  CNT_RP_AW_MAX_CREDIT_MAX = max4(CNT_RP0_AW_MAX_CREDIT, CNT_RP1_AW_MAX_CREDIT, CNT_RP2_AW_MAX_CREDIT, CNT_RP3_AW_MAX_CREDIT),
    localparam  CNT_RP_AR_MAX_CREDIT_MAX = max4(CNT_RP0_AR_MAX_CREDIT, CNT_RP1_AR_MAX_CREDIT, CNT_RP2_AR_MAX_CREDIT, CNT_RP3_AR_MAX_CREDIT),
    localparam  CNT_RP_W_MAX_CREDIT_MAX  = max4(CNT_RP0_W_MAX_CREDIT,  CNT_RP1_W_MAX_CREDIT,  CNT_RP2_W_MAX_CREDIT,  CNT_RP3_W_MAX_CREDIT),
    localparam  CNT_RP_R_MAX_CREDIT_MAX  = max4(CNT_RP0_R_MAX_CREDIT,  CNT_RP1_R_MAX_CREDIT,  CNT_RP2_R_MAX_CREDIT,  CNT_RP3_R_MAX_CREDIT),
    localparam  CNT_RP_B_MAX_CREDIT_MAX  = max4(CNT_RP0_B_MAX_CREDIT,  CNT_RP1_B_MAX_CREDIT,  CNT_RP2_B_MAX_CREDIT,  CNT_RP3_B_MAX_CREDIT),

    localparam  AOU_TX_AW_FIFO_DEPTH  = 2,
    localparam  AOU_TX_W_FIFO_DEPTH   = 2,
    localparam  AOU_TX_B_FIFO_DEPTH   = 2,
    localparam  AOU_TX_AR_FIFO_DEPTH  = 2,
    localparam  AOU_TX_R_FIFO_DEPTH   = 2,
    localparam  AOU_MISC_FIFO_DEPTH   = 2
)
(
    input  logic                                                I_CLK,
    input  logic                                                I_RESETN,

    //-----------------------------------------------------------------
    //  Interface for AXI RP0
    //-----------------------------------------------------------------
    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]                 I_AOU_TX_AXI_AWID,
    input  logic    [RP_CNT-1:0][AXI_ADDR_WD-1:0]               I_AOU_TX_AXI_AWADDR,
    input  logic    [RP_CNT-1:0][AXI_LEN_WD-1:0]                I_AOU_TX_AXI_AWLEN,
    input  logic    [RP_CNT-1:0][2:0]                           I_AOU_TX_AXI_AWSIZE,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_AWBURST,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_AWLOCK,
    input  logic    [RP_CNT-1:0][3:0]                           I_AOU_TX_AXI_AWCACHE,
    input  logic    [RP_CNT-1:0][2:0]                           I_AOU_TX_AXI_AWPROT,
    input  logic    [RP_CNT-1:0][3:0]                           I_AOU_TX_AXI_AWQOS,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_AWVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_AWREADY,

    input  logic    [RP_CNT-1:0][MAX_AXI_DATA_WD-1:0]           I_AOU_TX_AXI_WDATA,
    input  logic    [RP_CNT-1:0][MAX_AXI_STRB_WD-1:0]           I_AOU_TX_AXI_WSTRB,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_WLAST,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_WVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_WREADY,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]                 I_AOU_TX_AXI_ARID,
    input  logic    [RP_CNT-1:0][AXI_ADDR_WD-1:0]               I_AOU_TX_AXI_ARADDR,
    input  logic    [RP_CNT-1:0][AXI_LEN_WD-1:0]                I_AOU_TX_AXI_ARLEN,
    input  logic    [RP_CNT-1:0][2:0]                           I_AOU_TX_AXI_ARSIZE,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_ARBURST,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_ARLOCK,
    input  logic    [RP_CNT-1:0][3:0]                           I_AOU_TX_AXI_ARCACHE,
    input  logic    [RP_CNT-1:0][2:0]                           I_AOU_TX_AXI_ARPROT,
    input  logic    [RP_CNT-1:0][3:0]                           I_AOU_TX_AXI_ARQOS,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_ARVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_ARREADY,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]                 I_AOU_TX_AXI_BID_256,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_BRESP_256,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_BVALID_256,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_BREADY_256,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]                 I_AOU_TX_AXI_BID_512,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_BRESP_512,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_BVALID_512,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_BREADY_512,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]                 I_AOU_TX_AXI_BID_1024,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_BRESP_1024,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_BVALID_1024,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_BREADY_1024,

    input  logic    [RP_CNT-1:0][AXI_ID_WD-1:0]                 I_AOU_TX_AXI_RID,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_RDLEN,
    input  logic    [RP_CNT-1:0][1023:0]                        I_AOU_TX_AXI_RDATA,
    input  logic    [RP_CNT-1:0][1:0]                           I_AOU_TX_AXI_RRESP,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_RLAST,
    input  logic    [RP_CNT-1:0]                                I_AOU_TX_AXI_RVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_AXI_RREADY,

    //Interface for RX MsgCredit - header
    input  logic    [2:0]                                       I_AOU_MSGCREDIT_WREQCRED,
    input  logic    [2:0]                                       I_AOU_MSGCREDIT_RREQCRED,
    input  logic    [2:0]                                       I_AOU_MSGCREDIT_WDATACRED,
    input  logic    [2:0]                                       I_AOU_MSGCREDIT_RDATACRED,
    input  logic    [1:0]                                       I_AOU_MSGCREDIT_WRESPCRED,
    input  logic    [1:0]                                       I_AOU_MSGCREDIT_RP,
    input  logic                                                I_AOU_MSGCREDIT_CRED_VALID,
    output logic                                                O_AOU_MSGCREDIT_CRED_READY,

    // //Interface for Misc Message - Credit
    input  logic    [1:0]                                       I_AOU_CRDTGRANT_WRESPCRED3,
    input  logic    [1:0]                                       I_AOU_CRDTGRANT_WRESPCRED2,
    input  logic    [1:0]                                       I_AOU_CRDTGRANT_WRESPCRED1,
    input  logic    [1:0]                                       I_AOU_CRDTGRANT_WRESPCRED0,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RDATACRED3,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RDATACRED2,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RDATACRED1,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RDATACRED0,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WDATACRED3,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WDATACRED2,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WDATACRED1,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WDATACRED0,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RREQCRED3,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RREQCRED2,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RREQCRED1,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_RREQCRED0,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WREQCRED3,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WREQCRED2,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WREQCRED1,
    input  logic    [2:0]                                       I_AOU_CRDTGRANT_WREQCRED0,
    input  logic                                                I_AOU_CRDTGRANT_VALID,
    output logic                                                O_AOU_CRDTGRANT_READY,

    // Interface for Misc Message - Activation
    input  logic     [3:0]                                      I_AOU_ACTIVATION_OP,
    input  logic                                                I_AOU_ACTIVATION_PROP_REQ,
    input  logic                                                I_AOU_ACTIVATION_VALID,
    output logic                                                O_AOU_ACTIVATION_READY,

    // State for TX_CORE fifo
    output logic                                                O_AOU_TX_PENDING,
    output logic                                                O_AOU_TX_AXI_TR_PENDING,

    //Interface for TX Credit - credit input
    input  logic    [RP_CNT-1:0][CNT_RP_AW_MAX_CREDIT_MAX-1:0]  I_AOU_TX_WREQCRED,
    input  logic    [RP_CNT-1:0][CNT_RP_AR_MAX_CREDIT_MAX-1:0]  I_AOU_TX_RREQCRED,
    input  logic    [RP_CNT-1:0][CNT_RP_W_MAX_CREDIT_MAX -1:0]  I_AOU_TX_WDATACRED,
    input  logic    [RP_CNT-1:0][CNT_RP_R_MAX_CREDIT_MAX -1:0]  I_AOU_TX_RDATACRED,
    input  logic    [RP_CNT-1:0][CNT_RP_B_MAX_CREDIT_MAX -1:0]  I_AOU_TX_WRESPCRED,

    //Interface for TX Credit - transaction valid
    output logic    [RP_CNT-1:0]                                O_AOU_TX_WREQVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_RREQVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_WDATAVALID,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_WFDATA,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_RDATAVALID,
    output logic    [RP_CNT-1:0][1:0]                           O_AOU_TX_RDATA_DLENGTH,
    output logic    [RP_CNT-1:0]                                O_AOU_TX_WRESPVALID,


    input  logic                                                I_AOU_WRITEFULL_MSGTYPE_EN,

    input  logic    [7:0]                                       I_AOU_TX_LP_MODE_THRESHOLD,
    input  logic                                                I_AOU_TX_LP_MODE,

    //Interface for FDI
    input  logic                                                I_FDI_PL_TRDY_0,
    output logic [FDI_IF_WD0-1:0]                               O_FDI_LP_DATA_0,
    output logic                                                O_FDI_LP_VALID_0,

`ifdef TWO_PHY
    input  logic                                                I_PHY_TYPE,

    input  logic                                                I_FDI_PL_TRDY_1,
    output logic [FDI_IF_WD1-1:0]                               O_FDI_LP_DATA_1,
    output logic                                                O_FDI_LP_VALID_1,

`endif

    input  logic                                                I_STATUS_DISABLED,
    input  logic                                                I_STATUS_ENABLED,
    input  logic [3:0][1:0]                                     I_RP_DEST_RP,
    input  logic [3:0]                                          I_PRIOR_RP_AXI_AXI_QOS_TO_NP,
    input  logic [3:0]                                          I_PRIOR_RP_AXI_AXI_QOS_TO_HP,
    input  logic [1:0]                                          I_PRIOR_RP_AXI_RP3_PRIOR,
    input  logic [1:0]                                          I_PRIOR_RP_AXI_RP2_PRIOR,
    input  logic [1:0]                                          I_PRIOR_RP_AXI_RP1_PRIOR,
    input  logic [1:0]                                          I_PRIOR_RP_AXI_RP0_PRIOR,
    input  logic [1:0]                                          I_PRIOR_RP_AXI_ARB_MODE,
    input  logic [15:0]                                         I_PRIOR_TIMER_TIMER_RESOLUTION,
    input  logic [15:0]                                         I_PRIOR_TIMER_TIMER_THRESHOLD,
    input  logic                                                I_TX_REQ_CREDIT_BLOCKn,
    input  logic                                                I_TX_RSP_CREDIT_BLOCKn        

);
// Flit-packing parameters derived from FDI data width.
//   "Active" width for packing = max(FDI_IF_WD0, FDI_IF_WD1) so both
//   single-PHY (WD1 defaults to 512) and two-PHY configurations select the
//   same packing pipeline depth as the original FDI_*B defines:
//     FDI_PACK_WD == 1024 -> 2-step pack (half-flit at a time, 24 granules)
//     FDI_PACK_WD <= 512  -> 4-step pack (quarter-flit at a time, 12 granules)
localparam int FDI_PACK_WD           = (FDI_IF_WD0 > FDI_IF_WD1) ? FDI_IF_WD0 : FDI_IF_WD1;
localparam int FLIT_PACK_STATE_W     = (FDI_PACK_WD == 1024) ? 1 : 2;
localparam int FLIT_PACK_GRANULE_CNT = (FDI_PACK_WD == 1024) ? 24 : 12;
localparam logic [FLIT_PACK_STATE_W-1:0] FLIT_LAST_PACK_STATE = {FLIT_PACK_STATE_W{1'b1}};

localparam RP0_NO_STRB_W_G_SIZE  = (RP0_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP0_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP0_AXI_DATA_WD == 1024)? WF1024b_G : 0;

localparam RP0_W_G_SIZE          = (RP0_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP0_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP0_AXI_DATA_WD == 1024)? W1024b_G : 0;

localparam RP1_NO_STRB_W_G_SIZE  = (RP1_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP1_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP1_AXI_DATA_WD == 1024)? WF1024b_G : 0;

localparam RP1_W_G_SIZE          = (RP1_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP1_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP1_AXI_DATA_WD == 1024)? W1024b_G : 0;

localparam RP2_NO_STRB_W_G_SIZE  = (RP2_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP2_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP2_AXI_DATA_WD == 1024)? WF1024b_G : 0;

localparam RP2_W_G_SIZE          = (RP2_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP2_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP2_AXI_DATA_WD == 1024)? W1024b_G : 0;

localparam RP3_NO_STRB_W_G_SIZE  = (RP3_AXI_DATA_WD == 256) ? WF256b_G  :
                                    (RP3_AXI_DATA_WD == 512) ? WF512b_G  :
                                    (RP3_AXI_DATA_WD == 1024)? WF1024b_G : 0;

localparam RP3_W_G_SIZE          = (RP3_AXI_DATA_WD == 256) ? W256b_G  :
                                    (RP3_AXI_DATA_WD == 512) ? W512b_G  :
                                    (RP3_AXI_DATA_WD == 1024)? W1024b_G : 0;

localparam int RP_AXI_DATA_WD [4] = '{RP0_AXI_DATA_WD, RP1_AXI_DATA_WD, RP2_AXI_DATA_WD, RP3_AXI_DATA_WD};
localparam int RP_AXI_STRB_WD [4] = '{RP0_AXI_STRB_WD, RP1_AXI_STRB_WD, RP2_AXI_STRB_WD, RP3_AXI_STRB_WD};
localparam int RP_W_G_SIZE [4] = '{RP0_W_G_SIZE, RP1_W_G_SIZE, RP2_W_G_SIZE, RP3_W_G_SIZE};
localparam int RP_NO_STRB_W_G_SIZE [4] = '{RP0_NO_STRB_W_G_SIZE, RP1_NO_STRB_W_G_SIZE, RP2_NO_STRB_W_G_SIZE, RP3_NO_STRB_W_G_SIZE};

localparam RING_DEPTH = 128;
localparam RING_CNT   = $clog2(RING_DEPTH+1);

logic [1:0] w_aou_fifo_ar_rp, w_aou_fifo_r_rp, w_aou_fifo_aw_rp, w_aou_fifo_w_rp, w_aou_fifo_b_rp;

logic   [AXI_ID_WD-1:0]         w_aou_fifo_awid;
logic   [AXI_ADDR_WD-1:0]       w_aou_fifo_awaddr;
logic   [AXI_LEN_WD-1:0]        w_aou_fifo_awlen;
logic   [2:0]                   w_aou_fifo_awsize;
logic                           w_aou_fifo_awlock;
logic   [3:0]                   w_aou_fifo_awcache;
logic   [2:0]                   w_aou_fifo_awprot;
logic   [3:0]                   w_aou_fifo_awqos;
logic                           w_aou_fifo_awvalid;
logic                           w_aou_fifo_awready;

logic   [MAX_AXI_DATA_WD-1:0]   w_aou_fifo_wdata;
logic   [MAX_AXI_STRB_WD-1:0]   w_aou_fifo_wstrb;
logic                           w_aou_fifo_wstrb_full;
logic                           w_aou_fifo_wlast;
logic                           w_aou_fifo_wvalid;
logic                           w_aou_fifo_wready;

logic   [AXI_ID_WD-1:0]         w_aou_fifo_arid;
logic   [AXI_ADDR_WD-1:0]       w_aou_fifo_araddr;
logic   [AXI_LEN_WD-1:0]        w_aou_fifo_arlen;
logic   [2:0]                   w_aou_fifo_arsize;
logic                           w_aou_fifo_arlock;
logic   [3:0]                   w_aou_fifo_arcache;
logic   [2:0]                   w_aou_fifo_arprot;
logic   [3:0]                   w_aou_fifo_arqos;
logic                           w_aou_fifo_arvalid;
logic                           w_aou_fifo_arready;

logic    [AXI_ID_WD-1:0]        w_aou_fifo_bid;
logic    [1:0]                  w_aou_fifo_bresp;
logic                           w_aou_fifo_bvalid;
logic                           w_aou_fifo_bready;

logic    [AXI_ID_WD-1:0]        w_aou_fifo_rid;
logic    [1024-1:0]             w_aou_fifo_rdata;
logic    [1:0]                  w_aou_fifo_rresp;
logic                           w_aou_fifo_rlast;
logic    [1:0]                  w_aou_fifo_rdlen;
logic                           w_aou_fifo_rvalid;
logic                           w_aou_fifo_rready;

logic    [40*2-1:0]             w_misc_crdtgrant_message;
logic    [56-1:0]               w_misc_crdtgrant_payload;
logic                           w_misc_crdtgrant_fifo_valid;
logic                           w_misc_crdtgrant_fifo_ready;

logic    [39:0]                 w_misc_activate_message;
logic    [3:0]                  w_misc_activation_op;
logic                           w_misc_activation_prop_req;
logic                           w_misc_activation_valid;
logic                           w_misc_activation_ready;

logic                           w_aou_tx_axi_hs;
logic    [RP_CNT-1:0]           w_aou_tx_b_fifo_svalid;
integer unsigned i, j;

logic   w_aou_fifo_ar_hs;
logic   w_aou_fifo_aw_hs;
logic   w_aou_fifo_w_hs;
logic   w_aou_fifo_b_hs;
logic   w_aou_fifo_r_hs;
logic   w_aou_fifo_misc_crd_hs;
logic   w_aou_fifo_misc_act_hs;

logic  [RP_CNT-1:0] w_aou_tx_aw_hs     ;
logic  [RP_CNT-1:0] w_aou_tx_w_hs      ;
logic  [RP_CNT-1:0] w_aou_tx_b_256_hs  ;
logic  [RP_CNT-1:0] w_aou_tx_b_512_hs  ;
logic  [RP_CNT-1:0] w_aou_tx_b_1024_hs ;
logic  [RP_CNT-1:0] w_aou_tx_ar_hs     ;
logic  [RP_CNT-1:0] w_aou_tx_r_hs      ;

logic   w_rdata_256b;
logic   w_rdata_512b;



assign  w_aou_fifo_aw_hs        = w_aou_fifo_awvalid && w_aou_fifo_awready;
assign  w_aou_fifo_w_hs         = w_aou_fifo_wvalid && w_aou_fifo_wready;
assign  w_aou_fifo_b_hs         = w_aou_fifo_bvalid && w_aou_fifo_bready;
assign  w_aou_fifo_ar_hs        = w_aou_fifo_arvalid && w_aou_fifo_arready;
assign  w_aou_fifo_r_hs         = w_aou_fifo_rvalid && w_aou_fifo_rready;

assign  w_aou_fifo_misc_crd_hs      = w_misc_crdtgrant_fifo_valid && w_misc_crdtgrant_fifo_ready;
assign  w_aou_fifo_misc_act_hs      = w_misc_activation_valid && w_misc_activation_ready;

always_comb begin
    for (int unsigned i = 0; i < RP_CNT ; i++) begin
        w_aou_tx_aw_hs     [i] = I_AOU_TX_AXI_AWVALID     [i]  && O_AOU_TX_AXI_AWREADY      [i];
        w_aou_tx_w_hs      [i] = I_AOU_TX_AXI_WVALID      [i]  && O_AOU_TX_AXI_WREADY       [i];
        w_aou_tx_b_256_hs  [i] = I_AOU_TX_AXI_BVALID_256  [i]  && O_AOU_TX_AXI_BREADY_256   [i];
        w_aou_tx_b_512_hs  [i] = I_AOU_TX_AXI_BVALID_512  [i]  && O_AOU_TX_AXI_BREADY_512   [i];
        w_aou_tx_b_1024_hs [i] = I_AOU_TX_AXI_BVALID_1024 [i]  && O_AOU_TX_AXI_BREADY_1024  [i];
        w_aou_tx_ar_hs     [i] = I_AOU_TX_AXI_ARVALID     [i]  && O_AOU_TX_AXI_ARREADY      [i];
        w_aou_tx_r_hs      [i] = I_AOU_TX_AXI_RVALID      [i]  && O_AOU_TX_AXI_RREADY       [i];
    end
end


assign  w_aou_tx_axi_hs = ((|w_aou_tx_aw_hs) || (|w_aou_tx_w_hs) || (|w_aou_tx_b_256_hs) || (|w_aou_tx_b_512_hs) ||
                        (|w_aou_tx_b_1024_hs) || (|w_aou_tx_ar_hs) || (|w_aou_tx_r_hs));

logic       r_tx_activation_valid;

//4 stage for FDI_32B/64B & 2 stage for FDI_128B
typedef logic [FLIT_PACK_STATE_W-1:0] flit_packing_state_t;

flit_packing_state_t r_flit_packing_state;
flit_packing_state_t nxt_flit_packing_state;

//reg
logic [40-1:0]                   r_granule_buffer [RING_DEPTH-1:0];          //128 Granule buffer
logic                            r_msgstart_buffer [RING_DEPTH-1:0];
logic [40-1:0]                   nxt_granule_buffer [RING_DEPTH-1:0];          //128 Granule buffer
logic                            nxt_msgstart_buffer [RING_DEPTH-1:0];
logic [RING_CNT-1:0]             r_cur_granule_start;
logic [RING_CNT-1:0]             nxt_granule_start;
logic [RING_CNT-1:0]             w_cur_granule_end;
logic [RING_CNT-1:0]             r_cur_flit_for_fifo_start;
logic [RING_CNT-1:0]             nxt_flit_for_fifo_start;

//wire
logic [RING_CNT-1:0]             w_aw_message_start_idx;
logic [RING_CNT-1:0]             w_w_message_start_idx;
logic [RING_CNT-1:0]             w_b_message_start_idx;
logic [RING_CNT-1:0]             w_ar_message_start_idx;
logic [RING_CNT-1:0]             w_r_message_start_idx;
logic [RING_CNT-1:0]             w_misc_crdt_start_idx;
logic [RING_CNT-1:0]             w_misc_activate_start_idx;


logic [40*AW_G-1:0]              w_writereq_message;
logic [40*W1024b_G-1:0]          w_writedata_message;
logic [40*WF1024b_G-1:0]         w_writedata_wo_strb_message;
logic [40*B_G-1:0]               w_writeresp_message;
logic [40*AR_G-1:0]              w_readreq_message;
logic [40*R256b_G-1:0]           w_readdata256b_message;
logic [40*R512b_G-1:0]           w_readdata512b_message;
logic [40*R1024b_G-1:0]          w_readdata1024b_message;

logic     [40*AW_G-1:0]          w_aou_tx_m_axi_aw_message;
logic     [40*W1024b_G-1:0]      w_aou_tx_m_axi_w_message;
logic     [40*B_G-1:0]           w_aou_tx_m_axi_b_message;
logic     [40*R1024b_G-1:0]      w_aou_tx_m_axi_r_message;
logic     [40*AR_G-1:0]          w_aou_tx_m_axi_ar_message;


logic [40-1:0]      w_misc_activate_message_byteswap;
logic [40*2-1:0]    w_misc_crdtgrant_message_byteswap;

logic [RP_CNT-1:0][40*W1024b_G-1:0 ]  w_writedata_message_rp;
logic [RP_CNT-1:0][40*WF1024b_G-1:0]  w_writedata_wo_strb_message_rp;


logic                       w_flit_fifo_valid;
logic                       w_flit_fifo_ready;

logic                       w_ring_buffer_ready;
logic                       r_ring_buffer_ready;

assign  w_rdata_256b    = (w_aou_fifo_rdlen == 2'b00);
assign  w_rdata_512b    = (w_aou_fifo_rdlen == 2'b01);


//assume maximum granule is not larger than 64
logic [5:0]  w_rdata_granule_size;
logic [5:0]  w_wdata_granule_size;

always_comb begin
    case (w_aou_fifo_rdlen)
        2'b00: w_rdata_granule_size = R256b_G;
        2'b01: w_rdata_granule_size = R512b_G;
        2'b10: w_rdata_granule_size = R1024b_G;
        default: w_rdata_granule_size = 0;
    endcase
end

always_comb begin
    w_wdata_granule_size = 0;
    for (int unsigned i = 0 ; i < RP_CNT ; i ++) begin
        if (i == w_aou_fifo_w_rp) begin
            w_wdata_granule_size = (I_AOU_WRITEFULL_MSGTYPE_EN && w_aou_fifo_wstrb_full) ? RP_NO_STRB_W_G_SIZE[i] : RP_W_G_SIZE[i];
        end
    end
end

assign w_ring_buffer_ready = (((r_cur_granule_start - r_cur_flit_for_fifo_start) & 8'b1111_1111 ) < (128 - (AW_G + w_wdata_granule_size + B_G + AR_G + w_rdata_granule_size) ));

// Forward declaration of LP-engaged gate; assigned at the definition site
// below once r_act_in_flight is declared. Hoisted here because the AW/W/B/
// AR/R/CrdtGrant pop gates reference it.
logic w_lp_engaged;

// AXI-message and CrdtGrant ring-buffer ingress gates.
//
// In single-PHY 32B (4-step packing) mode AOU_TX_CORE_OUT_MUX drives
// O_FDI_PL_TRDY (= w_flit_fifo_ready) high only on r_phase==1 cycles,
// and r_phase only advances when I_FDI_LP_VALID is asserted. In LP-
// engaged mode with no traffic w_flit_fifo_valid stays 0 by design, so
// the original gate (TRDY only) deadlocks: nothing can enter the ring,
// the ring stays empty, no flit ever fires, TRDY never pulses.
//
// The "ring empty + LP-engaged" override below allows a single seeding
// pop that lets the OUT_MUX advance r_phase. Once ring is non-empty
// (or any chunk of a flit is already in flight), w_flit_fifo_valid==1
// and the override is gone, restoring the original TRDY-paced semantics
// so r_flit_fifo_data stays stable across the OUT_MUX 2-cycle r_phase
// window (otherwise pops mid-flit corrupt the second half of the flit).
//
// w_ring_buffer_ready still provides full overflow protection, and
// non-LP behavior is byte-identical (w_lp_engaged == 0 outside LP-
// engaged mode).
wire w_pop_ok = w_flit_fifo_ready || (w_lp_engaged && !w_flit_fifo_valid);

assign w_aou_fifo_awready           = w_ring_buffer_ready && (!w_misc_activation_valid) && w_pop_ok && I_TX_REQ_CREDIT_BLOCKn;
assign w_aou_fifo_wready            = w_ring_buffer_ready && (!w_misc_activation_valid) && w_pop_ok && I_TX_REQ_CREDIT_BLOCKn;
assign w_aou_fifo_bready            = w_ring_buffer_ready && (!w_misc_activation_valid) && w_pop_ok && I_TX_RSP_CREDIT_BLOCKn;
assign w_aou_fifo_arready           = w_ring_buffer_ready && (!w_misc_activation_valid) && w_pop_ok && I_TX_REQ_CREDIT_BLOCKn;
assign w_aou_fifo_rready            = w_ring_buffer_ready && (!w_misc_activation_valid) && w_pop_ok && I_TX_RSP_CREDIT_BLOCKn;

assign w_misc_crdtgrant_fifo_ready  = w_ring_buffer_ready && (!w_misc_activation_valid) && w_pop_ok;

// w_misc_activation_ready uses w_lp_engaged (declared/forward-declared above)
// and is assigned here after r_flit_packing_state etc. are visible.
assign w_misc_activation_ready      = w_ring_buffer_ready && ( w_lp_engaged ? ((r_flit_packing_state == '0) && (r_cur_granule_start == r_cur_flit_for_fifo_start)) :
                                                                (!r_tx_activation_valid) || ((r_flit_packing_state == FLIT_LAST_PACK_STATE) && (r_cur_granule_start == r_cur_flit_for_fifo_start) && w_flit_fifo_ready));


typedef logic [RING_CNT-2:0] msg_idx;

function automatic msg_idx add_idx(input logic [RING_CNT-1:0] base, input int unsigned offset);
    return msg_idx'(base + msg_idx'(offset));
endfunction

AOU_TX_AXI_BUFFER
#(
    .RP_CNT                  ( RP_CNT                ),
    .RP0_AXI_DATA_WD         ( RP0_AXI_DATA_WD       ),
    .RP1_AXI_DATA_WD         ( RP1_AXI_DATA_WD       ),
    .RP2_AXI_DATA_WD         ( RP2_AXI_DATA_WD       ),
    .RP3_AXI_DATA_WD         ( RP3_AXI_DATA_WD       ),
    .AXI_ADDR_WD             ( AXI_ADDR_WD           ),
    .AXI_ID_WD               ( AXI_ID_WD             ),
    .AXI_LEN_WD              ( AXI_LEN_WD            ),
    .MAX_AXI_DATA_WD         ( MAX_AXI_DATA_WD       ),

    .AXI_AW_FIFO_DEPTH       ( AOU_TX_AW_FIFO_DEPTH  ),
    .AXI_W_FIFO_DEPTH        ( AOU_TX_W_FIFO_DEPTH   ),
    .AXI_B_FIFO_DEPTH        ( AOU_TX_B_FIFO_DEPTH   ),
    .AXI_AR_FIFO_DEPTH       ( AOU_TX_AR_FIFO_DEPTH  ),
    .AXI_R_FIFO_DEPTH        ( AOU_TX_R_FIFO_DEPTH   ),

    .CNT_RP0_AW_MAX_CREDIT   ( CNT_RP0_AW_MAX_CREDIT ),
    .CNT_RP0_W_MAX_CREDIT    ( CNT_RP0_W_MAX_CREDIT  ),
    .CNT_RP0_B_MAX_CREDIT    ( CNT_RP0_B_MAX_CREDIT  ),
    .CNT_RP0_AR_MAX_CREDIT   ( CNT_RP0_AR_MAX_CREDIT ),
    .CNT_RP0_R_MAX_CREDIT    ( CNT_RP0_R_MAX_CREDIT  ),

    .CNT_RP1_AW_MAX_CREDIT   ( CNT_RP1_AW_MAX_CREDIT ),
    .CNT_RP1_W_MAX_CREDIT    ( CNT_RP1_W_MAX_CREDIT  ),
    .CNT_RP1_B_MAX_CREDIT    ( CNT_RP1_B_MAX_CREDIT  ),
    .CNT_RP1_AR_MAX_CREDIT   ( CNT_RP1_AR_MAX_CREDIT ),
    .CNT_RP1_R_MAX_CREDIT    ( CNT_RP1_R_MAX_CREDIT  ),

    .CNT_RP2_AW_MAX_CREDIT   ( CNT_RP2_AW_MAX_CREDIT ),
    .CNT_RP2_W_MAX_CREDIT    ( CNT_RP2_W_MAX_CREDIT  ),
    .CNT_RP2_B_MAX_CREDIT    ( CNT_RP2_B_MAX_CREDIT  ),
    .CNT_RP2_AR_MAX_CREDIT   ( CNT_RP2_AR_MAX_CREDIT ),
    .CNT_RP2_R_MAX_CREDIT    ( CNT_RP2_R_MAX_CREDIT  ),

    .CNT_RP3_AW_MAX_CREDIT   ( CNT_RP3_AW_MAX_CREDIT ),
    .CNT_RP3_W_MAX_CREDIT    ( CNT_RP3_W_MAX_CREDIT  ),
    .CNT_RP3_B_MAX_CREDIT    ( CNT_RP3_B_MAX_CREDIT  ),
    .CNT_RP3_AR_MAX_CREDIT   ( CNT_RP3_AR_MAX_CREDIT ),
    .CNT_RP3_R_MAX_CREDIT    ( CNT_RP3_R_MAX_CREDIT  )
) u_aou_tx_axi_buffer
(
    .I_CLK                                  ( I_CLK                             ),
    .I_RESETN                               ( I_RESETN                          ),

    //Interface for RP0
    .I_AOU_TX_S_AXI_AWID                    ( I_AOU_TX_AXI_AWID                 ),
    .I_AOU_TX_S_AXI_AWADDR                  ( I_AOU_TX_AXI_AWADDR               ),
    .I_AOU_TX_S_AXI_AWLEN                   ( I_AOU_TX_AXI_AWLEN                ),
    .I_AOU_TX_S_AXI_AWSIZE                  ( I_AOU_TX_AXI_AWSIZE               ),
    .I_AOU_TX_S_AXI_AWBURST                 ( I_AOU_TX_AXI_AWBURST              ),
    .I_AOU_TX_S_AXI_AWLOCK                  ( I_AOU_TX_AXI_AWLOCK               ),
    .I_AOU_TX_S_AXI_AWCACHE                 ( I_AOU_TX_AXI_AWCACHE              ),
    .I_AOU_TX_S_AXI_AWPROT                  ( I_AOU_TX_AXI_AWPROT               ),
    .I_AOU_TX_S_AXI_AWQOS                   ( I_AOU_TX_AXI_AWQOS                ),
    .I_AOU_TX_S_AXI_AWVALID                 ( I_AOU_TX_AXI_AWVALID              ),
    .O_AOU_TX_S_AXI_AWREADY                 ( O_AOU_TX_AXI_AWREADY              ),

    .I_AOU_TX_S_AXI_WDATA                   ( I_AOU_TX_AXI_WDATA                ),
    .I_AOU_TX_S_AXI_WSTRB                   ( I_AOU_TX_AXI_WSTRB                ),
    .I_AOU_TX_S_AXI_WLAST                   ( I_AOU_TX_AXI_WLAST                ),
    .I_AOU_TX_S_AXI_WVALID                  ( I_AOU_TX_AXI_WVALID               ),
    .O_AOU_TX_S_AXI_WREADY                  ( O_AOU_TX_AXI_WREADY               ),

    .I_AOU_TX_S_AXI_ARID                    ( I_AOU_TX_AXI_ARID                 ),
    .I_AOU_TX_S_AXI_ARADDR                  ( I_AOU_TX_AXI_ARADDR               ),
    .I_AOU_TX_S_AXI_ARLEN                   ( I_AOU_TX_AXI_ARLEN                ),
    .I_AOU_TX_S_AXI_ARSIZE                  ( I_AOU_TX_AXI_ARSIZE               ),
    .I_AOU_TX_S_AXI_ARBURST                 ( I_AOU_TX_AXI_ARBURST              ),
    .I_AOU_TX_S_AXI_ARLOCK                  ( I_AOU_TX_AXI_ARLOCK               ),
    .I_AOU_TX_S_AXI_ARCACHE                 ( I_AOU_TX_AXI_ARCACHE              ),
    .I_AOU_TX_S_AXI_ARPROT                  ( I_AOU_TX_AXI_ARPROT               ),
    .I_AOU_TX_S_AXI_ARQOS                   ( I_AOU_TX_AXI_ARQOS                ),
    .I_AOU_TX_S_AXI_ARVALID                 ( I_AOU_TX_AXI_ARVALID              ),
    .O_AOU_TX_S_AXI_ARREADY                 ( O_AOU_TX_AXI_ARREADY              ),

    .I_AOU_TX_S_AXI_BID_256                 ( I_AOU_TX_AXI_BID_256              ),
    .I_AOU_TX_S_AXI_BRESP_256               ( I_AOU_TX_AXI_BRESP_256            ),
    .I_AOU_TX_S_AXI_BVALID_256              ( I_AOU_TX_AXI_BVALID_256           ),
    .O_AOU_TX_S_AXI_BREADY_256              ( O_AOU_TX_AXI_BREADY_256           ),

    .I_AOU_TX_S_AXI_BID_512                 ( I_AOU_TX_AXI_BID_512              ),
    .I_AOU_TX_S_AXI_BRESP_512               ( I_AOU_TX_AXI_BRESP_512            ),
    .I_AOU_TX_S_AXI_BVALID_512              ( I_AOU_TX_AXI_BVALID_512           ),
    .O_AOU_TX_S_AXI_BREADY_512              ( O_AOU_TX_AXI_BREADY_512           ),

    .I_AOU_TX_S_AXI_BID_1024                ( I_AOU_TX_AXI_BID_1024             ),
    .I_AOU_TX_S_AXI_BRESP_1024              ( I_AOU_TX_AXI_BRESP_1024           ),
    .I_AOU_TX_S_AXI_BVALID_1024             ( I_AOU_TX_AXI_BVALID_1024          ),
    .O_AOU_TX_S_AXI_BREADY_1024             ( O_AOU_TX_AXI_BREADY_1024          ),

    .I_AOU_TX_S_AXI_RID                     ( I_AOU_TX_AXI_RID                  ),
    .I_AOU_TX_S_AXI_RDLEN                   ( I_AOU_TX_AXI_RDLEN                ),
    .I_AOU_TX_S_AXI_RDATA                   ( I_AOU_TX_AXI_RDATA                ),
    .I_AOU_TX_S_AXI_RRESP                   ( I_AOU_TX_AXI_RRESP                ),
    .I_AOU_TX_S_AXI_RLAST                   ( I_AOU_TX_AXI_RLAST                ),
    .I_AOU_TX_S_AXI_RVALID                  ( I_AOU_TX_AXI_RVALID               ),
    .O_AOU_TX_S_AXI_RREADY                  ( O_AOU_TX_AXI_RREADY               ),


    //Output
    .O_AOU_TX_M_AXI_AW_MESSAGE              ( w_aou_tx_m_axi_aw_message         ),
    .O_AOU_TX_M_AXI_AWVALID                 ( w_aou_fifo_awvalid                ),
    .I_AOU_TX_M_AXI_AWREADY                 ( w_aou_fifo_awready                ),

    .O_AOU_TX_M_AXI_W_RP                    ( w_aou_fifo_w_rp                   ),//only w channel rp is source rp
    .O_AOU_TX_M_AXI_WSTRB_FULL              ( w_aou_fifo_wstrb_full             ),
    .O_AOU_TX_M_AXI_W_MESSAGE               ( w_aou_tx_m_axi_w_message          ),
    .O_AOU_TX_M_AXI_WVALID                  ( w_aou_fifo_wvalid                 ),
    .I_AOU_TX_M_AXI_WREADY                  ( w_aou_fifo_wready                 ),

    .O_AOU_TX_M_AXI_B_MESSAGE               ( w_aou_tx_m_axi_b_message          ),
    .O_AOU_TX_M_AXI_BVALID                  ( w_aou_fifo_bvalid                 ),
    .I_AOU_TX_M_AXI_BREADY                  ( w_aou_fifo_bready                 ),

    .O_AOU_TX_M_AXI_AR_MESSAGE              ( w_aou_tx_m_axi_ar_message         ),
    .O_AOU_TX_M_AXI_ARVALID                 ( w_aou_fifo_arvalid                ),
    .I_AOU_TX_M_AXI_ARREADY                 ( w_aou_fifo_arready                ),

    .O_AOU_TX_M_AXI_RDLEN                   ( w_aou_fifo_rdlen                  ),
    .O_AOU_TX_M_AXI_R_MESSAGE               ( w_aou_tx_m_axi_r_message          ),
    .O_AOU_TX_M_AXI_RVALID                  ( w_aou_fifo_rvalid                 ),
    .I_AOU_TX_M_AXI_RREADY                  ( w_aou_fifo_rready                 ),

    .I_AOU_TX_WREQCRED                      ( I_AOU_TX_WREQCRED                 ),
    .I_AOU_TX_RREQCRED                      ( I_AOU_TX_RREQCRED                 ),
    .I_AOU_TX_WDATACRED                     ( I_AOU_TX_WDATACRED                ),
    .I_AOU_TX_RDATACRED                     ( I_AOU_TX_RDATACRED                ),
    .I_AOU_TX_WRESPCRED                     ( I_AOU_TX_WRESPCRED                ),

    .O_AOU_TX_WREQVALID                     ( O_AOU_TX_WREQVALID                ),
    .O_AOU_TX_RREQVALID                     ( O_AOU_TX_RREQVALID                ),
    .O_AOU_TX_WDATAVALID                    ( O_AOU_TX_WDATAVALID               ),
    .O_AOU_TX_WFDATA                        ( O_AOU_TX_WFDATA                   ),
    .O_AOU_TX_RDATAVALID                    ( O_AOU_TX_RDATAVALID               ),
    .O_AOU_TX_RDATA_DLENGTH                 ( O_AOU_TX_RDATA_DLENGTH            ),
    .O_AOU_TX_WRESPVALID                    ( O_AOU_TX_WRESPVALID               ),

    .I_RP_DEST_RP                           ( I_RP_DEST_RP                      ),

    .I_PRIOR_RP_AXI_AXI_QOS_TO_NP           ( I_PRIOR_RP_AXI_AXI_QOS_TO_NP      ),
    .I_PRIOR_RP_AXI_AXI_QOS_TO_HP           ( I_PRIOR_RP_AXI_AXI_QOS_TO_HP      ),
    .I_PRIOR_RP_AXI_RP3_PRIOR               ( I_PRIOR_RP_AXI_RP3_PRIOR          ),
    .I_PRIOR_RP_AXI_RP2_PRIOR               ( I_PRIOR_RP_AXI_RP2_PRIOR          ),
    .I_PRIOR_RP_AXI_RP1_PRIOR               ( I_PRIOR_RP_AXI_RP1_PRIOR          ),
    .I_PRIOR_RP_AXI_RP0_PRIOR               ( I_PRIOR_RP_AXI_RP0_PRIOR          ),
    .I_PRIOR_RP_AXI_ARB_MODE                ( I_PRIOR_RP_AXI_ARB_MODE           ),
    .I_PRIOR_TIMER_TIMER_RESOLUTION         ( I_PRIOR_TIMER_TIMER_RESOLUTION    ),
    .I_PRIOR_TIMER_TIMER_THRESHOLD          ( I_PRIOR_TIMER_TIMER_THRESHOLD     ),

    .I_AOU_WRITEFULL_MSGTYPE_EN             ( I_AOU_WRITEFULL_MSGTYPE_EN        ),
    .O_AOU_TX_B_FIFO_SVALID                 ( w_aou_tx_b_fifo_svalid            )
);

AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (56),
    .FIFO_DEPTH                     (AOU_MISC_FIFO_DEPTH)
)
u_aou_misc_crdtgrant_tx_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (I_AOU_CRDTGRANT_VALID),
    .I_SDATA                        ({I_AOU_CRDTGRANT_WREQCRED0, I_AOU_CRDTGRANT_WREQCRED1,I_AOU_CRDTGRANT_WREQCRED2, I_AOU_CRDTGRANT_WREQCRED3,
                                    I_AOU_CRDTGRANT_RREQCRED0,I_AOU_CRDTGRANT_RREQCRED1,I_AOU_CRDTGRANT_RREQCRED2,I_AOU_CRDTGRANT_RREQCRED3,
                                    I_AOU_CRDTGRANT_WDATACRED0,I_AOU_CRDTGRANT_WDATACRED1,I_AOU_CRDTGRANT_WDATACRED2,I_AOU_CRDTGRANT_WDATACRED3,
                                    I_AOU_CRDTGRANT_RDATACRED0,I_AOU_CRDTGRANT_RDATACRED1,I_AOU_CRDTGRANT_RDATACRED2,I_AOU_CRDTGRANT_RDATACRED3,
                                    I_AOU_CRDTGRANT_WRESPCRED0,I_AOU_CRDTGRANT_WRESPCRED1,I_AOU_CRDTGRANT_WRESPCRED2,I_AOU_CRDTGRANT_WRESPCRED3}),
    .O_SREADY                       (O_AOU_CRDTGRANT_READY),

    .I_MREADY                       (w_misc_crdtgrant_fifo_ready),
    .O_MDATA                        (w_misc_crdtgrant_payload),
    .O_MVALID                       (w_misc_crdtgrant_fifo_valid),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);


AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     (4 + 1),
    .FIFO_DEPTH                     (AOU_MISC_FIFO_DEPTH)
)
u_misc_activate_fifo(
    .I_CLK                          (I_CLK),
    .I_RESETN                       (I_RESETN),

    .I_SVALID                       (I_AOU_ACTIVATION_VALID),
    .I_SDATA                        ({I_AOU_ACTIVATION_OP, I_AOU_ACTIVATION_PROP_REQ}),
    .O_SREADY                       (O_AOU_ACTIVATION_READY),

    .I_MREADY                       (w_misc_activation_ready),
    .O_MDATA                        ({w_misc_activation_op, w_misc_activation_prop_req}),
    .O_MVALID                       (w_misc_activation_valid),

    .O_EMPTY_CNT                    (),
    .O_FULL_CNT                     ()
);

logic               w_aou_msgcredit_valid, w_aou_msgcredit_ready;
logic  [2:0]        w_aou_rs_msgcredit_wreqcred;
logic  [2:0]        w_aou_rs_msgcredit_rreqcred;
logic  [2:0]        w_aou_rs_msgcredit_wdatacred;
logic  [2:0]        w_aou_rs_msgcredit_rdatacred;
logic  [1:0]        w_aou_rs_msgcredit_wrespcred;
logic  [1:0]        w_aou_rs_msgcredit_rp;

AOU_FWD_RS #(
    .DATA_WIDTH      (16           )
) u_aou_rs_msgcredit
(
    .I_CLK           ( I_CLK                        ),
    .I_RESETN        ( I_RESETN                     ),

    .I_SVALID        ( I_AOU_MSGCREDIT_CRED_VALID        ),
    .I_SDATA         ( {I_AOU_MSGCREDIT_RP, I_AOU_MSGCREDIT_WRESPCRED, I_AOU_MSGCREDIT_RDATACRED,
                    I_AOU_MSGCREDIT_WDATACRED, I_AOU_MSGCREDIT_RREQCRED, I_AOU_MSGCREDIT_WREQCRED}),
    .O_SREADY        ( O_AOU_MSGCREDIT_CRED_READY        ),

    .I_MREADY        ( w_aou_msgcredit_ready     ),
    .O_MDATA         ( {w_aou_rs_msgcredit_rp, w_aou_rs_msgcredit_wrespcred, w_aou_rs_msgcredit_rdatacred,
                    w_aou_rs_msgcredit_wdatacred, w_aou_rs_msgcredit_rreqcred, w_aou_rs_msgcredit_wreqcred}),
    .O_MVALID        ( w_aou_msgcredit_valid     )

);

assign w_writereq_message       = w_aou_tx_m_axi_aw_message;
assign w_writedata_message      = w_aou_tx_m_axi_w_message;
assign w_writedata_wo_strb_message  = w_aou_tx_m_axi_w_message[40*WF1024b_G-1:0];
assign w_writeresp_message      = w_aou_tx_m_axi_b_message;
assign w_readreq_message        = w_aou_tx_m_axi_ar_message;
assign w_readdata256b_message   = w_aou_tx_m_axi_r_message[40*R256b_G-1:0];
assign w_readdata512b_message   = w_aou_tx_m_axi_r_message[40*R512b_G-1:0];
assign w_readdata1024b_message  = w_aou_tx_m_axi_r_message;


assign w_misc_activate_message_byteswap      = {MSG_MISC, 3'b010, w_misc_activation_op, w_misc_activation_prop_req, 28'b0};
assign w_misc_crdtgrant_message_byteswap     = {MSG_MISC, 3'b100, w_misc_crdtgrant_payload, 17'b0};

assign w_misc_activate_message = {<<8{w_misc_activate_message_byteswap}};
assign w_misc_crdtgrant_message = {<<8{w_misc_crdtgrant_message_byteswap}};


logic [1:0] w_aw_add, w_ar_add, w_b_add;
logic [5:0] w_w_add, w_r_add;
logic [1:0] w_misc_crdt_add;

always_comb begin
    w_aw_add = w_aou_fifo_aw_hs ? 2'(AW_G) : '0;
    w_w_add  = w_aou_fifo_w_hs  ? w_wdata_granule_size : '0;
    w_b_add  = w_aou_fifo_b_hs  ? 2'(B_G) : '0;
    w_ar_add = w_aou_fifo_ar_hs ? 2'(AR_G) : '0;
    w_r_add  = w_aou_fifo_r_hs  ? w_rdata_granule_size : '0;
    w_misc_crdt_add = w_aou_fifo_misc_crd_hs ? 2'b10 : '0;
end


always_comb begin
    w_aw_message_start_idx  = r_cur_granule_start;
    w_w_message_start_idx   = r_cur_granule_start + w_aw_add;
    w_b_message_start_idx   = r_cur_granule_start + w_aw_add + w_w_add;
    w_ar_message_start_idx  = r_cur_granule_start + w_aw_add + w_w_add
                         + w_b_add;
    w_r_message_start_idx   = r_cur_granule_start + w_aw_add + w_w_add
                         + w_b_add + w_ar_add;
    w_misc_activate_start_idx  = r_cur_granule_start + w_aw_add + w_w_add
                         + w_b_add + w_ar_add + w_r_add;
    w_misc_crdt_start_idx   =  r_cur_granule_start + w_aw_add + w_w_add
                         + w_b_add + w_ar_add + w_r_add
                         + w_aou_fifo_misc_act_hs;
    nxt_granule_start       =  r_cur_granule_start + w_aw_add + w_w_add
                         + w_b_add + w_ar_add + w_r_add
                         + w_aou_fifo_misc_act_hs + w_misc_crdt_add;
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        for (int unsigned n=0; n < RING_DEPTH; n++) begin
            r_granule_buffer[n] <= 40'b0;
            r_msgstart_buffer[n] <= 1'b0;
        end
        r_cur_granule_start <= 'b0;

    end else if(w_aou_fifo_misc_crd_hs | w_aou_fifo_misc_act_hs | w_aou_fifo_r_hs | w_aou_fifo_ar_hs | w_aou_fifo_b_hs | w_aou_fifo_w_hs | w_aou_fifo_aw_hs)begin
       for (int unsigned n=0; n < RING_DEPTH; n++) begin
          r_granule_buffer[n]  <= nxt_granule_buffer[n];
          r_msgstart_buffer[n] <= nxt_msgstart_buffer[n];
       end
       r_cur_granule_start <= nxt_granule_start;

    end
end

always_comb begin
    nxt_granule_buffer = r_granule_buffer;
    nxt_msgstart_buffer = r_msgstart_buffer;

    if (w_aou_fifo_aw_hs) begin
        for (int unsigned n=0; n < AW_G; n++) begin
            nxt_granule_buffer[add_idx(w_aw_message_start_idx, n)] = w_writereq_message[n*40 +: 40];
            nxt_msgstart_buffer[add_idx(w_aw_message_start_idx, n)] = (n == 0);
        end
    end

    if (w_aou_fifo_w_hs) begin
        for (int unsigned i = 0 ; i < RP_CNT ; i ++) begin
            if (w_aou_fifo_w_rp == i) begin
                if (I_AOU_WRITEFULL_MSGTYPE_EN && w_aou_fifo_wstrb_full) begin
                    for (int unsigned n=0; n < RP_NO_STRB_W_G_SIZE[i]; n++) begin
                        nxt_granule_buffer[add_idx(w_w_message_start_idx, n)] = w_writedata_wo_strb_message[n*40 +: 40];
                        nxt_msgstart_buffer[add_idx(w_w_message_start_idx, n)] = (n == 0);
                    end
                end else begin
                    for (int unsigned n=0; n < RP_W_G_SIZE[i]; n++) begin
                        nxt_granule_buffer[add_idx(w_w_message_start_idx, n)] = w_writedata_message[n*40 +: 40];
                        nxt_msgstart_buffer[add_idx(w_w_message_start_idx, n)] = (n == 0);
                    end
                end
            end
        end
    end

    if (w_aou_fifo_b_hs) begin
        for (int unsigned n=0; n < B_G; n++) begin
            nxt_granule_buffer[add_idx(w_b_message_start_idx, n)] = w_writeresp_message[n*40 +: 40];
            nxt_msgstart_buffer[add_idx(w_b_message_start_idx, n)] = (n == 0);
        end
    end

    if (w_aou_fifo_ar_hs) begin
        for (int unsigned n=0; n < AR_G; n++) begin
            nxt_granule_buffer[add_idx(w_ar_message_start_idx, n)] = w_readreq_message[n*40 +: 40];
            nxt_msgstart_buffer[add_idx(w_ar_message_start_idx, n)] = (n == 0);
        end
    end

    if (w_aou_fifo_r_hs) begin
        if (w_rdata_256b) begin
            for (int unsigned n=0; n < R256b_G; n++) begin
                nxt_granule_buffer[add_idx(w_r_message_start_idx, n)] = w_readdata256b_message[n*40 +: 40];
                nxt_msgstart_buffer[add_idx(w_r_message_start_idx, n)] = (n == 0);
            end
        end else if (w_rdata_512b) begin
            for (int unsigned n=0; n < R512b_G; n++) begin
                nxt_granule_buffer[add_idx(w_r_message_start_idx, n)] = w_readdata512b_message[n*40 +: 40];
                nxt_msgstart_buffer[add_idx(w_r_message_start_idx, n)] = (n == 0);
            end
        end else begin
            for (int unsigned n=0; n < R1024b_G; n++) begin
                nxt_granule_buffer[add_idx(w_r_message_start_idx, n)] = w_readdata1024b_message[n*40 +: 40];
                nxt_msgstart_buffer[add_idx(w_r_message_start_idx, n)] = (n == 0);
            end
        end
    end

    if (w_aou_fifo_misc_crd_hs) begin
        for (int unsigned n=0; n < 2; n++) begin
            nxt_granule_buffer[add_idx(w_misc_crdt_start_idx, n)] = w_misc_crdtgrant_message[n*40 +: 40];
            nxt_msgstart_buffer[add_idx(w_misc_crdt_start_idx, n)] = (n == 0);
        end
    end

    if (w_aou_fifo_misc_act_hs) begin
        for (int unsigned n=0; n < 1; n++) begin
            nxt_granule_buffer[add_idx(w_misc_activate_start_idx, n)] = w_misc_activate_message[n*40 +: 40];
            nxt_msgstart_buffer[add_idx(w_misc_activate_start_idx, n)] = (n == 0);
        end
    end

end


always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_cur_flit_for_fifo_start  <= 'b0;
    end else begin
        r_cur_flit_for_fifo_start <= nxt_flit_for_fifo_start;
    end
end

always_comb begin
    nxt_flit_for_fifo_start = r_cur_flit_for_fifo_start;
    if (w_flit_fifo_valid && w_flit_fifo_ready) begin
        if (((r_cur_granule_start - r_cur_flit_for_fifo_start) & 8'b1111_1111 ) > (FLIT_PACK_GRANULE_CNT -1)) begin
            nxt_flit_for_fifo_start = r_cur_flit_for_fifo_start + FLIT_PACK_GRANULE_CNT;
        end else begin
            nxt_flit_for_fifo_start = r_cur_granule_start;
        end
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_flit_packing_state <= 2'b00;
    end else if (w_flit_fifo_valid && w_flit_fifo_ready) begin
        r_flit_packing_state <= r_flit_packing_state + 1;
    end
end

assign nxt_flit_packing_state = (w_flit_fifo_valid && w_flit_fifo_ready) ? (r_flit_packing_state + 1) : r_flit_packing_state;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_tx_activation_valid <= 0;

    end else if (w_aou_fifo_misc_act_hs) begin
        //if activation start = always valid
        if (w_misc_activation_op == 3'b001 || w_misc_activation_op == 3'b000) r_tx_activation_valid <= 1'b1;
        //if deactivation start = valid until pending end.
    end else if(I_STATUS_DISABLED && ((r_cur_granule_start == r_cur_flit_for_fifo_start) && (r_flit_packing_state == FLIT_LAST_PACK_STATE)) && w_flit_fifo_ready) begin
        r_tx_activation_valid <= 1'b0;
    end
end

//w_flit_fifo_valid is always 1 when TX activation is valid
logic [7:0] w_flit_fifo_valid_timeout;
logic w_flit_fifo_valid_out_valid;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        w_flit_fifo_valid_timeout <= 8'b0;
    end else if (!w_flit_fifo_valid) begin
        w_flit_fifo_valid_timeout <=  w_flit_fifo_valid_timeout + 1;
    end else if (w_flit_fifo_valid && w_flit_fifo_ready) begin
        w_flit_fifo_valid_timeout <= 8'b0;
    end
end

assign w_flit_fifo_valid_out_valid = (w_flit_fifo_valid_timeout == I_AOU_TX_LP_MODE_THRESHOLD);

// ---------------------------------------------------------------------------
// LP-mode "engaged" gate
// ---------------------------------------------------------------------------
// LP-mode behavior is deliberately delayed until the activation handshake has
// fully completed *on the wire*. The activation FSM transitions to ENABLED as
// soon as it has decided to send ACTIVATE_ACK (push-into-activation-FIFO),
// which is earlier than the actual on-FDI transmission of that ACK. Engaging
// LP-mode at that moment can starve the partner because:
//   - LP-mode flit-trigger gates flit launch on real work, and
//   - LP-mode w_misc_activation_ready only pops at state==0 && ring empty.
// If the ACK is still sitting in the activation FIFO (or in flight in the
// current flit) when LP-mode kicks in, it can get stranded.
//
// We therefore engage LP-mode only when ALL of the following hold:
//   1. I_STATUS_ENABLED      : FSM has fully completed its 4-flag handshake
//                              (TX REQ/ACK pushed, RX REQ/ACK received).
//   2. !w_misc_activation_valid : activation FIFO is drained, no more REQ/ACK
//                                 waiting to be popped onto the ring.
//   3. !r_act_in_flight      : no activation message is currently riding in
//                              the flit being assembled (i.e., a previously
//                              popped activate has fully exited the flit_fifo).
//
// Until all three are met, we fall back to the legacy non-LP behavior so the
// heartbeat keeps emitting flits and the activation messages flow naturally.
// Note: protocol allows only 1 activate message per flit; this is preserved
// by w_misc_activation_ready in both engaged and non-engaged branches.
logic r_act_in_flight;
wire  w_flit_pack_completed = w_flit_fifo_valid && w_flit_fifo_ready
                              && (r_flit_packing_state == FLIT_LAST_PACK_STATE);

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_act_in_flight <= 1'b0;
    end else if (w_aou_fifo_misc_act_hs) begin
        // Activation pop happens at chunk 0 (state==0 && ring empty); the
        // activate granule is now part of the flit being assembled.
        r_act_in_flight <= 1'b1;
    end else if (w_flit_pack_completed) begin
        // Flit's last chunk fired; the activate is now on the wire.
        r_act_in_flight <= 1'b0;
    end
end

logic r_msgcredit_port_valid;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_msgcredit_port_valid <= 1'b0;
    end else if (I_AOU_MSGCREDIT_CRED_VALID) begin
        r_msgcredit_port_valid <= |{I_AOU_MSGCREDIT_WREQCRED, I_AOU_MSGCREDIT_RREQCRED, I_AOU_MSGCREDIT_WDATACRED
                                    , I_AOU_MSGCREDIT_RDATACRED, I_AOU_MSGCREDIT_WRESPCRED};
    end
end

assign w_lp_engaged = I_AOU_TX_LP_MODE && I_STATUS_ENABLED
                    && (!w_misc_activation_valid) && (!r_act_in_flight);

// ---------------------------------------------------------------------------
// Flit launch trigger
// ---------------------------------------------------------------------------
// LP engaged:
//   - threshold != 0: existing periodic heartbeat preserved (every threshold+1
//                     cycles while activation is valid) so legacy CSR semantics
//                     are unchanged for non-zero thresholds.
//   - threshold == 0: heartbeat is inert; flits may launch on the current MsgCredit payload or
//                     a previously latched MsgCredit presence via r_msgcredit_port_valid.
//                     This preserves the legacy latched-credit behavior while LP engagement/pop gating is fixed.
// LP not engaged (handshake in progress / non-LP):
//   Legacy behavior: fire whenever ring is non-empty, mid-flit, or activation
//   has started (r_tx_activation_valid). This guarantees the activation FIFO
//   gets drained quickly during bring-up.
//
// Note on the MsgCredit gate (threshold == 0):
//   AOU_RX_CRD_CTRL drives I_AOU_MSGCREDIT_CRED_VALID = ~I_STATUS_DISABLED, i.e.
//   it stays asserted as long as the link is up regardless of the actual credit
//   payload. Triggering on that bare valid would cause LP-engaged DUTs to emit
//   a continuous stream of empty flits with all-zero MsgCredit fields. Inspect
//   the live credit payload directly so flits only launch when there is at
//   least one real credit to return. (FWD_RS r_mdata still carries the actual
//   chunk-2 payload at handshake time, so credit accounting is unchanged.)

logic w_flit_header_credit_valid;

assign w_flit_header_credit_valid = w_aou_msgcredit_valid && |{
        w_aou_rs_msgcredit_wrespcred, w_aou_rs_msgcredit_rdatacred,
        w_aou_rs_msgcredit_wdatacred, w_aou_rs_msgcredit_rreqcred,
        w_aou_rs_msgcredit_wreqcred
    };

logic w_lp_mode_thres_val;

assign w_lp_mode_thres_val = (I_AOU_TX_LP_MODE_THRESHOLD == 'b0) ?  {w_flit_header_credit_valid || r_msgcredit_port_valid} : w_flit_fifo_valid_out_valid;


assign w_flit_fifo_valid = w_lp_engaged
    ? ((r_cur_granule_start != r_cur_flit_for_fifo_start) ||
         (r_flit_packing_state != '0) ||
         (r_tx_activation_valid && w_lp_mode_thres_val))
      : ((r_cur_granule_start != r_cur_flit_for_fifo_start) ||
         (r_flit_packing_state != '0) ||
         r_tx_activation_valid);


assign O_AOU_TX_PENDING = w_aou_fifo_awvalid || w_aou_fifo_wvalid || w_aou_fifo_bvalid
                        || w_aou_fifo_arvalid || w_aou_fifo_rvalid || (r_cur_granule_start != r_cur_flit_for_fifo_start) || w_aou_tx_axi_hs;

assign O_AOU_TX_AXI_TR_PENDING = w_aou_fifo_awvalid || w_aou_fifo_wvalid || w_aou_fifo_bvalid || w_aou_fifo_arvalid || w_aou_fifo_rvalid || w_aou_tx_axi_hs
                                || |I_AOU_TX_AXI_AWVALID || |I_AOU_TX_AXI_WVALID || |I_AOU_TX_AXI_ARVALID || |w_aou_tx_b_fifo_svalid || |I_AOU_TX_AXI_RVALID;


// Two parallel packing pipelines. Exactly one elaborates per config:
//   FDI_PACK_WD == 1024 -> g_pack_2step (half-flit per cycle, 24 granules)
//   otherwise           -> g_pack_4step (quarter-flit per cycle, 12 granules)
generate if (FDI_PACK_WD != 1024) begin : g_pack_4step
    logic [64*8-1:0]    w_flit_fifo_data;
    logic [64*8-1:0]    w_flit_chunk;
    logic [16-1:0]      w_a_half_header;
    logic [16-1:0]      w_b_half_header;

    // Pack sources: the look-ahead (next) state and ring when TX_NXT_PACKING_EN,
    // the current registered state and ring otherwise.
    flit_packing_state_t         w_pack_state;
    logic [RING_CNT-1:0]         w_pack_granule_start;
    logic [RING_CNT-1:0]         w_pack_fifo_start;
    logic [40-1:0]               w_pack_granule  [RING_DEPTH-1:0];
    logic                        w_pack_msgstart [RING_DEPTH-1:0];

    if (TX_NXT_PACKING_EN != 0) begin : g_src_nxt
        assign w_pack_state         = nxt_flit_packing_state;
        assign w_pack_granule_start = nxt_granule_start;
        assign w_pack_fifo_start    = nxt_flit_for_fifo_start;
        assign w_pack_granule       = nxt_granule_buffer;
        assign w_pack_msgstart      = nxt_msgstart_buffer;
    end else begin : g_src_cur
        assign w_pack_state         = r_flit_packing_state;
        assign w_pack_granule_start = r_cur_granule_start;
        assign w_pack_fifo_start    = r_cur_flit_for_fifo_start;
        assign w_pack_granule       = r_granule_buffer;
        assign w_pack_msgstart      = r_msgstart_buffer;
    end

    // Output stage: registered chunk when TX_NXT_PACKING_EN, combinational otherwise.
    if (TX_NXT_PACKING_EN != 0) begin : g_out_reg
        logic [64*8-1:0]    r_flit_fifo_data;
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if (!I_RESETN) begin
                r_flit_fifo_data <= 'd0;
            end else if (w_misc_activation_valid || w_flit_fifo_valid || O_AOU_TX_AXI_TR_PENDING) begin
                r_flit_fifo_data <= w_flit_fifo_data;
            end
        end
        assign w_flit_chunk = r_flit_fifo_data;
    end else begin : g_out_comb
        assign w_flit_chunk = w_flit_fifo_data;
    end

    always_comb begin
        //flit chunk
    
        case (w_pack_state)
            2'b00: begin
                w_a_half_header[2*8-1:0] = 16'b0000_0000_1100_0000;  //flit header 
            end
            2'b01: begin
                w_a_half_header[0 +: 4] = 4'b0000; //RSVD
                for (int unsigned n=0; n<12; n++) begin
                    if (n < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_a_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n) & (8'b0111_1111)];
                    end else begin
                        w_a_half_header[4 + n +: 1] = 1'b0;
                    end
                end
            end
            2'b10: begin
                w_a_half_header[0 +: 16] = w_aou_msgcredit_valid ? {w_aou_rs_msgcredit_rp, w_aou_rs_msgcredit_wrespcred, w_aou_rs_msgcredit_rdatacred,
                                            w_aou_rs_msgcredit_wdatacred, w_aou_rs_msgcredit_rreqcred, w_aou_rs_msgcredit_wreqcred} : 16'b0;
            end
        //4 flit chunk
            default: begin
                w_a_half_header[0+: 4] = 4'b0000; //RSVD
                for (int unsigned n=0; n<12; n++) begin
                    if (n < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_a_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n) & (8'b0111_1111)];
                    end else begin
                        w_a_half_header[4 + n +: 1] = 1'b0;
                    end
                end
            end
        endcase
    
        case (w_pack_state)
            2'b00: begin
                for (int unsigned n=0; n<12; n++) begin
                    if (n < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_b_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n) & (8'b0111_1111)];
                    end else begin
                        w_b_half_header[4 + n +: 1] = 1'b0;
                    end
                end
                w_b_half_header[0 +: 4] = 4'b0000; //RSVD
            end
            2'b01: begin
                w_b_half_header[0 +: 16] = 16'b0;
            end
            2'b10: begin
                for (int unsigned n=0; n<12; n++) begin
                    if (n < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_b_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n) & (8'b0111_1111)];
                    end else begin
                        w_b_half_header[4 + n +: 1] = 1'b0;
                    end
                        
                end
                w_b_half_header[0 +: 4] = 4'b0000; //RSVD
            end
        //4 flit chunk
            default: begin
                w_b_half_header[0 +: 16] = 16'b0;
            end
        endcase
        
        w_flit_fifo_data[0 +: 16] = w_a_half_header;
        w_flit_fifo_data[64 * 8 -1 -: 16] = w_b_half_header;
    
        for (int unsigned n=0; n<12; n++) begin
            if (n < ((w_pack_granule_start - w_pack_fifo_start ) & 8'b1111_1111 )) begin
                w_flit_fifo_data[16 + 40*n +: 40] = w_pack_granule[(w_pack_fifo_start + n) & (8'b0111_1111)];
            end else begin
                w_flit_fifo_data[16 + 40*n +: 40] = 40'b0;
            end
        end
    
    end

    assign w_aou_msgcredit_ready = w_flit_fifo_valid && w_flit_fifo_ready && (r_flit_packing_state == 2'b10);


    `ifdef TWO_PHY
        // Two-PHY + 4-step packing (FDI_IF_WD0 = 256, FDI_IF_WD1 = 512):
        //   out-mux splits flit across the two PHY streams, one REV_RS per PHY.
        logic                                w_fdi_pl_0_trdy;
        logic [FDI_IF_WD0-1:0]               w_fdi_lp_0_data;
        logic                                w_fdi_lp_0_valid;
        logic [FDI_IF_WD1-1:0]               w_flit_fifo_in_data;

        logic                                w_fdi_pl_1_trdy;
        logic [FDI_IF_WD1-1:0]               w_fdi_lp_1_data;
        logic                                w_fdi_lp_1_valid;

        assign w_flit_fifo_in_data = w_flit_chunk;

        AOU_TX_CORE_OUT_MUX #(
            .FDI_IF_WD           ( FDI_IF_WD1           )
        ) u_aou_tx_core_out_mux
        (
            .I_CLK               ( I_CLK                ),
            .I_RESETN            ( I_RESETN             ),

            .I_PHY_TYPE          ( I_PHY_TYPE           ),

            .O_FDI_PL_TRDY       ( w_flit_fifo_ready    ),
            .I_FDI_LP_DATA       ( w_flit_fifo_in_data  ),
            .I_FDI_LP_VALID      ( w_flit_fifo_valid    ),

            .I_FDI_PL_0_TRDY     ( w_fdi_pl_0_trdy      ),
            .O_FDI_LP_0_DATA     ( w_fdi_lp_0_data      ),
            .O_FDI_LP_0_VALID    ( w_fdi_lp_0_valid     ),

            .I_FDI_PL_1_TRDY     ( w_fdi_pl_1_trdy      ),
            .O_FDI_LP_1_DATA     ( w_fdi_lp_1_data      ),
            .O_FDI_LP_1_VALID    ( w_fdi_lp_1_valid     )
        );

        AOU_REV_RS #(
            .DATA_WIDTH         (FDI_IF_WD0)
        ) u_aou_tx_core_phy0_rs
        (
            .I_CLK              ( I_CLK              ),
            .I_RESETN           ( I_RESETN           ),

            .I_SVALID           ( w_fdi_lp_0_valid   ),
            .O_SREADY           ( w_fdi_pl_0_trdy    ),
            .I_SDATA            ( w_fdi_lp_0_data    ),

            .O_MVALID           ( O_FDI_LP_VALID_0   ),
            .I_MREADY           ( I_FDI_PL_TRDY_0    ),
            .O_MDATA            ( O_FDI_LP_DATA_0    )
        );

        AOU_REV_RS #(
            .DATA_WIDTH         (FDI_IF_WD1)
        ) u_aou_tx_core_phy1_rs
        (
            .I_CLK              ( I_CLK              ),
            .I_RESETN           ( I_RESETN           ),

            .I_SVALID           ( w_fdi_lp_1_valid   ),
            .O_SREADY           ( w_fdi_pl_1_trdy    ),
            .I_SDATA            ( w_fdi_lp_1_data    ),

            .O_MVALID           ( O_FDI_LP_VALID_1   ),
            .I_MREADY           ( I_FDI_PL_TRDY_1    ),
            .O_MDATA            ( O_FDI_LP_DATA_1    )
        );
    `else
        // Single-PHY + 4-step packing. Two sub-cases:
        //   FDI_IF_WD0 == 256 (FDI_32B): out-mux with PHY1 tied, one REV_RS
        //   FDI_IF_WD0 == 512 (FDI_64B): direct REV_RS, no out-mux needed
        if (FDI_IF_WD0 == 256) begin : g_sp_32b
            logic                                w_fdi_pl_0_trdy;
            logic [FDI_IF_WD0-1:0]               w_fdi_lp_0_data;
            logic                                w_fdi_lp_0_valid;
            logic [FDI_IF_WD1-1:0]               w_flit_fifo_in_data;

            assign w_flit_fifo_in_data = w_flit_chunk;

            AOU_TX_CORE_OUT_MUX #(
                .FDI_IF_WD           ( FDI_IF_WD1           )
            ) u_aou_tx_core_out_mux
            (
                .I_CLK               ( I_CLK                ),
                .I_RESETN            ( I_RESETN             ),

                .I_PHY_TYPE          ( 1'b0                 ),

                .O_FDI_PL_TRDY       ( w_flit_fifo_ready    ),
                .I_FDI_LP_DATA       ( w_flit_fifo_in_data  ),
                .I_FDI_LP_VALID      ( w_flit_fifo_valid    ),

                .I_FDI_PL_0_TRDY     ( w_fdi_pl_0_trdy      ),
                .O_FDI_LP_0_DATA     ( w_fdi_lp_0_data      ),
                .O_FDI_LP_0_VALID    ( w_fdi_lp_0_valid     ),

                .I_FDI_PL_1_TRDY     ( 1'b0                 ),
                .O_FDI_LP_1_DATA     (                      ),
                .O_FDI_LP_1_VALID    (                      )
            );

            AOU_REV_RS #(
                .DATA_WIDTH         (FDI_IF_WD0)
            ) u_aou_tx_core_phy0_rs
            (
                .I_CLK              ( I_CLK                 ),
                .I_RESETN           ( I_RESETN              ),

                .I_SVALID           ( w_fdi_lp_0_valid      ),
                .O_SREADY           ( w_fdi_pl_0_trdy       ),
                .I_SDATA            ( w_fdi_lp_0_data       ),

                .O_MVALID           ( O_FDI_LP_VALID_0      ),
                .I_MREADY           ( I_FDI_PL_TRDY_0       ),
                .O_MDATA            ( O_FDI_LP_DATA_0       )
            );
        end else begin : g_sp_64b
            logic [FDI_IF_WD0-1:0]               w_flit_fifo_in_data;

            assign w_flit_fifo_in_data = w_flit_chunk;

            AOU_REV_RS #(
                .DATA_WIDTH         (FDI_IF_WD0)
            ) u_aou_tx_core_phy0_rs
            (
                .I_CLK              ( I_CLK                 ),
                .I_RESETN           ( I_RESETN              ),

                .I_SVALID           ( w_flit_fifo_valid     ),
                .O_SREADY           ( w_flit_fifo_ready     ),
                .I_SDATA            ( w_flit_fifo_in_data   ),

                .O_MVALID           ( O_FDI_LP_VALID_0      ),
                .I_MREADY           ( I_FDI_PL_TRDY_0       ),
                .O_MDATA            ( O_FDI_LP_DATA_0       )
            );
        end
    `endif


end else begin : g_pack_2step
    logic [64*8*2-1:0]    w_flit_fifo_data;
    logic [64*8*2-1:0]    w_flit_chunk;
    logic [16-1:0]      w_first_a_half_header, w_second_a_half_header;
    logic [16-1:0]      w_first_b_half_header, w_second_b_half_header;

    // Pack sources: the look-ahead (next) state and ring when TX_NXT_PACKING_EN,
    // the current registered state and ring otherwise.
    flit_packing_state_t         w_pack_state;
    logic [RING_CNT-1:0]         w_pack_granule_start;
    logic [RING_CNT-1:0]         w_pack_fifo_start;
    logic [40-1:0]               w_pack_granule  [RING_DEPTH-1:0];
    logic                        w_pack_msgstart [RING_DEPTH-1:0];

    if (TX_NXT_PACKING_EN != 0) begin : g_src_nxt
        assign w_pack_state         = nxt_flit_packing_state;
        assign w_pack_granule_start = nxt_granule_start;
        assign w_pack_fifo_start    = nxt_flit_for_fifo_start;
        assign w_pack_granule       = nxt_granule_buffer;
        assign w_pack_msgstart      = nxt_msgstart_buffer;
    end else begin : g_src_cur
        assign w_pack_state         = r_flit_packing_state;
        assign w_pack_granule_start = r_cur_granule_start;
        assign w_pack_fifo_start    = r_cur_flit_for_fifo_start;
        assign w_pack_granule       = r_granule_buffer;
        assign w_pack_msgstart      = r_msgstart_buffer;
    end

    // Output stage: registered chunk when TX_NXT_PACKING_EN, combinational otherwise.
    if (TX_NXT_PACKING_EN != 0) begin : g_out_reg
        logic [64*8*2-1:0]    r_flit_fifo_data;
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if (!I_RESETN) begin
                r_flit_fifo_data <= 'd0;
            end else if (w_misc_activation_valid || w_flit_fifo_valid || O_AOU_TX_AXI_TR_PENDING) begin
                r_flit_fifo_data <= w_flit_fifo_data;
            end
        end
        assign w_flit_chunk = r_flit_fifo_data;
    end else begin : g_out_comb
        assign w_flit_chunk = w_flit_fifo_data;
    end

    always_comb begin
        //flit chunk

        case (w_pack_state)
            1'b0 : begin
                w_first_a_half_header[2*8-1:0] = 16'b0000_0000_1100_0000;  //flit header

                w_second_a_half_header[0 +: 4] = 4'b0000; //RSVD
                for (int unsigned n=0; n<12; n++) begin
                    if (n + 12< ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_second_a_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n + 12) & (8'b0111_1111)];
                    end else begin
                        w_second_a_half_header[4 + n +: 1] = 1'b0;
                    end
                end
            end
            1'b1: begin
                w_first_a_half_header[0 +: 16] = w_aou_msgcredit_valid ? {w_aou_rs_msgcredit_rp, w_aou_rs_msgcredit_wrespcred, w_aou_rs_msgcredit_rdatacred,
                                            w_aou_rs_msgcredit_wdatacred, w_aou_rs_msgcredit_rreqcred, w_aou_rs_msgcredit_wreqcred} : 16'b0;

                w_second_a_half_header[0+: 4] = 4'b0000; //RSVD
                for (int unsigned n=0; n<12; n++) begin
                    if (n + 12 < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_second_a_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n + 12) & (8'b0111_1111)];
                    end else begin
                        w_second_a_half_header[4 + n +: 1] = 1'b0;
                    end
                end
            end
        endcase

        case (w_pack_state)
            'b0: begin
                for (int unsigned n=0; n<12; n++) begin
                    if (n < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_first_b_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n) & (8'b0111_1111)];
                    end else begin
                        w_first_b_half_header[4 + n +: 1] = 1'b0;
                    end
                end
                w_first_b_half_header[0 +: 4] = 4'b0000; //RSVD

                w_second_b_half_header[0 +: 16] = 16'b0;
            end
            1'b1: begin
                for (int unsigned n=0; n<12; n++) begin
                    if (n < ((w_pack_granule_start - w_pack_fifo_start) & 8'b1111_1111 )) begin
                        w_first_b_half_header[4 + n +: 1] = w_pack_msgstart[(w_pack_fifo_start + n ) & (8'b0111_1111)];
                    end else begin
                        w_first_b_half_header[4 + n +: 1] = 1'b0;
                    end

                end
                w_first_b_half_header[0 +: 4] = 4'b0000; //RSVD

                w_second_b_half_header[0 +: 16] = 16'b0;
            end
        endcase

        w_flit_fifo_data[0 +: 16] = w_first_a_half_header;
        w_flit_fifo_data[64 * 8 -1 -: 16] = w_first_b_half_header;

        w_flit_fifo_data[512 +: 16] = w_second_a_half_header;
        w_flit_fifo_data[512 + 64 * 8 -1 -: 16] = w_second_b_half_header;

        for (int unsigned n=0; n<12; n++) begin
            if (n < ((w_pack_granule_start - w_pack_fifo_start ) & 8'b1111_1111 )) begin
                w_flit_fifo_data[16 + 40*n +: 40] = w_pack_granule[(w_pack_fifo_start + n) & (8'b0111_1111)];
            end else begin
                w_flit_fifo_data[16 + 40*n +: 40] = 40'b0;
            end
        end

        for (int unsigned n=0; n<12; n++) begin
            if (n + 12 < ((w_pack_granule_start - w_pack_fifo_start ) & 8'b1111_1111 )) begin
                w_flit_fifo_data[512 + 16 + 40*n +: 40] = w_pack_granule[(w_pack_fifo_start + n + 12) & (8'b0111_1111)];
            end else begin
                w_flit_fifo_data[512 + 16 + 40*n +: 40] = 40'b0;
            end
        end

    end
    
    assign w_aou_msgcredit_ready = w_flit_fifo_valid && w_flit_fifo_ready && (r_flit_packing_state == 1'b1);

    logic                                w_fdi_pl_0_trdy;
    logic [FDI_IF_WD0-1:0]               w_fdi_lp_0_data;
    logic                                w_fdi_lp_0_valid;
    logic [FDI_IF_WD1-1:0]               w_flit_fifo_in_data;

    assign w_flit_fifo_in_data = w_flit_chunk;

    `ifdef TWO_PHY

        logic                                w_fdi_pl_1_trdy;
        logic [FDI_IF_WD1-1:0]               w_fdi_lp_1_data;
        logic                                w_fdi_lp_1_valid;

        AOU_TX_CORE_OUT_MUX #(
            .FDI_IF_WD           ( FDI_IF_WD1           )
        ) u_aou_tx_core_out_mux
        (
            .I_CLK               ( I_CLK                ),
            .I_RESETN            ( I_RESETN             ),

            .I_PHY_TYPE          ( I_PHY_TYPE           ),

            .O_FDI_PL_TRDY       ( w_flit_fifo_ready    ),
            .I_FDI_LP_DATA       ( w_flit_fifo_in_data  ),
            .I_FDI_LP_VALID      ( w_flit_fifo_valid    ),

            .I_FDI_PL_0_TRDY     ( w_fdi_pl_0_trdy      ),
            .O_FDI_LP_0_DATA     ( w_fdi_lp_0_data      ),
            .O_FDI_LP_0_VALID    ( w_fdi_lp_0_valid     ),

            .I_FDI_PL_1_TRDY     ( w_fdi_pl_1_trdy      ),
            .O_FDI_LP_1_DATA     ( w_fdi_lp_1_data      ),
            .O_FDI_LP_1_VALID    ( w_fdi_lp_1_valid     )
        );

        AOU_REV_RS #(
            .DATA_WIDTH         (FDI_IF_WD0)
        ) u_aou_tx_core_phy0_rs
        (
            .I_CLK              ( I_CLK              ),
            .I_RESETN           ( I_RESETN           ),

            .I_SVALID           ( w_fdi_lp_0_valid   ),
            .O_SREADY           ( w_fdi_pl_0_trdy    ),
            .I_SDATA            ( w_fdi_lp_0_data    ),

            .O_MVALID           ( O_FDI_LP_VALID_0   ),
            .I_MREADY           ( I_FDI_PL_TRDY_0    ),
            .O_MDATA            ( O_FDI_LP_DATA_0    )
        );

        AOU_REV_RS #(
            .DATA_WIDTH         (FDI_IF_WD1)
        ) u_aou_tx_core_phy1_rs
        (
            .I_CLK              ( I_CLK              ),
            .I_RESETN           ( I_RESETN           ),

            .I_SVALID           ( w_fdi_lp_1_valid   ),
            .O_SREADY           ( w_fdi_pl_1_trdy    ),
            .I_SDATA            ( w_fdi_lp_1_data    ),

            .O_MVALID           ( O_FDI_LP_VALID_1   ),
            .I_MREADY           ( I_FDI_PL_TRDY_1    ),
            .O_MDATA            ( O_FDI_LP_DATA_1    )
        );
    `else
        // Single-PHY + 2-step packing (FDI_IF_WD0 = 1024): direct REV_RS.
        AOU_REV_RS #(
            .DATA_WIDTH         (FDI_IF_WD0)
        ) u_aou_tx_core_phy0_rs
        (
            .I_CLK              ( I_CLK                 ),
            .I_RESETN           ( I_RESETN              ),

            .I_SVALID           ( w_flit_fifo_valid     ),
            .O_SREADY           ( w_flit_fifo_ready     ),
            .I_SDATA            ( w_flit_fifo_in_data   ),

            .O_MVALID           ( O_FDI_LP_VALID_0      ),
            .I_MREADY           ( I_FDI_PL_TRDY_0       ),
            .O_MDATA            ( O_FDI_LP_DATA_0       )
        );
    `endif

end endgenerate

endmodule

