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
//  Module     : AOU_RX_CORE
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_RX_CORE
import packet_def_pkg::*;
#(
    parameter   PHY_TYPE                    = 2, //0:32B, 1:64B, 2:128B, 3:256B
    parameter   FDI_IF_WD                   = 1024,
    localparam  PHASE_CNT                   = 256*8/FDI_IF_WD,
    localparam  PHASE_CNT_WD                = (PHASE_CNT == 1) ? 1 : $clog2(PHASE_CNT),
    parameter   DEC_MULTI                   = 1,
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024,
    parameter   AXI_ADDR_WD                 = 64,
    parameter   AXI_ID_WD                   = 10,
    parameter   AXI_LEN_WD                  = 8,
    localparam  AXI_STRB_WD                 = AXI_PEER_DIE_MAX_DATA_WD / 8,

    parameter   MAX_MISC_COUNT_CHUNK        = 2,
    parameter   MAX_REQ_COUNT_CHUNK         = 4,
    parameter   MAX_DATA_COUNT_CHUNK        = 2,
    parameter   MAX_WR_RESP_COUNT_CHUNK     = 12,

    localparam  MAX_MISC_COUNT_WD           = $clog2(MAX_MISC_COUNT_CHUNK + 1),
    localparam  MAX_REQ_COUNT_WD            = $clog2(MAX_REQ_COUNT_CHUNK + 1),
    localparam  MAX_DATA_COUNT_WD           = $clog2(MAX_DATA_COUNT_CHUNK + 1),
    localparam  MAX_WR_RESP_COUNT_WD        = $clog2(MAX_WR_RESP_COUNT_CHUNK + 1),

    localparam  MAX_MISC_WD                 = $clog2(MAX_MISC_COUNT_CHUNK),
    localparam  MAX_REQ_WD                  = $clog2(MAX_REQ_COUNT_CHUNK),
    localparam  MAX_DATA_WD                 = $clog2(MAX_DATA_COUNT_CHUNK),
    localparam  MAX_WR_RESP_WD              = $clog2(MAX_WR_RESP_COUNT_CHUNK),

    parameter   DATA_DEC_CNT                = 4,
    parameter   RP_COUNT                    = 2,
    parameter   AW_AR_FIFO_DATA_WIDTH       = 97,
    parameter   R_FIFO_EXT_DATA_WIDTH       = 15,
    parameter   B_FIFO_DATA_WIDTH           = 12
)
(
    input                                                                                       I_CLK,
    input                                                                                       I_RESETN,

    input                                                                                       I_FDI_PL_VALID,
    input   [FDI_IF_WD-1: 0]                                                                    I_FDI_PL_DATA,
    input                                                                                       I_FDI_PL_FLIT_CANCEL,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0][AW_AR_FIFO_DATA_WIDTH-1:0]   O_RD_REQ_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]                              O_RD_REQ_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0][AW_AR_FIFO_DATA_WIDTH-1:0]   O_WR_REQ_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]                              O_WR_REQ_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]       O_WR_DATA_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_STRB_WD-1:0]                    O_WR_DATA_FIFO_SDATA_STRB,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                                     O_WR_DATA_FIFO_SDATA_WDATAF,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                                     O_WR_DATA_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_WR_RESP_COUNT_CHUNK-1:0][B_FIFO_DATA_WIDTH-1:0]   O_WR_RESP_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][MAX_WR_RESP_COUNT_CHUNK-1:0]                          O_WR_RESP_FIFO_SVALID,

    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]       O_RD_DATA_FIFO_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0][R_FIFO_EXT_DATA_WIDTH-1:0]          O_RD_DATA_FIFO_EXT_SDATA,
    output  [RP_COUNT-1:0][DEC_MULTI-1:0][DATA_DEC_CNT-1:0]                                     O_RD_DATA_FIFO_SVALID,

    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][1:0]                                      O_CRDTGRANT_WRESPCRED3,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][1:0]                                      O_CRDTGRANT_WRESPCRED2,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][1:0]                                      O_CRDTGRANT_WRESPCRED1,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][1:0]                                      O_CRDTGRANT_WRESPCRED0,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RDATACRED3,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RDATACRED2,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RDATACRED1,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RDATACRED0,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WDATACRED3,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WDATACRED2,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WDATACRED1,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WDATACRED0,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RREQCRED3,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RREQCRED2,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RREQCRED1,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_RREQCRED0,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WREQCRED3,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WREQCRED2,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WREQCRED1,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][2:0]                                      O_CRDTGRANT_WREQCRED0,
    output  [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0]                                           O_CRDTGRANT_VALID,

    output  [1:0]                                                                               O_MSGCRDT_WRESPCRED,
    output  [2:0]                                                                               O_MSGCRDT_RDATACRED,
    output  [2:0]                                                                               O_MSGCRDT_WDATACRED,
    output  [2:0]                                                                               O_MSGCRDT_RREQCRED,
    output  [2:0]                                                                               O_MSGCRDT_WREQCRED,
    output  [1:0]                                                                               O_MSGCRDT_RP,
    output                                                                                      O_MSGCRDT_VALID,

    output  [3:0]                                                                               O_ACTIVATION_OP,
    output                                                                                      O_ACTIVATION_PROP_REQ,
    output                                                                                      O_ACTIVATION_VALID
);
//-----------------------------------------------------------------------
    st_g_packet [DEC_MULTI-1:0][11:0]   i_g;     //12 Granules per chunk
    st_g_packet [11:0]                  zero_g;
    st_g_packet [2:0][11:0]             r_g;     //maximum 30 granules uses. therefore at least 3 register(3 cycle) needed to cover continue messages.
    st_g_packet [(DEC_MULTI+3)*12-1:0]  w_g;

    logic [FDI_IF_WD-1:0]       w_rx_chunk_data;
    logic                       w_rx_chunk_data_valid;
    logic [DEC_MULTI-1:0][11:0] i_msg_start;    //protocol header per chunk

    logic [2:0]                 r_fdi_pl_data_valid;
    logic [PHASE_CNT_WD-1:0]    r_aou_rx_phase;

    st_msg_credit_packet        i_msg_credit;

//-------------------------------------------------------------
    logic [DEC_MULTI-1:0][11:0]                             i_misc_start;
    logic [DEC_MULTI-1:0][11:0]                             i_write_req_start;
    logic [DEC_MULTI-1:0][11:0]                             i_read_req_start;
    logic [DEC_MULTI-1:0][11:0]                             i_write_data_start;
    logic [DEC_MULTI-1:0][11:0]                             i_read_data_start;
    logic [DEC_MULTI-1:0][11:0]                             i_write_resp_start;

    logic [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0][3:0]    i_misc_idx;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0]         i_misc_valid;
    logic [DEC_MULTI-1:0][MAX_MISC_COUNT_WD-1:0]            i_misc_cnt;
    logic [MAX_MISC_COUNT_WD-1:0]                           w_misc_cnt_for_wait;

    logic [MAX_MISC_COUNT_CHUNK-1:0][3:0]                   r_misc_idx;
    logic [MAX_MISC_COUNT_CHUNK-1:0]                        r_misc_valid;
    logic [MAX_MISC_COUNT_WD-1:0]                           r_misc_cnt;
    logic [1:0][MAX_MISC_COUNT_CHUNK-1:0][3:0]              w_misc_idx;
    logic [1:0][MAX_MISC_COUNT_CHUNK-1:0]                   w_misc_valid;
    logic [1:0][MAX_MISC_COUNT_WD-1:0]                      w_misc_cnt;

    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0][3:0]     i_write_req_idx;
    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]          i_write_req_valid;
    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_WD-1:0]             i_write_req_cnt;
    logic [MAX_REQ_COUNT_WD-1:0]                            w_write_req_cnt_for_wait;

    logic [MAX_REQ_COUNT_CHUNK-1:0][3:0]                    r_write_req_idx;
    logic [MAX_REQ_COUNT_CHUNK-1:0]                         r_write_req_valid;
    logic [MAX_REQ_COUNT_WD-1:0]                            r_write_req_cnt;
    logic [1:0][MAX_REQ_COUNT_CHUNK-1:0][3:0]               w_write_req_idx;
    logic [1:0][MAX_REQ_COUNT_CHUNK-1:0]                    w_write_req_valid;
    logic [1:0][MAX_REQ_COUNT_WD-1:0]                       w_write_req_cnt;

    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0][3:0]     i_read_req_idx;
    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]          i_read_req_valid;
    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_WD-1:0]             i_read_req_cnt;
    logic [MAX_REQ_COUNT_WD-1:0]                            w_read_req_cnt_for_wait;

    logic [MAX_REQ_COUNT_CHUNK-1:0][3:0]                    r_read_req_idx;
    logic [MAX_REQ_COUNT_CHUNK-1:0]                         r_read_req_valid;
    logic [MAX_REQ_COUNT_WD-1:0]                            r_read_req_cnt;
    logic [1:0][MAX_REQ_COUNT_CHUNK-1:0][3:0]               w_read_req_idx;
    logic [1:0][MAX_REQ_COUNT_CHUNK-1:0]                    w_read_req_valid;
    logic [1:0][MAX_REQ_COUNT_WD-1:0]                       w_read_req_cnt;

    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0][3:0]    i_write_data_idx;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0]         i_write_data_valid;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_WD-1:0]            i_write_data_cnt;
    logic [MAX_DATA_COUNT_WD-1:0]                           w_write0_data_cnt_m1;
    logic [MAX_DATA_COUNT_WD-1:0]                           w_write1_data_cnt_m1;

    logic [2:0][MAX_DATA_COUNT_CHUNK-1:0][3:0]              r_write_data_idx;
    logic [2:0][MAX_DATA_COUNT_CHUNK-1:0]                   r_write_data_valid;
    logic [2:0][MAX_DATA_COUNT_WD-1:0]                      r_write_data_cnt;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_CHUNK-1:0][3:0]    w_write_data_idx;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_CHUNK-1:0]         w_write_data_valid;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_WD-1:0]            w_write_data_cnt;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_WD-1:0]            w_valid_write_data_cnt;

    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0][3:0]    i_read_data_idx;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0]         i_read_data_valid;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_WD-1:0]            i_read_data_cnt;
    logic [MAX_DATA_COUNT_WD-1:0]                           w_read0_data_cnt_m1;
    logic [MAX_DATA_COUNT_WD-1:0]                           w_read1_data_cnt_m1;

    logic [2:0][MAX_DATA_COUNT_CHUNK-1:0][3:0]              r_read_data_idx;
    logic [2:0][MAX_DATA_COUNT_CHUNK-1:0]                   r_read_data_valid;
    logic [2:0][MAX_DATA_COUNT_WD-1:0]                      r_read_data_cnt;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_CHUNK-1:0][3:0]    w_read_data_idx;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_CHUNK-1:0]         w_read_data_valid;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_WD-1:0]            w_read_data_cnt;
    logic [DEC_MULTI+2:0][MAX_DATA_COUNT_WD-1:0]            w_valid_read_data_cnt;

    logic [DEC_MULTI-1:0][MAX_WR_RESP_COUNT_CHUNK-1:0][3:0] i_write_resp_idx;
    logic [DEC_MULTI-1:0][MAX_WR_RESP_COUNT_CHUNK-1:0]      i_write_resp_valid;
    logic [DEC_MULTI-1:0][MAX_WR_RESP_COUNT_WD-1:0]         i_write_resp_cnt;

    logic                                                   w_write512_data_continue;
    logic                                                   w_write1024_data_continue;
    logic                                                   w_read512_data_continue;
    logic                                                   w_read1024_data_continue;

    logic [2:0]                                             wait_valid_chunk;

    logic                                                   r_write_data_mask;
    logic                                                   r_read_data_mask;
//-------------------------------------------------------------
    AOU_RX_FDI_IF #(
        .FDI_IF_WD                  ( FDI_IF_WD             )
    ) u_aou_rx_fdi_if
    (
        .I_CLK                      ( I_CLK                 ),
        .I_RESETN                   ( I_RESETN              ),
        .I_FDI_PL_VALID             ( I_FDI_PL_VALID        ),
        .I_FDI_PL_DATA              ( I_FDI_PL_DATA         ),
        .I_FDI_PL_FLIT_CANCEL       ( I_FDI_PL_FLIT_CANCEL  ),
        .O_AOU_RX_CHUNK_DATA        ( w_rx_chunk_data       ),
        .O_AOU_RX_CHUNK_DATA_VALID  ( w_rx_chunk_data_valid )
    );
    generate
        if(PHY_TYPE <= 1) begin
            assign i_g = w_rx_chunk_data[(0+2)*8 +: 12*5*8];
            assign i_msg_start = (!r_aou_rx_phase[0]) ? w_rx_chunk_data[((0+2+12*5)*8+4) +: 12] : w_rx_chunk_data[((0)*8+4) +: 12];
            assign i_msg_credit = w_rx_chunk_data[0 +: 16];
        end else if(PHY_TYPE == 2) begin
            assign i_g = {w_rx_chunk_data[126*8 -1 : 66*8], w_rx_chunk_data[62*8 -1 : 2*8]};
            assign i_msg_start = {w_rx_chunk_data[(64*8+4) +: 12], w_rx_chunk_data[(62*8+4) +: 12]};
            assign i_msg_credit = w_rx_chunk_data[0 +: 16];
        end else begin
            assign i_g = {w_rx_chunk_data[254*8 -1 : 194*8], w_rx_chunk_data[190*8 -1 : 130*8], w_rx_chunk_data[126*8 -1: 66*8], w_rx_chunk_data[62*8 -1: 2*8]};
            assign i_msg_start = {w_rx_chunk_data[((128+64)*8+4) +: 12], w_rx_chunk_data[((128+62)*8+4) +: 12], w_rx_chunk_data[(64*8+4) +: 12], w_rx_chunk_data[(62*8+4) +: 12]};
            assign i_msg_credit = w_rx_chunk_data[128*8 +: 16];
        end
    endgenerate

//-------------------------------------------------------------
    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_aou_rx_phase <= 'd0;
        end else begin
            if(PHY_TYPE != 3) begin
                if(w_rx_chunk_data_valid)
                    r_aou_rx_phase <= r_aou_rx_phase + 1;
            end
        end
    end

    assign zero_g = 'd0;

//-----------------------------------------------------------------------
// Helper functions for selecting fields out of a 12-entry granule chunk
// (r_g[*]) using a 4-bit stored gid.
//
// The stored gid is 4 bits because that is the natural width for a
// 0..11 granule index, but the array has only 12 entries (`[11:0]`).
// Using `chunk_g[gid]` directly causes equivalence/synthesis tools to
// assume the access can address indices 12..15 and inject X for those
// unreachable lanes, which in turn produces large numbers of "E" key
// points in Conformal LEC. These helpers express the lookup as an
// explicit one-hot mux over the 12 in-range entries so the source code
// never expresses an out-of-range select. The functional behaviour for
// any in-range gid is identical to a direct array select.
//-----------------------------------------------------------------------
    function automatic logic [1:0] f_g_others (input logic [3:0] gid,
                                               input st_g_packet [11:0] chunk_g);
        f_g_others = '0;
        for (int j = 0; j < 12; j++) begin
            if (gid == j[3:0]) f_g_others = chunk_g[j].others;
        end
    endfunction

    function automatic logic [3:0] f_g_msg_type (input logic [3:0] gid,
                                                 input st_g_packet [11:0] chunk_g);
        f_g_msg_type = '0;
        for (int j = 0; j < 12; j++) begin
            if (gid == j[3:0]) f_g_msg_type = chunk_g[j].msg_type;
        end
    endfunction

    generate
        if(PHY_TYPE < 2) begin :gen_32_64B
            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_fdi_pl_data_valid     <= 'd0;
                    r_g                     <= 'd0;

                    r_misc_idx              <= 'd0;
                    r_misc_valid            <= 'd0;
                    r_misc_cnt              <= 'd0;

                    r_write_req_idx         <= 'd0;
                    r_write_req_valid       <= 'd0;
                    r_write_req_cnt         <= 'd0;

                    r_read_req_idx          <= 'd0;
                    r_read_req_valid        <= 'd0;
                    r_read_req_cnt          <= 'd0;

                    r_write_data_idx        <= 'd0;
                    r_write_data_valid      <= 'd0;
                    r_write_data_cnt        <= 'd0;

                    r_read_data_idx         <= 'd0;
                    r_read_data_valid       <= 'd0;
                    r_read_data_cnt         <= 'd0;

                    r_write_data_mask       <= 1'b0;
                    r_read_data_mask        <= 1'b0;
                end else begin

                    if(w_rx_chunk_data_valid) begin
                        r_misc_idx              <= i_misc_idx[DEC_MULTI-1];
                        r_misc_valid            <= i_misc_valid[DEC_MULTI-1];
                        r_misc_cnt              <= i_misc_cnt[DEC_MULTI-1];

                        r_write_req_idx         <= i_write_req_idx[DEC_MULTI-1];
                        r_write_req_valid       <= i_write_req_valid[DEC_MULTI-1];
                        r_write_req_cnt         <= i_write_req_cnt[DEC_MULTI-1];

                        r_read_req_idx          <= i_read_req_idx[DEC_MULTI-1];
                        r_read_req_valid        <= i_read_req_valid[DEC_MULTI-1];
                        r_read_req_cnt          <= i_read_req_cnt[DEC_MULTI-1];

                        if(|r_read_data_mask)
                            r_read_data_mask        <= 'd0;
                        else if(|r_write_data_mask)
                            r_write_data_mask       <= 'd0;

                        r_fdi_pl_data_valid     <= {r_fdi_pl_data_valid[1:0], w_rx_chunk_data_valid};
                        r_g                     <= {r_g[1:0], i_g};

                        r_write_data_idx        <= {r_write_data_idx[1], r_write_data_idx[0], i_write_data_idx};
                        r_write_data_valid      <= {r_write_data_valid[1], r_write_data_valid[0], i_write_data_valid};
                        r_write_data_cnt        <= {r_write_data_cnt[1], r_write_data_cnt[0], i_write_data_cnt};

                        r_read_data_idx         <= {r_read_data_idx[1], r_read_data_idx[0], i_read_data_idx};
                        r_read_data_valid       <= {r_read_data_valid[1], r_read_data_valid[0], i_read_data_valid};
                        r_read_data_cnt         <= {r_read_data_cnt[1], r_read_data_cnt[0], i_read_data_cnt};

                    end else begin
                        if(w_write512_data_continue | w_read512_data_continue) begin
                            r_misc_valid            <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_read_req_valid        <= 'd0;

                            r_write_data_valid[2:1] <= 'd0;
                            r_read_data_valid[2:1]  <= 'd0;

                            if(r_write_data_valid[0][0] && (f_g_others(r_write_data_idx[0][0], r_g[0]) == 2'b00))
                                r_write_data_mask   <= 'd1;
                            else if(r_read_data_valid[0][0] && (f_g_others(r_read_data_idx[0][0], r_g[0]) == 2'b00))
                                r_read_data_mask    <= 'd1;
                        end else if(w_write1024_data_continue | w_read1024_data_continue) begin
                            r_misc_valid            <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_read_req_valid        <= 'd0;
                            r_write_data_valid[2]   <= 'd0;
                            r_read_data_valid[2]    <= 'd0;

                            if(r_write_data_valid[0][0] && (f_g_others(r_write_data_idx[0][0], r_g[0]) == 2'b00))
                                r_write_data_mask       <= 'd1;
                            else if (r_read_data_valid[0][0] && (f_g_others(r_read_data_idx[0][0], r_g[0]) == 2'b00))
                                r_read_data_mask        <= 'd1;

                            if(|r_write_data_valid[0] && (f_g_others(r_write_data_idx[0][w_write0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)) begin
                                r_write_data_valid[1]   <= 'd0;
                                r_read_data_valid[1]    <= 'd0;
                            end else if(|r_read_data_valid[0] && (f_g_others(r_read_data_idx[0][w_read0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)) begin
                                r_write_data_valid[1]   <= 'd0;
                                r_read_data_valid[1]    <= 'd0;
                            end

                         end else if(wait_valid_chunk == 0) begin
                            r_misc_idx              <= 'd0;
                            r_misc_valid            <= 'd0;
                            r_misc_cnt              <= 'd0;

                            r_write_req_idx         <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_write_req_cnt         <= 'd0;

                            r_read_req_idx          <= 'd0;
                            r_read_req_valid        <= 'd0;
                            r_read_req_cnt          <= 'd0;

                            r_fdi_pl_data_valid     <= {r_fdi_pl_data_valid[1:0], 1'b0};
                            r_g                     <= {r_g[1:0], zero_g};

                            r_write_data_idx        <= {r_write_data_idx[1], r_write_data_idx[0], {MAX_DATA_COUNT_CHUNK{4'b0}}};
                            r_write_data_valid      <= {r_write_data_valid[1], r_write_data_valid[0], {MAX_DATA_COUNT_CHUNK{1'b0}}};
                            r_write_data_cnt        <= {r_write_data_cnt[1], r_write_data_cnt[0], {MAX_DATA_COUNT_WD{1'b0}}};

                            r_read_data_idx         <= {r_read_data_idx[1], r_read_data_idx[0], {MAX_DATA_COUNT_CHUNK{4'b0}}};
                            r_read_data_valid       <= {r_read_data_valid[1], r_read_data_valid[0], {MAX_DATA_COUNT_CHUNK{1'b0}}};
                            r_read_data_cnt         <= {r_read_data_cnt[1], r_read_data_cnt[0], {MAX_DATA_COUNT_WD{1'b0}}};

                        end
                    end
                end
            end

        end else if(PHY_TYPE == 2) begin :gen_128B
            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_fdi_pl_data_valid     <= 'd0;
                    r_g                     <= 'd0;

                    r_misc_idx              <= 'd0;
                    r_misc_valid            <= 'd0;
                    r_misc_cnt              <= 'd0;

                    r_write_req_idx         <= 'd0;
                    r_write_req_valid       <= 'd0;
                    r_write_req_cnt         <= 'd0;

                    r_read_req_idx          <= 'd0;
                    r_read_req_valid        <= 'd0;
                    r_read_req_cnt          <= 'd0;

                    r_write_data_idx        <= 'd0;
                    r_write_data_valid      <= 'd0;
                    r_write_data_cnt        <= 'd0;

                    r_read_data_idx         <= 'd0;
                    r_read_data_valid       <= 'd0;
                    r_read_data_cnt         <= 'd0;

                    r_write_data_mask       <= 1'b0;
                    r_read_data_mask        <= 1'b0;
                end else begin

                    if(w_rx_chunk_data_valid) begin
                        r_misc_idx              <= i_misc_idx[DEC_MULTI-1];
                        r_misc_valid            <= i_misc_valid[DEC_MULTI-1];
                        r_misc_cnt              <= i_misc_cnt[DEC_MULTI-1];

                        r_write_req_idx         <= i_write_req_idx[DEC_MULTI-1];
                        r_write_req_valid       <= i_write_req_valid[DEC_MULTI-1];
                        r_write_req_cnt         <= i_write_req_cnt[DEC_MULTI-1];

                        r_read_req_idx          <= i_read_req_idx[DEC_MULTI-1];
                        r_read_req_valid        <= i_read_req_valid[DEC_MULTI-1];
                        r_read_req_cnt          <= i_read_req_cnt[DEC_MULTI-1];

                        if(|r_read_data_mask)
                            r_read_data_mask        <= 'd0;
                        else if(|r_write_data_mask)
                            r_write_data_mask       <= 'd0;

                        r_fdi_pl_data_valid     <= {r_fdi_pl_data_valid[0], {2{w_rx_chunk_data_valid}}};
                        r_g                     <= {r_g[0], i_g[0], i_g[1]};

                        r_write_data_idx        <= {r_write_data_idx[0], i_write_data_idx[0], i_write_data_idx[1]};
                        r_write_data_valid      <= {r_write_data_valid[0], i_write_data_valid[0], i_write_data_valid[1]};
                        r_write_data_cnt        <= {r_write_data_cnt[0], i_write_data_cnt[0], i_write_data_cnt[1]};

                        r_read_data_idx         <= {r_read_data_idx[0], i_read_data_idx[0], i_read_data_idx[1]};
                        r_read_data_valid       <= {r_read_data_valid[0], i_read_data_valid[0], i_read_data_valid[1]};
                        r_read_data_cnt         <= {r_read_data_cnt[0], i_read_data_cnt[0], i_read_data_cnt[1]};

                    end else begin
                        if(w_write512_data_continue | w_read512_data_continue) begin
                            r_misc_valid            <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_read_req_valid        <= 'd0;

                            r_write_data_valid[2:1] <= 'd0;
                            r_read_data_valid[2:1]  <= 'd0;

                        end else if(w_write1024_data_continue | w_read1024_data_continue) begin
                            r_misc_valid            <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_read_req_valid        <= 'd0;
                            r_write_data_valid[2]   <= 'd0;
                            r_read_data_valid[2]    <= 'd0;

                            if(r_write_data_valid[0][0] && (f_g_others(r_write_data_idx[0][0], r_g[0]) == 2'b00))
                                r_write_data_mask       <= 'd1;
                            else if (r_read_data_valid[0][0] && (f_g_others(r_read_data_idx[0][0], r_g[0]) == 2'b00))
                                r_read_data_mask        <= 'd1;

                            if(|r_write_data_valid[0] && (f_g_others(r_write_data_idx[0][w_write0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)) begin
                                r_write_data_valid[1] <= 'd0;
                                r_read_data_valid[1]  <= 'd0;
                            end else if(|r_read_data_valid[0] && (f_g_others(r_read_data_idx[0][w_read0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)) begin
                                r_write_data_valid[1] <= 'd0;
                                r_read_data_valid[1]  <= 'd0;
                            end

                        end else if(wait_valid_chunk == 0) begin
                            r_misc_idx              <= 'd0;
                            r_misc_valid            <= 'd0;
                            r_misc_cnt              <= 'd0;

                            r_write_req_idx         <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_write_req_cnt         <= 'd0;

                            r_read_req_idx          <= 'd0;
                            r_read_req_valid        <= 'd0;
                            r_read_req_cnt          <= 'd0;

                            r_fdi_pl_data_valid     <= {r_fdi_pl_data_valid[0], 2'b0};
                            r_g                     <= {r_g[0], {2{zero_g}}};

                            r_write_data_idx        <= {r_write_data_idx[0], {MAX_DATA_COUNT_CHUNK{4'b0}}, {MAX_DATA_COUNT_CHUNK{4'b0}}};
                            r_write_data_valid      <= {r_write_data_valid[0], {MAX_DATA_COUNT_CHUNK{1'b0}}, {MAX_DATA_COUNT_CHUNK{1'b0}}};
                            r_write_data_cnt        <= {r_write_data_cnt[0], {MAX_DATA_COUNT_WD{1'b0}}, {MAX_DATA_COUNT_WD{1'b0}}};

                            r_read_data_idx         <= {r_read_data_idx[0], {MAX_DATA_COUNT_CHUNK{4'b0}}, {MAX_DATA_COUNT_CHUNK{4'b0}}};
                            r_read_data_valid       <= {r_read_data_valid[0], {MAX_DATA_COUNT_CHUNK{1'b0}}, {MAX_DATA_COUNT_CHUNK{1'b0}}};
                            r_read_data_cnt         <= {r_read_data_cnt[0], {MAX_DATA_COUNT_WD{1'b0}}, {MAX_DATA_COUNT_WD{1'b0}}};

                        end
                    end
                end
            end

        end else begin :gen_256B
            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_fdi_pl_data_valid     <= 'd0;
                    r_g                     <= 'd0;

                    r_misc_idx              <= 'd0;
                    r_misc_valid            <= 'd0;
                    r_misc_cnt              <= 'd0;

                    r_write_req_idx         <= 'd0;
                    r_write_req_valid       <= 'd0;
                    r_write_req_cnt         <= 'd0;

                    r_read_req_idx          <= 'd0;
                    r_read_req_valid        <= 'd0;
                    r_read_req_cnt          <= 'd0;

                    r_write_data_idx        <= 'd0;
                    r_write_data_valid      <= 'd0;
                    r_write_data_cnt        <= 'd0;

                    r_read_data_idx         <= 'd0;
                    r_read_data_valid       <= 'd0;
                    r_read_data_cnt         <= 'd0;

                    r_write_data_mask       <= 1'b0;
                    r_read_data_mask        <= 1'b0;
                end else begin

                    if(w_rx_chunk_data_valid) begin
                        r_misc_idx              <= i_misc_idx[DEC_MULTI-1];
                        r_misc_valid            <= i_misc_valid[DEC_MULTI-1];
                        r_misc_cnt              <= i_misc_cnt[DEC_MULTI-1];

                        r_write_req_idx         <= i_write_req_idx[DEC_MULTI-1];
                        r_write_req_valid       <= i_write_req_valid[DEC_MULTI-1];
                        r_write_req_cnt         <= i_write_req_cnt[DEC_MULTI-1];

                        r_read_req_idx          <= i_read_req_idx[DEC_MULTI-1];
                        r_read_req_valid        <= i_read_req_valid[DEC_MULTI-1];
                        r_read_req_cnt          <= i_read_req_cnt[DEC_MULTI-1];

                        if(|r_read_data_mask)
                            r_read_data_mask        <= 'd0;
                        else if(|r_write_data_mask)
                            r_write_data_mask       <= 'd0;

                        r_fdi_pl_data_valid     <= {3{w_rx_chunk_data_valid}};
                        r_g                     <= {i_g[1], i_g[2], i_g[3]};

                        r_write_data_idx        <= {i_write_data_idx[1], i_write_data_idx[2], i_write_data_idx[3]};
                        r_write_data_valid      <= {i_write_data_valid[1], i_write_data_valid[2], i_write_data_valid[3]};
                        r_write_data_cnt        <= {i_write_data_cnt[1], i_write_data_cnt[2], i_write_data_cnt[3]};

                        r_read_data_idx         <= {i_read_data_idx[1], i_read_data_idx[2], i_read_data_idx[3]};
                        r_read_data_valid       <= {i_read_data_valid[1], i_read_data_valid[2], i_read_data_valid[3]};
                        r_read_data_cnt         <= {i_read_data_cnt[1], i_read_data_cnt[2], i_read_data_cnt[3]};

                    end else begin
                        if(wait_valid_chunk == 0) begin
                            r_misc_idx              <= 'd0;
                            r_misc_valid            <= 'd0;
                            r_misc_cnt              <= 'd0;

                            r_write_req_idx         <= 'd0;
                            r_write_req_valid       <= 'd0;
                            r_write_req_cnt         <= 'd0;

                            r_read_req_idx          <= 'd0;
                            r_read_req_valid        <= 'd0;
                            r_read_req_cnt          <= 'd0;

                            r_fdi_pl_data_valid     <= 'd0;
                            r_g                     <= 'd0;

                            r_write_data_idx        <= 'd0;
                            r_write_data_valid      <= 'd0;
                            r_write_data_cnt        <= 'd0;

                            r_read_data_idx         <= 'd0;
                            r_read_data_valid       <= 'd0;
                            r_read_data_cnt         <= 'd0;
                        end
                    end
                end
            end
        end
    endgenerate

//-------------------------------------------------------------
    genvar i, j;
    generate
        for(j = 0; j < DEC_MULTI; j = j + 1) begin: gen_message_decode_per_chunk
            for (i = 0; i < 12; i = i + 1) begin : gen_message_decode
                assign i_misc_start[j][i]          = i_msg_start[j][i] & (i_g[j][i].msg_type == MSG_MISC);
                assign i_write_req_start[j][i]     = i_msg_start[j][i] & (i_g[j][i].msg_type == MSG_WR_REQ);
                assign i_read_req_start[j][i]      = i_msg_start[j][i] & (i_g[j][i].msg_type == MSG_RD_REQ);
                assign i_write_data_start[j][i]    = i_msg_start[j][i] & ((i_g[j][i].msg_type == MSG_WR_DATA) | (i_g[j][i].msg_type ==MSG_WRF_DATA));
                assign i_read_data_start[j][i]     = i_msg_start[j][i] & (i_g[j][i].msg_type == MSG_RD_DATA);
                assign i_write_resp_start[j][i]    = i_msg_start[j][i] & (i_g[j][i].msg_type == MSG_WR_RESP);
            end
        end
    endgenerate

    assign w_g                  = {i_g, r_g[0], r_g[1], r_g[2]};

    assign w_misc_idx           = {i_misc_idx[0], r_misc_idx};
    assign w_misc_valid         = {(i_misc_valid[0] & {MAX_MISC_COUNT_CHUNK{w_rx_chunk_data_valid}}), r_misc_valid};
    assign w_misc_cnt           = {i_misc_cnt[0], r_misc_cnt};

    assign w_write_req_idx      = {i_write_req_idx[0], r_write_req_idx};
    assign w_write_req_valid    = {(i_write_req_valid[0] & {MAX_REQ_COUNT_CHUNK{w_rx_chunk_data_valid}}) , r_write_req_valid};
    assign w_write_req_cnt      = {i_write_req_cnt[0], r_write_req_cnt};

    assign w_read_req_idx       = {i_read_req_idx[0], r_read_req_idx};
    assign w_read_req_valid     = {(i_read_req_valid[0] & {MAX_REQ_COUNT_CHUNK{w_rx_chunk_data_valid}}), r_read_req_valid};
    assign w_read_req_cnt       = {i_read_req_cnt[0], r_read_req_cnt};

    assign w_write_data_idx     = {i_write_data_idx, r_write_data_idx[0], r_write_data_idx[1], r_write_data_idx[2]};
    assign w_write_data_valid   = {(i_write_data_valid & {(MAX_DATA_COUNT_CHUNK*DEC_MULTI){w_rx_chunk_data_valid}}), r_write_data_valid[0], r_write_data_valid[1], r_write_data_valid[2]};
    assign w_write_data_cnt     = {i_write_data_cnt, r_write_data_cnt[0], r_write_data_cnt[1], r_write_data_cnt[2]};

    assign w_read_data_idx      = {i_read_data_idx, r_read_data_idx[0], r_read_data_idx[1], r_read_data_idx[2]};
    assign w_read_data_valid    = {(i_read_data_valid & {(MAX_DATA_COUNT_CHUNK*DEC_MULTI){w_rx_chunk_data_valid}}), r_read_data_valid[0], r_read_data_valid[1], r_read_data_valid[2]};
    assign w_read_data_cnt      = {i_read_data_cnt, r_read_data_cnt[0], r_read_data_cnt[1], r_read_data_cnt[2]};

//Find start index for each message (misc, aw, ar, w, b, r)
//-------------------------------------------------------------
    integer idx_misc;
    integer idx_dec_misc;
    always_comb begin
        i_misc_cnt     = 'd0;
        i_misc_valid   = 'd0;
        i_misc_idx     = 'd0;
        for(idx_dec_misc = 0; idx_dec_misc < DEC_MULTI; idx_dec_misc = idx_dec_misc + 1) begin
            for(idx_misc = 0; idx_misc < 12; idx_misc = idx_misc + 1) begin
                if(i_misc_start[idx_dec_misc][idx_misc] == 1'b1) begin
                    if (i_misc_cnt[idx_dec_misc] < MAX_MISC_COUNT_CHUNK) begin
                        i_misc_idx[idx_dec_misc][i_misc_cnt[idx_dec_misc][MAX_MISC_WD-1:0]] = idx_misc;
                        i_misc_valid[idx_dec_misc][i_misc_cnt[idx_dec_misc][MAX_MISC_WD-1:0]] = 1'b1;
                        i_misc_cnt[idx_dec_misc] = i_misc_cnt[idx_dec_misc] + 1;
                    end
                end
            end
        end
    end

//-------------------------------------------------------------
    integer idx_wr_req;
    integer idx_dec_wr_req;
    always_comb begin
        i_write_req_cnt     = 'd0;
        i_write_req_valid   = 'd0;
        i_write_req_idx     = 'd0;
        for(idx_dec_wr_req = 0; idx_dec_wr_req < DEC_MULTI; idx_dec_wr_req = idx_dec_wr_req + 1) begin
            for(idx_wr_req = 0; idx_wr_req < 12 ; idx_wr_req = idx_wr_req + 1) begin
                if(i_write_req_start[idx_dec_wr_req][idx_wr_req] == 1'b1) begin
                    if (i_write_req_cnt[idx_dec_wr_req] < MAX_REQ_COUNT_CHUNK) begin
                        i_write_req_idx[idx_dec_wr_req][i_write_req_cnt[idx_dec_wr_req][MAX_REQ_WD-1:0]] = idx_wr_req;
                        i_write_req_valid[idx_dec_wr_req][i_write_req_cnt[idx_dec_wr_req][MAX_REQ_WD-1:0]] = 1'b1;
                        i_write_req_cnt[idx_dec_wr_req] = i_write_req_cnt[idx_dec_wr_req] + 1;
                    end
                end
            end
        end
    end

//-------------------------------------------------------------
    integer idx_rd_req;
    integer idx_dec_rd_req;
    always_comb begin
        i_read_req_cnt     = 'd0;
        i_read_req_valid   = 'd0;
        i_read_req_idx     = 'd0;
        for(idx_dec_rd_req = 0; idx_dec_rd_req < DEC_MULTI; idx_dec_rd_req = idx_dec_rd_req + 1) begin
            for(idx_rd_req = 0; idx_rd_req < 12 ; idx_rd_req = idx_rd_req + 1) begin
                if(i_read_req_start[idx_dec_rd_req][idx_rd_req] == 1'b1) begin
                    if (i_read_req_cnt[idx_dec_rd_req] < MAX_REQ_COUNT_CHUNK) begin
                        i_read_req_idx[idx_dec_rd_req][i_read_req_cnt[idx_dec_rd_req][MAX_REQ_WD-1:0]] = idx_rd_req;
                        i_read_req_valid[idx_dec_rd_req][i_read_req_cnt[idx_dec_rd_req][MAX_REQ_WD-1:0]] = 1'b1;
                        i_read_req_cnt[idx_dec_rd_req] = i_read_req_cnt[idx_dec_rd_req] + 1;
                    end
                end
            end
        end
    end

//-------------------------------------------------------------
    integer idx_wr_data;
    integer idx_dec_wr_data;
    always_comb begin
        i_write_data_cnt     = 'd0;
        i_write_data_valid   = 'd0;
        i_write_data_idx     = 'd0;
        for(idx_dec_wr_data = 0; idx_dec_wr_data < DEC_MULTI; idx_dec_wr_data = idx_dec_wr_data + 1) begin
            for(idx_wr_data = 0; idx_wr_data < 12; idx_wr_data = idx_wr_data + 1) begin
                if(i_write_data_start[idx_dec_wr_data][idx_wr_data] == 1'b1) begin
                    if (i_write_data_cnt[idx_dec_wr_data] < MAX_DATA_COUNT_CHUNK) begin
                        i_write_data_idx[idx_dec_wr_data][i_write_data_cnt[idx_dec_wr_data][MAX_DATA_WD-1:0]] = idx_wr_data;
                        i_write_data_valid[idx_dec_wr_data][i_write_data_cnt[idx_dec_wr_data][MAX_DATA_WD-1:0]] = 1'b1;
                        i_write_data_cnt[idx_dec_wr_data] = i_write_data_cnt[idx_dec_wr_data] + 1;
                    end
                end
            end
        end
    end

    assign w_write0_data_cnt_m1 = (r_write_data_cnt[0] == 0) ? 0 : (r_write_data_cnt[0] -1);
    assign w_write1_data_cnt_m1 = (r_write_data_cnt[1] == 0) ? 0 : (r_write_data_cnt[1] -1);

    always_comb begin
        w_write512_data_continue = 1'b0;
        w_write1024_data_continue = 1'b0;
        if(PHY_TYPE < 2) begin
            if(|r_write_data_valid[0]) begin
                if(f_g_others(r_write_data_idx[0][w_write0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b01)
                    w_write512_data_continue = 1'b1;
                else if(f_g_others(r_write_data_idx[0][w_write0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)
                    w_write1024_data_continue = 1'b1;
            end
            if(|r_write_data_valid[1]) begin
                if(f_g_others(r_write_data_idx[1][w_write1_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[1]) == 2'b10)
                    w_write1024_data_continue = 1'b1;
            end
        end else if(PHY_TYPE == 2) begin
            if(|r_write_data_valid[0]) begin
                if(f_g_others(r_write_data_idx[0][w_write0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)
                    w_write1024_data_continue = 1'b1;
            end
        end
    end

//-------------------------------------------------------------
    integer idx_rd_data;
    integer idx_dec_rd_data;
    always_comb begin
        i_read_data_cnt     = 'd0;
        i_read_data_valid   = 'd0;
        i_read_data_idx     = 'd0;
        for(idx_dec_rd_data = 0; idx_dec_rd_data < DEC_MULTI; idx_dec_rd_data = idx_dec_rd_data + 1) begin
            for(idx_rd_data = 0; idx_rd_data < 12 ; idx_rd_data = idx_rd_data + 1) begin
                if(i_read_data_start[idx_dec_rd_data][idx_rd_data] == 1'b1) begin
                    if (i_read_data_cnt[idx_dec_rd_data] < MAX_DATA_COUNT_CHUNK) begin
                        i_read_data_idx[idx_dec_rd_data][i_read_data_cnt[idx_dec_rd_data][MAX_DATA_WD-1:0]] = idx_rd_data;
                        i_read_data_valid[idx_dec_rd_data][i_read_data_cnt[idx_dec_rd_data][MAX_DATA_WD-1:0]] = 1'b1;
                        i_read_data_cnt[idx_dec_rd_data] = i_read_data_cnt[idx_dec_rd_data] + 1;
                    end
                end
            end
        end
    end

    assign w_read0_data_cnt_m1 = (r_read_data_cnt[0] == 0) ? 0 : (r_read_data_cnt[0] -1);
    assign w_read1_data_cnt_m1 = (r_read_data_cnt[1] == 0) ? 0 : (r_read_data_cnt[1] -1);

    always_comb begin
        w_read512_data_continue = 1'b0;
        w_read1024_data_continue = 1'b0;
        if(PHY_TYPE < 2) begin
            if(|r_read_data_valid[0]) begin
                if(f_g_others(r_read_data_idx[0][w_read0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b01)
                    w_read512_data_continue = 1'b1;
                else if(f_g_others(r_read_data_idx[0][w_read0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)
                    w_read1024_data_continue = 1'b1;
            end
            if(|r_read_data_valid[1]) begin
                if(f_g_others(r_read_data_idx[1][w_read1_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[1]) == 2'b10)
                    w_read1024_data_continue = 1'b1;
            end
        end else if(PHY_TYPE == 2) begin
            if(|r_read_data_valid[0]) begin
                if(f_g_others(r_read_data_idx[0][w_read0_data_cnt_m1[MAX_DATA_WD-1:0]], r_g[0]) == 2'b10)
                    w_read1024_data_continue = 1'b1;
            end
        end
    end

//-------------------------------------------------------------
    integer idx_wr_resp;
    integer idx_dec_wr_resp;
    always_comb begin
        i_write_resp_cnt     = 'd0;
        i_write_resp_valid   = 'd0;
        i_write_resp_idx     = 'd0;
        for(idx_dec_wr_resp = 0; idx_dec_wr_resp < DEC_MULTI; idx_dec_wr_resp = idx_dec_wr_resp + 1) begin
            for(idx_wr_resp = 0; idx_wr_resp < 12 ; idx_wr_resp = idx_wr_resp + 1) begin
                if(i_write_resp_start[idx_dec_wr_resp][idx_wr_resp] == 1'b1) begin
                    if (i_write_resp_cnt[idx_dec_wr_resp] < MAX_WR_RESP_COUNT_CHUNK) begin
                        i_write_resp_idx[idx_dec_wr_resp][i_write_resp_cnt[idx_dec_wr_resp]] = idx_wr_resp;
                        i_write_resp_valid[idx_dec_wr_resp][i_write_resp_cnt[idx_dec_wr_resp]] = 1'b1;
                        i_write_resp_cnt[idx_dec_wr_resp] = i_write_resp_cnt[idx_dec_wr_resp] + 1;
                    end
                end
            end
        end
    end

//-------------------------------------------------------------
    assign w_misc_cnt_for_wait          = (r_misc_cnt == 0) ? 0 : (r_misc_cnt -1);
    assign w_write_req_cnt_for_wait     = (r_write_req_cnt == 0) ? 0 : (r_write_req_cnt -1);
    assign w_read_req_cnt_for_wait      = (r_read_req_cnt == 0) ? 0 : (r_read_req_cnt -1);

    integer data_dec_sel;
    always_comb begin
        for(data_dec_sel = 0; data_dec_sel < (DEC_MULTI + 3); data_dec_sel = data_dec_sel + 1) begin
            w_valid_write_data_cnt[data_dec_sel] = (w_write_data_cnt[data_dec_sel] == 0) ? 0 : (w_write_data_cnt[data_dec_sel] -1);
            w_valid_read_data_cnt[data_dec_sel] = (w_read_data_cnt[data_dec_sel] == 0) ? 0 : (w_read_data_cnt[data_dec_sel] -1);
        end
    end

    // Pre-resolve the per-chunk granule indices used by wait_valid_chunk so
    // each f_g_*() helper invocation stays narrow and readable. The slot
    // indices (e.g. w_valid_*_data_cnt[k][MAX_DATA_WD-1:0]) are already in
    // range for the data_idx arrays; the X-injection problem we are fixing
    // is on the outer r_g[X][gid] select, which is what the helpers absorb.
    logic [3:0] w_wvc_wridx_c2;
    logic [3:0] w_wvc_rdidx_c2;
    logic [3:0] w_wvc_wridx_c1;
    logic [3:0] w_wvc_rdidx_c1;
    logic [3:0] w_wvc_wridx_c0;
    logic [3:0] w_wvc_rdidx_c0;
    logic [3:0] w_wvc_misc_idx;
    // Pre-resolve the misc-chunk granule "others" lookup into a wire because
    // the Conformal LEC parser does not accept a bit-select directly on a
    // function call result (e.g. f_g_others(...)[0]).
    logic [1:0] w_wvc_misc_others;

    assign w_wvc_wridx_c2 = r_write_data_idx[2][w_valid_write_data_cnt[0][MAX_DATA_WD-1:0]];
    assign w_wvc_rdidx_c2 = r_read_data_idx [2][w_valid_read_data_cnt [0][MAX_DATA_WD-1:0]];
    assign w_wvc_wridx_c1 = r_write_data_idx[1][w_valid_write_data_cnt[1][MAX_DATA_WD-1:0]];
    assign w_wvc_rdidx_c1 = r_read_data_idx [1][w_valid_read_data_cnt [1][MAX_DATA_WD-1:0]];
    assign w_wvc_wridx_c0 = r_write_data_idx[0][w_valid_write_data_cnt[2][MAX_DATA_WD-1:0]];
    assign w_wvc_rdidx_c0 = r_read_data_idx [0][w_valid_read_data_cnt [2][MAX_DATA_WD-1:0]];
    assign w_wvc_misc_idx = r_misc_idx[w_misc_cnt_for_wait[MAX_MISC_WD-1:0]];
    assign w_wvc_misc_others = f_g_others(w_wvc_misc_idx, r_g[0]);

    assign wait_valid_chunk[2] = ((r_write_data_valid[2][w_valid_write_data_cnt[0][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_wridx_c2, r_g[2]) == 2'b10) && (((f_g_msg_type(w_wvc_wridx_c2, r_g[2]) == MSG_WR_DATA) && (w_wvc_wridx_c2 + 30 > 36)) |
                                                                                                                                                          ((f_g_msg_type(w_wvc_wridx_c2, r_g[2]) == MSG_WRF_DATA) && (w_wvc_wridx_c2 + 27 > 36)))) ||
                                 (r_read_data_valid[2][w_valid_read_data_cnt[0][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_rdidx_c2, r_g[2]) == 2'b10) && (w_wvc_rdidx_c2 + 27 > 36))) ||
                                 ((PHY_TYPE > 1) && ((r_write_data_valid[1][w_valid_write_data_cnt[1][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_wridx_c1, r_g[1]) == 2'b10) && ((f_g_msg_type(w_wvc_wridx_c1, r_g[1]) == MSG_WR_DATA) |
                                                                                                                                                                            (f_g_msg_type(w_wvc_wridx_c1, r_g[1]) == MSG_WRF_DATA))) ||
                                                    (r_read_data_valid[1][w_valid_read_data_cnt[1][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_rdidx_c1, r_g[1]) == 2'b10)))) ||
                                 ((PHY_TYPE == 3) && ((r_write_data_valid[0][w_valid_write_data_cnt[2][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_wridx_c0, r_g[0]) == 2'b10) && ((f_g_msg_type(w_wvc_wridx_c0, r_g[0]) == MSG_WR_DATA) |
                                                                                                                                                                              (f_g_msg_type(w_wvc_wridx_c0, r_g[0]) == MSG_WRF_DATA))) ||
                                                     (r_read_data_valid[0][w_valid_read_data_cnt[2][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_rdidx_c0, r_g[0]) == 2'b10))));

    assign wait_valid_chunk[1] = ((r_write_data_valid[1][w_valid_write_data_cnt[1][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_wridx_c1, r_g[1]) == 2'b01) && (((f_g_msg_type(w_wvc_wridx_c1, r_g[1]) == MSG_WR_DATA) && (w_wvc_wridx_c1 + 15 > 24)) |
                                                                                                                                                          ((f_g_msg_type(w_wvc_wridx_c1, r_g[1]) == MSG_WRF_DATA) && (w_wvc_wridx_c1 + 14 > 24)))) ||
                                 (r_read_data_valid[1][w_valid_read_data_cnt[1][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_rdidx_c1, r_g[1]) == 2'b01) && (w_wvc_rdidx_c1 + 14 > 24))) ||
                                 ((PHY_TYPE > 1) && ((r_write_data_valid[0][w_valid_write_data_cnt[2][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_wridx_c0, r_g[0]) == 2'b01) && ((f_g_msg_type(w_wvc_wridx_c0, r_g[0]) == MSG_WR_DATA) |
                                                                                                                                                                            (f_g_msg_type(w_wvc_wridx_c0, r_g[0]) == MSG_WRF_DATA))) ||
                                                    (r_read_data_valid[0][w_valid_read_data_cnt[2][MAX_DATA_WD-1:0]] && (f_g_others(w_wvc_rdidx_c0, r_g[0]) == 2'b01))));

    assign wait_valid_chunk[0] = ((|r_misc_valid && (w_wvc_misc_others[0] == 1'b1) && (w_wvc_misc_idx + 2 > 12)) |
                                  (|r_write_req_valid && (r_write_req_idx[w_write_req_cnt_for_wait[MAX_REQ_WD-1:0]] + 3 > 12)) |
                                  (|r_read_req_valid && (r_read_req_idx[w_read_req_cnt_for_wait[MAX_REQ_WD-1:0]] + 3 > 12)) |
                                  (|r_write_data_valid[0] && (f_g_others(w_wvc_wridx_c0, r_g[0]) == 2'b00) && (((f_g_msg_type(w_wvc_wridx_c0, r_g[0]) == MSG_WR_DATA) && (w_wvc_wridx_c0 + 8 > 12)) |
                                                                                                              ((f_g_msg_type(w_wvc_wridx_c0, r_g[0]) == MSG_WRF_DATA) && (w_wvc_wridx_c0 + 7 > 12))) ) |
                                  (|r_read_data_valid[0] && (f_g_others(w_wvc_rdidx_c0, r_g[0]) == 2'b00) && (w_wvc_rdidx_c0 + 8 > 12)));

//-------------------------------------------------------------
    st_misc_grantcredit_packet      [DEC_MULTI-1:0][MAX_MISC_COUNT_CHUNK-1:0]       w_misc_packet               ;
    st_misc_activation_packet                                                       w_misc_activation_packet    ;
    st_write_req_packet_tmp         [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]        w_write_req_packet_tmp      ;
    st_read_req_packet_tmp          [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]        w_read_req_packet_tmp       ;
    st_write_data256_packet_tmp     [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0]       w_write_data256_packet_tmp  ;
    st_write_data512_packet_tmp     [DEC_MULTI-1:0]                                 w_write_data512_packet_tmp  ;
    st_write_data1024_packet_tmp    [DEC_MULTI-1:0]                                 w_write_data1024_packet_tmp ;
    st_read_data256_packet_tmp      [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0]       w_read_data256_packet_tmp   ;
    st_read_data512_packet_tmp      [DEC_MULTI-1:0]                                 w_read_data512_packet_tmp   ;
    st_read_data1024_packet_tmp     [DEC_MULTI-1:0]                                 w_read_data1024_packet_tmp  ;
    st_write_resp_packet_tmp        [DEC_MULTI-1:0][MAX_WR_RESP_COUNT_CHUNK-1:0]    w_write_resp_packet_tmp     ;

    integer idx_msg_sel, idx_dec_sel;
    always_comb begin
        for(idx_dec_sel = 0; idx_dec_sel < DEC_MULTI; idx_dec_sel = idx_dec_sel + 1) begin
            for(idx_msg_sel = 0; idx_msg_sel < MAX_MISC_COUNT_CHUNK; idx_msg_sel = idx_msg_sel + 1) begin
                w_misc_packet[idx_dec_sel][idx_msg_sel] = w_g[(idx_dec_sel*12 + w_misc_idx[idx_dec_sel][idx_msg_sel] + 24) +: 2];
            end

            for(idx_msg_sel = 0; idx_msg_sel < MAX_REQ_COUNT_CHUNK; idx_msg_sel = idx_msg_sel + 1) begin
                w_write_req_packet_tmp[idx_dec_sel][idx_msg_sel] = w_g[(idx_dec_sel*12 + w_write_req_idx[idx_dec_sel][idx_msg_sel] + 24) +: 3];
                w_read_req_packet_tmp[idx_dec_sel][idx_msg_sel] = w_g[(idx_dec_sel*12 + w_read_req_idx[idx_dec_sel][idx_msg_sel] + 24) +: 3];
            end

            for(idx_msg_sel = 0; idx_msg_sel < MAX_DATA_COUNT_CHUNK; idx_msg_sel = idx_msg_sel + 1) begin
                if(w_g[(2+idx_dec_sel)*12 + w_write_data_idx[2+idx_dec_sel][idx_msg_sel]].msg_type == MSG_WR_DATA)
                    w_write_data256_packet_tmp[idx_dec_sel][idx_msg_sel] = w_g[(idx_dec_sel*12 + w_write_data_idx[2+idx_dec_sel][idx_msg_sel] + 24) +: 8];
                else
                    w_write_data256_packet_tmp[idx_dec_sel][idx_msg_sel] = w_g[(idx_dec_sel*12 + w_write_data_idx[2+idx_dec_sel][idx_msg_sel] + 24) +: 7];

                w_read_data256_packet_tmp[idx_dec_sel][idx_msg_sel] = w_g[(idx_dec_sel*12 + w_read_data_idx[2+idx_dec_sel][idx_msg_sel] + 24) +: 8];
            end

            if(w_g[(1+idx_dec_sel)*12 + w_write_data_idx[1+idx_dec_sel][w_valid_write_data_cnt[1+idx_dec_sel][MAX_DATA_WD-1:0]]].msg_type == MSG_WR_DATA)
                w_write_data512_packet_tmp[idx_dec_sel] = w_g[(idx_dec_sel*12 + w_write_data_idx[1+idx_dec_sel][w_valid_write_data_cnt[1+idx_dec_sel][MAX_DATA_WD-1:0]] + 12) +: 15];
            else
                w_write_data512_packet_tmp[idx_dec_sel] = w_g[(idx_dec_sel*12 + w_write_data_idx[1+idx_dec_sel][w_valid_write_data_cnt[1+idx_dec_sel][MAX_DATA_WD-1:0]] + 12) +: 14];

            if(w_g[idx_dec_sel*12 + w_write_data_idx[idx_dec_sel][w_valid_write_data_cnt[idx_dec_sel][MAX_DATA_WD-1:0]]].msg_type == MSG_WR_DATA)
                w_write_data1024_packet_tmp[idx_dec_sel] = w_g[(idx_dec_sel*12 + w_write_data_idx[idx_dec_sel][w_valid_write_data_cnt[idx_dec_sel][MAX_DATA_WD-1:0]]) +: 30];
            else
                w_write_data1024_packet_tmp[idx_dec_sel] = w_g[(idx_dec_sel*12 + w_write_data_idx[idx_dec_sel][w_valid_write_data_cnt[idx_dec_sel][MAX_DATA_WD-1:0]]) +: 27];

            w_read_data512_packet_tmp[idx_dec_sel] = w_g[(idx_dec_sel*12 + w_read_data_idx[1+idx_dec_sel][w_valid_read_data_cnt[1+idx_dec_sel][MAX_DATA_WD-1:0]] + 12) +: 14];
            w_read_data1024_packet_tmp[idx_dec_sel] = w_g[(idx_dec_sel*12 + w_read_data_idx[idx_dec_sel][w_valid_read_data_cnt[idx_dec_sel][MAX_DATA_WD-1:0]]) +: 27];

            for(idx_msg_sel = 0; idx_msg_sel < MAX_WR_RESP_COUNT_CHUNK; idx_msg_sel = idx_msg_sel + 1) begin
                w_write_resp_packet_tmp[idx_dec_sel][idx_msg_sel]        = w_g[(idx_dec_sel*12 + i_write_resp_idx[idx_dec_sel][idx_msg_sel]+36) +: 1];
            end
        end
    end
    assign w_misc_activation_packet = w_g[(i_misc_idx[0][0]+36) +: 1];

//-------------------------------------------------------------
    st_write_req_packet         [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]        w_write_req_packet          ;
    st_read_req_packet          [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0]        w_read_req_packet           ;
    st_write_data256_packet     [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0]       w_write_data256_packet      ;
    st_write_data512_packet     [DEC_MULTI-1:0]                                 w_write_data512_packet      ;
    st_write_data1024_packet    [DEC_MULTI-1:0]                                 w_write_data1024_packet     ;
    st_read_data256_packet      [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0]       w_read_data256_packet       ;
    st_read_data512_packet      [DEC_MULTI-1:0]                                 w_read_data512_packet       ;
    st_read_data1024_packet     [DEC_MULTI-1:0]                                 w_read_data1024_packet      ;
    st_write_resp_packet        [DEC_MULTI-1:0][MAX_WR_RESP_COUNT_CHUNK-1:0]    w_write_resp_packet         ;

    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0][63:0]        awaddr_flat;
    logic [DEC_MULTI-1:0][MAX_REQ_COUNT_CHUNK-1:0][63:0]        araddr_flat;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0][255:0]      wdata_256_flat;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0][31:0]       wstrb_256_flat;
    logic [DEC_MULTI-1:0][511:0]                                wdata_512_flat;
    logic [DEC_MULTI-1:0][63:0]                                 wstrb_512_flat;
    logic [DEC_MULTI-1:0][1023:0]                               wdata_1024_flat;
    logic [DEC_MULTI-1:0][127:0]                                wstrb_1024_flat;
    logic [DEC_MULTI-1:0][MAX_DATA_COUNT_CHUNK-1:0][255:0]      rdata_256_flat;
    logic [DEC_MULTI-1:0][511:0]                                rdata_512_flat;
    logic [DEC_MULTI-1:0][1023:0]                               rdata_1024_flat;


    always_comb begin
        for(int unsigned k = 0; k < DEC_MULTI; k = k + 1) begin
            for(int unsigned j = 0; j < MAX_REQ_COUNT_CHUNK; j = j + 1) begin
                for(int unsigned i = 0; i < 8 ; i = i+1) begin
                    awaddr_flat[k][j][(i+1)*8-1 -: 8] = w_write_req_packet_tmp[k][j].awaddr[i];
                    araddr_flat[k][j][(i+1)*8-1 -: 8] = w_read_req_packet_tmp[k][j].araddr[i];
                end
            end

            for(int unsigned j = 0; j < MAX_DATA_COUNT_CHUNK; j = j + 1) begin
                for(int unsigned i = 0; i < 4 ; i = i+1) begin
                    wstrb_256_flat[k][j][(i+1)*8-1 -: 8] = w_write_data256_packet_tmp[k][j].wstrb[i];
                end
                for(int unsigned i = 0; i < 32; i = i + 1) begin
                    wdata_256_flat[k][j][(i+1)*8-1 -: 8] = w_write_data256_packet_tmp[k][j].wdata[i];
                    rdata_256_flat[k][j][(i+1)*8-1 -: 8] = w_read_data256_packet_tmp[k][j].rdata[i];
                end
            end

            for(int unsigned i = 0; i < 64; i = i + 1) begin
                wdata_512_flat[k][(i+1)*8-1 -: 8]  = w_write_data512_packet_tmp[k].wdata[i];
                rdata_512_flat[k][(i+1)*8-1 -: 8]  = w_read_data512_packet_tmp[k].rdata[i];
            end

            for(int unsigned i = 0; i < 128; i = i + 1) begin
                wdata_1024_flat[k][(i+1)*8-1 -: 8] = w_write_data1024_packet_tmp[k].wdata[i];
                rdata_1024_flat[k][(i+1)*8-1 -: 8] = w_read_data1024_packet_tmp[k].rdata[i];
            end

            for(int unsigned i = 0; i < 8; i = i + 1) begin
                wstrb_512_flat[k][(i+1)*8-1 -: 8] = w_write_data512_packet_tmp[k].wstrb[i];
            end

            for(int unsigned i = 0; i < 16; i = i + 1) begin
                wstrb_1024_flat[k][(i+1)*8-1 -: 8] = w_write_data1024_packet_tmp[k].wstrb[i];
            end
        end
    end

    integer idx_msg_sel_tmp, idx_dec_sel_tmp;

    always_comb begin
        for(idx_dec_sel_tmp = 0; idx_dec_sel_tmp < DEC_MULTI; idx_dec_sel_tmp = idx_dec_sel_tmp + 1) begin
            for(idx_msg_sel_tmp = 0; idx_msg_sel_tmp < MAX_REQ_COUNT_CHUNK; idx_msg_sel_tmp = idx_msg_sel_tmp + 1) begin
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awid           = {w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awid_1, w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awid_0};
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awaddr         = awaddr_flat[idx_dec_sel_tmp][idx_msg_sel_tmp];
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awlen          = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awlen;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awsize         = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awsize;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awlock         = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awlock;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awcache        = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awcache;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awprot         = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awprot;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].awqos          = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].awqos;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].prof           = {w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_1, w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_0};
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen     = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type       = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rp             = w_write_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rp;
                w_write_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rsvd           = 'd0;

                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arid            = {w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arid_1, w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arid_0};
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].araddr          = araddr_flat[idx_dec_sel_tmp][idx_msg_sel_tmp];
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arlen           = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arlen;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arsize          = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arsize;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arlock          = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arlock;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arcache         = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arcache;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arprot          = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arprot;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].arqos           = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].arqos;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].prof            = {w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_1, w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_0};
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen      = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type        = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rp              = w_read_req_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rp;
                w_read_req_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rsvd            = 'd0;
            end

            for(idx_msg_sel_tmp = 0; idx_msg_sel_tmp < MAX_DATA_COUNT_CHUNK; idx_msg_sel_tmp = idx_msg_sel_tmp + 1) begin
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].wdata      = wdata_256_flat[idx_dec_sel_tmp][idx_msg_sel_tmp];
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].wstrb      = wstrb_256_flat[idx_dec_sel_tmp][idx_msg_sel_tmp];
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].prof       = {w_write_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_1, w_write_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_0};
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen = w_write_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen;
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type   = w_write_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type;
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rp         = w_write_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rp;
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].dlength    = w_write_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].dlength;
                w_write_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rsvd       = 'd0;

                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rdata       = rdata_256_flat[idx_dec_sel_tmp][idx_msg_sel_tmp];
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rid         = {w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rid_1, w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rid_0};
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rresp       = w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rresp;
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rlast       = w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rlast;
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].prof        = {w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_1, w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_0};
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen  = w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen;
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type    = w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type;
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rp          = w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rp;
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].dlength     = w_read_data256_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].dlength;
                w_read_data256_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rsvd        = 'd0;
            end

            w_write_data512_packet[idx_dec_sel_tmp].wdata                       = wdata_512_flat[idx_dec_sel_tmp];
            w_write_data512_packet[idx_dec_sel_tmp].wstrb                       = wstrb_512_flat[idx_dec_sel_tmp];
            w_write_data512_packet[idx_dec_sel_tmp].prof                        = {w_write_data512_packet_tmp[idx_dec_sel_tmp].prof_1, w_write_data512_packet_tmp[idx_dec_sel_tmp].prof_0};
            w_write_data512_packet[idx_dec_sel_tmp].profextlen                  = w_write_data512_packet_tmp[idx_dec_sel_tmp].profextlen;
            w_write_data512_packet[idx_dec_sel_tmp].msg_type                    = w_write_data512_packet_tmp[idx_dec_sel_tmp].msg_type;
            w_write_data512_packet[idx_dec_sel_tmp].rp                          = w_write_data512_packet_tmp[idx_dec_sel_tmp].rp;
            w_write_data512_packet[idx_dec_sel_tmp].dlength                     = w_write_data512_packet_tmp[idx_dec_sel_tmp].dlength;

            w_write_data1024_packet[idx_dec_sel_tmp].wdata                      = wdata_1024_flat[idx_dec_sel_tmp];
            w_write_data1024_packet[idx_dec_sel_tmp].wstrb                      = wstrb_1024_flat[idx_dec_sel_tmp];
            w_write_data1024_packet[idx_dec_sel_tmp].prof                       = {w_write_data1024_packet_tmp[idx_dec_sel_tmp].prof_1, w_write_data1024_packet_tmp[idx_dec_sel_tmp].prof_0};
            w_write_data1024_packet[idx_dec_sel_tmp].profextlen                 = w_write_data1024_packet_tmp[idx_dec_sel_tmp].profextlen;
            w_write_data1024_packet[idx_dec_sel_tmp].msg_type                   = w_write_data1024_packet_tmp[idx_dec_sel_tmp].msg_type;
            w_write_data1024_packet[idx_dec_sel_tmp].rp                         = w_write_data1024_packet_tmp[idx_dec_sel_tmp].rp;
            w_write_data1024_packet[idx_dec_sel_tmp].dlength                    = w_write_data1024_packet_tmp[idx_dec_sel_tmp].dlength;
            w_write_data1024_packet[idx_dec_sel_tmp].rsvd                       = 'd0;

            w_read_data512_packet[idx_dec_sel_tmp].rdata                        = rdata_512_flat[idx_dec_sel_tmp];
            w_read_data512_packet[idx_dec_sel_tmp].rid                          = {w_read_data512_packet_tmp[idx_dec_sel_tmp].rid_1, w_read_data512_packet_tmp[idx_dec_sel_tmp].rid_0} ;
            w_read_data512_packet[idx_dec_sel_tmp].rresp                        = w_read_data512_packet_tmp[idx_dec_sel_tmp].rresp;
            w_read_data512_packet[idx_dec_sel_tmp].rlast                        = w_read_data512_packet_tmp[idx_dec_sel_tmp].rlast;
            w_read_data512_packet[idx_dec_sel_tmp].prof                         = {w_read_data512_packet_tmp[idx_dec_sel_tmp].prof_1, w_read_data512_packet_tmp[idx_dec_sel_tmp].prof_0};
            w_read_data512_packet[idx_dec_sel_tmp].profextlen                   = w_read_data512_packet_tmp[idx_dec_sel_tmp].profextlen;
            w_read_data512_packet[idx_dec_sel_tmp].msg_type                     = w_read_data512_packet_tmp[idx_dec_sel_tmp].msg_type;
            w_read_data512_packet[idx_dec_sel_tmp].rp                           = w_read_data512_packet_tmp[idx_dec_sel_tmp].rp;
            w_read_data512_packet[idx_dec_sel_tmp].dlength                      = w_read_data512_packet_tmp[idx_dec_sel_tmp].dlength;
            w_read_data512_packet[idx_dec_sel_tmp].rsvd                         = 'd0;

            w_read_data1024_packet[idx_dec_sel_tmp].rdata                       = rdata_1024_flat[idx_dec_sel_tmp];
            w_read_data1024_packet[idx_dec_sel_tmp].rid                         = {w_read_data1024_packet_tmp[idx_dec_sel_tmp].rid_1, w_read_data1024_packet_tmp[idx_dec_sel_tmp].rid_0};
            w_read_data1024_packet[idx_dec_sel_tmp].rresp                       = w_read_data1024_packet_tmp[idx_dec_sel_tmp].rresp;
            w_read_data1024_packet[idx_dec_sel_tmp].rlast                       = w_read_data1024_packet_tmp[idx_dec_sel_tmp].rlast;
            w_read_data1024_packet[idx_dec_sel_tmp].prof                        = {w_read_data1024_packet_tmp[idx_dec_sel_tmp].prof_1, w_read_data1024_packet_tmp[idx_dec_sel_tmp].prof_0};
            w_read_data1024_packet[idx_dec_sel_tmp].profextlen                  = w_read_data1024_packet_tmp[idx_dec_sel_tmp].profextlen;
            w_read_data1024_packet[idx_dec_sel_tmp].msg_type                    = w_read_data1024_packet_tmp[idx_dec_sel_tmp].msg_type;
            w_read_data1024_packet[idx_dec_sel_tmp].rp                          = w_read_data1024_packet_tmp[idx_dec_sel_tmp].rp;
            w_read_data1024_packet[idx_dec_sel_tmp].dlength                     = w_read_data1024_packet_tmp[idx_dec_sel_tmp].dlength;
            w_read_data1024_packet[idx_dec_sel_tmp].rsvd                        = 'd0;

            for(idx_msg_sel_tmp = 0; idx_msg_sel_tmp < MAX_WR_RESP_COUNT_CHUNK; idx_msg_sel_tmp = idx_msg_sel_tmp + 1) begin
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].bid           = {w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].bid_1, w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].bid_0};
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].bresp         = w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].bresp;
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].prof          = {w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_1, w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].prof_0};
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen    = w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].profextlen;
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type      = w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].msg_type;
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rp            = w_write_resp_packet_tmp[idx_dec_sel_tmp][idx_msg_sel_tmp].rp;
                w_write_resp_packet[idx_dec_sel_tmp][idx_msg_sel_tmp].rsvd          = 'd0;
            end
        end
    end

//-------------------------------------------------------------
    genvar x,y,z;
    generate
        for (z = 0; z < RP_COUNT; z = z + 1) begin
            for(y = 0; y < DEC_MULTI; y = y + 1) begin

                for (x = 0; x < MAX_REQ_COUNT_CHUNK; x = x + 1) begin
                    assign O_WR_REQ_FIFO_SDATA[z][y][x] = (z == w_write_req_packet[y][x].rp) ? { w_write_req_packet[y][x].awid       ,
                                                                                                 w_write_req_packet[y][x].awaddr     ,
                                                                                                 w_write_req_packet[y][x].awlen      ,
                                                                                                 w_write_req_packet[y][x].awsize     ,
                                                                                                 w_write_req_packet[y][x].awlock     ,
                                                                                                 w_write_req_packet[y][x].awcache    ,
                                                                                                 w_write_req_packet[y][x].awprot     ,
                                                                                                 w_write_req_packet[y][x].awqos      } : {(AW_AR_FIFO_DATA_WIDTH){1'b0}};
                    assign O_WR_REQ_FIFO_SVALID[z][y][x] = (z == w_write_req_packet[y][x].rp) ? (|wait_valid_chunk) ? (w_write_req_valid[y][x] && w_rx_chunk_data_valid) : w_write_req_valid[y][x] : 1'b0;
                end

                assign O_WR_DATA_FIFO_SDATA[z][y][0] = (z == w_write_data1024_packet[y].rp) ? w_write_data1024_packet[y].wdata : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};
                assign O_WR_DATA_FIFO_SDATA[z][y][1] = (z == w_write_data512_packet[y].rp) ? {{(AXI_PEER_DIE_MAX_DATA_WD-512){1'b0}}, w_write_data512_packet[y].wdata[511:0]} : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};
                assign O_WR_DATA_FIFO_SDATA[z][y][2] = (z == w_write_data256_packet[y][0].rp) ? {{(AXI_PEER_DIE_MAX_DATA_WD-256){1'b0}}, w_write_data256_packet[y][0].wdata[255:0]} : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};
                assign O_WR_DATA_FIFO_SDATA[z][y][3] = (z == w_write_data256_packet[y][1].rp) ? {{(AXI_PEER_DIE_MAX_DATA_WD-256){1'b0}}, w_write_data256_packet[y][1].wdata[255:0]} : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};

                assign O_WR_DATA_FIFO_SDATA_STRB[z][y][0] = (z == w_write_data1024_packet[y].rp) ? (w_write_data1024_packet[y].msg_type == MSG_WR_DATA) ? w_write_data1024_packet[y].wstrb : 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff : {AXI_STRB_WD{1'b0}};
                assign O_WR_DATA_FIFO_SDATA_STRB[z][y][1] = (z == w_write_data512_packet[y].rp) ? (w_write_data512_packet[y].msg_type == MSG_WR_DATA) ? w_write_data512_packet[y].wstrb : {{(AXI_STRB_WD-64){1'b0}}, 64'hffff_ffff_ffff_ffff} : {AXI_STRB_WD{1'b0}};
                assign O_WR_DATA_FIFO_SDATA_STRB[z][y][2] = (z == w_write_data256_packet[y][0].rp) ? (w_write_data256_packet[y][0].msg_type == MSG_WR_DATA) ? w_write_data256_packet[y][0].wstrb : {{(AXI_STRB_WD-32){1'b0}}, 32'hffff_ffff} : {AXI_STRB_WD{1'b0}};
                assign O_WR_DATA_FIFO_SDATA_STRB[z][y][3] = (z == w_write_data256_packet[y][1].rp) ? (w_write_data256_packet[y][1].msg_type == MSG_WR_DATA) ? w_write_data256_packet[y][1].wstrb : {{(AXI_STRB_WD-32){1'b0}}, 32'hffff_ffff} : {AXI_STRB_WD{1'b0}};

                assign O_WR_DATA_FIFO_SDATA_WDATAF[z][y][0] = (z == w_write_data1024_packet[y].rp) ? (w_write_data1024_packet[y].msg_type == MSG_WR_DATA) ? 1'b0 : 1'b1 : 1'b0;
                assign O_WR_DATA_FIFO_SDATA_WDATAF[z][y][1] = (z == w_write_data512_packet[y].rp) ? (w_write_data512_packet[y].msg_type == MSG_WR_DATA) ? 1'b0 : 1'b1 : 1'b0;
                assign O_WR_DATA_FIFO_SDATA_WDATAF[z][y][2] = (z == w_write_data256_packet[y][0].rp) ? (w_write_data256_packet[y][0].msg_type == MSG_WR_DATA) ? 1'b0 : 1'b1 : 1'b0;
                assign O_WR_DATA_FIFO_SDATA_WDATAF[z][y][3] = (z == w_write_data256_packet[y][1].rp) ? (w_write_data256_packet[y][1].msg_type == MSG_WR_DATA) ? 1'b0 : 1'b1 : 1'b0;

                assign O_WR_DATA_FIFO_SVALID[z][y][0] = (z == w_write_data1024_packet[y].rp) ? (w_write_data1024_packet[y].dlength == 2'b10) ? (|wait_valid_chunk) ? (w_write_data_valid[y][w_valid_write_data_cnt[y][MAX_DATA_WD-1:0]] && w_rx_chunk_data_valid) : w_write_data_valid[y][w_valid_write_data_cnt[y][MAX_DATA_WD-1:0]] : 1'b0 : 1'b0;
                assign O_WR_DATA_FIFO_SVALID[z][y][1] = (z == w_write_data512_packet[y].rp) ? (w_write_data512_packet[y].dlength == 2'b01) ? (|wait_valid_chunk) ? (w_write_data_valid[y+1][w_valid_write_data_cnt[y+1][MAX_DATA_WD-1:0]] && w_rx_chunk_data_valid) : w_write_data_valid[y+1][w_valid_write_data_cnt[y+1][MAX_DATA_WD-1:0]] : 1'b0 : 1'b0;
                assign O_WR_DATA_FIFO_SVALID[z][y][2] = (z == w_write_data256_packet[y][0].rp) ? (w_write_data256_packet[y][0].dlength == 2'b00) ? (|wait_valid_chunk) ? (w_write_data_valid[y+2][0] && w_rx_chunk_data_valid) : (w_write_data_valid[y+2][0] && !r_write_data_mask) : 1'b0 : 1'b0;
                assign O_WR_DATA_FIFO_SVALID[z][y][3] = (z == w_write_data256_packet[y][1].rp) ? (w_write_data256_packet[y][1].dlength == 2'b00) ? (|wait_valid_chunk) ? (w_write_data_valid[y+2][1] && w_rx_chunk_data_valid) : w_write_data_valid[y+2][1] : 1'b0 : 1'b0;


                for (x = 0; x < MAX_WR_RESP_COUNT_CHUNK; x = x + 1) begin
                    assign O_WR_RESP_FIFO_SDATA[z][y][x] = (z == w_write_resp_packet[y][x].rp) ? { w_write_resp_packet[y][x].bid       ,
                                                                                                   w_write_resp_packet[y][x].bresp      } : {(B_FIFO_DATA_WIDTH){1'b0}};
                    assign O_WR_RESP_FIFO_SVALID[z][y][x] = (z == w_write_resp_packet[y][x].rp) ? (i_write_resp_valid[y][x] && w_rx_chunk_data_valid) : 1'b0;
                end

                for (x = 0; x < MAX_REQ_COUNT_CHUNK; x = x + 1) begin
                    assign O_RD_REQ_FIFO_SDATA[z][y][x] = (z == w_read_req_packet[y][x].rp) ? { w_read_req_packet[y][x].arid       ,
                                                                                                w_read_req_packet[y][x].araddr     ,
                                                                                                w_read_req_packet[y][x].arlen      ,
                                                                                                w_read_req_packet[y][x].arsize     ,
                                                                                                w_read_req_packet[y][x].arlock     ,
                                                                                                w_read_req_packet[y][x].arcache    ,
                                                                                                w_read_req_packet[y][x].arprot     ,
                                                                                                w_read_req_packet[y][x].arqos      } : {(AW_AR_FIFO_DATA_WIDTH){1'b0}};
                    assign O_RD_REQ_FIFO_SVALID[z][y][x] = (z == w_read_req_packet[y][x].rp) ? (|wait_valid_chunk) ? (w_read_req_valid[y][x] && w_rx_chunk_data_valid) : w_read_req_valid[y][x] : 1'b0;
                end

                assign O_RD_DATA_FIFO_SDATA[z][y][0] = (z == w_read_data1024_packet[y].rp) ? w_read_data1024_packet[y].rdata[1023:0] : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};
                assign O_RD_DATA_FIFO_SDATA[z][y][1] = (z == w_read_data512_packet[y].rp) ? {{(AXI_PEER_DIE_MAX_DATA_WD-512){1'b0}}, w_read_data512_packet[y].rdata[511:0]} : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};
                assign O_RD_DATA_FIFO_SDATA[z][y][2] = (z == w_read_data256_packet[y][0].rp) ? {{(AXI_PEER_DIE_MAX_DATA_WD-256){1'b0}}, w_read_data256_packet[y][0].rdata[255:0]} : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};
                assign O_RD_DATA_FIFO_SDATA[z][y][3] = (z == w_read_data256_packet[y][1].rp) ? {{(AXI_PEER_DIE_MAX_DATA_WD-256){1'b0}}, w_read_data256_packet[y][1].rdata[255:0]} : {(AXI_PEER_DIE_MAX_DATA_WD){1'b0}};

                assign O_RD_DATA_FIFO_EXT_SDATA[z][y][0] = (z == w_read_data1024_packet[y].rp) ? {w_read_data1024_packet[y].rid     ,
                                                                                                  w_read_data1024_packet[y].rresp   ,
                                                                                                  w_read_data1024_packet[y].rlast} : {R_FIFO_EXT_DATA_WIDTH{1'b0}};

                assign O_RD_DATA_FIFO_EXT_SDATA[z][y][1] = (z == w_read_data512_packet[y].rp) ? {w_read_data512_packet[y].rid     ,
                                                                                                 w_read_data512_packet[y].rresp   ,
                                                                                                 w_read_data512_packet[y].rlast} : {R_FIFO_EXT_DATA_WIDTH{1'b0}};

                assign O_RD_DATA_FIFO_EXT_SDATA[z][y][2] = (z == w_read_data256_packet[y][0].rp) ? {w_read_data256_packet[y][0].rid     ,
                                                                                                    w_read_data256_packet[y][0].rresp   ,
                                                                                                    w_read_data256_packet[y][0].rlast} : {R_FIFO_EXT_DATA_WIDTH{1'b0}};

                assign O_RD_DATA_FIFO_EXT_SDATA[z][y][3] = (z == w_read_data256_packet[y][1].rp) ? {w_read_data256_packet[y][1].rid     ,
                                                                                                    w_read_data256_packet[y][1].rresp   ,
                                                                                                    w_read_data256_packet[y][1].rlast} : {R_FIFO_EXT_DATA_WIDTH{1'b0}};

                assign O_RD_DATA_FIFO_SVALID[z][y][0] = (z == w_read_data1024_packet[y].rp) ? (w_read_data1024_packet[y].dlength == 2'b10) ? (|wait_valid_chunk) ? (w_read_data_valid[y][w_valid_read_data_cnt[y][MAX_DATA_WD-1:0]] && w_rx_chunk_data_valid) : w_read_data_valid[y][w_valid_read_data_cnt[y][MAX_DATA_WD-1:0]] : 1'b0 : 1'b0;
                assign O_RD_DATA_FIFO_SVALID[z][y][1] = (z == w_read_data512_packet[y].rp) ? (w_read_data512_packet[y].dlength == 2'b01) ? (|wait_valid_chunk) ? (w_read_data_valid[y+1][w_valid_read_data_cnt[y+1][MAX_DATA_WD-1:0]] && w_rx_chunk_data_valid) : w_read_data_valid[y+1][w_valid_read_data_cnt[y+1][MAX_DATA_WD-1:0]] : 1'b0 : 1'b0;
                assign O_RD_DATA_FIFO_SVALID[z][y][2] = (z == w_read_data256_packet[y][0].rp) ? (w_read_data256_packet[y][0].dlength == 2'b00) ? (|wait_valid_chunk) ? (w_read_data_valid[y+2][0] && w_rx_chunk_data_valid) : (w_read_data_valid[y+2][0] && !r_read_data_mask): 1'b0 : 1'b0;
                assign O_RD_DATA_FIFO_SVALID[z][y][3] = (z == w_read_data256_packet[y][1].rp) ? (w_read_data256_packet[y][1].dlength == 2'b00) ? (|wait_valid_chunk) ? (w_read_data_valid[y+2][1] && w_rx_chunk_data_valid) : w_read_data_valid[y+2][1] : 1'b0 : 1'b0;

            end
        end
    endgenerate

    //-------------------------------------------------------------
    generate
        for(y = 0; y < DEC_MULTI; y = y + 1) begin
            for(x = 0; x < MAX_MISC_COUNT_CHUNK; x = x + 1) begin
                assign O_CRDTGRANT_WRESPCRED3[y][x] = w_misc_packet[y][x].wrespcred3;
                assign O_CRDTGRANT_WRESPCRED2[y][x] = w_misc_packet[y][x].wrespcred2;
                assign O_CRDTGRANT_WRESPCRED1[y][x] = w_misc_packet[y][x].wrespcred1;
                assign O_CRDTGRANT_WRESPCRED0[y][x] = {w_misc_packet[y][x].wrespcred0_1, w_misc_packet[y][x].wrespcred0_0};
                assign O_CRDTGRANT_RDATACRED3[y][x] = w_misc_packet[y][x].rdatacred3;
                assign O_CRDTGRANT_RDATACRED2[y][x] = w_misc_packet[y][x].rdatacred2;
                assign O_CRDTGRANT_RDATACRED1[y][x] = {w_misc_packet[y][x].rdatacred1_1, w_misc_packet[y][x].rdatacred1_0};
                assign O_CRDTGRANT_RDATACRED0[y][x] = w_misc_packet[y][x].rdatacred0;
                assign O_CRDTGRANT_WDATACRED3[y][x] = w_misc_packet[y][x].wdatacred3;
                assign O_CRDTGRANT_WDATACRED2[y][x] = w_misc_packet[y][x].wdatacred2;
                assign O_CRDTGRANT_WDATACRED1[y][x] = w_misc_packet[y][x].wdatacred1;
                assign O_CRDTGRANT_WDATACRED0[y][x] = {w_misc_packet[y][x].wdatacred0_1, w_misc_packet[y][x].wdatacred0_0};
                assign O_CRDTGRANT_RREQCRED3[y][x]  = w_misc_packet[y][x].rreqcred3;
                assign O_CRDTGRANT_RREQCRED2[y][x]  = w_misc_packet[y][x].rreqcred2;
                assign O_CRDTGRANT_RREQCRED1[y][x]  = {w_misc_packet[y][x].rreqcred1_1, w_misc_packet[y][x].rreqcred1_0};
                assign O_CRDTGRANT_RREQCRED0[y][x]  = w_misc_packet[y][x].rreqcred0;
                assign O_CRDTGRANT_WREQCRED3[y][x]  = w_misc_packet[y][x].wreqcred3;
                assign O_CRDTGRANT_WREQCRED2[y][x]  = w_misc_packet[y][x].wreqcred2;
                assign O_CRDTGRANT_WREQCRED1[y][x]  = w_misc_packet[y][x].wreqcred1;
                assign O_CRDTGRANT_WREQCRED0[y][x]  = {w_misc_packet[y][x].wreqcred0_1, w_misc_packet[y][x].wreqcred0_0};
                assign O_CRDTGRANT_VALID[y][x]      = (w_misc_packet[y][x].misc_op == 3'b100) ? (|wait_valid_chunk) ? (w_misc_valid[y][x] && w_rx_chunk_data_valid) : w_misc_valid[y][x] : 1'b0;
            end
        end
    endgenerate

    assign O_MSGCRDT_WRESPCRED     = i_msg_credit.wrespcred;
    assign O_MSGCRDT_RDATACRED     = i_msg_credit.rdatacred;
    assign O_MSGCRDT_WDATACRED     = i_msg_credit.wdatacred;
    assign O_MSGCRDT_RREQCRED      = i_msg_credit.rreqcred;
    assign O_MSGCRDT_WREQCRED      = i_msg_credit.wreqcred;
    assign O_MSGCRDT_RP            = i_msg_credit.rp;
    assign O_MSGCRDT_VALID         = (PHY_TYPE < 2) ? ((r_aou_rx_phase == 2'b10) && w_rx_chunk_data_valid) : (PHY_TYPE == 2) ? ((r_aou_rx_phase[0] == 1'b1) && w_rx_chunk_data_valid) : w_rx_chunk_data_valid;

    assign O_ACTIVATION_OP         = {w_misc_activation_packet.activation_op_1, w_misc_activation_packet.activation_op_0};
    assign O_ACTIVATION_PROP_REQ   = w_misc_activation_packet.property_req;
    assign O_ACTIVATION_VALID      = (w_misc_activation_packet.misc_op == 3'b010) ? (i_misc_valid[0][0] && w_rx_chunk_data_valid) : 1'b0;

endmodule
