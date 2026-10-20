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
//  Module     : AOU_WRITE_TRANS_WDT
//  Version    : 1.00
//  Date       : 26-10-19
//  Author     : Soyoung Min
//
// *****************************************************************************

module AOU_WRITE_TRANS_WDT #(
  parameter BOS_PARAM_WR_CNT_WD = 32
)(
  //------------------------------------------------------------
  // Clock and reset
  //------------------------------------------------------------
  input                                  I_ACLK,
  input                                  I_RESETN_ACLK,

  //------------------------------------------------------------
  // SFR interface (I_ACLK domain)
  // Threshold is expressed in I_ACLK cycles.
  //------------------------------------------------------------
  input                                  I_SFR_WDT_EN,
  input  [31:0]                          I_SFR_WDT_THRESHOLD,

  //------------------------------------------------------------
  // AXI interface (I_ACLK domain)
  //------------------------------------------------------------
  input                                  I_AXI_AW_HS,
  input                                  I_AXI_B_HS,
  input  [BOS_PARAM_WR_CNT_WD-1:0]       I_WR_PEND_CNT,

  //------------------------------------------------------------
  // Outputs (I_ACLK domain, Timeout event pulse; emitted once per reset)
  //------------------------------------------------------------
  output logic                           O_AXI_WR_TRANS_TIMEOUT_ERR
);
  logic                                  write_cnt_inc;
  logic                                  write_cnt_dec;
  logic                                  timeout_tmr_cnt_en;
  logic                                  clr_tmr;
  logic                                  incr_tmr;
  logic [32:0]                           r_tmr_cnt;
  logic                                  r_axi_trans_timeout_event;

  assign write_cnt_inc = I_SFR_WDT_EN & I_AXI_AW_HS;
  assign write_cnt_dec = I_SFR_WDT_EN & I_AXI_B_HS;

  // No CDC or pulse expansion is needed in the single-clock design.
  assign timeout_tmr_cnt_en = I_SFR_WDT_EN & (|I_WR_PEND_CNT);
  assign clr_tmr = !timeout_tmr_cnt_en |
                   write_cnt_inc | write_cnt_dec |
                   r_axi_trans_timeout_event;
  assign incr_tmr = timeout_tmr_cnt_en &
                   (r_tmr_cnt < I_SFR_WDT_THRESHOLD);

  // Count idle cycles while write transactions are outstanding.
  // Either an AW handshake or a B handshake restarts the timer.
  always_ff @(posedge I_ACLK or negedge I_RESETN_ACLK) begin
    if (!I_RESETN_ACLK)
      r_tmr_cnt <= '0;
    else begin
      casez ({clr_tmr, incr_tmr})
        2'b1?: r_tmr_cnt <= '0;
        2'b01: r_tmr_cnt <= $bits(r_tmr_cnt)'(r_tmr_cnt + 1'b1);
        2'b00: r_tmr_cnt <= r_tmr_cnt;
        default: r_tmr_cnt <= 'x;
      endcase
    end
  end

  // Sticky timeout flag. Timer clear has priority over timeout detection.
  // Preserve the original comparison against the current timer count:
  // the flag is set on a qualifying edge after the count reaches threshold.
  always_ff @(posedge I_ACLK or negedge I_RESETN_ACLK) begin
    if (!I_RESETN_ACLK)
      r_axi_trans_timeout_event <= 1'b0;
    else if (!clr_tmr && timeout_tmr_cnt_en &&
             (r_tmr_cnt >= I_SFR_WDT_THRESHOLD))
      r_axi_trans_timeout_event <= 1'b1;
  end

  // Combinational timeout event.
  // Captured by the SFR and suppressed by the internal sticky flag.
  assign O_AXI_WR_TRANS_TIMEOUT_ERR = !clr_tmr && timeout_tmr_cnt_en && (r_tmr_cnt >= I_SFR_WDT_THRESHOLD);
endmodule : AOU_WRITE_TRANS_WDT
