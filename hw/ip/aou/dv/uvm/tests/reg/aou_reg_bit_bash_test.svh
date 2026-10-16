// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Walks a 1 and a 0 through every bit of every register (uvm_reg_bit_bash_seq).
// Bits are skipped only where aou_reg_policy turns comparison off: RDL status
// fields with no reset value and the self-clearing controls ACTIVATE_START,
// DEACTIVATE_START and DEACTIVATE_FORCE (the bash writes them as 0). W1C flags
// are bashed: writing 1 to a clear flag must leave it 0.
class aou_reg_bit_bash_test extends aou_reg_base_test;
  `uvm_component_utils(aou_reg_bit_bash_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_body();
    uvm_reg_bit_bash_seq s = uvm_reg_bit_bash_seq::type_id::create("bit_bash");
    s.model = env.regmodel;
    s.start(null);
  endtask
endclass
