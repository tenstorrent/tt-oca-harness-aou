// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 VNCHIPLabs
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The production AXI-R03 report remains an error; direct execution is an
// intentional negative control and must fail through the normal grader.
class aou_axi_r03_neg_test extends aou_axi_selftest_test;
  `uvm_component_utils(aou_axi_r03_neg_test)
  aou_axi_selftest_catcher catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mcfg.timing.b_ready.set_range(4, 8);
    catcher = aou_axi_selftest_catcher::type_id::create("catcher");
    catcher.r03_control = 1'b1;
    uvm_report_cb::add(null, catcher);
  endfunction

  task run_phase(uvm_phase phase);
    sub.drv.arm_bresp_stability_fault();
    super.run_phase(phase);
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (sub.drv.n_bresp_stall_faults == 0 || sub.drv.n_bresp_payload_mutations == 0)
      `uvm_error(get_type_name(), "STIMULUS_NOT_REACHED: no sampled B stall was mutated")
    if (catcher.n_axi_r03 == 0)
      `uvm_error(get_type_name(),
                 "AXI-R03 sensitivity failure: production monitor did not report the mutation")
    if (catcher.n_axi_r03 > 1 || catcher.n_caught > 1)
      `uvm_error(get_type_name(),
                 "AXI-R03 sensitivity failure: unexpected additional checker reports")
  endfunction
endclass
