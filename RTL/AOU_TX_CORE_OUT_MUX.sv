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
//  Module     : AOU_TX_CORE_OUT_MUX
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TX_CORE_OUT_MUX #(
    parameter int FDI_IF_WD = 512
)   
( 
    input                                   I_CLK,
    input                                   I_RESETN,

    input                                   I_PHY_TYPE,

    output logic                            O_FDI_PL_TRDY,
    output logic                            O_CHUNK_PARTIAL,
    input  logic [FDI_IF_WD-1:0]            I_FDI_LP_DATA,
    input  logic                            I_FDI_LP_VALID,

    input  logic                            I_FDI_PL_0_TRDY,
    output logic [FDI_IF_WD/2-1:0]          O_FDI_LP_0_DATA,
    output logic                            O_FDI_LP_0_VALID,

    input  logic                            I_FDI_PL_1_TRDY,
    output logic [FDI_IF_WD-1:0]            O_FDI_LP_1_DATA,
    output logic                            O_FDI_LP_1_VALID
);

logic                                   r_phase;

assign O_FDI_LP_1_VALID = I_PHY_TYPE & I_FDI_LP_VALID;
assign O_FDI_LP_1_DATA = I_PHY_TYPE ? I_FDI_LP_DATA : 'd0;

assign O_FDI_LP_0_VALID = ~I_PHY_TYPE & I_FDI_LP_VALID;
assign O_FDI_LP_0_DATA = I_PHY_TYPE ? 'd0 :
                           ~r_phase   ? I_FDI_LP_DATA[FDI_IF_WD/2-1:0]  :
                                        I_FDI_LP_DATA[FDI_IF_WD-1:FDI_IF_WD/2];

assign O_FDI_PL_TRDY = I_PHY_TYPE ? I_FDI_PL_1_TRDY :
                       (I_FDI_PL_0_TRDY & r_phase);

// O_CHUNK_PARTIAL: part of the current chunk is already on the narrower PHY
// and the rest is still owed (with today's 2:1 split, the lower half has been
// sent and the chunk is acknowledged only with the upper half), so
// I_FDI_LP_VALID must stay high until O_FDI_PL_TRDY or the flit is truncated
// mid-chunk.
assign O_CHUNK_PARTIAL = ~I_PHY_TYPE & r_phase;

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_phase <= 1'b0;
    end else begin
        if(~I_PHY_TYPE) begin
            if(~r_phase & I_FDI_LP_VALID & I_FDI_PL_0_TRDY)
                r_phase <= 1'b1;
            else if (r_phase & I_FDI_PL_0_TRDY)
                r_phase <= 1'b0;
        end

    end
end

endmodule
