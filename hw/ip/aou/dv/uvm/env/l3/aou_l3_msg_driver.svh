// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Hands sequence items to the model's send(); the packer decides when they
// reach a flit.
class aou_l3_msg_driver extends uvm_driver #(aou_msg);
  `uvm_component_utils(aou_l3_msg_driver)

  aou_l3_model model;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      model.send(req);
      seq_item_port.item_done();
    end
  endtask
endclass
