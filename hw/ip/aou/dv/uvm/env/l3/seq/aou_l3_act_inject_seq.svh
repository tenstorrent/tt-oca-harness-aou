// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Injection: an activation opcode sent regardless of the link state, for
// illegal-transition tests (receiver rule AOU-R40). The model's own state
// does not move.
class aou_l3_act_inject_seq extends aou_l3_base_seq;
  `uvm_object_utils(aou_l3_act_inject_seq)

  bit [3:0] op = AOU_ACT_ACK;
  bit       property_req = 1'b0;

  function new(string name = "aou_l3_act_inject_seq");
    super.new(name);
  endfunction

  task body();
    aou_msg_act m = aou_msg_act::type_id::create("m");
    m.op = op;
    m.property_req = property_req;
    m.ignore_state = 1'b1;
    send_msg(m);
  endtask
endclass
