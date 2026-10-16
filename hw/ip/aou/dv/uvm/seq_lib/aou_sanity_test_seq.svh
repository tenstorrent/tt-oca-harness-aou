// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bring-up scenario (aou_sanity_test): link up through the FDI agents,
// activation from a random side, a few transactions each way through the
// scoreboard, drain. One pass of the base body at the scenario seed the test
// set, so a failure replays from the simulator seed alone.
class aou_sanity_test_seq extends aou_base_test_seq;
  `uvm_object_utils(aou_sanity_test_seq)

  function new(string name = "aou_sanity_test_seq");
    super.new(name);
  endfunction

  task body();
    seed_scenario_rng();
    log_step("1", "link up");
    link_up();
    log_step("2", "activate");
    activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    log_step("3", $sformatf("%0d transactions per RP and direction", num_txns));
    traffic(AOU_T1_BOTH_DIRS, num_txns, null);
    log_step("4", "drain");
    drain();
  endtask
endclass
