// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX_LP_MODE written on the edge a flit's first half-chunk goes out, with a
// message waiting for the next cycle (aou_lp_mode_align_vseq, BUGS/034). The
// Adapter keeps pl_trdy high, and the remote die uses PHY0, the half-width
// path of the two-PHY builds.
class aou_lp_mode_align_test extends aou_base_test;
  `uvm_component_utils(aou_lp_mode_align_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_lp_mode_align_vseq";
    num_txns = 10;
  endfunction

  function void configure();
    foreach (cfg.fdi_cfg[p]) cfg.fdi_cfg[p].trdy_policy = AOU_TRDY_ALWAYS;
    cfg.lsm_cfg.active_phy = 0;
  endfunction

  // A hang shows within 2 ms of simulated time.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
