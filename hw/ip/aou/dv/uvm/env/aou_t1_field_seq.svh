// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Writes one register field (others keep their mirrored values).
class aou_t1_field_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_t1_field_seq)

  uvm_reg_field f;
  uvm_reg_data_t value = 0;

  function new(string name = "aou_t1_field_seq");
    super.new(name);
  endfunction

  task body();
    want_value(f, value);
    commit();
  endtask
endclass
