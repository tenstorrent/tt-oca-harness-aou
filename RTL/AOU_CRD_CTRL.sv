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
//  Module     : AOU_CRD_CTRL
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps


module  AOU_CRD_CTRL
import packet_def_pkg::*;
#(
    parameter  RP_COUNT                  = 4,

    parameter  RP0_RX_AW_MAX_CREDIT      = 256, 
    parameter  RP0_RX_AR_MAX_CREDIT      = 256, 
    parameter  RP0_RX_W_MAX_CREDIT       = 256, 
    parameter  RP0_RX_R_MAX_CREDIT       = 256, 
    parameter  RP0_RX_B_MAX_CREDIT       = 256, 
    parameter  RP1_RX_AW_MAX_CREDIT      = 256, 
    parameter  RP1_RX_AR_MAX_CREDIT      = 256, 
    parameter  RP1_RX_W_MAX_CREDIT       = 256, 
    parameter  RP1_RX_R_MAX_CREDIT       = 256, 
    parameter  RP1_RX_B_MAX_CREDIT       = 256, 
    parameter  RP2_RX_AW_MAX_CREDIT      = 256, 
    parameter  RP2_RX_AR_MAX_CREDIT      = 256, 
    parameter  RP2_RX_W_MAX_CREDIT       = 256, 
    parameter  RP2_RX_R_MAX_CREDIT       = 256, 
    parameter  RP2_RX_B_MAX_CREDIT       = 256, 
    parameter  RP3_RX_AW_MAX_CREDIT      = 256, 
    parameter  RP3_RX_AR_MAX_CREDIT      = 256, 
    parameter  RP3_RX_W_MAX_CREDIT       = 256, 
    parameter  RP3_RX_R_MAX_CREDIT       = 256, 
    parameter  RP3_RX_B_MAX_CREDIT       = 256, 

    parameter  RP0_TX_AW_MAX_CREDIT      = 256, 
    parameter  RP0_TX_AR_MAX_CREDIT      = 256, 
    parameter  RP0_TX_W_MAX_CREDIT       = 256, 
    parameter  RP0_TX_R_MAX_CREDIT       = 256, 
    parameter  RP0_TX_B_MAX_CREDIT       = 256, 
    parameter  RP1_TX_AW_MAX_CREDIT      = 256, 
    parameter  RP1_TX_AR_MAX_CREDIT      = 256, 
    parameter  RP1_TX_W_MAX_CREDIT       = 256, 
    parameter  RP1_TX_R_MAX_CREDIT       = 256, 
    parameter  RP1_TX_B_MAX_CREDIT       = 256, 
    parameter  RP2_TX_AW_MAX_CREDIT      = 256, 
    parameter  RP2_TX_AR_MAX_CREDIT      = 256, 
    parameter  RP2_TX_W_MAX_CREDIT       = 256, 
    parameter  RP2_TX_R_MAX_CREDIT       = 256, 
    parameter  RP2_TX_B_MAX_CREDIT       = 256, 
    parameter  RP3_TX_AW_MAX_CREDIT      = 256, 
    parameter  RP3_TX_AR_MAX_CREDIT      = 256, 
    parameter  RP3_TX_W_MAX_CREDIT       = 256, 
    parameter  RP3_TX_R_MAX_CREDIT       = 256, 
    parameter  RP3_TX_B_MAX_CREDIT       = 256,

    parameter  RP0_AXI_DATA_WD           = 1024,
    parameter  RP1_AXI_DATA_WD           = 256,
    parameter  RP2_AXI_DATA_WD           = 1024,
    parameter  RP3_AXI_DATA_WD           = 256,

    parameter  DEC_MULTI                 = 2,

    localparam  MAX_MISC_CNT             = 2,

    localparam  CNT_RP0_TX_AW_MAX_CREDIT = $clog2(RP0_TX_AW_MAX_CREDIT +1), 
    localparam  CNT_RP0_TX_AR_MAX_CREDIT = $clog2(RP0_TX_AR_MAX_CREDIT +1), 
    localparam  CNT_RP0_TX_W_MAX_CREDIT  = $clog2(RP0_TX_W_MAX_CREDIT  +1), 
    localparam  CNT_RP0_TX_R_MAX_CREDIT  = $clog2(RP0_TX_R_MAX_CREDIT  +1),     
    localparam  CNT_RP0_TX_B_MAX_CREDIT  = $clog2(RP0_TX_B_MAX_CREDIT  +1),      

    localparam  CNT_RP1_TX_AW_MAX_CREDIT = $clog2(RP1_TX_AW_MAX_CREDIT +1), 
    localparam  CNT_RP1_TX_AR_MAX_CREDIT = $clog2(RP1_TX_AR_MAX_CREDIT +1), 
    localparam  CNT_RP1_TX_W_MAX_CREDIT  = $clog2(RP1_TX_W_MAX_CREDIT  +1), 
    localparam  CNT_RP1_TX_R_MAX_CREDIT  = $clog2(RP1_TX_R_MAX_CREDIT  +1),     
    localparam  CNT_RP1_TX_B_MAX_CREDIT  = $clog2(RP1_TX_B_MAX_CREDIT  +1),  

    localparam  CNT_RP2_TX_AW_MAX_CREDIT = $clog2(RP2_TX_AW_MAX_CREDIT +1), 
    localparam  CNT_RP2_TX_AR_MAX_CREDIT = $clog2(RP2_TX_AR_MAX_CREDIT +1), 
    localparam  CNT_RP2_TX_W_MAX_CREDIT  = $clog2(RP2_TX_W_MAX_CREDIT  +1), 
    localparam  CNT_RP2_TX_R_MAX_CREDIT  = $clog2(RP2_TX_R_MAX_CREDIT  +1),     
    localparam  CNT_RP2_TX_B_MAX_CREDIT  = $clog2(RP2_TX_B_MAX_CREDIT  +1),  

    localparam  CNT_RP3_TX_AW_MAX_CREDIT = $clog2(RP3_TX_AW_MAX_CREDIT +1), 
    localparam  CNT_RP3_TX_AR_MAX_CREDIT = $clog2(RP3_TX_AR_MAX_CREDIT +1), 
    localparam  CNT_RP3_TX_W_MAX_CREDIT  = $clog2(RP3_TX_W_MAX_CREDIT  +1), 
    localparam  CNT_RP3_TX_R_MAX_CREDIT  = $clog2(RP3_TX_R_MAX_CREDIT  +1),     
    localparam  CNT_RP3_TX_B_MAX_CREDIT  = $clog2(RP3_TX_B_MAX_CREDIT  +1),

    localparam  CNT_RP_TX_AW_MAX_CREDIT_MAX = max4(CNT_RP0_TX_AW_MAX_CREDIT, CNT_RP1_TX_AW_MAX_CREDIT, CNT_RP2_TX_AW_MAX_CREDIT, CNT_RP3_TX_AW_MAX_CREDIT),
    localparam  CNT_RP_TX_AR_MAX_CREDIT_MAX = max4(CNT_RP0_TX_AR_MAX_CREDIT, CNT_RP1_TX_AR_MAX_CREDIT, CNT_RP2_TX_AR_MAX_CREDIT, CNT_RP3_TX_AR_MAX_CREDIT),
    localparam  CNT_RP_TX_W_MAX_CREDIT_MAX  = max4(CNT_RP0_TX_W_MAX_CREDIT,  CNT_RP1_TX_W_MAX_CREDIT,  CNT_RP2_TX_W_MAX_CREDIT,  CNT_RP3_TX_W_MAX_CREDIT),
    localparam  CNT_RP_TX_R_MAX_CREDIT_MAX  = max4(CNT_RP0_TX_R_MAX_CREDIT,  CNT_RP1_TX_R_MAX_CREDIT,  CNT_RP2_TX_R_MAX_CREDIT,  CNT_RP3_TX_R_MAX_CREDIT),
    localparam  CNT_RP_TX_B_MAX_CREDIT_MAX  = max4(CNT_RP0_TX_B_MAX_CREDIT,  CNT_RP1_TX_B_MAX_CREDIT,  CNT_RP2_TX_B_MAX_CREDIT,  CNT_RP3_TX_B_MAX_CREDIT)  
)
(
    input                                       I_CLK,
    input                                       I_RESETN,
//-------------------------------------------------------------
    //Credit Message Interface to the Remote Die
    output       [2:0]                          O_AOU_MSGCREDIT_WREQCRED,
    output       [2:0]                          O_AOU_MSGCREDIT_RREQCRED,
    output       [2:0]                          O_AOU_MSGCREDIT_WDATACRED,
    output       [2:0]                          O_AOU_MSGCREDIT_RDATACRED,
    output       [1:0]                          O_AOU_MSGCREDIT_WRESPCRED,
    output       [1:0]                          O_AOU_MSGCREDIT_RP,
    output                                      O_AOU_MSGCREDIT_CRED_VALID,
    input                                       I_AOU_MSGCREDIT_CRED_READY,

    output       [1:0]                          O_AOU_CRDTGRANT_WRESPCRED3,
    output       [1:0]                          O_AOU_CRDTGRANT_WRESPCRED2,
    output       [1:0]                          O_AOU_CRDTGRANT_WRESPCRED1,
    output       [1:0]                          O_AOU_CRDTGRANT_WRESPCRED0,
    output       [2:0]                          O_AOU_CRDTGRANT_RDATACRED3,
    output       [2:0]                          O_AOU_CRDTGRANT_RDATACRED2,
    output       [2:0]                          O_AOU_CRDTGRANT_RDATACRED1,
    output       [2:0]                          O_AOU_CRDTGRANT_RDATACRED0,
    output       [2:0]                          O_AOU_CRDTGRANT_WDATACRED3,
    output       [2:0]                          O_AOU_CRDTGRANT_WDATACRED2,
    output       [2:0]                          O_AOU_CRDTGRANT_WDATACRED1,
    output       [2:0]                          O_AOU_CRDTGRANT_WDATACRED0,
    output       [2:0]                          O_AOU_CRDTGRANT_RREQCRED3,
    output       [2:0]                          O_AOU_CRDTGRANT_RREQCRED2,
    output       [2:0]                          O_AOU_CRDTGRANT_RREQCRED1,
    output       [2:0]                          O_AOU_CRDTGRANT_RREQCRED0,
    output       [2:0]                          O_AOU_CRDTGRANT_WREQCRED3,
    output       [2:0]                          O_AOU_CRDTGRANT_WREQCRED2,
    output       [2:0]                          O_AOU_CRDTGRANT_WREQCRED1,
    output       [2:0]                          O_AOU_CRDTGRANT_WREQCRED0,
    output                                      O_AOU_CRDTGRANT_VALID,
    input                                       I_AOU_CRDTGRANT_READY,

    //Interface for RX FIFO write handshake
    input       [RP_COUNT-1:0]                  I_AOU_RX_WREQVALID,
    input       [RP_COUNT-1:0]                  I_AOU_RX_RREQVALID, 
    input       [RP_COUNT-1:0]                  I_AOU_RX_WDATAVALID,
    input       [RP_COUNT-1:0][1:0]             I_AOU_RX_WDATA_DLENGTH,
    input       [RP_COUNT-1:0]                  I_AOU_RX_WDATAF,
    input       [RP_COUNT-1:0]                  I_AOU_RX_RDATAVALID,
    input       [RP_COUNT-1:0][1:0]             I_AOU_RX_RDATA_DLENGTH,
    input       [RP_COUNT-1:0]                  I_AOU_RX_WRESPVALID,

//-------------------------------------------------------------
    //Interface for TX CORE credit 
    output      [RP_COUNT-1:0][CNT_RP_TX_AW_MAX_CREDIT_MAX-1:0]      O_AOU_TX_WREQCRED,
    output      [RP_COUNT-1:0][CNT_RP_TX_AR_MAX_CREDIT_MAX-1:0]      O_AOU_TX_RREQCRED,
    output      [RP_COUNT-1:0][CNT_RP_TX_W_MAX_CREDIT_MAX-1:0]       O_AOU_TX_WDATACRED,
    output      [RP_COUNT-1:0][CNT_RP_TX_R_MAX_CREDIT_MAX-1:0]       O_AOU_TX_RDATACRED,
    output      [RP_COUNT-1:0][CNT_RP_TX_B_MAX_CREDIT_MAX-1:0]       O_AOU_TX_WRESPCRED,

    //Interface for TX CORE transaction hanshake
    input       [RP_COUNT-1:0]                  I_AOU_TX_WREQVALID,
    input       [RP_COUNT-1:0]                  I_AOU_TX_RREQVALID,
    input       [RP_COUNT-1:0]                  I_AOU_TX_WDATAVALID,
    input       [RP_COUNT-1:0][1:0]             I_AOU_TX_WDATA_DLENGTH,
    input       [RP_COUNT-1:0]                  I_AOU_TX_WFDATA,
    input       [RP_COUNT-1:0]                  I_AOU_TX_RDATAVALID,
    input       [RP_COUNT-1:0][1:0]             I_AOU_TX_RDATA_DLENGTH,
    input       [RP_COUNT-1:0]                  I_AOU_TX_WRESPVALID,

    //Credit Message Interface Received from the Remote Die
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]       I_AOU_CRDTGRANT_WRESPCRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]       I_AOU_CRDTGRANT_WRESPCRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]       I_AOU_CRDTGRANT_WRESPCRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]       I_AOU_CRDTGRANT_WRESPCRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RDATACRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RDATACRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RDATACRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RDATACRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WDATACRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WDATACRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WDATACRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WDATACRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RREQCRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RREQCRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RREQCRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_RREQCRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WREQCRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WREQCRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WREQCRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]       I_AOU_CRDTGRANT_WREQCRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0]            I_AOU_CRDTGRANT_VALID,
    
    input       [1:0]                           I_AOU_MSGCRDT_WRESPCRED,
    input       [2:0]                           I_AOU_MSGCRDT_RDATACRED,
    input       [2:0]                           I_AOU_MSGCRDT_WDATACRED,
    input       [2:0]                           I_AOU_MSGCRDT_RREQCRED,
    input       [2:0]                           I_AOU_MSGCRDT_WREQCRED,
    input       [1:0]                           I_AOU_MSGCRDT_RP,//destination
    input                                       I_AOU_MSGCRDT_VALID,
//-------------------------------------------------------------
    input                                       I_CRD_COUNT_EN,

    input                                       I_REQ_CRD_ADVERTISE_EN      ,
    input                                       I_TX_REQ_CREDITED_MESSAGE_EN,
    input                                       I_RSP_CRD_ADVERTISE_EN      , 
    input                                       I_TX_RSP_CREDITED_MESSAGE_EN,

    input                                       I_STATUS_DISABLE,
    
    input       [3:0][1:0]                      I_RP_DEST_RP,
    
    input                                       I_CREDIT_BLOCK,
    output                                      O_TX_REQ_CREDIT_BLOCKn,
    output                                      O_TX_RSP_CREDIT_BLOCKn
    

);

AOU_RX_CRD_CTRL 
#(
    .RP_COUNT                   (RP_COUNT              ),

    .RP0_AW_MAX_CREDIT          (RP0_RX_AW_MAX_CREDIT  ), 
    .RP0_AR_MAX_CREDIT          (RP0_RX_AR_MAX_CREDIT  ), 
    .RP0_W_MAX_CREDIT           (RP0_RX_W_MAX_CREDIT   ), 
    .RP0_R_MAX_CREDIT           (RP0_RX_R_MAX_CREDIT   ), 
    .RP0_B_MAX_CREDIT           (RP0_RX_B_MAX_CREDIT   ), 
    .RP1_AW_MAX_CREDIT          (RP1_RX_AW_MAX_CREDIT  ), 
    .RP1_AR_MAX_CREDIT          (RP1_RX_AR_MAX_CREDIT  ), 
    .RP1_W_MAX_CREDIT           (RP1_RX_W_MAX_CREDIT   ), 
    .RP1_R_MAX_CREDIT           (RP1_RX_R_MAX_CREDIT   ), 
    .RP1_B_MAX_CREDIT           (RP1_RX_B_MAX_CREDIT   ), 
    .RP2_AW_MAX_CREDIT          (RP2_RX_AW_MAX_CREDIT  ), 
    .RP2_AR_MAX_CREDIT          (RP2_RX_AR_MAX_CREDIT  ), 
    .RP2_W_MAX_CREDIT           (RP2_RX_W_MAX_CREDIT   ), 
    .RP2_R_MAX_CREDIT           (RP2_RX_R_MAX_CREDIT   ), 
    .RP2_B_MAX_CREDIT           (RP2_RX_B_MAX_CREDIT   ), 
    .RP3_AW_MAX_CREDIT          (RP3_RX_AW_MAX_CREDIT  ), 
    .RP3_AR_MAX_CREDIT          (RP3_RX_AR_MAX_CREDIT  ), 
    .RP3_W_MAX_CREDIT           (RP3_RX_W_MAX_CREDIT   ), 
    .RP3_R_MAX_CREDIT           (RP3_RX_R_MAX_CREDIT   ), 
    .RP3_B_MAX_CREDIT           (RP3_RX_B_MAX_CREDIT   )

) u_aou_rx_crd_ctrl (
    .I_CLK                      (I_CLK                      ),
    .I_RESETN                   (I_RESETN                   ),
                                                            
    .O_AOU_MSGCREDIT_WREQCRED   (O_AOU_MSGCREDIT_WREQCRED   ),
    .O_AOU_MSGCREDIT_RREQCRED   (O_AOU_MSGCREDIT_RREQCRED   ),
    .O_AOU_MSGCREDIT_WDATACRED  (O_AOU_MSGCREDIT_WDATACRED  ),
    .O_AOU_MSGCREDIT_RDATACRED  (O_AOU_MSGCREDIT_RDATACRED  ),
    .O_AOU_MSGCREDIT_WRESPCRED  (O_AOU_MSGCREDIT_WRESPCRED  ),
    .O_AOU_MSGCREDIT_RP         (O_AOU_MSGCREDIT_RP         ),
    .O_AOU_MSGCREDIT_CRED_VALID (O_AOU_MSGCREDIT_CRED_VALID ),
    .I_AOU_MSGCREDIT_CRED_READY (I_AOU_MSGCREDIT_CRED_READY ),
                                                            
    .O_AOU_CRDTGRANT_WRESPCRED3 (O_AOU_CRDTGRANT_WRESPCRED3 ),
    .O_AOU_CRDTGRANT_WRESPCRED2 (O_AOU_CRDTGRANT_WRESPCRED2 ),
    .O_AOU_CRDTGRANT_WRESPCRED1 (O_AOU_CRDTGRANT_WRESPCRED1 ),
    .O_AOU_CRDTGRANT_WRESPCRED0 (O_AOU_CRDTGRANT_WRESPCRED0 ),
    .O_AOU_CRDTGRANT_RDATACRED3 (O_AOU_CRDTGRANT_RDATACRED3 ),
    .O_AOU_CRDTGRANT_RDATACRED2 (O_AOU_CRDTGRANT_RDATACRED2 ),
    .O_AOU_CRDTGRANT_RDATACRED1 (O_AOU_CRDTGRANT_RDATACRED1 ),
    .O_AOU_CRDTGRANT_RDATACRED0 (O_AOU_CRDTGRANT_RDATACRED0 ),
    .O_AOU_CRDTGRANT_WDATACRED3 (O_AOU_CRDTGRANT_WDATACRED3 ),
    .O_AOU_CRDTGRANT_WDATACRED2 (O_AOU_CRDTGRANT_WDATACRED2 ),
    .O_AOU_CRDTGRANT_WDATACRED1 (O_AOU_CRDTGRANT_WDATACRED1 ),
    .O_AOU_CRDTGRANT_WDATACRED0 (O_AOU_CRDTGRANT_WDATACRED0 ),
    .O_AOU_CRDTGRANT_RREQCRED3  (O_AOU_CRDTGRANT_RREQCRED3  ),
    .O_AOU_CRDTGRANT_RREQCRED2  (O_AOU_CRDTGRANT_RREQCRED2  ),
    .O_AOU_CRDTGRANT_RREQCRED1  (O_AOU_CRDTGRANT_RREQCRED1  ),
    .O_AOU_CRDTGRANT_RREQCRED0  (O_AOU_CRDTGRANT_RREQCRED0  ),
    .O_AOU_CRDTGRANT_WREQCRED3  (O_AOU_CRDTGRANT_WREQCRED3  ),
    .O_AOU_CRDTGRANT_WREQCRED2  (O_AOU_CRDTGRANT_WREQCRED2  ),
    .O_AOU_CRDTGRANT_WREQCRED1  (O_AOU_CRDTGRANT_WREQCRED1  ),
    .O_AOU_CRDTGRANT_WREQCRED0  (O_AOU_CRDTGRANT_WREQCRED0  ),
    .O_AOU_CRDTGRANT_VALID      (O_AOU_CRDTGRANT_VALID      ),
    .I_AOU_CRDTGRANT_READY      (I_AOU_CRDTGRANT_READY      ),
                                                            
    .I_AOU_RX_WREQVALID         (I_AOU_RX_WREQVALID         ),
    .I_AOU_RX_RREQVALID         (I_AOU_RX_RREQVALID         ), 
    .I_AOU_RX_WDATAVALID        (I_AOU_RX_WDATAVALID        ),
    .I_AOU_RX_WDATA_DLENGTH     (I_AOU_RX_WDATA_DLENGTH     ),
    .I_AOU_RX_WDATAF            (I_AOU_RX_WDATAF            ),
    .I_AOU_RX_RDATAVALID        (I_AOU_RX_RDATAVALID        ),
    .I_AOU_RX_RDATA_DLENGTH     (I_AOU_RX_RDATA_DLENGTH     ),
    .I_AOU_RX_WRESPVALID        (I_AOU_RX_WRESPVALID        ),

    .I_REQ_CRD_ADVERTISE_EN     (I_REQ_CRD_ADVERTISE_EN     ), 
    .I_RSP_CRD_ADVERTISE_EN     (I_RSP_CRD_ADVERTISE_EN     ), 

    .I_STATUS_DISABLE           (I_STATUS_DISABLE           ) 
);
                                              
AOU_TX_CRD_CTRL #(                                                            
    .RP_COUNT                       (RP_COUNT                       ),

    .RP0_AW_MAX_CREDIT              (RP0_TX_AW_MAX_CREDIT           ), 
    .RP0_AR_MAX_CREDIT              (RP0_TX_AR_MAX_CREDIT           ), 
    .RP0_W_MAX_CREDIT               (RP0_TX_W_MAX_CREDIT            ), 
    .RP0_R_MAX_CREDIT               (RP0_TX_R_MAX_CREDIT            ), 
    .RP0_B_MAX_CREDIT               (RP0_TX_B_MAX_CREDIT            ), 
    .RP1_AW_MAX_CREDIT              (RP1_TX_AW_MAX_CREDIT           ), 
    .RP1_AR_MAX_CREDIT              (RP1_TX_AR_MAX_CREDIT           ), 
    .RP1_W_MAX_CREDIT               (RP1_TX_W_MAX_CREDIT            ), 
    .RP1_R_MAX_CREDIT               (RP1_TX_R_MAX_CREDIT            ), 
    .RP1_B_MAX_CREDIT               (RP1_TX_B_MAX_CREDIT            ), 
    .RP2_AW_MAX_CREDIT              (RP2_TX_AW_MAX_CREDIT           ), 
    .RP2_AR_MAX_CREDIT              (RP2_TX_AR_MAX_CREDIT           ), 
    .RP2_W_MAX_CREDIT               (RP2_TX_W_MAX_CREDIT            ), 
    .RP2_R_MAX_CREDIT               (RP2_TX_R_MAX_CREDIT            ), 
    .RP2_B_MAX_CREDIT               (RP2_TX_B_MAX_CREDIT            ), 
    .RP3_AW_MAX_CREDIT              (RP3_TX_AW_MAX_CREDIT           ), 
    .RP3_AR_MAX_CREDIT              (RP3_TX_AR_MAX_CREDIT           ), 
    .RP3_W_MAX_CREDIT               (RP3_TX_W_MAX_CREDIT            ), 
    .RP3_R_MAX_CREDIT               (RP3_TX_R_MAX_CREDIT            ), 
    .RP3_B_MAX_CREDIT               (RP3_TX_B_MAX_CREDIT            ),

    .AXI_DATA_WD_RP0                (RP0_AXI_DATA_WD                ),
    .AXI_DATA_WD_RP1                (RP1_AXI_DATA_WD                ),
    .AXI_DATA_WD_RP2                (RP2_AXI_DATA_WD                ),
    .AXI_DATA_WD_RP3                (RP3_AXI_DATA_WD                ),
    
    .DEC_MULTI                      (DEC_MULTI                      )

) u_aou_tx_crd_ctrl(
    .I_CLK                          (I_CLK                          ),
    .I_RESETN                       (I_RESETN                       ),
                                                                    
    .O_AOU_TX_WREQCRED              (O_AOU_TX_WREQCRED              ),
    .O_AOU_TX_RREQCRED              (O_AOU_TX_RREQCRED              ),
    .O_AOU_TX_WDATACRED             (O_AOU_TX_WDATACRED             ),
    .O_AOU_TX_RDATACRED             (O_AOU_TX_RDATACRED             ),
    .O_AOU_TX_WRESPCRED             (O_AOU_TX_WRESPCRED             ),
                                                               
    .I_AOU_TX_WREQVALID             (I_AOU_TX_WREQVALID             ),
    .I_AOU_TX_RREQVALID             (I_AOU_TX_RREQVALID             ),
    .I_AOU_TX_WDATA_DLENGTH         (I_AOU_TX_WDATA_DLENGTH         ),
    .I_AOU_TX_WDATAVALID            (I_AOU_TX_WDATAVALID            ),
    .I_AOU_TX_WFDATA                (I_AOU_TX_WFDATA                ),
    .I_AOU_TX_RDATAVALID            (I_AOU_TX_RDATAVALID            ),
    .I_AOU_TX_RDATA_DLENGTH         (I_AOU_TX_RDATA_DLENGTH         ),
    .I_AOU_TX_WRESPVALID            (I_AOU_TX_WRESPVALID            ),
                                                                    
    .I_AOU_CRDTGRANT_WRESPCRED3     (I_AOU_CRDTGRANT_WRESPCRED3     ),
    .I_AOU_CRDTGRANT_WRESPCRED2     (I_AOU_CRDTGRANT_WRESPCRED2     ),
    .I_AOU_CRDTGRANT_WRESPCRED1     (I_AOU_CRDTGRANT_WRESPCRED1     ),
    .I_AOU_CRDTGRANT_WRESPCRED0     (I_AOU_CRDTGRANT_WRESPCRED0     ),
    .I_AOU_CRDTGRANT_RDATACRED3     (I_AOU_CRDTGRANT_RDATACRED3     ),
    .I_AOU_CRDTGRANT_RDATACRED2     (I_AOU_CRDTGRANT_RDATACRED2     ),
    .I_AOU_CRDTGRANT_RDATACRED1     (I_AOU_CRDTGRANT_RDATACRED1     ),
    .I_AOU_CRDTGRANT_RDATACRED0     (I_AOU_CRDTGRANT_RDATACRED0     ),
    .I_AOU_CRDTGRANT_WDATACRED3     (I_AOU_CRDTGRANT_WDATACRED3     ),
    .I_AOU_CRDTGRANT_WDATACRED2     (I_AOU_CRDTGRANT_WDATACRED2     ),
    .I_AOU_CRDTGRANT_WDATACRED1     (I_AOU_CRDTGRANT_WDATACRED1     ),
    .I_AOU_CRDTGRANT_WDATACRED0     (I_AOU_CRDTGRANT_WDATACRED0     ),
    .I_AOU_CRDTGRANT_RREQCRED3      (I_AOU_CRDTGRANT_RREQCRED3      ),
    .I_AOU_CRDTGRANT_RREQCRED2      (I_AOU_CRDTGRANT_RREQCRED2      ),
    .I_AOU_CRDTGRANT_RREQCRED1      (I_AOU_CRDTGRANT_RREQCRED1      ),
    .I_AOU_CRDTGRANT_RREQCRED0      (I_AOU_CRDTGRANT_RREQCRED0      ),
    .I_AOU_CRDTGRANT_WREQCRED3      (I_AOU_CRDTGRANT_WREQCRED3      ),
    .I_AOU_CRDTGRANT_WREQCRED2      (I_AOU_CRDTGRANT_WREQCRED2      ),
    .I_AOU_CRDTGRANT_WREQCRED1      (I_AOU_CRDTGRANT_WREQCRED1      ),
    .I_AOU_CRDTGRANT_WREQCRED0      (I_AOU_CRDTGRANT_WREQCRED0      ),
    .I_AOU_CRDTGRANT_VALID          (I_AOU_CRDTGRANT_VALID          ),
                                                                    
    .I_AOU_MSGCRDT_WRESPCRED        (I_AOU_MSGCRDT_WRESPCRED        ),
    .I_AOU_MSGCRDT_RDATACRED        (I_AOU_MSGCRDT_RDATACRED        ),
    .I_AOU_MSGCRDT_WDATACRED        (I_AOU_MSGCRDT_WDATACRED        ),
    .I_AOU_MSGCRDT_RREQCRED         (I_AOU_MSGCRDT_RREQCRED         ),
    .I_AOU_MSGCRDT_WREQCRED         (I_AOU_MSGCRDT_WREQCRED         ),
    .I_AOU_MSGCRDT_RP               (I_AOU_MSGCRDT_RP               ),//destination
    .I_AOU_MSGCRDT_VALID            (I_AOU_MSGCRDT_VALID            ),

    .I_CRD_COUNT_EN                 (I_CRD_COUNT_EN                 ), 

    .I_TX_REQ_CREDITED_MESSAGE_EN   (I_TX_REQ_CREDITED_MESSAGE_EN   ),
    .I_TX_RSP_CREDITED_MESSAGE_EN   (I_TX_RSP_CREDITED_MESSAGE_EN   ),
    .I_STATUS_DISABLE               (I_STATUS_DISABLE               ),

    .I_RP_DEST_RP                   (I_RP_DEST_RP                   ),

    .I_CREDIT_BLOCK                 (I_CREDIT_BLOCK                 ),
    .O_TX_REQ_CREDIT_BLOCKn         (O_TX_REQ_CREDIT_BLOCKn         ),
    .O_TX_RSP_CREDIT_BLOCKn         (O_TX_RSP_CREDIT_BLOCKn         )
    
);
endmodule                                     
                                              
                                              
