// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// A DUT write as the responder hands it to L4a: the WriteReq and its
// AWLEN+1 WriteData messages.
class aou_l3_wr_txn extends uvm_object;
  `uvm_object_utils(aou_l3_wr_txn)

  aou_msg_wreq  req;
  aou_msg_wdata beats[$];
  int unsigned  ticket;

  function new(string name = "aou_l3_wr_txn");
    super.new(name);
  endfunction
endclass
