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
//  Module     : AOU_EARLY_BRESP_CTRL_AWCACHE
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_EARLY_BRESP_CTRL_AWCACHE
#(
    parameter   AXI_DATA_WD         = 512,
    parameter   AXI_ADDR_WD         = 64,
    parameter   AXI_ID_WD           = 10,
    parameter   AXI_LEN_WD          = 8,
    localparam  AXI_STRB_WD         = AXI_DATA_WD / 8,
    parameter   AW_W_FIFO_CNT_DEPTH = 64,
    parameter   WR_MO_CNT           = 64,
    //When Early Response is disabled, MO is not limited, but the pending counter must be sized large enough
    //to cover the maximum number of outstanding transactions.
    parameter   PENDING_CNT_WD      = 10
    //localparam  MO_CNT_WD           = $clog2(WR_MO_CNT+1)
)
(
    input                           I_CLK,
    input                           I_RESETN,
    
    //Interface for AXI Slave
    input   [AXI_ID_WD-1:0]         I_AXI_S_AWID,
    input   [AXI_ADDR_WD-1:0]       I_AXI_S_AWADDR,
    input   [AXI_LEN_WD-1:0]        I_AXI_S_AWLEN,
    input   [2:0]                   I_AXI_S_AWSIZE,
    input   [1:0]                   I_AXI_S_AWBURST,      
    input                           I_AXI_S_AWLOCK,
    input   [3:0]                   I_AXI_S_AWCACHE,
    input   [2:0]                   I_AXI_S_AWPROT,
    input   [3:0]                   I_AXI_S_AWQOS,
    input                           I_AXI_S_AWVALID,
    output                          O_AXI_S_AWREADY,

    input   [AXI_DATA_WD-1:0]       I_AXI_S_WDATA,
    input   [AXI_STRB_WD-1:0]       I_AXI_S_WSTRB,
    input                           I_AXI_S_WLAST,
    input                           I_AXI_S_WVALID,
    output                          O_AXI_S_WREADY,

    output  [AXI_ID_WD-1:0]         O_AXI_S_BID,
    output  [1:0]                   O_AXI_S_BRESP,
    output                          O_AXI_S_BVALID,
    input                           I_AXI_S_BREADY,

    //Interface for AXI Master
    output  [AXI_ID_WD-1:0]         O_AXI_M_AWID,
    output  [AXI_ADDR_WD-1:0]       O_AXI_M_AWADDR,
    output  [AXI_LEN_WD-1:0]        O_AXI_M_AWLEN,
    output  [2:0]                   O_AXI_M_AWSIZE,
    output  [1:0]                   O_AXI_M_AWBURST,
    output                          O_AXI_M_AWLOCK,
    output  [3:0]                   O_AXI_M_AWCACHE,
    output  [2:0]                   O_AXI_M_AWPROT,
    output  [3:0]                   O_AXI_M_AWQOS,
    output                          O_AXI_M_AWVALID,
    input                           I_AXI_M_AWREADY,

    output  [AXI_DATA_WD-1:0]       O_AXI_M_WDATA,
    output  [AXI_STRB_WD-1:0]       O_AXI_M_WSTRB,
    output                          O_AXI_M_WLAST,
    output                          O_AXI_M_WVALID,
    input                           I_AXI_M_WREADY,

    input   [AXI_ID_WD-1:0]         I_AXI_M_BID,
    input   [1:0]                   I_AXI_M_BRESP,
    input                           I_AXI_M_BVALID,
    output                          O_AXI_M_BREADY,
    
    //Control signal
    input                           I_EARLY_BRESP_EN,
    input                           I_EARLY_BRESP_ALWAYS_EN, //When this signal is enable, does not check AWCAHCE[0]
    output                          O_BRESP_DONE,
    
    //Interrupt
    output                          O_BRESP_ERR,//Interrupt
    output  [AXI_ID_WD-1:0]         O_BRESP_ERR_ID,
    output  [1:0]                   O_BRESP_ERR_TYPE,

    input                           I_SFR_WDT_EN,
    input   [31:0]                  I_SFR_WDT_THRESHOLD,
    output                          O_AXI_WR_TRANS_TIMEOUT_ERR
    
);

//logic  [MO_CNT_WD-1:0]          r_aw_cnt;
logic  [PENDING_CNT_WD-1:0]     r_aw_cnt;
logic  [PENDING_CNT_WD-1:0]     r_w_cnt;

logic                           w_w_last_hs;
logic                           w_aw_hs;
logic                           w_b_hs;
logic                           w_write_aw_credit;

logic                           w_aw_cnt_fifo_sready;
logic                           w_aw_cnt_fifo_mvalid;

logic   [AXI_ID_WD-1:0]         w_awid;
logic                           w_bufferable_flag;
logic                           w_aw_early_eligible;
logic                           r_early_bresp_en;

logic                           w_early_table_available_flag;
logic                           w_earlyrsp_consume;
logic                           w_earlyrsp_valid;
logic   [AXI_ID_WD-1:0]         w_early_rsp_id;

logic                           w_bypass;
logic   [AXI_ID_WD-1:0]         w_table_awid;
logic                           w_table_bufferable_flag;

logic                           r_earlyresponse_non_stop;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_early_bresp_en <= 1'b0;
    end else if (I_EARLY_BRESP_EN & O_BRESP_DONE & ~r_early_bresp_en & ~w_aw_hs) begin
        r_early_bresp_en <= 1'b1;
    end else if (~I_EARLY_BRESP_EN & O_BRESP_DONE & r_early_bresp_en & ~w_aw_hs) begin
        r_early_bresp_en <= 1'b0;
    end
end

assign w_w_last_hs = I_AXI_S_WVALID & O_AXI_S_WREADY & I_AXI_S_WLAST;
assign w_aw_hs     = I_AXI_S_AWVALID & O_AXI_S_AWREADY;
assign w_b_hs      = I_AXI_M_BVALID & O_AXI_M_BREADY;

assign w_write_aw_credit = (r_aw_cnt > r_w_cnt) || (I_AXI_S_AWVALID && O_AXI_S_AWREADY);

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_aw_cnt <= '0;
    end else if (~w_b_hs & w_aw_hs) begin
        r_aw_cnt <= r_aw_cnt + 1;
    end else if (w_b_hs & ~w_aw_hs) begin
        r_aw_cnt <= r_aw_cnt - 1;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_w_cnt <= '0;
    end else if (~w_b_hs & w_w_last_hs) begin
        r_w_cnt <= r_w_cnt + 1;
    end else if (w_b_hs & ~w_w_last_hs) begin
        r_w_cnt <= r_w_cnt - 1;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_earlyresponse_non_stop <= 1'b1;
    end else if (~w_earlyrsp_valid && I_AXI_M_BVALID && ~O_AXI_M_BREADY) begin
        r_earlyresponse_non_stop <= 1'b0;
    end else if (w_b_hs) begin
        r_earlyresponse_non_stop <= 1'b1;        
    end
end

// A write is answered early when it is bufferable (AWCACHE[0]) or EARLY_ALWAYS_EN
// is set. Exclusive writes (AWLOCK) are never answered early: only the remote
// subordinate can decide EXOKAY/OKAY, and an early OKAY would report the
// exclusive as failed while the remote die may still perform it (issue #91).
assign w_aw_early_eligible      = (I_AXI_S_AWCACHE[0] || I_EARLY_BRESP_ALWAYS_EN) && ~I_AXI_S_AWLOCK;

assign w_bypass                 = ~w_aw_cnt_fifo_mvalid & w_aw_hs & w_w_last_hs;
assign w_table_awid             = w_aw_cnt_fifo_mvalid ? w_awid             : I_AXI_S_AWID;
assign w_table_bufferable_flag  = w_aw_cnt_fifo_mvalid ? w_bufferable_flag  : w_aw_early_eligible;

AOU_SYNC_FIFO_REG
#(
    .FIFO_WIDTH                     ( AXI_ID_WD + 1                             ),
    .FIFO_DEPTH                     ( AW_W_FIFO_CNT_DEPTH                       )
)
u_aou_aw_cnt(
    .I_CLK                          ( I_CLK                                     ),
    .I_RESETN                       ( I_RESETN                                  ),

    .I_SVALID                       ( r_early_bresp_en & w_aw_hs & ~w_bypass    ),
    .I_SDATA                        ( {I_AXI_S_AWID, w_aw_early_eligible}       ),
    .O_SREADY                       ( w_aw_cnt_fifo_sready                      ),

    .I_MREADY                       ( w_w_last_hs                               ),
    .O_MDATA                        ( {w_awid, w_bufferable_flag}               ),  
    .O_MVALID                       ( w_aw_cnt_fifo_mvalid                      ),

    .O_EMPTY_CNT                    (                                           ),
    .O_FULL_CNT                     (                                           )
);

AOU_EARLY_TABLE #(
    .AXI_ID_WD                      ( AXI_ID_WD                             ),
    .WR_MO_CNT                      ( WR_MO_CNT                             )
) u_aou_early_table
(
    .I_CLK                          ( I_CLK                                 ),
    .I_RESETN                       ( I_RESETN                              ),

    .I_AXI_AwId                     ( w_table_awid                          ), 
    .I_AXI_Bufferable               ( w_table_bufferable_flag               ),
    .I_AXI_AwValid                  ( r_early_bresp_en && w_w_last_hs       ),
    .I_AXI_AwReady                  ( w_early_table_available_flag          ),

    .I_AXI_M_BId                    ( I_AXI_M_BID                           ),
    .I_AXI_M_BValid                 ( r_early_bresp_en && I_AXI_M_BVALID    ),
    .I_AXI_M_BReady                 ( O_AXI_M_BREADY                        ),
    .O_AW_Slot_Available_Flag       ( w_early_table_available_flag          ),

    .I_AXI_S_BReady                 ( I_AXI_S_BREADY                        ),
    .O_EarlyResponse_Consume        ( w_earlyrsp_consume                    ),
    .O_EarlyResponse_Valid          ( w_earlyrsp_valid                      ),
    .O_EarlyResponse_Id             ( w_early_rsp_id                        ), 

    .I_EarlyResponse_NonStop        ( r_earlyresponse_non_stop              ),

    .O_DEST_TABLE_ID_ERR            (                                       )
);

AOU_WRITE_TRANS_WDT #(
    .BOS_PARAM_WR_CNT_WD        ( PENDING_CNT_WD                )
) u_aou_write_trans_wdt
(

    .I_ACLK                     ( I_CLK                         ),
    .I_RESETN_ACLK              ( I_RESETN                      ), 
                                
    .I_SFR_WDT_EN               ( I_SFR_WDT_EN                  ),
    .I_SFR_WDT_THRESHOLD        ( I_SFR_WDT_THRESHOLD           ),   
                                
    .I_AXI_AW_HS                ( w_aw_hs                       ),
    .I_AXI_B_HS                 ( w_b_hs                        ),
    .I_WR_PEND_CNT              ( r_aw_cnt                      ),
                                
    .O_AXI_WR_TRANS_TIMEOUT_ERR ( O_AXI_WR_TRANS_TIMEOUT_ERR    )

);

//  AW CH ==================================================
assign  O_AXI_M_AWID      = I_AXI_S_AWID    ;
assign  O_AXI_M_AWADDR    = I_AXI_S_AWADDR  ;
assign  O_AXI_M_AWLEN     = I_AXI_S_AWLEN   ;
assign  O_AXI_M_AWSIZE    = I_AXI_S_AWSIZE  ;
assign  O_AXI_M_AWBURST   = I_AXI_S_AWBURST ;
assign  O_AXI_M_AWLOCK    = I_AXI_S_AWLOCK  ;
assign  O_AXI_M_AWCACHE   = I_AXI_S_AWCACHE ;
assign  O_AXI_M_AWPROT    = I_AXI_S_AWPROT  ;
assign  O_AXI_M_AWQOS     = I_AXI_S_AWQOS   ;
assign  O_AXI_S_AWREADY   = r_early_bresp_en ? w_aw_cnt_fifo_sready & (r_aw_cnt != WR_MO_CNT) & I_AXI_M_AWREADY: I_AXI_M_AWREADY;
assign  O_AXI_M_AWVALID   = r_early_bresp_en ? w_aw_cnt_fifo_sready & (r_aw_cnt != WR_MO_CNT) & I_AXI_S_AWVALID: I_AXI_S_AWVALID;

//  W CH ==================================================
assign  O_AXI_M_WDATA     = I_AXI_S_WDATA   ;
assign  O_AXI_M_WSTRB     = I_AXI_S_WSTRB   ;
assign  O_AXI_M_WLAST     = I_AXI_S_WLAST   ;
assign  O_AXI_S_WREADY    = r_early_bresp_en ? I_AXI_M_WREADY & (w_aw_cnt_fifo_mvalid || (I_AXI_S_AWVALID && O_AXI_S_AWREADY)) : I_AXI_M_WREADY && w_write_aw_credit;
assign  O_AXI_M_WVALID    = r_early_bresp_en ? I_AXI_S_WVALID & (w_aw_cnt_fifo_mvalid || (I_AXI_S_AWVALID && O_AXI_S_AWREADY)) : I_AXI_S_WVALID && w_write_aw_credit ;

//  B CH ==================================================
assign  O_AXI_S_BID       = r_early_bresp_en ? w_earlyrsp_valid ? w_early_rsp_id  : w_earlyrsp_consume ? 'd0   : I_AXI_M_BID   : I_AXI_M_BID;  
assign  O_AXI_S_BRESP     = r_early_bresp_en ? w_earlyrsp_valid ? 2'b00           : w_earlyrsp_consume ? 2'b00 : I_AXI_M_BRESP : I_AXI_M_BRESP;
assign  O_AXI_S_BVALID    = r_early_bresp_en ? w_earlyrsp_valid ? 1'b1            : w_earlyrsp_consume ? 1'b0  : I_AXI_M_BVALID: I_AXI_M_BVALID;
assign  O_AXI_M_BREADY    = r_early_bresp_en ? w_earlyrsp_valid ? 1'b0            : w_earlyrsp_consume ? 1'b1  : I_AXI_S_BREADY: I_AXI_S_BREADY;

//Interrupt
assign  O_BRESP_ERR       = r_early_bresp_en & w_earlyrsp_consume & I_AXI_M_BVALID & O_AXI_M_BREADY & (I_AXI_M_BRESP[1]);
assign  O_BRESP_ERR_ID    = I_AXI_M_BID;
assign  O_BRESP_ERR_TYPE  = I_AXI_M_BRESP;

//assign  O_BRESP_DONE      = (r_aw_cnt == {MO_CNT_WD{1'b0}});
assign  O_BRESP_DONE      = (r_aw_cnt == {PENDING_CNT_WD{1'b0}});

endmodule
