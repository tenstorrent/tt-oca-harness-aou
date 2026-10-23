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
//  Description: FDI bringup state machine per the UCIe specification.
//               Manages the four FDI handshake pairs:
//                 - lp_wake_req  / pl_wake_ack  (LP-initiated wake)
//                 - pl_clk_req   / lp_clk_ack   (PL-initiated clock request)
//                 - lp_state_req / pl_state_sts  (state negotiation)
//                 - pl_rx_active_req / lp_rx_active_sts (RX activation)
//               and drives lp_linkerror for an LP-requested LinkError.
//               Bridges to the AOU activation control via
//               O_INT_FSM_IN_ACTIVE and I_INT_ACTIVATE_START.
//
//               The controller brings the link up and follows the
//               Adapter afterwards. It never takes the link down except
//               for an error (lp_linkerror), and never restarts it: after
//               LinkError, LinkReset or Disabled it drives NOP, follows
//               pl_state_sts to Reset and waits for pl_inband_pres as
//               after a cold reset. Taking the link down for PM, LinkReset
//               or Disable, and training it again, is software's job on
//               the UCIe controller (or the remote die's).
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
    output logic        O_LP_LINKERROR,

    // ----------------------------------------------------------------
    // AOU Activation Control interface
    // ----------------------------------------------------------------
    output logic        O_INT_FSM_IN_ACTIVE,
    input  logic        I_AOU_ACTIVATE_ST_ENABLED,
    input  logic        I_AOU_REQ_LINKRESET,
    input  logic        I_INT_ACTIVATE_START,

    // ----------------------------------------------------------------
    // Software control
    // ----------------------------------------------------------------
    input  logic        I_SW_ACTIVATE_START,
    input  logic        I_SW_LINKERROR_INJECT,
    input  logic        I_SW_RESET,          // AOU_CON0.AOU_SW_RESET in effect

    // ----------------------------------------------------------------
    // Status outputs
    // ----------------------------------------------------------------
    output logic [3:0]  O_FSM_STATE,
    output logic        O_LINK_UP
);

    // ================================================================
    // UCIe FDI pl_state_sts encodings (r1.1 Table 8-1; same in r2.0 and
    // r3.0). Also used on O_FSM_STATE.
    // ================================================================
    localparam logic [3:0] FDI_ST_RESET        = 4'b0000;
    localparam logic [3:0] FDI_ST_ACTIVE       = 4'b0001;
    localparam logic [3:0] FDI_ST_ACTIVE_PMNAK = 4'b0011;
    localparam logic [3:0] FDI_ST_L1           = 4'b0100;
    localparam logic [3:0] FDI_ST_L2           = 4'b1000;
    localparam logic [3:0] FDI_ST_LINKRESET    = 4'b1001;
    localparam logic [3:0] FDI_ST_LINKERROR    = 4'b1010;
    localparam logic [3:0] FDI_ST_RETRAIN      = 4'b1011;
    localparam logic [3:0] FDI_ST_DISABLED     = 4'b1100;

    // ================================================================
    // UCIe FDI lp_state_req encodings. Only the values this controller
    // drives are defined: it never requests Retrain (not allowed outside
    // Raw Format, r1.1 8.3.3.4), L2, LinkReset or Disabled.
    // ================================================================
    localparam logic [3:0] FDI_REQ_NOP         = 4'b0000;
    localparam logic [3:0] FDI_REQ_ACTIVE      = 4'b0001;
    localparam logic [3:0] FDI_REQ_L1          = 4'b0100;

    // ================================================================
    // Internal FSM States (one-hot, 11 states)
    // ================================================================
    localparam logic [10:0] ST_RESET         = 11'b000_0000_0001;
    localparam logic [10:0] ST_WAIT_PRESENCE = 11'b000_0000_0010;
    localparam logic [10:0] ST_WAKE_ASSERT   = 11'b000_0000_0100;
    localparam logic [10:0] ST_WAKE_WAIT_ACK = 11'b000_0000_1000;
    localparam logic [10:0] ST_REQ_ACTIVE    = 11'b000_0001_0000;
    localparam logic [10:0] ST_ACTIVE        = 11'b000_0010_0000;
    localparam logic [10:0] ST_LINKERROR     = 11'b000_0100_0000;
    localparam logic [10:0] ST_RETRAIN       = 11'b000_1000_0000;
    localparam logic [10:0] ST_L1            = 11'b001_0000_0000;
    localparam logic [10:0] ST_L1_CLK_WAKE   = 11'b010_0000_0000;
    localparam logic [10:0] ST_LINKDOWN      = 11'b100_0000_0000;

    logic [10:0] r_cur_st;
    logic [10:0] w_nxt_st;

    // ================================================================
    // PL state decode
    //
    // Every value the FSM reacts to is compared in full, so a reserved
    // or unknown value never counts as another state. Active.PMNAK
    // (0011b) is not decoded: the Adapter reports it only to refuse a
    // PM request from the Protocol Layer, and this controller requests
    // L1 only after the Adapter has entered L1 itself, so it cannot
    // occur. Should it appear, it is ignored (no transition): in ACTIVE
    // the link stays reported up, as the Adapter is still in Active.
    // ================================================================
    logic w_pl_active;
    logic w_pl_reset;
    logic w_pl_linkerror;
    logic w_pl_retrain;
    logic w_pl_l1;
    logic w_pl_disabled;
    logic w_pl_linkdown;

    assign w_pl_active    = (I_PL_STATE_STS == FDI_ST_ACTIVE);
    assign w_pl_reset     = (I_PL_STATE_STS == FDI_ST_RESET);
    assign w_pl_linkerror = (I_PL_STATE_STS == FDI_ST_LINKERROR);
    assign w_pl_retrain   = (I_PL_STATE_STS == FDI_ST_RETRAIN);
    assign w_pl_l1        = (I_PL_STATE_STS == FDI_ST_L1);
    assign w_pl_disabled  = (I_PL_STATE_STS == FDI_ST_DISABLED);
    assign w_pl_linkdown  = (I_PL_STATE_STS == FDI_ST_LINKRESET) | w_pl_disabled;

    // ================================================================
    // Request aggregation
    // ================================================================
    logic w_activate_request;
    logic w_linkerror_request;

    assign w_activate_request  = I_SW_ACTIVATE_START | I_INT_ACTIVATE_START;
    assign w_linkerror_request = I_AOU_REQ_LINKRESET | I_SW_LINKERROR_INJECT;

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
    // down: LINKERROR does not leave for RESET, so a flit abandoned by
    // the LinkError can never be resumed against a fresh Adapter flit
    // boundary.
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
    //
    // In every state but LINKERROR a PL LinkError report goes to
    // LINKERROR, and in every state but LINKERROR and LINKDOWN a PL
    // LinkReset or Disabled report goes to LINKDOWN, ahead of the
    // state's own transitions.
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
            // RESET: Drive NOP. Wait for PL to report RESET and remote
            // die presence. After a link-down this is where the FSM
            // waits for software (or the remote die) to train the link
            // again; it gives no training trigger of its own.
            // ----------------------------------------------------------
            ST_RESET: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
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
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
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
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
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
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
                end else if (I_PL_WAKE_ACK) begin
                    w_nxt_st = ST_REQ_ACTIVE;
                end else if (!I_PL_INBAND_PRES && w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // REQ_ACTIVE: Wake handshake complete. Drive lp_state_req =
            // Active. Wait for PL to reach Active AND assert
            // pl_rx_active_req (PL's RX is ready). LP responds with
            // lp_rx_active_sts via the output logic below.
            // ----------------------------------------------------------
            ST_REQ_ACTIVE: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
                end else if (w_pl_active && I_PL_RX_ACTIVE_REQ) begin
                    w_nxt_st = ST_ACTIVE;
                end else if (!I_PL_INBAND_PRES && w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // ACTIVE: Link is up. FDI data path operational. An AOU
            // deactivation does not leave this state: the link stays
            // Active and the next AOU activation handshake runs on it.
            // Only an error (own request or PL report) or a PL-reported
            // state change leaves ACTIVE.
            // ----------------------------------------------------------
            ST_ACTIVE: begin
                if (w_pl_linkerror || w_linkerror_request) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
                end else if (w_pl_retrain) begin
                    w_nxt_st = ST_RETRAIN;
                end else if (w_pl_l1) begin
                    w_nxt_st = ST_L1;
                end else if (w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // LINKERROR: lp_linkerror on an own request until PL reports
            // LinkError, then NOP. The Adapter leaves LinkError for Reset
            // on its own internal request (software on the UCIe
            // controller); nothing is requested here. Leave for RESET
            // once PL reports Reset and software has applied
            // AOU_SW_RESET (in either order).
            // ----------------------------------------------------------
            ST_LINKERROR: begin
                if (w_pl_reset && r_sw_reset_seen) begin
                    w_nxt_st = ST_RESET;
                end
            end

            // ----------------------------------------------------------
            // RETRAIN: PL is retraining (Adapter-initiated). lp_wake_req
            // stays asserted; lp_state_req gives the NOP->Active exit
            // (see r_retrain_nop_sent). Wait for PL to report Active.
            // ----------------------------------------------------------
            ST_RETRAIN: begin
                if (w_pl_linkerror || w_linkerror_request) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
                end else if (w_pl_active) begin
                    w_nxt_st = ST_ACTIVE;
                end
            end

            // ----------------------------------------------------------
            // L1: Low-power state. lp_wake_req is de-asserted.
            // Wake on PL clock request or LP activation request.
            // ----------------------------------------------------------
            ST_L1: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
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
                end else if (w_pl_linkdown) begin
                    w_nxt_st = ST_LINKDOWN;
                end else begin
                    w_nxt_st = ST_WAKE_ASSERT;
                end
            end

            // ----------------------------------------------------------
            // LINKDOWN: PL reports LinkReset or Disabled (software on the
            // UCIe controller, or the remote die). Link Status is Down
            // (UCIe Table 8-2). Drive NOP, which LinkReset and Disabled
            // ignore (r1.1 Table 8-3), so the link stays down until the
            // Adapter leaves for Reset on its own internal request.
            // ----------------------------------------------------------
            ST_LINKDOWN: begin
                if (w_pl_linkerror) begin
                    w_nxt_st = ST_LINKERROR;
                end else if (w_pl_reset) begin
                    w_nxt_st = ST_RESET;
                end
            end

            default: begin
                w_nxt_st = ST_RESET;
            end
        endcase
    end

    // ================================================================
    // Retrain exit request
    //
    // UCIe r1.1 8.3.3.4: a Retrain entered from Active ends only after
    // a NOP->Active transition on lp_state_req. ST_RETRAIN drives NOP
    // for its first cycle, then Active.
    // ================================================================
    logic r_retrain_nop_sent;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_retrain_nop_sent <= 1'b0;
        end else begin
            r_retrain_nop_sent <= (r_cur_st == ST_RETRAIN);
        end
    end

    // ================================================================
    // Output: lp_state_req
    //
    // Active is requested only on the cold bringup path (REQ_ACTIVE,
    // ACTIVE) and for the Retrain exit. Every link-down state drives
    // NOP: restarting the link is software's job.
    // ================================================================
    always_comb begin
        case (r_cur_st)
            ST_RESET:          O_LP_STATE_REQ = FDI_REQ_NOP;
            ST_WAIT_PRESENCE:  O_LP_STATE_REQ = FDI_REQ_NOP;
            ST_WAKE_ASSERT:    O_LP_STATE_REQ = FDI_REQ_NOP;
            ST_WAKE_WAIT_ACK:  O_LP_STATE_REQ = FDI_REQ_NOP;
            ST_REQ_ACTIVE:     O_LP_STATE_REQ = FDI_REQ_ACTIVE;
            ST_ACTIVE:         O_LP_STATE_REQ = FDI_REQ_ACTIVE;
            ST_LINKERROR:      O_LP_STATE_REQ = FDI_REQ_NOP;
            ST_RETRAIN:        O_LP_STATE_REQ = r_retrain_nop_sent ? FDI_REQ_ACTIVE
                                                                    : FDI_REQ_NOP;
            ST_L1:             O_LP_STATE_REQ = FDI_REQ_L1;
            ST_L1_CLK_WAKE:    O_LP_STATE_REQ = FDI_REQ_L1;
            ST_LINKDOWN:       O_LP_STATE_REQ = FDI_REQ_NOP;
            default:           O_LP_STATE_REQ = FDI_REQ_NOP;
        endcase
    end

    // ================================================================
    // Output: lp_wake_req  (registered)
    //
    // UCIe wake handshake:
    //   Assert:   LP sets lp_wake_req=1, PL answers pl_wake_ack=1
    //   De-assert: LP sets lp_wake_req=0, PL answers pl_wake_ack=0
    //
    // Asserted from WAKE_ASSERT through ACTIVE and RETRAIN.
    // De-asserted on entry to L1, LINKERROR, LINKDOWN and RESET.
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
    // UCIe clock handshake:
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
    // UCIe RX activation handshake:
    //   PL asserts pl_rx_active_req → LP responds with lp_rx_active_sts
    //   PL de-asserts pl_rx_active_req → LP de-asserts lp_rx_active_sts
    //
    // lp_rx_active_sts rises only when BOTH conditions are met:
    //   1. PL is requesting RX activation (I_PL_RX_ACTIVE_REQ = 1)
    //   2. FSM is in a state where the LP's RX path can be active
    //      (any state from WAIT_PRESENCE onward, except RESET and
    //       LINKERROR)
    // Once set it falls only when pl_rx_active_req falls, whatever the
    // FSM state (UCIe r1.1 8.2.7: the status follows the request), so
    // a request that is still high when the FSM enters RESET or
    // LINKERROR keeps the status until the Adapter withdraws it.
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
            ST_L1,
            ST_L1_CLK_WAKE,
            ST_LINKDOWN:     w_rx_capable = 1'b1;
            default:         w_rx_capable = 1'b0;
        endcase
    end

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_rx_active_sts <= 1'b0;
        end else begin
            r_rx_active_sts <= (w_rx_capable | r_rx_active_sts) & I_PL_RX_ACTIVE_REQ;
        end
    end

    assign O_LP_RX_ACTIVE_STS = r_rx_active_sts;

    // ================================================================
    // Output: lp_linkerror  (registered)
    //
    // Set on entry to LINKERROR on the LP's own request (AOU LinkReset
    // request or SW inject), so the Adapter takes the link down. Held
    // until the PL reports LinkError (UCIe Table 8-2: the Adapter stays
    // in LinkError while lp_linkerror=1, so holding it longer would
    // block the exit to Reset) or the FSM leaves LINKERROR. 0 in every
    // other state.
    // ================================================================
    logic r_lp_linkerror;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_lp_linkerror <= 1'b0;
        end else if ((w_nxt_st != ST_LINKERROR) || w_pl_linkerror) begin
            r_lp_linkerror <= 1'b0;
        end else if (r_cur_st != ST_LINKERROR) begin
            r_lp_linkerror <= 1'b1;
        end
    end

    assign O_LP_LINKERROR = r_lp_linkerror;

    // ================================================================
    // Output: AOU interface  (registered)
    //
    // O_INT_FSM_IN_ACTIVE means "link established": 1 from the first
    // Active until the link is lost (LinkError, LinkReset, Disabled or a
    // Reset reported straight from Active). Retrain and L1 are
    // transparent to the AOU core, including the wake handshake that
    // ends an L1 (L1 -> WAKE_ASSERT -> WAKE_WAIT_ACK -> REQ_ACTIVE ->
    // ACTIVE, the same states the cold bring-up uses), so the only
    // falling edge is a link loss; AOU_ACTIVATION_CTRL raises
    // INT_FDI_LINK_DOWN on it. Set on entry to ACTIVE, cleared on entry
    // to LINKERROR, LINKDOWN or RESET, so it changes in the same cycle
    // as r_cur_st. This differs on purpose from O_LINK_UP below, which
    // is "in Active" only.
    // ================================================================
    logic r_link_established;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_link_established <= 1'b0;
        end else begin
            case (w_nxt_st)
                ST_ACTIVE:       r_link_established <= 1'b1;
                ST_RESET,
                ST_LINKERROR,
                ST_LINKDOWN:     r_link_established <= 1'b0;
                default:         r_link_established <= r_link_established;
            endcase
        end
    end

    assign O_INT_FSM_IN_ACTIVE = r_link_established;

    // ================================================================
    // Status (UCIe pl_state_sts encoding)
    //
    // r_pl_disabled: the last link-down state PL reported was Disabled,
    // so LINKDOWN reports LinkReset or Disabled as PL does.
    // ================================================================
    logic r_pl_disabled;

    always_ff @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_pl_disabled <= 1'b0;
        end else if (w_pl_linkdown) begin
            r_pl_disabled <= w_pl_disabled;
        end
    end

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
            ST_L1:             O_FSM_STATE = FDI_ST_L1;
            ST_L1_CLK_WAKE:    O_FSM_STATE = FDI_ST_L1;
            ST_LINKDOWN:       O_FSM_STATE = r_pl_disabled ? FDI_ST_DISABLED : FDI_ST_LINKRESET;
            default:           O_FSM_STATE = FDI_ST_RESET;
        endcase
    end

    // O_LINK_UP (the AOU_TOP.O_FDI_LINK_UP pin) means "FSM in Active": it
    // drops in Retrain and L1 as well. Combinational decode of r_cur_st,
    // narrower than O_INT_FSM_IN_ACTIVE above on purpose.
    assign O_LINK_UP = (r_cur_st == ST_ACTIVE);

endmodule
