// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AoU protocol-layer types, geometry, credit encoding and message lengths.
// Encodings follow the AoU specification v0.7 (v0.8 deltas behind
// aou_spec_rev_e). Granules are 40-bit values whose bit 39 is the first bit on
// the wire (v0.8 5.8, v0.7 5.7: bytes count up, bits count down, fields MSB first).

localparam int AOU_FLIT_BYTES   = 256;
localparam int AOU_GRANULES     = 48;
localparam int AOU_GRANULE_W    = 40;
localparam int AOU_MAX_MSG_G    = 30;
localparam int AOU_MSG_BITS     = AOU_MAX_MSG_G * AOU_GRANULE_W;
localparam int AOU_RP_MAX       = 4;
localparam int AOU_CC_NUM       = 5;
localparam int AOU_HALF_G       = 24;

// Protocol header byte positions (Figure 5): PH B0..B9.
localparam int AOU_PH_BYTE[10] = '{62, 63, 64, 65, 128, 129, 190, 191, 192, 193};
// Link-layer bytes owned by the adapter (L1): flit header and the two CRCs.
localparam int AOU_FH_BYTE[2]  = '{0, 1};
localparam int AOU_CRC_BYTE[4] = '{126, 127, 254, 255};

typedef bit [AOU_GRANULE_W-1:0]  aou_granule_t;
typedef bit [AOU_MSG_BITS-1:0]   aou_msg_bits_t;
// Byte i of a flit is bits [8*i +: 8].
typedef bit [AOU_FLIT_BYTES*8-1:0] aou_flit_vec_t;

typedef enum bit [3:0] {
  AOU_MT_MISC   = 4'b0000,
  AOU_MT_WREQ   = 4'b0001,
  AOU_MT_RREQ   = 4'b0010,
  AOU_MT_WDATA  = 4'b0011,
  AOU_MT_RDATA  = 4'b0100,
  AOU_MT_WRESP  = 4'b0101,
  AOU_MT_WDATAF = 4'b0110
} aou_msg_type_e;

typedef enum bit [2:0] {
  AOU_MISCOP_ACT  = 3'b010,
  AOU_MISCOP_CRDT = 3'b100
} aou_miscop_e;

typedef enum bit [3:0] {
  AOU_ACT_REQ       = 4'd0,
  AOU_ACT_ACK       = 4'd1,
  AOU_DEACT_REQ     = 4'd2,
  AOU_DEACT_ACK     = 4'd3
} aou_act_op_e;

typedef enum bit [1:0] {
  AOU_DL_256  = 2'b00,
  AOU_DL_512  = 2'b01,
  AOU_DL_1024 = 2'b10
} aou_dlength_e;

typedef enum int {
  AOU_CC_WREQ  = 0,
  AOU_CC_RREQ  = 1,
  AOU_CC_WDATA = 2,
  AOU_CC_RDATA = 3,
  AOU_CC_WRESP = 4,
  AOU_CC_NONE  = 5
} aou_cred_class_e;

typedef enum int {
  AOU_SPEC_V07 = 0,
  AOU_SPEC_V08 = 1
} aou_spec_rev_e;

typedef enum int {
  AOU_LS_DISABLED   = 0,
  AOU_LS_ACTIVATE   = 1,
  AOU_LS_ENABLED    = 2,
  AOU_LS_DEACTIVATE = 3,
  AOU_LS_ERROR      = 4
} aou_link_state_e;

// Direction relative to the model: TX is model -> DUT, RX is DUT -> model.
typedef enum int {
  AOU_L3_TX = 0,
  AOU_L3_RX = 1
} aou_l3_dir_e;

// When the modelled RX buffer frees a message's granules for return.
typedef enum int {
  AOU_RET_IMMEDIATE = 0,   // on receipt (infinite buffer)
  AOU_RET_ON_CONSUME = 1,  // when the consumer dequeues the message (MAS 3.9)
  AOU_RET_DELAYED   = 2,   // on consume, then held for ret_delay ticks
  AOU_RET_WITHHELD  = 3    // never, until release_withheld()
} aou_cred_ret_e;

// How returned credits travel.
typedef enum int {
  AOU_CRM_DUT_LIKE = 0,    // initial CrdtGrant, then header MsgCredit (MAS 3.9)
  AOU_CRM_HDR      = 1,    // header MsgCredit only (initial grant still a CrdtGrant)
  AOU_CRM_GRANT    = 2,    // CrdtGrant messages only
  AOU_CRM_MIXED    = 3     // random choice per flit, both in one flit allowed
} aou_cred_method_e;

function automatic int unsigned aou_granule_byte(int unsigned g);
  return 2 + 64 * (g / 12) + 5 * (g % 12);
endfunction

function automatic int unsigned aou_dl_bits(bit [1:0] dl);
  case (dl)
    2'b00:   return 256;
    2'b01:   return 512;
    default: return 1024;
  endcase
endfunction

// ReadData DLENGTH required for an ARSIZE (spec 5.7): ReadData256 below 256 bits.
function automatic bit [1:0] aou_dl_for_size(bit [2:0] size);
  if (size <= 3'd5) return AOU_DL_256;
  if (size == 3'd6) return AOU_DL_512;
  return AOU_DL_1024;
endfunction

// Credit encoding, v0.8 Table 17 (v0.7 Table 18). WRESPCRED is two bits (0/1/4/8).
function automatic int unsigned aou_cred_dec3(bit [2:0] enc);
  case (enc)
    3'd0: return 0;
    3'd1: return 1;
    3'd2: return 4;
    3'd3: return 8;
    3'd4: return 16;
    3'd5: return 32;
    3'd6: return 64;
    default: return 128;
  endcase
endfunction

function automatic int unsigned aou_cred_dec2(bit [1:0] enc);
  return aou_cred_dec3({1'b0, enc});
endfunction

function automatic bit aou_cred_legal3(int unsigned n);
  return n inside {0, 1, 4, 8, 16, 32, 64, 128};
endfunction

function automatic bit aou_cred_legal2(int unsigned n);
  return n inside {0, 1, 4, 8};
endfunction

function automatic bit aou_cred_legal(aou_cred_class_e c, int unsigned n);
  return (c == AOU_CC_WRESP) ? aou_cred_legal2(n) : aou_cred_legal3(n);
endfunction

// Largest encoding whose value does not exceed n. Callers that need an exact
// value check aou_cred_legal() first; nothing here is fatal, so a test can
// still build an illegal wire value through the raw-override hook.
function automatic bit [2:0] aou_cred_enc_floor(aou_cred_class_e c, int unsigned n);
  bit [2:0] e = 3'd0;
  int unsigned max_e = (c == AOU_CC_WRESP) ? 3 : 7;
  for (int unsigned k = 0; k <= max_e; k++) begin
    if (aou_cred_dec3(3'(k)) <= n) e = 3'(k);
  end
  return e;
endfunction

function automatic int unsigned aou_cred_floor(aou_cred_class_e c, int unsigned n);
  return aou_cred_dec3(aou_cred_enc_floor(c, n));
endfunction

function automatic aou_cred_class_e aou_cred_class_of(bit [3:0] mt);
  case (mt)
    AOU_MT_WREQ:                return AOU_CC_WREQ;
    AOU_MT_RREQ:                return AOU_CC_RREQ;
    AOU_MT_WDATA, AOU_MT_WDATAF: return AOU_CC_WDATA;
    AOU_MT_RDATA:               return AOU_CC_RDATA;
    AOU_MT_WRESP:               return AOU_CC_WRESP;
    default:                    return AOU_CC_NONE;
  endcase
endfunction

function automatic string aou_cc_name(aou_cred_class_e c);
  case (c)
    AOU_CC_WREQ:  return "WREQ";
    AOU_CC_RREQ:  return "RREQ";
    AOU_CC_WDATA: return "WDATA";
    AOU_CC_RDATA: return "RDATA";
    AOU_CC_WRESP: return "WRESP";
    default:      return "NONE";
  endcase
endfunction

// Message length in granules from its first granule (Tables 2-13, 19, 26).
// Returns 0 when the type, DLENGTH, MISCOP or ACTIVATIONOP is not defined,
// so the length cannot be known.
function automatic int unsigned aou_msg_len(aou_granule_t g0, aou_spec_rev_e rev);
  bit [3:0] mt = g0[39:36];
  bit [1:0] dl = g0[33:32];
  bit [2:0] mop = g0[35:33];
  bit [3:0] aop = g0[32:29];
  case (mt)
    AOU_MT_WREQ, AOU_MT_RREQ: return 3;
    AOU_MT_WRESP:             return 1;
    AOU_MT_WDATA:  case (dl) 2'b00: return 8; 2'b01: return 15; 2'b10: return 30;
                             default: return 0; endcase
    AOU_MT_WDATAF: case (dl) 2'b00: return 7; 2'b01: return 14; 2'b10: return 27;
                             default: return 0; endcase
    AOU_MT_RDATA:  case (dl) 2'b00: return 8; 2'b01: return 14; 2'b10: return 27;
                             default: return 0; endcase
    AOU_MT_MISC: begin
      if (mop == AOU_MISCOP_CRDT) return 2;
      if (mop == AOU_MISCOP_ACT) begin
        if (aop > 4'd3) return 0;
        if (rev == AOU_SPEC_V08 && aop == AOU_ACT_REQ) return 4;
        return 1;
      end
      return 0;
    end
    default: return 0;
  endcase
endfunction

// Granule count of a data message, for coverage and unit tests.
function automatic int unsigned aou_data_len(bit [3:0] mt, bit [1:0] dl);
  aou_granule_t g0 = '0;
  g0[39:36] = mt;
  g0[33:32] = dl;
  return aou_msg_len(g0, AOU_SPEC_V07);
endfunction
