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
//  Module     : AOU_TPSRAM
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

module AOU_TPSRAM #(
    parameter RAM_DATA_WIDTH = 32,
    parameter RAM_ADDR_WIDTH = 16,
    parameter RAM_DEPTH      = 2**RAM_ADDR_WIDTH
) (
    // Read Port 
    input  wire                      CLKA,
    input  wire                      CENA,
    input  wire [RAM_ADDR_WIDTH-1:0] AA,
    output reg  [RAM_DATA_WIDTH-1:0] QA,
    
    // Write Port
    input  wire                      CLKB,
    input  wire                      CENB,
    input  wire [RAM_ADDR_WIDTH-1:0] AB,
    input  wire [RAM_DATA_WIDTH-1:0] DB
);

   reg [RAM_DATA_WIDTH-1:0] mem [RAM_DEPTH-1:0];

   always @(posedge CLKA) begin 
      if (!CENA) QA <= mem[AA];
      //else       QA <= 'hz; 
   end

   always @(posedge CLKB) begin 
      if (!CENB) mem[AB] <= DB;
   end

endmodule
