// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power mode (FEAT-R08; BUGS/017 interim expectation). After traffic
// drains and credits settle, counts the flits the DUT starts in an idle window
// of WINDOW cycles:
// - TX_LP_MODE=0: flits keep flowing, at least a quarter of the flit slots
//   (the L1 model's trdy holes take some);
// - TX_LP_MODE=1, threshold 0: no flit;
// - TX_LP_MODE=1, threshold T: at most one per max(T+1, flit cycles) plus one,
//   and at least half the rate of one flit T+1 cycles after each flit ends.
// Then traffic runs again, so leaving the idle state is covered too.
class aou_lp_mode_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_lp_mode_vseq)

  localparam int unsigned WINDOW = 2000;
  localparam int unsigned SETTLE = 500;

  aou_flit_counter cnt;

  function new(string name = "aou_lp_mode_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    if (!uvm_config_db#(aou_flit_counter)::get(null, "*", "lp_flit_counter", cnt))
      `uvm_fatal(get_type_name(), "no aou_flit_counter under lp_flit_counter")
  endtask

  task scenario();
    int unsigned flit_cyc = 256 / cfg.fdi_cfg[cfg.lsm_cfg.active_phy].beat_bytes;
    int unsigned slots = WINDOW / flit_cyc;
    int unsigned n;
    int unsigned lo;
    int unsigned hi;
    time t0;
    super.scenario();
    drain();
    wait_cycles(SETTLE);
    t0 = $time;
    wait_cycles(WINDOW);
    n = cnt.count(t0, $time);
    if (k.feat.lp_mode == 0) begin
      lo = slots / 4;
      hi = slots + 1;
    end else if (k.feat.lp_threshold == 0) begin
      lo = 0;
      hi = 0;
    end else begin
      int unsigned per = (k.feat.lp_threshold + 1 > flit_cyc) ? k.feat.lp_threshold + 1 : flit_cyc;
      // Half the rate of a heartbeat T+1 cycles after each flit ends.
      lo = WINDOW / (k.feat.lp_threshold + 1 + flit_cyc) / 2;
      if (lo == 0) lo = 1;
      hi = (WINDOW + per - 1) / per + 1;
    end
    if (n < lo || n > hi)
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R08: TX_LP_MODE=%0d threshold=%0d: %0d flits in %0d idle cycles, expected %0d..%0d",
          k.feat.lp_mode, k.feat.lp_threshold, n, WINDOW, lo, hi))
    else
      `uvm_info(get_type_name(), $sformatf("TX_LP_MODE=%0d thr=%0d: %0d idle flits (%0d..%0d)",
                                           k.feat.lp_mode, k.feat.lp_threshold, n, lo, hi), UVM_LOW)
    super.scenario();
  endtask
endclass
