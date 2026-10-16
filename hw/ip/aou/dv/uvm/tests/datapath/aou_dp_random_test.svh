// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Constrained-random legal AXI4 traffic (INCR, 1-256 beats, every size, 4KB
// rule, mixed strobes) from the remote die (+dp_dir=r2l; old D31) or both
// directions at once (+dp_dir=both; D41). +dp_profile picks a profile
// ("rand", "stall", "long"). Runs the env's own random sequence.
class aou_dp_random_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    use_dp_seq = 1'b0;
  endfunction

  function void set_knobs();
    k.dir = AOU_T1_R2L;
    k.n = 300;
  endfunction
endclass
