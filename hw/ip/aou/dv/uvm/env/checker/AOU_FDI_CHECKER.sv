// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
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
//  Module     : AOU_FDI_CHECKER
//  Version    : 1.13
//  Date       : 26-10-20
//
// *****************************************************************************
//
//  Synthesizable AoU protocol checker for one single-PHY FDI link: the v0.7
//  wire format the design implements, judged by the v0.8 activation and credit
//  ordering rules. Section numbers are v0.8's unless marked v0.7; the wire
//  format's citations (aou_fdi_wire_pkg) are v0.7's.
//  Design rationale and the interface reference are in DESIGN.md.
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_FDI_CHECKER
// Both packages are the checker's own; nothing here comes from the design it
// judges. The first is the wire format as AoU v0.7 states it, the second the
// checker's code spaces, mirrored into Python by
// scripts/check_checker_code_space.py.
import aou_fdi_wire_pkg::*;
import aou_fdi_checker_pkg::*;
#(
    // See DESIGN.md "Parameters".

    // Width of the FDI data bus in bytes: 32, 64 or 128 (UCIe 3.0 10.2), the
    // three single-PHY configurations.
    parameter int FDI_IF_BYTES      = 32,

    parameter int FLIT_SEQ_WD       = 32,
    parameter int VIOL_CNT_WD       = 16,

    // Planes both dies drive (AoU v0.7 6.2 makes the count symmetric), in the
    // observed die's numbering. I_CFG_RP_DEST_RP says what the peer calls them.
    parameter int RP_COUNT          = 4,

    // The Flit Destination ID (v0.7 4.3.1) of the one bridge pair this instance
    // watches; every flit on either stream must carry it. The single-bridge
    // case the specification calls basic is 0.
    parameter int FDID              = 0,

    // Outstanding credits one shadow counter can hold. Not a protocol quantity:
    // the receiver advertises exactly the slots it has (6.4.3), so this is the
    // checker's tracking capacity, and exceeding it is reported.
    parameter int CRD_CAPACITY      = 2048,

    // Which rule groups this instance checks, as one of the named postures in
    // the checker's package. See DESIGN.md "Selectable check groups".
    parameter int CHK_PROFILE = CHK_PROFILE_FULL,

    // One enable per rule group, each defaulted from the profile. Set one
    // directly to depart from a profile in that group alone.
    parameter int STRUCT_EN    =  (CHK_PROFILE == CHK_PROFILE_LINK_MODEL)  ? 0 : 1,
    parameter int FRAMING_EN   = ((CHK_PROFILE == CHK_PROFILE_STRUCTURAL) ||
                                  (CHK_PROFILE == CHK_PROFILE_LINK_MODEL)) ? 0 : 1,
    parameter int ACT_SEQ_EN   = ((CHK_PROFILE == CHK_PROFILE_WELL_FORMED) ||
                                  (CHK_PROFILE == CHK_PROFILE_STRUCTURAL))  ? 0 : 1,
    parameter int MSG_ORDER_EN = ((CHK_PROFILE == CHK_PROFILE_WELL_FORMED) ||
                                  (CHK_PROFILE == CHK_PROFILE_STRUCTURAL))  ? 0 : 1,
    parameter int CREDIT_EN    = ((CHK_PROFILE == CHK_PROFILE_NO_CREDIT)   ||
                                  (CHK_PROFILE == CHK_PROFILE_WELL_FORMED) ||
                                  (CHK_PROFILE == CHK_PROFILE_STRUCTURAL))  ? 0 : 1,

    // Which of the link's two flit streams this instance observes.
    // See DESIGN.md "Direction observation".
    parameter int OBS_LP_EN = 1,
    parameter int OBS_PL_EN = 1,

    // Activation-status cross-check, one enable per die, both off by default.
    // See DESIGN.md "Optional activation-status cross-check".
    parameter int XCHK_LP_EN = 0,
    parameter int XCHK_PL_EN = 0,

    // TIGHTEN ONLY WITH EVIDENCE -- the argument is in the package.
    parameter int XCHK_SETTLE_CYCLES   = XCHK_SETTLE_CYCLES_DEFAULT,
    parameter int XCHK_CONVERGE_CYCLES = XCHK_CONVERGE_CYCLES_DEFAULT,

    // Derived FDI geometry. A latency-optimized flit is 256 bytes at every bus
    // width, so the beat count follows from the width.
    localparam int FDI_IF_WD        = FDI_IF_BYTES * 8,
    localparam int BEATS_PER_FLIT   = FLIT_WD / FDI_IF_WD,

    localparam int GRANULE_IDX_WD   = $clog2(GRANULE_CNT)
)
(
    // The interface is tabulated in DESIGN.md "Interface".
    input                                   I_CLK,
    input                                   I_RESETN,
    // Starts a new observed-link epoch without clearing captured findings.
    input                                   I_LINK_RESET,

    // Outbound (LP) flit stream, driven by the die under observation. A beat
    // counts only on a completed FDI transfer. FDI has no lp_flit_cancel.
    //
    // BOTH STREAMS KEEP THEIR PORTS WHEN UNOBSERVED, and are tied off at the
    // instance: OBS_LP_EN and OBS_PL_EN qualify the beat, not the interface.
    input                                   I_LP_VALID,
    input                                   I_LP_IRDY,
    input        [FDI_IF_WD-1:0]            I_LP_DATA,
    input                                   I_PL_TRDY,

    // Inbound (PL) flit stream, driven by the peer die through its adapter.
    // FDI gives the receiver no backpressure, so valid is the whole handshake;
    // pl_flit_cancel retracts the 128B half whose last beat transferred in the
    // previous cycle (UCIe 3.0 10.2).
    input                                   I_PL_VALID,
    input        [FDI_IF_WD-1:0]            I_PL_DATA,
    input                                   I_PL_FLIT_CANCEL,

    // Configuration, supplied and never inferred from observed traffic.
    // Entry p is the plane number a message from local plane p carries on the
    // wire, i.e. the peer's name for it.
    input        [3:0][1:0]                 I_CFG_RP_DEST_RP,

    // Cross-check inputs: each die's own view of where the link is.
    //
    // COMPARISON ONLY. Read by the comparator at the bottom of this file and
    // by nothing else. A checker that let the design's own status inform its
    // model would agree with the design by construction. Grep for these names
    // before adding a reader.
    input                                   I_LP_ACT_ST_DISABLED,
    input                                   I_LP_ACT_ST_ENABLED,
    input                                   I_PL_ACT_ST_DISABLED,
    input                                   I_PL_ACT_ST_ENABLED,

    // Violation reporting. Sticky vector, saturating count, one-cycle trigger
    // and a capture record frozen on the first violation.
    output logic [VIOL_CLASS_CNT-1:0]       O_VIOLATION,
    output logic                            O_VIOLATION_TRIGGER,
    output logic [VIOL_CNT_WD-1:0]          O_VIOLATION_CNT,

    output logic                            O_CAPTURE_VALID,
    output logic [VIOL_CODE_WD-1:0]         O_CAPTURE_CODE,
    // 0: outbound (LP) flit stream. 1: inbound (PL) flit stream.
    output logic                            O_CAPTURE_DIR,
    output logic [FLIT_SEQ_WD-1:0]          O_CAPTURE_FLIT_SEQ,
    output logic [GRANULE_IDX_WD-1:0]       O_CAPTURE_GRANULE_IDX,
    output logic [GRANULE_WD-1:0]           O_CAPTURE_GRANULE,

    // Which classes this instance is actually checking, in O_VIOLATION's bit
    // space. Constant: a class that never ran is otherwise indistinguishable
    // from one that passed.
    output logic [VIOL_CLASS_CNT-1:0]       O_CHECK_ENABLED,

    // Flits consumed on the wire, per direction. Cancelled and partial flits
    // do not count, nor do the adapter's NOP flits on the inbound stream.
    output logic [FLIT_SEQ_WD-1:0]          O_LP_FLIT_SEQ,
    output logic [FLIT_SEQ_WD-1:0]          O_PL_FLIT_SEQ,

    // Cross-check reporting: the same shape as the protocol surface and none
    // of the same registers. See DESIGN.md "Cross-check reporting".
    output logic [XVIOL_CLASS_CNT-1:0]      O_XCHK_VIOLATION,
    output logic                            O_XCHK_TRIGGER,
    output logic [VIOL_CNT_WD-1:0]          O_XCHK_CNT,

    output logic                            O_XCHK_CAPTURE_VALID,
    output logic [XVIOL_CODE_WD-1:0]        O_XCHK_CAPTURE_CODE,
    // 0: the die under observation. 1: its peer.
    output logic                            O_XCHK_CAPTURE_DIE,
    // The two views at the moment of the finding, each as {enabled, disabled}.
    output logic [1:0]                      O_XCHK_CAPTURE_CHK_ST,
    output logic [1:0]                      O_XCHK_CAPTURE_OBS_ST,
    output logic [FLIT_SEQ_WD-1:0]          O_XCHK_CAPTURE_FLIT_SEQ,

    // Bit d: a settled comparison has actually been made for die d.
    output logic [1:0]                      O_XCHK_COMPARED,

    // Clears the error status only, in both domains. See DESIGN.md "Clearing".
    input                                   I_ERR_CLEAR
);

// -----------------------------------------------------------------------------
// Elaboration-time configuration guards.
// See DESIGN.md "Elaboration-time configuration guards".
// -----------------------------------------------------------------------------
// The three widths give 8, 4 and 2 beats per flit: a power of two, at least
// two, so a 128B half -- the unit of cancellation -- is a whole number of beats.
if ((FDI_IF_BYTES != 32) && (FDI_IF_BYTES != 64) &&
    (FDI_IF_BYTES != 128)) begin : gen_unsupported_fdi_if_bytes
    $fatal(1, "AOU_FDI_CHECKER: unsupported FDI_IF_BYTES=%0d (32, 64 or 128)", FDI_IF_BYTES);
end

`ifdef TWO_PHY
$fatal(1, "AOU_FDI_CHECKER: TWO_PHY is not supported (observes one single-PHY link)");
`endif

if ((RP_COUNT < 1) || (RP_COUNT > 4)) begin : gen_rp_count_out_of_range
    $fatal(1, "AOU_FDI_CHECKER: RP_COUNT=%0d; the protocol's plane field is two bits, so 1..4",
           RP_COUNT);
end

if ((FDID < 0) || (FDID > 3)) begin : gen_fdid_out_of_range
    $fatal(1, "AOU_FDI_CHECKER: FDID=%0d; the protocol's FDId field is two bits, so 0..3", FDID);
end

if ((FLIT_SEQ_WD < 1) || (VIOL_CNT_WD < 1)) begin : gen_width_too_small
    $fatal(1, "AOU_FDI_CHECKER: FLIT_SEQ_WD and VIOL_CNT_WD must be at least 1");
end

if ((CHK_PROFILE != CHK_PROFILE_FULL) &&
    (CHK_PROFILE != CHK_PROFILE_NO_CREDIT) &&
    (CHK_PROFILE != CHK_PROFILE_WELL_FORMED) &&
    (CHK_PROFILE != CHK_PROFILE_STRUCTURAL) &&
    (CHK_PROFILE != CHK_PROFILE_LINK_MODEL)) begin : gen_unknown_chk_profile
    $fatal(1, "AOU_FDI_CHECKER: CHK_PROFILE=%0d is not a posture in aou_fdi_checker_pkg",
           CHK_PROFILE);
end

// Any bit above bit 0 set in any enable, including a sign bit.
if (((STRUCT_EN | FRAMING_EN | ACT_SEQ_EN | MSG_ORDER_EN | CREDIT_EN |
      OBS_LP_EN | OBS_PL_EN | XCHK_LP_EN | XCHK_PL_EN) >> 1) != 0) begin : gen_enable_not_boolean
    $fatal(1, "AOU_FDI_CHECKER: an enable parameter is not 0 or 1 (*_EN, OBS_*_EN, XCHK_*_EN)");
end

// A class in no group could never be enabled and would never be reported.
if (CHK_CLASSES_ALL != ((1 << VIOL_CLASS_CNT) - 1)) begin : gen_class_in_no_group
    $fatal(1, "AOU_FDI_CHECKER: the rule groups cover 'h%0h, not all %0d violation classes",
           CHK_CLASSES_ALL, VIOL_CLASS_CNT);
end

if ((CHK_CLASSES_STRUCT + CHK_CLASSES_FRAMING + CHK_CLASSES_ACT_SEQ +
     CHK_CLASSES_MSG_ORDER + CHK_CLASSES_CREDIT) != CHK_CLASSES_ALL) begin : gen_class_in_two_groups
    $fatal(1, "AOU_FDI_CHECKER: a violation class belongs to more than one rule group");
end

// An instance watching neither stream, or running no rule group, would report
// a clean link whatever crossed it.
if ((OBS_LP_EN == 0) && (OBS_PL_EN == 0)) begin : gen_no_stream_observed
    $fatal(1, "AOU_FDI_CHECKER: neither flit stream is observed");
end

// The rules one stream cannot support: an acknowledge answers a request that
// crossed the other way, and credits travel against the traffic they fund.
// Activation sequencing, message ordering, credit accounting and the
// cross-check need both streams; CHK_PROFILE_WELL_FORMED and
// CHK_PROFILE_STRUCTURAL are the postures one stream can run.
if (((OBS_LP_EN == 0) || (OBS_PL_EN == 0)) &&
    ((ACT_SEQ_EN != 0) || (MSG_ORDER_EN != 0) || (CREDIT_EN != 0) ||
     (XCHK_LP_EN != 0) || (XCHK_PL_EN != 0))) begin : gen_one_stream_cannot_check
    $fatal(1,
           "AOU_FDI_CHECKER: one stream (OBS_LP_EN=%0d OBS_PL_EN=%0d) cannot run two-ended groups",
           OBS_LP_EN, OBS_PL_EN);
end

if ((XCHK_SETTLE_CYCLES < 1) || (XCHK_CONVERGE_CYCLES < 1)) begin : gen_xchk_window_too_small
    $fatal(1, "AOU_FDI_CHECKER: XCHK_SETTLE_CYCLES and XCHK_CONVERGE_CYCLES must be at least 1");
end

// -----------------------------------------------------------------------------
// Selectable check groups.
// See DESIGN.md "Selectable check groups".
// -----------------------------------------------------------------------------
// Prerequisites are derived so an enabled rule cannot omit one. Report enables
// do not suppress legality or framing terms used downstream.
localparam int ACT_MODEL_EN = ((ACT_SEQ_EN   != 0) ||
                               (MSG_ORDER_EN != 0) ||
                               (CREDIT_EN    != 0) ||
                               (XCHK_LP_EN   != 0) ||
                               (XCHK_PL_EN   != 0)) ? 1 : 0;

localparam int FRAMING_LOGIC_EN = ((FRAMING_EN   != 0) ||
                                   (ACT_MODEL_EN != 0) ||
                                   (CREDIT_EN    != 0)) ? 1 : 0;

localparam int CHK_CLASSES_ON = ((STRUCT_EN    != 0) ? CHK_CLASSES_STRUCT    : 0) |
                                ((FRAMING_EN   != 0) ? CHK_CLASSES_FRAMING   : 0) |
                                ((ACT_SEQ_EN   != 0) ? CHK_CLASSES_ACT_SEQ   : 0) |
                                ((MSG_ORDER_EN != 0) ? CHK_CLASSES_MSG_ORDER : 0) |
                                ((CREDIT_EN    != 0) ? CHK_CLASSES_CREDIT    : 0);

if (CHK_CLASSES_ON == 0) begin : gen_no_rule_group_enabled
    $fatal(1, "AOU_FDI_CHECKER: every rule group is disabled");
end

logic                       w_crd_en;
logic                       w_act_model_en;
logic                       w_framing_logic_en;
// The credit-grant hold-over serves the structural rules and the credit model.
logic                       w_grant_logic_en;
logic [VIOL_CLASS_CNT-1:0]  w_chk_class_en;

assign w_crd_en           = (CREDIT_EN != 0);
assign w_act_model_en     = (ACT_MODEL_EN != 0);
assign w_framing_logic_en = (FRAMING_LOGIC_EN != 0);
assign w_grant_logic_en   = (STRUCT_EN != 0) || (CREDIT_EN != 0);
assign w_chk_class_en     = VIOL_CLASS_CNT'(CHK_CLASSES_ON);

// -----------------------------------------------------------------------------
// Direction observation.
// See DESIGN.md "Direction observation".
// -----------------------------------------------------------------------------
localparam int DIR_CNT      = 2;
localparam int DIR_LP       = 0;    // outbound, driven by the die under observation
localparam int DIR_PL       = 1;    // inbound, driven by its peer

logic [DIR_CNT-1:0]                 w_obs_en;

assign w_obs_en[DIR_LP] = (OBS_LP_EN != 0);
assign w_obs_en[DIR_PL] = (OBS_PL_EN != 0);

// -----------------------------------------------------------------------------
// Flit reconstruction.
// See DESIGN.md "Flit reconstruction".
// -----------------------------------------------------------------------------
localparam int BEAT_IDX_WD  = $clog2(BEATS_PER_FLIT);
localparam int LAST_BEAT    = BEATS_PER_FLIT - 1;
localparam int HALF_BEATS   = BEATS_PER_FLIT / 2;

// The outbound stream needs the full handshake -- VALID and IRDY together with
// the receiver's TRDY. Sampling on VALID alone shifts every following beat by
// one wherever backpressure occurs. Only the inbound stream has a cancel.
logic [DIR_CNT-1:0]                 w_beat_xfer;
logic [DIR_CNT-1:0][FDI_IF_WD-1:0]  w_beat_data;
logic [DIR_CNT-1:0]                 w_flit_cancel;

assign w_beat_xfer[DIR_LP]   = w_obs_en[DIR_LP] & I_LP_VALID & I_LP_IRDY & I_PL_TRDY;
assign w_beat_data[DIR_LP]   = I_LP_DATA;
assign w_flit_cancel[DIR_LP] = 1'b0;

assign w_beat_xfer[DIR_PL]   = w_obs_en[DIR_PL] & I_PL_VALID;
assign w_beat_data[DIR_PL]   = I_PL_DATA;
assign w_flit_cancel[DIR_PL] = w_obs_en[DIR_PL] & I_PL_FLIT_CANCEL;

// Flit buffer. The protocol header is not complete until byte 193 of 256, so a
// flit is buffered and checked once complete. Beat zero occupies the low-order
// bits, so flit byte i is bits [i*8 +: 8]. Unpacked over direction so that an
// unobserved stream's buffer can be dropped.
logic [BEATS_PER_FLIT-1:0][FDI_IF_WD-1:0] r_flit_data [DIR_CNT];
logic [DIR_CNT-1:0][BEAT_IDX_WD-1:0]       r_beat_idx;
logic [DIR_CNT-1:0][FLIT_SEQ_WD-1:0]       r_flit_seq;

// HALVES, NOT FLITS, ARE THE UNIT OF CANCELLATION. UCIe 3.0 10.2: for
// latency-optimized flits pl_flit_cancel is asserted exactly one cycle after
// the last transfer of a 128B half, and that half must not be consumed; the
// adapter later replays it in order (Figures 10-15 to 10-17). So each half is
// written provisionally into its slot, r_half_done marks the cycle in which a
// cancel may retract it, a cancel rewinds the beat index to that half's start
// -- a beat arriving in the same cycle is the first of whatever the adapter
// sends next -- and a commit of the second half consumes the flit only if the
// first half was committed before it (r_half0_ok).
logic [DIR_CNT-1:0][1:0]                r_half_done;
logic [DIR_CNT-1:0]                     r_half0_ok;

logic [DIR_CNT-1:0]                     w_rewind;
logic [DIR_CNT-1:0][BEAT_IDX_WD-1:0]    w_beat_wr_idx;
logic [DIR_CNT-1:0][BEAT_IDX_WD-1:0]    w_beat_idx_nxt;
logic [DIR_CNT-1:0][1:0]                w_half_done_nxt;
logic [DIR_CNT-1:0]                     w_half0_commit;
// A flit completed on the wire, and the same flit less the adapter's NOPs: a
// completed flit is consumed by the reconstruction, a consumed flit is the one
// the check stage runs on this cycle.
logic [DIR_CNT-1:0]                     w_flit_done;
logic [DIR_CNT-1:0]                     w_flit_nop;
logic [DIR_CNT-1:0]                     w_chk_go;

// A D2D Adapter NOP (UCIe 3.0 Table 3-4) reaching the inbound stream
// uncancelled is the protocol layer's to discard: it is neither judged nor
// counted. The die under observation must never send one, so the outbound
// stream is judged as it comes.
assign w_flit_nop[DIR_LP] = 1'b0;
assign w_flit_nop[DIR_PL] =
    (r_flit_data[DIR_PL][0][FLIT_HDR_BYTE*8 + FLIT_PID_LSB +: FLIT_PID_WD] == FLIT_PID_NOP);

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_rewind[d]         = w_flit_cancel[d] & (|r_half_done[d]);
        w_beat_wr_idx[d]    = w_rewind[d] ? (r_half_done[d][1] ? BEAT_IDX_WD'(HALF_BEATS) : '0)
                                          : r_beat_idx[d];
        w_beat_idx_nxt[d]   = w_beat_xfer[d] ? w_beat_wr_idx[d] + BEAT_IDX_WD'(1)
                                             : w_beat_wr_idx[d];
        w_half_done_nxt[d]  = {w_beat_xfer[d] & (w_beat_wr_idx[d] == BEAT_IDX_WD'(LAST_BEAT)),
                               w_beat_xfer[d] & (w_beat_wr_idx[d] == BEAT_IDX_WD'(HALF_BEATS - 1))};

        w_half0_commit[d]   = r_half_done[d][0] & ~w_flit_cancel[d];
        w_flit_done[d]      = r_half_done[d][1] & ~w_flit_cancel[d] & r_half0_ok[d];
        w_chk_go[d]         = w_flit_done[d] & ~w_flit_nop[d];
    end
end

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            r_flit_data[d] <= '0;
        end
        r_beat_idx  <= '0;
        r_half_done <= '0;
        r_half0_ok  <= '0;
        r_flit_seq  <= '0;
    end else if (I_LINK_RESET) begin
        // The buffer itself is left alone: nothing reads it before every beat
        // has been rewritten, and a synchronous clear would be a mux leg on
        // each of its four thousand flops.
        r_beat_idx  <= '0;
        r_half_done <= '0;
        r_half0_ok  <= '0;
    end else begin
        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            r_beat_idx[d]  <= w_beat_idx_nxt[d];
            r_half_done[d] <= w_half_done_nxt[d];

            if (w_beat_xfer[d]) begin
                r_flit_data[d][w_beat_wr_idx[d]] <= w_beat_data[d];
            end

            if (w_flit_done[d]) begin
                r_half0_ok[d] <= 1'b0;
            end else if (w_half0_commit[d]) begin
                r_half0_ok[d] <= 1'b1;
            end

            if (w_chk_go[d]) begin
                r_flit_seq[d] <= r_flit_seq[d] + FLIT_SEQ_WD'(1);
            end
        end
    end
end

// -----------------------------------------------------------------------------
// Flit field extraction.
//
// A flit is four 64-byte quarters, each a two-byte half-header, twelve
// five-byte granules and a second two-byte half-header (AoU v0.7 Figure 4), so
// granule g lives at flit byte 2 + 64*(g/12) + 5*(g%12). MsgStart's 48 bits
// come from header bytes 62-65 and 190-193 (Figure 5); MsgCredit from bytes
// 128-129; FDId is the low two bits of byte 62.
// See DESIGN.md "Flit field extraction".
// -----------------------------------------------------------------------------
// Every position below is aou_fdi_wire_pkg's, from Figures 4, 5, 19 and 20.

// The buffer flattened, so flit byte i is bits [i*8 +: 8].
logic [DIR_CNT-1:0][FLIT_WD-1:0]                        w_chk_flit;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                    w_chk_msg_start;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][GRANULE_WD-1:0]    w_chk_granule;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][MSGTYPE_WD-1:0]    w_chk_msgtype;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][MISCOP_WD-1:0]     w_chk_miscop;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][DLENGTH_WD-1:0]    w_chk_dlength;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][ACTOP_WD-1:0]      w_chk_actop;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][RP_WD-1:0]         w_chk_rp;
logic [DIR_CNT-1:0][MSG_CREDIT_WD-1:0]                  w_chk_msg_credit;
logic [DIR_CNT-1:0][FDID_WD-1:0]                        w_chk_fdid;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_chk_flit[d] = r_flit_data[d];

        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_chk_granule[d][g] = w_chk_flit[d][8 * granule_byte(g) +: GRANULE_WD];

            w_chk_msgtype[d][g] = w_chk_granule[d][g][MSGTYPE_LSB +: MSGTYPE_WD];
            w_chk_miscop[d][g]  = w_chk_granule[d][g][MISCOP_LSB  +: MISCOP_WD];
            w_chk_dlength[d][g] = w_chk_granule[d][g][DLENGTH_LSB +: DLENGTH_WD];
            w_chk_actop[d][g]   = actop_of(w_chk_granule[d][g]);
            w_chk_rp[d][g]      = w_chk_granule[d][g][RP_LSB +: RP_WD];
        end

        w_chk_msg_start[d]  = msg_start_of(w_chk_flit[d]);
        w_chk_msg_credit[d] = w_chk_flit[d][MSG_CREDIT_BYTE*8 +: MSG_CREDIT_WD];
        w_chk_fdid[d]       = w_chk_flit[d][FDID_BYTE*8 +: FDID_WD];
    end
end

// -----------------------------------------------------------------------------
// Structural well-formedness rules.
//
// The legal encodings are aou_fdi_wire_pkg's, written from AoU v0.7 Tables 1,
// 15 and 27 and deliberately not shared with AOU_ACTIVATION_CTRL, which has a
// table of its own for the same encodings.
// See DESIGN.md "Structural well-formedness rules".
// -----------------------------------------------------------------------------
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_msgtype_legal;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_miscop_legal;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_actop_legal;

logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_starts_misc;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_starts_activation;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_starts_crdtgrant;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_starts_data;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_starts_credited;

// Reserved-field contents, evaluated for every granule and qualified
// afterwards. PROPERTYREQ is only meaningful on ActivateReq and "must be 0b0
// for other messages" (v0.7 Table 26), so it reads as reserved elsewhere. The
// credited messages' RsvdZero is judged in their first granule only (Tables
// 2, 3, 10-13); WriteData carries none there.
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_act_rsvd_nonzero;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_crdtgrant_rsvd_nonzero;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_msg_rsvd_nonzero;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_msgtype_legal[d][g] = (w_chk_msgtype[d][g] == MSG_MISC     ) |
                                    (w_chk_msgtype[d][g] == MSG_WR_REQ   ) |
                                    (w_chk_msgtype[d][g] == MSG_RD_REQ   ) |
                                    (w_chk_msgtype[d][g] == MSG_WR_DATA  ) |
                                    (w_chk_msgtype[d][g] == MSG_WRF_DATA ) |
                                    (w_chk_msgtype[d][g] == MSG_RD_DATA  ) |
                                    (w_chk_msgtype[d][g] == MSG_WR_RESP  );

            w_miscop_legal[d][g] = (w_chk_miscop[d][g] == MISCOP_ACTIVATION) |
                                   (w_chk_miscop[d][g] == MISCOP_CRDTGRANT );

            w_actop_legal[d][g] = (w_chk_actop[d][g] == ACTOP_ACTIVATE_REQ  ) |
                                  (w_chk_actop[d][g] == ACTOP_ACTIVATE_ACK  ) |
                                  (w_chk_actop[d][g] == ACTOP_DEACTIVATE_REQ) |
                                  (w_chk_actop[d][g] == ACTOP_DEACTIVATE_ACK);

            w_starts_misc[d][g]       = w_chk_msg_start[d][g] &
                                        (w_chk_msgtype[d][g] == MSG_MISC);
            w_starts_activation[d][g] = w_starts_misc[d][g] &
                                        (w_chk_miscop[d][g] == MISCOP_ACTIVATION);
            w_starts_crdtgrant[d][g]  = w_starts_misc[d][g] &
                                        (w_chk_miscop[d][g] == MISCOP_CRDTGRANT);

            w_starts_data[d][g] = w_chk_msg_start[d][g] &
                                  ((w_chk_msgtype[d][g] == MSG_WR_DATA ) |
                                   (w_chk_msgtype[d][g] == MSG_WRF_DATA) |
                                   (w_chk_msgtype[d][g] == MSG_RD_DATA ));

            w_starts_credited[d][g] = w_chk_msg_start[d][g] & w_msgtype_legal[d][g] &
                                      (w_chk_msgtype[d][g] != MSG_MISC);

            w_act_rsvd_nonzero[d][g] =
                (|(w_chk_granule[d][g] & ACT_RSVD_MASK)) |
                (w_chk_granule[d][g][PROPREQ_BIT] &
                 (w_chk_actop[d][g] != ACTOP_ACTIVATE_REQ));

            w_crdtgrant_rsvd_nonzero[d][g] = |(w_chk_granule[d][g] & CG_RSVD_G1_MASK);

            case (w_chk_msgtype[d][g])
                MSG_WR_REQ,
                MSG_RD_REQ:  w_msg_rsvd_nonzero[d][g] = |(w_chk_granule[d][g] & REQ_RSVD_MASK);
                MSG_WR_RESP: w_msg_rsvd_nonzero[d][g] = |(w_chk_granule[d][g] & B_RSVD_MASK);
                MSG_RD_DATA: w_msg_rsvd_nonzero[d][g] = |(w_chk_granule[d][g] & R_RSVD_MASK);
                default:     w_msg_rsvd_nonzero[d][g] = 1'b0;
            endcase
        end
    end
end

// -----------------------------------------------------------------------------
// Message lengths, from aou_fdi_wire_pkg (v0.7 Tables 2-13, 19, 26).
// See DESIGN.md "Message lengths".
// -----------------------------------------------------------------------------
localparam int MSG_G_WD = $clog2(MAX_MSG_G + 1);

// One level of carry is only enough because no message is longer than a flit.
if (MAX_MSG_G > GRANULE_CNT) begin : gen_message_longer_than_flit
    $fatal(1, "AOU_FDI_CHECKER: MAX_MSG_G=%0d exceeds the granules in a flit", MAX_MSG_G);
end

// -----------------------------------------------------------------------------
// Message-start consistency: a granule claimed as the continuation of one
// message must not itself begin another (v0.7 4.4).
// See DESIGN.md "Message-start consistency".
// -----------------------------------------------------------------------------
// A message spans at most one flit boundary, so one flit of carry is enough.
localparam int CARRY_WD = MAX_MSG_G - 1;
localparam int CLAIM_WD = GRANULE_CNT + CARRY_WD;

// Whether a message-start granule begins a message of determinable length, and
// what that length is. Lengths follow the Base Profile: PROFEXTLEN is ignored
// (v0.7 5.8), so every message has the fixed length of its type.
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                w_msg_claims;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][MSG_G_WD-1:0]  w_msg_len;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_msg_claims[d][g] = w_chk_msg_start[d][g];
            w_msg_len[d][g]    = MSG_G_WD'(1);

            case (w_chk_msgtype[d][g])
                MSG_MISC: begin
                    case (w_chk_miscop[d][g])
                        MISCOP_ACTIVATION:
                            w_msg_len[d][g] = MSG_G_WD'(MISC_ACT_G);
                        MISCOP_CRDTGRANT:
                            w_msg_len[d][g] = MSG_G_WD'(MISC_CG_G);
                        default:
                            w_msg_claims[d][g] = 1'b0;
                    endcase
                end

                MSG_WR_REQ:  w_msg_len[d][g] = MSG_G_WD'(AW_G);
                MSG_RD_REQ:  w_msg_len[d][g] = MSG_G_WD'(AR_G);
                MSG_WR_RESP: w_msg_len[d][g] = MSG_G_WD'(B_G);

                MSG_WR_DATA: begin
                    case (w_chk_dlength[d][g])
                        DLENGTH_256B:  w_msg_len[d][g] = MSG_G_WD'(W256B_G);
                        DLENGTH_512B:  w_msg_len[d][g] = MSG_G_WD'(W512B_G);
                        DLENGTH_1024B: w_msg_len[d][g] = MSG_G_WD'(W1024B_G);
                        default:       w_msg_claims[d][g] = 1'b0;
                    endcase
                end

                MSG_WRF_DATA: begin
                    case (w_chk_dlength[d][g])
                        DLENGTH_256B:  w_msg_len[d][g] = MSG_G_WD'(WF256B_G);
                        DLENGTH_512B:  w_msg_len[d][g] = MSG_G_WD'(WF512B_G);
                        DLENGTH_1024B: w_msg_len[d][g] = MSG_G_WD'(WF1024B_G);
                        default:       w_msg_claims[d][g] = 1'b0;
                    endcase
                end

                MSG_RD_DATA: begin
                    case (w_chk_dlength[d][g])
                        DLENGTH_256B:  w_msg_len[d][g] = MSG_G_WD'(R256B_G);
                        DLENGTH_512B:  w_msg_len[d][g] = MSG_G_WD'(R512B_G);
                        DLENGTH_1024B: w_msg_len[d][g] = MSG_G_WD'(R1024B_G);
                        default:       w_msg_claims[d][g] = 1'b0;
                    endcase
                end

                default: w_msg_claims[d][g] = 1'b0;
            endcase
        end
    end
end

// Granules claimed as continuation by some message in this flit. Bits at and
// above GRANULE_CNT are the claims that ran off the end of it.
logic [DIR_CNT-1:0][CLAIM_WD-1:0]       w_claimed;

// Carry from the previous flit. Deliberately not cleared by I_ERR_CLEAR.
logic [DIR_CNT-1:0][CARRY_WD-1:0]       r_carry;

logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_msgstart_forbidden;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_claimed[d] = '0;
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            for (int unsigned c = 1; c < MAX_MSG_G; c++) begin
                if (w_msg_claims[d][g] && (MSG_G_WD'(c) < w_msg_len[d][g])) begin
                    w_claimed[d][g + c] = 1'b1;
                end
            end
        end

        w_msgstart_forbidden[d] = w_claimed[d][GRANULE_CNT-1:0] |
                                  GRANULE_CNT'(r_carry[d]);
    end
end

// The derived framing enable is the load enable: with it constant zero this
// register is only ever reset, which lets the tools drop it and the claim walk
// with it. FRAMING_EN suppresses the framing *report*; this decides whether
// the logic exists.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_carry <= '0;
    end else if (I_LINK_RESET) begin
        r_carry <= '0;
    end else begin
        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            if (w_framing_logic_en & w_chk_go[d]) begin
                r_carry[d] <= w_claimed[d][CLAIM_WD-1:GRANULE_CNT];
            end
        end
    end
end

// -----------------------------------------------------------------------------
// Activation message placement (v0.7 4.4): at most one "MiscU" message per
// flit, and it is the first message, at granule 0. v0.7 never defines MiscU and
// uses the name only for the Activation messages (8.3.4); v0.8 4.4 says
// outright that the rule is for the Activation MiscOp. READ AS ACTIVATION-ONLY:
// a credit grant is packed like any other message and may start anywhere. Any
// Activation start elsewhere breaks one of the two, so one term covers both,
// and it is what makes 9.2's "ActivateReq and ActivateAck in two different
// flits" hold. See DESIGN.md "Activation message placement".
// -----------------------------------------------------------------------------
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_misc_misplaced;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_misc_misplaced[d][g] = w_starts_activation[d][g] & (g != 0);
        end
    end
end

// -----------------------------------------------------------------------------
// Resource-plane range (5.2.2, 6.2, 6.4.1, 6.4.2).
//
// A credited message names its destination plane in the receiver's numbering;
// an advertisement names the advertising die's own plane. Wire plane q is one
// of the observed die's when q < RP_COUNT, and one of the peer's when some
// local plane maps onto it. A message naming any other plane is reported here
// and is not spent or counted anywhere else, rather than silently matching
// no counter.
// -----------------------------------------------------------------------------
logic [RP_WIRE_CNT-1:0]                 w_rp_own_ok;
logic [RP_WIRE_CNT-1:0]                 w_rp_peer_ok;
// Per direction: the planes a credited message on it may name, and the planes
// an advertisement on it may name.
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0]    w_msg_rp_ok;
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0]    w_adv_rp_ok;
// Two local planes mapped onto one wire plane. Planes are independently flow
// controlled (3, 6.2), which only a one-to-one map preserves; with this set,
// every consumed flit is reported until the configuration is fixed.
logic                                   w_rp_map_bad;

always_comb begin
    for (int unsigned q = 0; q < RP_WIRE_CNT; q++) begin
        w_rp_own_ok[q]  = (q < RP_COUNT);
        w_rp_peer_ok[q] = 1'b0;
        for (int unsigned p = 0; p < RP_COUNT; p++) begin
            if (I_CFG_RP_DEST_RP[p] == RP_WD'(q)) begin
                w_rp_peer_ok[q] = 1'b1;
            end
        end
    end

    w_rp_map_bad = 1'b0;
    for (int unsigned p = 1; p < RP_COUNT; p++) begin
        for (int unsigned o = 0; o < p; o++) begin
            if (I_CFG_RP_DEST_RP[p] == I_CFG_RP_DEST_RP[o]) begin
                w_rp_map_bad = 1'b1;
            end
        end
    end

    w_msg_rp_ok[DIR_LP] = w_rp_peer_ok;
    w_msg_rp_ok[DIR_PL] = w_rp_own_ok;
    w_adv_rp_ok[DIR_LP] = w_rp_own_ok;
    w_adv_rp_ok[DIR_PL] = w_rp_peer_ok;
end

// -----------------------------------------------------------------------------
// Activation handshake model.
//
// Deliberately independent of AOU_ACTIVATION_CTRL; written from 8.2-8.4.
// A die is named by the stream it drives, so a die index is a direction index.
// -----------------------------------------------------------------------------
localparam int DIE_LP = DIR_LP;
localparam int DIE_PL = DIR_PL;

// The four activation states, in the checker's own encoding -- deliberately
// NOT AOU_ACTIVATION_CTRL's one-hot values.
localparam int ACT_ST_WD = 2;

localparam logic [ACT_ST_WD-1:0] ACT_ST_DISABLED   = 2'd0;
localparam logic [ACT_ST_WD-1:0] ACT_ST_ACTIVATE   = 2'd1;
localparam logic [ACT_ST_WD-1:0] ACT_ST_ENABLED    = 2'd2;
localparam logic [ACT_ST_WD-1:0] ACT_ST_DEACTIVATE = 2'd3;

// Activation messages observed so far, per direction of travel. Die d's own
// messages are on stream d; the ones it received are on stream 1-d.
logic [DIR_CNT-1:0]                     r_act_req;
logic [DIR_CNT-1:0]                     r_act_ack;
logic [DIR_CNT-1:0]                     r_deact_req;
logic [DIR_CNT-1:0]                     r_deact_ack;
// An ActivateAck in a committed first half (UCIe 3.0 10.2): the receiving die
// may act on it before the second half arrives. Opens the consume window the
// same way a consumed ActivateAck flit does, nothing else.
logic [DIR_CNT-1:0]                     r_act_ack_half;

// ONE STATE FOR THE LINK, NOT ONE PER DIE. 8.2's conditions -- ENABLED once an
// ActivateAck has been sent and received, DISABLED once a DeactivateAck has
// -- name the same four events from either die's side, so the two dies' states
// cannot differ on the wire and are held once, combinationally off the events.
// ENABLED is written with the request terms, which the answer rule already
// implies, so that it says the specification's condition.
logic                                   w_link_activated;
logic                                   w_link_activating;
logic                                   w_link_tearing_down;
logic [ACT_ST_WD-1:0]                   w_link_state;

always_comb begin
    w_link_activated    = (&r_act_req) & (&r_act_ack);
    w_link_activating   = ((|r_act_req) | (|r_act_ack)) & ~w_link_activated;
    w_link_tearing_down = (|r_deact_req) | (|r_deact_ack);

    if (w_link_activated) begin
        w_link_state = w_link_tearing_down ? ACT_ST_DEACTIVATE : ACT_ST_ENABLED;
    end else begin
        w_link_state = w_link_activating ? ACT_ST_ACTIVATE : ACT_ST_DISABLED;
    end
end

logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_actop_is_activate;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_actop_is_ack;

// An activation message these rules will judge at all, and the ones they
// believe -- the ones they did not report.
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_act_msg;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_actop_ok_in_state;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_act_wrong_phase;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_act_unsolicited;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]    w_act_believed;

// Requests completing on this edge, per stream. A die sees a request flit's
// granules before the flit is complete (narrow FDI), so its answer can complete
// on the same edge as the request; that answer is solicited. Written from the
// request terms of w_act_believed (a request is never unsolicited).
logic [DIR_CNT-1:0]                     w_flit_act_req_now;
logic [DIR_CNT-1:0]                     w_flit_deact_req_now;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_flit_act_req_now[d]   = 1'b0;
        w_flit_deact_req_now[d] = 1'b0;
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            if (w_chk_go[d] & w_starts_activation[d][g] & w_actop_legal[d][g] &
                ~w_msgstart_forbidden[d][g]) begin
                if ((w_chk_actop[d][g] == ACTOP_ACTIVATE_REQ) &
                    ((w_link_state == ACT_ST_DISABLED) | (w_link_state == ACT_ST_ACTIVATE)))
                    w_flit_act_req_now[d] = 1'b1;
                if ((w_chk_actop[d][g] == ACTOP_DEACTIVATE_REQ) &
                    ((w_link_state == ACT_ST_ENABLED) | (w_link_state == ACT_ST_DEACTIVATE)))
                    w_flit_deact_req_now[d] = 1'b1;
            end
        end
    end
end

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_actop_is_activate[d][g] =
                (w_chk_actop[d][g] == ACTOP_ACTIVATE_REQ) |
                (w_chk_actop[d][g] == ACTOP_ACTIVATE_ACK);

            w_actop_is_ack[d][g] =
                (w_chk_actop[d][g] == ACTOP_ACTIVATE_ACK) |
                (w_chk_actop[d][g] == ACTOP_DEACTIVATE_ACK);

            // A misplaced activation message is still believed: its placement
            // is reported, its meaning is unambiguous.
            w_act_msg[d][g] = w_starts_activation[d][g] &
                              w_actop_legal[d][g] &
                              ~w_msgstart_forbidden[d][g];

            // The legality table, written from 8.4. The answer rule asks about
            // the die that sent the message -- the die driving this stream --
            // whose received requests travelled the other way.
            case (w_link_state)
                ACT_ST_DISABLED,
                ACT_ST_ACTIVATE:
                    w_actop_ok_in_state[d][g] =  w_actop_is_activate[d][g];
                default:
                    w_actop_ok_in_state[d][g] = ~w_actop_is_activate[d][g];
            endcase

            w_act_wrong_phase[d][g] = w_act_msg[d][g] & ~w_actop_ok_in_state[d][g];

            w_act_unsolicited[d][g] =
                w_act_msg[d][g] & w_actop_is_ack[d][g] &
                ~(w_actop_is_activate[d][g] ?
                      (r_act_req[1-d] | (w_chk_go[d] & w_flit_act_req_now[1-d])) :
                      (r_deact_req[1-d] | (w_chk_go[d] & w_flit_deact_req_now[1-d])));

            w_act_believed[d][g] = w_act_msg[d][g] &
                                   ~w_act_wrong_phase[d][g] &
                                   ~w_act_unsolicited[d][g];
        end
    end
end

// Which events a consumed flit carries, gathered rather than sequenced.
logic [DIR_CNT-1:0]                     w_flit_act_req;
logic [DIR_CNT-1:0]                     w_flit_act_ack;
logic [DIR_CNT-1:0]                     w_flit_deact_req;
logic [DIR_CNT-1:0]                     w_flit_deact_ack;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_flit_act_req[d]   = 1'b0;
        w_flit_act_ack[d]   = 1'b0;
        w_flit_deact_req[d] = 1'b0;
        w_flit_deact_ack[d] = 1'b0;

        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            if (w_act_believed[d][g]) begin
                case (w_chk_actop[d][g])
                    ACTOP_ACTIVATE_REQ:   w_flit_act_req[d]   = 1'b1;
                    ACTOP_ACTIVATE_ACK:   w_flit_act_ack[d]   = 1'b1;
                    ACTOP_DEACTIVATE_REQ: w_flit_deact_req[d] = 1'b1;
                    ACTOP_DEACTIVATE_ACK: w_flit_deact_ack[d] = 1'b1;
                    default:              ;
                endcase
            end
        end
    end
end

logic [DIR_CNT-1:0]                     w_act_req_nxt;
logic [DIR_CNT-1:0]                     w_act_ack_nxt;
logic [DIR_CNT-1:0]                     w_deact_req_nxt;
logic [DIR_CNT-1:0]                     w_deact_ack_nxt;

// A completed teardown returns both dies to DISABLED (8.4). Computed from the
// events AFTER this flit, so the flit completing the exchange is judged against
// the link it tore down. Gated with the model so that an instance holding no
// activation state has no teardown to complete.
logic                                   w_teardown_done;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_act_req_nxt[d]   = r_act_req[d]   | (w_chk_go[d] & w_flit_act_req[d]);
        w_act_ack_nxt[d]   = r_act_ack[d]   | (w_chk_go[d] & w_flit_act_ack[d]);
        w_deact_req_nxt[d] = r_deact_req[d] | (w_chk_go[d] & w_flit_deact_req[d]);
        w_deact_ack_nxt[d] = r_deact_ack[d] | (w_chk_go[d] & w_flit_deact_ack[d]);
    end

    w_teardown_done = w_act_model_en & (&w_deact_req_nxt) & (&w_deact_ack_nxt);
end

// I_ERR_CLEAR does not alter protocol-model state.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_act_req      <= '0;
        r_act_ack      <= '0;
        r_deact_req    <= '0;
        r_deact_ack    <= '0;
        r_act_ack_half <= '0;
    end else if (I_LINK_RESET || w_teardown_done) begin
        r_act_req      <= '0;
        r_act_ack      <= '0;
        r_deact_req    <= '0;
        r_deact_ack    <= '0;
        r_act_ack_half <= '0;
    end else if (w_act_model_en) begin
        r_act_req   <= w_act_req_nxt;
        r_act_ack   <= w_act_ack_nxt;
        r_deact_req <= w_deact_req_nxt;
        r_deact_ack <= w_deact_ack_nxt;
        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            if (w_half0_commit[d] & ~w_flit_nop[d] & w_act_believed[d][0] &
                (w_chk_actop[d][0] == ACTOP_ACTIVATE_ACK)) begin
                r_act_ack_half[d] <= 1'b1;
            end
        end
    end
end

// -----------------------------------------------------------------------------
// Credit accounting.
//
// Deliberately independent of AOU_*_CRD_CTRL; written from 6.1-6.4 and
// 8.4. Plane fields name destinations on credited messages and sources on
// advertisements. See DESIGN.md "Credit accounting".
// -----------------------------------------------------------------------------
localparam int CRD_CLS_WD  = $clog2(CRD_CLS_CNT);

if (CRD_CAPACITY < 1) begin : gen_crd_capacity_too_small
    $fatal(1, "AOU_FDI_CHECKER: CRD_CAPACITY=%0d; a shadow counter must hold at least 1 credit",
           CRD_CAPACITY);
end

// The fallback width exists only long enough for the guard above to issue its
// diagnostic.
localparam int CRD_WD = (CRD_CAPACITY < 1) ? 1 : $clog2(CRD_CAPACITY + 1);

// The running count within a flit: a full counter plus everything one flit can
// advertise before the capacity clips it -- a protocol header and up to
// twenty-four two-granule credit grants, 128 each.
localparam int CRD_FLIT_ADS_MAX = (GRANULE_CNT / 2) * 128 + 128;
localparam int CRD_SUM_WD       = $clog2(CRD_CAPACITY + CRD_FLIT_ADS_MAX + 1);

// Shadow counters: credits die d may spend on its own local plane p, i.e.
// advertisements for that plane observed travelling the other way minus the
// credited messages die d has sent to it.
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_WD-1:0]  r_crd;

// The windows v0.8 8.4 and 9.2 open and close for die d. Advertising is legal
// from the flit that carries its own ActivateAck ("after ActivateAck is sent,
// it is permitted ... to send credits") until the link reaches DISABLED, where
// no credit may be sent (8.4 DISABLED). That includes every class after the
// die's own DeactivateAck: request credits -- WriteReq, ReadReq and, as an
// interim reading, WriteData -- by v0.8 8.4, response credits by MAS 7.3.1
// (v0.8 is silent on them). A flit's credits are consumed with the flit, so
// the flit completing the teardown is still judged before DISABLED. Sending
// credited messages is legal once it has sent an ActivateReq and received the
// ActivateAck answering it (9.2) -- the lenient of the two readings, since
// 8.4's ENABLED additionally waits for the die's own acknowledge; an
// ActivateAck in a committed first half counts as received. Requests stop at
// its own DeactivateReq; pending ReadData and WriteResp must still be sent
// after it (v0.8 8.4) and stay legal until DISABLED. Each closing message is
// the first in its flit (4.4), so the rest of that flit is after it and the
// windows close with the flit rather than after it.
logic [DIR_CNT-1:0]                                 w_adv_en;
logic [DIR_CNT-1:0]                                 w_consume_en;
logic [DIR_CNT-1:0]                                 w_consume_rsp_en;
logic [DIR_CNT-1:0][CRD_CLS_CNT-1:0]                w_consume_cls_en;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_adv_en[d]         = r_act_ack[d] | w_flit_act_ack[d];
        w_consume_rsp_en[d] = r_act_req[d] & (r_act_ack[1-d] | r_act_ack_half[1-d]);
        w_consume_en[d]     = w_consume_rsp_en[d] & ~w_deact_req_nxt[d];
        for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
            w_consume_cls_en[d][c] = ((c == CRD_R) || (c == CRD_B)) ? w_consume_rsp_en[d]
                                                                     : w_consume_en[d];
        end
    end
end

// Credited messages: class, believed, and legal to spend.
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][CRD_CLS_WD-1:0]    w_crd_cls;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                    w_crd_msg;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                    w_rp_out_of_range;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            case (w_chk_msgtype[d][g])
                MSG_WR_REQ:   w_crd_cls[d][g] = CRD_CLS_WD'(CRD_AW);
                MSG_RD_REQ:   w_crd_cls[d][g] = CRD_CLS_WD'(CRD_AR);
                MSG_WR_DATA,
                MSG_WRF_DATA: w_crd_cls[d][g] = CRD_CLS_WD'(CRD_W);
                MSG_RD_DATA:  w_crd_cls[d][g] = CRD_CLS_WD'(CRD_R);
                default:      w_crd_cls[d][g] = CRD_CLS_WD'(CRD_B);
            endcase

            w_rp_out_of_range[d][g] = w_starts_credited[d][g] &
                                      ~w_msg_rp_ok[d][w_chk_rp[d][g]];

            // Believed: a credited message of known length, beginning where a
            // message may, to a plane the link has. A message the rules above
            // have already rejected is not spent, so one root cause does not
            // also look like an underflow.
            w_crd_msg[d][g] = w_starts_credited[d][g] & w_msg_claims[d][g] &
                              ~w_msgstart_forbidden[d][g] & ~w_rp_out_of_range[d][g];
        end
    end
end

// A credit grant advertises all four planes at once, so its plane is a field
// index rather than a field value; aou_fdi_wire_pkg's decode_credit_grant
// reads the twenty fields off Figure 20's MSB-first stream. A grant may start
// at any granule -- 4.4 constrains only the Activation messages -- so the
// granule pair at every position is decoded and the believed grants summed. A grant starting at granule 47 continues in G0 of the next
// flit (4.4), so its first granule is held over in r_grant_g0 and its body is
// judged with the flit that carries it. Believed: well-formed and beginning
// where a message may. A grant the framing rule has rejected is neither counted
// nor has its reserved bits read.
localparam int GRANT_POS_CNT = GRANULE_CNT - 1;

logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                        w_grant_believed;
logic [DIR_CNT-1:0]                                         r_grant_pend;
logic [DIR_CNT-1:0][GRANULE_WD-1:0]                         r_grant_g0;
// A believed grant from granule 47 of the previous flit, whose body is G0.
logic [DIR_CNT-1:0]                                         w_grant_spans;
// The second granule of a believed grant, where its reserved bits live.
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                        w_grant_body;

logic [DIR_CNT-1:0][GRANT_POS_CNT-1:0][CG_MSG_WD-1:0]       w_grant_pkt;
logic [DIR_CNT-1:0][CG_MSG_WD-1:0]                          w_grant_span_pkt;
logic [DIR_CNT-1:0][GRANT_POS_CNT-1:0]
      [RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_ENC_WD-1:0]    w_grant_enc;
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_ENC_WD-1:0] w_grant_span_enc;
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_ENC_WD-1:0] w_hdr_enc;
logic [DIR_CNT-1:0]                                         w_hdr_adv;
logic [DIR_CNT-1:0][RP_WD-1:0]                              w_hdr_rp;
// Advertisements naming a plane the advertising die does not have (6.4.2), a
// grant's attributed to its first granule and a spanning grant's to G0.
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                        w_grant_rp_bad;
logic [DIR_CNT-1:0]                                         w_hdr_rp_bad;

// One flit's advertisements, in the advertising die's own plane numbering,
// then expressed as the peer's local plane that may spend them: die 1-d's
// local plane p is funded by the wire plane its messages carry, w_plane_wire.
//
// SUMMED AS A TREE, NOT A WALK. Forty-nine terms per plane and class -- the
// header, a spanning grant and forty-seven grant positions -- reduced pairwise
// in six levels, so the depth is logarithmic in the term count. Written out
// rather than left to a tool to re-associate, because not every tool will.
localparam int ADS_TERM_CNT = GRANT_POS_CNT + 2;
localparam int ADS_TERM_WD  = 8;
localparam int ADS_TREE_LVL = $clog2(ADS_TERM_CNT);

logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][ADS_TERM_CNT-1:0][ADS_TERM_WD-1:0] w_ads_term;
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0] w_ads_src;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0]    w_ads_for;

// THE MAP IS THE OBSERVED DIE'S ALONE. The wire plane a credited message from
// die d's local plane p carries: the observed die remaps through
// I_CFG_RP_DEST_RP; the peer names the observed die's planes as they are, and
// the observed die advertises them as they are. Indexing the peer's counters
// through the map as well is invisible under a permutation of 0..RP_COUNT-1
// and blinds the inbound direction under any other map (the peer's plane 2
// funding the observed die's plane 0, say), which the range rule admits.
logic [DIR_CNT-1:0][RP_COUNT-1:0][RP_WD-1:0]                          w_plane_wire;

// The terms are padded with zeros to a power of two so that every level halves
// exactly; each level's bound is a constant of the level, which is what lets
// every tool unroll it.
localparam int ADS_TREE_CNT = 1 << ADS_TREE_LVL;

function automatic logic [CRD_SUM_WD-1:0] sum_ads(
    input logic [ADS_TERM_CNT-1:0][ADS_TERM_WD-1:0] terms);
    logic [ADS_TREE_CNT-1:0][CRD_SUM_WD-1:0] lvl;
    lvl = '0;
    for (int unsigned i = 0; i < ADS_TERM_CNT; i++) begin
        lvl[i] = CRD_SUM_WD'(terms[i]);
    end
    for (int unsigned l = 0; l < ADS_TREE_LVL; l++) begin
        for (int unsigned i = 0; i < (ADS_TREE_CNT >> (l + 1)); i++) begin
            lvl[i] = lvl[2 * i] + lvl[2 * i + 1];
        end
    end
    return lvl[0];
endfunction

function automatic logic names_missing_plane(
    input logic [RP_WIRE_CNT-1:0] plane_ok,
    input logic [RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_ENC_WD-1:0] enc);
    names_missing_plane = 1'b0;
    for (int unsigned q = 0; q < RP_WIRE_CNT; q++) begin
        if (~plane_ok[q] && (|enc[q])) begin
            names_missing_plane = 1'b1;
        end
    end
endfunction

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_grant_believed[d] = w_starts_crdtgrant[d] & ~w_msgstart_forbidden[d];
        w_grant_spans[d]    = r_grant_pend[d] & ~w_chk_msg_start[d][0];
        w_grant_body[d]     = {w_grant_believed[d][GRANULE_CNT-2:0], w_grant_spans[d]};

        w_grant_span_pkt[d] = {w_chk_granule[d][0], r_grant_g0[d]};
        w_grant_span_enc[d] = decode_credit_grant(w_grant_span_pkt[d]);
        for (int unsigned g = 0; g < GRANT_POS_CNT; g++) begin
            w_grant_pkt[d][g] = {w_chk_granule[d][g+1], w_chk_granule[d][g]};
            w_grant_enc[d][g] = decode_credit_grant(w_grant_pkt[d][g]);
        end

        w_hdr_enc[d] = '0;
        w_hdr_rp[d] = w_chk_msg_credit[d][MC_RP_LSB +: RP_WD];
        w_hdr_enc[d][w_hdr_rp[d]][CRD_AW] = w_chk_msg_credit[d][MC_WREQ_LSB  +: CRD_ENC_WD];
        w_hdr_enc[d][w_hdr_rp[d]][CRD_AR] = w_chk_msg_credit[d][MC_RREQ_LSB  +: CRD_ENC_WD];
        w_hdr_enc[d][w_hdr_rp[d]][CRD_W]  = w_chk_msg_credit[d][MC_WDATA_LSB +: CRD_ENC_WD];
        w_hdr_enc[d][w_hdr_rp[d]][CRD_R]  = w_chk_msg_credit[d][MC_RDATA_LSB +: CRD_ENC_WD];
        w_hdr_enc[d][w_hdr_rp[d]][CRD_B]  =
            CRD_ENC_WD'(w_chk_msg_credit[d][MC_WRESP_LSB +: CRD_ENC_B_WD]);

        // A header advertising nothing names no plane.
        w_hdr_adv[d]    = |w_chk_msg_credit[d][MC_WREQ_LSB +: MC_RP_LSB];
        w_hdr_rp_bad[d] = w_hdr_adv[d] & ~w_adv_rp_ok[d][w_hdr_rp[d]];

        w_grant_rp_bad[d] = '0;
        if (w_grant_spans[d] && names_missing_plane(w_adv_rp_ok[d], w_grant_span_enc[d])) begin
            w_grant_rp_bad[d][0] = 1'b1;
        end
        for (int unsigned g = 0; g < GRANT_POS_CNT; g++) begin
            if (w_grant_believed[d][g] &&
                names_missing_plane(w_adv_rp_ok[d], w_grant_enc[d][g])) begin
                w_grant_rp_bad[d][g] = 1'b1;
            end
        end

        for (int unsigned q = 0; q < RP_WIRE_CNT; q++) begin
            for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
                w_ads_term[d][q][c][0] = CREDIT_TABLE[w_hdr_enc[d][q][c]];
                w_ads_term[d][q][c][1] = w_grant_spans[d]
                                       ? CREDIT_TABLE[w_grant_span_enc[d][q][c]] : '0;
                for (int unsigned g = 0; g < GRANT_POS_CNT; g++) begin
                    w_ads_term[d][q][c][g + 2] = w_grant_believed[d][g]
                                               ? CREDIT_TABLE[w_grant_enc[d][g][q][c]] : '0;
                end
                w_ads_src[d][q][c] = w_adv_rp_ok[d][q] ? sum_ads(w_ads_term[d][q][c]) : '0;
            end
        end

        for (int unsigned p = 0; p < RP_COUNT; p++) begin
            w_plane_wire[d][p] = (d == DIR_LP) ? I_CFG_RP_DEST_RP[p] : RP_WD'(p);
            // Advertisements on stream d fund die 1-d's local plane p, whose
            // messages carry the plane the advertiser named.
            w_ads_for[d][p] = w_ads_src[d][(d == DIR_LP) ? RP_WD'(p) : I_CFG_RP_DEST_RP[p]];
        end
    end
end

// FIRST HALVES FUND EARLY. A latency-optimized flit's first half that passes
// its cancel cycle is consumed by the protocol layer before the second half
// arrives (UCIe 3.0 10.2, pl_flit_cancel examples: "the first half of the Flit is consumed by the
// Protocol Layer because it is not canceled", Figures 10-16 and 10-17), so a
// die may spend a credit grant carried there from then on. At the first
// half's commit the buffer's first half is current, and the framing of
// granules 0-23 depends only on earlier granules and the carry, so the grants
// lying wholly in G0-G23 -- and one continuing from the previous flit's G47 --
// are summed then and fund the peer at once. The flit's consume adds only the
// rest: the header MsgCredit (bytes 128-129, second half) and grants reaching
// into the second half wait for the whole flit, as before. An Activation
// message is at G0 (4.4), so the window is already known at the commit.
localparam int HALF_G = GRANULE_CNT / 2;

logic [DIR_CNT-1:0]                                                   w_early_go;
logic [DIR_CNT-1:0]                                                   w_early_adv_en;
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0]
      [ADS_TERM_CNT-1:0][ADS_TERM_WD-1:0]                             w_early_term;
logic [DIR_CNT-1:0][RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0] w_early_src;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0]    w_early_for;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0]    r_early_for;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0]    w_late_for;
// A clip at the early funding, reported with the advertising flit's consume.
logic [DIR_CNT-1:0]                                                   r_early_clip;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_early_go[d]     = w_half0_commit[d] & ~w_flit_nop[d];
        // Funds every advertisement until DISABLED, the same window as
        // w_adv_en; the ActivateAck at G0 opens it within the first half.
        w_early_adv_en[d] =
            r_act_ack[d] | (w_act_believed[d][0] & (w_chk_actop[d][0] == ACTOP_ACTIVATE_ACK));

        for (int unsigned q = 0; q < RP_WIRE_CNT; q++) begin
            for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
                w_early_term[d][q][c] = '0;
                w_early_term[d][q][c][1] = w_grant_spans[d]
                                         ? CREDIT_TABLE[w_grant_span_enc[d][q][c]] : '0;
                for (int unsigned g = 0; g < HALF_G - 1; g++) begin
                    w_early_term[d][q][c][g + 2] = w_grant_believed[d][g]
                                                 ? CREDIT_TABLE[w_grant_enc[d][g][q][c]] : '0;
                end
                w_early_src[d][q][c] = (w_adv_rp_ok[d][q] & w_early_go[d] & w_early_adv_en[d])
                                     ? sum_ads(w_early_term[d][q][c]) : '0;
            end
        end

        for (int unsigned p = 0; p < RP_COUNT; p++) begin
            w_early_for[d][p] = w_early_src[d][(d == DIR_LP) ? RP_WD'(p) : I_CFG_RP_DEST_RP[p]];
            for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
                w_late_for[d][p][c] = (w_ads_for[d][p][c] > r_early_for[d][p][c])
                                    ? w_ads_for[d][p][c] - r_early_for[d][p][c] : '0;
            end
        end
    end
end

// Held for the structural rules as well as the credit model, so loaded while
// either is present. I_ERR_CLEAR does not alter protocol-model state.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_grant_pend <= '0;
        r_grant_g0   <= '0;
    end else if (I_LINK_RESET) begin
        r_grant_pend <= '0;
        r_grant_g0   <= '0;
    end else begin
        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            if (w_grant_logic_en & w_chk_go[d]) begin
                r_grant_pend[d] <= w_grant_believed[d][GRANULE_CNT-1];
                r_grant_g0[d]   <= w_chk_granule[d][GRANULE_CNT-1];
            end
        end
    end
end

// -----------------------------------------------------------------------------
// Spending. See DESIGN.md "Spending".
//
// Per counter, this flit's spend is a tree sum over the granules that start a
// credited message for that plane and class, and one comparison against what
// was available decides the underflow. Nothing walks the granules in sequence.
// -----------------------------------------------------------------------------
localparam int SPENT_WD       = $clog2(GRANULE_CNT + 1);
localparam int SPENT_TREE_LVL = $clog2(GRANULE_CNT);

// Granule g starts a believed credited message for die d's local plane p and
// class c. The granule's plane field is the destination, which is what local
// plane p's messages carry: w_plane_wire[d][p].
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0]     w_crd_sel;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][GRANULE_CNT-1:0][MSG_G_WD-1:0] w_spent_term;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][SPENT_WD-1:0]        w_spent;
// Spending on stream d is judged this cycle at all.
logic [DIR_CNT-1:0][CRD_CLS_CNT-1:0]                                    w_spend_go;

logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0]      w_crd_avail;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0]                      w_crd_uf;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_SUM_WD-1:0]      w_crd_left;
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0][CRD_WD-1:0]          w_crd_nxt;
// Die d's counter would have exceeded CRD_CAPACITY this cycle and was clipped:
// credit this instance can no longer track.
logic [DIR_CNT-1:0][RP_COUNT-1:0][CRD_CLS_CNT-1:0]                      w_crd_clip;
logic [DIR_CNT-1:0]                                                     w_crd_overflow;

logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                                    w_msg_order;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]                                    w_crd_underflow;

localparam int SPENT_TREE_CNT = 1 << SPENT_TREE_LVL;

function automatic logic [SPENT_WD-1:0] sum_spent(
    input logic [GRANULE_CNT-1:0][MSG_G_WD-1:0] terms);
    logic [SPENT_TREE_CNT-1:0][SPENT_WD-1:0] lvl;
    lvl = '0;
    for (int unsigned i = 0; i < GRANULE_CNT; i++) begin
        lvl[i] = SPENT_WD'(terms[i]);
    end
    for (int unsigned l = 0; l < SPENT_TREE_LVL; l++) begin
        for (int unsigned i = 0; i < (SPENT_TREE_CNT >> (l + 1)); i++) begin
            lvl[i] = lvl[2 * i] + lvl[2 * i + 1];
        end
    end
    return lvl[0];
endfunction

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
            w_spend_go[d][c] = w_chk_go[d] & w_consume_cls_en[d][c];
        end

        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            for (int unsigned p = 0; p < RP_COUNT; p++) begin
                for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
                    w_crd_sel[d][g][p][c] = w_crd_msg[d][g] &
                                            (w_chk_rp[d][g] == w_plane_wire[d][p]) &
                                            (w_crd_cls[d][g] == CRD_CLS_WD'(c));
                end
            end
        end

        for (int unsigned p = 0; p < RP_COUNT; p++) begin
            for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
                for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
                    w_spent_term[d][p][c][g] = (w_spend_go[d][c] & w_crd_sel[d][g][p][c])
                                             ? w_msg_len[d][g] : '0;
                end
                w_spent[d][p][c] = sum_spent(w_spent_term[d][p][c]);

                // Advertisements crossing the other way in this same cycle are
                // counted before this cycle's spending.
                w_crd_avail[d][p][c] = CRD_SUM_WD'(r_crd[d][p][c]) +
                    ((w_chk_go[1-d] & w_adv_en[1-d]) ? w_late_for[1-d][p][c] : '0) +
                    w_early_for[1-d][p][c];

                w_crd_uf[d][p][c]   = w_crd_avail[d][p][c] < CRD_SUM_WD'(w_spent[d][p][c]);
                w_crd_left[d][p][c] = w_crd_uf[d][p][c]
                                    ? '0 : w_crd_avail[d][p][c] - CRD_SUM_WD'(w_spent[d][p][c]);

                w_crd_clip[d][p][c] = w_crd_left[d][p][c] > CRD_SUM_WD'(CRD_CAPACITY);
                w_crd_nxt[d][p][c]  = w_crd_clip[d][p][c] ? CRD_WD'(CRD_CAPACITY)
                                                          : CRD_WD'(w_crd_left[d][p][c]);
            end
        end

        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            // Asks nothing about the plane: this is about when a credited
            // message was sent, not which buffer it lands in.
            w_msg_order[d][g] = w_chk_go[d] & w_crd_msg[d][g] &
                                ~w_consume_cls_en[d][w_crd_cls[d][g]];

            // An underflowing counter marks every credited granule of its
            // class in the flit; the capture names the lowest. The credit
            // enable is here as well as at the matrix row because this is what
            // makes the spend trees unread, and so takes them out with it.
            w_crd_underflow[d][g] = 1'b0;
            for (int unsigned p = 0; p < RP_COUNT; p++) begin
                for (int unsigned c = 0; c < CRD_CLS_CNT; c++) begin
                    w_crd_underflow[d][g] |= w_crd_en & w_spend_go[d][c] &
                                             w_crd_uf[d][p][c] & w_crd_sel[d][g][p][c];
                end
            end
        end

        // Only an advertisement can push a counter over, so a clip is a finding
        // against the stream that carried the advertisement, and it is judged
        // with that flit: after this cycle's spending, so credit advertised and
        // spent in the same flit is not lost and not reported.
        w_crd_overflow[d] = w_crd_en & w_chk_go[d] & ((|w_crd_clip[1-d]) | r_early_clip[d]);
    end
end

// The credit enable is the load enable: with it constant zero these registers
// are only ever reset, which lets the tools drop them and everything that only
// fed them. Zeroed when the link reaches DISABLED (8.2).
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_crd <= '0;
    end else if (I_LINK_RESET || w_teardown_done) begin
        r_crd <= '0;
    end else if (w_crd_en) begin
        r_crd <= w_crd_nxt;
    end
end

// The early part of the flit in progress, until its consume nets it out. A
// first half commits at least one cycle after the previous flit's consume.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_early_for  <= '0;
        r_early_clip <= '0;
    end else if (I_LINK_RESET) begin
        r_early_for  <= '0;
        r_early_clip <= '0;
    end else if (w_crd_en) begin
        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            if (w_early_go[d]) begin
                r_early_for[d]  <= w_early_for[d];
                r_early_clip[d] <= |w_crd_clip[1-d];
            end else if (w_chk_go[d]) begin
                r_early_for[d]  <= '0;
                r_early_clip[d] <= 1'b0;
            end
        end
    end
end

// -----------------------------------------------------------------------------
// Per-granule violation matrix. One bit per granule per violation class, and
// the class index is the code reported. Every rule drives its own row.
//
// EVERY ROW IS QUALIFIED BY ITS CLASS ENABLE, and this is the only place the
// reporting semantics of a disabled class are decided: nothing enters the
// bundle below, so a disabled class cannot set its sticky bit, pull the
// trigger, bump the count or freeze the capture record.
// -----------------------------------------------------------------------------
logic [DIR_CNT-1:0][GRANULE_CNT-1:0][VIOL_CLASS_CNT-1:0]    w_granule_viol;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_granule_viol[d][g] = '0;

            w_granule_viol[d][g][VIOL_MSGTYPE] =
                w_chk_class_en[VIOL_MSGTYPE] &
                w_chk_msg_start[d][g] & ~w_msgtype_legal[d][g];

            w_granule_viol[d][g][VIOL_MISCOP] =
                w_chk_class_en[VIOL_MISCOP] &
                w_starts_misc[d][g] & ~w_miscop_legal[d][g];

            w_granule_viol[d][g][VIOL_ACTIVATIONOP] =
                w_chk_class_en[VIOL_ACTIVATIONOP] &
                w_starts_activation[d][g] & ~w_actop_legal[d][g];

            w_granule_viol[d][g][VIOL_DLENGTH] =
                w_chk_class_en[VIOL_DLENGTH] &
                w_starts_data[d][g] & (w_chk_dlength[d][g] == DLENGTH_RESERVED);

            // Attributed to the granule whose bits are non-zero, which for the
            // credit grant is its second granule.
            w_granule_viol[d][g][VIOL_RSVD_NONZERO] =
                w_chk_class_en[VIOL_RSVD_NONZERO] &
                ((w_starts_activation[d][g] & w_act_rsvd_nonzero[d][g]) |
                 (w_grant_body[d][g]        & w_crdtgrant_rsvd_nonzero[d][g]) |
                 (w_chk_msg_start[d][g]     & w_msg_rsvd_nonzero[d][g]));

            w_granule_viol[d][g][VIOL_MSGSTART] =
                w_chk_class_en[VIOL_MSGSTART] &
                w_chk_msg_start[d][g] & w_msgstart_forbidden[d][g];

            // Both activation sequencing rules share one class.
            w_granule_viol[d][g][VIOL_ACT_SEQ] =
                w_chk_class_en[VIOL_ACT_SEQ] &
                (w_act_wrong_phase[d][g] | w_act_unsolicited[d][g]);

            w_granule_viol[d][g][VIOL_MSG_ORDER] =
                w_chk_class_en[VIOL_MSG_ORDER] &
                w_msg_order[d][g];

            w_granule_viol[d][g][VIOL_CRD_UNDERFLOW] =
                w_chk_class_en[VIOL_CRD_UNDERFLOW] &
                w_crd_underflow[d][g];

            // Attributed to the advertising flit's header, so granule 0.
            w_granule_viol[d][g][VIOL_CRD_OVERFLOW] =
                w_chk_class_en[VIOL_CRD_OVERFLOW] &
                (g == 0) & w_crd_overflow[d];

            w_granule_viol[d][g][VIOL_MISC_PLACEMENT] =
                w_chk_class_en[VIOL_MISC_PLACEMENT] &
                w_misc_misplaced[d][g];

            // A grant is attributed to its own granule; the protocol header has
            // none, so a header finding names granule 0.
            w_granule_viol[d][g][VIOL_ADV_ORDER] =
                w_chk_class_en[VIOL_ADV_ORDER] & ~w_adv_en[d] &
                (w_starts_crdtgrant[d][g] | ((g == 0) & w_hdr_adv[d]));

            w_granule_viol[d][g][VIOL_RP_RANGE] =
                w_chk_class_en[VIOL_RP_RANGE] &
                (w_rp_out_of_range[d][g] | w_grant_rp_bad[d][g] |
                 ((g == 0) & w_hdr_rp_bad[d]));

            // A flit for another bridge (4.3.1): its credits are assigned to
            // that bridge (6.4), so nothing this instance accounts for applies
            // to it. Reported on the header, so against granule 0; the flit is
            // otherwise judged as if it were ours, because a bench with one
            // bridge that sees this has a misconfiguration to fix first.
            w_granule_viol[d][g][VIOL_FDID] =
                w_chk_class_en[VIOL_FDID] &
                (g == 0) & (w_chk_fdid[d] != FDID_WD'(FDID));

            // A configuration finding rather than a flit finding, but reported
            // with each consumed flit so that it carries a sequence number and
            // arrives before any credit report the bad map would produce.
            w_granule_viol[d][g][VIOL_RP_MAP] =
                w_chk_class_en[VIOL_RP_MAP] & (g == 0) & w_rp_map_bad;
        end
    end
end

// -----------------------------------------------------------------------------
// Capture candidate per direction: lowest granule, then lowest class.
// Sticky status and count reduce the full matrix below.
// -----------------------------------------------------------------------------
logic [DIR_CNT-1:0]                         w_viol_valid;
logic [DIR_CNT-1:0][VIOL_CODE_WD-1:0]       w_viol_code;
logic [DIR_CNT-1:0][GRANULE_IDX_WD-1:0]     w_viol_granule_idx;
logic [DIR_CNT-1:0][GRANULE_WD-1:0]         w_viol_granule;
logic [DIR_CNT-1:0][GRANULE_CNT-1:0]        w_granule_bad;

always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
            w_granule_bad[d][g] = |w_granule_viol[d][g];
        end

        w_viol_valid[d] = w_chk_go[d] & (|w_granule_bad[d]);

        // Counting down means the last write wins and the last write is the
        // lowest set bit.
        w_viol_granule_idx[d] = '0;
        for (int unsigned g = GRANULE_CNT; g > 0; g--) begin
            if (w_granule_bad[d][g-1]) begin
                w_viol_granule_idx[d] = GRANULE_IDX_WD'(g - 1);
            end
        end

        w_viol_granule[d] = w_chk_granule[d][w_viol_granule_idx[d]];

        w_viol_code[d] = '0;
        for (int unsigned c = VIOL_CLASS_CNT; c > 0; c--) begin
            if (w_granule_viol[d][w_viol_granule_idx[d]][c-1]) begin
                w_viol_code[d] = VIOL_CODE_WD'(c - 1);
            end
        end
    end
end

logic [VIOL_CLASS_CNT-1:0]  r_violation;
logic [VIOL_CNT_WD-1:0]     r_violation_cnt;
logic                       r_violation_trigger;

logic                       r_capture_valid;
logic [VIOL_CODE_WD-1:0]    r_capture_code;
logic                       r_capture_dir;
logic [FLIT_SEQ_WD-1:0]     r_capture_flit_seq;
logic [GRANULE_IDX_WD-1:0]  r_capture_granule_idx;
logic [GRANULE_WD-1:0]      r_capture_granule;

// The singular capture takes LP when both directions report simultaneously.
// The one aggregate count adds one for each direction whose flit has a finding,
// not one per matrix hit: a flit breaking one rule in thirty granules is one
// event, while simultaneous offending LP and PL flits add two.
logic                       w_viol_any;
logic [VIOL_CLASS_CNT-1:0]  w_viol_set;
localparam int VIOL_INC_WD = $clog2(DIR_CNT + 1);
localparam int VIOL_SUM_WD = ((VIOL_CNT_WD > VIOL_INC_WD)
                              ? VIOL_CNT_WD : VIOL_INC_WD) + 1;

logic [VIOL_INC_WD-1:0]     w_viol_inc;
logic [VIOL_SUM_WD-1:0]     w_viol_cnt_sum;
logic                       w_viol_cap_dir;

assign w_viol_any     = |w_viol_valid;
assign w_viol_cap_dir = w_viol_valid[DIR_LP] ? 1'b0 : 1'b1;

always_comb begin
    w_viol_set = '0;
    w_viol_inc = '0;
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        if (w_chk_go[d]) begin
            for (int unsigned g = 0; g < GRANULE_CNT; g++) begin
                w_viol_set = w_viol_set | w_granule_viol[d][g];
            end
        end
        w_viol_inc = w_viol_inc + VIOL_INC_WD'(w_viol_valid[d]);
    end
end

assign w_viol_cnt_sum = VIOL_SUM_WD'(I_ERR_CLEAR ? '0 : r_violation_cnt) +
                        VIOL_SUM_WD'(w_viol_inc);

// Sticky violation vector, saturating count and one-cycle trigger. A finding
// coincident with I_ERR_CLEAR is kept.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_violation         <= '0;
        r_violation_cnt     <= '0;
        r_violation_trigger <= 1'b0;
    end else begin
        r_violation_trigger <= w_viol_any;
        if (w_viol_any) begin
            r_violation     <= (I_ERR_CLEAR ? '0 : r_violation) | w_viol_set;
            r_violation_cnt <= (|w_viol_cnt_sum[VIOL_SUM_WD-1:VIOL_CNT_WD])
                ? {VIOL_CNT_WD{1'b1}} : w_viol_cnt_sum[VIOL_CNT_WD-1:0];
        end else if (I_ERR_CLEAR) begin
            r_violation     <= '0;
            r_violation_cnt <= '0;
        end
    end
end

// First-violation capture record, frozen until cleared. r_flit_seq still holds
// this flit's number during the consume cycle. A clear drops the valid bit and
// leaves the fields, which mean nothing without it.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_capture_valid       <= 1'b0;
        r_capture_code        <= '0;
        r_capture_dir         <= 1'b0;
        r_capture_flit_seq    <= '0;
        r_capture_granule_idx <= '0;
        r_capture_granule     <= '0;
    end else if (w_viol_any && (!r_capture_valid || I_ERR_CLEAR)) begin
        r_capture_valid       <= 1'b1;
        r_capture_code        <= w_viol_code[w_viol_cap_dir];
        r_capture_dir         <= w_viol_cap_dir;
        r_capture_flit_seq    <= r_flit_seq[w_viol_cap_dir];
        r_capture_granule_idx <= w_viol_granule_idx[w_viol_cap_dir];
        r_capture_granule     <= w_viol_granule[w_viol_cap_dir];
    end else if (I_ERR_CLEAR) begin
        r_capture_valid       <= 1'b0;
    end
end

assign O_VIOLATION           = r_violation;
assign O_VIOLATION_TRIGGER   = r_violation_trigger;
assign O_VIOLATION_CNT       = r_violation_cnt;

assign O_CAPTURE_VALID       = r_capture_valid;
assign O_CAPTURE_CODE        = r_capture_code;
assign O_CAPTURE_DIR         = r_capture_dir;
assign O_CAPTURE_FLIT_SEQ    = r_capture_flit_seq;
assign O_CAPTURE_GRANULE_IDX = r_capture_granule_idx;
assign O_CAPTURE_GRANULE     = r_capture_granule;

assign O_CHECK_ENABLED       = w_chk_class_en;

assign O_LP_FLIT_SEQ         = r_flit_seq[DIR_LP];
assign O_PL_FLIT_SEQ         = r_flit_seq[DIR_PL];

// -----------------------------------------------------------------------------
// Optional activation-status cross-check.
//
// Quiescence-based comparison; see DESIGN.md before changing its timing.
// -----------------------------------------------------------------------------
// Each view is the two predicates the design's top level exposes, as
// {enabled, disabled}. ACTIVATE and DEACTIVATE both read as 2'b00 on both sides
// -- the design brings out no bit for either -- so the comparison cannot tell
// them apart and does not try.
localparam int XCHK_ST_WD = 2;

// The reset value of both view registers; ENABLED, 2'b10, is only ever derived.
localparam logic [XCHK_ST_WD-1:0] XCHK_ST_DISABLED = 2'b01;

// Counters stop at their limit rather than wrapping, so each is one bit wider
// than the limit needs and the limit itself is a reachable value.
localparam int XCHK_SETTLE_WD   = $clog2(XCHK_SETTLE_CYCLES + 1);
localparam int XCHK_CONVERGE_WD = $clog2(XCHK_CONVERGE_CYCLES + 1);

// One enable per die. Constants, so a disabled die's comparison logic is dead.
logic [DIR_CNT-1:0]                         w_xchk_en;

assign w_xchk_en[DIE_LP] = (XCHK_LP_EN != 0);
assign w_xchk_en[DIE_PL] = (XCHK_PL_EN != 0);

logic [DIR_CNT-1:0][XCHK_ST_WD-1:0]         w_xchk_chk_st;
logic [DIR_CNT-1:0][XCHK_ST_WD-1:0]         w_xchk_obs_st;

// The link has one state, so the checker's view is the same for both dies;
// what differs per die is the design status it is compared against.
always_comb begin
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_xchk_chk_st[d] = {(w_link_state == ACT_ST_ENABLED),
                            (w_link_state == ACT_ST_DISABLED)};
    end
end

// The only two reads of the comparison-only inputs in the module.
assign w_xchk_obs_st[DIE_LP] = {I_LP_ACT_ST_ENABLED, I_LP_ACT_ST_DISABLED};
assign w_xchk_obs_st[DIE_PL] = {I_PL_ACT_ST_ENABLED, I_PL_ACT_ST_DISABLED};

// Registered copies, used ONLY to notice a view changing. The comparison itself
// reads the live values.
logic [DIR_CNT-1:0][XCHK_ST_WD-1:0]         r_xchk_chk_st;
logic [DIR_CNT-1:0][XCHK_ST_WD-1:0]         r_xchk_obs_st;

logic [DIR_CNT-1:0]                         w_xchk_chk_moved;
logic [DIR_CNT-1:0]                         w_xchk_obs_moved;
logic [DIR_CNT-1:0]                         w_xchk_agree;

// An activation message crossed on either stream. Link-wide, and the set is
// the WELL-FORMED activation messages rather than the believed ones: a message
// this module rejected may still move a die's state machine.
logic                                       w_xchk_act_traffic;

logic [DIR_CNT-1:0]                         w_xchk_disturbed;
logic [DIR_CNT-1:0][XCHK_SETTLE_WD-1:0]     r_xchk_settle_cnt;
logic [DIR_CNT-1:0]                         w_xchk_settled;

// The one-sided convergence window: armed when this module's model moves into
// disagreement, disarmed when the design agrees again or the window expires.
logic [DIR_CNT-1:0]                         r_xchk_armed;
logic [DIR_CNT-1:0][XCHK_CONVERGE_WD-1:0]   r_xchk_conv_cnt;
logic [DIR_CNT-1:0]                         w_xchk_arm;
logic [DIR_CNT-1:0]                         w_xchk_expired;

// One report per disagreement, released when the two agree again.
logic [DIR_CNT-1:0]                         r_xchk_reported;
logic [DIR_CNT-1:0]                         w_xchk_fresh;

logic [DIR_CNT-1:0]                         w_xchk_timeout;
logic [DIR_CNT-1:0]                         w_xchk_mismatch;
logic [DIR_CNT-1:0]                         w_xchk_valid;
logic [DIR_CNT-1:0][XVIOL_CODE_WD-1:0]      w_xchk_code;

// Evidence that a comparison was reached, whatever its verdict.
logic [DIR_CNT-1:0]                         r_xchk_compared;

always_comb begin
    w_xchk_act_traffic = 1'b0;
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        if (w_chk_go[d] & (|w_act_msg[d])) begin
            w_xchk_act_traffic = 1'b1;
        end
    end

    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        w_xchk_chk_moved[d] = (w_xchk_chk_st[d] != r_xchk_chk_st[d]);
        w_xchk_obs_moved[d] = (w_xchk_obs_st[d] != r_xchk_obs_st[d]);
        w_xchk_agree[d]     = (w_xchk_chk_st[d] == w_xchk_obs_st[d]);

        w_xchk_disturbed[d] = w_xchk_act_traffic | w_xchk_chk_moved[d] |
                              w_xchk_obs_moved[d];

        // THE DISTURBANCE TERM IS LOAD-BEARING: on the cycle a view moves the
        // counter still holds what it reached before the move, and without it
        // the comparison would be made against the very change that was
        // supposed to restart the wait.
        w_xchk_settled[d] = (r_xchk_settle_cnt[d] ==
                             XCHK_SETTLE_WD'(XCHK_SETTLE_CYCLES)) &
                            ~w_xchk_disturbed[d];

        w_xchk_arm[d]     = w_xchk_chk_moved[d] & ~w_xchk_agree[d];
        w_xchk_expired[d] = r_xchk_armed[d] &
                            (r_xchk_conv_cnt[d] ==
                             XCHK_CONVERGE_WD'(XCHK_CONVERGE_CYCLES));

        w_xchk_fresh[d] = ~w_xchk_agree[d] & ~r_xchk_reported[d];

        w_xchk_timeout[d] = w_xchk_fresh[d] & w_xchk_expired[d];

        // The timeout term wins where both could fire at once.
        w_xchk_mismatch[d] = w_xchk_fresh[d] & w_xchk_settled[d] &
                             ~w_xchk_timeout[d];

        w_xchk_valid[d] = w_xchk_en[d] &
                          (w_xchk_timeout[d] | w_xchk_mismatch[d]);

        w_xchk_code[d] = w_xchk_timeout[d] ? XVIOL_CODE_WD'(XVIOL_TIMEOUT)
                                           : XVIOL_CODE_WD'(XVIOL_MISMATCH);
    end
end

// The settling timer and the convergence window are model state, not error
// status, so I_ERR_CLEAR leaves both alone. r_xchk_reported exists to suppress
// a report, so clearing releases it.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        // DISABLED rather than zero: zero reads as "activating or tearing
        // down" and would show both views moving on the first cycle.
        r_xchk_chk_st     <= {DIR_CNT{XCHK_ST_DISABLED}};
        r_xchk_obs_st     <= {DIR_CNT{XCHK_ST_DISABLED}};
        r_xchk_settle_cnt <= '0;
        r_xchk_armed      <= '0;
        r_xchk_conv_cnt   <= '0;
        r_xchk_reported   <= '0;
        r_xchk_compared   <= '0;
    end else if (I_LINK_RESET) begin
        r_xchk_chk_st     <= {DIR_CNT{XCHK_ST_DISABLED}};
        r_xchk_obs_st     <= {DIR_CNT{XCHK_ST_DISABLED}};
        r_xchk_settle_cnt <= '0;
        r_xchk_armed      <= '0;
        r_xchk_conv_cnt   <= '0;
        r_xchk_reported   <= '0;
        r_xchk_compared   <= '0;
    end else begin
        r_xchk_chk_st <= w_xchk_chk_st;
        r_xchk_obs_st <= w_xchk_obs_st;

        for (int unsigned d = 0; d < DIR_CNT; d++) begin
            if (w_xchk_disturbed[d]) begin
                r_xchk_settle_cnt[d] <= '0;
            end else if (~w_xchk_settled[d]) begin
                r_xchk_settle_cnt[d] <= r_xchk_settle_cnt[d] +
                                        XCHK_SETTLE_WD'(1);
            end

            // Arming restarts the window as well as opening it.
            if (w_xchk_arm[d]) begin
                r_xchk_armed[d]    <= 1'b1;
                r_xchk_conv_cnt[d] <= '0;
            end else if (w_xchk_agree[d] | w_xchk_expired[d]) begin
                r_xchk_armed[d]    <= 1'b0;
                r_xchk_conv_cnt[d] <= '0;
            end else if (r_xchk_armed[d]) begin
                r_xchk_conv_cnt[d] <= r_xchk_conv_cnt[d] +
                                      XCHK_CONVERGE_WD'(1);
            end

            if (w_xchk_agree[d]) begin
                r_xchk_reported[d] <= 1'b0;
            end else if (w_xchk_valid[d]) begin
                r_xchk_reported[d] <= 1'b1;
            end else if (I_ERR_CLEAR) begin
                r_xchk_reported[d] <= 1'b0;
            end

            // Gated on the enable, so this says "a comparison was made" rather
            // than "one would have been made had anyone asked for one".
            if (w_xchk_en[d] & w_xchk_settled[d]) begin
                r_xchk_compared[d] <= 1'b1;
            end
        end
    end
end

// -----------------------------------------------------------------------------
// Cross-check reporting.
//
// Deliberately separate from protocol reporting so neither domain can freeze
// or clear the other's capture. See DESIGN.md.
// -----------------------------------------------------------------------------
logic [XVIOL_CLASS_CNT-1:0] r_xchk_violation;
logic [VIOL_CNT_WD-1:0]     r_xchk_cnt;
logic                       r_xchk_trigger;

logic                       r_xchk_capture_valid;
logic [XVIOL_CODE_WD-1:0]   r_xchk_capture_code;
logic                       r_xchk_capture_die;
logic [XCHK_ST_WD-1:0]      r_xchk_capture_chk_st;
logic [XCHK_ST_WD-1:0]      r_xchk_capture_obs_st;
logic [FLIT_SEQ_WD-1:0]     r_xchk_capture_flit_seq;

// Sized as the protocol count is, so the two saturate the same way at any
// VIOL_CNT_WD.
logic                       w_xchk_any;
logic [XVIOL_CLASS_CNT-1:0] w_xchk_set;
logic [VIOL_INC_WD-1:0]     w_xchk_inc;
logic [VIOL_SUM_WD-1:0]     w_xchk_cnt_sum;
logic                       w_xchk_cap_die;

assign w_xchk_any     = |w_xchk_valid;
assign w_xchk_cap_die = w_xchk_valid[DIE_LP] ? 1'b0 : 1'b1;

always_comb begin
    w_xchk_set = '0;
    w_xchk_inc = '0;
    for (int unsigned d = 0; d < DIR_CNT; d++) begin
        if (w_xchk_valid[d]) begin
            w_xchk_set[w_xchk_code[d]] = 1'b1;
        end
        w_xchk_inc = w_xchk_inc + VIOL_INC_WD'(w_xchk_valid[d]);
    end
end

assign w_xchk_cnt_sum = VIOL_SUM_WD'(I_ERR_CLEAR ? '0 : r_xchk_cnt) +
                        VIOL_SUM_WD'(w_xchk_inc);

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_xchk_violation <= '0;
        r_xchk_cnt       <= '0;
        r_xchk_trigger   <= 1'b0;
    end else begin
        r_xchk_trigger <= w_xchk_any;
        if (w_xchk_any) begin
            r_xchk_violation <= (I_ERR_CLEAR ? '0 : r_xchk_violation) | w_xchk_set;
            r_xchk_cnt       <= (|w_xchk_cnt_sum[VIOL_SUM_WD-1:VIOL_CNT_WD])
                ? {VIOL_CNT_WD{1'b1}} : w_xchk_cnt_sum[VIOL_CNT_WD-1:0];
        end else if (I_ERR_CLEAR) begin
            r_xchk_violation <= '0;
            r_xchk_cnt       <= '0;
        end
    end
end

// Its own capture record, with its own freeze: were it the protocol capture
// record, a cross-check finding on a bench with untuned tolerances would
// freeze it before the run reached the protocol violation it was looking for.
always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_xchk_capture_valid    <= 1'b0;
        r_xchk_capture_code     <= '0;
        r_xchk_capture_die      <= 1'b0;
        r_xchk_capture_chk_st   <= '0;
        r_xchk_capture_obs_st   <= '0;
        r_xchk_capture_flit_seq <= '0;
    end else if (w_xchk_any && (!r_xchk_capture_valid || I_ERR_CLEAR)) begin
        r_xchk_capture_valid    <= 1'b1;
        r_xchk_capture_code     <= w_xchk_code[w_xchk_cap_die];
        r_xchk_capture_die      <= w_xchk_cap_die;
        r_xchk_capture_chk_st   <= w_xchk_chk_st[w_xchk_cap_die];
        r_xchk_capture_obs_st   <= w_xchk_obs_st[w_xchk_cap_die];
        // Not caused by a particular flit, so this says when rather than what.
        r_xchk_capture_flit_seq <= r_flit_seq[w_xchk_cap_die];
    end else if (I_ERR_CLEAR) begin
        r_xchk_capture_valid    <= 1'b0;
    end
end

assign O_XCHK_VIOLATION        = r_xchk_violation;
assign O_XCHK_TRIGGER          = r_xchk_trigger;
assign O_XCHK_CNT              = r_xchk_cnt;

assign O_XCHK_CAPTURE_VALID    = r_xchk_capture_valid;
assign O_XCHK_CAPTURE_CODE     = r_xchk_capture_code;
assign O_XCHK_CAPTURE_DIE      = r_xchk_capture_die;
assign O_XCHK_CAPTURE_CHK_ST   = r_xchk_capture_chk_st;
assign O_XCHK_CAPTURE_OBS_ST   = r_xchk_capture_obs_st;
assign O_XCHK_CAPTURE_FLIT_SEQ = r_xchk_capture_flit_seq;

assign O_XCHK_COMPARED         = r_xchk_compared;

// -----------------------------------------------------------------------------
// Simulation-only reporting, behind the same guard the rest of the RTL uses.
// NO FILE LOGGING: keeping this module free of file I/O is what keeps the
// synthesizable-subset claim honest. Unlike the rest of the RTL's ASSERTION_ON
// blocks this one does not $finish: the checker's purpose is to survive the
// violation and report it.
// -----------------------------------------------------------------------------
`ifdef ASSERTION_ON
// synopsys translate_off

aou_fdi_checker_violation_assertion:
    assert
        property (
            @(posedge I_CLK) disable iff (!I_RESETN)
            !w_viol_any
        )
        else begin
            $error("\n[%t] AOU_FDI_CHECKER: violation code=%0d dir=%0d seq=%0d g=%0d data=%010h",
                   $time, w_viol_code[w_viol_cap_dir], w_viol_cap_dir,
                   r_flit_seq[w_viol_cap_dir],
                   w_viol_granule_idx[w_viol_cap_dir],
                   w_viol_granule[w_viol_cap_dir]);
        end

aou_fdi_checker_xchk_assertion:
    assert
        property (
            @(posedge I_CLK) disable iff (!I_RESETN)
            !w_xchk_any
        )
        else begin
            // verilog_lint: waive line-length
            $error("\n[%t] AOU_FDI_CHECKER: cross-check code=%0d die=%0d seq=%0d checker={en,dis}=%02b observed={en,dis}=%02b",
                   $time, w_xchk_code[w_xchk_cap_die], w_xchk_cap_die,
                   r_flit_seq[w_xchk_cap_die],
                   w_xchk_chk_st[w_xchk_cap_die],
                   w_xchk_obs_st[w_xchk_cap_die]);
        end

// synopsys translate_on
`endif

endmodule
