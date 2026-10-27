// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// ACTIVATE_START swept across the end of a deactivation (aou_act_after_deact_vseq).
class aou_act_after_deact_test extends aou_base_test;
  `uvm_component_utils(aou_act_after_deact_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_act_after_deact_vseq";
    num_txns = 10;
  endfunction
endclass
