// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Injection: one message with a reserved encoding (receiver rule AOU-R3).
// kind 0: MSGTYPE msg_type (7..15); 1: reserved MISCOP; 2: reserved
// ACTIVATIONOP; 3: DLENGTH 11 on WriteData.
class aou_l3_bad_type_seq extends aou_l3_base_seq;
  `uvm_object_utils(aou_l3_bad_type_seq)

  int unsigned kind = 0;
  bit [3:0]    msg_type = 4'd7;

  function new(string name = "aou_l3_bad_type_seq");
    super.new(name);
  endfunction

  task body();
    aou_msg_raw m = aou_msg_raw::type_id::create("m");
    aou_granule_t g[$];
    case (kind)
      0: g.push_back({msg_type, rp, 34'h0});
      1: g.push_back({4'h0, 3'b011, 33'h0});
      2: g.push_back({4'h0, 3'b010, 4'd9, 29'h0});
      default: g.push_back({4'(AOU_MT_WDATA), rp, 2'b11, 32'h0});
    endcase
    m.set_granules(g);
    m.ignore_state = 1'b1;
    send_msg(m);
  endtask
endclass
