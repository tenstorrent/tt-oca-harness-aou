// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// ReadData (Tables 10-12): 8/14/27 granules. RDATA starts in the second
// granule; the first carries RID, RRESP and RLAST.
class aou_msg_rdata extends aou_msg;
  `uvm_object_utils(aou_msg_rdata)

  bit [1:0]    dlength;
  bit [9:0]    id;
  bit [1:0]    resp;
  bit          last;
  bit [1023:0] data;
  bit [2:0]    rsvd_hdr;
  bit [23:0]   rsvd_tail;

  function new(string name = "aou_msg_rdata");
    super.new(name);
    msg_type = AOU_MT_RDATA;
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    bit [39:0] h = {msg_type, rp, dlength, flex, id, resp, last, rsvd_hdr};
    b = '0;
    case (dlength)
      AOU_DL_256:  b[AOU_MSG_BITS-1 -: 320]  = {h, data[255:0], rsvd_tail[23:0]};
      AOU_DL_512:  b[AOU_MSG_BITS-1 -: 560]  = {h, data[511:0], rsvd_tail[7:0]};
      AOU_DL_1024: b[AOU_MSG_BITS-1 -: 1080] = {h, data, rsvd_tail[15:0]};
      default:     b[AOU_MSG_BITS-1 -: 40]   = h;
    endcase
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    {msg_type, rp, dlength, flex, id, resp, last, rsvd_hdr} = b[AOU_MSG_BITS-1 -: 40];
    data = '0;
    rsvd_tail = '0;
    case (dlength)
      AOU_DL_256:  {data[255:0], rsvd_tail[23:0]} = b[AOU_MSG_BITS-41 -: 280];
      AOU_DL_512:  {data[511:0], rsvd_tail[7:0]}  = b[AOU_MSG_BITS-41 -: 520];
      AOU_DL_1024: {data, rsvd_tail[15:0]}        = b[AOU_MSG_BITS-41 -: 1040];
      default: ;
    endcase
  endfunction

  virtual function string rsvd_nonzero();
    if (rsvd_hdr != 0) return "RsvdZero after RLAST";
    if (rsvd_tail != 0) return "RsvdZero tail padding";
    return "";
  endfunction

  virtual function string kind();
    return $sformatf("ReadData%0d", aou_dl_bits(dlength));
  endfunction

  virtual function string fields2string();
    return $sformatf("id=%0h resp=%0d last=%0d data[63:0]=%0h", id, resp, last, data[63:0]);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg_rdata r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    dlength = r.dlength;
    id = r.id;
    resp = r.resp;
    last = r.last;
    data = r.data;
    rsvd_hdr = r.rsvd_hdr;
    rsvd_tail = r.rsvd_tail;
  endfunction
endclass
