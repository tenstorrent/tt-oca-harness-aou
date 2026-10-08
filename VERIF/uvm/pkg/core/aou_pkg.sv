// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 VNCHIPLabs
// *****************************************************************************
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
//  Package    : aou_pkg
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
`timescale 1ns/1ps
package aou_pkg;

  // AoU wire-format fields and pack/unpack helpers used by the FDI monitor,
  // remote peer, and deterministic multi-RP smoke. Message bit layouts
  // follow AoU standard v0.7, including the
  // message tables and figures cited in the protocol definitions below.

  // ---------------------------------------------------------------------
  // Flit layout dimensions from the AoU wire format.
  // ---------------------------------------------------------------------
  localparam int FLIT_BYTES           = 256;
  localparam int GRANULE_BYTES        = 5;
  localparam int GRANULES_PER_GROUP   = 12;
  localparam int GROUP_STRIDE_BYTES   = 64;
  localparam int FIRST_GROUP_OFFSET   = 2;
  localparam int NUM_GRANULES         = 48;

  // PH B0..B9 occupy protocol-header and CRC gaps between granule groups:
  // four bytes after group 0, two after group 1, and four after group 2.
  localparam int PH_BYTE[10] = '{62, 63, 64, 65, 128, 129, 190, 191, 192, 193};

  // One 64-byte group starts with its preceding header/gap area, followed
  // by twelve consecutive five-byte granules. The equation follows those
  // layout dimensions directly: offset = first group start + group stride
  // + granule position within the group.
  function automatic int unsigned granule_byte_pos(input int unsigned g);
    automatic int unsigned group_index = g / GRANULES_PER_GROUP;
    automatic int unsigned index_in_group = g % GRANULES_PER_GROUP;
    return FIRST_GROUP_OFFSET + group_index * GROUP_STRIDE_BYTES +
           index_in_group * GRANULE_BYTES;
  endfunction
  // ---------------------------------------------------------------------
  // Message type and sub-opcode encodings used by the layouts below.
  // ---------------------------------------------------------------------
  typedef enum logic [3:0] {
    MSGTYPE_MISC          = 4'b0000,
    MSGTYPE_WRITEREQ      = 4'b0001,
    MSGTYPE_READREQ       = 4'b0010,
    MSGTYPE_WRITEDATA     = 4'b0011,
    MSGTYPE_READDATA      = 4'b0100,
    MSGTYPE_WRITERESP     = 4'b0101,
    MSGTYPE_WRITEDATAFULL = 4'b0110,
    // Not a real wire encoding (the protocol reserves 0b0111-0b1111). This
    // item carries the protocol header's MsgCredit field (spec Section 6.3.1)
    // from the FDI monitor to the smoke peer, since MsgCredit
    // is per-flit header state, not a message that starts at a granule.
    MSGTYPE_HDRCREDIT      = 4'b1111
  } msgtype_e;

  typedef enum logic [2:0] {
    MISCOP_ACTIVATION = 3'b010,
    MISCOP_CRDTGRANT  = 3'b100
  } miscop_e;

  typedef enum logic [3:0] {
    ACTOP_ACTIVATE_REQ   = 4'b0000,
    ACTOP_ACTIVATE_ACK   = 4'b0001,
    ACTOP_DEACTIVATE_REQ = 4'b0010,
    ACTOP_DEACTIVATE_ACK = 4'b0011
  } activationop_e;

  localparam logic [1:0] DLENGTH_256B = 2'b00;
  localparam logic [1:0] DLENGTH_512B = 2'b01;
  localparam logic [1:0] DLENGTH_1024B = 2'b10;

  // The documented public smoke uses RP_COUNT=4, AXI_DATA_BYTES=64
  // (AXI_DATA_W=512), and FDI_CONFIG=SP64B (FDI_DATA_W=512). The width
  // calculations below keep the message helpers internally consistent.
`ifdef AOU_AXI_DATA_BYTES
  localparam int unsigned AXI_DATA_BYTES = `AOU_AXI_DATA_BYTES; // from build config
`else
  localparam int unsigned AXI_DATA_BYTES = 64; // 32 (256b) / 64 (512b) / 128 (1024b)
`endif
  localparam int unsigned AXI_DATA_W     = AXI_DATA_BYTES * 8;
`ifdef AOU_FDI_DATA_W
  localparam int unsigned FDI_DATA_W     = `AOU_FDI_DATA_W;
`else
  localparam int unsigned FDI_DATA_W     = AXI_DATA_W;
`endif
  localparam int unsigned FDI_DATA_BYTES = FDI_DATA_W / 8;
`ifdef AOU_RP_COUNT
  localparam int unsigned RP_COUNT_CFG = `AOU_RP_COUNT;
`else
  localparam int unsigned RP_COUNT_CFG = 4;
`endif
  localparam logic [2:0]  AXI_SIZE       = 3'($clog2(AXI_DATA_BYTES)); // AWSIZE/ARSIZE encoding
  localparam logic [1:0]  AXI_DLENGTH    = (AXI_DATA_BYTES == 32) ? DLENGTH_256B :
                                            (AXI_DATA_BYTES == 64) ? DLENGTH_512B :
                                                                      DLENGTH_1024B;

  // Granule count for a data-carrying message, by type and DLENGTH. Values
  // follow the AoU v0.7 message layouts.
  // Used by the FDI monitor to advance over data messages of any supported
  // type and length.
  function automatic int unsigned data_msg_granules(
      input logic [3:0] mtype, input logic [1:0] dlength);
    case (mtype)
      MSGTYPE_WRITEDATA:     case (dlength) 2'd0: return 8;  2'd1: return 15; 2'd2: return 30; default: return 0; endcase
      MSGTYPE_READDATA:      case (dlength) 2'd0: return 8;  2'd1: return 14; 2'd2: return 27; default: return 0; endcase
      MSGTYPE_WRITEDATAFULL: case (dlength) 2'd0: return 7;  2'd1: return 14; 2'd2: return 27; default: return 0; endcase
      default: return 0;
    endcase
  endfunction

  // Exact granule consumption for one complete message. This returns the
  // encoded-message cost, not the nearest representable CrdtGrant value.
  function automatic int unsigned message_granule_cost(
      input logic [3:0] mtype, input logic [1:0] dlength = AXI_DLENGTH);
    case (mtype)
      MSGTYPE_WRITEREQ, MSGTYPE_READREQ: return 3;
      MSGTYPE_WRITEDATA, MSGTYPE_WRITEDATAFULL, MSGTYPE_READDATA:
        return data_msg_granules(mtype, dlength);
      MSGTYPE_WRITERESP: return 1;
      MSGTYPE_MISC: return 0;
      default: return 0;
    endcase
  endfunction

  // CrdtGrant fields use the discrete Table-18 encodings.  Keep the
  // round-up helpers next to the encoder so a policy cannot accidentally
  // pass an arbitrary integer (for example 27) and silently turn it into a
  // different wire grant.
  function automatic int unsigned credit_round_up3(input int unsigned n);
    if (n == 0) return 0;
    if (n <= 1) return 1;
    if (n <= 4) return 4;
    if (n <= 8) return 8;
    if (n <= 16) return 16;
    if (n <= 32) return 32;
    if (n <= 64) return 64;
    return 128;
  endfunction

  function automatic int unsigned credit_round_up2(input int unsigned n);
    if (n == 0) return 0;
    if (n <= 1) return 1;
    if (n <= 4) return 4;
    return 8;
  endfunction

  function automatic bit credit_is_legal3(input int unsigned n);
    return (n == 0 || n == 1 || n == 4 || n == 8 || n == 16 ||
            n == 32 || n == 64 || n == 128);
  endfunction

  function automatic bit credit_is_legal2(input int unsigned n);
    return (n == 0 || n == 1 || n == 4 || n == 8);
  endfunction

  // *CRED encodings, Table 18 (3-bit form; 2-bit WRESPCRED uses the first
  // four entries only).
  function automatic logic [2:0] credit_enc3(input int unsigned n);
    case (n)
      0:  return 3'b000;  1:  return 3'b001;  4:  return 3'b010;
      8:  return 3'b011;  16: return 3'b100;  32: return 3'b101;
      64: return 3'b110;  128: return 3'b111;
      default: begin
        $fatal(1, "illegal 3-bit credit value %0d", n);
        return 'x;
      end
    endcase
  endfunction

  function automatic logic [1:0] credit_enc2(input int unsigned n);
    case (n)
      0: return 2'b00;  1: return 2'b01;
      4: return 2'b10;  8: return 2'b11;
      default: begin
        $fatal(1, "illegal 2-bit credit value %0d", n);
        return 'x;
      end
    endcase
  endfunction

  function automatic int unsigned credit_dec3(input logic [2:0] enc);
    case (enc)
      3'b000: return 0;   3'b001: return 1;   3'b010: return 4;
      3'b011: return 8;   3'b100: return 16;  3'b101: return 32;
      3'b110: return 64;  default: return 128; // 3'b111
    endcase
  endfunction

  function automatic int unsigned credit_dec2(input logic [1:0] enc);
    case (enc)
      2'b00: return 0;   2'b01: return 1;
      2'b10: return 4;   default: return 8;
    endcase
  endfunction

  // Inverse of pack_crdtgrant().  The CrdtGrant wire layout is not a
  // header-first concatenation: the two transmitted granules are byte
  // reversed and the grant fields are split across both struct halves.
  // Keep this inverse beside the encoder so passive credit accounting never
  // has to reconstruct a grant from a driver-side object or an RP0-only
  // shortcut.
  function automatic void unpack_crdtgrant(
      input logic [1:0][39:0] g,
      output int unsigned wreq_n[4],  output int unsigned rreq_n[4],
      output int unsigned wdata_n[4], output int unsigned rdata_n[4],
      output int unsigned wresp_n[4], output bit rsvd_zero,
      output logic [2:0] wreq_enc[4],  output logic [2:0] rreq_enc[4],
      output logic [2:0] wdata_enc[4], output logic [2:0] rdata_enc[4],
      output logic [1:0] wresp_enc[4]);
    logic [39:0] g0_struct, g1_struct;
    logic [2:0] e_wreq0, e_wreq1, e_wreq2, e_wreq3;
    logic [2:0] e_rreq0, e_rreq1, e_rreq2, e_rreq3;
    logic [2:0] e_wdata0, e_wdata1, e_wdata2, e_wdata3;
    logic [2:0] e_rdata0, e_rdata1, e_rdata2, e_rdata3;
    logic [1:0] e_wresp0, e_wresp1, e_wresp2, e_wresp3;

    // pack_crdtgrant(): g[0] is the byte-reversed g1_struct and g[1] is
    // the byte-reversed g0_struct.
    g1_struct = {<<8{g[0]}};
    g0_struct = {<<8{g[1]}};

    e_wreq0  = {g1_struct[0],  g1_struct[15:14]};
    e_wreq1  = g1_struct[13:11];
    e_wreq2  = g1_struct[10:8];
    e_wreq3  = g1_struct[23:21];
    e_rreq0  = g1_struct[20:18];
    // rreqcred1_0 is the encoded LSB; rreqcred1_1/2 occupy the
    // encoded MSBs.  The split field therefore reconstructs as
    // {g1_struct[17:16], g1_struct[31]}, not the reverse order.
    e_rreq1  = {g1_struct[17:16], g1_struct[31]};
    e_rreq2  = g1_struct[30:28];
    e_rreq3  = g1_struct[27:25];

    e_wdata0 = {g1_struct[24], g1_struct[39:38]};
    e_wdata1 = g1_struct[37:35];
    e_wdata2 = g1_struct[34:32];
    e_wdata3 = g0_struct[7:5];

    e_rdata0 = g0_struct[4:2];
    // As above, rdatacred1_0 is the encoded LSB and rdatacred1_1/2
    // are the encoded MSBs split across the granule.
    e_rdata1 = {g0_struct[1:0], g0_struct[15]};
    e_rdata2 = g0_struct[14:12];
    e_rdata3 = g0_struct[11:9];

    e_wresp0 = {g0_struct[8], g0_struct[23]};
    e_wresp1 = g0_struct[22:21];
    e_wresp2 = g0_struct[20:19];
    e_wresp3 = g0_struct[18:17];

    wreq_enc[0] = e_wreq0;  wreq_enc[1] = e_wreq1;
    wreq_enc[2] = e_wreq2;  wreq_enc[3] = e_wreq3;
    rreq_enc[0] = e_rreq0;  rreq_enc[1] = e_rreq1;
    rreq_enc[2] = e_rreq2;  rreq_enc[3] = e_rreq3;
    wdata_enc[0] = e_wdata0; wdata_enc[1] = e_wdata1;
    wdata_enc[2] = e_wdata2; wdata_enc[3] = e_wdata3;
    rdata_enc[0] = e_rdata0; rdata_enc[1] = e_rdata1;
    rdata_enc[2] = e_rdata2; rdata_enc[3] = e_rdata3;
    wresp_enc[0] = e_wresp0; wresp_enc[1] = e_wresp1;
    wresp_enc[2] = e_wresp2; wresp_enc[3] = e_wresp3;

    wreq_n[0]  = credit_dec3(wreq_enc[0]);  wreq_n[1]  = credit_dec3(wreq_enc[1]);
    wreq_n[2]  = credit_dec3(wreq_enc[2]);  wreq_n[3]  = credit_dec3(wreq_enc[3]);
    rreq_n[0]  = credit_dec3(rreq_enc[0]);  rreq_n[1]  = credit_dec3(rreq_enc[1]);
    rreq_n[2]  = credit_dec3(rreq_enc[2]);  rreq_n[3]  = credit_dec3(rreq_enc[3]);
    wdata_n[0] = credit_dec3(wdata_enc[0]); wdata_n[1] = credit_dec3(wdata_enc[1]);
    wdata_n[2] = credit_dec3(wdata_enc[2]); wdata_n[3] = credit_dec3(wdata_enc[3]);
    rdata_n[0] = credit_dec3(rdata_enc[0]); rdata_n[1] = credit_dec3(rdata_enc[1]);
    rdata_n[2] = credit_dec3(rdata_enc[2]); rdata_n[3] = credit_dec3(rdata_enc[3]);
    wresp_n[0] = credit_dec2(wresp_enc[0]); wresp_n[1] = credit_dec2(wresp_enc[1]);
    wresp_n[2] = credit_dec2(wresp_enc[2]); wresp_n[3] = credit_dec2(wresp_enc[3]);

    // g0_struct explicitly names these reserved locations.  No generic
    // unspecified/reserved bits are asserted here.
    rsvd_zero = (g0_struct[39:24] == 16'b0) && (g0_struct[16] == 1'b0);
  endfunction

  // ---------------------------------------------------------------------
  // Granule pack/unpack. Each function builds/parses one 40-bit (5-byte)
  // granule via ordered concatenation matching the spec table's declared
  // field order MSB-first -- this is deliberately not a packed struct so
  // the field order is visible and auditable at the call site, and pack/
  // unpack are trivially symmetric (unpack destructures the same
  // concatenation on the LHS).
  // ---------------------------------------------------------------------

  // WriteReq / ReadReq -- Table 2/3, Figure 6/7. 3 granules, PROFEXTLEN=0,
  // PROF=0 (Base Profile -- PROF/PROFEXTLEN must be ignored per spec 5.8).
  function automatic void pack_req(
      output logic [2:0][39:0] g, input msgtype_e msgtype, input logic [1:0] rp,
      input logic lock, input logic [9:0] id, input logic [2:0] size,
      input logic [2:0] prot, input logic [7:0] len, input logic [3:0] cache,
      input logic [3:0] qos, input logic [63:0] addr);
    g[0] = {msgtype, rp, 1'b0, lock, 4'b0000, 12'b0, id, size, prot};
    g[1] = {len, cache, qos, addr[63:40]};
    g[2] = addr[39:0];
  endfunction

  function automatic void unpack_req(
      input logic [2:0][39:0] g, output logic [3:0] msgtype, output logic [1:0] rp,
      output logic lock, output logic [9:0] id, output logic [2:0] size,
      output logic [2:0] prot, output logic [7:0] len, output logic [3:0] cache,
      output logic [3:0] qos, output logic [63:0] addr);
    logic rsvd0; logic [3:0] profextlen; logic [11:0] prof; logic [23:0] addr_hi;
    {msgtype, rp, rsvd0, lock, profextlen, prof, id, size, prot} = g[0];
    {len, cache, qos, addr_hi} = g[1];
    addr = {addr_hi, g[2]};
  endfunction

  // WriteData / ReadData, DLENGTH=256b -- Table 4/10, Figure 8/14. 8 granules.
  function automatic void pack_writedata256(
      output logic [7:0][39:0] g, input logic [1:0] rp,
      input logic [255:0] wdata, input logic [31:0] wstrb);
    g[0] = {MSGTYPE_WRITEDATA, rp, DLENGTH_256B, 4'b0000, 12'b0, wdata[255:240]};
    g[1] = wdata[239:200]; g[2] = wdata[199:160]; g[3] = wdata[159:120];
    g[4] = wdata[119:80];  g[5] = wdata[79:40];   g[6] = wdata[39:0];
    g[7] = {wstrb, 8'b0};
  endfunction

  function automatic void unpack_writedata256(
      input logic [7:0][39:0] g, output logic [1:0] rp,
      output logic [255:0] wdata, output logic [31:0] wstrb);
    logic [3:0] msgtype; logic [1:0] dlength; logic [3:0] profextlen; logic [11:0] prof;
    logic [15:0] wdata_hi; logic [7:0] rsvd8;
    {msgtype, rp, dlength, profextlen, prof, wdata_hi} = g[0];
    wdata = {wdata_hi, g[1], g[2], g[3], g[4], g[5], g[6]};
    {wstrb, rsvd8} = g[7];
  endfunction

  // WriteDataFull, DLENGTH=256b -- the trailing WSTRB granule is omitted
  // because all bytes are implicitly valid.
  function automatic void pack_writedatafull256(
      output logic [6:0][39:0] g, input logic [1:0] rp,
      input logic [255:0] wdata);
    g[0] = {MSGTYPE_WRITEDATAFULL, rp, DLENGTH_256B, 4'b0000, 12'b0, wdata[255:240]};
    g[1] = wdata[239:200]; g[2] = wdata[199:160]; g[3] = wdata[159:120];
    g[4] = wdata[119:80];  g[5] = wdata[79:40];   g[6] = wdata[39:0];
  endfunction

  function automatic void unpack_writedatafull256(
      input logic [6:0][39:0] g, output logic [1:0] rp,
      output logic [255:0] wdata);
    logic [3:0] msgtype; logic [1:0] dlength; logic [3:0] profextlen; logic [11:0] prof;
    logic [15:0] wdata_hi;
    {msgtype, rp, dlength, profextlen, prof, wdata_hi} = g[0];
    wdata = {wdata_hi, g[1], g[2], g[3], g[4], g[5], g[6]};
  endfunction

  function automatic void pack_readdata256(
      output logic [7:0][39:0] g, input logic [1:0] rp, input logic [9:0] rid,
      input logic [1:0] rresp, input logic rlast, input logic [255:0] rdata);
    g[0] = {MSGTYPE_READDATA, rp, DLENGTH_256B, 4'b0000, 12'b0, rid, rresp, rlast, 3'b0};
    g[1] = rdata[255:216]; g[2] = rdata[215:176]; g[3] = rdata[175:136];
    g[4] = rdata[135:96];  g[5] = rdata[95:56];   g[6] = rdata[55:16];
    g[7] = {rdata[15:0], 24'b0};
  endfunction

  function automatic void unpack_readdata256(
      input logic [7:0][39:0] g, output logic [1:0] rp, output logic [9:0] rid,
      output logic [1:0] rresp, output logic rlast, output logic [255:0] rdata);
    logic [3:0] msgtype; logic [1:0] dlength; logic [3:0] profextlen; logic [11:0] prof;
    logic [2:0] rsvd3; logic [15:0] rdata_lo; logic [23:0] rsvd24;
    {msgtype, rp, dlength, profextlen, prof, rid, rresp, rlast, rsvd3} = g[0];
    {rdata_lo, rsvd24} = g[7];
    rdata = {g[1], g[2], g[3], g[4], g[5], g[6], rdata_lo};
  endfunction

  // Generic DLENGTH-parametrized data-message helpers support the three
  // protocol lengths: 256, 512, and 1024 bits.
  // `g` is always the fixed max size (NUM_GRANULES=48, comfortably
  // covering the largest case, 30 granules for WriteData 1024b) with only
  // [0:data_msg_granules(...)-1] meaningful -- same convention as
  // flit_put_granules()/flit_get_granules() above.
  function automatic void pack_writedata(
      output logic [39:0] g[NUM_GRANULES], input logic [1:0] rp,
      input logic [1023:0] wdata, input logic [127:0] wstrb, input logic [1:0] dlength);
    automatic logic [23:0] hdr = {MSGTYPE_WRITEDATA, rp, dlength, 4'b0000, 12'b0};
    case (dlength)
      DLENGTH_256B: begin
        g[0] = {hdr, wdata[255:240]};
        g[1] = wdata[239:200]; g[2] = wdata[199:160]; g[3] = wdata[159:120];
        g[4] = wdata[119:80];  g[5] = wdata[79:40];   g[6] = wdata[39:0];
        g[7] = {wstrb[31:0], 8'b0};
      end
      DLENGTH_512B: begin
        g[0] = {hdr, wdata[511:496]};
        g[1]  = wdata[495:456]; g[2]  = wdata[455:416]; g[3]  = wdata[415:376];
        g[4]  = wdata[375:336]; g[5]  = wdata[335:296]; g[6]  = wdata[295:256];
        g[7]  = wdata[255:216]; g[8]  = wdata[215:176]; g[9]  = wdata[175:136];
        g[10] = wdata[135:96];  g[11] = wdata[95:56];   g[12] = wdata[55:16];
        g[13] = {wdata[15:0], wstrb[63:40]};
        g[14] = wstrb[39:0];
      end
      default: begin // DLENGTH_1024B
        g[0] = {hdr, wdata[1023:1008]};
        g[1]  = wdata[1007:968]; g[2]  = wdata[967:928]; g[3]  = wdata[927:888];
        g[4]  = wdata[887:848];  g[5]  = wdata[847:808]; g[6]  = wdata[807:768];
        g[7]  = wdata[767:728];  g[8]  = wdata[727:688]; g[9]  = wdata[687:648];
        g[10] = wdata[647:608];  g[11] = wdata[607:568]; g[12] = wdata[567:528];
        g[13] = wdata[527:488];  g[14] = wdata[487:448]; g[15] = wdata[447:408];
        g[16] = wdata[407:368];  g[17] = wdata[367:328]; g[18] = wdata[327:288];
        g[19] = wdata[287:248];  g[20] = wdata[247:208]; g[21] = wdata[207:168];
        g[22] = wdata[167:128];  g[23] = wdata[127:88];  g[24] = wdata[87:48];
        g[25] = wdata[47:8];
        g[26] = {wdata[7:0], wstrb[127:96]};
        g[27] = wstrb[95:56];
        g[28] = wstrb[55:16];
        g[29] = {wstrb[15:0], 24'b0};
      end
    endcase
  endfunction

  function automatic void unpack_writedata(
      input logic [39:0] g[NUM_GRANULES], input logic [1:0] dlength,
      output logic [1:0] rp, output logic [1023:0] wdata, output logic [127:0] wstrb);
    automatic logic [3:0] msgtype; automatic logic [1:0] dl;
    automatic logic [3:0] profextlen; automatic logic [11:0] prof;
    automatic logic [15:0] wdata_g0;
    {msgtype, rp, dl, profextlen, prof, wdata_g0} = g[0];
    wdata = '0;
    wstrb = '0;
    case (dlength)
      DLENGTH_256B: begin
        automatic logic [255:0] wdata256;
        automatic logic [31:0]  wstrb256;
        automatic logic [7:0]   rsvd8;
        {wstrb256, rsvd8} = g[7];
        wdata256 = {wdata_g0, g[1], g[2], g[3], g[4], g[5], g[6]};
        wdata = 1024'(wdata256);
        wstrb = 128'(wstrb256);
      end
      DLENGTH_512B: begin
        automatic logic [511:0] wdata512;
        automatic logic [63:0]  wstrb512;
        automatic logic [15:0]  wdata_g13;
        automatic logic [23:0]  wstrb_g13;
        {wdata_g13, wstrb_g13} = g[13];
        wdata512 = {wdata_g0, g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12], wdata_g13};
        wstrb512 = {wstrb_g13, g[14]};
        wdata = 1024'(wdata512);
        wstrb = 128'(wstrb512);
      end
      default: begin // DLENGTH_1024B
        automatic logic [7:0]  wdata_g26;
        automatic logic [31:0] wstrb_g26;
        {wdata_g26, wstrb_g26} = g[26];
        wdata = {wdata_g0, g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12],
                  g[13], g[14], g[15], g[16], g[17], g[18], g[19], g[20], g[21], g[22], g[23], g[24], g[25], wdata_g26};
        wstrb = {wstrb_g26, g[27], g[28], g[29][39:24]};
      end
    endcase
  endfunction

  function automatic void pack_writedatafull(
      output logic [39:0] g[NUM_GRANULES], input logic [1:0] rp,
      input logic [1023:0] wdata, input logic [1:0] dlength);
    automatic logic [23:0] hdr = {MSGTYPE_WRITEDATAFULL, rp, dlength, 4'b0000, 12'b0};
    case (dlength)
      DLENGTH_256B: begin
        g[0] = {hdr, wdata[255:240]};
        g[1] = wdata[239:200]; g[2] = wdata[199:160]; g[3] = wdata[159:120];
        g[4] = wdata[119:80];  g[5] = wdata[79:40];   g[6] = wdata[39:0];
      end
      DLENGTH_512B: begin
        g[0] = {hdr, wdata[511:496]};
        g[1]  = wdata[495:456]; g[2]  = wdata[455:416]; g[3]  = wdata[415:376];
        g[4]  = wdata[375:336]; g[5]  = wdata[335:296]; g[6]  = wdata[295:256];
        g[7]  = wdata[255:216]; g[8]  = wdata[215:176]; g[9]  = wdata[175:136];
        g[10] = wdata[135:96];  g[11] = wdata[95:56];   g[12] = wdata[55:16];
        g[13] = {wdata[15:0], 24'b0};
      end
      default: begin // DLENGTH_1024B
        g[0] = {hdr, wdata[1023:1008]};
        g[1]  = wdata[1007:968]; g[2]  = wdata[967:928]; g[3]  = wdata[927:888];
        g[4]  = wdata[887:848];  g[5]  = wdata[847:808]; g[6]  = wdata[807:768];
        g[7]  = wdata[767:728];  g[8]  = wdata[727:688]; g[9]  = wdata[687:648];
        g[10] = wdata[647:608];  g[11] = wdata[607:568]; g[12] = wdata[567:528];
        g[13] = wdata[527:488];  g[14] = wdata[487:448]; g[15] = wdata[447:408];
        g[16] = wdata[407:368];  g[17] = wdata[367:328]; g[18] = wdata[327:288];
        g[19] = wdata[287:248];  g[20] = wdata[247:208]; g[21] = wdata[207:168];
        g[22] = wdata[167:128];  g[23] = wdata[127:88];  g[24] = wdata[87:48];
        g[25] = wdata[47:8];
        g[26] = {wdata[7:0], 32'b0};
      end
    endcase
  endfunction

  function automatic void unpack_writedatafull(
      input logic [39:0] g[NUM_GRANULES], input logic [1:0] dlength,
      output logic [1:0] rp, output logic [1023:0] wdata);
    automatic logic [3:0] msgtype; automatic logic [1:0] dl;
    automatic logic [3:0] profextlen; automatic logic [11:0] prof;
    automatic logic [15:0] wdata_g0;
    {msgtype, rp, dl, profextlen, prof, wdata_g0} = g[0];
    case (dlength)
      DLENGTH_256B: begin
        automatic logic [255:0] wdata256;
        wdata256 = {wdata_g0, g[1], g[2], g[3], g[4], g[5], g[6]};
        wdata = 1024'(wdata256);
      end
      DLENGTH_512B: begin
        automatic logic [511:0] wdata512;
        automatic logic [15:0]  wdata_g13;
        automatic logic [23:0]  rsvd24;
        {wdata_g13, rsvd24} = g[13];
        wdata512 = {wdata_g0, g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12], wdata_g13};
        wdata = 1024'(wdata512);
      end
      default: begin // DLENGTH_1024B
        automatic logic [7:0]  wdata_g26;
        automatic logic [31:0] rsvd32;
        {wdata_g26, rsvd32} = g[26];
        wdata = {wdata_g0, g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12],
                  g[13], g[14], g[15], g[16], g[17], g[18], g[19], g[20], g[21], g[22], g[23], g[24], g[25], wdata_g26};
      end
    endcase
  endfunction

  function automatic void pack_readdata(
      output logic [39:0] g[NUM_GRANULES], input logic [1:0] rp, input logic [9:0] rid,
      input logic [1:0] rresp, input logic rlast, input logic [1023:0] rdata,
      input logic [1:0] dlength);
    automatic logic [39:0] hdr = {MSGTYPE_READDATA, rp, dlength, 4'b0000, 12'b0, rid, rresp, rlast, 3'b0};
    case (dlength)
      DLENGTH_256B: begin
        g[0] = hdr;
        g[1] = rdata[255:216]; g[2] = rdata[215:176]; g[3] = rdata[175:136];
        g[4] = rdata[135:96];  g[5] = rdata[95:56];   g[6] = rdata[55:16];
        g[7] = {rdata[15:0], 24'b0};
      end
      DLENGTH_512B: begin
        g[0] = hdr;
        g[1]  = rdata[511:472]; g[2]  = rdata[471:432]; g[3]  = rdata[431:392];
        g[4]  = rdata[391:352]; g[5]  = rdata[351:312]; g[6]  = rdata[311:272];
        g[7]  = rdata[271:232]; g[8]  = rdata[231:192]; g[9]  = rdata[191:152];
        g[10] = rdata[151:112]; g[11] = rdata[111:72];  g[12] = rdata[71:32];
        g[13] = {rdata[31:0], 8'b0};
      end
      default: begin // DLENGTH_1024B
        g[0] = hdr;
        g[1]  = rdata[1023:984]; g[2]  = rdata[983:944]; g[3]  = rdata[943:904];
        g[4]  = rdata[903:864];  g[5]  = rdata[863:824]; g[6]  = rdata[823:784];
        g[7]  = rdata[783:744];  g[8]  = rdata[743:704]; g[9]  = rdata[703:664];
        g[10] = rdata[663:624];  g[11] = rdata[623:584]; g[12] = rdata[583:544];
        g[13] = rdata[543:504];  g[14] = rdata[503:464]; g[15] = rdata[463:424];
        g[16] = rdata[423:384];  g[17] = rdata[383:344]; g[18] = rdata[343:304];
        g[19] = rdata[303:264];  g[20] = rdata[263:224]; g[21] = rdata[223:184];
        g[22] = rdata[183:144];  g[23] = rdata[143:104]; g[24] = rdata[103:64];
        g[25] = rdata[63:24];
        g[26] = {rdata[23:0], 16'b0};
      end
    endcase
  endfunction

  function automatic void unpack_readdata(
      input logic [39:0] g[NUM_GRANULES], input logic [1:0] dlength,
      output logic [1:0] rp, output logic [9:0] rid, output logic [1:0] rresp,
      output logic rlast, output logic [1023:0] rdata);
    automatic logic [3:0] msgtype; automatic logic [1:0] dl;
    automatic logic [3:0] profextlen; automatic logic [11:0] prof; automatic logic [2:0] rsvd3;
    {msgtype, rp, dl, profextlen, prof, rid, rresp, rlast, rsvd3} = g[0];
    case (dlength)
      DLENGTH_256B: begin
        automatic logic [255:0] rdata256;
        automatic logic [15:0]  rdata_lo;
        automatic logic [23:0]  rsvd24;
        {rdata_lo, rsvd24} = g[7];
        rdata256 = {g[1], g[2], g[3], g[4], g[5], g[6], rdata_lo};
        rdata = 1024'(rdata256);
      end
      DLENGTH_512B: begin
        automatic logic [511:0] rdata512;
        automatic logic [31:0]  rdata_lo;
        automatic logic [7:0]   rsvd8;
        {rdata_lo, rsvd8} = g[13];
        rdata512 = {g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12], rdata_lo};
        rdata = 1024'(rdata512);
      end
      default: begin // DLENGTH_1024B
        automatic logic [23:0] rdata_lo;
        automatic logic [15:0] rsvd16;
        {rdata_lo, rsvd16} = g[26];
        rdata = {g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12],
                  g[13], g[14], g[15], g[16], g[17], g[18], g[19], g[20], g[21], g[22], g[23], g[24], g[25], rdata_lo};
      end
    endcase
  endfunction

  // WriteResp -- Table 13, Figure 17. 1 granule.
  function automatic void pack_writeresp(
      output logic [39:0] g, input logic [1:0] rp, input logic [9:0] bid,
      input logic [1:0] bresp);
    g = {MSGTYPE_WRITERESP, rp, 2'b00, 4'b0000, 12'b0, bid, bresp, 4'b0};
  endfunction

  function automatic void unpack_writeresp(
      input logic [39:0] g, output logic [1:0] rp, output logic [9:0] bid,
      output logic [1:0] bresp);
    logic [3:0] msgtype; logic [1:0] rsvd2; logic [3:0] profextlen; logic [11:0] prof;
    logic [3:0] rsvd4;
    {msgtype, rp, rsvd2, profextlen, prof, bid, bresp, rsvd4} = g;
  endfunction

  // Misc/Activation -- Table 26/27, Figure 19. 1 granule.
  function automatic void pack_activation(
      output logic [39:0] g, input activationop_e op, input logic property_req);
    g = {MSGTYPE_MISC, MISCOP_ACTIVATION, op, property_req, 28'b0};
  endfunction

  function automatic void unpack_activation(
      input logic [39:0] g, output logic [3:0] msgtype, output logic [2:0] miscop,
      output logic [3:0] actop, output logic property_req);
    logic [27:0] rsvd28;
    {msgtype, miscop, actop, property_req, rsvd28} = g;
  endfunction

  // Misc/CrdtGrant -- two granules grant credits for all four RPs. Each
  // argument group is ordered RP0 through RP3. The wire layout byte-reverses
  // each granule and splits several credit fields across struct positions;
  // the inverse unpacker below follows the same field placement.
  function automatic void pack_crdtgrant(
      output logic [1:0][39:0] g,
      input int unsigned wreq_n0,  input int unsigned wreq_n1,
      input int unsigned wreq_n2,  input int unsigned wreq_n3,
      input int unsigned rreq_n0,  input int unsigned rreq_n1,
      input int unsigned rreq_n2,  input int unsigned rreq_n3,
      input int unsigned wdata_n0, input int unsigned wdata_n1,
      input int unsigned wdata_n2, input int unsigned wdata_n3,
      input int unsigned rdata_n0, input int unsigned rdata_n1,
      input int unsigned rdata_n2, input int unsigned rdata_n3,
      input int unsigned wresp_n0, input int unsigned wresp_n1,
      input int unsigned wresp_n2, input int unsigned wresp_n3);
    logic [2:0] e_wreq0, e_wreq1, e_wreq2, e_wreq3;
    logic [2:0] e_rreq0, e_rreq1, e_rreq2, e_rreq3;
    logic [2:0] e_wdata0, e_wdata1, e_wdata2, e_wdata3;
    logic [2:0] e_rdata0, e_rdata1, e_rdata2, e_rdata3;
    logic [1:0] e_wresp0, e_wresp1, e_wresp2, e_wresp3;
    logic [39:0] g0_struct, g1_struct;
    e_wreq0  = credit_enc3(wreq_n0);  e_wreq1  = credit_enc3(wreq_n1);
    e_wreq2  = credit_enc3(wreq_n2);  e_wreq3  = credit_enc3(wreq_n3);
    e_rreq0  = credit_enc3(rreq_n0);  e_rreq1  = credit_enc3(rreq_n1);
    e_rreq2  = credit_enc3(rreq_n2);  e_rreq3  = credit_enc3(rreq_n3);
    e_wdata0 = credit_enc3(wdata_n0); e_wdata1 = credit_enc3(wdata_n1);
    e_wdata2 = credit_enc3(wdata_n2); e_wdata3 = credit_enc3(wdata_n3);
    e_rdata0 = credit_enc3(rdata_n0); e_rdata1 = credit_enc3(rdata_n1);
    e_rdata2 = credit_enc3(rdata_n2); e_rdata3 = credit_enc3(rdata_n3);
    e_wresp0 = credit_enc2(wresp_n0); e_wresp1 = credit_enc2(wresp_n1);
    e_wresp2 = credit_enc2(wresp_n2); e_wresp3 = credit_enc2(wresp_n3);

    g0_struct = {16'b0,                    // rsvd[15:0]
            e_wresp0[0],              // wrespcred0_0
            e_wresp1, e_wresp2, e_wresp3,
            1'b0,                     // rsvd_0
            e_rdata1[0],              // rdatacred1_0
            e_rdata2, e_rdata3,
            e_wresp0[1],              // wrespcred0_1
            e_wdata3, e_rdata0,
            e_rdata1[2:1]};           // rdatacred1_1
    g1_struct = {e_wdata0[1:0],            // wdatacred0_0
            e_wdata1, e_wdata2,
            e_rreq1[0],               // rreqcred1_0
            e_rreq2, e_rreq3,
            e_wdata0[2],              // wdatacred0_1
            e_wreq3, e_rreq0,
            e_rreq1[2:1],             // rreqcred1_1
            e_wreq0[1:0],             // wreqcred0_0
            e_wreq1, e_wreq2,
            MSGTYPE_MISC, MISCOP_CRDTGRANT,
            e_wreq0[2]};              // wreqcred0_1
    // Byte-reverse each granule and place the half containing the message
    // type in the first transmitted granule.
    g[0] = {<<8{g1_struct}};
    g[1] = {<<8{g0_struct}};
  endfunction

  // ---------------------------------------------------------------------
  // Protocol header pack/unpack (10 bytes / 5 byte-pairs) for AoU v0.7.
  // ---------------------------------------------------------------------
  function automatic void pack_header(
      output logic [9:0][7:0] ph, input logic [1:0] fdid,
      input logic [47:0] msg_start, input logic [15:0] msg_credit);
    ph[0] = {msg_start[3:0],   2'b00, fdid};
    ph[1] = msg_start[11:4];
    ph[2] = {msg_start[15:12], 4'b0000};
    ph[3] = msg_start[23:16];
    ph[4] = msg_credit[7:0];
    ph[5] = msg_credit[15:8];
    ph[6] = {msg_start[27:24], 4'b0000};
    ph[7] = msg_start[35:28];
    ph[8] = {msg_start[39:36], 4'b0000};
    ph[9] = msg_start[47:40];
  endfunction

  function automatic void unpack_header(
      input logic [9:0][7:0] ph, output logic [1:0] fdid,
      output logic [47:0] msg_start, output logic [15:0] msg_credit);
    fdid = ph[0][1:0];
    msg_start = {ph[9], ph[8][7:4], ph[7], ph[6][7:4],
                 ph[3], ph[2][7:4], ph[1], ph[0][7:4]};
    msg_credit = {ph[5], ph[4]};
  endfunction

  // ---------------------------------------------------------------------
  // Whole-flit byte-array helpers. `flit` is the 256B container in wire
  // (byte-stream) order; FH (bytes 0-1) and CRC (bytes 126-127, 254-255)
  // are left zero -- see the header comment on this package.
  // ---------------------------------------------------------------------
  function automatic void flit_clear(ref logic [7:0] flit[FLIT_BYTES]);
    foreach (flit[i]) flit[i] = 8'h00;
  endfunction

  function automatic void flit_put_header(
      ref logic [7:0] flit[FLIT_BYTES], input logic [1:0] fdid,
      input logic [47:0] msg_start, input logic [15:0] msg_credit);
    logic [9:0][7:0] ph;
    pack_header(ph, fdid, msg_start, msg_credit);
    for (int i = 0; i < 10; i++) flit[PH_BYTE[i]] = ph[i];
  endfunction

  function automatic void flit_get_header(
      input logic [7:0] flit[FLIT_BYTES], output logic [1:0] fdid,
      output logic [47:0] msg_start, output logic [15:0] msg_credit);
    logic [9:0][7:0] ph;
    for (int i = 0; i < 10; i++) ph[i] = flit[PH_BYTE[i]];
    unpack_header(ph, fdid, msg_start, msg_credit);
  endfunction

  // Place num_granules*40 bits (MSB-first, granule 0 first) starting at
  // granule g0 of the flit. `gdata` is always the fixed max size (48
  // granules) with only [0:num_granules-1] meaningful -- deliberately not
  // an open/dynamic array argument, to stay clear of subroutine
  // array-formal-argument corners some SV front-ends (Verilator included)
  // support unevenly.
  function automatic void flit_put_granules(
      ref logic [7:0] flit[FLIT_BYTES], input int unsigned g0,
      input int unsigned num_granules, input logic [39:0] gdata[NUM_GRANULES]);
    for (int gi = 0; gi < num_granules; gi++) begin
      automatic int unsigned bpos = granule_byte_pos(g0 + gi);
      logic [39:0] gv = gdata[gi];
      for (int b = 0; b < GRANULE_BYTES; b++)
        flit[bpos + b] = gv[(GRANULE_BYTES-1-b)*8 +: 8];
    end
  endfunction

  function automatic void flit_get_granules(
      input logic [7:0] flit[FLIT_BYTES], input int unsigned g0,
      input int unsigned num_granules, output logic [39:0] gdata[NUM_GRANULES]);
    for (int gi = 0; gi < num_granules; gi++) begin
      automatic int unsigned bpos = granule_byte_pos(g0 + gi);
      logic [39:0] gv;
      for (int b = 0; b < GRANULE_BYTES; b++)
        gv[(GRANULE_BYTES-1-b)*8 +: 8] = flit[bpos + b];
      gdata[gi] = gv;
    end
  endfunction

endpackage
