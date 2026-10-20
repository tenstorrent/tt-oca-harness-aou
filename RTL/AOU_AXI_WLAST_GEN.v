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
//  Module     : AOU_AXI_WLAST_GEN
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AXI_WLAST_GEN #(
    parameter   AOU_AXI_WLAST_AWCH_RS_EN = 1,
    parameter   AOU_AXI_WLAST_WCH_RS_EN  = 1,
    parameter   DATA_WD   = 512,
    parameter   ADDR_WD   = 64,
    parameter   ID_WD     = 10,
    parameter   STRB_WD   = DATA_WD / 8,
    parameter   QOS_WD    = 4,
    parameter   LEN_WD    = 8
)
(
    input                               I_CLK,
    input                               I_RESETN,

    input       [ ID_WD-1: 0]           I_S_AWID,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR,
    input       [ LEN_WD-1: 0]          I_S_AWLEN,
    input       [ 2: 0]                 I_S_AWSIZE,
    input                               I_S_AWLOCK,
    input       [ 3: 0]                 I_S_AWCACHE,
    input       [ 2: 0]                 I_S_AWPROT,
    input       [ QOS_WD-1: 0]          I_S_AWQOS,
    input                               I_S_AWVALID,
    output wire                         O_S_AWREADY,

    input       [ 1: 0]                 I_S_WDLENGTH,
    input       [ DATA_WD-1 : 0]        I_S_WDATA,
    input       [ STRB_WD-1 : 0]        I_S_WSTRB,
    input                               I_S_WVALID,
    output                              O_S_WREADY,

    output wire [ ID_WD-1: 0]           O_M_AWID,
    output wire [ ADDR_WD-1: 0]         O_M_AWADDR,
    output wire [ LEN_WD-1: 0]          O_M_AWLEN,
    output wire [ 2: 0]                 O_M_AWSIZE,
    output wire                         O_M_AWLOCK,
    output wire [ 3: 0]                 O_M_AWCACHE,
    output wire [ 2: 0]                 O_M_AWPROT,
    output wire [ 3: 0]                 O_M_AWQOS,
    output wire                         O_M_AWVALID_256,
    output wire                         O_M_AWVALID_512,
    output wire                         O_M_AWVALID_1024,
    input                               I_M_AWREADY_256,      
    input                               I_M_AWREADY_512,      
    input                               I_M_AWREADY_1024,      

    output wire [ 1: 0]                 O_M_WDLENGTH,
    output wire [ DATA_WD-1: 0]         O_M_WDATA,
    output wire [ STRB_WD-1: 0]         O_M_WSTRB,
    output wire                         O_M_WLAST,
    output wire                         O_M_WVALID_256,
    output wire                         O_M_WVALID_512,
    output wire                         O_M_WVALID_1024,
    input                               I_M_WREADY_256,
    input                               I_M_WREADY_512,
    input                               I_M_WREADY_1024

);

localparam AXI_AWCH_PAYLOAD_WD = ID_WD + ADDR_WD + LEN_WD + 3 + 1 + 4 + 3 + QOS_WD;//+2 BURST is always 01
localparam AXI_WCH_PAYLOAD_WD  = 2 + DATA_WD + STRB_WD;

wire [AXI_AWCH_PAYLOAD_WD - 1 : 0]  w_awch_fwd_rs_sdata;
wire [AXI_AWCH_PAYLOAD_WD - 1 : 0]  w_awch_fwd_rs_mdata;
wire                                w_awch_fwd_rs_mvalid;
wire                                w_awch_fwd_rs_sready;

wire [AXI_WCH_PAYLOAD_WD - 1 : 0]   w_wch_fwd_rs_sdata;
wire [AXI_WCH_PAYLOAD_WD - 1 : 0]   w_wch_fwd_rs_mdata;
wire                                w_wch_fwd_rs_mvalid;
wire                                w_wch_fwd_rs_sready;

reg  [LEN_WD-1:0]                   r_m_awch_remain_beat;
wire                                w_m_awch_en;
wire                                w_m_awch_ready;
wire                                w_wch_fwd_rs_mready;
wire                                w_m_awch_working;

assign w_awch_fwd_rs_sdata = {
    I_S_AWID,
    I_S_AWADDR,
    I_S_AWLEN,
    I_S_AWSIZE,
    I_S_AWLOCK,
    I_S_AWCACHE,
    I_S_AWPROT,
    I_S_AWQOS
};

assign {O_M_AWID,
        O_M_AWADDR,
        O_M_AWLEN,
        O_M_AWSIZE,
        O_M_AWLOCK,
        O_M_AWCACHE,
        O_M_AWPROT,
        O_M_AWQOS} = w_awch_fwd_rs_mdata;

generate
if (AOU_AXI_WLAST_AWCH_RS_EN == 1) begin

    AOU_REV_RS #(
        .DATA_WIDTH ( AXI_AWCH_PAYLOAD_WD  )
    ) u_axi_wlast_gen_awch_rs
    (
       // global interconnect inputs
       .I_RESETN( I_RESETN                      ),
       .I_CLK   ( I_CLK                         ),
    
       // inputs
       .I_SVALID( I_S_AWVALID                   ),
       .O_SREADY( O_S_AWREADY                   ),
       .I_SDATA ( w_awch_fwd_rs_sdata           ),
    
       // outputs
       .I_MREADY( w_m_awch_ready                ),
       .O_MVALID( w_awch_fwd_rs_mvalid          ),
       .O_MDATA ( w_awch_fwd_rs_mdata           )
    );

end else begin
    assign w_awch_fwd_rs_mdata  = w_awch_fwd_rs_sdata ;
    assign w_awch_fwd_rs_mvalid = I_S_AWVALID ;
    assign O_S_AWREADY          = w_m_awch_ready  ;

end
endgenerate


//----------------------------------------------------
assign w_wch_fwd_rs_sdata = {
    I_S_WDLENGTH,
    I_S_WDATA,
    I_S_WSTRB
};

generate
if (AOU_AXI_WLAST_WCH_RS_EN == 1) begin

    AOU_REV_RS #(
        .DATA_WIDTH ( AXI_WCH_PAYLOAD_WD  )
    ) u_aximux_4x1_fwd_rs_wch
    (
       // global interconnect inputs
       .I_RESETN( I_RESETN                     ),
       .I_CLK   ( I_CLK                        ),
    
       // inputs
       .I_SVALID( I_S_WVALID                   ),
       .O_SREADY( O_S_WREADY                   ),
       .I_SDATA ( w_wch_fwd_rs_sdata           ),
    
       // outputs
       .I_MREADY( w_wch_fwd_rs_mready          ),
       .O_MVALID( w_wch_fwd_rs_mvalid          ),
       .O_MDATA ( w_wch_fwd_rs_mdata           )
    );
end else begin
    assign w_wch_fwd_rs_mdata = w_wch_fwd_rs_sdata;
    assign w_wch_fwd_rs_mvalid = I_S_WVALID; 
    assign O_S_WREADY = w_wch_fwd_rs_mready;

end
endgenerate

assign {O_M_WDLENGTH,
        O_M_WDATA,
        O_M_WSTRB} = w_wch_fwd_rs_mdata;

//----------------------------------------------------
wire   w_m_awvalid_awready;
wire   w_m_wvalid_wready;
wire   w_m_wready_combined;
assign w_m_wready_combined = (I_M_WREADY_256 & (O_M_WDLENGTH == 2'b00)) | (I_M_WREADY_512 & (O_M_WDLENGTH == 2'b01)) | (I_M_WREADY_1024 & (O_M_WDLENGTH == 2'b10));
assign w_m_awvalid_awready = (O_M_AWVALID_256 & I_M_AWREADY_256) | (O_M_AWVALID_512 & I_M_AWREADY_512) | (O_M_AWVALID_1024 & I_M_AWREADY_1024);
assign w_m_wvalid_wready = w_wch_fwd_rs_mvalid & w_m_wready_combined ;

assign w_m_awch_en = w_awch_fwd_rs_mvalid & w_wch_fwd_rs_mvalid & (r_m_awch_remain_beat == 0);
assign O_M_AWVALID_256  = w_m_awch_en & (O_M_WDLENGTH == 2'b00) & I_M_WREADY_256;
assign O_M_AWVALID_512  = w_m_awch_en & (O_M_WDLENGTH == 2'b01) & I_M_WREADY_512;
assign O_M_AWVALID_1024 = w_m_awch_en & (O_M_WDLENGTH == 2'b10) & I_M_WREADY_1024;
assign w_m_awch_ready   = w_m_awch_en & w_m_awvalid_awready;

assign w_m_awch_working = w_m_awvalid_awready | (r_m_awch_remain_beat != 0) ;

always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_m_awch_remain_beat <= 'd0;
    end else begin
        if (w_m_awvalid_awready & w_m_wvalid_wready) begin
            r_m_awch_remain_beat <= O_M_AWLEN;
        end else if(w_m_wvalid_wready & w_wch_fwd_rs_mready & (|r_m_awch_remain_beat)) begin
            r_m_awch_remain_beat <= r_m_awch_remain_beat - 1;
        end
    end
end

assign w_wch_fwd_rs_mready = w_m_awch_working & w_m_wready_combined;            
assign O_M_WVALID_256   = w_m_awch_working & w_wch_fwd_rs_mvalid & (O_M_WDLENGTH == 2'b00);
assign O_M_WVALID_512   = w_m_awch_working & w_wch_fwd_rs_mvalid & (O_M_WDLENGTH == 2'b01);
assign O_M_WVALID_1024  = w_m_awch_working & w_wch_fwd_rs_mvalid & (O_M_WDLENGTH == 2'b10);

assign O_M_WLAST        = (w_m_awvalid_awready & (O_M_AWLEN == 'd0)) |
                          (~w_m_awvalid_awready & (r_m_awch_remain_beat == 'd1));


//-------------------------------------------------------------------
`ifdef ASSERTION_ON
// synopsys translate_off

ready_valid_assertion:
    assert
        property (
            @(posedge I_CLK) (I_S_AWVALID) |-> ##[0:500] O_S_AWREADY
        )
        else begin
            $error("\n[%t] Error!. You need check M_AWREADY and M_WREADY of wlastegn ", $time);
            $finish;
        end

s_awvalid_s_wvalid_assertion:
    assert
        property (
            @(posedge I_CLK) (I_S_AWVALID) |-> ##[0:500] I_S_WVALID
        )
        else begin
            $error("\n[%t] Error!. You need check I_S_AWVALID and I_S_WVALID of wlastegn ", $time);
            $finish;
        end

// synopsys translate_on
`endif
//-------------------------------------------------------------------

endmodule
