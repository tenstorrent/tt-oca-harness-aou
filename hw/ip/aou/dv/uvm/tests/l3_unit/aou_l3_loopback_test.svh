// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Legal traffic both ways between two L3 models under the chosen packer and
// return policies: activation, random writes read back through the remote
// memories, deactivation. Expects no rule finding from either model and none
// from AOU_FDI_CHECKER.
class aou_l3_loopback_test extends aou_l3_unit_env_test;
  `uvm_component_utils(aou_l3_loopback_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    expect_true(chk.total() == 0, $sformatf("no rule findings (%s)", chk.summary()));
  endfunction
endclass
