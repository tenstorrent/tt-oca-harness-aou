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
//  Module     : AOU_AXI_DOWN_RDATA_ORDER
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AXI_DOWN_RDATA_ORDER #(
    parameter  AXI_ID_WD        = 4,
    parameter  O_DATA_WD        = 512,
    parameter  I_DATA_WD        = 1024,

    parameter  RD_MO_CNT         = 32,
    localparam RD_MO_IDX_WD      = $clog2(RD_MO_CNT),
    localparam RD_MO_CNT_WD      = $clog2(RD_MO_CNT+1)
)
(
    input  logic                                I_CLK,
    input  logic                                I_RESETN,

    input  logic  [AXI_ID_WD-1:0]               I_AXI_ArId,
    input  logic                                I_AXI_ArValid,
    input  logic                                I_AXI_ArReady,

    input  logic  [AXI_ID_WD-1:0]               I_AXI_RId,
    input  logic                                I_AXI_RLast,
    input  logic     [1:0]                      I_AXI_RResp,
    input  logic     [15:0]                     I_AXI_RUser,
    input  logic     [O_DATA_WD-1:0]            I_AXI_RData,
    input  logic                                I_AXI_RValid,
    input  logic                                I_AXI_RReady,
    output logic                                O_AR_Slot_Available_Flag,

    output logic                                O_ReorderBuf_MValid,
    output logic     [I_DATA_WD-1:0]            O_ReorderBuf_MData,
    output logic     [1:0]                      O_ReorderBuf_MResp,
    output logic     [15:0]                     O_ReorderBuf_MUser,
    output logic                                O_RReadyNonBlocking,
    output logic     [AXI_ID_WD-1:0]            O_ReorderBuf_MId,

    output logic                                O_DEST_TABLE_ID_ERR
);

localparam UP_N          = I_DATA_WD/O_DATA_WD;
localparam UP_WD         = $clog2(UP_N);

typedef struct  packed {
    logic [AXI_ID_WD-1:0]           id;
    logic [UP_WD-1:0]               burst_cnt;
    logic [((UP_N-1)*O_DATA_WD)-1:0]rdata;
    logic [1:0]                     rresp;
    // RUSER of the transaction's first R beat. Several narrow beats become one
    // wide beat here, and AXI defines no rule for USER under width conversion;
    // every merged beat of the transaction carries this value, which becomes the
    // FLEX field of its ReadData (AoU v0.8 Basic Profile: FLEX = USER[15:0]).
    logic [15:0]                    ruser;
    logic                           ruser_vld;

    logic                           pending;
    logic [RD_MO_IDX_WD-1:0]        rid_numbering;
} st_artable;

st_artable [RD_MO_CNT-1:0] artable;

logic [((UP_N-1)*O_DATA_WD)-1:0]   nxt_rdata;
logic [RD_MO_CNT-1:0]              w_artable_r_onehot;
logic [RD_MO_IDX_WD-1:0]           w_artable_wptr_cur, w_artable_rptr_cur;

logic [RD_MO_CNT_WD-1:0]           r_arcnt, w_arcnt_next;

logic [RD_MO_CNT-1:0]              w_rid_numbering_onehot;
logic [RD_MO_IDX_WD-1:0]           w_rid_numbering;


always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_arcnt <= 'd0;
    end else if ((I_AXI_ArValid & I_AXI_ArReady)|(I_AXI_RLast & I_AXI_RValid & I_AXI_RReady))begin
        r_arcnt <= w_arcnt_next;
    end
end

always_comb begin
    w_arcnt_next = r_arcnt;
    if (I_AXI_ArValid & I_AXI_ArReady) begin
        w_arcnt_next = w_arcnt_next + 'd1;
    end

    if (I_AXI_RLast & I_AXI_RValid & I_AXI_RReady) begin
        w_arcnt_next = w_arcnt_next - 'd1;
    end
end

always_comb begin
    for (int i=0; i<RD_MO_CNT; i++)
        w_rid_numbering_onehot[i] = artable[i].pending && (artable[i].id == I_AXI_ArId);

    w_rid_numbering = $countones(w_rid_numbering_onehot);
end

generate
if (UP_N==2) begin
    assign nxt_rdata = I_AXI_RData;
end else begin
    assign nxt_rdata = {I_AXI_RData, artable[w_artable_rptr_cur].rdata[((UP_N-1)*O_DATA_WD)-1:O_DATA_WD]};
end
endgenerate
//------------------------------------------------------------------
// Update artable
//------------------------------------------------------------------
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        for (integer i = 0; i < RD_MO_CNT  ; i = i + 1 ) begin
            artable[i].id            <= {AXI_ID_WD{1'b0}};
            artable[i].burst_cnt     <= '0;
            artable[i].rdata         <= '0;
            artable[i].rresp         <= '0;
            artable[i].ruser         <= '0;
            artable[i].ruser_vld     <= '0;

            artable[i].pending       <= '0;
            artable[i].rid_numbering <= '0;
        end
    end
    else begin
        if (I_AXI_ArReady & I_AXI_ArValid & O_AR_Slot_Available_Flag) begin
            artable[w_artable_wptr_cur].id            <= I_AXI_ArId;
            artable[w_artable_wptr_cur].burst_cnt     <= '0;
            artable[w_artable_wptr_cur].rresp         <= '0;
            artable[w_artable_wptr_cur].ruser         <= '0;
            artable[w_artable_wptr_cur].ruser_vld     <= '0;
            artable[w_artable_wptr_cur].rdata         <= '0;
            artable[w_artable_wptr_cur].pending       <= 1'b1;
            if (I_AXI_RValid & I_AXI_RReady & I_AXI_RLast & (I_AXI_ArId == I_AXI_RId)) begin
                artable[w_artable_wptr_cur].rid_numbering       <= w_rid_numbering - 1;
            end else begin
                artable[w_artable_wptr_cur].rid_numbering       <= w_rid_numbering;
            end
        end

        if (I_AXI_RValid & I_AXI_RReady) begin
            if(I_AXI_RLast) begin
                artable[w_artable_rptr_cur].pending      <= 1'b0;
            end
            artable[w_artable_rptr_cur].burst_cnt        <= artable[w_artable_rptr_cur].burst_cnt + 1;
            artable[w_artable_rptr_cur].rdata            <= nxt_rdata;
            if (~artable[w_artable_rptr_cur].ruser_vld) begin
                artable[w_artable_rptr_cur].ruser        <= I_AXI_RUser;
                artable[w_artable_rptr_cur].ruser_vld    <= 1'b1;
            end
            if(&artable[w_artable_rptr_cur].burst_cnt) begin
                artable[w_artable_rptr_cur].rresp        <= '0;
            end else begin
                artable[w_artable_rptr_cur].rresp        <= artable[w_artable_rptr_cur].rresp | I_AXI_RResp;
            end
        end

        for (integer i=0; i<RD_MO_CNT; i=i+1) begin
            if (I_AXI_RValid & I_AXI_RReady & I_AXI_RLast & artable[i].pending & (artable[i].id == I_AXI_RId) & (artable[i].rid_numbering != 'd0)) begin
                artable[i].rid_numbering <= artable[i].rid_numbering -'d1;
            end
        end

    end
end

always_comb begin
    w_artable_wptr_cur = 'd0;
    for (integer i=0; i<RD_MO_CNT; i=i+1) begin
        if (!artable[RD_MO_CNT-1 - i].pending) begin  // search from back
            w_artable_wptr_cur = RD_MO_CNT-1 - i;
        end
    end
end

always_comb begin
    w_artable_rptr_cur = 'd0;
    for (integer i=0; i<RD_MO_CNT; i=i+1) begin
        w_artable_r_onehot[i] = artable[i].pending & (artable[i].id == I_AXI_RId) & (artable[i].rid_numbering == 'd0);
    end

    for (integer i=0; i<RD_MO_CNT; i=i+1) begin
        if (w_artable_r_onehot[i]) begin
            w_artable_rptr_cur = i;
        end
    end
end

//------------------------------------------------------------------
assign O_ReorderBuf_MValid = &artable[w_artable_rptr_cur].burst_cnt;
assign O_ReorderBuf_MData  = {I_AXI_RData, artable[w_artable_rptr_cur].rdata};
assign O_ReorderBuf_MResp  = artable[w_artable_rptr_cur].rresp | I_AXI_RResp;
// A merged beat leaves on narrow beat UP_N-1 of its group at the earliest and
// UP_N >= 2, so the first beat's RUSER is always in the table before it is read.
assign O_ReorderBuf_MUser  = artable[w_artable_rptr_cur].ruser;
assign O_RReadyNonBlocking = ~(&artable[w_artable_rptr_cur].burst_cnt);
assign O_ReorderBuf_MId    = artable[w_artable_rptr_cur].id;
//------------------------------------------------------------------
assign O_DEST_TABLE_ID_ERR = I_AXI_RValid & I_AXI_RReady & ~(|w_artable_r_onehot);
assign O_AR_Slot_Available_Flag = (r_arcnt != RD_MO_CNT);

`ifdef ASSERTION_ON
// synopsys translate_off

aou_axi_down_rdata_order_table_id_err_assertion:
    assert
        property (
            @(posedge I_CLK) disable iff (!I_RESETN)
            !O_DEST_TABLE_ID_ERR
        )
        else begin
            $error("\n[%t] AOU_AXI_DOWN_RDATA_ORDER: O_DEST_TABLE_ID_ERR asserted!", $time);
            $finish;
        end

// synopsys translate_on
`endif

endmodule
