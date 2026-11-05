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
//  Module     : packet_def_pkg
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

package packet_def_pkg;

parameter MSG_MISC          = 4'b0000;
parameter MSG_WR_REQ        = 4'b0001;
parameter MSG_RD_REQ        = 4'b0010;
parameter MSG_WR_DATA       = 4'b0011;
parameter MSG_WRF_DATA      = 4'b0110;
parameter MSG_RD_DATA       = 4'b0100;
parameter MSG_WR_RESP       = 4'b0101;

parameter AW_G              = 3;
parameter W256b_G           = 8;
parameter W512b_G           = 15;
parameter W1024b_G          = 30;
parameter WF256b_G          = 7;
parameter WF512b_G          = 14;
parameter WF1024b_G         = 27;
parameter B_G               = 1;
parameter AR_G              = 3;
parameter R256b_G           = 8;
parameter R512b_G           = 14;
parameter R1024b_G          = 27;
// Misc messages. The ActivateReq is four granules in AoU v0.8 (Table
// "Activation Req Message Format"): granule 0 carries MSGTYPE, MISCOP,
// ACTIVATIONOP, RsvdZero3 and RP0's ProfileID5/ProfileRev5/ProfileOpt16;
// granules 1-3 carry RsvdZero14 and the same three fields for RP1-RP3. Every
// other Activation opcode and the CrdtGrant keep their lengths.
parameter ACT_REQ_G         = 4;
parameter ACT_OTHER_G       = 1;
parameter CRDTGRANT_G       = 2;
parameter PROFILE_WD        = 26;       // {ProfileID[4:0], ProfileRev[4:0], ProfileOpt[15:0]}
parameter ACTOP_ACTIVATE_REQ = 4'b0000;

// ----------------------------------------------------------------------------
// FDI configuration selectors.
//
// FDI_CONFIG is a single integer parameter on AOU_TOP / AOU_CORE_TOP that
// replaces the legacy FDI_IF_WD0 / FDI_IF_WD1 width pair. The selected value
// determines the internally-derived FDI_IF_WD0 (always-present PHY0) and
// FDI_IF_WD1 (PHY1, gated by `+define+TWO_PHY`) widths in bits.
//
// SP_* values describe a single-PHY configuration (no `+define+TWO_PHY`).
// TP_* values describe a two-PHY configuration and require `+define+TWO_PHY`
// at compile time so the second-PHY ports physically exist.
//
// Width mapping (also documented in DOC/integration_guide/integration_guide.md):
//   FDI_CFG_SP_32B      -> WD0=256,  WD1=512   (single PHY, RX accumulates two
//                                                256b phases into 512b internally)
//   FDI_CFG_SP_64B      -> WD0=512,  WD1=512   (single PHY)
//   FDI_CFG_SP_128B     -> WD0=1024, WD1=1024  (single PHY)
//   FDI_CFG_TP_32B_64B  -> WD0=256,  WD1=512   (two PHY)
//   FDI_CFG_TP_64B_128B -> WD0=512,  WD1=1024  (two PHY)
//   FDI_CFG_SP_256B     -> WD0=2048, WD1=2048  (single PHY, one 256 B flit per
//                                                beat; pl_flit_cancel cancels the
//                                                whole flit)
//
// Note: SP_32B and TP_32B_64B produce identical width pairs; only
// `+define+TWO_PHY` distinguishes them. Consistency between FDI_CONFIG and
// the presence/absence of `+define+TWO_PHY` is the integrator's
// responsibility; no in-RTL elaboration check is added.
// ----------------------------------------------------------------------------
parameter int FDI_CFG_SP_32B      = 0;
parameter int FDI_CFG_SP_64B      = 1;
parameter int FDI_CFG_SP_128B     = 2;
parameter int FDI_CFG_TP_32B_64B  = 3;
parameter int FDI_CFG_TP_64B_128B = 4;
parameter int FDI_CFG_SP_256B     = 5;

parameter logic [7:0] CREDIT_TABLE [7:0] = '{
    8'd128,
    8'd64,
    8'd32,
    8'd16,
    8'd8,
    8'd4,
    8'd1,
    8'd0
};

//5B per Granule
typedef struct  packed {
    logic [31:0]                   others_1;
    logic [3:0]                    msg_type;
    logic [1:0]                    rp;
    logic [1:0]                    others;
} st_g_packet;



typedef struct packed {
    logic [1:0]                     rp;
    logic [1:0]                     wrespcred;
    logic [2:0]                     rdatacred;
    logic [2:0]                     wdatacred;
    logic [2:0]                     rreqcred;
    logic [2:0]                     wreqcred;
} st_msg_credit_packet;


typedef struct packed {
    logic [15:0]                    rsvd;

    logic                           wrespcred0_0;
    logic [1:0]                     wrespcred1;
    logic [1:0]                     wrespcred2;
    logic [1:0]                     wrespcred3;
    logic                           rsvd_0; 

    logic                           rdatacred1_0;
    logic [2:0]                     rdatacred2;
    logic [2:0]                     rdatacred3;
    logic                           wrespcred0_1;

    logic [2:0]                     wdatacred3;
    logic [2:0]                     rdatacred0;
    logic [1:0]                     rdatacred1_1;

    logic [1:0]                     wdatacred0_0;
    logic [2:0]                     wdatacred1;
    logic [2:0]                     wdatacred2;

    logic                           rreqcred1_0;
    logic [2:0]                     rreqcred2;
    logic [2:0]                     rreqcred3;
    logic                           wdatacred0_1;

    logic [2:0]                     wreqcred3;
    logic [2:0]                     rreqcred0;
    logic [1:0]                     rreqcred1_1;

    logic [1:0]                     wreqcred0_0;
    logic [2:0]                     wreqcred1;
    logic [2:0]                     wreqcred2;

    logic [3:0]                     msg_type;
    logic [2:0]                     misc_op;
    logic                           wreqcred0_1;
} st_misc_grantcredit_packet;

typedef struct packed {
    logic [40+33-2:0]               misc_payload;
    logic [3:0]                     msg_type;
    logic [2:0]                     misc_op;
    logic                           rsvd;
} st_misc_packet;                   //misc packet including misc grantcredit_packet

// First granule of an Activation message, in wire byte order (byte 0 in bits
// [7:0]). property_req is the v0.7 PropertyReq position: in AoU v0.8 it is a
// RsvdZero bit, and in an ActivateReq the 29 bits after ACTIVATIONOP are
// RsvdZero3 followed by RP0's ProfileID/Rev/Opt (see ACT_REQ_G), which the
// TX and RX cores handle in spec bit order ({<<8{granule}}) rather than through
// this struct. The DUT still sets property_req on the DeactivateReq that
// AOU_CON0.DEACTIVATE_FORCE sends (MAS 7.1).
typedef struct packed {
    logic [23:0]                    rsvd;
    logic [2:0]                     activation_op_0;
    logic                           property_req;
    logic [3:0]                     rsvd_0;
    logic [3:0]                     msg_type;
    logic [2:0]                     misc_op;
    logic                           activation_op_1;
} st_misc_activation_packet;

typedef struct packed {
    logic [0:7][7:0]                awaddr;
    logic [3:0]                     awcache;
    logic [3:0]                     awqos;
    logic [7:0]                     awlen;
    logic [1:0]                     awid_0;
    logic [2:0]                     awsize;
    logic [2:0]                     awprot;
    logic [7:0]                     awid_1;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic                           rsvd;
    logic                           awlock;
} st_write_req_packet_tmp;
  
typedef struct packed {
    logic [15:0]                    flex;
    logic                           rsvd;
    logic [3:0]                     awqos;
    logic [2:0]                     awprot;
    logic [3:0]                     awcache;
    logic                           awlock;
    logic [2:0]                     awsize;
    logic [7:0]                     awlen;
    logic [63:0]                    awaddr;
    logic [9:0]                     awid;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_write_req_packet;

typedef struct packed {
    logic [0:7][7:0]                araddr;
    logic [3:0]                     arcache;
    logic [3:0]                     arqos;
    logic [7:0]                     arlen;
    logic [1:0]                     arid_0;
    logic [2:0]                     arsize;
    logic [2:0]                     arprot;
    logic [7:0]                     arid_1;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic                           rsvd;
    logic                           arlock;
} st_read_req_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic                           rsvd;
    logic [3:0]                     arqos;
    logic [2:0]                     arprot;
    logic [3:0]                     arcache;
    logic                           arlock;
    logic [2:0]                     arsize;
    logic [7:0]                     arlen;
    logic [63:0]                    araddr;
    logic [9:0]                     arid;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_read_req_packet;

typedef struct packed {
    logic [7:0]                     rsvd;
    logic [0:3][7:0]                wstrb;
    logic [0:31][7:0]               wdata;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     dlength;
} st_write_data256_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [7:0]                     rsvd;
    logic [31:0]                    wstrb;
    logic [255:0]                   wdata;
    logic [1:0]                     dlength;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_write_data256_packet;

typedef struct packed {
    logic [0:7][7:0]                wstrb;
    logic [0:63][7:0]               wdata;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     dlength;
} st_write_data512_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [63:0]                    wstrb;
    logic [511:0]                   wdata;
    logic [1:0]                     dlength;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_write_data512_packet;

typedef struct packed {
    logic [23:0]                    rsvd;
    logic [0:15][7:0]               wstrb;
    logic [0:127][7:0]              wdata;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     dlength;
} st_write_data1024_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [23:0]                    rsvd;
    logic [127:0]                   wstrb;
    logic [1023:0]                  wdata;
    logic [1:0]                     dlength;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_write_data1024_packet;

typedef struct packed {
    logic [23:0]                    rsvd_0;
    logic [0:31][7:0]               rdata;
    logic [1:0]                     rid_0;
    logic [1:0]                     rresp;
    logic                           rlast;
    logic [2:0]                     rsvd_1;
    logic [7:0]                     rid_1;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     dlength;
} st_read_data256_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [26:0]                    rsvd;
    logic                           rlast;
    logic [255:0]                   rdata;
    logic [1:0]                     rresp;
    logic [9:0]                     rid;
    logic [1:0]                     dlength;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_read_data256_packet;

typedef struct packed {
    logic [7:0]                     rsvd_0;
    logic [0:63][7:0]               rdata;
    logic [1:0]                     rid_0;
    logic [1:0]                     rresp;
    logic                           rlast;
    logic [2:0]                     rsvd_1;
    logic [7:0]                     rid_1;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     dlength;
} st_read_data512_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [10:0]                    rsvd;
    logic                           rlast;
    logic [511:0]                   rdata;
    logic [1:0]                     rresp;
    logic [9:0]                     rid;
    logic [1:0]                     dlength;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_read_data512_packet;

typedef struct packed {
    logic [15:0]                    rsvd_0;
    logic [0:127][7:0]              rdata;
    logic [1:0]                     rid_0;
    logic [1:0]                     rresp;
    logic                           rlast;
    logic [2:0]                     rsvd_1;
    logic [7:0]                     rid_1;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     dlength;
} st_read_data1024_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [18:0]                    rsvd;
    logic                           rlast;
    logic [1023:0]                  rdata;
    logic [1:0]                     rresp;
    logic [9:0]                     rid;
    logic [1:0]                     dlength;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_read_data1024_packet;

typedef struct packed {
    logic [1:0]                     bid_0;
    logic [1:0]                     bresp;
    logic [3:0]                     rsvd_0;
    logic [7:0]                     bid_1;
    logic [7:0]                     flex_lo;    // message byte 2 = FLEX[7:0]
    logic [7:0]                     flex_hi;    // message byte 1 = FLEX[15:8]
    logic [3:0]                     msg_type;
    logic [1:0]                     rp;
    logic [1:0]                     rsvd_1;
} st_write_resp_packet_tmp;

typedef struct packed {
    logic [15:0]                    flex;
    logic [5:0]                     rsvd;
    logic [1:0]                     bresp;
    logic [9:0]                     bid;
    logic [1:0]                     rp;
    logic [3:0]                     msg_type;
} st_write_resp_packet;

//Function for parameter calculation
function automatic int unsigned max2(input int unsigned a, input int unsigned b);
    if(a>b)
        max2 = a;
    else
        max2 = b;
endfunction

function automatic int unsigned max4 (input int unsigned a, input int unsigned b, input int unsigned c, input int unsigned d);
    int temp0, temp1;
    begin
        temp0 = max2(a, b);
        temp1 = max2(c, d);
        max4  = max2(temp0, temp1);
    end
endfunction

endpackage
