// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of the L3 message and injection sequences.
class aou_l3_base_seq extends uvm_sequence #(aou_msg);
  `uvm_object_utils(aou_l3_base_seq)
  `uvm_declare_p_sequencer(aou_l3_sequencer)

  bit [1:0] rp = 2'd0;

  function new(string name = "aou_l3_base_seq");
    super.new(name);
  endfunction

  task send_msg(aou_msg m);
    start_item(m);
    finish_item(m);
  endtask
endclass
