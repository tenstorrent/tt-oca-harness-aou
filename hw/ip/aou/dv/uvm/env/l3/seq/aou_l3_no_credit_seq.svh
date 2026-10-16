// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Injection: n WriteResp messages sent whether or not credit covers them, so
// the receiver sees more granules than it advertised (AOU-R16).
class aou_l3_no_credit_seq extends aou_l3_base_seq;
  `uvm_object_utils(aou_l3_no_credit_seq)

  int unsigned n = 1;

  function new(string name = "aou_l3_no_credit_seq");
    super.new(name);
  endfunction

  task body();
    for (int unsigned i = 0; i < n; i++) begin
      aou_msg_wresp m = aou_msg_wresp::type_id::create("m");
      m.rp = rp;
      m.id = 10'(i);
      m.ignore_credits = 1'b1;
      send_msg(m);
    end
  endtask
endclass
