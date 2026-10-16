// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// G1a end-to-end slice (aou_t1_slice_vseq).
class aou_t1_slice_test extends aou_base_test;
  `uvm_component_utils(aou_t1_slice_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_t1_slice_vseq";
  endfunction
endclass
