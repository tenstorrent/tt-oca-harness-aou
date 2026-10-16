// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credit advertisement and return corners (aou_credit_return_vseq).
class aou_credit_return_test extends aou_base_test;
  `uvm_component_utils(aou_credit_return_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_credit_return_vseq";
    num_txns = 30;
  endfunction

  // A hang shows within 2 ms of simulated time; every scenario here,
  // the 2^18-cycle time-outs included, ends well before.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
