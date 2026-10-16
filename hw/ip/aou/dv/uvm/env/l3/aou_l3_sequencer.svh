// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Message sequencer of the L3 agent. Sequences reach the model through
// p_sequencer.model for injections that are not messages.
class aou_l3_sequencer extends uvm_sequencer #(aou_msg);
  `uvm_component_utils(aou_l3_sequencer)

  aou_l3_model model;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
