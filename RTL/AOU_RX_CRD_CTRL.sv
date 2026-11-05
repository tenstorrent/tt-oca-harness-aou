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
//  Module     : AOU_RX_CRD_CTRL
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_RX_CRD_CTRL
import packet_def_pkg::*;
#(
    parameter RP_COUNT              = 4,

    parameter RP0_AW_MAX_CREDIT     = 256,
    parameter RP0_AR_MAX_CREDIT     = 256,
    parameter RP0_W_MAX_CREDIT      = 256,
    parameter RP0_R_MAX_CREDIT      = 256,
    parameter RP0_B_MAX_CREDIT      = 256,
    parameter RP1_AW_MAX_CREDIT     = 256,
    parameter RP1_AR_MAX_CREDIT     = 256,
    parameter RP1_W_MAX_CREDIT      = 256,
    parameter RP1_R_MAX_CREDIT      = 256,
    parameter RP1_B_MAX_CREDIT      = 256,
    parameter RP2_AW_MAX_CREDIT     = 256,
    parameter RP2_AR_MAX_CREDIT     = 256,
    parameter RP2_W_MAX_CREDIT      = 256,
    parameter RP2_R_MAX_CREDIT      = 256,
    parameter RP2_B_MAX_CREDIT      = 256,
    parameter RP3_AW_MAX_CREDIT     = 256,
    parameter RP3_AR_MAX_CREDIT     = 256,
    parameter RP3_W_MAX_CREDIT      = 256,
    parameter RP3_R_MAX_CREDIT      = 256,
    parameter RP3_B_MAX_CREDIT      = 256,

    localparam CNT_RP0_AW_MAX_CREDIT = $clog2(RP0_AW_MAX_CREDIT+1),
    localparam CNT_RP0_AR_MAX_CREDIT = $clog2(RP0_AR_MAX_CREDIT+1),
    localparam CNT_RP0_W_MAX_CREDIT  = $clog2(RP0_W_MAX_CREDIT +1),
    localparam CNT_RP0_R_MAX_CREDIT  = $clog2(RP0_R_MAX_CREDIT +1),
    localparam CNT_RP0_B_MAX_CREDIT  = $clog2(RP0_B_MAX_CREDIT +1),
    localparam CNT_RP1_AW_MAX_CREDIT = $clog2(RP1_AW_MAX_CREDIT+1),
    localparam CNT_RP1_AR_MAX_CREDIT = $clog2(RP1_AR_MAX_CREDIT+1),
    localparam CNT_RP1_W_MAX_CREDIT  = $clog2(RP1_W_MAX_CREDIT +1),
    localparam CNT_RP1_R_MAX_CREDIT  = $clog2(RP1_R_MAX_CREDIT +1),
    localparam CNT_RP1_B_MAX_CREDIT  = $clog2(RP1_B_MAX_CREDIT +1),
    localparam CNT_RP2_AW_MAX_CREDIT = $clog2(RP2_AW_MAX_CREDIT+1),
    localparam CNT_RP2_AR_MAX_CREDIT = $clog2(RP2_AR_MAX_CREDIT+1),
    localparam CNT_RP2_W_MAX_CREDIT  = $clog2(RP2_W_MAX_CREDIT +1),
    localparam CNT_RP2_R_MAX_CREDIT  = $clog2(RP2_R_MAX_CREDIT +1),
    localparam CNT_RP2_B_MAX_CREDIT  = $clog2(RP2_B_MAX_CREDIT +1),
    localparam CNT_RP3_AW_MAX_CREDIT = $clog2(RP3_AW_MAX_CREDIT+1),
    localparam CNT_RP3_AR_MAX_CREDIT = $clog2(RP3_AR_MAX_CREDIT+1),
    localparam CNT_RP3_W_MAX_CREDIT  = $clog2(RP3_W_MAX_CREDIT +1),
    localparam CNT_RP3_R_MAX_CREDIT  = $clog2(RP3_R_MAX_CREDIT +1),
    localparam CNT_RP3_B_MAX_CREDIT  = $clog2(RP3_B_MAX_CREDIT +1),


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
    input                       I_CLK,
    input                       I_RESETN,

    output       [2:0]          O_AOU_MSGCREDIT_WREQCRED,
    output       [2:0]          O_AOU_MSGCREDIT_RREQCRED,
    output       [2:0]          O_AOU_MSGCREDIT_WDATACRED,
    output       [2:0]          O_AOU_MSGCREDIT_RDATACRED,
    output       [1:0]          O_AOU_MSGCREDIT_WRESPCRED,
    output       [1:0]          O_AOU_MSGCREDIT_RP,
    output                      O_AOU_MSGCREDIT_CRED_VALID,
    input                       I_AOU_MSGCREDIT_CRED_READY,

    output       [1:0]          O_AOU_CRDTGRANT_WRESPCRED3,
    output       [1:0]          O_AOU_CRDTGRANT_WRESPCRED2,
    output       [1:0]          O_AOU_CRDTGRANT_WRESPCRED1,
    output       [1:0]          O_AOU_CRDTGRANT_WRESPCRED0,
    output       [2:0]          O_AOU_CRDTGRANT_RDATACRED3,
    output       [2:0]          O_AOU_CRDTGRANT_RDATACRED2,
    output       [2:0]          O_AOU_CRDTGRANT_RDATACRED1,
    output       [2:0]          O_AOU_CRDTGRANT_RDATACRED0,
    output       [2:0]          O_AOU_CRDTGRANT_WDATACRED3,
    output       [2:0]          O_AOU_CRDTGRANT_WDATACRED2,
    output       [2:0]          O_AOU_CRDTGRANT_WDATACRED1,
    output       [2:0]          O_AOU_CRDTGRANT_WDATACRED0,
    output       [2:0]          O_AOU_CRDTGRANT_RREQCRED3,
    output       [2:0]          O_AOU_CRDTGRANT_RREQCRED2,
    output       [2:0]          O_AOU_CRDTGRANT_RREQCRED1,
    output       [2:0]          O_AOU_CRDTGRANT_RREQCRED0,
    output       [2:0]          O_AOU_CRDTGRANT_WREQCRED3,
    output       [2:0]          O_AOU_CRDTGRANT_WREQCRED2,
    output       [2:0]          O_AOU_CRDTGRANT_WREQCRED1,
    output       [2:0]          O_AOU_CRDTGRANT_WREQCRED0,
    output                      O_AOU_CRDTGRANT_VALID,
    input                       I_AOU_CRDTGRANT_READY,

    input  [RP_COUNT-1:0]       I_AOU_RX_WREQVALID    ,
    input  [RP_COUNT-1:0]       I_AOU_RX_RREQVALID    ,
    input  [RP_COUNT-1:0]       I_AOU_RX_WDATAVALID   ,
    input  [RP_COUNT-1:0][1:0]  I_AOU_RX_WDATA_DLENGTH,
    input  [RP_COUNT-1:0]       I_AOU_RX_WDATAF       ,
    input  [RP_COUNT-1:0]       I_AOU_RX_RDATAVALID   ,
    input  [RP_COUNT-1:0][1:0]  I_AOU_RX_RDATA_DLENGTH,
    input  [RP_COUNT-1:0]       I_AOU_RX_WRESPVALID   ,

    input                       I_REQ_CRD_ADVERTISE_EN,
    input                       I_RSP_CRD_ADVERTISE_EN,

    input                       I_STATUS_DISABLE

);

logic                           r_status_disable_1d;
logic                           w_status_disable_rising_edge_detect;
logic                           r_crd_advertise_en_1d;
logic                           w_crd_advertise_rising_edge_detect;
logic                           r_aou_misc_crdgrant_done;
logic                           r_aou_crdtgrant_hs;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN)begin
         r_status_disable_1d <= 1'b0;
    end else begin
         r_status_disable_1d <= I_STATUS_DISABLE;
    end
end
assign  w_status_disable_rising_edge_detect =   ~r_status_disable_1d & I_STATUS_DISABLE;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN)begin
        r_crd_advertise_en_1d <= 1'b0;
    end else begin
        r_crd_advertise_en_1d <= I_REQ_CRD_ADVERTISE_EN;
    end
end
assign  w_crd_advertise_rising_edge_detect =    ~r_crd_advertise_en_1d & I_REQ_CRD_ADVERTISE_EN;

//For RX_CORE Credit count
for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_aw_credit
    logic [CNT_RP_AW_MAX_CREDIT[a]-1:0] r_cnt_aw_credit_rx;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_ar_credit
    logic [CNT_RP_AR_MAX_CREDIT[a]-1:0] r_cnt_ar_credit_rx;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_w_credit
    logic [CNT_RP_W_MAX_CREDIT[a]-1:0] r_cnt_w_credit_rx;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_r_credit
    logic [CNT_RP_R_MAX_CREDIT[a]-1:0] r_cnt_r_credit_rx;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_b_credit
    logic [CNT_RP_B_MAX_CREDIT[a]-1:0] r_cnt_b_credit_rx;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_aw_credit_next
    logic [CNT_RP_AW_MAX_CREDIT[a]-1:0] w_cnt_aw_credit_rx_next;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_ar_credit_next
    logic [CNT_RP_AR_MAX_CREDIT[a]-1:0] w_cnt_ar_credit_rx_next;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_w_credit_next
    logic [CNT_RP_W_MAX_CREDIT[a]-1:0] w_cnt_w_credit_rx_next;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_r_credit_next
    logic [CNT_RP_R_MAX_CREDIT[a]-1:0] w_cnt_r_credit_rx_next;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_b_credit_next
    logic [CNT_RP_B_MAX_CREDIT[a]-1:0] w_cnt_b_credit_rx_next;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_aw_credit_available
    logic [CNT_RP_AW_MAX_CREDIT[a]-1:0] w_cnt_aw_credit_rx_available;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_ar_credit_available
    logic [CNT_RP_AR_MAX_CREDIT[a]-1:0] w_cnt_ar_credit_rx_available;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_w_credit_available
    logic [CNT_RP_W_MAX_CREDIT[a]-1:0] w_cnt_w_credit_rx_available;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_r_credit_available
    logic [CNT_RP_R_MAX_CREDIT[a]-1:0] w_cnt_r_credit_rx_available;
end

for (genvar a = 0; a <RP_COUNT ; a++) begin : generate_rp_b_credit_available
    logic [CNT_RP_B_MAX_CREDIT[a]-1:0] w_cnt_b_credit_rx_available;
end

logic   [RP_COUNT-1:0] [8:0]          w_cnt_rp_aw_credit_return_rx;
logic   [RP_COUNT-1:0] [8:0]          w_cnt_rp_ar_credit_return_rx;
logic   [RP_COUNT-1:0] [8:0]          w_cnt_rp_w_credit_return_rx;
logic   [RP_COUNT-1:0] [8:0]          w_cnt_rp_r_credit_return_rx;
logic   [RP_COUNT-1:0] [4:0]          w_cnt_rp_b_credit_return_rx;

logic   [RP_COUNT-1:0] [3:0]          o_aou_crdtgrant_wrespcred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_crdtgrant_rdatacred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_crdtgrant_wdatacred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_crdtgrant_rreqcred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_crdtgrant_wreqcred;

logic   [RP_COUNT-1:0] [3:0]          o_aou_msgcrdt_wrespcred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_msgcrdt_rdatacred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_msgcrdt_wdatacred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_msgcrdt_rreqcred;
logic   [RP_COUNT-1:0] [7:0]          o_aou_msgcrdt_wreqcred;

logic   [3:0] [2:0]                   best_index_aw;
logic   [3:0] [2:0]                   best_index_ar;
logic   [3:0] [2:0]                   best_index_w;
logic   [3:0] [2:0]                   best_index_r;
logic   [3:0] [1:0]                   best_index_b;

logic   [3:0]                         w_credit_en;
logic   [3:0]                         w_rp_credit_grant;

logic                                 w_msgcredit_cred_hs;
logic                                 w_crdtgrant_hs;

logic   [2:0]                         w_aou_msgcredit_wreqcred;
logic   [2:0]                         w_aou_msgcredit_rreqcred;
logic   [2:0]                         w_aou_msgcredit_wdatacred;
logic   [2:0]                         w_aou_msgcredit_rdatacred;
logic   [1:0]                         w_aou_msgcredit_wrespcred;
logic   [1:0]                         w_aou_msgcredit_rp;

assign  w_msgcredit_cred_hs     =   O_AOU_MSGCREDIT_CRED_VALID & I_AOU_MSGCREDIT_CRED_READY;
assign  w_crdtgrant_hs          =   O_AOU_CRDTGRANT_VALID & I_AOU_CRDTGRANT_READY;

//-------------------------------------------------------------
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_aou_crdtgrant_hs <= 1'b0;
    end else if (w_crdtgrant_hs) begin
        r_aou_crdtgrant_hs <= 1'b1;
    end else if (r_aou_misc_crdgrant_done)begin
        r_aou_crdtgrant_hs <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
         r_aou_misc_crdgrant_done <= 1'b0;
    end else if (w_status_disable_rising_edge_detect) begin
         r_aou_misc_crdgrant_done <= 1'b0;
    end else if (r_aou_crdtgrant_hs && I_AOU_MSGCREDIT_CRED_READY) begin
         r_aou_misc_crdgrant_done <= 1'b1;
    end
end

//-------------------------------------------------------------
genvar j;
generate
    for(j = 0; j<RP_COUNT ; j=j+1) begin : GEN_BEST_SEL
        always_comb begin
            best_index_aw[j] = 'd0;
            o_aou_msgcrdt_wreqcred[j] = 'd0;
            o_aou_crdtgrant_wreqcred[j]  = 'd0;
            if(I_REQ_CRD_ADVERTISE_EN) begin
                for(int unsigned i = 0; i<8 ; i=i+1) begin
                    if((CREDIT_TABLE[i]) <= {1'b0, generate_rp_aw_credit_available[j].w_cnt_aw_credit_rx_available}) begin
                        best_index_aw[j]            = i;
                        o_aou_msgcrdt_wreqcred[j]   = CREDIT_TABLE[i];
                        o_aou_crdtgrant_wreqcred[j] = CREDIT_TABLE[i];
                    end
                end
            end
        end

        always_comb begin
            best_index_ar[j] = 'd0;
            o_aou_msgcrdt_rreqcred[j] = 'd0;
            o_aou_crdtgrant_rreqcred[j] = 'd0;
            if(I_REQ_CRD_ADVERTISE_EN) begin
                for(int unsigned i = 0; i<8 ; i=i+1) begin
                    if((CREDIT_TABLE[i]) <= {1'b0, generate_rp_ar_credit_available[j].w_cnt_ar_credit_rx_available}) begin
                        best_index_ar[j]            = i;
                        o_aou_msgcrdt_rreqcred[j]   = CREDIT_TABLE[i];
                        o_aou_crdtgrant_rreqcred[j] = CREDIT_TABLE[i];
                    end
                end
            end
        end

        always_comb begin
            best_index_w[j] = 'd0;
            o_aou_msgcrdt_wdatacred[j] = 'd0;
            o_aou_crdtgrant_wdatacred[j] = 'd0;
            if(I_REQ_CRD_ADVERTISE_EN) begin
                for(int unsigned i = 0; i<8 ; i=i+1) begin
                    if({2'b0, (CREDIT_TABLE[i])} <= generate_rp_w_credit_available[j].w_cnt_w_credit_rx_available) begin
                        best_index_w[j] =i;
                        o_aou_msgcrdt_wdatacred[j]= CREDIT_TABLE[i];
                        o_aou_crdtgrant_wdatacred[j] = CREDIT_TABLE[i];
                    end
                end
            end
        end

        always_comb begin
            best_index_r[j] = 'd0;
            o_aou_msgcrdt_rdatacred[j] = 'd0;
            o_aou_crdtgrant_rdatacred[j] = 'd0;
            if(I_RSP_CRD_ADVERTISE_EN) begin
                for(int unsigned i = 0; i<8 ; i=i+1) begin
                    if({2'b0, (CREDIT_TABLE[i])} <= generate_rp_r_credit_available[j].w_cnt_r_credit_rx_available) begin
                        best_index_r[j] =i;
                        o_aou_msgcrdt_rdatacred[j] = CREDIT_TABLE[i];
                        o_aou_crdtgrant_rdatacred[j] = CREDIT_TABLE[i];
                    end
                end
            end
        end

        always_comb begin
            best_index_b[j] = 'd0;
            o_aou_msgcrdt_wrespcred[j] = 'd0;
            o_aou_crdtgrant_wrespcred[j] = 'd0;
            if(I_RSP_CRD_ADVERTISE_EN) begin
                for(int unsigned i = 0; i<4 ; i=i+1) begin
                    if((CREDIT_TABLE[i]) <= generate_rp_b_credit_available[j].w_cnt_b_credit_rx_available) begin
                        best_index_b[j] =i;
                        o_aou_msgcrdt_wrespcred[j]= CREDIT_TABLE[i];
                        o_aou_crdtgrant_wrespcred[j] = CREDIT_TABLE[i];
                    end
                end
            end
        end
    end

   if (RP_COUNT < 4) begin : GEN_UNUSED_ZERO
        for (genvar k = RP_COUNT; k < 4; k++) begin
            assign best_index_aw[k] = '0;
            assign best_index_ar[k] = '0;
            assign best_index_w[k]  = '0;
            assign best_index_r[k]  = '0;
            assign best_index_b[k]  = '0;
        end
    end

endgenerate

//-------------------------------------------------------------
always_comb begin
    for(int unsigned i = 0; i < RP_COUNT; i= i+1) begin
        w_cnt_rp_aw_credit_return_rx[i] = I_AOU_RX_WREQVALID[i] ? AW_G : 'd0;
        w_cnt_rp_ar_credit_return_rx[i] = I_AOU_RX_RREQVALID[i] ? AR_G : 'd0;

        w_cnt_rp_w_credit_return_rx[i] = 'd0;
        if(I_AOU_RX_WDATAVALID[i]) begin
            if(I_AOU_RX_WDATA_DLENGTH[i]==2'b10) begin
                w_cnt_rp_w_credit_return_rx[i] = I_AOU_RX_WDATAF[i] ? WF1024b_G : W1024b_G;
            end else if (I_AOU_RX_WDATA_DLENGTH[i]==2'b01) begin
                w_cnt_rp_w_credit_return_rx[i] = I_AOU_RX_WDATAF[i] ? WF512b_G  : W512b_G;
            end else if (I_AOU_RX_WDATA_DLENGTH[i]==2'b00) begin
                w_cnt_rp_w_credit_return_rx[i] = I_AOU_RX_WDATAF[i] ? WF256b_G  : W256b_G;
            end
        end

        w_cnt_rp_r_credit_return_rx[i]  = 'd0;
        if(I_AOU_RX_RDATAVALID[i]) begin
            if(I_AOU_RX_RDATA_DLENGTH[i]==2'b10) begin
                w_cnt_rp_r_credit_return_rx[i] = R1024b_G;
            end else if (I_AOU_RX_RDATA_DLENGTH[i]==2'b01) begin
                w_cnt_rp_r_credit_return_rx[i] = R512b_G;
            end else if (I_AOU_RX_RDATA_DLENGTH[i]==2'b00) begin
                w_cnt_rp_r_credit_return_rx[i] = R256b_G;
            end
        end

        w_cnt_rp_b_credit_return_rx[i]  = I_AOU_RX_WRESPVALID[i] ? B_G : 'd0;
    end
end

//-------------------------------------------------------------
genvar b;
generate
    for(b=0; b<RP_COUNT; b++) begin : GEN_CREDIT_NEXT_UPDATE
        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_aw_credit[b].r_cnt_aw_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                    generate_rp_aw_credit[b].r_cnt_aw_credit_rx <= 'd0;
                end else if (~I_STATUS_DISABLE)begin
                    if( (w_msgcredit_cred_hs & (w_aou_msgcredit_rp==b[1:0])) | w_crdtgrant_hs | I_AOU_RX_WREQVALID[b]) begin
                        generate_rp_aw_credit[b].r_cnt_aw_credit_rx <= generate_rp_aw_credit_next[b].w_cnt_aw_credit_rx_next;
                    end
                end
            end
        end

        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_ar_credit[b].r_cnt_ar_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                    generate_rp_ar_credit[b].r_cnt_ar_credit_rx <= 'd0;
                end else if (~I_STATUS_DISABLE)begin
                    if( (w_msgcredit_cred_hs & (w_aou_msgcredit_rp==b[1:0])) | w_crdtgrant_hs | I_AOU_RX_RREQVALID[b]) begin
                        generate_rp_ar_credit[b].r_cnt_ar_credit_rx <= generate_rp_ar_credit_next[b].w_cnt_ar_credit_rx_next;
                    end
                end
            end
        end

        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_w_credit[b].r_cnt_w_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                    generate_rp_w_credit[b].r_cnt_w_credit_rx <= 'd0;
                end else if (~I_STATUS_DISABLE)begin
                    if( (w_msgcredit_cred_hs & (w_aou_msgcredit_rp==b[1:0])) | w_crdtgrant_hs | I_AOU_RX_WDATAVALID[b]) begin
                        generate_rp_w_credit[b].r_cnt_w_credit_rx <= generate_rp_w_credit_next[b].w_cnt_w_credit_rx_next;
                    end
                end
            end
        end

        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_r_credit[b].r_cnt_r_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                    generate_rp_r_credit[b].r_cnt_r_credit_rx <= 'd0;
                end else if (~I_STATUS_DISABLE)begin
                    if( (w_msgcredit_cred_hs & (w_aou_msgcredit_rp==b[1:0])) | w_crdtgrant_hs | I_AOU_RX_RDATAVALID[b]) begin
                        generate_rp_r_credit[b].r_cnt_r_credit_rx <= generate_rp_r_credit_next[b].w_cnt_r_credit_rx_next;
                    end
                end
            end
        end


        always_ff @ (posedge I_CLK or negedge I_RESETN) begin
            if(~I_RESETN) begin
                generate_rp_b_credit[b].r_cnt_b_credit_rx <= 'd0;
            end else begin
                if(w_status_disable_rising_edge_detect) begin
                    generate_rp_b_credit[b].r_cnt_b_credit_rx <= 'd0;
                end else if (~I_STATUS_DISABLE)begin
                    if( (w_msgcredit_cred_hs & (w_aou_msgcredit_rp==b[1:0])) | w_crdtgrant_hs | I_AOU_RX_WRESPVALID[b]) begin
                        generate_rp_b_credit[b].r_cnt_b_credit_rx <= generate_rp_b_credit_next[b].w_cnt_b_credit_rx_next;
                    end
                end
            end
        end

    end
endgenerate


//-------------------------------------------------------------
genvar i;
generate
    for(i = 0; i < RP_COUNT ; i=i+1) begin : GEN_CREDIT_NEX_CAL
        always_comb begin
            generate_rp_aw_credit_next[i].w_cnt_aw_credit_rx_next =  generate_rp_aw_credit[i].r_cnt_aw_credit_rx - w_cnt_rp_aw_credit_return_rx[i];
            if(w_msgcredit_cred_hs & (w_aou_msgcredit_rp==i[1:0]) & r_aou_misc_crdgrant_done) generate_rp_aw_credit_next[i].w_cnt_aw_credit_rx_next = CNT_RP_AW_MAX_CREDIT[i]'(generate_rp_aw_credit_next[i].w_cnt_aw_credit_rx_next + o_aou_msgcrdt_wreqcred[i]);
            if(w_crdtgrant_hs)     generate_rp_aw_credit_next[i].w_cnt_aw_credit_rx_next  = CNT_RP_AW_MAX_CREDIT[i]'(generate_rp_aw_credit_next[i].w_cnt_aw_credit_rx_next + o_aou_crdtgrant_wreqcred[i]);
        end

        always_comb begin
            generate_rp_ar_credit_next[i].w_cnt_ar_credit_rx_next =  generate_rp_ar_credit[i].r_cnt_ar_credit_rx - w_cnt_rp_ar_credit_return_rx[i];
            if(w_msgcredit_cred_hs & (w_aou_msgcredit_rp==i[1:0]) & r_aou_misc_crdgrant_done) generate_rp_ar_credit_next[i].w_cnt_ar_credit_rx_next = CNT_RP_AR_MAX_CREDIT[i]'(generate_rp_ar_credit_next[i].w_cnt_ar_credit_rx_next + o_aou_msgcrdt_rreqcred[i]);
            if(w_crdtgrant_hs)     generate_rp_ar_credit_next[i].w_cnt_ar_credit_rx_next  = CNT_RP_AR_MAX_CREDIT[i]'(generate_rp_ar_credit_next[i].w_cnt_ar_credit_rx_next + o_aou_crdtgrant_rreqcred[i]);
        end

        always_comb begin
            generate_rp_w_credit_next[i].w_cnt_w_credit_rx_next =  generate_rp_w_credit[i].r_cnt_w_credit_rx - w_cnt_rp_w_credit_return_rx[i];
            if(w_msgcredit_cred_hs & (w_aou_msgcredit_rp==i[1:0]) & r_aou_misc_crdgrant_done) generate_rp_w_credit_next[i].w_cnt_w_credit_rx_next = CNT_RP_W_MAX_CREDIT[i]'(generate_rp_w_credit_next[i].w_cnt_w_credit_rx_next + o_aou_msgcrdt_wdatacred[i]);
            if(w_crdtgrant_hs)     generate_rp_w_credit_next[i].w_cnt_w_credit_rx_next  = CNT_RP_W_MAX_CREDIT[i]'(generate_rp_w_credit_next[i].w_cnt_w_credit_rx_next + o_aou_crdtgrant_wdatacred[i]);
        end

        always_comb begin
            generate_rp_r_credit_next[i].w_cnt_r_credit_rx_next =  generate_rp_r_credit[i].r_cnt_r_credit_rx - w_cnt_rp_r_credit_return_rx[i];
            if(w_msgcredit_cred_hs & (w_aou_msgcredit_rp==i[1:0]) & r_aou_misc_crdgrant_done) generate_rp_r_credit_next[i].w_cnt_r_credit_rx_next = CNT_RP_R_MAX_CREDIT[i]'(generate_rp_r_credit_next[i].w_cnt_r_credit_rx_next + o_aou_msgcrdt_rdatacred[i]);
            if(w_crdtgrant_hs)     generate_rp_r_credit_next[i].w_cnt_r_credit_rx_next  = CNT_RP_R_MAX_CREDIT[i]'(generate_rp_r_credit_next[i].w_cnt_r_credit_rx_next + o_aou_crdtgrant_rdatacred[i]);
        end

        always_comb begin
            generate_rp_b_credit_next[i].w_cnt_b_credit_rx_next =  generate_rp_b_credit[i].r_cnt_b_credit_rx - w_cnt_rp_b_credit_return_rx[i];
            if(w_msgcredit_cred_hs & (w_aou_msgcredit_rp==i[1:0]) & r_aou_misc_crdgrant_done) generate_rp_b_credit_next[i].w_cnt_b_credit_rx_next = CNT_RP_B_MAX_CREDIT[i]'(generate_rp_b_credit_next[i].w_cnt_b_credit_rx_next + o_aou_msgcrdt_wrespcred[i][3:0]);
            if(w_crdtgrant_hs)     generate_rp_b_credit_next[i].w_cnt_b_credit_rx_next  = CNT_RP_B_MAX_CREDIT[i]'(generate_rp_b_credit_next[i].w_cnt_b_credit_rx_next + o_aou_crdtgrant_wrespcred[i]);
        end
    end
endgenerate
//-------------------------------------------------------------
genvar l;
generate
    for(l = 0; l < RP_COUNT ; l = l+1) begin : GEN_CREDIT_AVAILABLE
        always_comb begin
            generate_rp_aw_credit_available[l].w_cnt_aw_credit_rx_available = CNT_RP_AW_MAX_CREDIT[l]'(RP_AW_MAX_CREDIT[l] - (generate_rp_aw_credit[l].r_cnt_aw_credit_rx - w_cnt_rp_aw_credit_return_rx[l]));
            generate_rp_ar_credit_available[l].w_cnt_ar_credit_rx_available = CNT_RP_AR_MAX_CREDIT[l]'(RP_AR_MAX_CREDIT[l] - (generate_rp_ar_credit[l].r_cnt_ar_credit_rx - w_cnt_rp_ar_credit_return_rx[l]));
            generate_rp_w_credit_available[l].w_cnt_w_credit_rx_available = CNT_RP_W_MAX_CREDIT[l]'(RP_W_MAX_CREDIT[l] - (generate_rp_w_credit[l].r_cnt_w_credit_rx - w_cnt_rp_w_credit_return_rx[l]));
            generate_rp_r_credit_available[l].w_cnt_r_credit_rx_available = CNT_RP_R_MAX_CREDIT[l]'(RP_R_MAX_CREDIT[l] - (generate_rp_r_credit[l].r_cnt_r_credit_rx - w_cnt_rp_r_credit_return_rx[l]));
            generate_rp_b_credit_available[l].w_cnt_b_credit_rx_available = CNT_RP_B_MAX_CREDIT[l]'(RP_B_MAX_CREDIT[l] - (generate_rp_b_credit[l].r_cnt_b_credit_rx - w_cnt_rp_b_credit_return_rx[l]));
        end
    end
endgenerate

//-------------------------------------------------------------
always_comb begin
    for(int unsigned i = 0; i < RP_COUNT ; i=i+1) begin
        w_credit_en[i] = (|(best_index_aw[i])) | (|(best_index_ar[i])) | (|(best_index_w[i])) | (|(best_index_r[i])) | (|(best_index_b[i]));
    end
    for(int unsigned i = RP_COUNT; i < 4 ; i=i+1) begin
        w_credit_en[i] = 'd0;
    end
end

AOU_4X1_ARBITER u_aou_msgcredit_rp_4x1_arbiter (
    .I_CLK                              ( I_CLK  ),
    .I_RESETN                           ( I_RESETN  ),

    .I_REQ                              ( {w_credit_en[3], w_credit_en[2], w_credit_en[1], w_credit_en[0]} ),
    .I_ARB_EN                           ( r_aou_misc_crdgrant_done & O_AOU_MSGCREDIT_CRED_VALID & I_AOU_MSGCREDIT_CRED_READY),

    .O_GRANTED_AGENT                    ( {w_rp_credit_grant[3], w_rp_credit_grant[2], w_rp_credit_grant[1], w_rp_credit_grant[0]} )
);

always_comb begin
    case(w_rp_credit_grant)
        4'b0001:begin
            w_aou_msgcredit_wreqcred    =  r_aou_misc_crdgrant_done ? best_index_aw[0]  : 3'b000;
            w_aou_msgcredit_rreqcred    =  r_aou_misc_crdgrant_done ? best_index_ar[0]  : 3'b000;
            w_aou_msgcredit_wdatacred   =  r_aou_misc_crdgrant_done ? best_index_w[0]   : 3'b000;
            w_aou_msgcredit_rdatacred   =  r_aou_misc_crdgrant_done ? best_index_r[0]   : 3'b000;
            w_aou_msgcredit_wrespcred   =  r_aou_misc_crdgrant_done ? best_index_b[0]   : 2'b00;
            w_aou_msgcredit_rp          =  2'b00;
        end
        4'b0010:begin
            w_aou_msgcredit_wreqcred    =  r_aou_misc_crdgrant_done ? best_index_aw[1]  : 3'b000;
            w_aou_msgcredit_rreqcred    =  r_aou_misc_crdgrant_done ? best_index_ar[1]  : 3'b000;
            w_aou_msgcredit_wdatacred   =  r_aou_misc_crdgrant_done ? best_index_w[1]   : 3'b000;
            w_aou_msgcredit_rdatacred   =  r_aou_misc_crdgrant_done ? best_index_r[1]   : 3'b000;
            w_aou_msgcredit_wrespcred   =  r_aou_misc_crdgrant_done ? best_index_b[1]   : 2'b00;
            w_aou_msgcredit_rp          =  2'b01;
        end
        4'b0100:begin
            w_aou_msgcredit_wreqcred    =  r_aou_misc_crdgrant_done ? best_index_aw[2]  : 3'b000;
            w_aou_msgcredit_rreqcred    =  r_aou_misc_crdgrant_done ? best_index_ar[2]  : 3'b000;
            w_aou_msgcredit_wdatacred   =  r_aou_misc_crdgrant_done ? best_index_w[2]   : 3'b000;
            w_aou_msgcredit_rdatacred   =  r_aou_misc_crdgrant_done ? best_index_r[2]   : 3'b000;
            w_aou_msgcredit_wrespcred   =  r_aou_misc_crdgrant_done ? best_index_b[2]   : 2'b00;
            w_aou_msgcredit_rp          =  2'b10;
        end
        4'b1000:begin
            w_aou_msgcredit_wreqcred    =  r_aou_misc_crdgrant_done ? best_index_aw[3]  : 3'b000;
            w_aou_msgcredit_rreqcred    =  r_aou_misc_crdgrant_done ? best_index_ar[3]  : 3'b000;
            w_aou_msgcredit_wdatacred   =  r_aou_misc_crdgrant_done ? best_index_w[3]   : 3'b000;
            w_aou_msgcredit_rdatacred   =  r_aou_misc_crdgrant_done ? best_index_r[3]   : 3'b000;
            w_aou_msgcredit_wrespcred   =  r_aou_misc_crdgrant_done ? best_index_b[3]   : 2'b00;
            w_aou_msgcredit_rp          =  2'b11;
        end
        default: begin
            w_aou_msgcredit_wreqcred    =  3'b000;
            w_aou_msgcredit_rreqcred    =  3'b000;
            w_aou_msgcredit_wdatacred   =  3'b000;
            w_aou_msgcredit_rdatacred   =  3'b000;
            w_aou_msgcredit_wrespcred   =  2'b00;
            w_aou_msgcredit_rp          =  2'b00;
        end
    endcase
end

assign  O_AOU_MSGCREDIT_WREQCRED    = w_aou_msgcredit_wreqcred   ;
assign  O_AOU_MSGCREDIT_RREQCRED    = w_aou_msgcredit_rreqcred   ;
assign  O_AOU_MSGCREDIT_WDATACRED   = w_aou_msgcredit_wdatacred  ;
assign  O_AOU_MSGCREDIT_RDATACRED   = w_aou_msgcredit_rdatacred  ;
assign  O_AOU_MSGCREDIT_WRESPCRED   = w_aou_msgcredit_wrespcred  ;
// A MsgCredit header that advertises no credit names RP0. Without this gate the RP field
// follows the arbiter's parked grant (RP3 out of reset), which an RP_COUNT < 4 build does
// not implement.
assign  O_AOU_MSGCREDIT_RP          = (|{w_aou_msgcredit_wreqcred, w_aou_msgcredit_rreqcred,
                                         w_aou_msgcredit_wdatacred, w_aou_msgcredit_rdatacred,
                                         w_aou_msgcredit_wrespcred}) ? w_aou_msgcredit_rp : 2'b00;
assign  O_AOU_MSGCREDIT_CRED_VALID  = ~I_STATUS_DISABLE;
//-------------------------------------------------------------

assign  O_AOU_CRDTGRANT_WRESPCRED3  = w_crd_advertise_rising_edge_detect ? best_index_b[3]  : 2'b00;
assign  O_AOU_CRDTGRANT_RDATACRED3  = w_crd_advertise_rising_edge_detect ? best_index_r[3]  : 3'b000;
assign  O_AOU_CRDTGRANT_WDATACRED3  = w_crd_advertise_rising_edge_detect ? best_index_w[3]  : 3'b000;
assign  O_AOU_CRDTGRANT_RREQCRED3   = w_crd_advertise_rising_edge_detect ? best_index_ar[3] : 3'b000;
assign  O_AOU_CRDTGRANT_WREQCRED3   = w_crd_advertise_rising_edge_detect ? best_index_aw[3] : 3'b000;

assign  O_AOU_CRDTGRANT_WRESPCRED2  = w_crd_advertise_rising_edge_detect ? best_index_b[2]  : 2'b00;
assign  O_AOU_CRDTGRANT_RDATACRED2  = w_crd_advertise_rising_edge_detect ? best_index_r[2]  : 3'b000;
assign  O_AOU_CRDTGRANT_WDATACRED2  = w_crd_advertise_rising_edge_detect ? best_index_w[2]  : 3'b000;
assign  O_AOU_CRDTGRANT_RREQCRED2   = w_crd_advertise_rising_edge_detect ? best_index_ar[2] : 3'b000;
assign  O_AOU_CRDTGRANT_WREQCRED2   = w_crd_advertise_rising_edge_detect ? best_index_aw[2] : 3'b000;

assign  O_AOU_CRDTGRANT_WRESPCRED1  = w_crd_advertise_rising_edge_detect ? best_index_b[1]  : 2'b00;
assign  O_AOU_CRDTGRANT_RDATACRED1  = w_crd_advertise_rising_edge_detect ? best_index_r[1]  : 3'b000;
assign  O_AOU_CRDTGRANT_WDATACRED1  = w_crd_advertise_rising_edge_detect ? best_index_w[1]  : 3'b000;
assign  O_AOU_CRDTGRANT_RREQCRED1   = w_crd_advertise_rising_edge_detect ? best_index_ar[1] : 3'b000;
assign  O_AOU_CRDTGRANT_WREQCRED1   = w_crd_advertise_rising_edge_detect ? best_index_aw[1] : 3'b000;

assign  O_AOU_CRDTGRANT_WRESPCRED0  = w_crd_advertise_rising_edge_detect ? best_index_b[0]  : 2'b00;
assign  O_AOU_CRDTGRANT_RDATACRED0  = w_crd_advertise_rising_edge_detect ? best_index_r[0]  : 3'b000;
assign  O_AOU_CRDTGRANT_WDATACRED0  = w_crd_advertise_rising_edge_detect ? best_index_w[0]  : 3'b000;
assign  O_AOU_CRDTGRANT_RREQCRED0   = w_crd_advertise_rising_edge_detect ? best_index_ar[0] : 3'b000;
assign  O_AOU_CRDTGRANT_WREQCRED0   = w_crd_advertise_rising_edge_detect ? best_index_aw[0] : 3'b000;

assign  O_AOU_CRDTGRANT_VALID       = w_crd_advertise_rising_edge_detect;

endmodule
