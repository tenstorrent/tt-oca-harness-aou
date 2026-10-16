// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Checks the checkers: the subordinate flips read-data bits, drops writes and
// withdraws RVALID early, and the scoreboard and monitor must flag them. Those
// errors are demoted to info and counted; the test fails if either count is 0.
class aou_axi_selftest_neg_test extends aou_axi_selftest_test;
  `uvm_component_utils(aou_axi_selftest_neg_test)

  aou_axi_selftest_catcher catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    num_txns = 200;
    super.build_phase(phase);
    // AXI-R05 needs RVALID pending without RREADY.
    mcfg.timing.r_ready.set_range(0, 3);
    catcher = aou_axi_selftest_catcher::type_id::create("catcher");
    uvm_report_cb::add(null, catcher);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    sub.drv.fault_rdata_pct = 3;
    sub.drv.fault_wdrop_pct = 3;
    sub.drv.fault_rvalid_pct = 2;
  endfunction

  function void report_phase(uvm_phase phase);
    if (catcher.n_caught == 0)
      `uvm_error(get_type_name(), "injected data faults raised no scoreboard errors")
    if (catcher.n_proto == 0)
      `uvm_error(get_type_name(), "withdrawn RVALID raised no AXI-R05 errors")
    `uvm_info(get_type_name(), $sformatf("scoreboard flagged %0d, monitor flagged %0d",
                                         catcher.n_caught, catcher.n_proto), UVM_LOW)
  endfunction
endclass
