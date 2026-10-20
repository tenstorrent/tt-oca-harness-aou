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
//  Module     : AOU_SLV_AXI_INFO
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_SLV_AXI_INFO #(
    parameter  AXI_ID_WD             = 10,
    parameter  AXI_LEN_WD            = 8,

    parameter  RD_MO_CNT                = 64,
    parameter  WR_MO_CNT                = 64,
    localparam RD_MO_CNT_WD             = $clog2(RD_MO_CNT+1),
    localparam WR_MO_CNT_WD             = $clog2(WR_MO_CNT+1),

    localparam RD_MO_IDX_WD             = $clog2(RD_MO_CNT),
    localparam WR_MO_IDX_WD             = $clog2(WR_MO_CNT)

)
(
    input                                       I_CLK                      ,
    input                                       I_RESETN                   ,

    input [AXI_ID_WD-1:0]                       I_AWID                     ,
    input                                       I_AWVALID                  ,
    input                                       I_AWREADY                  ,      

    input                                       I_WLAST                    ,
    input                                       I_WVALID                   ,
    input                                       I_WREADY                   ,

    input [AXI_ID_WD-1:0]                       I_BID                      ,
    input                                       I_BVALID                   ,
    input                                       I_BREADY                   ,

    input [AXI_ID_WD-1:0]                       I_ARID                     ,
    input                                       I_ARVALID                  ,
    input                                       I_ARREADY                  ,

    input [AXI_ID_WD-1:0]                       I_RID                      ,
    input                                       I_RLAST                    ,
    input                                       I_RVALID                   ,
    input                                       I_RREADY                   ,

    output [AXI_ID_WD-1:0]                      O_SLV_AXI_MISMATCH_RID     ,
    output                                      O_SLV_AXI_MISMATCH_R_ERR   ,

    output [AXI_ID_WD-1:0]                      O_SLV_AXI_MISMATCH_BID     ,
    output                                      O_SLV_AXI_MISMATCH_B_ERR   ,

    output                                      O_SLV_AXI_R_BLOCK          ,
    output                                      O_SLV_AXI_B_BLOCK          ,

    output                                      O_AW_HOLD_FLAG             ,
    output                                      O_W_HOLD_FLAG              ,
    output                                      O_AR_HOLD_FLAG   

);
localparam table_payload_width = 1 + AXI_ID_WD;

typedef struct packed {
    logic [AXI_ID_WD-1:0]   axi_id;
    logic                   valid;
} st_ar_table;

st_ar_table [RD_MO_CNT-1:0] r_pending_rid_table;
st_ar_table [WR_MO_CNT-1:0] r_pending_wid_table;

// AR table logic
logic [RD_MO_IDX_WD-1:0]   r_rid_table_rd_ptr;
logic [RD_MO_IDX_WD-1:0]   r_rid_table_wr_ptr;

logic [RD_MO_CNT-1:0]      w_rid_table_match_flag; //find valid & ID match idx

// AW table logic
logic [WR_MO_IDX_WD-1:0]   r_wid_table_rd_ptr;
logic [WR_MO_IDX_WD-1:0]   r_wid_table_wr_ptr;

logic [WR_MO_CNT-1:0]      w_wid_table_match_flag; //find valid & ID match idx

// Tranaction count
logic [WR_MO_CNT_WD-1:0]   r_awcnt;
logic [WR_MO_CNT_WD-1:0]   r_wcnt;

logic [RD_MO_CNT_WD-1:0]   r_arcnt;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_awcnt <= '0;
    end else if ((I_AWVALID && I_AWREADY) & ~(I_BVALID && I_BREADY)) begin
        r_awcnt <= r_awcnt + {{(WR_MO_CNT_WD-1){1'b0}}, 1'b1};
    end else if (~(I_AWVALID && I_AWREADY) & (I_BVALID && I_BREADY)) begin
        r_awcnt <= r_awcnt - {{(WR_MO_CNT_WD-1){1'b0}}, 1'b1};
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_wcnt <= '0;
    end else if ((I_WLAST && I_WVALID && I_WREADY) & ~(I_BVALID && I_BREADY)) begin
        r_wcnt <= r_wcnt + {{(WR_MO_CNT_WD-1){1'b0}}, 1'b1};
    end else if (~(I_WLAST && I_WVALID && I_WREADY) & (I_BVALID && I_BREADY)) begin
        r_wcnt <= r_wcnt - {{(WR_MO_CNT_WD-1){1'b0}}, 1'b1};
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_arcnt <= '0;
    end else if ((I_ARVALID && I_ARREADY) & ~(I_RVALID && I_RREADY && I_RLAST)) begin
        r_arcnt <= r_arcnt + {{(RD_MO_CNT_WD-1){1'b0}}, 1'b1};
    end else if (~(I_ARVALID && I_ARREADY) & (I_RVALID && I_RREADY && I_RLAST)) begin
        r_arcnt <= r_arcnt - {{(RD_MO_CNT_WD-1){1'b0}}, 1'b1};
    end
end

//=====================================================================================
//=================== AR Table ========================================================
//=====================================================================================
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        for (int unsigned i = 0; i < RD_MO_CNT ; i = i + 1) begin
            r_pending_rid_table[i].axi_id   <= {AXI_ID_WD{1'b0}};
            r_pending_rid_table[i].valid    <= 1'b0;
        end
    end else begin
        if (I_ARVALID && I_ARREADY) begin
            r_pending_rid_table[r_rid_table_wr_ptr].axi_id <= I_ARID;
            r_pending_rid_table[r_rid_table_wr_ptr].valid  <= 1'b1;
        end 

        if (I_RVALID && I_RREADY && (|w_rid_table_match_flag) && I_RLAST) begin
            r_pending_rid_table[r_rid_table_rd_ptr].axi_id <= {AXI_ID_WD{1'b0}};
            r_pending_rid_table[r_rid_table_rd_ptr].valid  <= 1'b0;
        end
    end
end

//Write ptr

always_comb begin
    r_rid_table_wr_ptr = 0;
    for (int unsigned i = 0; i < RD_MO_CNT ; i = i + 1) begin
        if (r_pending_rid_table[i].valid == 1'b0) begin
            r_rid_table_wr_ptr = i;
        end
    end
end

//Read ptr
always_comb begin
    r_rid_table_rd_ptr = 0;
   for (int unsigned i = 0; i < RD_MO_CNT ; i = i + 1) begin
       if ((r_pending_rid_table[i].axi_id == I_RID) && (r_pending_rid_table[i].valid == 1'b1)) begin
           w_rid_table_match_flag[i] = 1'b1;
           r_rid_table_rd_ptr = i;
       end else begin
           w_rid_table_match_flag[i] = 1'b0;
       end
   end
end

logic r_slv_axi_mismatch_r_err;
logic [AXI_ID_WD-1:0] r_slv_axi_mismatch_r_id;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_slv_axi_mismatch_r_err <= 1'b0;
        r_slv_axi_mismatch_r_id <= 'b0;
    end else if (I_RVALID && I_RREADY) begin
        if (|w_rid_table_match_flag) begin
            r_slv_axi_mismatch_r_err <= 1'b0;
            r_slv_axi_mismatch_r_id <= 'b0;
        end else begin
            r_slv_axi_mismatch_r_err <= 1'b1;
            r_slv_axi_mismatch_r_id <= I_RID;
        end
    end else if (r_slv_axi_mismatch_r_err) begin
        r_slv_axi_mismatch_r_err <= 1'b0;
        r_slv_axi_mismatch_r_id <= 'b0;
    end
end

logic w_slv_axi_mismatch_r_err;

always_comb begin
    if (I_RVALID && I_RREADY && (!(|w_rid_table_match_flag))) begin
        w_slv_axi_mismatch_r_err = 1'b1;
    end else begin
        w_slv_axi_mismatch_r_err = 1'b0;
    end
end

//======================================================================================
//=================== AW Table =========================================================
//======================================================================================

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        for (int unsigned i = 0; i < WR_MO_CNT ; i = i + 1) begin
            r_pending_wid_table[i].axi_id   <= {AXI_ID_WD{1'b0}};
            r_pending_wid_table[i].valid    <= 1'b0;
        end
    end else begin
        if (I_AWVALID && I_AWREADY) begin
            r_pending_wid_table[r_wid_table_wr_ptr].axi_id <= I_AWID;
            r_pending_wid_table[r_wid_table_wr_ptr].valid  <= 1'b1;
        end 

        if (I_BVALID && I_BREADY && (|w_wid_table_match_flag)) begin
            r_pending_wid_table[r_wid_table_rd_ptr].axi_id <= {AXI_ID_WD{1'b0}};
            r_pending_wid_table[r_wid_table_rd_ptr].valid  <= 1'b0;
        end
    end
end

always_comb begin
    r_wid_table_wr_ptr = 0;
    for (int unsigned i = 0; i < WR_MO_CNT ; i = i + 1) begin
        if (r_pending_wid_table[i].valid == 1'b0) begin
            r_wid_table_wr_ptr = i;
        end
    end
end

//Read ptr
always_comb begin
    r_wid_table_rd_ptr = 0;
   for (int unsigned i = 0; i < WR_MO_CNT ; i = i + 1) begin
       if ((r_pending_wid_table[i].axi_id == I_BID) && (r_pending_wid_table[i].valid == 1'b1)) begin
           w_wid_table_match_flag[i] = 1'b1;
           r_wid_table_rd_ptr = i;
       end else begin
           w_wid_table_match_flag[i] = 1'b0;
       end
   end
end

logic r_slv_axi_mismatch_w_err;
logic [AXI_ID_WD-1:0] r_slv_axi_mismatch_b_id;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_slv_axi_mismatch_w_err <= 1'b0;
        r_slv_axi_mismatch_b_id <= 'b0;
    end else if (I_BVALID && I_BREADY) begin
        if (|w_wid_table_match_flag) begin
            r_slv_axi_mismatch_w_err <= 1'b0;
            r_slv_axi_mismatch_b_id <= 'b0;
        end else begin
            r_slv_axi_mismatch_w_err <= 1'b1;
            r_slv_axi_mismatch_b_id <= I_BID;
        end
    end else if (r_slv_axi_mismatch_w_err) begin
        r_slv_axi_mismatch_w_err <= 1'b0;
        r_slv_axi_mismatch_b_id <= 'b0;
    end
end

logic w_slv_axi_mismatch_w_err;

always_comb begin
    if (I_BVALID && I_BREADY && (!(|w_wid_table_match_flag))) begin
        w_slv_axi_mismatch_w_err = 1'b1;
    end else begin
        w_slv_axi_mismatch_w_err = 1'b0;
    end
end

assign O_SLV_AXI_MISMATCH_R_ERR = r_slv_axi_mismatch_r_err ; 
assign O_SLV_AXI_MISMATCH_RID   = r_slv_axi_mismatch_r_id  ; 
assign O_SLV_AXI_MISMATCH_B_ERR = r_slv_axi_mismatch_w_err ; 
assign O_SLV_AXI_MISMATCH_BID   = r_slv_axi_mismatch_b_id  ; 
assign O_SLV_AXI_R_BLOCK        = w_slv_axi_mismatch_r_err ; 
assign O_SLV_AXI_B_BLOCK        = w_slv_axi_mismatch_w_err ; 

assign O_AW_HOLD_FLAG           = (r_awcnt == WR_MO_CNT);
assign O_W_HOLD_FLAG            = (r_wcnt  == WR_MO_CNT);
assign O_AR_HOLD_FLAG           = (r_arcnt == RD_MO_CNT);

endmodule
