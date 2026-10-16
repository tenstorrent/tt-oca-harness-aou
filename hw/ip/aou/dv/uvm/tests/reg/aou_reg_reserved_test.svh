// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reserved bits read 0 and unmapped offsets are inert (see aou_reg_reserved_seq).
class aou_reg_reserved_test extends aou_reg_base_test;
  `uvm_component_utils(aou_reg_reserved_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_body();
    aou_reg_reserved_seq s = aou_reg_reserved_seq::type_id::create("reserved");
    prep(s);
    s.start(null);
  endtask
endclass
