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
//  Module     : AOU_FIFO_RP
//  Version    : 2.00
//  Date       : 26-10-29
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
//  Per-RP RX message storage: register FIFOs for WriteReq, ReadReq and
//  WriteResp (one message per entry, fed from the AOU_RX_CORE lanes) and
//  granule stores for WriteData/WriteDataFull and ReadData (one credit per
//  granule, fed with the tagged granule vector). W_FIFO_DEPTH and
//  R_FIFO_DEPTH are in granules.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_FIFO_RP
#(
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024,
    localparam  AXI_MAX_STRB_WD             = AXI_PEER_DIE_MAX_DATA_WD/8,
    parameter   AXI_ID_WD                   = 10,

    parameter   AW_AR_FIFO_WIDTH            = 10 + 64 + 8 + 3 + 1 + 4 + 3 + 4 + 16, // + FLEX
    parameter   B_FIFO_WIDTH                = AXI_ID_WD + 2 + 16,                   // + FLEX
    parameter   R_FIFO_EXT_DATA_WIDTH       = AXI_ID_WD + 2 + 1,

    parameter   AW_FIFO_DEPTH               = 44,
    parameter   AR_FIFO_DEPTH               = 44,
    parameter   W_FIFO_DEPTH                = 600,      // granules
    parameter   R_FIFO_DEPTH                = 600,      // granules
    parameter   B_FIFO_DEPTH                = 44,

    parameter   G_CNT                       = 24,       // granules per decode cycle
    localparam  G_WD                        = 40,
    localparam  REQ_LANES                   = G_CNT/3 + 1,
    localparam  B_LANES                     = G_CNT,

    parameter   AW_FWD_RS_EN                = 1,
    parameter   B_FWD_RS_EN                 = 1,
    parameter   AR_FWD_RS_EN                = 1
)
(
    input                                                       I_CLK,
    input                                                       I_RESETN,

    input       [REQ_LANES-1:0]                                 I_WR_REQ_FIFO_SVALID,
    input       [REQ_LANES-1:0][AW_AR_FIFO_WIDTH-1:0]           I_WR_REQ_FIFO_SDATA,

    input       [REQ_LANES-1:0]                                 I_RD_REQ_FIFO_SVALID,
    input       [REQ_LANES-1:0][AW_AR_FIFO_WIDTH-1:0]           I_RD_REQ_FIFO_SDATA,

    input       [B_LANES-1:0]                                   I_WR_RESP_FIFO_SVALID,
    input       [B_LANES-1:0][B_FIFO_WIDTH-1:0]                 I_WR_RESP_FIFO_SDATA,

    input                                                       I_GRANULE_VALID,
    input       [G_CNT-1:0][G_WD-1:0]                           I_GRANULE,
    input       [G_CNT-1:0]                                     I_WR_DATA_COVER,
    input       [G_CNT-1:0]                                     I_WR_DATA_START,
    input       [G_CNT-1:0]                                     I_RD_DATA_COVER,
    input       [G_CNT-1:0]                                     I_RD_DATA_START,

    input                                                       I_WR_REQ_FIFO_MREADY,
    output      [AW_AR_FIFO_WIDTH -1:0]                         O_WR_REQ_FIFO_MDATA,
    output                                                      O_WR_REQ_FIFO_MVALID,

    input                                                       I_WR_DATA_FIFO_MREADY,
    output      [AXI_PEER_DIE_MAX_DATA_WD-1:0]                  O_WR_DATA_FIFO_MDATA,
    output      [AXI_MAX_STRB_WD-1:0]                           O_WR_DATA_FIFO_MSTRB,
    output      [1:0]                                           O_WR_DATA_FIFO_MDLEN,
    output                                                      O_WR_DATA_FIFO_WDATAF,
    output      [15:0]                                          O_WR_DATA_FIFO_MFLEX,
    output                                                      O_WR_DATA_FIFO_MVALID,

    input                                                       I_RD_REQ_FIFO_MREADY,
    output      [AW_AR_FIFO_WIDTH -1:0]                         O_RD_REQ_FIFO_MDATA,
    output                                                      O_RD_REQ_FIFO_MVALID,

    input                                                       I_RD_DATA_FIFO_MREADY,
    output      [AXI_PEER_DIE_MAX_DATA_WD-1:0]                  O_RD_DATA_FIFO_MDATA,
    output      [R_FIFO_EXT_DATA_WIDTH -1:0]                    O_RD_DATA_FIFO_EXT_MDATA,
    output      [1:0]                                           O_RD_DATA_FIFO_MDLEN,
    output      [15:0]                                          O_RD_DATA_FIFO_MFLEX,
    output                                                      O_RD_DATA_FIFO_MVALID,

    input                                                       I_WR_RESP_FIFO_MREADY,
    output      [B_FIFO_WIDTH-1:0]                              O_WR_RESP_FIFO_MDATA,
    output                                                      O_WR_RESP_FIFO_MVALID
);
    logic w_aw_fwd_rs_ready;
    logic w_ar_fwd_rs_ready;
    logic w_b_fwd_rs_ready;

    logic [REQ_LANES-1:0]                           w_wr_req_fifo_svalid;
    logic [REQ_LANES-1:0][AW_AR_FIFO_WIDTH-1:0]     w_wr_req_fifo_sdata;

    logic [REQ_LANES-1:0]                           w_rd_req_fifo_svalid;
    logic [REQ_LANES-1:0][AW_AR_FIFO_WIDTH-1:0]     w_rd_req_fifo_sdata;

    logic [B_LANES-1:0]                             w_wr_resp_fifo_svalid;
    logic [B_LANES-1:0][B_FIFO_WIDTH-1:0]           w_wr_resp_fifo_sdata;

//-----------------------------------------------------------------------------
// WriteReq
//-----------------------------------------------------------------------------
    generate
    if(AW_FWD_RS_EN) begin : gen_aw_rs

    logic   [REQ_LANES-1:0]                         w_wr_req_fwd_rs_mvalid;
    logic   [REQ_LANES-1:0][AW_AR_FIFO_WIDTH-1:0]   w_wr_req_fwd_rs_mdata;
    logic   w_aw_fwd_rs_valid;

        AOU_FWD_RS #(
            .DATA_WIDTH         (REQ_LANES*(AW_AR_FIFO_WIDTH+1))
        ) u_aou_rx_aw_fwd_rs
        (
            .I_CLK              ( I_CLK                     ),
            .I_RESETN           ( I_RESETN                  ),

            .I_SVALID           ( |I_WR_REQ_FIFO_SVALID     ),
            .I_SDATA            ( {I_WR_REQ_FIFO_SVALID, I_WR_REQ_FIFO_SDATA}),
            .O_SREADY           (),

            .I_MREADY           ( w_aw_fwd_rs_ready         ),
            .O_MDATA            ( {w_wr_req_fwd_rs_mvalid, w_wr_req_fwd_rs_mdata}),
            .O_MVALID           ( w_aw_fwd_rs_valid         )
        );
        assign w_wr_req_fifo_svalid = w_wr_req_fwd_rs_mvalid & {REQ_LANES{w_aw_fwd_rs_valid}};
        assign w_wr_req_fifo_sdata  = w_wr_req_fwd_rs_mdata;

    end else begin : gen_aw_direct
        assign w_wr_req_fifo_svalid = I_WR_REQ_FIFO_SVALID;
        assign w_wr_req_fifo_sdata  = I_WR_REQ_FIFO_SDATA;
    end
    endgenerate

    AOU_SYNC_FIFO_NS1M #(
        .FIFO_WIDTH                 ( AW_AR_FIFO_WIDTH                  ),
        .FIFO_DEPTH                 ( AW_FIFO_DEPTH                     ),
        .ICH_CNT                    ( REQ_LANES                         ),
        .ALWAYS_READY               ( 1                                 )
    ) u_aou_rx_aw_fifo_rp0
    (
        .I_CLK                      ( I_CLK                             ),
        .I_RESETN                   ( I_RESETN                          ),
        // write transaction
        .I_SVALID                   ( w_wr_req_fifo_svalid              ),
        .I_SDATA                    ( w_wr_req_fifo_sdata               ),
        .O_SREADY                   ( w_aw_fwd_rs_ready                 ),
        // read transaction
        .I_MREADY                   ( I_WR_REQ_FIFO_MREADY              ),
        .O_MDATA                    ( O_WR_REQ_FIFO_MDATA               ),
        .O_MVALID                   ( O_WR_REQ_FIFO_MVALID              ),

        .O_S_EMPTY_CNT              (                                   ),
        .O_M_DATA_CNT               (                                   )
    );

//-----------------------------------------------------------------------------
// WriteData / WriteDataFull granule store
//-----------------------------------------------------------------------------
    AOU_RX_GRANULE_STORE #(
        .G_CNT                      ( G_CNT                             ),
        .DEPTH_G                    ( W_FIFO_DEPTH                      ),
        .IS_READ                    ( 0                                 ),
        .AXI_ID_WD                  ( AXI_ID_WD                         )
    ) u_aou_rx_w_store
    (
        .I_CLK                      ( I_CLK                             ),
        .I_RESETN                   ( I_RESETN                          ),

        .I_SVALID                   ( I_GRANULE_VALID                   ),
        .I_SGRANULE                 ( I_GRANULE                         ),
        .I_SCOVER                   ( I_WR_DATA_COVER                   ),
        .I_SSTART                   ( I_WR_DATA_START                   ),

        .I_MREADY                   ( I_WR_DATA_FIFO_MREADY             ),
        .O_MVALID                   ( O_WR_DATA_FIFO_MVALID             ),
        .O_MDATA                    ( O_WR_DATA_FIFO_MDATA              ),
        .O_MDLEN                    ( O_WR_DATA_FIFO_MDLEN              ),
        .O_MFLEX                    ( O_WR_DATA_FIFO_MFLEX              ),
        .O_MSTRB                    ( O_WR_DATA_FIFO_MSTRB              ),
        .O_MWDATAF                  ( O_WR_DATA_FIFO_WDATAF             ),
        .O_MEXT                     (                                   )
    );

//-----------------------------------------------------------------------------
// ReadReq
//-----------------------------------------------------------------------------
    generate
    if(AR_FWD_RS_EN) begin : gen_ar_rs

    logic   [REQ_LANES-1:0]                         w_rd_req_fwd_rs_mvalid;
    logic   [REQ_LANES-1:0][AW_AR_FIFO_WIDTH-1:0]   w_rd_req_fwd_rs_mdata;
    logic   w_ar_fwd_rs_valid;

        AOU_FWD_RS #(
            .DATA_WIDTH         (REQ_LANES*(AW_AR_FIFO_WIDTH+1))
        ) u_aou_rx_ar_fwd_rs
        (
            .I_CLK              ( I_CLK                     ),
            .I_RESETN           ( I_RESETN                  ),

            .I_SVALID           ( |I_RD_REQ_FIFO_SVALID     ),
            .I_SDATA            ( {I_RD_REQ_FIFO_SVALID, I_RD_REQ_FIFO_SDATA}),
            .O_SREADY           (),

            .I_MREADY           ( w_ar_fwd_rs_ready         ),
            .O_MDATA            ( {w_rd_req_fwd_rs_mvalid, w_rd_req_fwd_rs_mdata}),
            .O_MVALID           ( w_ar_fwd_rs_valid         )
        );
        assign w_rd_req_fifo_svalid = w_rd_req_fwd_rs_mvalid & {REQ_LANES{w_ar_fwd_rs_valid}};
        assign w_rd_req_fifo_sdata  = w_rd_req_fwd_rs_mdata;

    end else begin : gen_ar_direct
        assign w_rd_req_fifo_svalid = I_RD_REQ_FIFO_SVALID;
        assign w_rd_req_fifo_sdata  = I_RD_REQ_FIFO_SDATA;
    end
    endgenerate

    AOU_SYNC_FIFO_NS1M #(
        .FIFO_WIDTH                 ( AW_AR_FIFO_WIDTH                  ),
        .FIFO_DEPTH                 ( AR_FIFO_DEPTH                     ),
        .ICH_CNT                    ( REQ_LANES                         ),
        .ALWAYS_READY               ( 1                                 )
    ) u_aou_rx_ar_fifo_rp0
    (
        .I_CLK                      ( I_CLK                             ),
        .I_RESETN                   ( I_RESETN                          ),
        // write transaction
        .I_SVALID                   ( w_rd_req_fifo_svalid              ),
        .I_SDATA                    ( w_rd_req_fifo_sdata               ),
        .O_SREADY                   ( w_ar_fwd_rs_ready                 ),
        // read transaction
        .I_MREADY                   ( I_RD_REQ_FIFO_MREADY              ),
        .O_MDATA                    ( O_RD_REQ_FIFO_MDATA               ),
        .O_MVALID                   ( O_RD_REQ_FIFO_MVALID              ),

        .O_S_EMPTY_CNT              (                                   ),
        .O_M_DATA_CNT               (                                   )
    );

//-----------------------------------------------------------------------------
// ReadData granule store
//-----------------------------------------------------------------------------
    AOU_RX_GRANULE_STORE #(
        .G_CNT                      ( G_CNT                             ),
        .DEPTH_G                    ( R_FIFO_DEPTH                      ),
        .IS_READ                    ( 1                                 ),
        .AXI_ID_WD                  ( AXI_ID_WD                         )
    ) u_aou_rx_r_store
    (
        .I_CLK                      ( I_CLK                             ),
        .I_RESETN                   ( I_RESETN                          ),

        .I_SVALID                   ( I_GRANULE_VALID                   ),
        .I_SGRANULE                 ( I_GRANULE                         ),
        .I_SCOVER                   ( I_RD_DATA_COVER                   ),
        .I_SSTART                   ( I_RD_DATA_START                   ),

        .I_MREADY                   ( I_RD_DATA_FIFO_MREADY             ),
        .O_MVALID                   ( O_RD_DATA_FIFO_MVALID             ),
        .O_MDATA                    ( O_RD_DATA_FIFO_MDATA              ),
        .O_MDLEN                    ( O_RD_DATA_FIFO_MDLEN              ),
        .O_MFLEX                    ( O_RD_DATA_FIFO_MFLEX              ),
        .O_MSTRB                    (                                   ),
        .O_MWDATAF                  (                                   ),
        .O_MEXT                     ( O_RD_DATA_FIFO_EXT_MDATA          )
    );

//-----------------------------------------------------------------------------
// WriteResp
//-----------------------------------------------------------------------------
    generate
    if(B_FWD_RS_EN) begin : gen_b_rs

        logic [B_LANES-1:0]                     w_wr_resp_fwd_rs_mvalid;
        logic                                   w_b_fwd_rs_valid;
        logic [B_LANES-1:0][B_FIFO_WIDTH-1:0]   w_wr_resp_fwd_rs_mdata;

    AOU_FWD_RS #(
            .DATA_WIDTH         ( B_LANES*(B_FIFO_WIDTH+1) )
    ) u_aou_rx_b_fwd_rs
    (
        .I_CLK              ( I_CLK                     ),
        .I_RESETN           ( I_RESETN                  ),

        .I_SVALID           ( |I_WR_RESP_FIFO_SVALID    ),
        .I_SDATA            ( {I_WR_RESP_FIFO_SVALID, I_WR_RESP_FIFO_SDATA}),
        .O_SREADY           (                           ),

        .I_MREADY           ( w_b_fwd_rs_ready          ),
        .O_MDATA            ( {w_wr_resp_fwd_rs_mvalid, w_wr_resp_fwd_rs_mdata}),
        .O_MVALID           ( w_b_fwd_rs_valid          )
    );
        assign w_wr_resp_fifo_svalid = w_wr_resp_fwd_rs_mvalid & {B_LANES{w_b_fwd_rs_valid}};
        assign w_wr_resp_fifo_sdata  = w_wr_resp_fwd_rs_mdata;

    end else begin : gen_b_direct
        assign w_wr_resp_fifo_svalid  = I_WR_RESP_FIFO_SVALID;
        assign w_wr_resp_fifo_sdata   = I_WR_RESP_FIFO_SDATA;
    end
    endgenerate

    AOU_SYNC_FIFO_NS1M #(
        .FIFO_WIDTH                 ( B_FIFO_WIDTH                  ),
        .FIFO_DEPTH                 ( B_FIFO_DEPTH                  ),
        .ICH_CNT                    ( B_LANES                       ),
        .ALWAYS_READY               ( 1                             )
    ) u_aou_rx_b_fifo_rp0
    (
        .I_CLK                      ( I_CLK                         ),
        .I_RESETN                   ( I_RESETN                      ),
        // write transaction
        .I_SVALID                   ( w_wr_resp_fifo_svalid         ),
        .I_SDATA                    ( w_wr_resp_fifo_sdata          ),
        .O_SREADY                   ( w_b_fwd_rs_ready              ),
        // read transaction
        .I_MREADY                   ( I_WR_RESP_FIFO_MREADY         ),
        .O_MDATA                    ( O_WR_RESP_FIFO_MDATA          ),
        .O_MVALID                   ( O_WR_RESP_FIFO_MVALID         ),

        .O_S_EMPTY_CNT              (                               ),
        .O_M_DATA_CNT               (                               )
    );

endmodule
