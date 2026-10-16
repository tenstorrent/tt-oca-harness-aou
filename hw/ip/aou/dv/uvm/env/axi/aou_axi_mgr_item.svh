// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Manager driver's internal per-transaction state; never leaves the agent.
class aou_axi_mgr_item extends uvm_sequence_item;
  `uvm_object_utils(aou_axi_mgr_item)

  aou_axi_txn  txn;
  bit          addr_started; // AW/AR taken by its channel thread
  bit          w_started;
  bit          addr_done;
  bit          w_done;
  bit          untouched;   // reset_flush: never reached the bus
  int unsigned beats_rcvd;

  function new(string name = "aou_axi_mgr_item");
    super.new(name);
  endfunction
endclass
