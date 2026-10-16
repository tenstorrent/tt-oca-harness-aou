// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reset values of every register against the RDL (uvm_reg_hw_reset_seq).
class aou_reg_hw_reset_test extends aou_reg_base_test;
  `uvm_component_utils(aou_reg_hw_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_body();
    uvm_reg_hw_reset_seq s = uvm_reg_hw_reset_seq::type_id::create("hw_reset");
    s.model = env.regmodel;
    s.start(null);
  endtask
endclass
