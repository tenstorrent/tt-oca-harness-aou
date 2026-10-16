// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Addresses above the 64 KiB window alias the registers (see aou_reg_alias_seq).
class aou_reg_alias_test extends aou_reg_base_test;
  `uvm_component_utils(aou_reg_alias_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_body();
    aou_reg_alias_seq s = aou_reg_alias_seq::type_id::create("alias");
    prep(s);
    s.start(null);
  endtask
endclass
