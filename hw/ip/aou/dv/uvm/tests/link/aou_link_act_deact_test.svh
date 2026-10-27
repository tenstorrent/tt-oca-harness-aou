// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Activation/deactivation loops from either side (aou_link_act_deact_vseq).
class aou_link_act_deact_test extends aou_base_test;
  `uvm_component_utils(aou_link_act_deact_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_link_act_deact_vseq";
    num_txns = 20;
  endfunction

  // A hang shows within 2 ms of simulated time; every scenario here,
  // the 2^18-cycle time-outs included, ends well before.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction

  // +early_act=1: the link stays down after reset until the test brings it up.
  function void configure();
    int early = 0;
    void'($value$plusargs("early_act=%d", early));
    if (early != 0) cfg.lsm_cfg.auto_bringup = 1'b0;
  endfunction
endclass
