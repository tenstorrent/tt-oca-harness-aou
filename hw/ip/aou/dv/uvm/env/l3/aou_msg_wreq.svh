// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class aou_msg_wreq extends aou_msg_req;
  `uvm_object_utils(aou_msg_wreq)

  function new(string name = "aou_msg_wreq");
    super.new(name);
    msg_type = AOU_MT_WREQ;
  endfunction
endclass
