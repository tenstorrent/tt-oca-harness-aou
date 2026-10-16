// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Injection: a WriteResp with RsvdZero bits set (receiver rule AOU-R11). The
// message is otherwise legal and credited.
class aou_l3_rsvd_seq extends aou_l3_base_seq;
  `uvm_object_utils(aou_l3_rsvd_seq)

  bit [9:0] id = 10'd0;

  function new(string name = "aou_l3_rsvd_seq");
    super.new(name);
  endfunction

  task body();
    aou_msg_wresp m = aou_msg_wresp::type_id::create("m");
    m.rp = rp;
    m.id = id;
    m.rsvd_b = 4'hA;
    send_msg(m);
  endtask
endclass
