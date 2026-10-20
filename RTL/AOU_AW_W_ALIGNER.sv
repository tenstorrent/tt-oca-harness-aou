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
//  Module     : AOU_AW_W_ALIGNER
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AW_W_ALIGNER #(
    parameter   AXI_SLV_NUM  = 2,
    localparam  RP_SEL_WD = ( AXI_SLV_NUM == 1) ? 1: $clog2(AXI_SLV_NUM),  
    parameter   AXI_DATA_WD   = 512,
    parameter   AXI_ADDR_WD   = 64,
    parameter   AXI_ID_WD     = 2,
    parameter   AXI_QOS_WD    = 4,
    localparam  AXI_STRB_WD   = AXI_DATA_WD / 8,
    parameter   AXI_LEN_WD    = 8
)
(
    input                                               I_CLK,
    input                                               I_RESETN,

    input       [1:0]                                   I_S_AW_RP_SEL,
    input       [AXI_ID_WD-1: 0]                        I_S_AWID,
    input       [AXI_ADDR_WD-1: 0]                      I_S_AWADDR,
    input       [AXI_LEN_WD-1: 0]                       I_S_AWLEN,
    input       [2: 0]                                  I_S_AWSIZE,
    input                                               I_S_AWLOCK,
    input       [3: 0]                                  I_S_AWCACHE,
    input       [2: 0]                                  I_S_AWPROT,
    input       [AXI_QOS_WD-1: 0]                       I_S_AWQOS,
    input                                               I_S_AWVALID,
    output wire                                         O_S_AWREADY,

    input       [AXI_SLV_NUM-1:0][AXI_DATA_WD-1: 0]     I_S_WDATA,
    input       [AXI_SLV_NUM-1:0][AXI_STRB_WD-1: 0]     I_S_WSTRB,
    input       [AXI_SLV_NUM-1:0]                       I_S_WSTRB_FULL,
    input       [AXI_SLV_NUM-1:0]                       I_S_WLAST,
    input       [AXI_SLV_NUM-1:0]                       I_S_WVALID,
    output      [AXI_SLV_NUM-1:0]                       O_S_WREADY,

    output      [AXI_SLV_NUM-1:0]                       O_AW_RP_READY,

    output      [1:0]                                   O_M_AW_RP_SEL,
    output wire [AXI_ID_WD-1:0]                         O_M_AWID,
    output wire [AXI_ADDR_WD-1: 0]                      O_M_AWADDR,
    output wire [AXI_LEN_WD-1: 0]                       O_M_AWLEN,
    output wire [2: 0]                                  O_M_AWSIZE,
    output wire                                         O_M_AWLOCK,
    output wire [3: 0]                                  O_M_AWCACHE,
    output wire [2: 0]                                  O_M_AWPROT,
    output wire [AXI_QOS_WD-1: 0]                       O_M_AWQOS,
    output wire                                         O_M_AWVALID,
    input                                               I_M_AWREADY,      

    output      [1:0]                                   O_M_W_RP_SEL,
    output wire [AXI_DATA_WD-1: 0]                      O_M_WDATA,
    output wire [AXI_STRB_WD-1: 0]                      O_M_WSTRB,
    output wire                                         O_M_WSTRB_FULL,
    output wire                                         O_M_WLAST,
    output wire                                         O_M_WVALID,
    input                                               I_M_WREADY

);

// Each RP's W burst follows its own AW, and W beats of different RPs may interleave
// (every WriteData message carries its RP). One RP waiting for WDATA credit therefore
// holds only its own next AW, never the shared AW path (AoU v0.7 RP independence).
logic [AXI_SLV_NUM-1:0]                         r_wbusy         ;
logic [AXI_SLV_NUM-1:0]                         w_aw_sel_oh     ;
logic                                           w_aw_busy       ;
logic                                           w_aw_hs         ;
logic [AXI_SLV_NUM-1:0]                         w_w_new         ;
logic [AXI_SLV_NUM-1:0]                         w_w_open        ;
logic [AXI_SLV_NUM-1:0]                         w_w_open_nxt    ;
// [q][p] = 1: q's open burst was opened before p's
logic [AXI_SLV_NUM-1:0][AXI_SLV_NUM-1:0]        r_w_older       ;
logic [AXI_SLV_NUM-1:0][AXI_SLV_NUM-1:0]        w_w_older       ;
logic [AXI_SLV_NUM-1:0]                         w_w_req         ;
logic [AXI_SLV_NUM-1:0]                         w_w_grant       ;
logic [AXI_SLV_NUM-1:0]                         w_w_last_hs     ;
logic [RP_SEL_WD-1: 0]                          w_w_sel         ;

wire                                            w_no_awvalid    ;

genvar p;
//==============================================================
//                          AW
//==============================================================
always_comb begin
    w_aw_sel_oh = '0;
    w_aw_sel_oh[I_S_AW_RP_SEL[RP_SEL_WD-1:0]] = 1'b1;
end

assign w_aw_busy       = |(r_wbusy & w_aw_sel_oh);
assign w_no_awvalid    = ~I_S_AWVALID;

assign O_S_AWREADY     = ~w_aw_busy & (I_M_AWREADY | w_no_awvalid);
assign O_M_AWVALID     = ~w_aw_busy & I_S_AWVALID;
assign w_aw_hs         = I_S_AWVALID & O_S_AWREADY;

assign O_AW_RP_READY   = ~r_wbusy;

if(RP_SEL_WD==1) begin : g_aw_rp_sel_1b
    assign O_M_AW_RP_SEL   = {1'b0, I_S_AW_RP_SEL[0]};
end else begin : g_aw_rp_sel
    assign O_M_AW_RP_SEL   = I_S_AW_RP_SEL;
end
assign O_M_AWID        = I_S_AWID    ;
assign O_M_AWADDR      = I_S_AWADDR  ;
assign O_M_AWLEN       = I_S_AWLEN   ;
assign O_M_AWSIZE      = I_S_AWSIZE  ;
assign O_M_AWLOCK      = I_S_AWLOCK  ;
assign O_M_AWCACHE     = I_S_AWCACHE ;
assign O_M_AWPROT      = I_S_AWPROT  ;
assign O_M_AWQOS       = I_S_AWQOS   ;

//==============================================================
//                          W
//==============================================================
// The first beat may go in the same cycle as its AW, as before. Bursts go out in
// AW order (oldest first), as before; a younger RP's beat goes only while every
// older open burst has no beat it can send (no WVALID or no WDATA credit).
assign w_w_new         = w_aw_sel_oh & {AXI_SLV_NUM{w_aw_hs}};
assign w_w_open        = r_wbusy | w_w_new;
assign w_w_req         = w_w_open & I_S_WVALID;

always_comb begin
    for (int unsigned q = 0; q < AXI_SLV_NUM; q++) begin
        for (int unsigned i = 0; i < AXI_SLV_NUM; i++) begin
            w_w_older[q][i] = r_w_older[q][i] | (r_wbusy[q] & w_w_new[i]);
        end
    end
end

always_comb begin
    w_w_grant = '0;
    w_w_sel   = '0;
    for (int unsigned i = 0; i < AXI_SLV_NUM; i++) begin
        if (w_w_req[i]) begin
            w_w_grant[i] = 1'b1;
            for (int unsigned q = 0; q < AXI_SLV_NUM; q++) begin
                if (w_w_req[q] & w_w_older[q][i]) w_w_grant[i] = 1'b0;
            end
        end
        if (w_w_grant[i]) w_w_sel = i[RP_SEL_WD-1:0];
    end
end

if(RP_SEL_WD==1) begin : g_w_rp_sel_1b
    assign O_M_W_RP_SEL    = {1'b0, w_w_sel};
end else begin : g_w_rp_sel
    assign O_M_W_RP_SEL    = w_w_sel;
end

assign O_M_WDATA       = I_S_WDATA[w_w_sel] ;
assign O_M_WSTRB       = I_S_WSTRB[w_w_sel] ;
assign O_M_WLAST       = I_S_WLAST[w_w_sel] ;
assign O_M_WSTRB_FULL  = I_S_WSTRB_FULL[w_w_sel] ;
assign O_M_WVALID      = |w_w_grant;

    for(p = 0; p < AXI_SLV_NUM; p = p + 1) begin : g_wready
        assign O_S_WREADY[p]  = w_w_grant[p] & I_M_WREADY;
    end

assign w_w_last_hs     = O_S_WREADY & I_S_WVALID & I_S_WLAST;

assign w_w_open_nxt    = w_w_open & ~w_w_last_hs;

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_wbusy   <= '0;
        r_w_older <= '0;
    end else begin
        r_wbusy   <= w_w_open_nxt;
        for (int unsigned q = 0; q < AXI_SLV_NUM; q++) begin
            r_w_older[q] <= w_w_older[q] & w_w_open_nxt & {AXI_SLV_NUM{w_w_open_nxt[q]}};
        end
    end
end

endmodule
