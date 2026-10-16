// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// ReadData wider than the DUT's AXI width (aou_rdata_wide_vseq, plan 9.21).
class aou_rdata_wide_test extends aou_base_test;
  `uvm_component_utils(aou_rdata_wide_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_rdata_wide_vseq";
    num_txns = 20;
  endfunction
endclass
