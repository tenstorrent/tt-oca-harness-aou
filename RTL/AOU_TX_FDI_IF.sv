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
//  Module     : AOU_TX_FDI_IF
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TX_FDI_IF #(
  parameter FDI_DATA_WD = 512
)
(
  input I_CLK,
  input I_RESETN,

  //------------------------------------------------------------
  //AOU_TX_CORE Interface
  //------------------------------------------------------------
  input                             I_AOU_TX_FLIT_DATA_VALID,
  input        [FDI_DATA_WD-1:0]    I_AOU_TX_FLIT_DATA,
  output logic                      O_AOU_TX_FLIT_READY,

  //------------------------------------------------------------
  //FDI Interface
  //------------------------------------------------------------
  input                             I_FDI_PL_TRDY,
  input                             I_FDI_PL_STALLREQ,
  input        [3:0]                I_FDI_PL_STATE_STS,
  output logic [FDI_DATA_WD-1:0]    O_FDI_LP_DATA,
  output logic                      O_FDI_LP_VALID,
  output logic                      O_FDI_LP_IRDY,
  output logic                      O_FDI_LP_STALLACK

);
// Beats per 256 B flit; one at 2048 bits, where the phase counter stays 0.
localparam PHASE_CNT      = 256*8 / FDI_DATA_WD;
localparam PHASE_WD       = (PHASE_CNT > 1) ? $clog2(PHASE_CNT) : 1;
localparam ST_FDI_STS_RST = 4'b0000;
localparam PL_STATE_STS_ACTIVE = 4'b0001;

logic   [PHASE_WD-1:0]   r_phase_cnt;
logic                    w_phase_start;
logic                    w_valid;
logic                    w_ready;
logic                    w_fdi_lp_stallack;
logic                    r_fdi_lp_stallack;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_phase_cnt <= 'd0;
    end else if (I_AOU_TX_FLIT_DATA_VALID & O_AOU_TX_FLIT_READY) begin
        r_phase_cnt <= (PHASE_CNT > 1) ? r_phase_cnt + 1'b1 : '0;
    end
end

assign  w_phase_start   = ~(|r_phase_cnt);

always_comb begin
    if(w_phase_start) begin
        if(O_FDI_LP_STALLACK || I_FDI_PL_STALLREQ) begin
            w_valid = 1'b0;
            w_ready = 1'b0;
            w_fdi_lp_stallack = I_FDI_PL_STALLREQ;
        end else begin
            w_valid = I_AOU_TX_FLIT_DATA_VALID && (I_FDI_PL_STATE_STS == PL_STATE_STS_ACTIVE);
            w_ready = I_FDI_PL_TRDY && (I_FDI_PL_STATE_STS == PL_STATE_STS_ACTIVE);
            w_fdi_lp_stallack = 1'b0;
        end
    end else begin
        w_valid = I_AOU_TX_FLIT_DATA_VALID && (!O_FDI_LP_STALLACK);
        w_ready = I_FDI_PL_TRDY && (I_FDI_PL_STATE_STS == PL_STATE_STS_ACTIVE);
        w_fdi_lp_stallack = r_fdi_lp_stallack && I_FDI_PL_STALLREQ;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_fdi_lp_stallack <= 1'b0; 
    end else begin
        r_fdi_lp_stallack <= w_fdi_lp_stallack;
    end
end


assign  O_AOU_TX_FLIT_READY = w_ready;

assign  O_FDI_LP_VALID      = O_FDI_LP_IRDY ? w_valid : 1'b0;
assign  O_FDI_LP_IRDY       = (I_FDI_PL_STATE_STS == ST_FDI_STS_RST) ? 1'b0 : !O_FDI_LP_STALLACK;
assign  O_FDI_LP_STALLACK   = r_fdi_lp_stallack;
assign  O_FDI_LP_DATA       = I_AOU_TX_FLIT_DATA;

endmodule
