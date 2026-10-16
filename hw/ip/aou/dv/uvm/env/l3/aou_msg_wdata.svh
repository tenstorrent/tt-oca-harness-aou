// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// WriteData (Tables 4-6) and WriteDataFull (msg type 6): 8/15/30 and 7/14/27
// granules. WriteDataFull carries no WSTRB; every byte is valid.
class aou_msg_wdata extends aou_msg;
  `uvm_object_utils(aou_msg_wdata)

  bit [1:0]    dlength;
  bit [1023:0] data;          // the low aou_dl_bits(dlength) bits travel
  bit [127:0]  strb;
  bit [31:0]   rsvd_tail;

  function new(string name = "aou_msg_wdata");
    super.new(name);
    msg_type = AOU_MT_WDATA;
  endfunction

  function bit full();
    return msg_type == AOU_MT_WDATAF;
  endfunction

  function void set_full(bit f);
    msg_type = f ? AOU_MT_WDATAF : AOU_MT_WDATA;
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    bit [23:0] h = {msg_type, rp, dlength, flex};
    b = '0;
    case ({full(), dlength})
      {1'b0, AOU_DL_256}:  b[AOU_MSG_BITS-1 -: 320]  = {h, data[255:0], strb[31:0], rsvd_tail[7:0]};
      {1'b0, AOU_DL_512}:  b[AOU_MSG_BITS-1 -: 600]  = {h, data[511:0], strb[63:0]};
      {1'b0, AOU_DL_1024}: b[AOU_MSG_BITS-1 -: 1200] = {h, data, strb, rsvd_tail[23:0]};
      {1'b1, AOU_DL_256}:  b[AOU_MSG_BITS-1 -: 280]  = {h, data[255:0]};
      {1'b1, AOU_DL_512}:  b[AOU_MSG_BITS-1 -: 560]  = {h, data[511:0], rsvd_tail[23:0]};
      {1'b1, AOU_DL_1024}: b[AOU_MSG_BITS-1 -: 1080] = {h, data, rsvd_tail[31:0]};
      default:             b[AOU_MSG_BITS-1 -: 24]   = h;
    endcase
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    {msg_type, rp, dlength, flex} = b[AOU_MSG_BITS-1 -: 24];
    data = '0;
    strb = '0;
    rsvd_tail = '0;
    case ({full(), dlength})
      {1'b0, AOU_DL_256}:  {data[255:0], strb[31:0], rsvd_tail[7:0]} = b[AOU_MSG_BITS-25 -: 296];
      {1'b0, AOU_DL_512}:  {data[511:0], strb[63:0]} = b[AOU_MSG_BITS-25 -: 576];
      {1'b0, AOU_DL_1024}: {data, strb, rsvd_tail[23:0]} = b[AOU_MSG_BITS-25 -: 1176];
      {1'b1, AOU_DL_256}:  data[255:0] = b[AOU_MSG_BITS-25 -: 256];
      {1'b1, AOU_DL_512}:  {data[511:0], rsvd_tail[23:0]} = b[AOU_MSG_BITS-25 -: 536];
      {1'b1, AOU_DL_1024}: {data, rsvd_tail[31:0]} = b[AOU_MSG_BITS-25 -: 1056];
      default: ;
    endcase
    if (full()) begin
      for (int unsigned i = 0; i < aou_dl_bits(dlength) / 8; i++) strb[i] = 1'b1;
    end
  endfunction

  virtual function string rsvd_nonzero();
    return (rsvd_tail != 0) ? "RsvdZero tail padding" : "";
  endfunction

  virtual function string kind();
    // Not a ?: of the two names: VCS evaluates it as a packed vector and pads the
    // shorter name with leading spaces.
    string n = "WriteData";
    if (full()) n = "WriteDataFull";
    return $sformatf("%s%0d", n, aou_dl_bits(dlength));
  endfunction

  virtual function string fields2string();
    bit [127:0] s = '0;
    if (full()) return $sformatf("data[63:0]=%0h", data[63:0]);
    for (int unsigned i = 0; i < aou_dl_bits(dlength) / 8; i++) s[i] = strb[i];
    return $sformatf("strb=%0h data[63:0]=%0h", s, data[63:0]);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg_wdata r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    dlength = r.dlength;
    data = r.data;
    strb = r.strb;
    rsvd_tail = r.rsvd_tail;
  endfunction
endclass
