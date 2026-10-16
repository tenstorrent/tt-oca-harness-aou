// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class aou_msg_rreq extends aou_msg_req;
  `uvm_object_utils(aou_msg_rreq)

  function new(string name = "aou_msg_rreq");
    super.new(name);
    msg_type = AOU_MT_RREQ;
  endfunction
endclass
