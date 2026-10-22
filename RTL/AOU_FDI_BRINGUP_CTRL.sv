// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 Tenstorrent AI ULC
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
//  Module     : AOU_FDI_BRINGUP_CTRL
//  Description: FDI bringup/teardown state machine per UCIe 3.0 specification.
//               Manages the four FDI handshake pairs:
//                 - lp_wake_req  / pl_wake_ack  (LP-initiated wake)
//                 - pl_clk_req   / lp_clk_ack   (PL-initiated clock request)
//                 - lp_state_req / pl_state_sts  (state negotiation)
//                 - pl_rx_active_req / lp_rx_active_sts (RX activation)
//               Bridges to the AOU activation/deactivation control via
//               I_INT_FSM_IN_ACTIVE, ACTIVATE_START, and DEACTIVATE_START.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_FDI_BRINGUP_CTRL (
    input  logic        I_CLK,
    input  logic        I_RESETN,

    // ----------------------------------------------------------------
    // Physical Layer (PL) → Link Protocol (LP) signals
    // ----------------------------------------------------------------
    input  logic [3:0]  I_PL_STATE_STS,
    input  logic        I_PL_INBAND_PRES,
    input  logic        I_PL_CLK_REQ,
    input  logic        I_PL_WAKE_ACK,
    input  logic        I_PL_RX_ACTIVE_REQ,
    input  logic        I_PL_STALLREQ,

    // ----------------------------------------------------------------
    // Link Protocol (LP) → Physical Layer (PL) signals
    // ----------------------------------------------------------------
    output logic [3:0]  O_LP_STATE_REQ,
    output logic        O_LP_WAKE_REQ,
    output logic        O_LP_CLK_ACK,
    output logic        O_LP_RX_ACTIVE_STS,

    // ----------------------------------------------------------------
    // AOU Activation Control interface
    // ----------------------------------------------------------------
    output logic        O_INT_FSM_IN_ACTIVE,
    input  logic        I_AOU_ACTIVATE_ST_DISABLED,
    input  logic        I_AOU_ACTIVATE_ST_ENABLED,
    input  logic        I_AOU_REQ_LINKRESET,
    input  logic        I_INT_ACTIVATE_START,
    input  logic        I_INT_DEACTIVATE_START,

    // ----------------------------------------------------------------
    // Software control
    // ----------------------------------------------------------------
    input  logic        I_SW_ACTIVATE_START,
    input  logic        I_SW_DEACTIVATE_START,
    input  logic        I_SW_RETRAIN_REQ,
    input  logic        I_SW_LINKERROR_INJECT,
    input  logic        I_SW_RESET,          // AOU_CON0.AOU_SW_RESET in effect

    // ----------------------------------------------------------------
    // Status outputs
    // ----------------------------------------------------------------
    output logic [3:0]  O_FSM_STATE,
    output logic        O_LINK_UP
);

    // ================================================================
    // UCIe 3.0 FDI State Encodings (pl_state_sts / lp_state_req)
    // ================================================================
    localparam FDI_ST_RESET      = 4'h0;
    localparam FDI_ST_ACTIVE     = 4'h1;
    localparam FDI_ST_LINKERROR  = 4'h2;
    localparam FDI_ST_RETRAIN    = 4'h3;
    localparam FDI_ST_L1         = 4'h4;
    localparam FDI_ST_L2         = 4'h5;
    localparam FDI_ST_DISABLED   = 4'h6;

    // ================================================================
    // Internal FSM States (one-hot, 12 states)
    // ================================================================
    localparam ST_RESET           = 12'b0000_0000_0001;
    localparam ST_WAIT_PRESENCE   = 12'b0000_0000_0010;
    localparam ST_WAKE_ASSERT     = 12'b0000_0000_0100;
    localparam ST_WAKE_WAIT_ACK   = 12'b0000_0000_1000;
    localparam ST_REQ_ACTIVE      = 12'b0000_0001_0000;
    localparam ST_ACTIVE          = 12'b0000_0010_0000;
    localparam ST_LINKERROR       = 12'b0000_0100_0000;
    localparam ST_RETRAIN         = 12'b0000_1000_0000;
    localparam ST_DEACTIVATE      = 12'b0001_0000_0000;
    localparam ST_UNWAKE_WAIT     = 12'b0010_0000_0000;
    localparam ST_L1              = 12'b0100_0000_0000;
    localparam ST_L1_CLK_WAKE     = 12'b1000_0000_0000;

    logic [11:0] r_cur_st;
    logic [11:0] w_nxt_st;

    // ================================================================
    // PL state decode
    // ================================================================
    logic w_pl_active;
    logic w_pl_reset;
    logic w_pl_linkerror;
    logic w_pl_retrain;
    logic w_pl_l1;

    assign w_pl_active    = (I_PL_STATE_STS == FDI_ST_ACTIVE);
    assign w_pl_reset     = (I_PL_STATE_STS == FDI_ST_RESET);
    assign w_pl_linkerror = (I_PL_STATE_STS == FDI_ST_LINKERROR);
    assign w_pl_retrain   = (I_PL_STATE_STS == FDI_ST_RETRAIN);
    assign w_pl_l1        = (I_PL_STATE_STS == FDI_ST_L1);

    // ================================================================
    // Request aggregation
    // ================================================================
    logic w_activate_request;
    logic w_deactivate_request;
    logic w_linkerror_request;
    logic w_retrain_request;

    assign w_activate_request   = I_SW_ACTIVATE_START | I_INT_ACTIVATE_START;
    assign w_deactivate_request = I_SW_DEACTIVATE_START | I_INT_DEACTIVATE_START;
    assign w_linkerror_request  = I_AOU_REQ_LINKRESET | I_SW_LINKERROR_INJECT;
    assign w_retrain_request    = I_SW_RETRAIN_REQ;

    // ================================================================
    // Inband presence edge detect
    // ================================================================
    logic r_pl_inband_pres_d1;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_pl_inband_pres_d1 <= 1'b0;
        end else begin
            r_pl_inband_pres_d1 <= I_PL_INBAND_PRES;
        end
    end

    // ================================================================
    // AOU_SW_RESET seen since LINKERROR entry
    //
    // A LinkError may leave Active in the middle of a flit in either
    // direction (UCIe r1.1 8.3.3.7). AOU_CORE's FDI data paths keep
    // their beat position across it and are cleared only by
    // AOU_CON0.AOU_SW_RESET, which the MAS LinkReset sequence already
    // requires. Until software has applied that reset the link is held
    // down: LINKERROR keeps requesting Reset and does not leave for
    // RESET, so a flit abandoned by the LinkError can never be resumed
    // against a fresh Adapter flit boundary.
    // ================================================================
    logic r_sw_reset_seen;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_sw_reset_seen <= 1'b0;
        end else if (r_cur_st != ST_LINKERROR) begin
            r_sw_reset_seen <= 1'b0;
        end else if (I_SW_RESET) begin
            r_sw_reset_seen <= 1'b1;
        end
    end

    // ================================================================
    // Main FSM
    // ================================================================
    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_cur_st <= ST_RESET;
        end else begin
            r_cur_st <= w_nxt_st;
        end
    end

    always_comb begin
        w_nxt_st = r_cur_st;

        case (r_cur_st)
            // ----------------------------------------------------------
            // RESET: Wait for PL to report RESET and remote die presence.
            // ----------------------------------------------------------
            ST_RESET: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_reset && I_PL_INBAND_PRES) begin
                    w_nxt_st = ST_WAIT_PRESENCE;
                end
            end

            // ----------------------------------------------------------
            // WAIT_PRESENCE: Remote die detected. Assert lp_rx_active_sts.
            // Wait for an activation trigger or PL-initiated clock request
            // before starting the wake handshake.
            // ----------------------------------------------------------
            ST_WAIT_PRESENCE: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_activate_request || I_PL_CLK_REQ) begin
                    w_nxt_st = ST_WAKE_ASSERT;
                end else if (!I_PL_INBAND_PRES) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // WAKE_ASSERT: Assert lp_wake_req. Registered output updates
            // this cycle; transition immediately to wait for ack.
            // ----------------------------------------------------------
            ST_WAKE_ASSERT: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else begin
                    w_nxt_st = ST_WAKE_WAIT_ACK;
                end
            end

            // ----------------------------------------------------------
            // WAKE_WAIT_ACK: lp_wake_req is asserted. Wait for PL to
            // respond with pl_wake_ack, confirming the physical layer is
            // awake and clocked.
            // ----------------------------------------------------------
            ST_WAKE_WAIT_ACK: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (I_PL_WAKE_ACK) begin
                    w_nxt_st = ST_REQ_ACTIVE;
                end else if (!I_PL_INBAND_PRES && w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // REQ_ACTIVE: Wake handshake complete. Drive lp_state_req =
            // ACTIVE. Wait for PL to reach ACTIVE state AND assert
            // pl_rx_active_req (PL's RX is ready). LP responds with
            // lp_rx_active_sts via the output logic below.
            // ----------------------------------------------------------
            ST_REQ_ACTIVE: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_active && I_PL_RX_ACTIVE_REQ) begin
                    w_nxt_st = ST_ACTIVE;
                end else if (!I_PL_INBAND_PRES && w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // ACTIVE: Link is up. FDI data path operational.
            // ----------------------------------------------------------
            ST_ACTIVE: begin
                if (w_pl_linkerror || w_linkerror_request) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_retrain || w_retrain_request) begin
                    w_nxt_st = ST_RETRAIN;
                end else if (w_deactivate_request && I_AOU_ACTIVATE_ST_DISABLED) begin
                    w_nxt_st = ST_DEACTIVATE;
                end else if (w_pl_l1) begin
                    w_nxt_st = ST_L1;
                end else if (w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // LINKERROR: Drive lp_state_req = RESET. Wait for PL to
            // reach RESET and for software to apply AOU_SW_RESET (in
            // either order), then restart.
            // ----------------------------------------------------------
            ST_LINKERROR: begin
                if (w_pl_reset && r_sw_reset_seen) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // RETRAIN: PL is retraining. lp_wake_req stays asserted.
            // Wait for PL to report ACTIVE or LINKERROR.
            // ----------------------------------------------------------
            ST_RETRAIN: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_active) begin
                    w_nxt_st = ST_ACTIVE;
                end
            end

            // ----------------------------------------------------------
            // DEACTIVATE: AOU deactivation handshake is done. Drive
            // lp_state_req = RESET and begin the unwake handshake.
            // ----------------------------------------------------------
            ST_DEACTIVATE: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else begin
                    w_nxt_st = ST_UNWAKE_WAIT;
                end
            end

            // ----------------------------------------------------------
            // UNWAKE_WAIT: lp_wake_req has been de-asserted. Wait for
            // PL to de-assert pl_wake_ack, confirming the physical layer
            // has acknowledged the teardown.
            // ----------------------------------------------------------
            ST_UNWAKE_WAIT: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (!I_PL_WAKE_ACK && w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // L1: Low-power state. lp_wake_req is de-asserted.
            // Wake on PL clock request or LP activation request.
            // ----------------------------------------------------------
            ST_L1: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (I_PL_CLK_REQ) begin
                    w_nxt_st = ST_L1_CLK_WAKE;
                end else if (w_activate_request) begin
                    w_nxt_st = ST_WAKE_ASSERT;
                end else if (w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // L1_CLK_WAKE: PL asserted pl_clk_req while in L1. Assert
            // lp_clk_ack (handled below) and begin LP-side wake sequence.
            // ----------------------------------------------------------
            ST_L1_CLK_WAKE: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else begin
                    w_nxt_st = ST_WAKE_ASSERT;
                end
            end

            default: begin
                w_nxt_st = ST_RESET;
            end
        endcase
    end

    // ================================================================
    // Output: lp_state_req
    // ================================================================
    always_comb begin
        case (r_cur_st)
            ST_RESET:          O_LP_STATE_REQ = FDI_ST_RESET;
            ST_WAIT_PRESENCE:  O_LP_STATE_REQ = FDI_ST_RESET;
            ST_WAKE_ASSERT:    O_LP_STATE_REQ = FDI_ST_RESET;
            ST_WAKE_WAIT_ACK:  O_LP_STATE_REQ = FDI_ST_RESET;
            ST_REQ_ACTIVE:     O_LP_STATE_REQ = FDI_ST_ACTIVE;
            ST_ACTIVE:         O_LP_STATE_REQ = FDI_ST_ACTIVE;
            ST_LINKERROR:      O_LP_STATE_REQ = FDI_ST_RESET;
            ST_RETRAIN:        O_LP_STATE_REQ = FDI_ST_RETRAIN;
            ST_DEACTIVATE:     O_LP_STATE_REQ = FDI_ST_RESET;
            ST_UNWAKE_WAIT:    O_LP_STATE_REQ = FDI_ST_RESET;
            ST_L1:             O_LP_STATE_REQ = FDI_ST_L1;
            ST_L1_CLK_WAKE:    O_LP_STATE_REQ = FDI_ST_L1;
            default:           O_LP_STATE_REQ = FDI_ST_RESET;
        endcase
    end

    // ================================================================
    // Output: lp_wake_req  (registered)
    //
    // UCIe 3.0 wake handshake:
    //   Assert:   LP sets lp_wake_req=1, waits for pl_wake_ack=1
    //   De-assert: LP sets lp_wake_req=0, waits for pl_wake_ack=0
    //
    // Asserted from WAKE_ASSERT through ACTIVE and RETRAIN.
    // De-asserted on entry to DEACTIVATE/UNWAKE_WAIT, L1, LINKERROR,
    // and RESET.
    // ================================================================
    logic r_wake_req;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_wake_req <= 1'b0;
        end else begin
            case (w_nxt_st)
                ST_WAKE_ASSERT,
                ST_WAKE_WAIT_ACK,
                ST_REQ_ACTIVE,
                ST_ACTIVE,
                ST_RETRAIN:      r_wake_req <= 1'b1;
                default:         r_wake_req <= 1'b0;
            endcase
        end
    end

    assign O_LP_WAKE_REQ = r_wake_req;

    // ================================================================
    // Output: lp_clk_ack  (registered)
    //
    // UCIe 3.0 clock handshake:
    //   PL asserts pl_clk_req → LP responds with lp_clk_ack
    //   PL de-asserts pl_clk_req → LP de-asserts lp_clk_ack
    //
    // lp_clk_ack unconditionally tracks pl_clk_req regardless of
    // FSM state (state-gated suppression was removed).
    // ================================================================
    logic r_clk_ack;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_clk_ack <= 1'b0;
        end else begin
            r_clk_ack <= I_PL_CLK_REQ;
        end
    end

    assign O_LP_CLK_ACK = r_clk_ack;

    // ================================================================
    // Output: lp_rx_active_sts  (registered)
    //
    // UCIe 3.0 RX activation handshake:
    //   PL asserts pl_rx_active_req → LP responds with lp_rx_active_sts
    //   PL de-asserts pl_rx_active_req → LP de-asserts lp_rx_active_sts
    //
    // lp_rx_active_sts is asserted only when BOTH conditions are met:
    //   1. PL is requesting RX activation (I_PL_RX_ACTIVE_REQ = 1)
    //   2. FSM is in a state where the LP's RX path can be active
    //      (any state from WAIT_PRESENCE onward, except RESET and
    //       LINKERROR)
    // ================================================================
    logic r_rx_active_sts;
    logic w_rx_capable;

    always_comb begin
        case (w_nxt_st)
            ST_WAIT_PRESENCE,
            ST_WAKE_ASSERT,
            ST_WAKE_WAIT_ACK,
            ST_REQ_ACTIVE,
            ST_ACTIVE,
            ST_RETRAIN,
            ST_DEACTIVATE,
            ST_UNWAKE_WAIT,
            ST_L1,
            ST_L1_CLK_WAKE:  w_rx_capable = 1'b1;
            default:         w_rx_capable = 1'b0;
        endcase
    end

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_rx_active_sts <= 1'b0;
        end else begin
            r_rx_active_sts <= w_rx_capable & I_PL_RX_ACTIVE_REQ;
        end
    end

    assign O_LP_RX_ACTIVE_STS = r_rx_active_sts;

    // ================================================================
    // Output: AOU interface
    // ================================================================
    assign O_INT_FSM_IN_ACTIVE = (r_cur_st == ST_ACTIVE);

    // ================================================================
    // Status
    // ================================================================
    always_comb begin
        case (r_cur_st)
            ST_RESET:          O_FSM_STATE = FDI_ST_RESET;
            ST_WAIT_PRESENCE:  O_FSM_STATE = FDI_ST_RESET;
            ST_WAKE_ASSERT:    O_FSM_STATE = FDI_ST_RESET;
            ST_WAKE_WAIT_ACK:  O_FSM_STATE = FDI_ST_RESET;
            ST_REQ_ACTIVE:     O_FSM_STATE = FDI_ST_RESET;
            ST_ACTIVE:         O_FSM_STATE = FDI_ST_ACTIVE;
            ST_LINKERROR:      O_FSM_STATE = FDI_ST_LINKERROR;
            ST_RETRAIN:        O_FSM_STATE = FDI_ST_RETRAIN;
            ST_DEACTIVATE:     O_FSM_STATE = FDI_ST_ACTIVE;
            ST_UNWAKE_WAIT:    O_FSM_STATE = FDI_ST_RESET;
            ST_L1:             O_FSM_STATE = FDI_ST_L1;
            ST_L1_CLK_WAKE:    O_FSM_STATE = FDI_ST_L1;
            default:           O_FSM_STATE = FDI_ST_RESET;
        endcase
    end

    assign O_LINK_UP = (r_cur_st == ST_ACTIVE);

endmodule
