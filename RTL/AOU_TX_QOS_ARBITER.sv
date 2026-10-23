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
//  Module     : AOU_TX_QOS_ARBITER
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

/*
Module : QoS Arbiter
Description :
Arbitration Scheme
00 : RoundRobin / 01 : Port QoS field / 10 : Current QoS 
*/

`timescale 1ns/1ps

module AOU_TX_QOS_ARBITER #(
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


logic   [RP_CNT-1:0]    r_grant;
logic   [RP_CNT-1:0]    w_grant_next;
logic   [RP_CNT-1:0]    w_grant_rr_next, w_grant_qos_next;

logic   [RP_CNT-1:0]    r_prev_req;
logic                   r_keep_prev_req;
logic                   w_any_request;
logic   [RP_CNT-1:0]    w_rr_req;

// I_REQ is gated by credit, which can be withdrawn without a send (credit clear on
// disable). Fall back to the live request rather than hold a grant nobody can use.
assign w_rr_req = (r_keep_prev_req & |(r_prev_req & I_REQ)) ? (r_prev_req & I_REQ) : I_REQ;

generate
    if(RP_CNT == 4) begin
        AOU_4X1_RR_ARBITER u_tx_rr_arbiter(
            .I_REQUEST      (w_rr_req       ),
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
            .I_REQUEST      (w_rr_req       ),
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
            .I_REQUEST      (w_rr_req       ),
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

AOU_TX_QOS_CURRENT_ARBITER #(
    .RP_CNT         (RP_CNT      )
) u_tx_cur_qos_arbiter(
    .I_REQ          (I_REQ        ),
    .I_GRANT        (r_grant        ),
    .I_QOS          (I_QOS          ),
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
    end else if (~r_keep_prev_req & ~I_ARB_EN) begin
        r_prev_req <= I_REQ;
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

module AOU_TX_QOS_CURRENT_ARBITER # (
    parameter RP_CNT = 4,
    localparam RP_CNT_WD = (RP_CNT>1)?$clog2(RP_CNT) : 1
)(
    input  logic [RP_CNT-1:0]        I_REQ,
    input  logic [RP_CNT-1:0]        I_GRANT,
    input  logic [RP_CNT-1:0][1:0]   I_QOS,
    output logic [RP_CNT-1:0]        O_GRANT_NEXT
);

logic [1:0] w_max_qos;
int idx;
int cur_idx;

always_comb begin
    w_max_qos = 2'b00;
    O_GRANT_NEXT = 'b0;
    cur_idx   = 'd0;
    for (int unsigned i = 0; i < RP_CNT ; i++) begin
        if (I_GRANT[i] == 1'b1) cur_idx = i;
    end
    
    for (int unsigned k = 1 ; k <= RP_CNT ; k++) begin
        idx = (cur_idx + k >= RP_CNT) ? cur_idx + k - RP_CNT : cur_idx + k;

        if ((I_QOS[idx[RP_CNT_WD-1:0]] > w_max_qos) && (I_REQ[idx[RP_CNT_WD-1:0]] == 1'b1)) begin
            w_max_qos = I_QOS[idx[RP_CNT_WD-1:0]];
            O_GRANT_NEXT = 'b0;
            O_GRANT_NEXT[idx[RP_CNT_WD-1:0]] = 1'b1;
        end
    end
end

endmodule
