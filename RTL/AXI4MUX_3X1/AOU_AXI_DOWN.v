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
//  Module     : AOU_AXI_DOWN
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps
module AOU_AXI_DOWN #(
    parameter       I_DATA_WD      = 512,
                    O_DATA_WD      = 128,
                    ADDR_WD        = 32,
                    ID_WD          = 4,
                    SIZE_WD        = 3,
                    RESP_WD        = 2,
                    BURST_WD       = 2,
                    CACHE_WD       = 4,
                    PROT_WD        = 3,
                    STRB_WD        = I_DATA_WD / 8,
                    O_STRB_WD      = O_DATA_WD / 8,
                    LEN_WD         = 4,

    parameter   RD_MO_CNT = 64,
    parameter   WR_MO_CNT = 64,

    localparam  RD_MO_IDX_WD = $clog2(RD_MO_CNT)
)
(
    // Slave I/F    =================================================
    input                                                  I_CLK,
    input                                                  I_RESETN,

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
    
    // Master I/F   =================================================
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
    output                                                 O_M_BREADY,
     
    output       [ADDR_WD-1:0]                             O_M_ARADDR,
    output       [SIZE_WD-1:0]                             O_M_ARSIZE,
    output       [BURST_WD-1:0]                            O_M_ARBURST,
    output       [CACHE_WD-1:0]                            O_M_ARCACHE,
    output       [PROT_WD-1:0]                             O_M_ARPROT,
    output       [ID_WD-1:0]                               O_M_ARID,
    output       [LEN_WD-1:0]                              O_M_ARLEN,
    output                                                 O_M_ARLOCK,
    output       [3:0]                                     O_M_ARQOS,
    output                                                 O_M_ARVALID,
    input                                                  I_M_ARREADY,

    input        [ID_WD-1:0]                               I_M_RID,
    input        [O_DATA_WD-1:0]                           I_M_RDATA,
    input        [RESP_WD-1:0]                             I_M_RRESP,
    input                                                  I_M_RLAST,
    input                                                  I_M_RVALID,
    output                                                 O_M_RREADY,

    output  [ID_WD-1:0]                                    O_DOWN_MISMATCH_RID,
    output                                                 O_DEST_TABLE_RID_ERR
  
);
// internal FIFO DEPTH
localparam FIFO_DEPTH  = 8;
localparam INST_WD = ID_WD + ADDR_WD + LEN_WD + SIZE_WD + BURST_WD + 1 + CACHE_WD + PROT_WD + 4;

// wire for AR ctrl split
wire    [INST_WD -1:0]    w_i_ar_ctrl;
assign w_i_ar_ctrl = {I_S_ARID, I_S_ARADDR, I_S_ARLEN, I_S_ARSIZE, I_S_ARBURST, I_S_ARLOCK, I_S_ARCACHE, I_S_ARPROT, I_S_ARQOS};

// AW FIFO val & rdy
wire                    w_aw_fifo_ready, w_aw_fifo_valid;
wire                    w_w_data_fifo_ready, w_w_data_fifo_valid;

reg     [LEN_WD:0]      r_wr_cnt;
wire                    w_o_m_wlast;

wire [I_DATA_WD/O_DATA_WD*(RESP_WD+1)-1:0] w_r_resp;
reg [RESP_WD-1:0] w_resp_ans;
reg               w_last_ans;

//for LINT error
wire w_i_wlast;
assign w_i_wlast = I_S_WLAST;

wire    w_arch_no_stop;
wire    w_rch_no_stop;
wire    w_rch_ready_nonblocking;
// ================================================================================================
//  WRITE STAGE ===================================================================================
// ================================================================================================
wire [LEN_WD-1:0] w_wr_o_awlen;

always @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) r_wr_cnt <= 0;
    else if (O_M_WVALID && I_M_WREADY) begin
        if (r_wr_cnt == {1'b0, w_wr_o_awlen}) begin
            r_wr_cnt <= 0;
        end else begin
            r_wr_cnt <= r_wr_cnt + 1;
        end
    end
end

// O_M_WLAST wire
assign w_o_m_wlast = (r_wr_cnt == {1'b0, w_wr_o_awlen});

//AW channel FIFO (indicater for how many "WRITE transactions" left)
AOU_SYNC_FIFO_REG #(
    .FIFO_WIDTH         (LEN_WD),
    .FIFO_DEPTH         (FIFO_DEPTH)
)
u_aw_fifo (
    .I_CLK                  (I_CLK), 
    .I_RESETN               (I_RESETN),

    .I_SVALID               (I_S_AWVALID && O_S_AWREADY),
    .I_SDATA                (O_M_AWLEN),
    .O_SREADY               (w_aw_fifo_ready),
 
    .I_MREADY               (O_M_WVALID && I_M_WREADY && w_o_m_wlast), 
 
    .O_MDATA                (w_wr_o_awlen),                                    //hold AWLEN till write transaction
    .O_MVALID               (w_aw_fifo_valid),

    .O_EMPTY_CNT            (),
    .O_FULL_CNT             ()   
);

assign  {O_M_AWID, O_M_AWBURST, O_M_AWLOCK, O_M_AWCACHE, O_M_AWPROT, O_M_AWQOS} = 
            {I_S_AWID, I_S_AWBURST, I_S_AWLOCK, I_S_AWCACHE, I_S_AWPROT, I_S_AWQOS};

generate
    if($clog2(I_DATA_WD/8)==0) begin
        assign O_M_AWADDR = I_S_AWADDR;
    end else begin
        //assign O_M_AWADDR = (I_S_AWSIZE == $clog2(I_DATA_WD/8)) ? {I_S_AWADDR[ADDR_WD-1:$clog2(I_DATA_WD/8)], {$clog2(I_DATA_WD/8){1'b0}}} : I_S_AWADDR;
        //bug fix for 1024-256 Downsizing
        assign O_M_AWADDR = (I_S_AWSIZE > $clog2(O_DATA_WD/8)) ? ((I_S_AWADDR >> I_S_AWSIZE) << I_S_AWSIZE) : I_S_AWADDR; 
    end
endgenerate

assign O_M_AWSIZE = (I_S_AWSIZE <= unsigned'($clog2(O_DATA_WD/8))) ? I_S_AWSIZE : $clog2(O_DATA_WD/8);
assign O_M_AWLEN =  (I_S_AWSIZE <= unsigned'($clog2(O_DATA_WD/8))) ? I_S_AWLEN  : (((I_S_AWLEN + 1) << (I_S_AWSIZE - unsigned'($clog2(O_DATA_WD/8)))) -1);

wire [I_DATA_WD/O_DATA_WD-1:0]                      w_ns1m_wdata_svalid;
wire [$clog2(I_DATA_WD/O_DATA_WD)-1:0]              w_sdata_wdata_start_idx;

reg  [11:0]                                         r_s_awaddr;
wire [LEN_WD-1:0]                                   w_m_awlen;

reg  [2:0]                                          r_s_awsize;
wire [2:0]                                          w_cur_s_awsize;
wire [2:0]                                          w_cur_awsize_diff;

assign w_cur_s_awsize = (I_S_AWVALID && O_S_AWREADY) ? I_S_AWSIZE : r_s_awsize;
assign w_cur_awsize_diff  = (w_cur_s_awsize <= $clog2(O_DATA_WD/8))     ? 3'd0 :
                        (w_cur_s_awsize == unsigned'($clog2(O_DATA_WD/8)) + 1) ? 3'd1 :
                        3'd2;

assign w_sdata_wdata_start_idx = (I_S_AWVALID && O_S_AWREADY) ? I_S_AWADDR[$clog2(I_DATA_WD/8)-1:$clog2(O_DATA_WD/8)] :
                                                                r_s_awaddr[$clog2(I_DATA_WD/8)-1:$clog2(O_DATA_WD/8)] ;

generate
    if (I_DATA_WD/O_DATA_WD == 4) begin
        assign w_ns1m_wdata_svalid = (w_cur_awsize_diff == 3'd0) ? 
                                      ((w_sdata_wdata_start_idx == 2'b00) ? 4'b0001 :
                                        (w_sdata_wdata_start_idx == 2'b01) ? 4'b0010 : 
                                        (w_sdata_wdata_start_idx == 2'b10) ? 4'b0100 : 
                                                                             4'b1000 ) :
                                     (w_cur_awsize_diff == 3'd1) ? 
                                      ((w_sdata_wdata_start_idx[1] == 1'b0) ? 4'b0011 : 
                                                                              4'b1100 ) :
                                     4'b1111;
    end else begin
        assign w_ns1m_wdata_svalid = (w_cur_awsize_diff == 3'd0) ? 
                                      ((w_sdata_wdata_start_idx == 1'b0) ? 2'b01 : 2'b10): 
                                     2'b11;
    end
endgenerate

always @(posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_s_awaddr <= 12'd0;
        r_s_awsize <= 3'd0;

    end else begin
        if (I_S_AWVALID && O_S_AWREADY) begin
            r_s_awaddr <= I_S_AWADDR[11:0] + (1 << I_S_AWSIZE);
            r_s_awsize <= I_S_AWSIZE;
        end else if ( I_S_WVALID && O_S_WREADY ) begin
            r_s_awaddr <= r_s_awaddr + (1 << r_s_awsize) ;
        end

    end
end

AOU_SYNC_FIFO_NS1M #(
    .FIFO_WIDTH                         (O_DATA_WD                  ),
    .FIFO_DEPTH                         (FIFO_DEPTH                 ),
    .ICH_CNT                            (I_DATA_WD/O_DATA_WD        )
) u_wdata_fifo
(
    .I_CLK                              (I_CLK                      ),
    .I_RESETN                           (I_RESETN                   ),
    // write transaction
    .I_SVALID                           (w_ns1m_wdata_svalid & {(I_DATA_WD/O_DATA_WD){I_S_WVALID && I_M_WREADY}}),
    .I_SDATA                            (I_S_WDATA                  ),
    .O_SREADY                           (w_w_data_fifo_ready        ),
    // read transaction
    .I_MREADY                           (I_M_WREADY && O_M_WVALID   ),
    .O_MDATA                            (O_M_WDATA                  ),
    .O_MVALID                           (w_w_data_fifo_valid        ),

    .O_S_EMPTY_CNT                      (                           ),
    .O_M_DATA_CNT                       (                           )
);

AOU_SYNC_FIFO_NS1M #(
    .FIFO_WIDTH                         (O_STRB_WD                  ),
    .FIFO_DEPTH                         (FIFO_DEPTH                 ),
    .ICH_CNT                            (I_DATA_WD/O_DATA_WD        )
) u_wstrb_fifo
(
    .I_CLK                              (I_CLK                      ),
    .I_RESETN                           (I_RESETN                   ),
    // write transaction
    .I_SVALID                           (w_ns1m_wdata_svalid & {(I_DATA_WD/O_DATA_WD){I_S_WVALID && I_M_WREADY}}),
    .I_SDATA                            (I_S_WSTRB                  ),
    .O_SREADY                           (                           ),
    // read transaction
    .I_MREADY                           (I_M_WREADY && O_M_WVALID   ),
    .O_MDATA                            (O_M_WSTRB                  ),
    .O_MVALID                           (                           ),

    .O_S_EMPTY_CNT                      (                           ),
    .O_M_DATA_CNT                       (                           )
);


// ================================================================================================
//  READ STAGE ====================================================================================
// ================================================================================================

//AR channel FIFO   ===========================================================

AOU_AXI_INST_SPLITTER #(
    .INST_WD            (INST_WD),
    .ID_WD              (ID_WD),
    .ADDR_WD            (ADDR_WD),
    .LEN_WD             (LEN_WD),
    .SIZE_WD            (SIZE_WD),
    .BURST_WD           (BURST_WD),
    .CACHE_WD           (CACHE_WD),
    .PROT_WD            (PROT_WD),
    .I_DATA_WD          (I_DATA_WD),
    .O_DATA_WD          (O_DATA_WD)
)u_axi_r_inst_splitter (
    .I_AW_INST          (w_i_ar_ctrl),
    .O_SPLIT_AWID       (O_M_ARID),
    .O_SPLIT_AWADDR     (O_M_ARADDR),
    .O_SPLIT_AWLEN      (O_M_ARLEN),
    .O_SPLIT_AWSIZE     (O_M_ARSIZE),
    .O_SPLIT_AWBURST    (O_M_ARBURST),
    .O_SPLIT_AWLOCK     (O_M_ARLOCK),
    .O_SPLIT_AWCACHE    (O_M_ARCACHE),
    .O_SPLIT_AWPROT     (O_M_ARPROT),
    .O_SPLIT_AWQOS      (O_M_ARQOS)
);

AOU_AXI_DOWN_RDATA_ORDER #(
    .AXI_ID_WD          (ID_WD),
    .O_DATA_WD          (O_DATA_WD),
    .I_DATA_WD          (I_DATA_WD),
    .RD_MO_CNT          (RD_MO_CNT)
) u_axi_down_rdata_order (
    .I_CLK                           (I_CLK),
    .I_RESETN                        (I_RESETN),

    .I_AXI_ArId                      (O_M_ARID), 
    .I_AXI_ArValid                   (I_S_ARVALID),
    .I_AXI_ArReady                   (O_S_ARREADY),
    
    .I_AXI_RId                       (I_M_RID),
    .I_AXI_RLast                     (I_M_RLAST),
    .I_AXI_RResp                     (I_M_RRESP),
    .I_AXI_RData                     (I_M_RDATA),
    .I_AXI_RValid                    (I_M_RVALID),
    .I_AXI_RReady                    (O_M_RREADY),
    .O_AR_Slot_Available_Flag        (w_arch_no_stop),
    
    .O_ReorderBuf_MValid             (w_rch_no_stop),
    .O_ReorderBuf_MData              (O_S_RDATA),
    .O_ReorderBuf_MResp              (O_S_RRESP),
    .O_ReorderBuf_MId                (O_S_RID),
    .O_RReadyNonBlocking             (w_rch_ready_nonblocking),
    .O_DEST_TABLE_ID_ERR             (O_DEST_TABLE_RID_ERR)             
);

assign O_DOWN_MISMATCH_RID = I_M_RID;

// R channel  ================================================

assign O_M_RREADY = w_rch_ready_nonblocking ? 1'b1:  I_S_RREADY;
assign O_S_RLAST  = I_M_RLAST;
assign O_S_RVALID = I_M_RVALID & w_rch_no_stop;

// AW channel ================================================
assign O_S_AWREADY = I_M_AWREADY && w_aw_fifo_ready;
assign O_M_AWVALID = I_S_AWVALID && w_aw_fifo_ready;

//  W channel ================================================
assign O_S_WREADY = I_M_WREADY && w_w_data_fifo_ready;
assign O_M_WVALID =  w_w_data_fifo_valid;
assign O_M_WLAST  = w_o_m_wlast;

//  B channel ================================================
assign O_S_BVALID = I_M_BVALID;
assign O_M_BREADY = I_S_BREADY;
assign O_S_BID    = I_M_BID;
assign O_S_BRESP  = I_M_BRESP;

//  AR channel ================================================
assign O_S_ARREADY = I_M_ARREADY & w_arch_no_stop;
assign O_M_ARVALID = I_S_ARVALID & w_arch_no_stop; 

endmodule
