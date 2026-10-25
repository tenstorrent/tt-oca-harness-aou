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
//  Module     : AOU_ERROR_INFO
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_ERROR_INFO #(
    parameter  AXI_ID_WD = 16,
    parameter   AXI_DATA_WD = 512,
    parameter  AXI_ADDR_WD = 64,
    parameter  AXI_LEN_WD  = 8,
    parameter  FIFO_DEPTH = 4,
    localparam AXI_STRB_WD = AXI_DATA_WD/8
)
(
    input                               I_RESETN,
    input                               I_CLK,
    
    input      [ AXI_ID_WD-1:0]         I_BRESP_ERR_ID,
    input      [ AXI_ADDR_WD-1:0]       I_BRESP_ERR_ADDR,
    input      [ 1 :0]                  I_BRESP_ERR_BRESP,
    input                               I_BRESP_ERR,

    input      [ AXI_ID_WD-1:0]         I_RRESP_ERR_ID,
    input      [ AXI_ADDR_WD-1:0]       I_RRESP_ERR_ADDR,
    input      [ 1 :0]                  I_RRESP_ERR_RRESP,
    input                               I_RRESP_ERR,

    //AXI IF for INFO access
    input       [ AXI_ID_WD-1: 0]       I_S_AWID,
    input       [ AXI_ADDR_WD-1: 0]     I_S_AWADDR,
    input       [ AXI_LEN_WD-1: 0]      I_S_AWLEN,
    input       [ 2: 0]                 I_S_AWSIZE,
    input       [ 1: 0]                 I_S_AWBURST,
    input                               I_S_AWLOCK,
    input       [ 3: 0]                 I_S_AWCACHE,
    input       [ 2: 0]                 I_S_AWPROT,
    input       [ 3: 0]                 I_S_AWQOS,
    input                               I_S_AWVALID,
    output wire                         O_S_AWREADY,

    input       [ AXI_DATA_WD-1 : 0]    I_S_WDATA,
    input       [ AXI_STRB_WD-1 : 0]    I_S_WSTRB,
    input                               I_S_WLAST,
    input                               I_S_WVALID,
    output                              O_S_WREADY,

    output wire [ AXI_ID_WD-1: 0]       O_S_BID,
    output wire [ 1: 0]                 O_S_BRESP,
    output wire                         O_S_BVALID,
    input                               I_S_BREADY,

    input       [ AXI_ID_WD-1: 0]       I_S_ARID,
    input       [ AXI_ADDR_WD-1: 0]     I_S_ARADDR,
    input       [ 2: 0]                 I_S_ARSIZE,
    input       [ 1: 0]                 I_S_ARBURST,
    input       [ 3: 0]                 I_S_ARCACHE,
    input       [ 2: 0]                 I_S_ARPROT,
    input       [ AXI_LEN_WD-1: 0]      I_S_ARLEN,
    input                               I_S_ARLOCK,
    input       [ 3: 0]                 I_S_ARQOS,
    input                               I_S_ARVALID,
    output wire                         O_S_ARREADY,

    output wire [ AXI_ID_WD-1: 0]       O_S_RID,
    output wire [ AXI_DATA_WD-1: 0]     O_S_RDATA,
    output wire [ 1: 0]                 O_S_RRESP,
    output wire                         O_S_RLAST,
    output wire                         O_S_RVALID,
    input                               I_S_RREADY

);
localparam ERROR_INFO_WD = AXI_ID_WD + AXI_ADDR_WD + 2;
localparam AW = $clog2(FIFO_DEPTH);
localparam CNT_WD = $clog2(FIFO_DEPTH+1);

typedef logic [AW-1:0] ptr_idx;

logic [ERROR_INFO_WD-1:0] r_error_info_fifo  [FIFO_DEPTH-1:0];

logic [AW-1:0] r_ptr, w_ptr;
logic [AW-1:0] nxt_r_ptr, nxt_w_ptr_1, nxt_w_ptr_2;

logic  r_ex_ptr, w_ex_ptr;
logic  nxt_r_ex_ptr, nxt_w_ex_ptr_1, nxt_w_ex_ptr_2;

logic w_fifo_full;
logic w_fifo_empty;

assign w_fifo_full = (w_ptr == r_ptr) && (r_ex_ptr != w_ex_ptr);
assign w_fifo_empty = (w_ptr == r_ptr) && (r_ex_ptr == w_ex_ptr);

always_comb begin
    nxt_r_ptr   = w_fifo_empty ? r_ptr : (r_ptr == FIFO_DEPTH-1) ? ptr_idx'(1'b0) : ptr_idx'(r_ptr + 1);
    nxt_w_ptr_1 = w_fifo_full ? w_ptr : (w_ptr == FIFO_DEPTH-1) ? ptr_idx'(1'b0) : ptr_idx'(w_ptr + 1);
    nxt_w_ptr_2 = w_fifo_full ? w_ptr : (nxt_w_ptr_1 == FIFO_DEPTH-1) ? ptr_idx'(1'b0) : ptr_idx'(nxt_w_ptr_1 + 1);
end

always_comb begin
    nxt_r_ex_ptr   = w_fifo_empty ? r_ex_ptr : (r_ptr == FIFO_DEPTH-1) ? ~r_ex_ptr : r_ex_ptr;
    nxt_w_ex_ptr_1 = w_fifo_full ? w_ex_ptr : (w_ptr == FIFO_DEPTH-1) ? ~w_ex_ptr : w_ex_ptr;
    nxt_w_ex_ptr_2 = w_fifo_full ? w_ex_ptr : (nxt_w_ptr_1 == FIFO_DEPTH-1) ? ~nxt_w_ex_ptr_1 : nxt_w_ex_ptr_1;
end

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        for (int unsigned i = 0; i < FIFO_DEPTH; i++) begin
            r_error_info_fifo[i] <= 'b0;
        end
        w_ptr <= ptr_idx'(1'b0);
        w_ex_ptr <= 1'b0;
    end else if (I_BRESP_ERR && I_RRESP_ERR) begin
        if ((nxt_w_ptr_1 == r_ptr) && (nxt_w_ex_ptr_1 != r_ex_ptr)) begin
            w_ptr <= nxt_w_ptr_1;
            w_ex_ptr <= nxt_w_ex_ptr_1;
            if (!w_fifo_full) begin
                r_error_info_fifo[ptr_idx'(w_ptr)] <= {I_BRESP_ERR_ID, I_BRESP_ERR_ADDR, I_BRESP_ERR_BRESP};
            end
        end else begin
            w_ptr <= nxt_w_ptr_2;
            w_ex_ptr <= nxt_w_ex_ptr_2;
            if (!w_fifo_full) begin
                r_error_info_fifo[ptr_idx'(w_ptr)] <= {I_BRESP_ERR_ID, I_BRESP_ERR_ADDR, I_BRESP_ERR_BRESP};
                r_error_info_fifo[ptr_idx'(w_ptr + 1)] <= {I_RRESP_ERR_ID, I_RRESP_ERR_ADDR, I_RRESP_ERR_RRESP};
            end
        end
    end else if (I_BRESP_ERR) begin
        w_ptr <= nxt_w_ptr_1;
        w_ex_ptr <= nxt_w_ex_ptr_1;
        if (!w_fifo_full) begin
            r_error_info_fifo[ptr_idx'(w_ptr)] <= {I_BRESP_ERR_ID, I_BRESP_ERR_ADDR, I_BRESP_ERR_BRESP};
        end
    end else if (I_RRESP_ERR) begin
        w_ptr <= nxt_w_ptr_1;
        w_ex_ptr <= nxt_w_ex_ptr_1;
        if (!w_fifo_full) begin
            r_error_info_fifo[ptr_idx'(w_ptr)] <= {I_RRESP_ERR_ID, I_RRESP_ERR_ADDR, I_RRESP_ERR_RRESP};
        end
    end
end


// A pop is one write burst. The burst completes once its AW and its WLAST beat
// have both been accepted. AWREADY/WREADY are held low between that point and
// the cycle the B register is free, so B never precedes WLAST and is never lost.
logic w_aw_hs;
logic w_w_hs;
logic w_aw_seen;
logic w_wlast_seen;
logic w_fifo_pop;
logic r_aw_got;
logic r_wlast_got;
logic [AXI_ID_WD-1:0] r_awid;

assign w_aw_hs      = O_S_AWREADY && I_S_AWVALID;
assign w_w_hs       = O_S_WREADY && I_S_WVALID;
assign w_aw_seen    = r_aw_got || w_aw_hs;
assign w_wlast_seen = r_wlast_got || (w_w_hs && I_S_WLAST);
assign w_fifo_pop   = w_aw_seen && w_wlast_seen && (!O_S_BVALID || I_S_BREADY);

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_ptr <= 'b0;
        r_ex_ptr <= 1'b0;
    end else if (w_fifo_pop) begin
        r_ptr  <= nxt_r_ptr;
        r_ex_ptr <= nxt_r_ex_ptr;
    end
end 

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_aw_got <= 1'b0;
        r_wlast_got <= 1'b0;
        r_awid <= 'b0;
    end else if (w_fifo_pop) begin
        r_aw_got <= 1'b0;
        r_wlast_got <= 1'b0;
    end else begin
        if (w_aw_hs) begin
            r_aw_got <= 1'b1;
            r_awid <= I_S_AWID;
        end
        if (w_w_hs && I_S_WLAST) begin
            r_wlast_got <= 1'b1;
        end
    end
end

logic r_fifo_pop_state;
logic [AXI_ID_WD-1:0] r_fifo_pop_id;
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_fifo_pop_state <= 1'b0;
        r_fifo_pop_id <= 'b0;
    end else if (w_fifo_pop) begin
        r_fifo_pop_state <= 1'b1;
        r_fifo_pop_id <= r_aw_got ? r_awid : I_S_AWID;
    end else if (O_S_BVALID && I_S_BREADY) begin
        r_fifo_pop_state <= 1'b0;
        r_fifo_pop_id <= 'b0;
    end
end

// A read burst returns I_S_ARLEN+1 beats, each carrying the FIFO head, so the
// entry sits in every lane a width converter can map the requester's bytes to.
// The head is sampled into r_fifo_read_data when the request becomes the active
// read, so every beat of the burst carries the same entry and RDATA holds still
// while RVALID waits for RREADY, whatever the FIFO does meanwhile (a pop from the
// write channel, a push into an empty FIFO).
// One AR can wait in r_ar_pend_* while a burst is in flight; it is loaded on the
// last beat's handshake, keeping back-to-back single-beat reads gapless without
// a combinational RREADY -> ARREADY path.
logic w_ar_hs;
logic w_r_hs;
logic w_r_last;
logic w_r_load;
logic r_fifo_read_resp;
logic [AXI_ID_WD-1:0] r_fifo_read_id;
logic [AXI_LEN_WD-1:0] r_fifo_read_cnt;
logic [ERROR_INFO_WD-1:0] r_fifo_read_data;
logic r_ar_pend;
logic [AXI_ID_WD-1:0] r_ar_pend_id;
logic [AXI_LEN_WD-1:0] r_ar_pend_len;

assign w_ar_hs  = O_S_ARREADY && I_S_ARVALID;
assign w_r_hs   = O_S_RVALID && I_S_RREADY;
assign w_r_last = (r_fifo_read_cnt == '0);
assign w_r_load = !r_fifo_read_resp || (w_r_hs && w_r_last);

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_fifo_read_resp <= 1'b0;
        r_fifo_read_id <= 'b0;
        r_fifo_read_cnt <= 'b0;
        r_fifo_read_data <= 'b0;
    end else if (w_r_load) begin
        if (r_ar_pend) begin
            r_fifo_read_resp <= 1'b1;
            r_fifo_read_id <= r_ar_pend_id;
            r_fifo_read_cnt <= r_ar_pend_len;
            r_fifo_read_data <= r_error_info_fifo[ptr_idx'(r_ptr)];
        end else if (w_ar_hs) begin
            r_fifo_read_resp <= 1'b1;
            r_fifo_read_id <= I_S_ARID;
            r_fifo_read_cnt <= I_S_ARLEN;
            r_fifo_read_data <= r_error_info_fifo[ptr_idx'(r_ptr)];
        end else begin
            r_fifo_read_resp <= 1'b0;
            r_fifo_read_id <= 'b0;
            r_fifo_read_cnt <= 'b0;
        end
    end else if (w_r_hs) begin
        r_fifo_read_cnt <= r_fifo_read_cnt - 1'b1;
    end
end

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_ar_pend <= 1'b0;
        r_ar_pend_id <= 'b0;
        r_ar_pend_len <= 'b0;
    end else if (w_ar_hs && !w_r_load) begin
        r_ar_pend <= 1'b1;
        r_ar_pend_id <= I_S_ARID;
        r_ar_pend_len <= I_S_ARLEN;
    end else if (w_r_load) begin
        r_ar_pend <= 1'b0;
    end
end

assign O_S_AWREADY = !r_aw_got;
assign O_S_WREADY  = !r_wlast_got;

assign O_S_BID = r_fifo_pop_id;
assign O_S_BRESP = 2'b00;
assign O_S_BVALID  = r_fifo_pop_state;

assign O_S_ARREADY = !r_ar_pend;

assign O_S_RID = r_fifo_read_id;
assign O_S_RDATA = r_fifo_read_data;
assign O_S_RRESP = 2'b00;
assign O_S_RLAST = w_r_last;
assign O_S_RVALID  = r_fifo_read_resp;

endmodule

