// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// WriteResp (Table 13): 1 granule.
class aou_msg_wresp extends aou_msg;
  `uvm_object_utils(aou_msg_wresp)

  bit [9:0] id;
  bit [1:0] resp;
  bit [1:0] rsvd_a;
  bit [3:0] rsvd_b;

  function new(string name = "aou_msg_wresp");
    super.new(name);
    msg_type = AOU_MT_WRESP;
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    b = '0;
    b[AOU_MSG_BITS-1 -: 40] = {msg_type, rp, rsvd_a, flex, id, resp, rsvd_b};
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    {msg_type, rp, rsvd_a, flex, id, resp, rsvd_b} = b[AOU_MSG_BITS-1 -: 40];
  endfunction

  virtual function string rsvd_nonzero();
    return (rsvd_a != 0 || rsvd_b != 0) ? "RsvdZero around BRESP" : "";
  endfunction

  virtual function string kind();
    return "WriteResp";
  endfunction

  virtual function string fields2string();
    return $sformatf("id=%0h resp=%0d", id, resp);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg_wresp r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    id = r.id;
    resp = r.resp;
    rsvd_a = r.rsvd_a;
    rsvd_b = r.rsvd_b;
  endfunction
endclass
