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
//  Module     : AOU_RX_GRANULE_STORE
//  Version    : 1.00
//  Date       : 26-10-29
//
//  RX data-message store for one RP and one message class (WriteData /
//  WriteDataFull, or ReadData). It stores the raw 40-bit granules of the
//  messages it owns, in arrival order, packed WG granules to an SRAM word,
//  and decodes a message into AXI fields only when it is popped. Reserved
//  message bits are kept verbatim, so a profile that assigns them a meaning
//  only changes the pop-side extraction.
//
//  Input (one cycle per received half flit, after AOU_RX_CORE's tag stage):
//    I_SGRANULE[i]  the G_CNT granules of the half flit
//    I_SCOVER[i]    granule i belongs to a message of this RP and class
//    I_SSTART[i]    a message of this RP and class starts at granule i
//  The covered granules are compacted and appended to the granule ring. A
//  message that straddles half flits simply continues at the next cycle's
//  first covered granule. Every word touched in a cycle is written, including
//  the partial last word, which is rewritten (with the residue kept in flops)
//  when later granules append to it.
//
//  Messages are tracked in a small control FIFO pushed at the start granule
//  with {word, offset, running granule count, DLENGTH, WriteDataFull}. The
//  head message is complete when the running count has advanced past its
//  last granule; it is then read back (up to RD_WORDS consecutive words, one
//  per bank, one cycle SRAM latency), aligned to its start offset, decoded by
//  DLENGTH, and queued in a two-entry output buffer.
//
//  Capacity: one credit per granule, DEPTH_G granules advertised. The ring
//  holds at least DEPTH_G + WG - 1 granules so the partial-word rewrite can
//  never reach the word that holds the oldest unread message.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_RX_GRANULE_STORE
import packet_def_pkg::*;
#(
    parameter   G_CNT       = 24,       // granules presented per cycle (24 per half flit)
    parameter   DEPTH_G     = 600,      // advertised capacity in granules (credits)
    parameter   IS_READ     = 0,        // 0: WriteData/WriteDataFull, 1: ReadData
    parameter   AXI_ID_WD   = 10,
    parameter   WG          = 8,        // granules per SRAM word (power of two)

    localparam  DATA_WD     = 1024,
    localparam  STRB_WD     = DATA_WD / 8,
    localparam  EXT_WD      = AXI_ID_WD + 2 + 1,            // {rid, rresp, rlast}
    localparam  G_WD        = 40,
    localparam  WORD_WD     = WG * G_WD,
    localparam  MAX_MSG_G   = 30,                           // WriteData1024
    localparam  OFF_WD      = $clog2(WG),
    localparam  WR_WORDS    = (WG - 1 + G_CNT + WG - 1) / WG,       // words touched per write cycle
    localparam  RD_WORDS    = (WG - 1 + MAX_MSG_G + WG - 1) / WG,   // words covering one message
    localparam  NBANK       = (WR_WORDS > RD_WORDS) ? WR_WORDS : RD_WORDS,
    localparam  BANK_WD     = $clog2(NBANK),
    localparam  WORDS_MIN   = (DEPTH_G + WG - 1 + WG - 1) / WG,
    localparam  ROWS        = (WORDS_MIN + NBANK - 1) / NBANK,
    localparam  ROW_WD      = (ROWS > 1) ? $clog2(ROWS) : 1,
    localparam  CNT_WD      = $clog2(DEPTH_G + MAX_MSG_G + 1) + 1,  // running granule count
    localparam  IN_CNT_WD   = $clog2(G_CNT + 1),
    localparam  STREAM_G    = WG - 1 + G_CNT,               // residue + new granules
    localparam  STREAM_WD   = $clog2(STREAM_G + 1),
    localparam  MIN_MSG_G   = IS_READ ? R256b_G : WF256b_G,
    localparam  MAX_STARTS  = (G_CNT + MIN_MSG_G - 1) / MIN_MSG_G,
    localparam  CTRL_DEPTH  = DEPTH_G / MIN_MSG_G + 2,
    localparam  CTRL_WD     = ROW_WD + BANK_WD + OFF_WD + CNT_WD + 2 + 1,
    localparam  RD_STREAM_G = RD_WORDS * WG,
    localparam  OUT_WD      = DATA_WD + (IS_READ ? EXT_WD : (STRB_WD + 1)) + 2 + 16
)
(
    input                                   I_CLK,
    input                                   I_RESETN,

    input                                   I_SVALID,
    input       [G_CNT-1:0][G_WD-1:0]       I_SGRANULE,
    input       [G_CNT-1:0]                 I_SCOVER,
    input       [G_CNT-1:0]                 I_SSTART,

    input                                   I_MREADY,
    output                                  O_MVALID,
    output      [DATA_WD-1:0]               O_MDATA,
    output      [1:0]                       O_MDLEN,
    output      [15:0]                      O_MFLEX,
    // WriteData only
    output      [STRB_WD-1:0]               O_MSTRB,
    output                                  O_MWDATAF,
    // ReadData only
    output      [EXT_WD-1:0]                O_MEXT
);
//-----------------------------------------------------------------------------
// Message length in granules from the header granule of a message.
//-----------------------------------------------------------------------------
    function automatic logic [4:0] f_msg_len(input logic [1:0] dlen, input logic wdataf);
        if (IS_READ)
            f_msg_len = (dlen == 2'd2) ? 5'(R1024b_G) : (dlen == 2'd1) ? 5'(R512b_G) : 5'(R256b_G);
        else if (wdataf)
            f_msg_len = (dlen == 2'd2) ? 5'(WF1024b_G) : (dlen == 2'd1) ? 5'(WF512b_G) : 5'(WF256b_G);
        else
            f_msg_len = (dlen == 2'd2) ? 5'(W1024b_G) : (dlen == 2'd1) ? 5'(W512b_G) : 5'(W256b_G);
    endfunction

//-----------------------------------------------------------------------------
// Write side: compaction and word assembly
//-----------------------------------------------------------------------------
    logic   [G_CNT-1:0]                 w_cover;
    logic   [G_CNT-1:0]                 w_start;
    logic   [G_CNT-1:0][IN_CNT_WD-1:0]  w_pre;          // covered granules before i
    logic   [IN_CNT_WD-1:0]             w_in_cnt;       // covered granules this cycle
    logic   [G_CNT-1:0][G_WD-1:0]       w_cmp;          // compacted granules

    logic   [OFF_WD-1:0]                r_resid_cnt;    // granules held in the partial word
    logic   [WG-2:0][G_WD-1:0]          r_resid;
    logic   [ROW_WD-1:0]                r_wr_row;
    logic   [BANK_WD-1:0]               r_wr_bank;
    logic   [CNT_WD-1:0]                r_wr_cnt;       // running granule count (free running)

    // residue followed by the new granules, zero padded to whole words
    logic   [WR_WORDS*WG-1:0][G_WD-1:0] w_resid_pad;
    logic   [WR_WORDS*WG-1:0][G_WD-1:0] w_stream;
    logic   [STREAM_WD-1:0]             w_stream_cnt;
    logic   [STREAM_WD-1:0]             w_words_touched;
    logic   [STREAM_WD-OFF_WD-1:0]      w_words_full;
    logic   [OFF_WD-1:0]                w_resid_cnt_nxt;
    logic                               w_wr_any;

    assign w_cover = I_SCOVER & {G_CNT{I_SVALID}};
    assign w_start = I_SSTART & w_cover;

    always_comb begin
        w_pre[0] = '0;
        for (int i = 1; i < G_CNT; i++)
            w_pre[i] = w_pre[i-1] + IN_CNT_WD'(w_cover[i-1]);
        w_in_cnt = w_pre[G_CNT-1] + IN_CNT_WD'(w_cover[G_CNT-1]);

        // compaction: covered granule i lands in slot w_pre[i]
        w_cmp = '0;
        for (int j = 0; j < G_CNT; j++)
            for (int i = j; i < G_CNT; i++)
                if (w_cover[i] && (w_pre[i] == IN_CNT_WD'(j)))
                    w_cmp[j] = w_cmp[j] | I_SGRANULE[i];

        // stream slot q: residue for q < r_resid_cnt, else compacted slot q - r_resid_cnt
        w_resid_pad = '0;
        w_resid_pad[WG-2:0] = r_resid;
        w_stream = '0;
        for (int q = 0; q < WR_WORDS*WG; q++) begin
            if (STREAM_WD'(q) < STREAM_WD'(r_resid_cnt))
                w_stream[q] = w_resid_pad[q];
            for (int j = 0; j < G_CNT; j++)
                if ((j < w_in_cnt) && (STREAM_WD'(j) + STREAM_WD'(r_resid_cnt) == STREAM_WD'(q)))
                    w_stream[q] = w_stream[q] | w_cmp[j];
        end
    end

    assign w_stream_cnt    = STREAM_WD'(r_resid_cnt) + STREAM_WD'(w_in_cnt);
    assign w_words_touched = STREAM_WD'(({1'b0, w_stream_cnt} + (STREAM_WD+1)'(WG - 1)) >> OFF_WD);
    assign w_words_full    = w_stream_cnt[STREAM_WD-1:OFF_WD];
    assign w_resid_cnt_nxt = w_stream_cnt[OFF_WD-1:0];
    assign w_wr_any        = I_SVALID && (w_in_cnt != '0);

    // (row, bank) of word k after the current write pointer
    logic   [WR_WORDS-1:0][BANK_WD:0]       w_wr_sum_k;
    logic   [WR_WORDS-1:0][BANK_WD-1:0]     w_wr_bank_k;
    logic   [WR_WORDS-1:0][ROW_WD-1:0]      w_wr_row_k;
    logic   [WR_WORDS-1:0]                  w_wr_en_k;

    always_comb begin
        for (int k = 0; k < WR_WORDS; k++) begin
            w_wr_sum_k[k] = {1'b0, r_wr_bank} + (BANK_WD+1)'(k);
            if (w_wr_sum_k[k] >= (BANK_WD+1)'(NBANK)) begin
                w_wr_bank_k[k] = BANK_WD'(w_wr_sum_k[k] - (BANK_WD+1)'(NBANK));
                w_wr_row_k[k]  = (r_wr_row == ROW_WD'(ROWS-1)) ? '0 : r_wr_row + 1'b1;
            end else begin
                w_wr_bank_k[k] = BANK_WD'(w_wr_sum_k[k]);
                w_wr_row_k[k]  = r_wr_row;
            end
            w_wr_en_k[k] = w_wr_any && (STREAM_WD'(k) < w_words_touched);
        end
    end

    // SRAM write ports
    logic   [NBANK-1:0]                 w_sram_wen;
    logic   [NBANK-1:0][ROW_WD-1:0]     w_sram_waddr;
    logic   [NBANK-1:0][WORD_WD-1:0]    w_sram_wdata;
    logic   [WR_WORDS-1:0][WORD_WD-1:0] w_stream_w;     // the stream as whole words

    assign w_stream_w = w_stream;

    always_comb begin
        w_sram_wen   = '0;
        w_sram_waddr = '0;
        w_sram_wdata = '0;
        for (int b = 0; b < NBANK; b++)
            for (int k = 0; k < WR_WORDS; k++)
                if (w_wr_en_k[k] && (w_wr_bank_k[k] == BANK_WD'(b))) begin
                    w_sram_wen[b]   = 1'b1;
                    w_sram_waddr[b] = w_wr_row_k[k];
                    w_sram_wdata[b] = w_stream_w[k];
                end
    end

    // pointer, residue and running count
    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_resid_cnt <= '0;
            r_resid     <= '0;
            r_wr_row    <= '0;
            r_wr_bank   <= '0;
            r_wr_cnt    <= '0;
        end else if (w_wr_any) begin
            r_resid_cnt <= w_resid_cnt_nxt;
            r_wr_cnt    <= r_wr_cnt + CNT_WD'(w_in_cnt);
            for (int f = 0; f < WR_WORDS; f++) begin
                if (w_words_full == (STREAM_WD-OFF_WD)'(f)) begin
                    for (int s = 0; s < WG-1; s++)
                        r_resid[s] <= w_stream[f*WG + s];
                    r_wr_bank <= w_wr_bank_k[f];
                    r_wr_row  <= w_wr_row_k[f];
                end
            end
        end
    end

//-----------------------------------------------------------------------------
// Message control FIFO, pushed at each start granule
//-----------------------------------------------------------------------------
    logic   [G_CNT-1:0][$clog2(MAX_STARTS+1)-1:0]   w_start_pre;
    logic   [G_CNT-1:0][STREAM_WD-1:0]              w_start_pos;
    logic   [G_CNT-1:0][ROW_WD-1:0]                 w_start_row;
    logic   [G_CNT-1:0][BANK_WD-1:0]                w_start_bank;
    logic   [MAX_STARTS-1:0]                        w_ctrl_svalid;
    logic   [MAX_STARTS-1:0][CTRL_WD-1:0]           w_ctrl_sdata;

    always_comb begin
        w_start_pre[0] = '0;
        for (int i = 1; i < G_CNT; i++)
            w_start_pre[i] = w_start_pre[i-1] + ($clog2(MAX_STARTS+1))'(w_start[i-1]);

        // stream position of each start and the word it lands in
        for (int i = 0; i < G_CNT; i++) begin
            w_start_pos[i]  = STREAM_WD'(r_resid_cnt) + STREAM_WD'(w_pre[i]);
            w_start_row[i]  = '0;
            w_start_bank[i] = '0;
            for (int k = 0; k < WR_WORDS; k++)
                if (w_start_pos[i][STREAM_WD-1:OFF_WD] == (STREAM_WD-OFF_WD)'(k)) begin
                    w_start_row[i]  = w_wr_row_k[k];
                    w_start_bank[i] = w_wr_bank_k[k];
                end
        end

        w_ctrl_svalid = '0;
        w_ctrl_sdata  = '0;
        for (int l = 0; l < MAX_STARTS; l++)
            for (int i = 0; i < G_CNT; i++)
                if (w_start[i] && (w_start_pre[i] == ($clog2(MAX_STARTS+1))'(l))) begin
                    w_ctrl_svalid[l]   = 1'b1;
                    w_ctrl_sdata[l]    = w_ctrl_sdata[l] | {
                        w_start_row[i],
                        w_start_bank[i],
                        w_start_pos[i][OFF_WD-1:0],
                        r_wr_cnt + CNT_WD'(w_pre[i]),
                        I_SGRANULE[i][1:0],                          // DLENGTH
                        (I_SGRANULE[i][7:4] == MSG_WRF_DATA) };      // WriteDataFull
                end
    end

    logic                   w_ctrl_mvalid;
    logic   [CTRL_WD-1:0]   w_ctrl_mdata;
    logic                   w_ctrl_mready;

    AOU_SYNC_FIFO_NS1M #(
        .FIFO_WIDTH     ( CTRL_WD       ),
        .FIFO_DEPTH     ( CTRL_DEPTH    ),
        .ICH_CNT        ( MAX_STARTS    ),
        .ALWAYS_READY   ( 1             )
    ) u_ctrl_fifo
    (
        .I_CLK          ( I_CLK         ),
        .I_RESETN       ( I_RESETN      ),
        .I_SVALID       ( w_ctrl_svalid ),
        .I_SDATA        ( w_ctrl_sdata  ),
        .O_SREADY       (               ),
        .I_MREADY       ( w_ctrl_mready ),
        .O_MDATA        ( w_ctrl_mdata  ),
        .O_MVALID       ( w_ctrl_mvalid ),
        .O_S_EMPTY_CNT  (               ),
        .O_M_DATA_CNT   (               )
    );

    logic   [ROW_WD-1:0]    w_head_row;
    logic   [BANK_WD-1:0]   w_head_bank;
    logic   [OFF_WD-1:0]    w_head_off;
    logic   [CNT_WD-1:0]    w_head_cnt;
    logic   [1:0]           w_head_dlen;
    logic                   w_head_wdataf;
    logic   [4:0]           w_head_len;
    logic   [CNT_WD-1:0]    w_head_avail;
    logic                   w_head_complete;

    assign {w_head_row, w_head_bank, w_head_off, w_head_cnt, w_head_dlen, w_head_wdataf} = w_ctrl_mdata;
    assign w_head_len      = f_msg_len(w_head_dlen, w_head_wdataf);
    assign w_head_avail    = r_wr_cnt - w_head_cnt;
    assign w_head_complete = w_ctrl_mvalid && (w_head_avail >= CNT_WD'(w_head_len));

//-----------------------------------------------------------------------------
// Read side
//-----------------------------------------------------------------------------
    logic                   r_rd_pend;
    logic   [BANK_WD-1:0]   r_rd_bank;
    logic   [OFF_WD-1:0]    r_rd_off;
    logic   [1:0]           r_rd_dlen;
    logic                   r_rd_wdataf;

    logic   [1:0]           w_out_empty_cnt;
    logic                   w_out_svalid;
    logic   [OUT_WD-1:0]    w_out_sdata;
    logic                   w_out_pop;
    logic                   w_issue;

    assign w_out_pop     = O_MVALID & I_MREADY;
    // Room in the output buffer for the read in flight plus this one, counting
    // this cycle's pop.
    assign w_issue       = w_head_complete &&
                           (({1'b0, w_out_empty_cnt} + 3'(w_out_pop)) >= (3'(r_rd_pend) + 3'd1));
    assign w_ctrl_mready = w_issue;

    logic   [RD_WORDS-1:0][BANK_WD:0]       w_hd_sum_s;
    logic   [RD_WORDS-1:0][BANK_WD-1:0]     w_rd_bank_s;
    logic   [RD_WORDS-1:0][ROW_WD-1:0]      w_rd_row_s;

    always_comb begin
        for (int s = 0; s < RD_WORDS; s++) begin
            w_hd_sum_s[s] = {1'b0, w_head_bank} + (BANK_WD+1)'(s);
            if (w_hd_sum_s[s] >= (BANK_WD+1)'(NBANK)) begin
                w_rd_bank_s[s] = BANK_WD'(w_hd_sum_s[s] - (BANK_WD+1)'(NBANK));
                w_rd_row_s[s]  = (w_head_row == ROW_WD'(ROWS-1)) ? '0 : w_head_row + 1'b1;
            end else begin
                w_rd_bank_s[s] = BANK_WD'(w_hd_sum_s[s]);
                w_rd_row_s[s]  = w_head_row;
            end
        end
    end

    logic   [NBANK-1:0]                 w_sram_ren;
    logic   [NBANK-1:0][ROW_WD-1:0]     w_sram_raddr;
    logic   [NBANK-1:0][WORD_WD-1:0]    w_sram_rdata;

    always_comb begin
        w_sram_ren   = '0;
        w_sram_raddr = '0;
        for (int b = 0; b < NBANK; b++)
            for (int s = 0; s < RD_WORDS; s++)
                if (w_issue && (w_rd_bank_s[s] == BANK_WD'(b))) begin
                    w_sram_ren[b]   = 1'b1;
                    w_sram_raddr[b] = w_rd_row_s[s];
                end
    end

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_rd_pend   <= 1'b0;
            r_rd_bank   <= '0;
            r_rd_off    <= '0;
            r_rd_dlen   <= '0;
            r_rd_wdataf <= 1'b0;
        end else begin
            r_rd_pend <= w_issue;
            if (w_issue) begin
                r_rd_bank   <= w_head_bank;
                r_rd_off    <= w_head_off;
                r_rd_dlen   <= w_head_dlen;
                r_rd_wdataf <= w_head_wdataf;
            end
        end
    end

    // Reassemble the consecutive words, then align the message to granule 0.
    logic   [RD_WORDS-1:0][WORD_WD-1:0]     w_rd_stream_w;  // the words read, in order
    logic   [RD_STREAM_G-1:0][G_WD-1:0]     w_rd_stream;    // the same as granules
    logic   [MAX_MSG_G-1:0][G_WD-1:0]       w_msg_g;
    logic   [MAX_MSG_G*5-1:0][7:0]          w_msg_b;        // message bytes

    logic   [RD_WORDS-1:0][BANK_WD:0]       w_rd_sum_s;
    logic   [RD_WORDS-1:0][BANK_WD-1:0]     w_rd_pend_bank_s;

    always_comb begin
        w_rd_stream_w = '0;
        for (int s = 0; s < RD_WORDS; s++) begin
            w_rd_sum_s[s]       = {1'b0, r_rd_bank} + (BANK_WD+1)'(s);
            w_rd_pend_bank_s[s] = (w_rd_sum_s[s] >= (BANK_WD+1)'(NBANK)) ?
                                  BANK_WD'(w_rd_sum_s[s] - (BANK_WD+1)'(NBANK)) : BANK_WD'(w_rd_sum_s[s]);
            for (int b = 0; b < NBANK; b++)
                if (w_rd_pend_bank_s[s] == BANK_WD'(b))
                    w_rd_stream_w[s] = w_sram_rdata[b];
        end
        w_rd_stream = w_rd_stream_w;
        for (int m = 0; m < MAX_MSG_G; m++) begin
            w_msg_g[m] = '0;
            for (int o = 0; o < WG; o++)
                if (r_rd_off == OFF_WD'(o))
                    w_msg_g[m] = w_rd_stream[m + o];
        end
        w_msg_b = w_msg_g;
    end

    // Field extraction. Data fields are MSB first in the message, so the AXI
    // vector is the byte reversal of a fixed slice of the message bytes
    // (constant indices: synthesis need not bound a variable part select).
    logic   [255:0]         w_data_256;
    logic   [511:0]         w_data_512;
    logic   [DATA_WD-1:0]   w_data_1024, w_data;
    logic   [31:0]          w_strb_256;
    logic   [63:0]          w_strb_512;
    logic   [STRB_WD-1:0]   w_strb_1024, w_strb;
    logic   [15:0]          w_flex;
    logic   [9:0]           w_rid;
    logic   [EXT_WD-1:0]    w_ext;
    localparam  DATA_B0 = IS_READ ? 5 : 3;      // first data byte of the message

    assign w_data_256  = {<<8{w_msg_b[DATA_B0 +: 32]}};
    assign w_data_512  = {<<8{w_msg_b[DATA_B0 +: 64]}};
    assign w_data_1024 = {<<8{w_msg_b[DATA_B0 +: 128]}};
    assign w_strb_256  = {<<8{w_msg_b[3 + 32 +: 4]}};       // WriteData: strobes follow the data
    assign w_strb_512  = {<<8{w_msg_b[3 + 64 +: 8]}};
    assign w_strb_1024 = {<<8{w_msg_b[3 + 128 +: 16]}};

    always_comb begin
        // ReadData narrower than the bus is replicated across it so the beat
        // is valid whichever lanes the address selects (as the previous FIFO).
        case (r_rd_dlen)
            2'd2:    begin
                w_data = w_data_1024;
                w_strb = w_strb_1024;
            end
            2'd1:    begin
                w_data = IS_READ ? {2{w_data_512}} : {{(DATA_WD-512){1'b0}}, w_data_512};
                w_strb = {{(STRB_WD-64){1'b0}}, w_strb_512};
            end
            default: begin
                w_data = IS_READ ? {4{w_data_256}} : {{(DATA_WD-256){1'b0}}, w_data_256};
                w_strb = {{(STRB_WD-32){1'b0}}, w_strb_256};
            end
        endcase
        if (r_rd_wdataf) begin
            w_strb = (r_rd_dlen == 2'd2) ? {STRB_WD{1'b1}} :
                     (r_rd_dlen == 2'd1) ? {{(STRB_WD-64){1'b0}}, {64{1'b1}}} :
                                           {{(STRB_WD-32){1'b0}}, {32{1'b1}}};
        end
        w_flex = {w_msg_b[1], w_msg_b[2]};
        // ReadData: RID = {byte 3, byte 4[7:6]}, RRESP = byte 4[5:4], RLAST = byte 4[3]
        w_rid  = {w_msg_b[3], w_msg_b[4][7:6]};
        w_ext  = {w_rid[AXI_ID_WD-1:0], w_msg_b[4][5:4], w_msg_b[4][3]};
    end

    generate
        if (IS_READ) begin : gen_out_r
            assign w_out_sdata = {w_data, w_ext, r_rd_dlen, w_flex};
        end else begin : gen_out_w
            assign w_out_sdata = {w_data, w_strb, r_rd_wdataf, r_rd_dlen, w_flex};
        end
    endgenerate
    assign w_out_svalid = r_rd_pend;

//-----------------------------------------------------------------------------
// Output buffer (two entries)
//-----------------------------------------------------------------------------
    logic   [OUT_WD-1:0]    w_out_mdata;

    AOU_SYNC_FIFO_REG #(
        .FIFO_WIDTH     ( OUT_WD            ),
        .FIFO_DEPTH     ( 2                 )
    ) u_out_fifo
    (
        .I_CLK          ( I_CLK             ),
        .I_RESETN       ( I_RESETN          ),
        .I_SVALID       ( w_out_svalid      ),
        .I_SDATA        ( w_out_sdata       ),
        .O_SREADY       (                   ),
        .I_MREADY       ( I_MREADY          ),
        .O_MDATA        ( w_out_mdata       ),
        .O_MVALID       ( O_MVALID          ),
        .O_EMPTY_CNT    ( w_out_empty_cnt   ),
        .O_FULL_CNT     (                   )
    );

    generate
        if (IS_READ) begin : gen_unpack_r
            assign {O_MDATA, O_MEXT, O_MDLEN, O_MFLEX} = w_out_mdata;
            assign O_MSTRB   = '0;
            assign O_MWDATAF = 1'b0;
        end else begin : gen_unpack_w
            assign {O_MDATA, O_MSTRB, O_MWDATAF, O_MDLEN, O_MFLEX} = w_out_mdata;
            assign O_MEXT    = '0;
        end
    endgenerate

//-----------------------------------------------------------------------------
// SRAM banks
//-----------------------------------------------------------------------------
    generate
        genvar gb;
        for (gb = 0; gb < NBANK; gb++) begin : gen_bank
            AOU_TPSRAM #(
                .RAM_DATA_WIDTH ( WORD_WD   ),
                .RAM_ADDR_WIDTH ( ROW_WD    )
            ) u_tpsram
            (
                .CLKA   ( I_CLK             ),
                .CENA   ( ~w_sram_ren[gb]   ),
                .AA     ( w_sram_raddr[gb]  ),
                .QA     ( w_sram_rdata[gb]  ),

                .CLKB   ( I_CLK             ),
                .CENB   ( ~w_sram_wen[gb]   ),
                .AB     ( w_sram_waddr[gb]  ),
                .DB     ( w_sram_wdata[gb]  )
            );
        end
    endgenerate

//-----------------------------------------------------------------------------
`ifdef ASSERTION_ON
// synopsys translate_off
    logic [CNT_WD-1:0] r_occ;
    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN)
            r_occ <= '0;
        else
            r_occ <= r_occ + (I_SVALID ? CNT_WD'(w_in_cnt) : '0) - (w_issue ? CNT_WD'(w_head_len) : '0);
    end

    occupancy_within_credit:
        assert property (@(posedge I_CLK) disable iff (!I_RESETN) (r_occ <= CNT_WD'(DEPTH_G)))
        else begin
            $error("\n[%t] Error! RX granule store holds %0d granules, more than its %0d credits", $time, r_occ, DEPTH_G);
            $finish;
        end

    start_is_covered:
        assert property (@(posedge I_CLK) disable iff (!I_RESETN) I_SVALID |-> ((I_SSTART & ~I_SCOVER) == '0))
        else begin
            $error("\n[%t] Error! RX granule store start without cover", $time);
            $finish;
        end
// synopsys translate_on
`endif

endmodule
