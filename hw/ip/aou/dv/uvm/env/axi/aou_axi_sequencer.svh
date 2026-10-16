// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class aou_axi_sequencer extends uvm_sequencer #(aou_axi_txn);
  `uvm_component_utils(aou_axi_sequencer)

  aou_axi_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
