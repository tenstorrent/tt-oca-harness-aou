// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI requests before AoU activation (aou_before_enable_vseq).
class aou_before_enable_test extends aou_base_test;
  `uvm_component_utils(aou_before_enable_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_before_enable_vseq";
    num_txns = 10;
  endfunction
endclass
