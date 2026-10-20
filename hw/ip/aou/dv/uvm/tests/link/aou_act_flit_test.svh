// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credited messages waiting as the DUT sends an Activation message
// (aou_act_flit_vseq, AoU v0.8 4.4).
class aou_act_flit_test extends aou_base_test;
  `uvm_component_utils(aou_act_flit_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_act_flit_vseq";
    num_txns = 8;
  endfunction
endclass
