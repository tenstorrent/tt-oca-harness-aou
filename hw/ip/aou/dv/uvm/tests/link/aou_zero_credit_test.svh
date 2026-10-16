// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Zero credit for one class, then a late grant (aou_zero_credit_vseq).
class aou_zero_credit_test extends aou_base_test;
  `uvm_component_utils(aou_zero_credit_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_zero_credit_vseq";
    num_txns = 4;
    // One direction only: the class decides which.
    min_l2r = 0;
    min_r2l = 0;
  endfunction

  // A hang shows within 2 ms of simulated time; every scenario here,
  // the 2^18-cycle time-outs included, ends well before.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
