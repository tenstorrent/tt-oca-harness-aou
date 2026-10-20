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
//  Module     : aou_fdi_wire_pkg
//  Version    : 1.02
//  Date       : 26-10-20
//
// *****************************************************************************
//
//  The AoU v0.7 wire format as AOU_FDI_CHECKER reads it: flit geometry, the
//  protocol header, the message encodings and lengths, and the two Misc
//  message layouts. Every value cites the v0.7 section or table it comes from
//  (the revision the design implements; v0.8 renumbers 5.7-5.9 to 5.8-5.10,
//  6.3 to 6.4 and Tables 17-26 to 16-25) and is shared with nothing in the
//  design: the checker judges the wire against the specification, so it must
//  not learn the wire from the RTL it judges.
//
//  Message layouts follow 5.7's convention -- bytes count up, bits count down,
//  fields MSB-first -- through wire_bit(), so a field is stated as the stream
//  bits it occupies rather than as byte arithmetic.
//
//  See DESIGN.md "The wire-format package".
//
// *****************************************************************************

`timescale 1ns/1ps

package aou_fdi_wire_pkg;

// -----------------------------------------------------------------------------
// Flit geometry (4.2, Figure 4). A latency-optimized flit is 256 bytes: four
// 64-byte quarters, each a two-byte protocol-header pair (or link-layer bytes),
// twelve five-byte granules and a second two-byte pair.
// -----------------------------------------------------------------------------
localparam int FLIT_BYTES       = 256;
localparam int FLIT_WD          = FLIT_BYTES * 8;
localparam int GRANULE_BYTES    = 5;
localparam int GRANULE_WD       = GRANULE_BYTES * 8;
localparam int GRANULE_CNT      = 48;
localparam int QUARTER_BYTES    = 64;
localparam int GRANULE_PER_QTR  = 12;
localparam int QTR_HDR_BYTES    = 2;

// Flit byte of granule g's first byte.
function automatic int unsigned granule_byte(input int unsigned g);
    return QTR_HDR_BYTES + QUARTER_BYTES * (g / GRANULE_PER_QTR)
                         + GRANULE_BYTES * (g % GRANULE_PER_QTR);
endfunction

// -----------------------------------------------------------------------------
// Link-layer flit header (UCIe 3.0 Table 3-4, Format 6, Streaming protocol):
// bits [7:6] of flit byte 0 are the Protocol Identifier, 00b being a D2D
// Adapter NOP flit, which the protocol layer must discard if it arrives
// uncancelled and must never send.
// -----------------------------------------------------------------------------
localparam int FLIT_HDR_BYTE    = 0;
localparam int FLIT_PID_LSB     = 6;
localparam int FLIT_PID_WD      = 2;
localparam logic [FLIT_PID_WD-1:0] FLIT_PID_NOP = 2'b00;

// -----------------------------------------------------------------------------
// Protocol header (4.3, Figure 5). Ten bytes at the quarter boundaries: FDId
// and MsgStart[3:0] in byte 62, MsgStart[11:4] in 63, [15:12] in the high
// nibble of 64, [23:16] in 65, MsgCredit in 128-129, then the same MsgStart
// pattern for [47:24] in bytes 190-193. The low nibbles not named here are Rsvd.
// -----------------------------------------------------------------------------
localparam int FDID_BYTE        = 62;
localparam int FDID_WD          = 2;
localparam int MSG_CREDIT_BYTE  = 128;
localparam int MSG_CREDIT_WD    = 16;

function automatic logic [GRANULE_CNT-1:0] msg_start_of(input logic [FLIT_WD-1:0] flit);
    msg_start_of[ 3: 0] = flit[ 62*8 + 4 +: 4];
    msg_start_of[11: 4] = flit[ 63*8     +: 8];
    msg_start_of[15:12] = flit[ 64*8 + 4 +: 4];
    msg_start_of[23:16] = flit[ 65*8     +: 8];
    msg_start_of[27:24] = flit[190*8 + 4 +: 4];
    msg_start_of[35:28] = flit[191*8     +: 8];
    msg_start_of[39:36] = flit[192*8 + 4 +: 4];
    msg_start_of[47:40] = flit[193*8     +: 8];
endfunction

// MsgCredit sub-fields (Table 17), as bit offsets within the 16-bit field.
localparam int MC_WREQ_LSB      = 0;
localparam int MC_RREQ_LSB      = 3;
localparam int MC_WDATA_LSB     = 6;
localparam int MC_RDATA_LSB     = 9;
localparam int MC_WRESP_LSB     = 12;
localparam int MC_RP_LSB        = 14;

// -----------------------------------------------------------------------------
// The 5.7 stream convention. Stream bit s of a message -- s = 0 is the first
// bit on the wire -- is bit 7 - s%8 of byte s/8. With byte i occupying bits
// [i*8 +: 8] of a packed message, that is packed bit 8*(s/8) + 7 - s%8.
// -----------------------------------------------------------------------------
function automatic int unsigned wire_bit(input int unsigned s);
    return 8 * (s / 8) + 7 - (s % 8);
endfunction

// A mask over one granule of the stream bits first..last inclusive.
function automatic logic [GRANULE_WD-1:0] granule_stream_mask(input int unsigned first,
                                                             input int unsigned last);
    granule_stream_mask = '0;
    for (int unsigned s = first; s <= last; s++) begin
        granule_stream_mask[wire_bit(s)] = 1'b1;
    end
endfunction

// -----------------------------------------------------------------------------
// The first byte of every message (5.7, Figures 6-20). MSGTYPE is stream bits
// 0-3, so the high nibble; what follows depends on the type: RP (5.2.2) on the
// credited messages, with DLENGTH (5.4) below it on the data messages, MISCOP
// (5.6) on Misc.
// -----------------------------------------------------------------------------
localparam int MSGTYPE_WD       = 4;
localparam int MSGTYPE_LSB      = 4;
localparam int RP_WD            = 2;
localparam int RP_LSB           = 2;
localparam int DLENGTH_WD       = 2;
localparam int DLENGTH_LSB      = 0;
localparam int MISCOP_WD        = 3;
localparam int MISCOP_LSB       = 1;

// MSGTYPE (Table 1). 0b0111 to 0b1111 are reserved.
localparam logic [MSGTYPE_WD-1:0] MSG_MISC      = 4'b0000;
localparam logic [MSGTYPE_WD-1:0] MSG_WR_REQ    = 4'b0001;
localparam logic [MSGTYPE_WD-1:0] MSG_RD_REQ    = 4'b0010;
localparam logic [MSGTYPE_WD-1:0] MSG_WR_DATA   = 4'b0011;
localparam logic [MSGTYPE_WD-1:0] MSG_RD_DATA   = 4'b0100;
localparam logic [MSGTYPE_WD-1:0] MSG_WR_RESP   = 4'b0101;
localparam logic [MSGTYPE_WD-1:0] MSG_WRF_DATA  = 4'b0110;

// MISCOP (Table 15). Every other encoding is reserved.
localparam logic [MISCOP_WD-1:0]  MISCOP_ACTIVATION = 3'b010;
localparam logic [MISCOP_WD-1:0]  MISCOP_CRDTGRANT  = 3'b100;

// DLENGTH (5.4). 0b11 is unassigned; no compliant sender emits it.
localparam logic [DLENGTH_WD-1:0] DLENGTH_256B     = 2'b00;
localparam logic [DLENGTH_WD-1:0] DLENGTH_512B     = 2'b01;
localparam logic [DLENGTH_WD-1:0] DLENGTH_1024B    = 2'b10;
localparam logic [DLENGTH_WD-1:0] DLENGTH_RESERVED = 2'b11;

// -----------------------------------------------------------------------------
// Message lengths in granules (Tables 2-13, 19, 26). Every message is a fixed
// number of granules under the Base Profile, which ignores PROFEXTLEN (5.8;
// v0.8 removes PROFEXTLEN).
// -----------------------------------------------------------------------------
localparam int AW_G         = 3;
localparam int AR_G         = 3;
localparam int B_G          = 1;
localparam int W256B_G      = 8;
localparam int W512B_G      = 15;
localparam int W1024B_G     = 30;
localparam int WF256B_G     = 7;
localparam int WF512B_G     = 14;
localparam int WF1024B_G    = 27;
localparam int R256B_G      = 8;
localparam int R512B_G      = 14;
localparam int R1024B_G     = 27;
localparam int MISC_ACT_G   = 1;
localparam int MISC_CG_G    = 2;
// The longest of them, which sizes the message-start carry.
localparam int MAX_MSG_G    = W1024B_G;

// -----------------------------------------------------------------------------
// RsvdZero in the first granule of the credited messages (Tables 2, 3, 10-13;
// Figures 6, 7, 14-17), as stream bits after MSGTYPE and RP. WriteReq and
// ReadReq pad one bit before AWLOCK / PROFEXTLEN; WriteResp pads two before
// PROFEXTLEN and four after BRESP; ReadData pads three after RLAST. The
// padding at the tail of the data messages lies in a later granule and is not
// stated here. PROF and PROFEXTLEN are not reserved: the Base Profile ignores
// them (5.8).
// -----------------------------------------------------------------------------
localparam int PROFEXTLEN_WD    = 4;
localparam int PROF_WD          = 12;
localparam int AXI_ID_WD        = 10;
localparam int AXI_RESP_WD      = 2;

localparam int REQ_RSVD_S       = MSGTYPE_WD + RP_WD;                       // 6
localparam int B_RSVD_HEAD_S    = REQ_RSVD_S;                               // 6-7
localparam int B_RSVD_TAIL_S    = B_RSVD_HEAD_S + 2 + PROFEXTLEN_WD + PROF_WD
                                + AXI_ID_WD + AXI_RESP_WD;                  // 36-39
localparam int R_RSVD_S         = MSGTYPE_WD + RP_WD + DLENGTH_WD + PROFEXTLEN_WD
                                + PROF_WD + AXI_ID_WD + AXI_RESP_WD + 1;     // 37-39

localparam logic [GRANULE_WD-1:0] REQ_RSVD_MASK =
    granule_stream_mask(REQ_RSVD_S, REQ_RSVD_S);
localparam logic [GRANULE_WD-1:0] B_RSVD_MASK =
    granule_stream_mask(B_RSVD_HEAD_S, B_RSVD_HEAD_S + 1) |
    granule_stream_mask(B_RSVD_TAIL_S, GRANULE_WD - 1);
localparam logic [GRANULE_WD-1:0] R_RSVD_MASK =
    granule_stream_mask(R_RSVD_S, GRANULE_WD - 1);

// -----------------------------------------------------------------------------
// Activation message (8.3.4, Table 26, Figure 19). After MSGTYPE and MISCOP:
// ACTIVATIONOP at stream bits 7-10, PROPERTYREQ at 11, RsvdZero at 12-39.
// -----------------------------------------------------------------------------
localparam int ACTOP_WD         = 4;
localparam int ACTOP_S          = MSGTYPE_WD + MISCOP_WD;
localparam int PROPREQ_S        = ACTOP_S + ACTOP_WD;
localparam int ACT_RSVD_FIRST_S = PROPREQ_S + 1;

// ACTIVATIONOP (Table 27). 0b0100 and above are reserved.
localparam logic [ACTOP_WD-1:0]  ACTOP_ACTIVATE_REQ   = 4'd0;
localparam logic [ACTOP_WD-1:0]  ACTOP_ACTIVATE_ACK   = 4'd1;
localparam logic [ACTOP_WD-1:0]  ACTOP_DEACTIVATE_REQ = 4'd2;
localparam logic [ACTOP_WD-1:0]  ACTOP_DEACTIVATE_ACK = 4'd3;

function automatic logic [ACTOP_WD-1:0] actop_of(input logic [GRANULE_WD-1:0] g);
    for (int unsigned k = 0; k < ACTOP_WD; k++) begin
        actop_of[ACTOP_WD-1-k] = g[8 * ((ACTOP_S + k) / 8) + 7 - ((ACTOP_S + k) % 8)];
    end
endfunction

localparam int PROPREQ_BIT = wire_bit(PROPREQ_S);

localparam logic [GRANULE_WD-1:0] ACT_RSVD_MASK =
    granule_stream_mask(ACT_RSVD_FIRST_S, GRANULE_WD - 1);

// -----------------------------------------------------------------------------
// Credit encoding (Table 18) and the CrdtGrant message (6.3.2, Table 19,
// Figure 20). After MSGTYPE and MISCOP the grant carries, for each class in
// the order WREQ, RREQ, WDATA, RDATA, WRESP and for planes 0..3 within each,
// one credit field -- three bits, except WRESP at two -- then 17 bits RsvdZero.
// -----------------------------------------------------------------------------
localparam int RP_WIRE_CNT  = 1 << RP_WD;
localparam int CRD_CLS_CNT  = 5;
localparam int CRD_AW       = 0;
localparam int CRD_AR       = 1;
localparam int CRD_W        = 2;
localparam int CRD_R        = 3;
localparam int CRD_B        = 4;
localparam int CRD_ENC_WD   = 3;
localparam int CRD_ENC_B_WD = 2;

localparam logic [7:0] CREDIT_TABLE [8] = '{8'd0, 8'd1, 8'd4, 8'd8,
                                           8'd16, 8'd32, 8'd64, 8'd128};

localparam int CG_MSG_WD    = MISC_CG_G * GRANULE_WD;
localparam int CG_FIELDS_S  = MSGTYPE_WD + MISCOP_WD;
// The WRESP fields follow the sixteen three-bit ones; RsvdZero follows them.
localparam int CG_B_FIELDS_S   = CG_FIELDS_S + (CRD_CLS_CNT - 1) * RP_WIRE_CNT * CRD_ENC_WD;
localparam int CG_RSVD_FIRST_S = CG_B_FIELDS_S + RP_WIRE_CNT * CRD_ENC_B_WD;

// The grant's twenty credit fields, indexed [plane][class], each zero-extended
// to CRD_ENC_WD so that one table serves WRESP as well. Field c of plane q
// begins at stream bit CG_FIELDS_S + (c*4 + q)*3 for the three-bit classes and
// after all of those, at plane q * 2, for WRESP; bit k of a field is stream bit
// start + k, MSB first. Written as arithmetic on the loop variables rather
// than as function calls so that every tool folds it at elaboration.
function automatic logic [RP_WIRE_CNT-1:0][CRD_CLS_CNT-1:0][CRD_ENC_WD-1:0]
    decode_credit_grant(input logic [CG_MSG_WD-1:0] grant);
    for (int unsigned c = 0; c < CRD_CLS_CNT - 1; c++) begin
        for (int unsigned q = 0; q < RP_WIRE_CNT; q++) begin
            for (int unsigned k = 0; k < CRD_ENC_WD; k++) begin
                decode_credit_grant[q][c][CRD_ENC_WD-1-k] =
                    grant[8 * ((CG_FIELDS_S + (c * RP_WIRE_CNT + q) * CRD_ENC_WD + k) / 8)
                          + 7 - ((CG_FIELDS_S + (c * RP_WIRE_CNT + q) * CRD_ENC_WD + k) % 8)];
            end
        end
    end
    for (int unsigned q = 0; q < RP_WIRE_CNT; q++) begin
        decode_credit_grant[q][CRD_B] = '0;
        for (int unsigned k = 0; k < CRD_ENC_B_WD; k++) begin
            decode_credit_grant[q][CRD_B][CRD_ENC_B_WD-1-k] =
                grant[8 * ((CG_B_FIELDS_S + q * CRD_ENC_B_WD + k) / 8)
                      + 7 - ((CG_B_FIELDS_S + q * CRD_ENC_B_WD + k) % 8)];
        end
    end
endfunction

// The RsvdZero tail lies wholly in the grant's second granule.
localparam logic [GRANULE_WD-1:0] CG_RSVD_G1_MASK =
    granule_stream_mask(CG_RSVD_FIRST_S - GRANULE_WD, GRANULE_WD - 1);

endpackage
