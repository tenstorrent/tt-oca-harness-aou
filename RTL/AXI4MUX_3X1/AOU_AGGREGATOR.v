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
//  Module     : AOU_AGGREGATOR
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AGGREGATOR #(

    parameter DATA_WD = 512,
    parameter ADDR_WD = 64,
    parameter ID_WD   = 10,
    parameter STRB_WD = DATA_WD / 8,
    parameter LEN_WD  = 8,
    parameter DATA_BYTE = DATA_WD / 8,
    parameter RD_MO_CNT = 128,
    parameter AOU_AGG_WCH_FIFO_DEPTH = 16 //It should be configured to a value greater than the maximum burst length of the local bus.
) 
(
    input                           I_CLK,
    input                           I_RESETN,

    //WRITE TRANSCATION
    input [ID_WD-1:0]               I_S_AWID,
    input [ADDR_WD-1: 0]            I_S_AWADDR,
    input [LEN_WD-1: 0]             I_S_AWLEN,
    input [2: 0]                    I_S_AWSIZE,
    input [1:0]                     I_S_AWBURST,
    input                           I_S_AWLOCK,
    input [3:0]                     I_S_AWCACHE,//[1]: Modifiable, [0]: Bufferable
    input [2:0]                     I_S_AWPROT,
    input [3:0]                     I_S_AWQOS,
    input                           I_S_AWVALID,
    output reg                      O_S_AWREADY,


    input [ DATA_WD-1: 0]           I_S_WDATA,
    input [ STRB_WD-1: 0]           I_S_WSTRB,
    input                           I_S_WLAST,
    input                           I_S_WVALID,
    output reg                      O_S_WREADY,

    output reg [ID_WD-1:0]          O_M_AWID,
    output reg [ADDR_WD-1: 0]       O_M_AWADDR,
    output reg [LEN_WD-1: 0]        O_M_AWLEN,
    output reg [2: 0]               O_M_AWSIZE,
    output reg [1:0]                O_M_AWBURST,
    output reg                      O_M_AWLOCK,
    output reg [3:0]                O_M_AWCACHE,
    output reg [2:0]                O_M_AWPROT,
    output reg [3:0]                O_M_AWQOS,
    output reg                      O_M_AWVALID,
    input                           I_M_AWREADY,

    output     [ DATA_WD-1: 0]      O_M_WDATA,
    output     [ STRB_WD-1: 0]      O_M_WSTRB,
    output                          O_M_WLAST,
    output                          O_M_WVALID,
    input                           I_M_WREADY,
    
    // READ TRANSACTION
    input [ID_WD-1:0]               I_S_ARID,
    input [ADDR_WD-1:0]             I_S_ARADDR,
    input [LEN_WD-1: 0]             I_S_ARLEN,
    input [2:0]                     I_S_ARSIZE,
    input [1:0]                     I_S_ARBURST,
    input [3:0]                     I_S_ARCACHE,
    input [2:0]                     I_S_ARPROT,
    input                           I_S_ARLOCK,
    input [3:0]                     I_S_ARQOS,
    input                           I_S_ARVALID,
    output reg                      O_S_ARREADY,
    
    output reg [ID_WD-1:0]          O_S_RID,
    output reg [DATA_WD-1:0]        O_S_RDATA,
    output reg [1:0]                O_S_RRESP,
    output reg                      O_S_RLAST,
    output reg                      O_S_RVALID,
    input                           I_S_RREADY,
    
    output [ID_WD-1:0]              O_M_ARID,
    output [ADDR_WD-1:0]            O_M_ARADDR,
    output [LEN_WD-1: 0]            O_M_ARLEN,
    output [2:0]                    O_M_ARSIZE,
    output [1:0]                    O_M_ARBURST,
    output [3:0]                    O_M_ARCACHE,
    output [2:0]                    O_M_ARPROT,
    output                          O_M_ARLOCK,
    output [3:0]                    O_M_ARQOS,
    output                          O_M_ARVALID,
    input                           I_M_ARREADY,
    
    input [ID_WD-1:0]               I_M_RID,
    input [DATA_WD-1:0]             I_M_RDATA,
    input [1:0]                     I_M_RRESP,
    input                           I_M_RLAST,
    input                           I_M_RVALID,
    output reg                      O_M_RREADY,

    output                          O_DEST_TABLE_RID_ERR,
    output[ID_WD-1:0]               O_AGGRE_MISMATCH_RID
);

//write transaction reg, wire
reg                                 w_en_aggregator_w;
reg                                 r_en_aggregator_w;
wire                                w_en_aggregator_w_mux;

reg [7:0]                           size_in_bytes;

//----------------------------------------------------
localparam AXSIZE = $clog2(DATA_WD/8);
localparam ADDR_OFF_WD = $clog2(DATA_WD/8);

reg  [LEN_WD-1:0]                   w_agg_awlen;
reg  [LEN_WD:0]                     w_agg_awlen_ext;

reg                                 r_s_wbusy_tt;
reg  [2: 0]                         r_s_awsize;
wire [2: 0]                         w_s_awsize_mux;

reg                                 w_agg_wr_en ;
reg  [ADDR_OFF_WD-1:0]              w_agg_cur_awaddr;
reg  [ADDR_OFF_WD-1:0]              r_s_awaddr;

reg  [LEN_WD-1:0]                   w_agg_arlen;
reg  [LEN_WD:0]                     w_agg_arlen_ext;

wire [$clog2(STRB_WD)-1:0]          w_rob_araddr;

wire                                w_rob_ar_slot_avail_flag; 
wire [ID_WD-1:0]                    w_rob_rid;
wire [2:0]                          w_rob_arsize;
wire [LEN_WD-1:0]                   w_rob_org_arlen;
wire [2:0]                          w_rob_org_arsize;
wire [LEN_WD-1:0]                   w_rob_cur_burst_len;
wire                                w_rob_s_rlast_send;

reg  [ID_WD-1:0]                    r_rob_rid;
reg  [LEN_WD:0]                     r_rob_cur_burst_len;
reg                                 r_rob_s_rlast_send;

reg  [DATA_WD-1:0]                  r_m_rdata;
reg  [1:0]                          r_m_rresp;

//----------------------------------------------------
//internal memory
reg  [DATA_WD-1:0]                  r_prev_mem_wdata;
wire [DATA_WD-1:0]                  w_cur_mem_wdata;

reg  [STRB_WD-1:0]                  r_prev_mem_wstrb;
wire [STRB_WD-1:0]                  w_cur_mem_wstrb;

wire [DATA_WD-1:0]                  nxt_masked_wdata;

//----------------------------------------------------
reg  [ID_WD-1:0]                    O_M_AWID_RS;
reg  [ADDR_WD-1: 0]                 O_M_AWADDR_RS;
reg  [LEN_WD-1: 0]                  O_M_AWLEN_RS;
reg  [2: 0]                         O_M_AWSIZE_RS;
reg  [1:0]                          O_M_AWBURST_RS;
reg                                 O_M_AWLOCK_RS;
reg  [3:0]                          O_M_AWCACHE_RS;
reg  [2:0]                          O_M_AWPROT_RS;
reg  [3:0]                          O_M_AWQOS_RS;
reg                                 O_M_AWVALID_RS;
wire                                I_M_AWREADY_RS;

//----------------------------------------------------
reg  [ DATA_WD-1: 0]                O_M_WDATA_FIFO_IN;
reg  [ STRB_WD-1: 0]                O_M_WSTRB_FIFO_IN;
reg                                 O_M_WLAST_FIFO_IN;
reg                                 O_M_WVALID_FIFO_IN;
wire                                I_M_WREADY_FIFO_IN;
    
//----------------------------------------------------
assign w_en_aggregator_w_mux = ~r_s_wbusy_tt ? w_en_aggregator_w : r_en_aggregator_w; 
assign w_s_awsize_mux = ~r_s_wbusy_tt ? I_S_AWSIZE : r_s_awsize; 
assign w_cur_mem_wdata = r_prev_mem_wdata | nxt_masked_wdata;
assign w_cur_mem_wstrb = r_prev_mem_wstrb | I_S_WSTRB;

always @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_s_wbusy_tt <= 'd0;
        r_en_aggregator_w <= 1'b0;

        r_s_awsize <= 'd0;
        r_s_awaddr <= 'd0;
        r_prev_mem_wdata <= 'd0;
        r_prev_mem_wstrb <= 'd0;
    end else begin
        if ((I_S_AWVALID & O_S_AWREADY)) begin
            if (I_S_WVALID & O_S_WREADY & I_S_WLAST)
                r_s_wbusy_tt <=1'b0;
            else
                r_s_wbusy_tt <=1'b1;

            r_en_aggregator_w <= w_en_aggregator_w;
            r_s_awsize <= I_S_AWSIZE;

            if (I_S_WVALID & O_S_WREADY) begin
                if (~I_S_WLAST) begin
                    r_s_awaddr <= ADDR_OFF_WD'(w_agg_cur_awaddr + size_in_bytes) ;
                end 
            end 
            else begin
                r_s_awaddr <= w_agg_cur_awaddr ;
            end

        end else begin
            if (I_S_WVALID & O_S_WREADY & I_S_WLAST)
                r_s_wbusy_tt <= 1'b0;

            if (I_S_WVALID & O_S_WREADY) begin
                if (~w_agg_wr_en) begin
                    r_s_awaddr <= ADDR_OFF_WD'(w_agg_cur_awaddr + size_in_bytes) ;
                end 
                else begin 
                    r_s_awaddr <= 'd0;
                end
            end
        end

        if (O_M_WVALID_FIFO_IN & I_M_WREADY_FIFO_IN) begin
            r_prev_mem_wdata <= 'd0;
            r_prev_mem_wstrb <= 'd0;
        end 
        else if (I_S_WVALID & O_S_WREADY) begin
            r_prev_mem_wdata <= r_prev_mem_wdata | nxt_masked_wdata;
            r_prev_mem_wstrb <= r_prev_mem_wstrb | I_S_WSTRB;
        end 

    end
end

generate 

if(DATA_WD==256) begin
    always @(*) begin
        case (I_S_AWSIZE)
            'd4:     w_agg_awlen_ext = (I_S_AWADDR[4:4] + {1'b0, I_S_AWLEN}) >> 1;
            'd3:     w_agg_awlen_ext = (I_S_AWADDR[4:3] + {1'b0, I_S_AWLEN}) >> 2;
            'd2:     w_agg_awlen_ext = (I_S_AWADDR[4:2] + {1'b0, I_S_AWLEN}) >> 3;
            'd1:     w_agg_awlen_ext = (I_S_AWADDR[4:1] + {1'b0, I_S_AWLEN}) >> 4;
            default: w_agg_awlen_ext = (I_S_AWADDR[4:0] + {1'b0, I_S_AWLEN}) >> 5;
        endcase

        case (w_s_awsize_mux)
            'd4:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[4:4], 4'd0} : {r_s_awaddr[4:4], 4'd0} ;
            'd3:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[4:3], 3'd0} : {r_s_awaddr[4:3], 3'd0} ;
            'd2:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[4:2], 2'd0} : {r_s_awaddr[4:2], 2'd0} ;
            'd1:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[4:1], 1'd0} : {r_s_awaddr[4:1], 1'd0} ;
            default: w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[4:0]} : {r_s_awaddr[4:0]} ;
        endcase

        case (w_s_awsize_mux)
            'd4:     w_agg_wr_en = &w_agg_cur_awaddr[4:4] | I_S_WLAST;
            'd3:     w_agg_wr_en = &w_agg_cur_awaddr[4:3] | I_S_WLAST;
            'd2:     w_agg_wr_en = &w_agg_cur_awaddr[4:2] | I_S_WLAST;
            'd1:     w_agg_wr_en = &w_agg_cur_awaddr[4:1] | I_S_WLAST;
            default: w_agg_wr_en = &w_agg_cur_awaddr[4:0] | I_S_WLAST;
        endcase

    end

end else if(DATA_WD==512) begin
    always @(*) begin
        case (I_S_AWSIZE)
            'd5:     w_agg_awlen_ext = (I_S_AWADDR[5:5] + {1'b0, I_S_AWLEN}) >> 1;
            'd4:     w_agg_awlen_ext = (I_S_AWADDR[5:4] + {1'b0, I_S_AWLEN}) >> 2;
            'd3:     w_agg_awlen_ext = (I_S_AWADDR[5:3] + {1'b0, I_S_AWLEN}) >> 3;
            'd2:     w_agg_awlen_ext = (I_S_AWADDR[5:2] + {1'b0, I_S_AWLEN}) >> 4;
            'd1:     w_agg_awlen_ext = (I_S_AWADDR[5:1] + {1'b0, I_S_AWLEN}) >> 5;
            default: w_agg_awlen_ext = (I_S_AWADDR[5:0] + {1'b0, I_S_AWLEN}) >> 6;
        endcase

        case (w_s_awsize_mux)
            'd5:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[5:5], 5'd0} : {r_s_awaddr[5:5], 5'd0};
            'd4:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[5:4], 4'd0} : {r_s_awaddr[5:4], 4'd0};
            'd3:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[5:3], 3'd0} : {r_s_awaddr[5:3], 3'd0};
            'd2:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[5:2], 2'd0} : {r_s_awaddr[5:2], 2'd0};
            'd1:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[5:1], 1'd0} : {r_s_awaddr[5:1], 1'd0};
            default: w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[5:0]} : {r_s_awaddr[5:0]};
        endcase

        case (w_s_awsize_mux)
            'd5:     w_agg_wr_en = &w_agg_cur_awaddr[5:5] | I_S_WLAST;
            'd4:     w_agg_wr_en = &w_agg_cur_awaddr[5:4] | I_S_WLAST;
            'd3:     w_agg_wr_en = &w_agg_cur_awaddr[5:3] | I_S_WLAST;
            'd2:     w_agg_wr_en = &w_agg_cur_awaddr[5:2] | I_S_WLAST;
            'd1:     w_agg_wr_en = &w_agg_cur_awaddr[5:1] | I_S_WLAST;
            default: w_agg_wr_en = &w_agg_cur_awaddr[5:0] | I_S_WLAST;
        endcase
    end
end else begin
    always @(*) begin
        case (I_S_AWSIZE)
            'd6:     w_agg_awlen_ext = (I_S_AWADDR[6:6] + {1'b0, I_S_AWLEN}) >> 1;
            'd5:     w_agg_awlen_ext = (I_S_AWADDR[6:5] + {1'b0, I_S_AWLEN}) >> 2;
            'd4:     w_agg_awlen_ext = (I_S_AWADDR[6:4] + {1'b0, I_S_AWLEN}) >> 3;
            'd3:     w_agg_awlen_ext = (I_S_AWADDR[6:3] + {1'b0, I_S_AWLEN}) >> 4;
            'd2:     w_agg_awlen_ext = (I_S_AWADDR[6:2] + {1'b0, I_S_AWLEN}) >> 5;
            'd1:     w_agg_awlen_ext = (I_S_AWADDR[6:1] + {1'b0, I_S_AWLEN}) >> 6;
            default: w_agg_awlen_ext = (I_S_AWADDR[6:0] + {1'b0, I_S_AWLEN}) >> 7;
        endcase

        case (w_s_awsize_mux)
            'd6:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:6], 6'd0} : {r_s_awaddr[6:6], 6'd0};
            'd5:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:5], 5'd0} : {r_s_awaddr[6:5], 5'd0};
            'd4:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:4], 4'd0} : {r_s_awaddr[6:4], 4'd0};
            'd3:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:3], 3'd0} : {r_s_awaddr[6:3], 3'd0};
            'd2:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:2], 2'd0} : {r_s_awaddr[6:2], 2'd0};
            'd1:     w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:1], 1'd0} : {r_s_awaddr[6:1], 1'd0};
            default: w_agg_cur_awaddr = ~r_s_wbusy_tt ? {I_S_AWADDR[6:0]} : {r_s_awaddr[6:0]};
        endcase

        case (w_s_awsize_mux)
            'd6:     w_agg_wr_en = &w_agg_cur_awaddr[6:6] | I_S_WLAST;
            'd5:     w_agg_wr_en = &w_agg_cur_awaddr[6:5] | I_S_WLAST;
            'd4:     w_agg_wr_en = &w_agg_cur_awaddr[6:4] | I_S_WLAST;
            'd3:     w_agg_wr_en = &w_agg_cur_awaddr[6:3] | I_S_WLAST;
            'd2:     w_agg_wr_en = &w_agg_cur_awaddr[6:2] | I_S_WLAST;
            'd1:     w_agg_wr_en = &w_agg_cur_awaddr[6:1] | I_S_WLAST;
            default: w_agg_wr_en = &w_agg_cur_awaddr[6:0] | I_S_WLAST;
        endcase

    end
end

endgenerate
assign w_agg_awlen = w_agg_awlen_ext[LEN_WD-1:0];
//----------------------------------------------------
//for AWSIZE to BYTES
always @ (*) begin
    case(w_s_awsize_mux)
    3'b000 : size_in_bytes = 8'd1;
    3'b001 : size_in_bytes = 8'd2;
    3'b010 : size_in_bytes = 8'd4;
    3'b011 : size_in_bytes = 8'd8;
    3'b100 : size_in_bytes = 8'd16;
    3'b101 : size_in_bytes = 8'd32;
    3'b110 : size_in_bytes = 8'd64;
    3'b111 : size_in_bytes = 8'd128;
    default : size_in_bytes = 8'd0;
    endcase
end

genvar j;
generate
  for (j = 0; j < STRB_WD; j = j + 1) begin : GEN_MASK
    assign nxt_masked_wdata[(j*8)+7 : j*8] = I_S_WSTRB[j] ? I_S_WDATA[(j*8)+7 : j*8] : 8'b0;
  end
endgenerate

//---------------------------------------------
//signal for aggregator operation
generate
if(DATA_WD == 256) begin
    assign w_en_aggregator_w = ~I_S_AWLOCK && I_S_AWCACHE[1] && (I_S_AWSIZE < 3'b101) & (|I_S_AWLEN);
end else if (DATA_WD == 512) begin
    assign w_en_aggregator_w = ~I_S_AWLOCK && I_S_AWCACHE[1] && (I_S_AWSIZE < 3'b110) & (|I_S_AWLEN);
end else if (DATA_WD == 1024) begin
    assign w_en_aggregator_w = ~I_S_AWLOCK && I_S_AWCACHE[1] && (I_S_AWSIZE < 3'b111) & (|I_S_AWLEN);
end else begin
    assign w_en_aggregator_w = 0;
end
endgenerate

always @ (*) begin
    O_M_AWID_RS    = I_S_AWID;
    O_M_AWADDR_RS  = I_S_AWADDR;
    O_M_AWBURST_RS = I_S_AWBURST;
    O_M_AWLOCK_RS  = I_S_AWLOCK;
    O_M_AWCACHE_RS = I_S_AWCACHE;
    O_M_AWPROT_RS  = I_S_AWPROT;
    O_M_AWQOS_RS   = I_S_AWQOS;
    O_M_AWVALID_RS = I_S_AWVALID & ~r_s_wbusy_tt;
    O_S_AWREADY = I_M_AWREADY_RS & ~r_s_wbusy_tt;

    if (w_en_aggregator_w_mux) begin
        O_M_AWLEN_RS   = w_agg_awlen;
        O_M_AWSIZE_RS  = AXSIZE;
    end else begin
        O_M_AWLEN_RS   = I_S_AWLEN;
        O_M_AWSIZE_RS  = I_S_AWSIZE;
    end     

    O_M_WLAST_FIFO_IN  = I_S_WLAST;
    O_S_WREADY  = ((~r_s_wbusy_tt & (I_S_AWVALID & O_S_AWREADY)) | r_s_wbusy_tt) & I_M_WREADY_FIFO_IN;
    if(w_en_aggregator_w_mux) begin
        O_M_WDATA_FIFO_IN    = w_cur_mem_wdata;
        O_M_WSTRB_FIFO_IN    = w_cur_mem_wstrb;
        O_M_WVALID_FIFO_IN   = w_agg_wr_en & ((~r_s_wbusy_tt & I_S_AWVALID & O_S_AWREADY) | r_s_wbusy_tt) & I_S_WVALID;
    end else begin
        O_M_WDATA_FIFO_IN  = I_S_WDATA;
        O_M_WSTRB_FIFO_IN  = I_S_WSTRB;
        O_M_WVALID_FIFO_IN = ((~r_s_wbusy_tt & I_S_AWVALID & O_S_AWREADY) | r_s_wbusy_tt) & I_S_WVALID;
    end
end

//========================================================================================
//                        LOGIC FOR READ TRANSACTION
//========================================================================================

always @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin

        r_rob_rid <= 'd0;
        r_rob_cur_burst_len <= 'd0;
        r_rob_s_rlast_send <= 'd0;
        r_m_rdata <= 'd0;
        r_m_rresp <= 'd0;
    end else begin
        if (|r_rob_cur_burst_len) begin
            if(I_S_RREADY)
                r_rob_cur_burst_len <= r_rob_cur_burst_len - 1;
        end
        else if (I_M_RVALID & O_M_RREADY) begin
            r_rob_rid               <= w_rob_rid              ;

            if ((w_rob_arsize > w_rob_org_arsize) & (|w_rob_org_arlen)) begin
                if(I_S_RREADY)
                    r_rob_cur_burst_len <= w_rob_cur_burst_len;

                r_rob_s_rlast_send  <= w_rob_s_rlast_send ;
                
                r_m_rdata <= I_M_RDATA;
                r_m_rresp <= I_M_RRESP;
            end else begin
                r_rob_cur_burst_len <= 'd0;
                r_rob_s_rlast_send  <= 'd0;
            end

        end 
    end
end

generate
if(DATA_WD==256) begin
    always @(*) begin
        case (I_S_ARSIZE)
            'd5:     w_agg_arlen_ext = {1'b0, I_S_ARLEN};
            'd4:     w_agg_arlen_ext = (I_S_ARADDR[4:4] + {1'b0, I_S_ARLEN}) >> 1;
            'd3:     w_agg_arlen_ext = (I_S_ARADDR[4:3] + {1'b0, I_S_ARLEN}) >> 2;
            'd2:     w_agg_arlen_ext = (I_S_ARADDR[4:2] + {1'b0, I_S_ARLEN}) >> 3;
            'd1:     w_agg_arlen_ext = (I_S_ARADDR[4:1] + {1'b0, I_S_ARLEN}) >> 4;
            default: w_agg_arlen_ext = (I_S_ARADDR[4:0] + {1'b0, I_S_ARLEN}) >> 5;
        endcase

    end

end else if(DATA_WD==512) begin
    always @(*) begin
        case (I_S_ARSIZE)
            'd6:     w_agg_arlen_ext = {1'b0, I_S_ARLEN};
            'd5:     w_agg_arlen_ext = (I_S_ARADDR[5:5] + {1'b0, I_S_ARLEN}) >> 1;
            'd4:     w_agg_arlen_ext = (I_S_ARADDR[5:4] + {1'b0, I_S_ARLEN}) >> 2;
            'd3:     w_agg_arlen_ext = (I_S_ARADDR[5:3] + {1'b0, I_S_ARLEN}) >> 3;
            'd2:     w_agg_arlen_ext = (I_S_ARADDR[5:2] + {1'b0, I_S_ARLEN}) >> 4;
            'd1:     w_agg_arlen_ext = (I_S_ARADDR[5:1] + {1'b0, I_S_ARLEN}) >> 5;
            default: w_agg_arlen_ext = (I_S_ARADDR[5:0] + {1'b0, I_S_ARLEN}) >> 6;
        endcase

    end
end else begin
    always @(*) begin
        case (I_S_ARSIZE)
            'd7:     w_agg_arlen_ext = {1'b0, I_S_ARLEN};
            'd6:     w_agg_arlen_ext = (I_S_ARADDR[6:6] + {1'b0, I_S_ARLEN}) >> 1;
            'd5:     w_agg_arlen_ext = (I_S_ARADDR[6:5] + {1'b0, I_S_ARLEN}) >> 2;
            'd4:     w_agg_arlen_ext = (I_S_ARADDR[6:4] + {1'b0, I_S_ARLEN}) >> 3;
            'd3:     w_agg_arlen_ext = (I_S_ARADDR[6:3] + {1'b0, I_S_ARLEN}) >> 4;
            'd2:     w_agg_arlen_ext = (I_S_ARADDR[6:2] + {1'b0, I_S_ARLEN}) >> 5;
            'd1:     w_agg_arlen_ext = (I_S_ARADDR[6:1] + {1'b0, I_S_ARLEN}) >> 6;
            default: w_agg_arlen_ext = (I_S_ARADDR[6:0] + {1'b0, I_S_ARLEN}) >> 7;
        endcase

    end
end

endgenerate
assign w_agg_arlen = w_agg_arlen_ext[LEN_WD-1:0];

reg [2:0] w_agg_arsize;

always @ (*) begin
    if(I_S_ARLEN == 0) begin
        w_agg_arsize = I_S_ARSIZE;
    end else begin
        w_agg_arsize = $clog2(DATA_WD/8);
    end
end

//===========================================================================================================================
//===========================================================================================================================
logic [$clog2(STRB_WD)-1:0] w_aggregator_araddr_align;

generate
if(DATA_WD == 1024) begin
always_comb begin
    case (I_S_ARSIZE)
        3'b000  : w_aggregator_araddr_align = I_S_ARADDR[$clog2(STRB_WD)-1:0];
        3'b001  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:1] , 1'b0};
        3'b010  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:2] , 2'b00};
        3'b011  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:3] , 3'b000};
        3'b100  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:4] , 4'b0000};
        3'b101  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:5] , 5'b00000};
        3'b110  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:6] , 6'b000000};
        3'b111  : w_aggregator_araddr_align = 7'b0000000;
        default : w_aggregator_araddr_align = '0; 
    endcase
end
end else if (DATA_WD == 512) begin
always_comb begin
    case (I_S_ARSIZE)
        3'b000  : w_aggregator_araddr_align = I_S_ARADDR[$clog2(STRB_WD)-1:0];
        3'b001  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:1] , 1'b0};
        3'b010  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:2] , 2'b00};
        3'b011  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:3] , 3'b000};
        3'b100  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:4] , 4'b0000};
        3'b101  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:5] , 5'b00000};
        3'b110  : w_aggregator_araddr_align = 6'b000000;
        default : w_aggregator_araddr_align = '0; 
    endcase
end
end else if (DATA_WD == 256) begin
always_comb begin
    case (I_S_ARSIZE)
        3'b000  : w_aggregator_araddr_align = I_S_ARADDR[$clog2(STRB_WD)-1:0];
        3'b001  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:1] , 1'b0};
        3'b010  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:2] , 2'b00};
        3'b011  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:3] , 3'b000};
        3'b100  : w_aggregator_araddr_align = { I_S_ARADDR[$clog2(STRB_WD)-1:4] , 4'b0000};
        3'b101  : w_aggregator_araddr_align = 5'b00000;
        default : w_aggregator_araddr_align = '0; 
    endcase
end
end

endgenerate


//Reorder Table
AOU_AGGREGATOR_INFO #(
    .AXI_DATA_WD              ( DATA_WD        ),
    .AXI_ID_WD                ( ID_WD          ),
    .AXI_LEN_WD               ( LEN_WD         ),
    .RD_MO_CNT                ( RD_MO_CNT      )

) reorder_table
(
    .I_CLK                    ( I_CLK       ),
    .I_RESETN                 ( I_RESETN    ),
    
    .I_AXI_ArId               ( I_S_ARID    ),
    .I_AXI_ArLen              ( w_agg_arlen ),
    .I_AXI_ArAddr_align       ( w_aggregator_araddr_align ),
    .I_AXI_ArSize             ( w_agg_arsize ),
    .I_ORIGINAL_ArLen         ( I_S_ARLEN   ),
    .I_ORIGINAL_ArSize        ( I_S_ARSIZE  ),
    .I_AXI_ArValid            ( I_S_ARVALID & w_rob_ar_slot_avail_flag ),
    .I_AXI_ArReady            ( O_S_ARREADY ),
    
    .I_AXI_RId                ( I_M_RID     ),
    .I_AXI_RLast              ( I_M_RLAST   ),
    .I_AXI_RValid             ( I_M_RVALID  ),
    .I_AXI_RReady             ( O_M_RREADY  ),
    .O_AR_Slot_Available_Flag ( w_rob_ar_slot_avail_flag ),
    
    .O_ReorderBuf_MValid      (             ),
    .O_ReorderBuf_MData       ( {w_rob_rid, w_rob_araddr, w_rob_arsize, w_rob_org_arlen, w_rob_org_arsize, w_rob_cur_burst_len, w_rob_s_rlast_send}),
    
    .O_DEST_TABLE_ID_ERR      ( O_DEST_TABLE_RID_ERR      )

);
assign O_AGGRE_MISMATCH_RID = I_M_RID;
//=====================================================================================
// transport to slave logic
//=====================================================================================
assign  O_M_ARID = I_S_ARID;
assign  O_M_ARADDR = I_S_ARADDR;
assign  O_M_ARLEN = w_agg_arlen;
assign  O_M_ARSIZE = w_agg_arsize;
assign  O_M_ARBURST = I_S_ARBURST;
assign  O_M_ARCACHE = I_S_ARCACHE;
assign  O_M_ARPROT = I_S_ARPROT;
assign  O_M_ARLOCK = I_S_ARLOCK;
assign  O_M_ARQOS = I_S_ARQOS;
assign  O_M_ARVALID = I_S_ARVALID & w_rob_ar_slot_avail_flag;
assign  O_S_ARREADY = I_M_ARREADY & w_rob_ar_slot_avail_flag;

assign  O_S_RID    = (|r_rob_cur_burst_len) ? r_rob_rid : I_M_RID;
assign  O_S_RDATA  = (|r_rob_cur_burst_len) ? r_m_rdata : I_M_RDATA;
assign  O_S_RRESP  = (|r_rob_cur_burst_len) ? r_m_rresp : I_M_RRESP;
assign  O_S_RLAST  = ((r_rob_cur_burst_len == 1) & r_rob_s_rlast_send) ? 1'b1: 
                     ((r_rob_cur_burst_len == 0) & ~((w_rob_arsize > w_rob_org_arsize) & (|w_rob_org_arlen))) ? I_M_RLAST :
                     ((r_rob_cur_burst_len == 0) & ((w_rob_arsize > w_rob_org_arsize) & (|w_rob_org_arlen)) & (w_rob_cur_burst_len == 0)) ? w_rob_s_rlast_send  : 1'b0;
                    
assign  O_S_RVALID = (|r_rob_cur_burst_len) ? 1'b1      : I_M_RVALID;
assign  O_M_RREADY = (|r_rob_cur_burst_len) ? 1'b0      : I_S_RREADY;
    

//=====================================================================================
//   AW_FWD_RS, and WFIFO for WDATA aggregation
//=====================================================================================

localparam AOU_AGG_AWCH_PAYLOAD_WD = ID_WD + ADDR_WD + LEN_WD + 3 + 2 + 1 + 4 + 3 + 4 + 1;  // + 1 for w_en_aggregator_w_mux_rs_out
wire [AOU_AGG_AWCH_PAYLOAD_WD - 1:0] w_aou_agg_awch_rs_sdata;
wire [AOU_AGG_AWCH_PAYLOAD_WD - 1:0] w_aou_agg_awch_rs_mdata;
wire                                 w_aou_agg_awch_rs_mvalid;
wire                                 w_aou_agg_awch_rs_mready;

wire                                 w_en_aggregator_w_mux_rs_out;
wire                                 w_write_op_halt;
wire                                 o_m_awvalid_tmp;
wire                                 i_m_awready_tmp;
wire                                 o_m_wvalid_tmp;
wire                                 i_m_wready_tmp;

assign w_aou_agg_awch_rs_sdata = {w_en_aggregator_w_mux, 
                                  O_M_AWID_RS,
                                  O_M_AWADDR_RS,
                                  O_M_AWLEN_RS,
                                  O_M_AWSIZE_RS,
                                  O_M_AWBURST_RS,
                                  O_M_AWLOCK_RS,
                                  O_M_AWCACHE_RS,
                                  O_M_AWPROT_RS,
                                  O_M_AWQOS_RS};
 
assign {w_en_aggregator_w_mux_rs_out,
        O_M_AWID,
        O_M_AWADDR,
        O_M_AWLEN,
        O_M_AWSIZE,
        O_M_AWBURST,
        O_M_AWLOCK,
        O_M_AWCACHE,
        O_M_AWPROT,
        O_M_AWQOS} = w_aou_agg_awch_rs_mdata;

AOU_FWD_RS #(
    .DATA_WIDTH         (AOU_AGG_AWCH_PAYLOAD_WD)
) u_aou_agg_awch_rs
(
    .I_CLK              ( I_CLK                    ),
    .I_RESETN           ( I_RESETN                 ),

    .I_SVALID           ( O_M_AWVALID_RS           ),
    .O_SREADY           ( I_M_AWREADY_RS           ),
    .I_SDATA            ( w_aou_agg_awch_rs_sdata  ),

    .O_MVALID           ( o_m_awvalid_tmp          ),
    .I_MREADY           ( i_m_awready_tmp          ),
    .O_MDATA            ( w_aou_agg_awch_rs_mdata  )
);

//----------------------------------------------------
localparam AOU_AGG_WCH_PAYLOAD_WD = DATA_WD + STRB_WD + 1; 
localparam WCH_FIFO_FULL_CNT_WD   = $clog2(AOU_AGG_WCH_FIFO_DEPTH + 1); 

wire [AOU_AGG_WCH_PAYLOAD_WD - 1:0] w_aou_agg_wch_fifo_sdata;
wire [AOU_AGG_WCH_PAYLOAD_WD - 1:0] w_aou_agg_wch_fifo_mdata;
wire                                w_aou_agg_wch_fifo_mvalid;
wire                                w_aou_agg_wch_fifo_mready;

assign w_aou_agg_wch_fifo_sdata = {O_M_WDATA_FIFO_IN, 
                                   O_M_WSTRB_FIFO_IN, 
                                   O_M_WLAST_FIFO_IN};

assign {O_M_WDATA, 
        O_M_WSTRB, 
        O_M_WLAST} = w_aou_agg_wch_fifo_mdata;

wire [WCH_FIFO_FULL_CNT_WD-1:0] w_wch_fifo_full_cnt;

AOU_SYNC_FIFO_REG #(
    .FIFO_WIDTH         ( AOU_AGG_WCH_PAYLOAD_WD    ),
    .FIFO_DEPTH         ( AOU_AGG_WCH_FIFO_DEPTH    )
) u_wch_regfifo
(
    .I_CLK              ( I_CLK                     ),
    .I_RESETN           ( I_RESETN                  ),

    .I_SVALID           ( O_M_WVALID_FIFO_IN        ),
    .O_SREADY           ( I_M_WREADY_FIFO_IN        ),
    .I_SDATA            ( w_aou_agg_wch_fifo_sdata  ),

    .O_MVALID           ( o_m_wvalid_tmp            ),
    .I_MREADY           ( i_m_wready_tmp            ),
    .O_MDATA            ( w_aou_agg_wch_fifo_mdata  ),

    .O_EMPTY_CNT        (                           ),
    .O_FULL_CNT         ( w_wch_fifo_full_cnt       ) 
);

//----------------------------------------------------
localparam ST_IDLE = 2'b00;
localparam ST_HALT = 2'b01;
localparam ST_SEND = 2'b10;

reg [1:0] r_cur_st, nxt_st;

always @(*) begin
    case (r_cur_st)
        ST_IDLE : 
            if (o_m_awvalid_tmp & w_en_aggregator_w_mux_rs_out & ({3'd0, w_wch_fifo_full_cnt} < (O_M_AWLEN + 1)))
                nxt_st = ST_HALT ;
            else
                nxt_st = r_cur_st ;
        ST_HALT :
            if ({3'd0, w_wch_fifo_full_cnt} > O_M_AWLEN)
                nxt_st = ST_SEND ;
            else
                nxt_st = r_cur_st ;
        ST_SEND :
            if (O_M_WLAST & O_M_WVALID & I_M_WREADY)
                nxt_st = ST_IDLE;
            else
                nxt_st = r_cur_st ;
        default :
            nxt_st = ST_IDLE;
    endcase
end

always @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_cur_st <= ST_IDLE; 
    end else begin
        r_cur_st <= nxt_st; 
    end
end

assign w_write_op_halt = ((r_cur_st == ST_IDLE) & (o_m_awvalid_tmp & w_en_aggregator_w_mux_rs_out & ({3'd0, w_wch_fifo_full_cnt} < (O_M_AWLEN + 1)))) | ((r_cur_st == ST_HALT) & ({3'd0, w_wch_fifo_full_cnt} <= O_M_AWLEN));

assign O_M_AWVALID     = ~w_write_op_halt & o_m_awvalid_tmp;
assign i_m_awready_tmp = ~w_write_op_halt & I_M_AWREADY ;
assign O_M_WVALID      = ~w_write_op_halt & o_m_wvalid_tmp;
assign i_m_wready_tmp  = ~w_write_op_halt & I_M_WREADY ;


endmodule
