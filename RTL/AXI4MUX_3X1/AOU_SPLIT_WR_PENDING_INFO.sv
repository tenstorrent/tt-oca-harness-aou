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
//  Module     : AOU_SPLIT_WR_PENDING_INFO
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_SPLIT_WR_PENDING_INFO #(
    parameter  AXI_ADDR_WD  = 32,
    parameter  AXI_ID_WD    = 4,
    parameter  AXI_LEN_WD   = 8,

    parameter  WR_MO_CNT    = 32,
    localparam WR_MO_IDX_WD = $clog2(WR_MO_CNT),
    localparam WR_MO_CNT_WD = $clog2(WR_MO_CNT+1)

)
(
    input                           I_CLK,
    input                           I_RESETN,

    // CH0 Slave I/F
    input    [1:0]                  I_AXI_MuxId,
    input    [AXI_ID_WD-1:0]        I_AXI_AwId,
    input    [AXI_ADDR_WD-1:0]      I_AXI_AwAddr,
    input    [AXI_LEN_WD-1:0]       I_AXI_AwLen,
    input                           I_AXI_AwValid,
    input                           I_AXI_AwReady,
    output                          O_AW_Slot_Available_Flag,

    // Master I/F
    input    [AXI_ID_WD+1:0]        I_AXI_BId,
    input    [15:0]                 I_AXI_BUser,
    input                           I_AXI_BValid,
    input                           I_AXI_BReady,

    output   [AXI_ADDR_WD-1:0]      O_CUR_AWADDR,
    output                          O_ReorderBuf_MValid,
    output   [AXI_ID_WD+3:0]        O_ReorderBuf_MData,
    output   [15:0]                 O_ReorderBuf_MUser,

    output                          O_DEST_TABLE_ID_ERR

);

typedef struct  packed {
    logic [AXI_ID_WD-1:0]           id;
    logic [AXI_LEN_WD-1:0]          burst_len;
    logic                           pending;
    logic [WR_MO_IDX_WD-1:0]        wid_numbering;

    logic [1:0]                     bresp;
    // BUSER of the first sub-burst's B. The Bs of all sub-bursts of a split write
    // become one response, and AXI defines no rule for USER in that case; the one
    // response carries this value, which becomes the FLEX field of the WriteResp
    // (AoU v0.8 Basic Profile: FLEX = USER[15:0]).
    logic [15:0]                    buser;
    logic                           buser_vld;
    logic [AXI_ADDR_WD-1:0]         awaddr;
    logic [1:0]                     muxid;
} st_awtable;

st_awtable [WR_MO_CNT-1:0]          awtable;

logic [WR_MO_CNT-1:0]               w_awtable_r_onehot;     // not one hot (multi-hot), but work same as one hot
logic [WR_MO_IDX_WD-1:0]            w_awtable_wptr_cur, w_awtable_rptr_cur;

logic [WR_MO_CNT_WD-1:0]            r_awcnt, w_awcnt_next;

logic [WR_MO_CNT-1:0]               w_wid_numbering_onehot;
logic [WR_MO_IDX_WD-1:0]            w_wid_numbering;

//////////////////////////////////////////////////////////////////////////////////////////
assign O_AW_Slot_Available_Flag = (r_awcnt != WR_MO_CNT);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_awcnt <= 'd0;
    end else if ((I_AXI_AwValid & I_AXI_AwReady) | (I_AXI_BValid & I_AXI_BReady & ~(|awtable[w_awtable_rptr_cur].burst_len))) begin
        r_awcnt <= w_awcnt_next;
    end
end

always_comb begin
    w_awcnt_next = r_awcnt;

    if (I_AXI_AwValid & I_AXI_AwReady) begin
        w_awcnt_next = w_awcnt_next + 'd1;
    end

    if (I_AXI_BValid & I_AXI_BReady & ~(|awtable[w_awtable_rptr_cur].burst_len)) begin
        w_awcnt_next = w_awcnt_next - 'd1;
    end
end

/////////////////////////////////// WID numbering ///////////////////////////////////////////////
always_comb begin
    for (int i=0; i<WR_MO_CNT; i++)
        w_wid_numbering_onehot[i] = awtable[i].pending && (awtable[i].id == I_AXI_AwId);

    w_wid_numbering = $countones(w_wid_numbering_onehot);
end
///////////////////////////////////////////////////////////////////////////////////////

/////////////////////////////////// AW ////////////////////////////////////////////

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        for (integer i=0; i<WR_MO_CNT; i=i+1) begin
            awtable[i].id                <= 'd0;
            awtable[i].burst_len         <= 'd0;
            awtable[i].pending           <= 'd0;
            awtable[i].wid_numbering     <= 'd0;

            awtable[i].bresp             <= 'd0;
            awtable[i].buser             <= 'd0;
            awtable[i].buser_vld         <= 'd0;
            awtable[i].muxid             <= 'd0;
            awtable[i].awaddr            <= 'd0;
        end
    end else begin
        if (I_AXI_AwValid & I_AXI_AwReady) begin
            if (I_AXI_BValid & I_AXI_BReady & (I_AXI_AwId == I_AXI_BId[AXI_ID_WD-1:0]) & (awtable[w_awtable_rptr_cur].burst_len == 'd0)) begin
                awtable[w_awtable_wptr_cur].id            <= I_AXI_AwId;
                awtable[w_awtable_wptr_cur].burst_len     <= I_AXI_AwLen;
                awtable[w_awtable_wptr_cur].pending       <= 1'd1;
                awtable[w_awtable_wptr_cur].wid_numbering <= w_wid_numbering - 1;

                awtable[w_awtable_wptr_cur].bresp         <= 'd0;
                awtable[w_awtable_wptr_cur].buser         <= 'd0;
                awtable[w_awtable_wptr_cur].buser_vld     <= 'd0;
                awtable[w_awtable_wptr_cur].muxid         <= I_AXI_MuxId;
                awtable[w_awtable_wptr_cur].awaddr        <= I_AXI_AwAddr;

            end else begin
                awtable[w_awtable_wptr_cur].id            <= I_AXI_AwId;
                awtable[w_awtable_wptr_cur].burst_len     <= I_AXI_AwLen;
                awtable[w_awtable_wptr_cur].pending       <= 1'd1;
                awtable[w_awtable_wptr_cur].wid_numbering <= w_wid_numbering;

                awtable[w_awtable_wptr_cur].bresp         <= 'd0;
                awtable[w_awtable_wptr_cur].buser         <= 'd0;
                awtable[w_awtable_wptr_cur].buser_vld     <= 'd0;
                awtable[w_awtable_wptr_cur].muxid         <= I_AXI_MuxId;
                awtable[w_awtable_wptr_cur].awaddr        <= I_AXI_AwAddr;
            end
        end

        if (I_AXI_BValid & I_AXI_BReady) begin
            awtable[w_awtable_rptr_cur].bresp         <= awtable[w_awtable_rptr_cur].bresp | I_AXI_BId[AXI_ID_WD + 1:AXI_ID_WD];
            if (~awtable[w_awtable_rptr_cur].buser_vld) begin
                awtable[w_awtable_rptr_cur].buser     <= I_AXI_BUser;
                awtable[w_awtable_rptr_cur].buser_vld <= 1'b1;
            end
            if (|awtable[w_awtable_rptr_cur].burst_len)
                awtable[w_awtable_rptr_cur].burst_len <= awtable[w_awtable_rptr_cur].burst_len - 'd1;
            else
                awtable[w_awtable_rptr_cur].pending <= 1'b0;
        end

        for (integer i=0; i<WR_MO_CNT; i=i+1) begin
            if (I_AXI_BValid & I_AXI_BReady & (awtable[w_awtable_rptr_cur].burst_len == 'd0) & awtable[i].pending & (awtable[i].id == I_AXI_BId[AXI_ID_WD-1:0]) & (awtable[i].wid_numbering != 'd0)) begin
                awtable[i].wid_numbering <= awtable[i].wid_numbering -'d1;
            end
        end
    end
end

always_comb begin
    w_awtable_wptr_cur = 'd0;
    for (integer i=0; i<WR_MO_CNT; i=i+1) begin
        if (!awtable[WR_MO_CNT-1 - i].pending) begin // search from back
            w_awtable_wptr_cur = WR_MO_CNT-1 - i;
        end
    end
end

always_comb begin
    w_awtable_rptr_cur = 'd0;
    for (integer i=0; i<WR_MO_CNT; i=i+1) begin
        w_awtable_r_onehot[i] = awtable[i].pending & (awtable[i].id == I_AXI_BId[AXI_ID_WD-1:0]) & (awtable[i].wid_numbering == 'd0);
    end

    for (integer i=0; i<WR_MO_CNT; i=i+1) begin
        if (w_awtable_r_onehot[i]) begin
            w_awtable_rptr_cur = i;
        end
    end
end

///////////////////////////////////////////////////////////////////////////////////
assign O_ReorderBuf_MData  = {(awtable[w_awtable_rptr_cur].bresp | I_AXI_BId[AXI_ID_WD + 1:AXI_ID_WD]), awtable[w_awtable_rptr_cur].id, awtable[w_awtable_rptr_cur].muxid};
assign O_ReorderBuf_MValid = I_AXI_BValid & (awtable[w_awtable_rptr_cur].burst_len == 'd0);
// A write that was not split answers with its only B in the cycle it arrives,
// before the table has captured it: take the live BUSER then (the same shape as
// the bresp OR above).
assign O_ReorderBuf_MUser  = awtable[w_awtable_rptr_cur].buser_vld ? awtable[w_awtable_rptr_cur].buser : I_AXI_BUser;
//------------------------------------------------------------------
assign O_DEST_TABLE_ID_ERR = I_AXI_BValid & I_AXI_BReady & ~(|w_awtable_r_onehot);

assign O_CUR_AWADDR  = awtable[w_awtable_rptr_cur].awaddr;

`ifdef ASSERTION_ON
// synopsys translate_off

aou_split_wr_pending_info_table_id_err_assertion:
    assert
        property (
            @(posedge I_CLK) disable iff (!I_RESETN)
            !O_DEST_TABLE_ID_ERR 
        )
        else begin
            $error("\n[%t] AOU_SPLIT_WR_PENDING_INFO: O_DEST_TABLE_ID_ERR asserted!", $time);
            $finish;
        end

// synopsys translate_on
`endif

endmodule
