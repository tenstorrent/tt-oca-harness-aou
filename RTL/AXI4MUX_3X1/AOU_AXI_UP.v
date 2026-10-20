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
//  Module     : AOU_AXI_UP
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps
module AOU_AXI_UP #(
    parameter       I_DATA_WD      = 128,
                    O_DATA_WD      = 32,
                    ADDR_WD        = 32,
                    ID_WD          = 4,
                    SIZE_WD        = 3,
                    RESP_WD        = 2,
                    BURST_WD       = 2,
                    CACHE_WD       = 4,
                    PROT_WD        = 3,
                    STRB_WD        = I_DATA_WD / 8,
                    O_STRB_WD      = O_DATA_WD / 8,
                    LEN_WD         = 4
)
(
    // Slave I/F    =================================================
    input                                                  I_CLK,
    input                                                  I_RESETN,

    input        [ID_WD-1:0]                               I_S_ARID,
    input        [ADDR_WD-1:0]                             I_S_ARADDR,
    input        [SIZE_WD-1:0]                             I_S_ARSIZE,
    input        [BURST_WD-1:0]                            I_S_ARBURST,
    input        [CACHE_WD-1:0]                            I_S_ARCACHE,
    input        [PROT_WD-1:0]                             I_S_ARPROT,
    input        [LEN_WD-1:0]                              I_S_ARLEN,
    input                                                  I_S_ARLOCK,
    input        [3:0]                                     I_S_ARQOS,
    input                                                  I_S_ARVALID,
    output                                                 O_S_ARREADY,

    output       [ID_WD-1:0]                               O_S_RID,
    output       [I_DATA_WD-1:0]                           O_S_RDATA,
    output       [RESP_WD-1:0]                             O_S_RRESP,
    output                                                 O_S_RLAST,
    output                                                 O_S_RVALID,
    input                                                  I_S_RREADY,
    
    input        [ID_WD-1:0]                               I_S_AWID,
    input        [ADDR_WD-1:0]                             I_S_AWADDR,
    input        [LEN_WD-1:0]                              I_S_AWLEN,
    input        [SIZE_WD-1:0]                             I_S_AWSIZE,
    input        [BURST_WD-1:0]                            I_S_AWBURST,
    input                                                  I_S_AWLOCK,
    input        [CACHE_WD-1:0]                            I_S_AWCACHE,
    input        [PROT_WD-1:0]                             I_S_AWPROT,
    input        [3:0]                                     I_S_AWQOS,
    input                                                  I_S_AWVALID,
    output                                                 O_S_AWREADY,

    input        [I_DATA_WD-1:0]                           I_S_WDATA,
    input        [STRB_WD-1:0]                             I_S_WSTRB,  
    input                                                  I_S_WLAST,
    input                                                  I_S_WVALID,
    output                                                 O_S_WREADY,
    
    output       [ID_WD-1:0]                               O_S_BID,
    output       [RESP_WD-1:0]                             O_S_BRESP,
    output                                                 O_S_BVALID,
    input                                                  I_S_BREADY,

    // Master I/F   =================================================
    input                                                  I_M_ARREADY,
    output                                                 O_M_ARVALID,
    output       [ADDR_WD-1:0]                             O_M_ARADDR,
    output       [SIZE_WD-1:0]                             O_M_ARSIZE,
    output       [BURST_WD-1:0]                            O_M_ARBURST,
    output       [CACHE_WD-1:0]                            O_M_ARCACHE,
    output       [PROT_WD-1:0]                             O_M_ARPROT,
    output       [ID_WD-1:0]                               O_M_ARID,
    output       [LEN_WD-1:0]                              O_M_ARLEN,
    output                                                 O_M_ARLOCK,
    output       [3:0]                                     O_M_ARQOS,

    input        [ID_WD-1:0]                               I_M_RID,
    input        [O_DATA_WD-1:0]                           I_M_RDATA,
    input        [RESP_WD-1:0]                             I_M_RRESP,
    input                                                  I_M_RLAST,
    input        [ADDR_WD-1:0]                             I_M_ADDR_CNT,
    input                                                  I_M_RVALID,
    output                                                 O_M_RREADY,

    output       [ID_WD-1:0]                               O_M_AWID,
    output       [ADDR_WD-1:0]                             O_M_AWADDR,
    output       [LEN_WD-1:0]                              O_M_AWLEN,
    output       [SIZE_WD-1:0]                             O_M_AWSIZE,
    output       [BURST_WD-1:0]                            O_M_AWBURST,
    output                                                 O_M_AWLOCK,
    output       [CACHE_WD-1:0]                            O_M_AWCACHE,
    output       [PROT_WD-1:0]                             O_M_AWPROT,
    output       [3:0]                                     O_M_AWQOS,
    output                                                 O_M_AWVALID,
    input                                                  I_M_AWREADY,      

    output       [O_DATA_WD-1:0]                           O_M_WDATA,
    output       [O_STRB_WD-1:0]                           O_M_WSTRB,
    output                                                 O_M_WLAST,
    output                                                 O_M_WVALID,
    input                                                  I_M_WREADY,

    input        [ID_WD-1:0]                               I_M_BID,
    input        [RESP_WD-1:0]                             I_M_BRESP,
    input                                                  I_M_BVALID,
    output                                                 O_M_BREADY
     
);

localparam  FIFO_DEPTH  = 32;

wire                    w_aw_fifo_ready;
wire    [LEN_WD-1:0]    w_o_m_awlen;
reg                     w_o_m_wlast;

wire                    w_ar_pending_info_valid, w_ar_fifo_ready;

// =============================================================================
// ==== WRITE channel modules ==================================================
// =============================================================================
assign  {O_M_AWID, O_M_AWADDR, O_M_AWLEN, O_M_AWSIZE, O_M_AWBURST, O_M_AWLOCK, O_M_AWCACHE, O_M_AWPROT, O_M_AWQOS} = 
            {I_S_AWID, I_S_AWADDR, I_S_AWLEN, I_S_AWSIZE, I_S_AWBURST, I_S_AWLOCK, I_S_AWCACHE, I_S_AWPROT, I_S_AWQOS};

//1, 2, 4, 8, 16, 32, 64, 128 Byte transfer

localparam I_BYTES = $clog2(STRB_WD);
localparam O_BYTES = $clog2(O_STRB_WD);

localparam SUPPORT_AWSIZE_0 = (I_DATA_WD >= (8<<0)) && (O_DATA_WD >=(8<<0));
localparam SUPPORT_AWSIZE_1 = (I_DATA_WD >= (8<<1)) && (O_DATA_WD >=(8<<1));
localparam SUPPORT_AWSIZE_2 = (I_DATA_WD >= (8<<2)) && (O_DATA_WD >=(8<<2));
localparam SUPPORT_AWSIZE_3 = (I_DATA_WD >= (8<<3)) && (O_DATA_WD >=(8<<3));
localparam SUPPORT_AWSIZE_4 = (I_DATA_WD >= (8<<4)) && (O_DATA_WD >=(8<<4));
localparam SUPPORT_AWSIZE_5 = (I_DATA_WD >= (8<<5)) && (O_DATA_WD >=(8<<5));
localparam SUPPORT_AWSIZE_6 = (I_DATA_WD >= (8<<6)) && (O_DATA_WD >=(8<<6));
localparam SUPPORT_AWSIZE_7 = (I_DATA_WD >= (8<<7)) && (O_DATA_WD >=(8<<7));

reg  [O_DATA_WD - 1: 0]                            w_modified_wdata_sdata;
wire [O_DATA_WD - 1: 0]                            w_modified_wdata_mdata;
reg  [O_STRB_WD - 1: 0]                            w_modified_wstrb_sdata;
wire [O_STRB_WD - 1: 0]                            w_modified_wstrb_mdata;

reg  [SIZE_WD-1:0]                                 r_awsize;
reg  [ADDR_WD:0]                                   r_addr;
wire [SIZE_WD-1:0]                                 w_cur_awsize;
wire [ADDR_WD-1:0]                                 w_cur_addr;
wire [ADDR_WD-1:0]                                 w_cur_inc_bytes;
 
assign w_cur_addr   = (I_S_AWVALID & O_S_AWREADY) ? I_S_AWADDR : r_addr[ADDR_WD-1:0];
assign w_cur_awsize = (I_S_AWVALID & O_S_AWREADY) ? I_S_AWSIZE : r_awsize;
assign w_cur_inc_bytes = ({{(ADDR_WD-1){1'b0}},1'b1}) << w_cur_awsize;

always @ (posedge I_CLK or negedge I_RESETN) begin
    if(!I_RESETN) begin
        r_addr <= 'd0;
        r_awsize <= 'd0;
    end else begin
        if (I_S_AWVALID & O_S_AWREADY) begin
            r_awsize <= I_S_AWSIZE;
            r_addr   <= (w_cur_addr & ~((1<<w_cur_awsize)-1)) + w_cur_inc_bytes;
        end else if (I_S_WVALID & O_S_WREADY) begin
            r_addr   <= w_cur_addr + w_cur_inc_bytes;
        end
    end
end

reg [ADDR_WD-1:0] dst_lane, src_lane;

generate 

if(I_DATA_WD==256) begin
    always @ (*) begin
        w_modified_wdata_sdata = {O_DATA_WD{1'b0}};
        w_modified_wstrb_sdata = {O_STRB_WD{1'b0}};
        dst_lane               = 0;
        src_lane               = 0;
        
        case (w_cur_awsize)
        0: begin
            dst_lane = (w_cur_addr >> 0) & ((1<< (O_BYTES-0))-1);
            src_lane = (w_cur_addr >> 0) & ((1<< (I_BYTES-0))-1);
            if(SUPPORT_AWSIZE_0) begin
            w_modified_wdata_sdata[(dst_lane*8) +: 8] = I_S_WDATA[(src_lane*8) +: 8];
            w_modified_wstrb_sdata[(dst_lane[O_BYTES-1:0]*1) +: 1] = I_S_WSTRB[(src_lane[I_BYTES-1:0]*1) +: 1];
            end
        end
        1: begin
            dst_lane = (w_cur_addr >> 1) & ((1<< (O_BYTES-1))-1);
            src_lane = (w_cur_addr >> 1) & ((1<< (I_BYTES-1))-1);
            if(SUPPORT_AWSIZE_1) begin
            w_modified_wdata_sdata[(dst_lane*16) +: 16] = I_S_WDATA[(src_lane*16) +: 16];
            w_modified_wstrb_sdata[(dst_lane*2) +: 2] = I_S_WSTRB[(src_lane*2) +: 2];
            end
        end
        2: begin
            dst_lane = (w_cur_addr >> 2) & ((1<< (O_BYTES-2))-1);
            src_lane = (w_cur_addr >> 2) & ((1<< (I_BYTES-2))-1);
            if(SUPPORT_AWSIZE_2) begin
            w_modified_wdata_sdata[(dst_lane*32) +: 32] = I_S_WDATA[(src_lane*32) +: 32];
            w_modified_wstrb_sdata[(dst_lane*4) +: 4] = I_S_WSTRB[(src_lane*4) +: 4];
            end
        end
        3: begin
            dst_lane = (w_cur_addr >> 3) & ((1<< (O_BYTES-3))-1);
            src_lane = (w_cur_addr >> 3) & ((1<< (I_BYTES-3))-1);
            if(SUPPORT_AWSIZE_3) begin
            w_modified_wdata_sdata[(dst_lane*64) +: 64] = I_S_WDATA[(src_lane*64) +: 64];
            w_modified_wstrb_sdata[(dst_lane*8) +: 8] = I_S_WSTRB[(src_lane*8) +: 8];
            end    
        end
        4: begin
            dst_lane = (w_cur_addr >> 4) & ((1<< (O_BYTES-4))-1);
            src_lane = (w_cur_addr >> 4) & ((1<< (I_BYTES-4))-1);
            if(SUPPORT_AWSIZE_4) begin
            w_modified_wdata_sdata[(dst_lane*128) +: 128] = I_S_WDATA[(src_lane*128) +: 128];
            w_modified_wstrb_sdata[(dst_lane*16) +: 16] = I_S_WSTRB[(src_lane*16) +: 16];
            end
        end
        5: begin
            dst_lane = (w_cur_addr >> 5) & ((1<< (O_BYTES-5))-1);
            src_lane = (w_cur_addr >> 5) & ((1<< (I_BYTES-5))-1);
            if(SUPPORT_AWSIZE_5) begin
            w_modified_wdata_sdata[(dst_lane*256) +: 256] = I_S_WDATA[(src_lane*256) +: 256];
            w_modified_wstrb_sdata[(dst_lane*32) +: 32] = I_S_WSTRB[(src_lane*32) +: 32];
            end
        end
        default: begin
            w_modified_wdata_sdata[I_DATA_WD-1:0] = I_S_WDATA;
            w_modified_wstrb_sdata[STRB_WD-1:0]   = I_S_WSTRB;
        end
        endcase
    end
end else if (I_DATA_WD==512) begin
    always @ (*) begin
        w_modified_wdata_sdata = {O_DATA_WD{1'b0}};
        w_modified_wstrb_sdata = {O_STRB_WD{1'b0}};
        dst_lane               = 0;
        src_lane               = 0;
        
        case (w_cur_awsize)
        0: begin
            dst_lane = (w_cur_addr >> 0) & ((1<< (O_BYTES-0))-1);
            src_lane = (w_cur_addr >> 0) & ((1<< (I_BYTES-0))-1);
            if(SUPPORT_AWSIZE_0) begin
            w_modified_wdata_sdata[(dst_lane*8) +: 8] = I_S_WDATA[(src_lane*8) +: 8];
            w_modified_wstrb_sdata[(dst_lane[O_BYTES-1:0]*1) +: 1] = I_S_WSTRB[(src_lane[I_BYTES-1:0]*1) +: 1];
            end
        end
        1: begin
            dst_lane = (w_cur_addr >> 1) & ((1<< (O_BYTES-1))-1);
            src_lane = (w_cur_addr >> 1) & ((1<< (I_BYTES-1))-1);
            if(SUPPORT_AWSIZE_1) begin
            w_modified_wdata_sdata[(dst_lane*16) +: 16] = I_S_WDATA[(src_lane*16) +: 16];
            w_modified_wstrb_sdata[(dst_lane*2) +: 2] = I_S_WSTRB[(src_lane*2) +: 2];
            end
        end
        2: begin
            dst_lane = (w_cur_addr >> 2) & ((1<< (O_BYTES-2))-1);
            src_lane = (w_cur_addr >> 2) & ((1<< (I_BYTES-2))-1);
            if(SUPPORT_AWSIZE_2) begin
            w_modified_wdata_sdata[(dst_lane*32) +: 32] = I_S_WDATA[(src_lane*32) +: 32];
            w_modified_wstrb_sdata[(dst_lane*4) +: 4] = I_S_WSTRB[(src_lane*4) +: 4];
            end
        end
        3: begin
            dst_lane = (w_cur_addr >> 3) & ((1<< (O_BYTES-3))-1);
            src_lane = (w_cur_addr >> 3) & ((1<< (I_BYTES-3))-1);
            if(SUPPORT_AWSIZE_3) begin
            w_modified_wdata_sdata[(dst_lane*64) +: 64] = I_S_WDATA[(src_lane*64) +: 64];
            w_modified_wstrb_sdata[(dst_lane*8) +: 8] = I_S_WSTRB[(src_lane*8) +: 8];
            end    
        end
        4: begin
            dst_lane = (w_cur_addr >> 4) & ((1<< (O_BYTES-4))-1);
            src_lane = (w_cur_addr >> 4) & ((1<< (I_BYTES-4))-1);
            if(SUPPORT_AWSIZE_4) begin
            w_modified_wdata_sdata[(dst_lane*128) +: 128] = I_S_WDATA[(src_lane*128) +: 128];
            w_modified_wstrb_sdata[(dst_lane*16) +: 16] = I_S_WSTRB[(src_lane*16) +: 16];
            end
        end
        5: begin
            dst_lane = (w_cur_addr >> 5) & ((1<< (O_BYTES-5))-1);
            src_lane = (w_cur_addr >> 5) & ((1<< (I_BYTES-5))-1);
            if(SUPPORT_AWSIZE_5) begin
            w_modified_wdata_sdata[(dst_lane*256) +: 256] = I_S_WDATA[(src_lane*256) +: 256];
            w_modified_wstrb_sdata[(dst_lane*32) +: 32] = I_S_WSTRB[(src_lane*32) +: 32];
            end
        end
        6: begin
            dst_lane = (w_cur_addr >> 6) & ((1<< (O_BYTES-6))-1);
            src_lane = (w_cur_addr >> 6) & ((1<< (I_BYTES-6))-1);
            if(SUPPORT_AWSIZE_6) begin
            w_modified_wdata_sdata[(dst_lane*512) +: 512] = I_S_WDATA[(src_lane*512) +: 512];
            w_modified_wstrb_sdata[(dst_lane*64) +: 64] = I_S_WSTRB[(src_lane*64) +: 64];
            end
        end
        default: begin
            w_modified_wdata_sdata[I_DATA_WD-1:0] = I_S_WDATA;
            w_modified_wstrb_sdata[STRB_WD-1:0]   = I_S_WSTRB;
        end
        endcase
    end
end else if (I_DATA_WD==1024)begin
    always @ (*) begin
        w_modified_wdata_sdata = {O_DATA_WD{1'b0}};
        w_modified_wstrb_sdata = {O_STRB_WD{1'b0}};
        dst_lane               = 0;
        src_lane               = 0;
        
        case (w_cur_awsize)
        0: begin
            dst_lane = (w_cur_addr >> 0) & ((1<< (O_BYTES-0))-1);
            src_lane = (w_cur_addr >> 0) & ((1<< (I_BYTES-0))-1);
            if(SUPPORT_AWSIZE_0) begin
            w_modified_wdata_sdata[(dst_lane*8) +: 8] = I_S_WDATA[(src_lane*8) +: 8];
            w_modified_wstrb_sdata[(dst_lane[O_BYTES-1:0]*1) +: 1] = I_S_WSTRB[(src_lane[I_BYTES-1:0]*1) +: 1];
            end
        end
        1: begin
            dst_lane = (w_cur_addr >> 1) & ((1<< (O_BYTES-1))-1);
            src_lane = (w_cur_addr >> 1) & ((1<< (I_BYTES-1))-1);
            if(SUPPORT_AWSIZE_1) begin
            w_modified_wdata_sdata[(dst_lane*16) +: 16] = I_S_WDATA[(src_lane*16) +: 16];
            w_modified_wstrb_sdata[(dst_lane*2) +: 2] = I_S_WSTRB[(src_lane*2) +: 2];
            end
        end
        2: begin
            dst_lane = (w_cur_addr >> 2) & ((1<< (O_BYTES-2))-1);
            src_lane = (w_cur_addr >> 2) & ((1<< (I_BYTES-2))-1);
            if(SUPPORT_AWSIZE_2) begin
            w_modified_wdata_sdata[(dst_lane*32) +: 32] = I_S_WDATA[(src_lane*32) +: 32];
            w_modified_wstrb_sdata[(dst_lane*4) +: 4] = I_S_WSTRB[(src_lane*4) +: 4];
            end
        end
        3: begin
            dst_lane = (w_cur_addr >> 3) & ((1<< (O_BYTES-3))-1);
            src_lane = (w_cur_addr >> 3) & ((1<< (I_BYTES-3))-1);
            if(SUPPORT_AWSIZE_3) begin
            w_modified_wdata_sdata[(dst_lane*64) +: 64] = I_S_WDATA[(src_lane*64) +: 64];
            w_modified_wstrb_sdata[(dst_lane*8) +: 8] = I_S_WSTRB[(src_lane*8) +: 8];
            end    
        end
        4: begin
            dst_lane = (w_cur_addr >> 4) & ((1<< (O_BYTES-4))-1);
            src_lane = (w_cur_addr >> 4) & ((1<< (I_BYTES-4))-1);
            if(SUPPORT_AWSIZE_4) begin
            w_modified_wdata_sdata[(dst_lane*128) +: 128] = I_S_WDATA[(src_lane*128) +: 128];
            w_modified_wstrb_sdata[(dst_lane*16) +: 16] = I_S_WSTRB[(src_lane*16) +: 16];
            end
        end
        5: begin
            dst_lane = (w_cur_addr >> 5) & ((1<< (O_BYTES-5))-1);
            src_lane = (w_cur_addr >> 5) & ((1<< (I_BYTES-5))-1);
            if(SUPPORT_AWSIZE_5) begin
            w_modified_wdata_sdata[(dst_lane*256) +: 256] = I_S_WDATA[(src_lane*256) +: 256];
            w_modified_wstrb_sdata[(dst_lane*32) +: 32] = I_S_WSTRB[(src_lane*32) +: 32];
            end
        end
        6: begin
            dst_lane = (w_cur_addr >> 6) & ((1<< (O_BYTES-6))-1);
            src_lane = (w_cur_addr >> 6) & ((1<< (I_BYTES-6))-1);
            if(SUPPORT_AWSIZE_6) begin
            w_modified_wdata_sdata[(dst_lane*512) +: 512] = I_S_WDATA[(src_lane*512) +: 512];
            w_modified_wstrb_sdata[(dst_lane*64) +: 64] = I_S_WSTRB[(src_lane*64) +: 64];
            end
        end
        7: begin
            dst_lane = (w_cur_addr >> 7) & ((1<< (O_BYTES-7))-1);
            src_lane = (w_cur_addr >> 7) & ((1<< (I_BYTES-7))-1);
            if(SUPPORT_AWSIZE_7) begin
            w_modified_wdata_sdata[(dst_lane*1024) +: 1024] = I_S_WDATA[(src_lane*1024) +: 1024];
            w_modified_wstrb_sdata[(dst_lane*128) +: 128] = I_S_WSTRB[(src_lane*128) +: 128];
            end
        end
        default: begin
            w_modified_wdata_sdata[I_DATA_WD-1:0] = I_S_WDATA;
            w_modified_wstrb_sdata[STRB_WD-1:0]   = I_S_WSTRB;
        end
        endcase
    end
end
endgenerate


//  W CH ==================================================
//  AW CH ==================================================
`ifdef AXI_UP_RS_EN

//FIFO for AWLEN
AOU_SYNC_FIFO_REG #(
    .FIFO_WIDTH         (LEN_WD),
    .FIFO_DEPTH         (FIFO_DEPTH)
) 
u_aw_fifo (
    .I_CLK              (I_CLK) , 
    .I_RESETN           (I_RESETN) ,

    .I_SVALID           (I_S_AWVALID && O_S_AWREADY),
    .I_SDATA            (O_M_AWLEN),
    .O_SREADY           (w_aw_fifo_ready),
 
    .I_MREADY           (O_M_WVALID && I_M_WREADY && O_M_WLAST),
    .O_MDATA            (w_o_m_awlen),                        //return O_M_AWLEN
    .O_MVALID           (),

    .O_EMPTY_CNT        (),     
    .O_FULL_CNT         ()   
);

reg     [LEN_WD:0]      r_wr_cnt;

always @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_wr_cnt <= 'b0;
    end else if (O_M_WVALID && I_M_WREADY) begin
        if (r_wr_cnt == {1'b0, w_o_m_awlen}) begin
            r_wr_cnt <= 'b0;
        end else begin
            r_wr_cnt <= r_wr_cnt + 1;
        end
    end
end

AOU_FWD_RS #(
    .DATA_WIDTH        (O_DATA_WD + O_STRB_WD)
)
u_w_data_fifo_wdata(
    .I_CLK              (I_CLK), 
    .I_RESETN           (I_RESETN),

    .I_SVALID           (I_S_WVALID),
    .I_SDATA            ({w_modified_wdata_sdata, w_modified_wstrb_sdata} ),
    .O_SREADY           (O_S_WREADY),

    .I_MREADY           (I_M_WREADY),     //maybe add last signal with AWLEN     
    .O_MDATA            ({w_modified_wdata_mdata, w_modified_wstrb_mdata}),
    .O_MVALID           (O_M_WVALID)
);


assign O_M_WDATA = w_modified_wdata_mdata;
assign O_M_WSTRB = w_modified_wstrb_mdata;

assign w_o_m_wlast = (r_wr_cnt == {1'b0, w_o_m_awlen});
assign O_M_WLAST    = w_o_m_wlast;

assign O_S_AWREADY  = I_M_AWREADY && w_aw_fifo_ready;
assign O_M_AWVALID  = I_S_AWVALID && w_aw_fifo_ready;

`else
assign O_M_WLAST    = I_S_WLAST;
assign O_S_WREADY   = I_M_WREADY; 
assign O_M_WVALID   = I_S_WVALID;
assign O_M_WDATA    = w_modified_wdata_sdata;
assign O_M_WSTRB    = w_modified_wstrb_sdata;

assign O_S_AWREADY  = I_M_AWREADY; 
assign O_M_AWVALID  = I_S_AWVALID; 
`endif

// =============================================================================
// ==== READ channel modules ===================================================
// =============================================================================
assign  {O_M_ARID, O_M_ARADDR, O_M_ARLEN, O_M_ARSIZE, O_M_ARBURST, O_M_ARLOCK, O_M_ARCACHE, O_M_ARPROT, O_M_ARQOS} = 
            {I_S_ARID, I_S_ARADDR, I_S_ARLEN, I_S_ARSIZE, I_S_ARBURST, I_S_ARLOCK, I_S_ARCACHE, I_S_ARPROT, I_S_ARQOS};
    
localparam DATA_START_IDX_WD = $clog2(O_DATA_WD/I_DATA_WD); 

wire [O_DATA_WD/I_DATA_WD - 1:0][I_DATA_WD - 1: 0] rdata_2d;
wire [DATA_START_IDX_WD -1:0] w_start_idx;
assign rdata_2d = I_M_RDATA;


assign w_start_idx = I_M_ADDR_CNT[$clog2(O_DATA_WD/8)-1:$clog2(I_DATA_WD/8)];


//  B CH ==================================================
assign O_S_BID      = I_M_BID;
assign O_S_BRESP    = I_M_BRESP;
assign O_S_BVALID   = I_M_BVALID;
assign O_M_BREADY   = I_S_BREADY;

//  AR CH ==================================================
assign O_S_ARREADY = I_M_ARREADY;
assign O_M_ARVALID = I_S_ARVALID;

//  R CH ==================================================
assign O_S_RDATA  = rdata_2d[w_start_idx];
assign O_S_RID    = I_M_RID;
assign O_S_RLAST  = I_M_RLAST;
assign O_S_RRESP  = I_M_RRESP;
assign O_S_RVALID = I_M_RVALID;
assign O_M_RREADY = I_S_RREADY;

endmodule
