// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Monitor's internal state for one transaction or one W burst; never published.
class aou_axi_mon_item extends uvm_sequence_item;
  `uvm_object_utils(aou_axi_mon_item)

  aou_axi_txn      txn;
  longint unsigned addr_cyc;   // AW/AR handshake
  longint unsigned w_cyc;      // last W handshake
  longint unsigned first_cyc;  // first cycle the first R beat was valid
  int unsigned     beats;      // R beats received

  function new(string name = "aou_axi_mon_item");
    super.new(name);
  endfunction
endclass
