// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data patterns written and read back in both directions (plan 7.4-7.9):
// +dp_pattern=walk1|walk0|ones|zeros|checker|addr (aou_pattern_seq). The
// scoreboard compares every byte against the golden memories.
class aou_pattern_test extends aou_dp_base_test;
  `uvm_component_utils(aou_pattern_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.lens = '{0, 1, 3, 7, 15};
    k.loopback = 1'b1;
    k.batch = 8;
    k.wr_pct = 100;
    k.n = 64;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    aou_dp_seq::type_id::set_type_override(aou_pattern_seq::get_type());
  endfunction
endclass
