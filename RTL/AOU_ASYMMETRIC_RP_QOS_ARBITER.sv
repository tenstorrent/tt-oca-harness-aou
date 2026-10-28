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
//  Module     : AOU_ASYMMETRIC_QOS_ARBITER
//  Version    : 1.00
//  Date       : 26-10-25
//  Author     : Soyoung Min, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

/*
Module : QoS Arbiter
Description :
Arbitration Scheme
00 : RoundRobin / 01 : Port QoS field / 10 : Current QoS 
*/

`timescale 1ns/1ps

module AOU_ASYMMETRIC_RP_QOS_ARBITER #(
    parameter   RP_CNT        = 4 
)(
    input                       I_CLK,
    input                       I_RESETN,

    input   [1:0]               I_ARB_MODE,
    input   [RP_CNT-1:0][1:0]   I_QOS,
    input   [RP_CNT-1:0]        I_REQ,
    input                       I_ARB_EN,
    
    output  [RP_CNT-1:0]        O_GRANTED_AGENT
);


logic   [RP_CNT-1:0]      r_grant;
logic   [RP_CNT-1:0]      w_grant_next;
logic   [RP_CNT-1:0]      w_grant_rr_next, w_grant_qos_next;

logic   [RP_CNT-1:0]      r_prev_req;
logic   [RP_CNT-1:0][1:0] r_prev_qos;
logic                     r_keep_prev_req;
logic                     w_any_request;

generate
    if(RP_CNT == 4) begin
        AOU_4X1_RR_ARBITER u_tx_rr_arbiter(
            .I_REQUEST      (r_keep_prev_req ? r_prev_req : I_REQ ),
            .I_GRANT        (r_grant        ),
            .O_GRANT_NEXT   ( w_grant_rr_next  )
        );
        always @(posedge I_CLK or negedge I_RESETN) begin
            if (~I_RESETN) begin
                r_grant <= 4'b1000;
            end else if (w_any_request & I_ARB_EN) begin
                r_grant <= w_grant_next;
            end
        end
    end else if (RP_CNT == 3) begin
        AOU_3X1_RR_ARBITER u_tx_rr_arbiter(
            .I_REQUEST      (r_keep_prev_req ? r_prev_req : I_REQ ),
            .I_GRANT        (r_grant        ),
            .O_GRANT_NEXT   ( w_grant_rr_next  )
        );
        always @(posedge I_CLK or negedge I_RESETN) begin
            if (~I_RESETN) begin
                r_grant <= 3'b100;
            end else if (w_any_request & I_ARB_EN) begin
                r_grant <= w_grant_next;
            end
        end
    end else if (RP_CNT == 2) begin
        AOU_2X1_RR_ARBITER u_tx_rr_arbiter(
            .I_REQUEST      (r_keep_prev_req ? r_prev_req : I_REQ ),
            .I_GRANT        (r_grant        ),
            .O_GRANT_NEXT   ( w_grant_rr_next  )
        );
        always @(posedge I_CLK or negedge I_RESETN) begin
            if (~I_RESETN) begin
                r_grant <= 2'b10;
            end else if (w_any_request & I_ARB_EN) begin
                r_grant <= w_grant_next;
            end
        end
    end else begin
        assign r_grant = 1'b1;
        assign w_grant_rr_next = r_grant;
    end
endgenerate

AOU_ASYMMETRIC_QOS_CURRENT_ARBITER #(
    .RP_CNT         (RP_CNT      )
) u_tx_cur_qos_arbiter(
    .I_REQ          (r_keep_prev_req ? r_prev_req : I_REQ),
    .I_GRANT        (r_grant        ),
    .I_QOS          (r_keep_prev_req ? r_prev_qos : I_QOS),
    .O_GRANT_NEXT   (w_grant_qos_next  )
);

always_comb begin
    case (I_ARB_MODE)
        2'b00 : w_grant_next = w_grant_rr_next;
        2'b01 : w_grant_next = w_grant_qos_next; //Port Priority
        2'b10 : w_grant_next = w_grant_qos_next; //Qos Priority
        2'b11 : w_grant_next = w_grant_rr_next;
        default: w_grant_next = w_grant_rr_next;
    endcase
end
assign w_any_request = |I_REQ;

always @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_prev_req <= 'd0;
        r_prev_qos <= 'd0;
    end else if (~r_keep_prev_req & ~I_ARB_EN) begin
        r_prev_req <= I_REQ;
        r_prev_qos <= I_QOS;
    end
end

always @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_keep_prev_req <= 1'b0;
    end else if (w_any_request & ~I_ARB_EN) begin
        r_keep_prev_req <= 1'b1;
    end else if(I_ARB_EN) begin 
        r_keep_prev_req <= 1'b0;
    end
end

assign O_GRANTED_AGENT = w_grant_next;

endmodule

module AOU_ASYMMETRIC_QOS_CURRENT_ARBITER #(
    parameter RP_CNT = 4
)(
    input  logic [RP_CNT-1:0]        I_REQ,
    input  logic [RP_CNT-1:0]        I_GRANT,
    input  logic [RP_CNT-1:0][1:0]   I_QOS,
    output logic [RP_CNT-1:0]        O_GRANT_NEXT
);

logic [RP_CNT-1:0] w_req_qos3;
logic [RP_CNT-1:0] w_req_qos2;
logic [RP_CNT-1:0] w_req_qos1;

logic              w_has_qos3;
logic              w_has_qos2;
logic [RP_CNT-1:0] w_candidate;

// Select requests with the highest QoS.
// Valid QoS values: 2'b01, 2'b10, 2'b11.
assign w_has_qos3 = |w_req_qos3;
assign w_has_qos2 = |w_req_qos2;

assign w_candidate =
      w_req_qos3
    | (w_req_qos2 & {RP_CNT{~w_has_qos3}})
    | (w_req_qos1 & {RP_CNT{~w_has_qos3 & ~w_has_qos2}});

generate
    for (genvar g = 0; g < RP_CNT; g++) begin : GEN_QOS
        assign w_req_qos3[g] = I_REQ[g] & (I_QOS[g] == 2'b11);
        assign w_req_qos2[g] = I_REQ[g] & (I_QOS[g] == 2'b10);
        assign w_req_qos1[g] = I_REQ[g] & (I_QOS[g] == 2'b01);
    end

    // I_GRANT is assumed to be one-hot.
    if (RP_CNT == 4) begin : GEN_RP4
        always_comb begin
            O_GRANT_NEXT = '0;

            case (I_GRANT)
                4'b0001: begin  // RP1 -> RP2 -> RP3 -> RP0
                    if      (w_candidate[1]) O_GRANT_NEXT = 4'b0010;
                    else if (w_candidate[2]) O_GRANT_NEXT = 4'b0100;
                    else if (w_candidate[3]) O_GRANT_NEXT = 4'b1000;
                    else if (w_candidate[0]) O_GRANT_NEXT = 4'b0001;
                end

                4'b0010: begin  // RP2 -> RP3 -> RP0 -> RP1
                    if      (w_candidate[2]) O_GRANT_NEXT = 4'b0100;
                    else if (w_candidate[3]) O_GRANT_NEXT = 4'b1000;
                    else if (w_candidate[0]) O_GRANT_NEXT = 4'b0001;
                    else if (w_candidate[1]) O_GRANT_NEXT = 4'b0010;
                end

                4'b0100: begin  // RP3 -> RP0 -> RP1 -> RP2
                    if      (w_candidate[3]) O_GRANT_NEXT = 4'b1000;
                    else if (w_candidate[0]) O_GRANT_NEXT = 4'b0001;
                    else if (w_candidate[1]) O_GRANT_NEXT = 4'b0010;
                    else if (w_candidate[2]) O_GRANT_NEXT = 4'b0100;
                end

                4'b1000: begin  // RP0 -> RP1 -> RP2 -> RP3
                    if      (w_candidate[0]) O_GRANT_NEXT = 4'b0001;
                    else if (w_candidate[1]) O_GRANT_NEXT = 4'b0010;
                    else if (w_candidate[2]) O_GRANT_NEXT = 4'b0100;
                    else if (w_candidate[3]) O_GRANT_NEXT = 4'b1000;
                end

                default: O_GRANT_NEXT = '0;
            endcase
        end

    end else if (RP_CNT == 3) begin : GEN_RP3
        always_comb begin
            O_GRANT_NEXT = '0;

            case (I_GRANT)
                3'b001: begin  // RP1 -> RP2 -> RP0
                    if      (w_candidate[1]) O_GRANT_NEXT = 3'b010;
                    else if (w_candidate[2]) O_GRANT_NEXT = 3'b100;
                    else if (w_candidate[0]) O_GRANT_NEXT = 3'b001;
                end

                3'b010: begin  // RP2 -> RP0 -> RP1
                    if      (w_candidate[2]) O_GRANT_NEXT = 3'b100;
                    else if (w_candidate[0]) O_GRANT_NEXT = 3'b001;
                    else if (w_candidate[1]) O_GRANT_NEXT = 3'b010;
                end

                3'b100: begin  // RP0 -> RP1 -> RP2
                    if      (w_candidate[0]) O_GRANT_NEXT = 3'b001;
                    else if (w_candidate[1]) O_GRANT_NEXT = 3'b010;
                    else if (w_candidate[2]) O_GRANT_NEXT = 3'b100;
                end

                default: O_GRANT_NEXT = '0;
            endcase
        end

    end else if (RP_CNT == 2) begin : GEN_RP2
        always_comb begin
            O_GRANT_NEXT = '0;

            case (I_GRANT)
                2'b01: begin  // RP1 -> RP0
                    if      (w_candidate[1]) O_GRANT_NEXT = 2'b10;
                    else if (w_candidate[0]) O_GRANT_NEXT = 2'b01;
                end

                2'b10: begin  // RP0 -> RP1
                    if      (w_candidate[0]) O_GRANT_NEXT = 2'b01;
                    else if (w_candidate[1]) O_GRANT_NEXT = 2'b10;
                end

                default: O_GRANT_NEXT = '0;
            endcase
        end

    end else begin : GEN_OTHER
        // RP_CNT=1: pass the sole candidate.
        // Supported RP_CNT range: 1 to 4.
        assign O_GRANT_NEXT = w_candidate;
    end
endgenerate

endmodule
