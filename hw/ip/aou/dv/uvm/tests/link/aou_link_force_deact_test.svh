// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Forced deactivation through DEACTIVATE_FORCE, each ended by a software reset
// (aou_link_force_deact_vseq).
class aou_link_force_deact_test extends aou_base_test;
  `uvm_component_utils(aou_link_force_deact_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_link_force_deact_vseq";
    num_txns = 20;
  endfunction

  // A hang shows within 2 ms of simulated time; every scenario here,
  // the 2^18-cycle time-outs included, ends well before.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
