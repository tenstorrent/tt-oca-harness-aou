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
//  Module     : AOU_TX_ARBITER
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_TX_ARBITER #(
    parameter   RP_CNT        = 4 
)(
    input                   I_CLK,
    input                   I_RESETN,

    input   [RP_CNT-1:0]    I_REQ,
    input                   I_ARB_EN,
    
    output  [RP_CNT-1:0]    O_GRANTED_AGENT
);

logic   [RP_CNT-1:0]    r_grant;
logic   [RP_CNT-1:0]    r_prev_req;
logic                   r_keep_prev_req;
logic   [RP_CNT-1:0]    w_grant_next;
logic   [RP_CNT-1:0]    w_rr_req;

// I_REQ is gated by credit, which can be withdrawn without a send (credit clear on
// disable). Fall back to the live request rather than hold a grant nobody can use.
assign w_rr_req = (r_keep_prev_req & |(r_prev_req & I_REQ)) ? (r_prev_req & I_REQ) : I_REQ;

AOU_TX_RR_ARBITER #(
    .RP_CNT         (RP_CNT         )
) u_tx_rr_arbiter(
    .I_REQUEST      (w_rr_req       ),
    .I_GRANT        (r_grant        ),
    .O_GRANT_NEXT   (w_grant_next   )
);

logic  w_any_request;  
assign w_any_request = |I_REQ ;

always @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_grant <= {1'b1, {(RP_CNT-1){1'b0}}};
    end else if (w_any_request & I_ARB_EN) begin
        r_grant <= w_grant_next;
    end
end

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


module AOU_TX_RR_ARBITER #(
    parameter int RP_CNT = 4
)(
    input  logic [RP_CNT-1:0] I_REQUEST,   
    input  logic [RP_CNT-1:0] I_GRANT,     
    output logic [RP_CNT-1:0] O_GRANT_NEXT 
);

generate
    if(RP_CNT == 4) begin
        always @(*) begin
            O_GRANT_NEXT = I_GRANT;
            case(1) 
                I_GRANT[0]:
                    if      (I_REQUEST[1])  O_GRANT_NEXT = 4'b0010;
                    else if (I_REQUEST[2])  O_GRANT_NEXT = 4'b0100;
                    else if (I_REQUEST[3])  O_GRANT_NEXT = 4'b1000;
                    else if (I_REQUEST[0])  O_GRANT_NEXT = 4'b0001;
                I_GRANT[1]:
                    if      (I_REQUEST[2])  O_GRANT_NEXT = 4'b0100;
                    else if (I_REQUEST[3])  O_GRANT_NEXT = 4'b1000;
                    else if (I_REQUEST[0])  O_GRANT_NEXT = 4'b0001;
                    else if (I_REQUEST[1])  O_GRANT_NEXT = 4'b0010;
                I_GRANT[2]:
                    if      (I_REQUEST[3])  O_GRANT_NEXT = 4'b1000;
                    else if (I_REQUEST[0])  O_GRANT_NEXT = 4'b0001;
                    else if (I_REQUEST[1])  O_GRANT_NEXT = 4'b0010;
                    else if (I_REQUEST[2])  O_GRANT_NEXT = 4'b0100;
                I_GRANT[3]:
                    if      (I_REQUEST[0])  O_GRANT_NEXT = 4'b0001;
                    else if (I_REQUEST[1])  O_GRANT_NEXT = 4'b0010;
                    else if (I_REQUEST[2])  O_GRANT_NEXT = 4'b0100;
                    else if (I_REQUEST[3])  O_GRANT_NEXT = 4'b1000;
            endcase
        end
    end else if(RP_CNT == 3) begin
        always @(*) begin
            O_GRANT_NEXT = I_GRANT;
            case(1) 
                I_GRANT[0]:
                    if      (I_REQUEST[1])  O_GRANT_NEXT = 3'b010;
                    else if (I_REQUEST[2])  O_GRANT_NEXT = 3'b100;
                    else if (I_REQUEST[0])  O_GRANT_NEXT = 3'b001;
                I_GRANT[1]:
                    if      (I_REQUEST[2])  O_GRANT_NEXT = 3'b100;
                    else if (I_REQUEST[0])  O_GRANT_NEXT = 3'b001;
                    else if (I_REQUEST[1])  O_GRANT_NEXT = 3'b010;
                I_GRANT[2]:
                    if      (I_REQUEST[0])  O_GRANT_NEXT = 3'b001;
                    else if (I_REQUEST[1])  O_GRANT_NEXT = 3'b010;
                    else if (I_REQUEST[2])  O_GRANT_NEXT = 3'b100;
            endcase
        end 
    end else if(RP_CNT == 2) begin
        always @(*) begin
            O_GRANT_NEXT = I_GRANT;
            case(1) 
                I_GRANT[0]:
                    if      (I_REQUEST[1])  O_GRANT_NEXT = 2'b10;
                    else if (I_REQUEST[0])  O_GRANT_NEXT = 2'b01;
                I_GRANT[1]:
                    if      (I_REQUEST[0])  O_GRANT_NEXT = 2'b01;
                    else if (I_REQUEST[1])  O_GRANT_NEXT = 2'b10;
            endcase
        end      
    end else begin
        assign O_GRANT_NEXT = I_GRANT;
    end
endgenerate

endmodule
