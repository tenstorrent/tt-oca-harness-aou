// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Re-activation with remote requests still in the DUT's RX FIFO
// (aou_act_rx_drain_vseq).
class aou_act_rx_drain_test extends aou_base_test;
  `uvm_component_utils(aou_act_rx_drain_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_act_rx_drain_vseq";
    num_txns = 24;
  endfunction

  // More remote requests in flight than the stages after the RX FIFO hold.
  function void configure();
    foreach (cfg.r_mgr_cfg[r]) begin
      cfg.r_mgr_cfg[r].max_wr_outstanding = 32;
      cfg.r_mgr_cfg[r].max_rd_outstanding = 32;
    end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
