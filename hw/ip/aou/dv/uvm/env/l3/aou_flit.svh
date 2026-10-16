// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One 256-byte Format 6 flit as the protocol layer sees it (spec 4.2-4.3):
// 48 granules, the 10-byte protocol header (FDId, MsgStart[48], MsgCredit)
// and the adapter's bytes (flit header and CRC), which L1 owns.
//   bytes 2-61 G0-11, 62-65 PH B0-B3, 66-125 G12-23, 126-127 CRC0,
//   128-129 PH B4-B5 (MsgCredit), 130-189 G24-35, 190-193 PH B6-B9,
//   194-253 G36-47, 254-255 CRC1.
class aou_flit extends uvm_object;
  `uvm_object_utils(aou_flit)

  aou_granule_t g[AOU_GRANULES];
  bit [47:0]    msg_start;
  bit [15:0]    msg_credit;
  bit [1:0]     fdid;
  // Header bits the spec marks Rsvd (not RsvdZero): B0[3:2], B2/B6/B8[3:0].
  bit [13:0]    hdr_rsvd;
  bit [7:0]     fh[2];
  bit [7:0]     crc[4];

  int unsigned  seq;
  aou_l3_dir_e  dir = AOU_L3_TX;
  int unsigned  carry_in;      // leading granules continuing an earlier message
  aou_msg       msgs[$];       // messages that start in this flit

  function new(string name = "aou_flit");
    super.new(name);
    // Protocol Identifier 11b: a NOP (00b) is discarded by the receiver.
    fh[0] = 8'hC0;
  endfunction

  function void header_bytes(output bit [7:0] ph[10]);
    ph[0] = {msg_start[3:0], hdr_rsvd[1:0], fdid};
    ph[1] = msg_start[11:4];
    ph[2] = {msg_start[15:12], hdr_rsvd[5:2]};
    ph[3] = msg_start[23:16];
    ph[4] = msg_credit[7:0];
    ph[5] = msg_credit[15:8];
    ph[6] = {msg_start[27:24], hdr_rsvd[9:6]};
    ph[7] = msg_start[35:28];
    ph[8] = {msg_start[39:36], hdr_rsvd[13:10]};
    ph[9] = msg_start[47:40];
  endfunction

  function aou_flit_vec_t to_vec();
    aou_flit_vec_t v = '0;
    bit [7:0] ph[10];
    for (int unsigned i = 0; i < AOU_GRANULES; i++) begin
      int unsigned b0 = aou_granule_byte(i);
      for (int unsigned k = 0; k < 5; k++) v[8*(b0+k) +: 8] = g[i][39-8*k -: 8];
    end
    header_bytes(ph);
    foreach (ph[i]) v[8*AOU_PH_BYTE[i] +: 8] = ph[i];
    foreach (fh[i]) v[8*AOU_FH_BYTE[i] +: 8] = fh[i];
    foreach (crc[i]) v[8*AOU_CRC_BYTE[i] +: 8] = crc[i];
    return v;
  endfunction

  function void from_vec(aou_flit_vec_t v);
    bit [7:0] ph[10];
    for (int unsigned i = 0; i < AOU_GRANULES; i++) begin
      int unsigned b0 = aou_granule_byte(i);
      for (int unsigned k = 0; k < 5; k++) g[i][39-8*k -: 8] = v[8*(b0+k) +: 8];
    end
    foreach (ph[i]) ph[i] = v[8*AOU_PH_BYTE[i] +: 8];
    foreach (fh[i]) fh[i] = v[8*AOU_FH_BYTE[i] +: 8];
    foreach (crc[i]) crc[i] = v[8*AOU_CRC_BYTE[i] +: 8];
    fdid = ph[0][1:0];
    hdr_rsvd = {ph[8][3:0], ph[6][3:0], ph[2][3:0], ph[0][3:2]};
    msg_start = {ph[9], ph[8][7:4], ph[7], ph[6][7:4], ph[3], ph[2][7:4], ph[1], ph[0][7:4]};
    msg_credit = {ph[5], ph[4]};
  endfunction

  function void to_bytes(ref bit [7:0] b[AOU_FLIT_BYTES]);
    aou_flit_vec_t v = to_vec();
    foreach (b[i]) b[i] = v[8*i +: 8];
  endfunction

  function void from_bytes(input bit [7:0] b[AOU_FLIT_BYTES]);
    aou_flit_vec_t v;
    foreach (b[i]) v[8*i +: 8] = b[i];
    from_vec(v);
  endfunction

  function int unsigned num_starts();
    return $countones(msg_start);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_flit r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    g = r.g;
    msg_start = r.msg_start;
    msg_credit = r.msg_credit;
    fdid = r.fdid;
    hdr_rsvd = r.hdr_rsvd;
    fh = r.fh;
    crc = r.crc;
    seq = r.seq;
    dir = r.dir;
    carry_in = r.carry_in;
    msgs = r.msgs;
  endfunction

  virtual function string convert2string();
    string s = $sformatf("flit#%0d %s fdid=%0d start=%012h credit=%04h carry=%0d:", seq,
                         (dir == AOU_L3_TX) ? "TX" : "RX", fdid, msg_start, msg_credit,
                         carry_in);
    foreach (msgs[i]) s = {s, " ", msgs[i].kind(), $sformatf("@%0d", msgs[i].start_granule)};
    return s;
  endfunction
endclass
