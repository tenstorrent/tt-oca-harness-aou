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
//  Module     : AOU_SYNC_FIFO_NS1M_SREADY
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_SYNC_FIFO_NS1M_SREADY
#(
    parameter   FIFO_WIDTH = 32,          // data width
    parameter   FIFO_DEPTH = 8 ,          // depth
    parameter   ICH_CNT  = 4   ,          // input channel count

    localparam  ICH_CNT_WD = $clog2(ICH_CNT+1),
    localparam  ICH_IDX_WD = (ICH_CNT <= 1 ) ? 1 : $clog2(ICH_CNT),
    localparam  AW         = $clog2(FIFO_DEPTH),
    localparam  CNT_WD     = $clog2(FIFO_DEPTH+1)
)
(
    input                                   I_CLK,
    input                                   I_RESETN,

    input    [ICH_CNT -1:0]                 I_SVALID,
    input    [ICH_CNT -1:0][FIFO_WIDTH-1:0] I_SDATA,
    output                                  O_SREADY,
    
    input                                   I_MREADY,
    output   [FIFO_WIDTH-1:0]               O_MDATA,
    output                                  O_MVALID,

    output   [CNT_WD-1:0]                   O_S_EMPTY_CNT,
    output   [CNT_WD-1:0]                   O_M_DATA_CNT

);

logic [FIFO_DEPTH-1:0][FIFO_WIDTH-1:0]  r_fifo;
logic [AW-1:0]                          r_rd_ptr, r_wr_ptr;
logic                                   r_ex_rd_ptr, r_ex_wr_ptr ;
logic [ICH_CNT-1:0][AW-1:0]             w_nxt_wr_ptr;

logic [CNT_WD-1:0]                      r_data_cnt;

logic [ICH_CNT-1:0][FIFO_WIDTH-1:0]     w_nxt_fifo_data ;
logic [ICH_CNT_WD -1:0]                 w_write_req_cnt;

logic [ICH_CNT_WD -1:0]                 require_space;

//-------------------------------------------------------------
integer idx_write_req;

always_comb begin
    w_write_req_cnt     = 'd0;
    w_nxt_fifo_data     = 'd0;
    w_nxt_wr_ptr        = 'd0;

    for (idx_write_req = 0; idx_write_req < ICH_CNT; idx_write_req = idx_write_req + 1) begin
        if (I_SVALID[idx_write_req] == 1'b1) begin
            w_nxt_fifo_data[w_write_req_cnt[ICH_IDX_WD-1:0]] = I_SDATA[idx_write_req]; 
            w_nxt_wr_ptr[w_write_req_cnt[ICH_IDX_WD-1:0]] = (r_wr_ptr + w_write_req_cnt >= FIFO_DEPTH) ? (r_wr_ptr + w_write_req_cnt - FIFO_DEPTH) : (r_wr_ptr + w_write_req_cnt);
            w_write_req_cnt = w_write_req_cnt + 1;
        end
    end
end

//for write 
integer i;
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        for (i = 0; i < FIFO_DEPTH; i = i+1) begin
            r_fifo[i] <= 0;
        end
        r_wr_ptr <= 0;
        r_ex_wr_ptr <= 0;
    end else begin
        if (|I_SVALID & O_SREADY ) begin
            for (i = 0; i < ICH_CNT; i = i+1) begin
                if(i < w_write_req_cnt) r_fifo[w_nxt_wr_ptr[i][AW-1:0]] <= w_nxt_fifo_data[i];
            end
            r_wr_ptr <= (r_wr_ptr + w_write_req_cnt >= FIFO_DEPTH) ? (r_wr_ptr + w_write_req_cnt - FIFO_DEPTH) : (r_wr_ptr + w_write_req_cnt);
            r_ex_wr_ptr <= (r_wr_ptr + w_write_req_cnt >= FIFO_DEPTH) ?  ~r_ex_wr_ptr : r_ex_wr_ptr;
        end 
    end
end

//for read
always_ff @ (posedge I_CLK or negedge I_RESETN ) begin
    if (~I_RESETN) begin
        r_rd_ptr <= 0;
        r_ex_rd_ptr <= 0;
    end else begin
        if (I_MREADY && O_MVALID) begin
            r_rd_ptr <= (r_rd_ptr + 1 == FIFO_DEPTH) ? 0 : (r_rd_ptr + 1);
            r_ex_rd_ptr <= (r_rd_ptr + 1 == FIFO_DEPTH) ? ~r_ex_rd_ptr  : r_ex_rd_ptr ;
        end
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN ) begin
    if (~I_RESETN) begin
        r_data_cnt <= 0;
    end else begin
        if (|I_SVALID & O_SREADY & I_MREADY & O_MVALID) begin
            r_data_cnt <= r_data_cnt + w_write_req_cnt -1;
        end else if (|I_SVALID & O_SREADY) begin
            r_data_cnt <= r_data_cnt + w_write_req_cnt;
        end else if (I_MREADY & O_MVALID) begin
            r_data_cnt <= r_data_cnt - 1;
        end
    end
end

assign O_S_EMPTY_CNT = FIFO_DEPTH - r_data_cnt;
assign O_M_DATA_CNT = r_data_cnt;


always_comb begin
    require_space = 'd0;
    for(int k = 0; k < ICH_CNT; k = k + 1) begin
        if(I_SVALID[k])
            require_space = require_space + 1;
    end
end

assign O_SREADY = O_S_EMPTY_CNT >= require_space;

assign O_MVALID = ~((r_wr_ptr == r_rd_ptr) & (r_ex_wr_ptr == r_ex_rd_ptr)); 
assign O_MDATA = r_fifo[r_rd_ptr];

endmodule


