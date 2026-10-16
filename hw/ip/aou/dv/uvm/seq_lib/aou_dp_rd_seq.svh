// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reads one register field over APB.
class aou_dp_rd_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_dp_rd_seq)

  uvm_reg_field  f;
  uvm_reg_data_t value;

  function new(string name = "aou_dp_rd_seq");
    super.new(name);
  endfunction

  task body();
    rd_field(f, value);
  endtask
endclass
