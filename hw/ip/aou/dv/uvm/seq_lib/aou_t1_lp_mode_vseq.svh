// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power mode (plan 21.x). With TX_LP_MODE=0 the DUT keeps sending
// flits on an idle ENABLED link; with TX_LP_MODE=1 and threshold 0 it sends
// none without work (BUGS/017 interim: threshold 0 = no heartbeat). Traffic
// must pass in both modes.
class aou_t1_lp_mode_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_lp_mode_vseq)

  function new(string name = "aou_t1_lp_mode_vseq");
    super.new(name);
  endfunction

  int unsigned window = 2000;
  int unsigned n_idle;   // result of idle_flits()

  // DUT flits seen by L3 in an idle window.
  task idle_flits();
    int unsigned start;
    drain();
    wait_cycles(200);
    start = env.bridge.n_flits;
    wait_cycles(window);
    n_idle = env.bridge.n_flits - start;
  endtask

  task body();
    int unsigned n_off;
    int unsigned n_on;
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    idle_flits();
    n_off = n_idle;
    lp_mode(1'b1, 0);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    idle_flits();
    n_on = n_idle;
    `uvm_info(get_type_name(), $sformatf("idle DUT flits in %0d cycles: LP off %0d, LP on %0d",
                                         window, n_off, n_on), UVM_LOW)
    if (n_off < window / 4 / 4)
      `uvm_error(get_type_name(), $sformatf("T1-LP01: %0d flits with TX_LP_MODE=0", n_off))
    if (n_on > 4)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-LP02: %0d idle flits with TX_LP_MODE=1, threshold 0", n_on))
    lp_mode(1'b0, 0);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
  endtask
endclass
