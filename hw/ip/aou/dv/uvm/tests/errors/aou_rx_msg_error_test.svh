// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Malformed messages from the remote die (aou_rx_msg_error_vseq).
class aou_rx_msg_error_test extends aou_base_test;
  `uvm_component_utils(aou_rx_msg_error_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_rx_msg_error_vseq";
    num_txns = 10;
  endfunction

  // A hang shows within 2 ms of simulated time; every scenario here,
  // the 2^18-cycle time-outs included, ends well before.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
