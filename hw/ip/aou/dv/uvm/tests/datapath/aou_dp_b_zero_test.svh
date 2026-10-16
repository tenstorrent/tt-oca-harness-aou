// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Issue #64 (plan 16.16): back-to-back single-beat writes with zero delays end
// to end, so the M-port subordinate presents B in the cycle after the AW/W
// handshakes (and R after AR); both directions. The AXI monitors cover the
// zero-cycle case (zero_cg); DP-R01 fails the test if the M port never saw it.
class aou_dp_b_zero_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_b_zero_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    use_dp_seq = 1'b0;
  endfunction

  function void set_knobs();
    k.profile = "b_zero";
    k.n = 64;
  endfunction

  function void check_phase(uvm_phase phase);
    int unsigned nz = 0;
    super.check_phase(phase);
    foreach (env.m_sub[r]) if (env.m_sub[r].mon != null) nz += env.m_sub[r].mon.n_b_zero;
    if (nz == 0)
      `uvm_error(get_type_name(), "DP-R01: no B presented zero cycles after AW/W at the M port")
    else
      `uvm_info(get_type_name(), $sformatf("%0d zero-cycle B responses at the M port", nz), UVM_LOW)
  endfunction
endclass
