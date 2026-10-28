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
//  Module     : AOU_TX_CRD_CTRL
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TX_CRD_CTRL
import packet_def_pkg::*; 
#(
    parameter   RP_COUNT                 = 4,    

    parameter   RP0_AW_MAX_CREDIT        = 2048, 
    parameter   RP0_AR_MAX_CREDIT        = 2048, 
    parameter   RP0_W_MAX_CREDIT         = 2048, 
    parameter   RP0_R_MAX_CREDIT         = 2048, 
    parameter   RP0_B_MAX_CREDIT         = 2048, 
    parameter   RP1_AW_MAX_CREDIT        = 2048, 
    parameter   RP1_AR_MAX_CREDIT        = 2048, 
    parameter   RP1_W_MAX_CREDIT         = 2048, 
    parameter   RP1_R_MAX_CREDIT         = 2048, 
    parameter   RP1_B_MAX_CREDIT         = 2048, 
    parameter   RP2_AW_MAX_CREDIT        = 2048, 
    parameter   RP2_AR_MAX_CREDIT        = 2048, 
    parameter   RP2_W_MAX_CREDIT         = 2048, 
    parameter   RP2_R_MAX_CREDIT         = 2048, 
    parameter   RP2_B_MAX_CREDIT         = 2048, 
    parameter   RP3_AW_MAX_CREDIT        = 2048, 
    parameter   RP3_AR_MAX_CREDIT        = 2048, 
    parameter   RP3_W_MAX_CREDIT         = 2048, 
    parameter   RP3_R_MAX_CREDIT         = 2048, 
    parameter   RP3_B_MAX_CREDIT         = 2048,

    parameter   AXI_DATA_WD_RP0          = 512,
    parameter   AXI_DATA_WD_RP1          = 512,
    parameter   AXI_DATA_WD_RP2          = 512,
    parameter   AXI_DATA_WD_RP3          = 512,

    parameter   DEC_MULTI                = 2,

    localparam  MAX_MISC_CNT             = 2,

    localparam  CNT_RP0_AW_MAX_CREDIT = $clog2(RP0_AW_MAX_CREDIT +1), 
    localparam  CNT_RP0_AR_MAX_CREDIT = $clog2(RP0_AR_MAX_CREDIT +1), 
    localparam  CNT_RP0_W_MAX_CREDIT  = $clog2(RP0_W_MAX_CREDIT  +1), 
    localparam  CNT_RP0_R_MAX_CREDIT  = $clog2(RP0_R_MAX_CREDIT  +1),     
    localparam  CNT_RP0_B_MAX_CREDIT  = $clog2(RP0_B_MAX_CREDIT  +1),      

    localparam  CNT_RP1_AW_MAX_CREDIT = $clog2(RP1_AW_MAX_CREDIT +1), 
    localparam  CNT_RP1_AR_MAX_CREDIT = $clog2(RP1_AR_MAX_CREDIT +1), 
    localparam  CNT_RP1_W_MAX_CREDIT  = $clog2(RP1_W_MAX_CREDIT  +1), 
    localparam  CNT_RP1_R_MAX_CREDIT  = $clog2(RP1_R_MAX_CREDIT  +1),     
    localparam  CNT_RP1_B_MAX_CREDIT  = $clog2(RP1_B_MAX_CREDIT  +1),  

    localparam  CNT_RP2_AW_MAX_CREDIT = $clog2(RP2_AW_MAX_CREDIT +1), 
    localparam  CNT_RP2_AR_MAX_CREDIT = $clog2(RP2_AR_MAX_CREDIT +1), 
    localparam  CNT_RP2_W_MAX_CREDIT  = $clog2(RP2_W_MAX_CREDIT  +1), 
    localparam  CNT_RP2_R_MAX_CREDIT  = $clog2(RP2_R_MAX_CREDIT  +1),     
    localparam  CNT_RP2_B_MAX_CREDIT  = $clog2(RP2_B_MAX_CREDIT  +1),  

    localparam  CNT_RP3_AW_MAX_CREDIT = $clog2(RP3_AW_MAX_CREDIT +1), 
    localparam  CNT_RP3_AR_MAX_CREDIT = $clog2(RP3_AR_MAX_CREDIT +1), 
    localparam  CNT_RP3_W_MAX_CREDIT  = $clog2(RP3_W_MAX_CREDIT  +1), 
    localparam  CNT_RP3_R_MAX_CREDIT  = $clog2(RP3_R_MAX_CREDIT  +1),     
    localparam  CNT_RP3_B_MAX_CREDIT  = $clog2(RP3_B_MAX_CREDIT  +1),

    localparam CNT_RP_AW_MAX_CREDIT_MAX = max4(CNT_RP0_AW_MAX_CREDIT, CNT_RP1_AW_MAX_CREDIT, CNT_RP2_AW_MAX_CREDIT, CNT_RP3_AW_MAX_CREDIT),
    localparam CNT_RP_AR_MAX_CREDIT_MAX = max4(CNT_RP0_AR_MAX_CREDIT, CNT_RP1_AR_MAX_CREDIT, CNT_RP2_AR_MAX_CREDIT, CNT_RP3_AR_MAX_CREDIT),
    localparam CNT_RP_W_MAX_CREDIT_MAX  = max4(CNT_RP0_W_MAX_CREDIT, CNT_RP1_W_MAX_CREDIT, CNT_RP2_W_MAX_CREDIT, CNT_RP3_W_MAX_CREDIT),
    localparam CNT_RP_R_MAX_CREDIT_MAX  = max4(CNT_RP0_R_MAX_CREDIT, CNT_RP1_R_MAX_CREDIT, CNT_RP2_R_MAX_CREDIT, CNT_RP3_R_MAX_CREDIT),
    localparam CNT_RP_B_MAX_CREDIT_MAX  = max4(CNT_RP0_B_MAX_CREDIT, CNT_RP1_B_MAX_CREDIT, CNT_RP2_B_MAX_CREDIT, CNT_RP3_B_MAX_CREDIT),

    localparam int unsigned RP_AXI_DATA_WD[4]  = '{
        AXI_DATA_WD_RP0,
        AXI_DATA_WD_RP1,
        AXI_DATA_WD_RP2,
        AXI_DATA_WD_RP3
    },

    localparam int unsigned RP_AW_MAX_CREDIT[4] = '{
        RP0_AW_MAX_CREDIT,
        RP1_AW_MAX_CREDIT,
        RP2_AW_MAX_CREDIT,
        RP3_AW_MAX_CREDIT
    },

    localparam int unsigned RP_AR_MAX_CREDIT[4] = '{
        RP0_AR_MAX_CREDIT,
        RP1_AR_MAX_CREDIT,
        RP2_AR_MAX_CREDIT,
        RP3_AR_MAX_CREDIT
    },

    localparam int unsigned RP_W_MAX_CREDIT[4] = '{
        RP0_W_MAX_CREDIT,
        RP1_W_MAX_CREDIT,
        RP2_W_MAX_CREDIT,
        RP3_W_MAX_CREDIT
    },

    localparam int unsigned RP_R_MAX_CREDIT[4] = '{
        RP0_R_MAX_CREDIT,
        RP1_R_MAX_CREDIT,
        RP2_R_MAX_CREDIT,
        RP3_R_MAX_CREDIT
    },

    localparam int unsigned RP_B_MAX_CREDIT[4] = '{
        RP0_B_MAX_CREDIT,
        RP1_B_MAX_CREDIT,
        RP2_B_MAX_CREDIT,
        RP3_B_MAX_CREDIT
    },
 
    localparam int unsigned CNT_RP_AW_MAX_CREDIT[4] = '{
        CNT_RP0_AW_MAX_CREDIT,
        CNT_RP1_AW_MAX_CREDIT,
        CNT_RP2_AW_MAX_CREDIT,
        CNT_RP3_AW_MAX_CREDIT
    },

    localparam int unsigned CNT_RP_AR_MAX_CREDIT[4] = '{
        CNT_RP0_AR_MAX_CREDIT,
        CNT_RP1_AR_MAX_CREDIT,
        CNT_RP2_AR_MAX_CREDIT,
        CNT_RP3_AR_MAX_CREDIT
    },

    localparam int unsigned CNT_RP_W_MAX_CREDIT[4] = '{
        CNT_RP0_W_MAX_CREDIT,
        CNT_RP1_W_MAX_CREDIT,
        CNT_RP2_W_MAX_CREDIT,
        CNT_RP3_W_MAX_CREDIT
    },

    localparam int unsigned CNT_RP_R_MAX_CREDIT[4] = '{
        CNT_RP0_R_MAX_CREDIT,
        CNT_RP1_R_MAX_CREDIT,
        CNT_RP2_R_MAX_CREDIT,
        CNT_RP3_R_MAX_CREDIT
    },

    localparam int unsigned CNT_RP_B_MAX_CREDIT[4] = '{
        CNT_RP0_B_MAX_CREDIT,
        CNT_RP1_B_MAX_CREDIT,
        CNT_RP2_B_MAX_CREDIT,
        CNT_RP3_B_MAX_CREDIT
    }

)
(
    input                                       I_CLK,
    input                                       I_RESETN,

    output  logic    [RP_COUNT-1:0][CNT_RP_AW_MAX_CREDIT_MAX-1:0]  O_AOU_TX_WREQCRED,
    output  logic    [RP_COUNT-1:0][CNT_RP_AR_MAX_CREDIT_MAX-1:0]  O_AOU_TX_RREQCRED,
    output  logic    [RP_COUNT-1:0][CNT_RP_W_MAX_CREDIT_MAX-1:0]   O_AOU_TX_WDATACRED,
    output  logic    [RP_COUNT-1:0][CNT_RP_R_MAX_CREDIT_MAX-1:0]   O_AOU_TX_RDATACRED,
    output  logic    [RP_COUNT-1:0][CNT_RP_B_MAX_CREDIT_MAX-1:0]   O_AOU_TX_WRESPCRED,

    input       [RP_COUNT-1:0]                  I_AOU_TX_WREQVALID,
    input       [RP_COUNT-1:0]                  I_AOU_TX_RREQVALID,
    input       [RP_COUNT-1:0]                  I_AOU_TX_WDATAVALID,
    input       [RP_COUNT-1:0][1:0]             I_AOU_TX_WDATA_DLENGTH,
    input       [RP_COUNT-1:0]                  I_AOU_TX_WFDATA,
    input       [RP_COUNT-1:0]                  I_AOU_TX_RDATAVALID,
    input       [RP_COUNT-1:0][1:0]             I_AOU_TX_RDATA_DLENGTH,
    input       [RP_COUNT-1:0]                  I_AOU_TX_WRESPVALID,
    
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]                           I_AOU_CRDTGRANT_WRESPCRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]                           I_AOU_CRDTGRANT_WRESPCRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]                           I_AOU_CRDTGRANT_WRESPCRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][1:0]                           I_AOU_CRDTGRANT_WRESPCRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RDATACRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RDATACRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RDATACRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RDATACRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WDATACRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WDATACRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WDATACRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WDATACRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RREQCRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RREQCRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RREQCRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_RREQCRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WREQCRED3,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WREQCRED2,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WREQCRED1,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][2:0]                           I_AOU_CRDTGRANT_WREQCRED0,
    input       [DEC_MULTI-1:0][MAX_MISC_CNT-1:0]                                I_AOU_CRDTGRANT_VALID,

    input       [1:0]                           I_AOU_MSGCRDT_WRESPCRED,
    input       [2:0]                           I_AOU_MSGCRDT_RDATACRED,
    input       [2:0]                           I_AOU_MSGCRDT_WDATACRED,
    input       [2:0]                           I_AOU_MSGCRDT_RREQCRED,
    input       [2:0]                           I_AOU_MSGCRDT_WREQCRED,
    input       [1:0]                           I_AOU_MSGCRDT_RP,
    input                                       I_AOU_MSGCRDT_VALID,

    input                                       I_CRD_COUNT_EN,
    input                                       I_TX_REQ_CREDITED_MESSAGE_EN,
    input                                       I_TX_RSP_CREDITED_MESSAGE_EN,

    input                                       I_STATUS_DISABLE,
    
    //RP Mapping
    input       [3:0][1:0]                      I_RP_DEST_RP,

    input                                       I_CREDIT_BLOCK,
    output                                      O_TX_REQ_CREDIT_BLOCKn,
    output                                      O_TX_RSP_CREDIT_BLOCKn
    

);

logic                           r_status_disable_1d;
logic                           w_status_disable_rising_edge_detect;

logic                           r_tx_req_credited_message_en;
logic                           r_tx_rsp_credited_message_en;

for (genvar a = 0; a <4 ; a++) begin : generate_rp_aw_credit
    logic [CNT_RP_AW_MAX_CREDIT[a]-1:0] r_cnt_aw_credit_rx;
end

for (genvar a = 0; a <4 ; a++) begin : generate_rp_ar_credit
    logic [CNT_RP_AR_MAX_CREDIT[a]-1:0] r_cnt_ar_credit_rx;
end

for (genvar a = 0; a <4 ; a++) begin : generate_rp_w_credit
    logic [CNT_RP_W_MAX_CREDIT[a]-1:0] r_cnt_w_credit_rx;
end

for (genvar a = 0; a <4 ; a++) begin : generate_rp_r_credit
    logic [CNT_RP_R_MAX_CREDIT[a]-1:0] r_cnt_r_credit_rx;
end

for (genvar a = 0; a <4 ; a++) begin : generate_rp_b_credit
    logic [CNT_RP_B_MAX_CREDIT[a]-1:0] r_cnt_b_credit_rx;
end

logic   [3:0] [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][3:0]             i_crdtgrant_wrespcred;
logic   [3:0] [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][7:0]             i_crdtgrant_rdatacred;
logic   [3:0] [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][7:0]             i_crdtgrant_wdatacred;
logic   [3:0] [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][7:0]             i_crdtgrant_rreqcred;
logic   [3:0] [DEC_MULTI-1:0][MAX_MISC_CNT-1:0][7:0]             i_crdtgrant_wreqcred;

logic   [3:0] [9:0]             w_cnt_rp_aw_credit;
logic   [3:0] [9:0]             w_cnt_rp_ar_credit;
logic   [3:0] [9:0]             w_cnt_rp_w_credit; 
logic   [3:0] [9:0]             w_cnt_rp_r_credit; 
logic   [3:0] [5:0]             w_cnt_rp_b_credit;
 
logic   [RP_COUNT-1:0] [8:0]    w_cnt_rp_aw_credit_discount;
logic   [RP_COUNT-1:0] [8:0]    w_cnt_rp_ar_credit_discount;
logic   [RP_COUNT-1:0] [8:0]    w_cnt_rp_w_credit_discount; 
logic   [RP_COUNT-1:0] [8:0]    w_cnt_rp_r_credit_discount; 
logic   [RP_COUNT-1:0] [4:0]    w_cnt_rp_b_credit_discount; 

logic                           w_rp0_credit_match;
logic                           w_rp1_credit_match;
logic                           w_rp2_credit_match;
logic                           w_rp3_credit_match;
logic   [3:0]                   w_rp_credit_match_one_hot;

logic   [3:0]                   w_aou_tx_wreqvalid_dest_rp;
logic   [3:0]                   w_aou_tx_rreqvalid_dest_rp;
logic   [3:0]                   w_aou_tx_wdatavalid_dest_rp;
logic   [3:0]                   w_aou_tx_rdatavalid_dest_rp;
logic   [3:0]                   w_aou_tx_wrespvalid_dest_rp;

logic   [3:0] [8:0]             w_cnt_rp_aw_credit_discount_dest_rp;
logic   [3:0] [8:0]             w_cnt_rp_ar_credit_discount_dest_rp;
logic   [3:0] [8:0]             w_cnt_rp_w_credit_discount_dest_rp; 
logic   [3:0] [8:0]             w_cnt_rp_r_credit_discount_dest_rp; 
logic   [3:0] [4:0]             w_cnt_rp_b_credit_discount_dest_rp; 

//-------------------------------------------------------------

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN)begin
         r_status_disable_1d <= 1'b0;

    end else begin
         r_status_disable_1d <= I_STATUS_DISABLE;
    end
end
assign  w_status_disable_rising_edge_detect =   ~r_status_disable_1d & I_STATUS_DISABLE;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_tx_req_credited_message_en <= 1'b0;
    end else begin
        r_tx_req_credited_message_en <= I_TX_REQ_CREDITED_MESSAGE_EN && ~I_CREDIT_BLOCK;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_tx_rsp_credited_message_en <= 1'b0;
    end else begin
        r_tx_rsp_credited_message_en <= I_TX_RSP_CREDITED_MESSAGE_EN && ~I_CREDIT_BLOCK;
    end
end

assign O_TX_REQ_CREDIT_BLOCKn  = r_tx_req_credited_message_en;
assign O_TX_RSP_CREDIT_BLOCKn  = r_tx_rsp_credited_message_en;

//For TX_CORE Credit count
assign  w_rp0_credit_match        = (I_AOU_MSGCRDT_RP == 2'b00);
assign  w_rp1_credit_match        = (I_AOU_MSGCRDT_RP == 2'b01);
assign  w_rp2_credit_match        = (I_AOU_MSGCRDT_RP == 2'b10);
assign  w_rp3_credit_match        = (I_AOU_MSGCRDT_RP == 2'b11);
assign  w_rp_credit_match_one_hot = {w_rp3_credit_match,w_rp2_credit_match,w_rp1_credit_match,w_rp0_credit_match};

always_comb begin
    for(int dec_multi = 0 ; dec_multi < DEC_MULTI; dec_multi = dec_multi + 1) begin
        for(int misc_cnt = 0; misc_cnt < MAX_MISC_CNT; misc_cnt = misc_cnt +1) begin
            i_crdtgrant_wrespcred[0][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WRESPCRED0[dec_multi][misc_cnt]][3:0];
            i_crdtgrant_rdatacred[0][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RDATACRED0[dec_multi][misc_cnt]];
            i_crdtgrant_wdatacred[0][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WDATACRED0[dec_multi][misc_cnt]];
            i_crdtgrant_rreqcred [0][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RREQCRED0 [dec_multi][misc_cnt]];
            i_crdtgrant_wreqcred [0][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WREQCRED0 [dec_multi][misc_cnt]];
            
            i_crdtgrant_wrespcred[1][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WRESPCRED1[dec_multi][misc_cnt]][3:0];
            i_crdtgrant_rdatacred[1][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RDATACRED1[dec_multi][misc_cnt]];
            i_crdtgrant_wdatacred[1][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WDATACRED1[dec_multi][misc_cnt]];
            i_crdtgrant_rreqcred [1][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RREQCRED1 [dec_multi][misc_cnt]];
            i_crdtgrant_wreqcred [1][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WREQCRED1 [dec_multi][misc_cnt]];
            
            i_crdtgrant_wrespcred[2][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WRESPCRED2[dec_multi][misc_cnt]][3:0];
            i_crdtgrant_rdatacred[2][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RDATACRED2[dec_multi][misc_cnt]];
            i_crdtgrant_wdatacred[2][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WDATACRED2[dec_multi][misc_cnt]];
            i_crdtgrant_rreqcred [2][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RREQCRED2 [dec_multi][misc_cnt]];
            i_crdtgrant_wreqcred [2][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WREQCRED2 [dec_multi][misc_cnt]];
            
            i_crdtgrant_wrespcred[3][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WRESPCRED3[dec_multi][misc_cnt]][3:0];
            i_crdtgrant_rdatacred[3][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RDATACRED3[dec_multi][misc_cnt]];
            i_crdtgrant_wdatacred[3][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WDATACRED3[dec_multi][misc_cnt]];
            i_crdtgrant_rreqcred [3][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_RREQCRED3 [dec_multi][misc_cnt]];
            i_crdtgrant_wreqcred [3][dec_multi][misc_cnt]   = CREDIT_TABLE[I_AOU_CRDTGRANT_WREQCRED3 [dec_multi][misc_cnt]];
        end
    end
end

always_comb begin
    for(int unsigned i=0; i<4; i= i+1)begin
        w_cnt_rp_aw_credit[i]   = 'd0;
        w_cnt_rp_ar_credit[i]   = 'd0;
        w_cnt_rp_w_credit[i]    = 'd0;
        w_cnt_rp_r_credit[i]    = 'd0;
        w_cnt_rp_b_credit[i]    = 'd0;
        if(I_AOU_MSGCRDT_VALID) begin
            if(w_rp_credit_match_one_hot[i]) begin
                w_cnt_rp_aw_credit[i]   +=   CREDIT_TABLE[I_AOU_MSGCRDT_WREQCRED    ];
                w_cnt_rp_ar_credit[i]   +=   CREDIT_TABLE[I_AOU_MSGCRDT_RREQCRED    ];
                w_cnt_rp_w_credit[i]    +=   CREDIT_TABLE[I_AOU_MSGCRDT_WDATACRED   ];
                w_cnt_rp_r_credit[i]    +=   CREDIT_TABLE[I_AOU_MSGCRDT_RDATACRED   ];
                w_cnt_rp_b_credit[i]    +=   CREDIT_TABLE[I_AOU_MSGCRDT_WRESPCRED   ][3:0];
            end
        end
        for(int dec_multi = 0 ; dec_multi < DEC_MULTI; dec_multi = dec_multi + 1) begin
            for(int misc_cnt = 0; misc_cnt < MAX_MISC_CNT; misc_cnt = misc_cnt +1) begin
                if(I_AOU_CRDTGRANT_VALID[dec_multi][misc_cnt])begin
                    w_cnt_rp_aw_credit[i]   +=   i_crdtgrant_wreqcred [i][dec_multi][misc_cnt];
                    w_cnt_rp_ar_credit[i]   +=   i_crdtgrant_rreqcred [i][dec_multi][misc_cnt];
                    w_cnt_rp_w_credit[i]    +=   i_crdtgrant_wdatacred[i][dec_multi][misc_cnt];
                    w_cnt_rp_r_credit[i]    +=   i_crdtgrant_rdatacred[i][dec_multi][misc_cnt];
                    w_cnt_rp_b_credit[i]    +=   i_crdtgrant_wrespcred[i][dec_multi][misc_cnt];
                end
            end
        end     
    end
end

//-------------------------------------------------------------
always_comb begin
    for(int unsigned i = 0; i < RP_COUNT; i++) begin
        w_cnt_rp_aw_credit_discount[i] = I_AOU_TX_WREQVALID[i] ? AW_G : 'd0;
        w_cnt_rp_ar_credit_discount[i] = I_AOU_TX_RREQVALID[i] ? AR_G : 'd0;
        w_cnt_rp_b_credit_discount[i]  = I_AOU_TX_WRESPVALID[i]? B_G  : 'd0;
    end
end

always_comb begin
    for(int unsigned i = 0; i < RP_COUNT; i++) begin
        w_cnt_rp_w_credit_discount[i] = 'd0;
        if(I_AOU_TX_WDATAVALID[i]) begin
            if(I_AOU_TX_WDATA_DLENGTH[i]==2'b10) begin
                w_cnt_rp_w_credit_discount[i] = I_AOU_TX_WFDATA[i] ? WF1024b_G : W1024b_G;
            end else if (I_AOU_TX_WDATA_DLENGTH[i]==2'b01) begin
                w_cnt_rp_w_credit_discount[i] = I_AOU_TX_WFDATA[i] ? WF512b_G  : W512b_G;        
            end else if (I_AOU_TX_WDATA_DLENGTH[i]==2'b00) begin
                w_cnt_rp_w_credit_discount[i] = I_AOU_TX_WFDATA[i] ? WF256b_G  : W256b_G;
            end
        end
    end
end

always_comb begin
    for(int unsigned i = 0; i < RP_COUNT; i++) begin
        w_cnt_rp_r_credit_discount[i] = 'd0;
        if(I_AOU_TX_RDATAVALID[i]) begin
            if(I_AOU_TX_RDATA_DLENGTH[i]==2'b10) begin
                w_cnt_rp_r_credit_discount[i] = R1024b_G;
            end else if (I_AOU_TX_RDATA_DLENGTH[i]==2'b01) begin
                w_cnt_rp_r_credit_discount[i] = R512b_G;        
            end else if (I_AOU_TX_RDATA_DLENGTH[i]==2'b00) begin
                w_cnt_rp_r_credit_discount[i] = R256b_G;
            end
        end
    end
end
//-------------------------------------------------------------
always_comb begin
    for(int unsigned i = 0; i < 4 ; i++) begin
        w_aou_tx_wreqvalid_dest_rp[i]         = 'd0;
        w_aou_tx_rreqvalid_dest_rp[i]         = 'd0;
        w_aou_tx_wdatavalid_dest_rp[i]        = 'd0;
        w_aou_tx_rdatavalid_dest_rp[i]        = 'd0;
        w_aou_tx_wrespvalid_dest_rp[i]        = 'd0;

        w_cnt_rp_aw_credit_discount_dest_rp[i]= 'd0;
        w_cnt_rp_ar_credit_discount_dest_rp[i]= 'd0;
        w_cnt_rp_w_credit_discount_dest_rp[i] = 'd0;
        w_cnt_rp_r_credit_discount_dest_rp[i] = 'd0;
        w_cnt_rp_b_credit_discount_dest_rp[i] = 'd0;
    end
    for(int unsigned j = 0 ; j < RP_COUNT ; j++) begin
        w_aou_tx_wreqvalid_dest_rp[I_RP_DEST_RP[j]]         =   I_AOU_TX_WREQVALID[j];
        w_aou_tx_rreqvalid_dest_rp[I_RP_DEST_RP[j]]         =   I_AOU_TX_RREQVALID[j];
        w_aou_tx_wdatavalid_dest_rp[I_RP_DEST_RP[j]]        =   I_AOU_TX_WDATAVALID[j];
        w_aou_tx_rdatavalid_dest_rp[I_RP_DEST_RP[j]]        =   I_AOU_TX_RDATAVALID[j];       
        w_aou_tx_wrespvalid_dest_rp[I_RP_DEST_RP[j]]        =   I_AOU_TX_WRESPVALID[j];

        w_cnt_rp_aw_credit_discount_dest_rp[I_RP_DEST_RP[j]]= w_cnt_rp_aw_credit_discount[j];
        w_cnt_rp_ar_credit_discount_dest_rp[I_RP_DEST_RP[j]]= w_cnt_rp_ar_credit_discount[j];
        w_cnt_rp_w_credit_discount_dest_rp[I_RP_DEST_RP[j]] = w_cnt_rp_w_credit_discount[j];
        w_cnt_rp_r_credit_discount_dest_rp[I_RP_DEST_RP[j]] = w_cnt_rp_r_credit_discount[j];
        w_cnt_rp_b_credit_discount_dest_rp[I_RP_DEST_RP[j]] = w_cnt_rp_b_credit_discount[j];

    end
end
//-------------------------------------------------------------
genvar n;
generate
    for(n=0; n<4; n++) begin : GEN_CREDIT_UPDATE       
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_aw_credit[n].r_cnt_aw_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                   generate_rp_aw_credit[n].r_cnt_aw_credit_rx  <= 'd0;
                end else if (I_CRD_COUNT_EN)begin
                    if( (I_AOU_MSGCRDT_VALID & w_rp_credit_match_one_hot[n]) | (|I_AOU_CRDTGRANT_VALID) | w_aou_tx_wreqvalid_dest_rp[n]) begin
                        if(w_cnt_rp_aw_credit[n] >= RP_AW_MAX_CREDIT[n] - generate_rp_aw_credit[n].r_cnt_aw_credit_rx + w_cnt_rp_aw_credit_discount_dest_rp[n]) begin
                            generate_rp_aw_credit[n].r_cnt_aw_credit_rx <= RP_AW_MAX_CREDIT[n];  
                        end else begin
                            generate_rp_aw_credit[n].r_cnt_aw_credit_rx <= generate_rp_aw_credit[n].r_cnt_aw_credit_rx + w_cnt_rp_aw_credit[n] - w_cnt_rp_aw_credit_discount_dest_rp[n];            
                        end
                    end 
                end
            end
        end

        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_ar_credit[n].r_cnt_ar_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                   generate_rp_ar_credit[n].r_cnt_ar_credit_rx  <= 'd0;
                end else if (I_CRD_COUNT_EN)begin
                    if( (I_AOU_MSGCRDT_VALID & w_rp_credit_match_one_hot[n]) | (|I_AOU_CRDTGRANT_VALID) | w_aou_tx_rreqvalid_dest_rp[n]) begin
                        if(w_cnt_rp_ar_credit[n] >= RP_AR_MAX_CREDIT[n] - generate_rp_ar_credit[n].r_cnt_ar_credit_rx + w_cnt_rp_ar_credit_discount_dest_rp[n]) begin
                            generate_rp_ar_credit[n].r_cnt_ar_credit_rx <= RP_AR_MAX_CREDIT[n];  
                        end else begin
                            generate_rp_ar_credit[n].r_cnt_ar_credit_rx <= generate_rp_ar_credit[n].r_cnt_ar_credit_rx + w_cnt_rp_ar_credit[n] - w_cnt_rp_ar_credit_discount_dest_rp[n];            
                        end
                    end 
                end
            end
        end
        
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_w_credit[n].r_cnt_w_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                   generate_rp_w_credit[n].r_cnt_w_credit_rx  <= 'd0;
                end else if (I_CRD_COUNT_EN)begin
                    if( (I_AOU_MSGCRDT_VALID & w_rp_credit_match_one_hot[n]) | (|I_AOU_CRDTGRANT_VALID) | w_aou_tx_wdatavalid_dest_rp[n]) begin
                        if(w_cnt_rp_w_credit[n] >= RP_W_MAX_CREDIT[n] - generate_rp_w_credit[n].r_cnt_w_credit_rx + w_cnt_rp_w_credit_discount_dest_rp[n]) begin
                            generate_rp_w_credit[n].r_cnt_w_credit_rx <= RP_W_MAX_CREDIT[n];  
                        end else begin
                            generate_rp_w_credit[n].r_cnt_w_credit_rx <= generate_rp_w_credit[n].r_cnt_w_credit_rx + w_cnt_rp_w_credit[n] - w_cnt_rp_w_credit_discount_dest_rp[n];            
                        end
                    end 
                end
            end
        end
        
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_r_credit[n].r_cnt_r_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                   generate_rp_r_credit[n].r_cnt_r_credit_rx  <= 'd0;
                end else if (I_CRD_COUNT_EN)begin
                    if( (I_AOU_MSGCRDT_VALID & w_rp_credit_match_one_hot[n]) | (|I_AOU_CRDTGRANT_VALID) | w_aou_tx_rdatavalid_dest_rp[n]) begin
                        if(w_cnt_rp_r_credit[n] >= RP_R_MAX_CREDIT[n] - generate_rp_r_credit[n].r_cnt_r_credit_rx + w_cnt_rp_r_credit_discount_dest_rp[n]) begin
                            generate_rp_r_credit[n].r_cnt_r_credit_rx <= RP_R_MAX_CREDIT[n];  
                        end else begin
                            generate_rp_r_credit[n].r_cnt_r_credit_rx <= generate_rp_r_credit[n].r_cnt_r_credit_rx + w_cnt_rp_r_credit[n] - w_cnt_rp_r_credit_discount_dest_rp[n];            
                        end
                    end 
                end
            end
        end
        
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_b_credit[n].r_cnt_b_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                   generate_rp_b_credit[n].r_cnt_b_credit_rx  <= 'd0;
                end else if (I_CRD_COUNT_EN)begin
                    if( (I_AOU_MSGCRDT_VALID & w_rp_credit_match_one_hot[n])| (|I_AOU_CRDTGRANT_VALID) | w_aou_tx_wrespvalid_dest_rp[n]) begin
                        if(w_cnt_rp_b_credit[n] >= RP_B_MAX_CREDIT[n] - generate_rp_b_credit[n].r_cnt_b_credit_rx + w_cnt_rp_b_credit_discount_dest_rp[n]) begin
                            generate_rp_b_credit[n].r_cnt_b_credit_rx <= RP_B_MAX_CREDIT[n];  
                        end else begin
                            generate_rp_b_credit[n].r_cnt_b_credit_rx <= generate_rp_b_credit[n].r_cnt_b_credit_rx + w_cnt_rp_b_credit[n] - w_cnt_rp_b_credit_discount_dest_rp[n];            
                        end
                    end 
                end
            end
        end
    end
endgenerate

genvar i;
generate
    for(i = 0; i < RP_COUNT; i++) begin
        always_comb begin
            O_AOU_TX_WREQCRED[i]  = 'd0;
            O_AOU_TX_RREQCRED[i]  = 'd0; 
            O_AOU_TX_WDATACRED[i] = 'd0; 
            O_AOU_TX_RDATACRED[i] = 'd0; 
            O_AOU_TX_WRESPCRED[i] = 'd0;
         
            if(r_tx_req_credited_message_en) begin
                unique case (I_RP_DEST_RP[i])
                2'b00: begin
                    O_AOU_TX_WREQCRED[i][CNT_RP_AW_MAX_CREDIT[i]-1:0]  = generate_rp_aw_credit[0].r_cnt_aw_credit_rx;
                    O_AOU_TX_RREQCRED[i][CNT_RP_AR_MAX_CREDIT[i]-1:0]  = generate_rp_ar_credit[0].r_cnt_ar_credit_rx;
                    O_AOU_TX_WDATACRED[i][CNT_RP_W_MAX_CREDIT[i]-1:0]  = generate_rp_w_credit[0].r_cnt_w_credit_rx  ;
               end
                2'b01: begin
                    O_AOU_TX_WREQCRED[i][CNT_RP_AW_MAX_CREDIT[i]-1:0]  = generate_rp_aw_credit[1].r_cnt_aw_credit_rx;
                    O_AOU_TX_RREQCRED[i][CNT_RP_AR_MAX_CREDIT[i]-1:0]  = generate_rp_ar_credit[1].r_cnt_ar_credit_rx;
                    O_AOU_TX_WDATACRED[i][CNT_RP_W_MAX_CREDIT[i]-1:0]  = generate_rp_w_credit[1].r_cnt_w_credit_rx  ;
               end
                2'b10: begin 
                    O_AOU_TX_WREQCRED[i][CNT_RP_AW_MAX_CREDIT[i]-1:0]  = generate_rp_aw_credit[2].r_cnt_aw_credit_rx;
                    O_AOU_TX_RREQCRED[i][CNT_RP_AR_MAX_CREDIT[i]-1:0]  = generate_rp_ar_credit[2].r_cnt_ar_credit_rx;
                    O_AOU_TX_WDATACRED[i][CNT_RP_W_MAX_CREDIT[i]-1:0]  = generate_rp_w_credit[2].r_cnt_w_credit_rx  ;
               end
                2'b11: begin
                    O_AOU_TX_WREQCRED[i][CNT_RP_AW_MAX_CREDIT[i]-1:0]  = generate_rp_aw_credit[3].r_cnt_aw_credit_rx;
                    O_AOU_TX_RREQCRED[i][CNT_RP_AR_MAX_CREDIT[i]-1:0]  = generate_rp_ar_credit[3].r_cnt_ar_credit_rx;
                    O_AOU_TX_WDATACRED[i][CNT_RP_W_MAX_CREDIT[i]-1:0]  = generate_rp_w_credit[3].r_cnt_w_credit_rx  ;
               end 
                endcase
            end         

            if(r_tx_rsp_credited_message_en) begin
                unique case (I_RP_DEST_RP[i])
                2'b00: begin
                    O_AOU_TX_RDATACRED[i][CNT_RP_R_MAX_CREDIT[i]-1:0]  = generate_rp_r_credit[0].r_cnt_r_credit_rx  ;
                    O_AOU_TX_WRESPCRED[i][CNT_RP_B_MAX_CREDIT[i]-1:0]  = generate_rp_b_credit[0].r_cnt_b_credit_rx  ;
                end
                2'b01: begin
                    O_AOU_TX_RDATACRED[i][CNT_RP_R_MAX_CREDIT[i]-1:0]  = generate_rp_r_credit[1].r_cnt_r_credit_rx  ;
                    O_AOU_TX_WRESPCRED[i][CNT_RP_B_MAX_CREDIT[i]-1:0]  = generate_rp_b_credit[1].r_cnt_b_credit_rx  ;
                end
                2'b10: begin 
                    O_AOU_TX_RDATACRED[i][CNT_RP_R_MAX_CREDIT[i]-1:0]  = generate_rp_r_credit[2].r_cnt_r_credit_rx  ;
                    O_AOU_TX_WRESPCRED[i][CNT_RP_B_MAX_CREDIT[i]-1:0]  = generate_rp_b_credit[2].r_cnt_b_credit_rx  ;
                end
                2'b11: begin
                    O_AOU_TX_RDATACRED[i][CNT_RP_R_MAX_CREDIT[i]-1:0]  = generate_rp_r_credit[3].r_cnt_r_credit_rx  ;
                    O_AOU_TX_WRESPCRED[i][CNT_RP_B_MAX_CREDIT[i]-1:0]  = generate_rp_b_credit[3].r_cnt_b_credit_rx  ;
                end 
                endcase
            end            
        end
    end
endgenerate
endmodule
