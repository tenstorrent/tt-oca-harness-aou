// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// DFT scan mode and the software reset path (aou_dft_scan_vseq, plan 11.19).
class aou_dft_scan_test extends aou_base_test;
  `uvm_component_utils(aou_dft_scan_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_dft_scan_vseq";
    num_txns = 20;
  endfunction
endclass
