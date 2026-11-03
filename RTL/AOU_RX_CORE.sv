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
//  Version    : 2.00
//  Date       : 26-10-29
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
//  Decodes one half flit (24 granules; a whole 256 B flit, 48 granules, on a
//  2048-bit FDI) per cycle, independent of the FDI beat width.
//
//  Stage A (on the half flit AOU_RX_FDI_IF presents): every MsgStart granule
//  gives a message length from its header; a message that runs past the last
//  granule leaves a remainder that covers the first granules of the next half
//  flit. Each granule is tagged with the RP and class of the message that
//  owns it. The granules and tags are registered.
//
//  Stage B (registered): the request (WriteReq/ReadReq), WriteResp and Misc
//  messages are decoded into FIFO lanes. Request lanes are position windows
//  of three granules (at most one request starts in a window), WriteResp lanes
//  are the granule positions, Misc lanes the first and second Misc message of
//  the half flit. Lane 0 of each kind replays a message whose first granules
//  were in the previous half flit. The WriteData/ReadData granules are not
//  decoded here: the per-RP granule stores receive the granule vector with
//  their cover and start tags.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_RX_CORE
import packet_def_pkg::*;
#(
    parameter   FDI_IF_WD                   = 1024,
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024,
    parameter   AXI_ADDR_WD                 = 64,
    parameter   AXI_ID_WD                   = 10,
    parameter   AXI_LEN_WD                  = 8,
    parameter   RP_COUNT                    = 2,
    parameter   AW_AR_FIFO_DATA_WIDTH       = 97 + 16,   // {id, addr, len, size, lock, cache, prot, qos, flex}
    parameter   B_FIFO_DATA_WIDTH           = 12 + 16,   // {id, resp, flex}

    localparam  HF_CNT                      = (FDI_IF_WD == 2048) ? 2 : 1,
    localparam  G_CNT                       = 24 * HF_CNT,
    localparam  G_WD                        = 40,
    localparam  REQ_WIN                     = 8 * HF_CNT,
    localparam  REQ_LANES                   = REQ_WIN + 1,
    localparam  B_LANES                     = G_CNT,
    localparam  MISC_LANES                  = 3
)
(
    input                                                           I_CLK,
    input                                                           I_RESETN,

    input                                                           I_FDI_PL_VALID,
    input   [FDI_IF_WD-1: 0]                                        I_FDI_PL_DATA,
    input                                                           I_FDI_PL_FLIT_CANCEL,

    output  [RP_COUNT-1:0][REQ_LANES-1:0][AW_AR_FIFO_DATA_WIDTH-1:0] O_RD_REQ_FIFO_SDATA,
    output  [RP_COUNT-1:0][REQ_LANES-1:0]                           O_RD_REQ_FIFO_SVALID,

    output  [RP_COUNT-1:0][REQ_LANES-1:0][AW_AR_FIFO_DATA_WIDTH-1:0] O_WR_REQ_FIFO_SDATA,
    output  [RP_COUNT-1:0][REQ_LANES-1:0]                           O_WR_REQ_FIFO_SVALID,

    output  [RP_COUNT-1:0][B_LANES-1:0][B_FIFO_DATA_WIDTH-1:0]      O_WR_RESP_FIFO_SDATA,
    output  [RP_COUNT-1:0][B_LANES-1:0]                             O_WR_RESP_FIFO_SVALID,

    // granule stream to the W and R stores
    output                                                          O_GRANULE_VALID,
    output  [G_CNT-1:0][G_WD-1:0]                                   O_GRANULE,
    output  [RP_COUNT-1:0][G_CNT-1:0]                               O_WR_DATA_COVER,
    output  [RP_COUNT-1:0][G_CNT-1:0]                               O_WR_DATA_START,
    output  [RP_COUNT-1:0][G_CNT-1:0]                               O_RD_DATA_COVER,
    output  [RP_COUNT-1:0][G_CNT-1:0]                               O_RD_DATA_START,

    output  [MISC_LANES-1:0][1:0]                                   O_CRDTGRANT_WRESPCRED3,
    output  [MISC_LANES-1:0][1:0]                                   O_CRDTGRANT_WRESPCRED2,
    output  [MISC_LANES-1:0][1:0]                                   O_CRDTGRANT_WRESPCRED1,
    output  [MISC_LANES-1:0][1:0]                                   O_CRDTGRANT_WRESPCRED0,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RDATACRED3,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RDATACRED2,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RDATACRED1,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RDATACRED0,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WDATACRED3,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WDATACRED2,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WDATACRED1,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WDATACRED0,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RREQCRED3,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RREQCRED2,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RREQCRED1,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_RREQCRED0,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WREQCRED3,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WREQCRED2,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WREQCRED1,
    output  [MISC_LANES-1:0][2:0]                                   O_CRDTGRANT_WREQCRED0,
    output  [MISC_LANES-1:0]                                        O_CRDTGRANT_VALID,

    output  [1:0]                                                   O_MSGCRDT_WRESPCRED,
    output  [2:0]                                                   O_MSGCRDT_RDATACRED,
    output  [2:0]                                                   O_MSGCRDT_WDATACRED,
    output  [2:0]                                                   O_MSGCRDT_RREQCRED,
    output  [2:0]                                                   O_MSGCRDT_WREQCRED,
    output  [1:0]                                                   O_MSGCRDT_RP,
    output                                                          O_MSGCRDT_VALID,

    output  [3:0]                                                   O_ACTIVATION_OP,
    output                                                          O_ACTIVATION_PROP_REQ,
    output                                                          O_ACTIVATION_VALID,
    // ProfileID/Rev/Opt per RP from granules 0-3 of a received ActivateReq
    // (AoU v0.8); valid with O_ACTIVATION_VALID when O_ACTIVATION_OP is ActivateReq
    output  [3:0][PROFILE_WD-1:0]                                   O_ACTIVATION_PROFILE
);
//-----------------------------------------------------------------------------
    localparam  HF_WD       = 1024 * HF_CNT;
    localparam  LEN_WD      = 5;
    localparam  MAX_MSG_G   = 30;
    localparam  MISC_OP_CRDTGRANT  = 3'b100;
    localparam  MISC_OP_ACTIVATION = 3'b010;
    // non-data carry classes
    localparam  ND_AW   = 2'd0;
    localparam  ND_AR   = 2'd1;
    localparam  ND_MISC = 2'd2;

    // Message length in granules from the first granule of a message.
    // Granule byte 0 is bits [7:0]: MSGTYPE g[7:4], MISCOP g[3:1], ACTIVATIONOP
    // {g[0], g[15:13]} (spec bit order within each byte, bytes in stream order).
    function automatic logic f_is_act_req(input logic [G_WD-1:0] g);
        f_is_act_req = (g[7:4] == MSG_MISC) & (g[3:1] == MISC_OP_ACTIVATION)
                     & ({g[0], g[15:13]} == ACTOP_ACTIVATE_REQ);
    endfunction

    function automatic logic [LEN_WD-1:0] f_msg_len(input logic [G_WD-1:0] g);
        case (g[7:4])
            MSG_MISC:     f_msg_len = (g[3:1] == MISC_OP_CRDTGRANT) ? LEN_WD'(CRDTGRANT_G) :
                                      f_is_act_req(g)               ? LEN_WD'(ACT_REQ_G)   : LEN_WD'(ACT_OTHER_G);
            MSG_WR_REQ:   f_msg_len = LEN_WD'(AW_G);
            MSG_RD_REQ:   f_msg_len = LEN_WD'(AR_G);
            MSG_WR_DATA:  f_msg_len = (g[1:0] == 2'd2) ? LEN_WD'(W1024b_G) :
                                      (g[1:0] == 2'd1) ? LEN_WD'(W512b_G)  : LEN_WD'(W256b_G);
            MSG_WRF_DATA: f_msg_len = (g[1:0] == 2'd2) ? LEN_WD'(WF1024b_G) :
                                      (g[1:0] == 2'd1) ? LEN_WD'(WF512b_G)  : LEN_WD'(WF256b_G);
            MSG_RD_DATA:  f_msg_len = (g[1:0] == 2'd2) ? LEN_WD'(R1024b_G) :
                                      (g[1:0] == 2'd1) ? LEN_WD'(R512b_G)  : LEN_WD'(R256b_G);
            default:      f_msg_len = LEN_WD'(1);
        endcase
    endfunction

    // WriteReq / ReadReq granules to the request FIFO payload
    function automatic logic [AW_AR_FIFO_DATA_WIDTH-1:0] f_req_sdata(input logic [2:0][G_WD-1:0] gr);
        st_write_req_packet_tmp t;
        logic [63:0] addr;
        t = gr;
        addr = {<<8{t.awaddr}};     // awaddr[0] (the message's first address byte) is AxADDR[7:0]
        f_req_sdata = { {t.awid_1, t.awid_0}, addr, t.awlen, t.awsize, t.awlock, t.awcache, t.awprot, t.awqos,
                        {t.flex_hi, t.flex_lo} };
    endfunction

    // WriteResp granule to the response FIFO payload
    function automatic logic [B_FIFO_DATA_WIDTH-1:0] f_resp_sdata(input logic [G_WD-1:0] g);
        st_write_resp_packet_tmp t;
        t = g;
        f_resp_sdata = { {t.bid_1, t.bid_0}, t.bresp, {t.flex_hi, t.flex_lo} };
    endfunction

//-----------------------------------------------------------------------------
// Half flit input
//-----------------------------------------------------------------------------
    logic                           w_hf_valid;
    logic   [HF_WD-1:0]             w_hf_data;

    AOU_RX_FDI_IF #(
        .FDI_IF_WD                  ( FDI_IF_WD             )
    ) u_aou_rx_fdi_if
    (
        .I_CLK                      ( I_CLK                 ),
        .I_RESETN                   ( I_RESETN              ),
        .I_FDI_PL_VALID             ( I_FDI_PL_VALID        ),
        .I_FDI_PL_DATA              ( I_FDI_PL_DATA         ),
        .I_FDI_PL_FLIT_CANCEL       ( I_FDI_PL_FLIT_CANCEL  ),
        .O_AOU_RX_HF_VALID          ( w_hf_valid            ),
        .O_AOU_RX_HF_DATA           ( w_hf_data             )
    );

    // Half flit layout (bytes): 0-1 header, 2-61 G0-G11, 62-63 MsgStart[11:0]
    // (bits 4..15), 64-65 MsgStart[23:12] (bits 4..15), 66-125 G12-G23, 126-127 CRC.
    logic   [G_CNT-1:0][G_WD-1:0]   a_g;
    logic   [G_CNT-1:0]             a_start;
    logic   [15:0]                  a_msgcrdt;
    logic                           a_msgcrdt_valid;
    logic                           r_hf_phase;

    generate
        genvar gh, gj;
        for (gh = 0; gh < HF_CNT; gh++) begin : gen_hf
            for (gj = 0; gj < 12; gj++) begin : gen_g
                assign a_g[gh*24 + gj]      = w_hf_data[gh*1024 + (2 + 5*gj)*8 +: G_WD];
                assign a_g[gh*24 + 12 + gj] = w_hf_data[gh*1024 + (66 + 5*gj)*8 +: G_WD];
            end
            assign a_start[gh*24 +: 12]      = w_hf_data[gh*1024 + 62*8 + 4 +: 12] & {12{w_hf_valid}};
            assign a_start[gh*24 + 12 +: 12] = w_hf_data[gh*1024 + 64*8 + 4 +: 12] & {12{w_hf_valid}};
        end

        // MsgCredit is the header of the second half flit of each flit.
        if (HF_CNT == 2) begin : gen_msgcrdt_flit
            assign a_msgcrdt       = w_hf_data[1024 +: 16];
            assign a_msgcrdt_valid = w_hf_valid;
            assign r_hf_phase      = 1'b0;
        end else begin : gen_msgcrdt_hf
            assign a_msgcrdt       = w_hf_data[0 +: 16];
            assign a_msgcrdt_valid = w_hf_valid & r_hf_phase;
            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN)
                    r_hf_phase <= 1'b0;
                else if (w_hf_valid)
                    r_hf_phase <= ~r_hf_phase;
            end
        end
    endgenerate

//-----------------------------------------------------------------------------
// Stage A: message extents and granule ownership
//-----------------------------------------------------------------------------
    logic   [G_CNT-1:0][LEN_WD-1:0]     a_len;
    logic   [G_CNT-1:0]                 a_is_w;
    logic   [G_CNT-1:0]                 a_is_r;
    logic   [G_CNT-1:0][1:0]            a_rp;

    // data message running past this half flit (WriteData1024 may run past two)
    logic   [LEN_WD-1:0]                r_carry_rem;
    logic                               r_carry_is_w;
    logic   [1:0]                       r_carry_rp;
    logic   [LEN_WD-1:0]                w_carry_rem_nxt;
    logic                               w_carry_is_w_nxt;
    logic   [1:0]                       w_carry_rp_nxt;

    logic   [RP_COUNT-1:0][G_CNT-1:0]   a_cover_w;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   a_cover_r;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   a_start_w;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   a_start_r;

    always_comb begin
        for (int i = 0; i < G_CNT; i++) begin
            a_len[i]  = f_msg_len(a_g[i]);
            a_is_w[i] = (a_g[i][7:4] == MSG_WR_DATA) | (a_g[i][7:4] == MSG_WRF_DATA);
            a_is_r[i] = (a_g[i][7:4] == MSG_RD_DATA);
            a_rp[i]   = a_g[i][3:2];
        end

        a_cover_w = '0;
        a_cover_r = '0;
        a_start_w = '0;
        a_start_r = '0;
        for (int z = 0; z < RP_COUNT; z++) begin
            for (int i = 0; i < G_CNT; i++) begin
                // remainder of a message from the previous half flit
                if ((6'(i) < 6'(r_carry_rem)) && (r_carry_rp == 2'(z))) begin
                    a_cover_w[z][i] = r_carry_is_w;
                    a_cover_r[z][i] = ~r_carry_is_w;
                end
                // messages starting in this half flit
                for (int p = 0; p <= i; p++) begin
                    if ((i - p < MAX_MSG_G) && a_start[p] && (a_rp[p] == 2'(z)) &&
                        (LEN_WD'(i - p) < a_len[p])) begin
                        a_cover_w[z][i] = a_cover_w[z][i] | a_is_w[p];
                        a_cover_r[z][i] = a_cover_r[z][i] | a_is_r[p];
                    end
                end
                a_start_w[z][i] = a_start[i] & a_is_w[i] & (a_rp[i] == 2'(z));
                a_start_r[z][i] = a_start[i] & a_is_r[i] & (a_rp[i] == 2'(z));
            end
        end

        // remainder for the next half flit: only the last data message can run past
        w_carry_rem_nxt  = '0;
        w_carry_is_w_nxt = r_carry_is_w;
        w_carry_rp_nxt   = r_carry_rp;
        // (compared at full width: G_CNT = 48 does not fit LEN_WD, and a
        // remainder never exceeds it there)
        if (7'(r_carry_rem) > 7'(G_CNT)) begin
            w_carry_rem_nxt = LEN_WD'(7'(r_carry_rem) - 7'(G_CNT));
        end
        for (int p = 0; p < G_CNT; p++) begin
            if (a_start[p] && (a_is_w[p] | a_is_r[p]) &&
                ((7'(p) + 7'(a_len[p])) > 7'(G_CNT))) begin
                w_carry_rem_nxt  = LEN_WD'(7'(p) + 7'(a_len[p]) - 7'(G_CNT));
                w_carry_is_w_nxt = a_is_w[p];
                w_carry_rp_nxt   = a_rp[p];
            end
        end
    end

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_carry_rem  <= '0;
            r_carry_is_w <= 1'b0;
            r_carry_rp   <= '0;
        end else if (w_hf_valid) begin
            r_carry_rem  <= w_carry_rem_nxt;
            r_carry_is_w <= w_carry_is_w_nxt;
            r_carry_rp   <= w_carry_rp_nxt;
        end
    end

//-----------------------------------------------------------------------------
// Stage B registers
//-----------------------------------------------------------------------------
    logic                               r_valid;
    logic   [G_CNT-1:0][G_WD-1:0]       r_g;
    logic   [G_CNT-1:0]                 r_start;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   r_cover_w;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   r_cover_r;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   r_start_w;
    logic   [RP_COUNT-1:0][G_CNT-1:0]   r_start_r;
    logic                               r_msgcrdt_valid;
    st_msg_credit_packet                r_msgcrdt;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_valid         <= 1'b0;
            r_g             <= '0;
            r_start         <= '0;
            r_cover_w       <= '0;
            r_cover_r       <= '0;
            r_start_w       <= '0;
            r_start_r       <= '0;
            r_msgcrdt_valid <= 1'b0;
            r_msgcrdt       <= '0;
        end else begin
            r_valid         <= w_hf_valid;
            r_msgcrdt_valid <= a_msgcrdt_valid;
            if (w_hf_valid) begin
                r_g         <= a_g;
                r_start     <= a_start;
                r_cover_w   <= a_cover_w;
                r_cover_r   <= a_cover_r;
                r_start_w   <= a_start_w;
                r_start_r   <= a_start_r;
                r_msgcrdt   <= a_msgcrdt;
            end
        end
    end

    assign O_GRANULE_VALID = r_valid;
    assign O_GRANULE       = r_g;
    assign O_WR_DATA_COVER = r_cover_w;
    assign O_WR_DATA_START = r_start_w;
    assign O_RD_DATA_COVER = r_cover_r;
    assign O_RD_DATA_START = r_start_r;

    assign O_MSGCRDT_WRESPCRED = r_msgcrdt.wrespcred;
    assign O_MSGCRDT_RDATACRED = r_msgcrdt.rdatacred;
    assign O_MSGCRDT_WDATACRED = r_msgcrdt.wdatacred;
    assign O_MSGCRDT_RREQCRED  = r_msgcrdt.rreqcred;
    assign O_MSGCRDT_WREQCRED  = r_msgcrdt.wreqcred;
    assign O_MSGCRDT_RP        = r_msgcrdt.rp;
    assign O_MSGCRDT_VALID     = r_msgcrdt_valid;

//-----------------------------------------------------------------------------
// Stage B: non-data message lanes
//-----------------------------------------------------------------------------
    // granules padded past the end so a window may index two granules beyond
    logic   [G_CNT+1:0][G_WD-1:0]       b_g;
    logic   [G_CNT-1:0][3:0]            b_type;
    logic   [G_CNT-1:0][1:0]            b_rp;
    logic   [G_CNT-1:0]                 b_start_aw;
    logic   [G_CNT-1:0]                 b_start_ar;
    logic   [G_CNT-1:0]                 b_start_b;
    logic   [G_CNT-1:0]                 b_start_misc;

    // a WriteReq, ReadReq or CrdtGrant whose last granules are in the next half flit
    logic                               r_nd_valid;
    logic   [1:0]                       r_nd_class;
    logic   [1:0]                       r_nd_saved;     // granules saved (1 or 2)
    logic   [1:0][G_WD-1:0]             r_nd_g;
    logic                               w_nd_valid_nxt;
    logic   [1:0]                       w_nd_class_nxt;
    logic   [1:0]                       w_nd_saved_nxt;

    always_comb begin
        b_g = '0;
        for (int i = 0; i < G_CNT; i++) begin
            b_g[i]          = r_g[i];
            b_type[i]       = r_g[i][7:4];
            b_rp[i]         = r_g[i][3:2];
            b_start_aw[i]   = r_valid & r_start[i] & (b_type[i] == MSG_WR_REQ);
            b_start_ar[i]   = r_valid & r_start[i] & (b_type[i] == MSG_RD_REQ);
            b_start_b[i]    = r_valid & r_start[i] & (b_type[i] == MSG_WR_RESP);
            b_start_misc[i] = r_valid & r_start[i] & (b_type[i] == MSG_MISC);
        end

        // straddle into the next half flit
        w_nd_valid_nxt = 1'b0;
        w_nd_class_nxt = ND_AW;
        w_nd_saved_nxt = '0;
        if (b_start_aw[G_CNT-2] | b_start_ar[G_CNT-2]) begin
            w_nd_valid_nxt = 1'b1;
            w_nd_class_nxt = b_start_aw[G_CNT-2] ? ND_AW : ND_AR;
            w_nd_saved_nxt = 2'd2;
        end else if (b_start_aw[G_CNT-1] | b_start_ar[G_CNT-1]) begin
            w_nd_valid_nxt = 1'b1;
            w_nd_class_nxt = b_start_aw[G_CNT-1] ? ND_AW : ND_AR;
            w_nd_saved_nxt = 2'd1;
        end else if (b_start_misc[G_CNT-1] && (r_g[G_CNT-1][3:1] == MISC_OP_CRDTGRANT)) begin
            w_nd_valid_nxt = 1'b1;
            w_nd_class_nxt = ND_MISC;
            w_nd_saved_nxt = 2'd1;
        end
    end

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_nd_valid <= 1'b0;
            r_nd_class <= ND_AW;
            r_nd_saved <= '0;
            r_nd_g     <= '0;
        end else if (r_valid) begin
            r_nd_valid <= w_nd_valid_nxt;
            r_nd_class <= w_nd_class_nxt;
            r_nd_saved <= w_nd_saved_nxt;
            // r_nd_g[0] is always the first granule of the straddled message
            r_nd_g     <= {r_g[G_CNT-1], (w_nd_saved_nxt == 2'd2) ? r_g[G_CNT-2] : r_g[G_CNT-1]};
        end
    end

    // request lanes: lane 0 replays the straddled request, lane k+1 is window k
    logic   [REQ_LANES-1:0]                 w_aw_lane_valid;
    logic   [REQ_LANES-1:0]                 w_ar_lane_valid;
    logic   [REQ_LANES-1:0][1:0]            w_aw_lane_rp;
    logic   [REQ_LANES-1:0][1:0]            w_ar_lane_rp;
    logic   [REQ_LANES-1:0][2:0][G_WD-1:0]  w_aw_lane_g;
    logic   [REQ_LANES-1:0][2:0][G_WD-1:0]  w_ar_lane_g;
    logic   [2:0][G_WD-1:0]                 w_nd_req_g;

    always_comb begin
        // straddled request: saved granules first, then the first of this half flit
        if (r_nd_saved == 2'd2)
            w_nd_req_g = {r_g[0], r_nd_g[1], r_nd_g[0]};
        else
            w_nd_req_g = {r_g[1], r_g[0], r_nd_g[0]};

        w_aw_lane_valid[0] = r_valid & r_nd_valid & (r_nd_class == ND_AW);
        w_ar_lane_valid[0] = r_valid & r_nd_valid & (r_nd_class == ND_AR);
        w_aw_lane_rp[0]    = r_nd_g[0][3:2];
        w_ar_lane_rp[0]    = r_nd_g[0][3:2];
        w_aw_lane_g[0]     = w_nd_req_g;
        w_ar_lane_g[0]     = w_nd_req_g;

        for (int k = 0; k < REQ_WIN; k++) begin
            w_aw_lane_valid[k+1] = 1'b0;
            w_ar_lane_valid[k+1] = 1'b0;
            w_aw_lane_rp[k+1]    = '0;
            w_ar_lane_rp[k+1]    = '0;
            w_aw_lane_g[k+1]     = '0;
            w_ar_lane_g[k+1]     = '0;
            for (int m = 0; m < 3; m++) begin
                // a request starting in the last two granules is replayed next half flit
                if ((3*k + m + 2) < G_CNT) begin
                    if (b_start_aw[3*k + m]) begin
                        w_aw_lane_valid[k+1] = 1'b1;
                        w_aw_lane_rp[k+1]    = b_rp[3*k + m];
                        w_aw_lane_g[k+1]     = {b_g[3*k + m + 2], b_g[3*k + m + 1], b_g[3*k + m]};
                    end
                    if (b_start_ar[3*k + m]) begin
                        w_ar_lane_valid[k+1] = 1'b1;
                        w_ar_lane_rp[k+1]    = b_rp[3*k + m];
                        w_ar_lane_g[k+1]     = {b_g[3*k + m + 2], b_g[3*k + m + 1], b_g[3*k + m]};
                    end
                end
            end
        end
    end

    // misc lanes: lane 0 replays a straddled CrdtGrant, lanes 1 and 2 the first
    // and second Misc message of the half flit
    logic   [G_CNT-1:0][1:0]                w_misc_pre;
    logic   [MISC_LANES-1:0]                w_misc_lane_valid;
    logic   [MISC_LANES-1:0][1:0][G_WD-1:0] w_misc_lane_g;
    st_misc_grantcredit_packet  [MISC_LANES-1:0]    w_misc_packet;
    st_misc_activation_packet                       w_misc_activation_packet;
    logic   [ACT_REQ_G-1:0][G_WD-1:0]       w_act_req_g;        // granules 0-3 of the lane-1 Activation
    logic   [ACT_REQ_G-1:0][G_WD-1:0]       w_act_req_spec;     // byte-reversed: spec bit order

    always_comb begin
        w_misc_pre[0] = '0;
        for (int i = 1; i < G_CNT; i++)
            w_misc_pre[i] = (w_misc_pre[i-1] == 2'd3) ? 2'd3 : w_misc_pre[i-1] + 2'(b_start_misc[i-1]);

        w_misc_lane_valid[0] = r_valid & r_nd_valid & (r_nd_class == ND_MISC);
        w_misc_lane_g[0]     = {r_g[0], r_nd_g[0]};
        for (int l = 1; l < MISC_LANES; l++) begin
            w_misc_lane_valid[l] = 1'b0;
            w_misc_lane_g[l]     = '0;
            for (int i = 0; i < G_CNT; i++) begin
                if (b_start_misc[i] && (w_misc_pre[i] == 2'(l-1))) begin
                    // a CrdtGrant starting in the last granule is replayed next half flit
                    w_misc_lane_valid[l] = (i < G_CNT-1) || (r_g[i][3:1] != MISC_OP_CRDTGRANT);
                    w_misc_lane_g[l]     = {b_g[i+1], b_g[i]};
                end
            end
        end

        for (int l = 0; l < MISC_LANES; l++)
            w_misc_packet[l] = w_misc_lane_g[l];
        w_misc_activation_packet = w_misc_lane_g[1][0];

        // Granules 0-3 of the Activation message in lane 1 (the ActivateReq's
        // profile fields, AoU v0.8). It starts at G0 of the flit (4.4), so the
        // window never runs past the half flit; granules past it read 0.
        w_act_req_g = '0;
        for (int i = 0; i < G_CNT; i++)
            if (b_start_misc[i] && (w_misc_pre[i] == 2'd0))
                for (int k = 0; k < ACT_REQ_G; k++)
                    if (i + k < G_CNT) w_act_req_g[k] = b_g[i + k];
    end

    // The 26 profile bits of every ActivateReq granule are the low 26 bits in
    // spec order ({ProfileID, ProfileRev, ProfileOpt} after RsvdZero3 or 14).
    always_comb begin
        for (int k = 0; k < ACT_REQ_G; k++)
            w_act_req_spec[k] = {<<8{w_act_req_g[k]}};
    end
    generate
        for (genvar pk = 0; pk < ACT_REQ_G; pk++) begin : gen_act_profile
            assign O_ACTIVATION_PROFILE[pk] = w_act_req_spec[pk][PROFILE_WD-1:0];
        end
    endgenerate

//-----------------------------------------------------------------------------
// FIFO lane outputs
//-----------------------------------------------------------------------------
    genvar z, x;
    generate
        for (z = 0; z < RP_COUNT; z++) begin : gen_rp
            for (x = 0; x < REQ_LANES; x++) begin : gen_req
                assign O_WR_REQ_FIFO_SVALID[z][x] = w_aw_lane_valid[x] & (w_aw_lane_rp[x] == 2'(z));
                assign O_WR_REQ_FIFO_SDATA[z][x]  = (w_aw_lane_valid[x] & (w_aw_lane_rp[x] == 2'(z))) ?
                                                    f_req_sdata(w_aw_lane_g[x]) : '0;
                assign O_RD_REQ_FIFO_SVALID[z][x] = w_ar_lane_valid[x] & (w_ar_lane_rp[x] == 2'(z));
                assign O_RD_REQ_FIFO_SDATA[z][x]  = (w_ar_lane_valid[x] & (w_ar_lane_rp[x] == 2'(z))) ?
                                                    f_req_sdata(w_ar_lane_g[x]) : '0;
            end
            for (x = 0; x < B_LANES; x++) begin : gen_resp
                assign O_WR_RESP_FIFO_SVALID[z][x] = b_start_b[x] & (b_rp[x] == 2'(z));
                assign O_WR_RESP_FIFO_SDATA[z][x]  = (b_start_b[x] & (b_rp[x] == 2'(z))) ?
                                                     f_resp_sdata(r_g[x]) : '0;
            end
        end

        for (x = 0; x < MISC_LANES; x++) begin : gen_misc
            assign O_CRDTGRANT_WRESPCRED3[x] = w_misc_packet[x].wrespcred3;
            assign O_CRDTGRANT_WRESPCRED2[x] = w_misc_packet[x].wrespcred2;
            assign O_CRDTGRANT_WRESPCRED1[x] = w_misc_packet[x].wrespcred1;
            assign O_CRDTGRANT_WRESPCRED0[x] = {w_misc_packet[x].wrespcred0_1, w_misc_packet[x].wrespcred0_0};
            assign O_CRDTGRANT_RDATACRED3[x] = w_misc_packet[x].rdatacred3;
            assign O_CRDTGRANT_RDATACRED2[x] = w_misc_packet[x].rdatacred2;
            assign O_CRDTGRANT_RDATACRED1[x] = {w_misc_packet[x].rdatacred1_1, w_misc_packet[x].rdatacred1_0};
            assign O_CRDTGRANT_RDATACRED0[x] = w_misc_packet[x].rdatacred0;
            assign O_CRDTGRANT_WDATACRED3[x] = w_misc_packet[x].wdatacred3;
            assign O_CRDTGRANT_WDATACRED2[x] = w_misc_packet[x].wdatacred2;
            assign O_CRDTGRANT_WDATACRED1[x] = w_misc_packet[x].wdatacred1;
            assign O_CRDTGRANT_WDATACRED0[x] = {w_misc_packet[x].wdatacred0_1, w_misc_packet[x].wdatacred0_0};
            assign O_CRDTGRANT_RREQCRED3[x]  = w_misc_packet[x].rreqcred3;
            assign O_CRDTGRANT_RREQCRED2[x]  = w_misc_packet[x].rreqcred2;
            assign O_CRDTGRANT_RREQCRED1[x]  = {w_misc_packet[x].rreqcred1_1, w_misc_packet[x].rreqcred1_0};
            assign O_CRDTGRANT_RREQCRED0[x]  = w_misc_packet[x].rreqcred0;
            assign O_CRDTGRANT_WREQCRED3[x]  = w_misc_packet[x].wreqcred3;
            assign O_CRDTGRANT_WREQCRED2[x]  = w_misc_packet[x].wreqcred2;
            assign O_CRDTGRANT_WREQCRED1[x]  = w_misc_packet[x].wreqcred1;
            assign O_CRDTGRANT_WREQCRED0[x]  = {w_misc_packet[x].wreqcred0_1, w_misc_packet[x].wreqcred0_0};
            assign O_CRDTGRANT_VALID[x]      = w_misc_lane_valid[x] & (w_misc_packet[x].misc_op == MISC_OP_CRDTGRANT);
        end
    endgenerate

    assign O_ACTIVATION_OP       = {w_misc_activation_packet.activation_op_1, w_misc_activation_packet.activation_op_0};
    assign O_ACTIVATION_PROP_REQ = w_misc_activation_packet.property_req;
    assign O_ACTIVATION_VALID    = w_misc_lane_valid[1] & (w_misc_activation_packet.misc_op == MISC_OP_ACTIVATION);

endmodule
