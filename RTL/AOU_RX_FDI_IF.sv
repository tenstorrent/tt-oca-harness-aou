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
//  Module     : AOU_RX_FDI_IF
//  Version    : 2.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
//  Collects FDI beats into whole 128 B half flits (or a whole 256 B flit on
//  a 2048-bit FDI) and presents each one atomically to AOU_RX_CORE. Beat b of
//  a half flit lands at bits [b*FDI_IF_WD +: FDI_IF_WD] of the output.
//
//  pl_flit_cancel arrives the cycle after the last beat of the canceled half
//  flit, either alone or coincident with the first beat of the replay. The
//  completed half flit is held in r_data for exactly that cycle, so gating
//  the output valid with the cancel drops it; a beat coincident with the
//  cancel is accumulated as beat 0 of the replay.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_RX_FDI_IF #(
  parameter   FDI_IF_WD = 1024,
  localparam  HF_CNT    = (FDI_IF_WD == 2048) ? 2 : 1,  // half flits per output
  localparam  OUT_WD    = 1024 * HF_CNT
)
(
    input I_CLK,
    input I_RESETN,

    //------------------------------------------------------------
    //AOU_RX_CORE Interface
    //------------------------------------------------------------
    output                          O_AOU_RX_HF_VALID,
    output      [OUT_WD-1:0]        O_AOU_RX_HF_DATA,

    //------------------------------------------------------------
    //FDI Interface
    //------------------------------------------------------------
    input                           I_FDI_PL_VALID,
    input logic [FDI_IF_WD-1:0]     I_FDI_PL_DATA,
    input                           I_FDI_PL_FLIT_CANCEL

);
    localparam BEATS    = OUT_WD / FDI_IF_WD;                   // 1, 2 or 4
    localparam BEAT_WD  = (BEATS == 1) ? 1 : $clog2(BEATS);

    logic   [OUT_WD-1:0]    r_data;
    logic                   r_valid;

    generate
        if (BEATS == 1) begin : gen_single_beat
            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_data  <= 'd0;
                    r_valid <= 1'b0;
                end else begin
                    r_valid <= I_FDI_PL_VALID;
                    if (I_FDI_PL_VALID)
                        r_data <= I_FDI_PL_DATA;
                end
            end
        end else begin : gen_multi_beat
            logic   [BEAT_WD-1:0]                   r_beat;
            logic   [BEATS-2:0][FDI_IF_WD-1:0]      r_acc;      // beats 0 .. BEATS-2
            // A beat coincident with a cancel is beat 0 of the replayed half flit.
            logic   [BEAT_WD-1:0]                   w_beat;
            logic                                   w_last_beat;

            assign w_beat      = I_FDI_PL_FLIT_CANCEL ? {BEAT_WD{1'b0}} : r_beat;
            assign w_last_beat = (w_beat == BEAT_WD'(BEATS-1));

            always_ff @(posedge I_CLK or negedge I_RESETN) begin
                if (!I_RESETN) begin
                    r_beat  <= 'd0;
                    r_acc   <= 'd0;
                    r_data  <= 'd0;
                    r_valid <= 1'b0;
                end else begin
                    r_valid <= I_FDI_PL_VALID & w_last_beat;
                    if (I_FDI_PL_VALID) begin
                        if (w_last_beat) begin
                            r_beat <= 'd0;
                            r_data <= {I_FDI_PL_DATA, r_acc};
                        end else begin
                            r_beat <= w_beat + 1'b1;
                            for (int b = 0; b < BEATS-1; b++) begin
                                if (w_beat == BEAT_WD'(b))
                                    r_acc[b] <= I_FDI_PL_DATA;
                            end
                        end
                    end else if (I_FDI_PL_FLIT_CANCEL) begin
                        r_beat <= 'd0;
                    end
                end
            end
        end
    endgenerate

    assign O_AOU_RX_HF_VALID = r_valid & ~I_FDI_PL_FLIT_CANCEL;
    assign O_AOU_RX_HF_DATA  = r_data;

endmodule
