// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The DUT's advertised RX credit against its FIFO depths, and credit held while
// the M port back-pressures (aou_rx_credit_vseq).
class aou_rx_credit_test extends aou_base_test;
  `uvm_component_utils(aou_rx_credit_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_rx_credit_vseq";
    num_txns = 48;
  endfunction

  // Enough remote requests in flight to fill more of the RX FIFOs than the
  // stages after them can take.
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
