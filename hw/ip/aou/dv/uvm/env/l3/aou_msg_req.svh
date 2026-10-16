// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// WriteReq / ReadReq (Tables 2, 3): 3 granules.
class aou_msg_req extends aou_msg;
  `uvm_object_utils(aou_msg_req)

  bit        lock;
  bit [9:0]  id;
  bit [2:0]  size;
  bit [2:0]  prot;
  bit [7:0]  len;
  bit [3:0]  cache;
  bit [3:0]  qos;
  bit [63:0] addr;
  bit        rsvd;

  function new(string name = "aou_msg_req");
    super.new(name);
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    b = '0;
    b[AOU_MSG_BITS-1 -: 120] = {msg_type, rp, rsvd, lock, flex, id, size, prot, len, cache,
                                qos, addr};
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    {msg_type, rp, rsvd, lock, flex, id, size, prot, len, cache, qos, addr} =
        b[AOU_MSG_BITS-1 -: 120];
  endfunction

  virtual function string rsvd_nonzero();
    return rsvd ? "RsvdZero after RP" : "";
  endfunction

  virtual function string kind();
    return (msg_type == AOU_MT_WREQ) ? "WriteReq" : "ReadReq";
  endfunction

  virtual function string fields2string();
    return $sformatf("id=%0h addr=%0h len=%0d size=%0d lock=%0d cache=%0h prot=%0h qos=%0h",
                     id, addr, len, size, lock, cache, prot, qos);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg_req r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    lock = r.lock;
    id = r.id;
    size = r.size;
    prot = r.prot;
    len = r.len;
    cache = r.cache;
    qos = r.qos;
    addr = r.addr;
    rsvd = r.rsvd;
  endfunction
endclass
