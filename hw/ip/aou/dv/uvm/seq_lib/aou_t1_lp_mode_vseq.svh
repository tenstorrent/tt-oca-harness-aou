// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power mode (plan 21.x). With TX_LP_MODE=0 the DUT keeps sending
// flits on an idle ENABLED link; with TX_LP_MODE=1 and threshold 0 it sends
// none without work (BUGS/017 interim: threshold 0 = no heartbeat). Traffic
// must pass in both modes. TX_LP_MODE is static configuration (T1-LP03), so
// each mode is its own activation session: deactivate, program, activate.
// The idle count is judged against the cycles the Adapter could take a beat
// (pl_trdy high, no stall), so the pl_trdy policy a seed draws doesn't
// decide it: with TX_LP_MODE=0 the DUT must send at least one flit per 16 such
// cycles, the same rate as one flit per 16 cycles with pl_trdy always high.
class aou_t1_lp_mode_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_lp_mode_vseq)

  function new(string name = "aou_t1_lp_mode_vseq");
    super.new(name);
  endfunction

  int unsigned window = 2000;
  int unsigned n_idle;   // result of idle_flits(): DUT flits
  int unsigned n_ready;  // ... and cycles the Adapter could take a beat

  // DUT flits seen by L3 in an idle window, and the Adapter-ready cycles of
  // the active PHY in the same window.
  task idle_flits();
    ucie_fdi_monitor mon = env.fdi[cfg.lsm_cfg.active_phy].mon;
    int unsigned start;
    int unsigned start_ready;
    drain();
    wait_cycles(200);
    start = env.bridge.n_flits;
    start_ready = mon.n_tx_ready;
    wait_cycles(window);
    n_idle = env.bridge.n_flits - start;
    n_ready = mon.n_tx_ready - start_ready;
  endtask

  // A new activation session with the mode programmed while DISABLED.
  task session(bit en, int threshold);
    deactivate(AOU_T1_BY_APB);
    lp_mode(en, threshold);
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
  endtask

  task body();
    int unsigned n_off;
    int unsigned n_on;
    int unsigned ready_off;
    int unsigned ready_on;
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    idle_flits();
    n_off = n_idle;
    ready_off = n_ready;
    session(1'b1, 0);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    idle_flits();
    n_on = n_idle;
    ready_on = n_ready;
    `uvm_info(get_type_name(), $sformatf({"idle DUT flits in %0d cycles: LP off %0d ",
                                          "(%0d Adapter-ready), LP on %0d (%0d Adapter-ready)"},
                                         window, n_off, ready_off, n_on, ready_on), UVM_LOW)
    // Rejects a window too thin to judge: with almost no ready cycles the rate
    // check below would pass on almost no flits. The policies the bench draws
    // stay far above this; only an extreme +trdy override could come near it.
    if (ready_off < window / 16)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-LP01: only %0d of %0d cycles had pl_trdy high, too few to judge",
                 ready_off, window))
    if (n_off < ready_off / 16)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-LP01: %0d flits in %0d Adapter-ready cycles with TX_LP_MODE=0",
                 n_off, ready_off))
    if (n_on > 4)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-LP02: %0d idle flits with TX_LP_MODE=1, threshold 0", n_on))
    session(1'b0, 0);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
  endtask
endclass
