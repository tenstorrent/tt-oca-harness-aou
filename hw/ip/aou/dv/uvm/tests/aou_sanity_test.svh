// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bring-up gate test and the default T1 test: the DUT comes up through the
// FDI agents, activates, passes a few AXI transactions each way through the
// scoreboard and drains, with every T1 checker on. One pass of
// aou_sanity_test_seq through the library's run_single_scenario(), at the
// simulator seed; +T1_TXN=<n> sets the transaction count (default 8).
class aou_sanity_test extends aou_base_test;
  `uvm_component_utils(aou_sanity_test)

  function new(string name = "aou_sanity_test", uvm_component parent = null);
    super.new(name, parent);
    num_txns = 8;
  endfunction

  virtual function ocah_sequence create_scenario_seq();
    return aou_sanity_test_seq::type_id::create("sanity_seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, {get_type_name(), " running"});
    run_single_scenario();
    repeat (100) @(env.lsm_vif.mon_cb);
    check_cred_return();
    phase.drop_objection(this, {get_type_name(), " done"});
  endtask
endclass
