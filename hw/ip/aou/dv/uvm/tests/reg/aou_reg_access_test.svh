// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Every field behaves as its RDL access policy says (see aou_reg_access_seq).
class aou_reg_access_test extends aou_reg_base_test;
  `uvm_component_utils(aou_reg_access_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_body();
    aou_reg_access_seq s = aou_reg_access_seq::type_id::create("access");
    prep(s);
    s.start(null);
  endtask
endclass
