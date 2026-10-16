// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power mode with traffic (MAS §7.1 "Low Power mode"; plan 21.2-21.7).
// DUT flits are counted over an idle window after the link settles:
//   TX_LP_MODE=0                 flits keep flowing: at least a quarter of
//                                the flit slots (the L1 model inserts trdy
//                                holes);
//   TX_LP_MODE=1, threshold 0    fully gated: no flit while idle;
//   TX_LP_MODE=1, threshold T    a heartbeat: at least one flit and at most
//                                ceil(W / max(T+1, flit cycles)) + 1
//                                (BUGS/017 interim).
// Traffic both ways runs in LP mode, so the remote side completes only if the
// DUT still returns credits (21.6), and the mode is switched on and off
// mid-traffic (21.7).
// Knobs: +threshold=0..255 (random, 0 one time in three) +T1_TXN.
class aou_lp_mode_traffic_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_lp_mode_traffic_vseq)

  // Cycles per 256-byte flit at the build's FDI width.
  localparam int unsigned FLIT_CYCLES = 256 / AOU_T1_BEAT0;

  int unsigned idle_n;

  function new(string name = "aou_lp_mode_traffic_vseq");
    super.new(name);
  endfunction

  task body();
    int thr = arg_int("threshold", ($urandom_range(2) == 0) ? 0 : $urandom_range(255, 1));
    int unsigned win = 4000 + 16 * thr;
    int unsigned slot = (thr + 1 > FLIT_CYCLES) ? thr + 1 : FLIT_CYCLES;
    int unsigned base;
    int unsigned lp;
    `uvm_info(get_type_name(), $sformatf("LP threshold %0d, idle window %0d cycles", thr, win),
              UVM_LOW)
    link_up();
    sw_activate();
    check_traffic(num_txns);
    idle_flits(win);
    base = idle_n;
    if (base < win / FLIT_CYCLES / 4)
      `uvm_error(get_type_name(), $sformatf("T1-L20: TX_LP_MODE=0 but %0d flits in %0d cycles",
                                            base, win))
    lp_mode(1'b1, thr);
    check_traffic(num_txns);
    idle_flits(win);
    lp = idle_n;
    `uvm_info(get_type_name(), $sformatf("idle flits in %0d cycles: %0d, LP mode (%0d): %0d",
                                         win, base, thr, lp), UVM_LOW)
    if (thr == 0 && lp != 0)
      `uvm_error(get_type_name(), $sformatf("T1-L21: fully gated LP mode sent %0d idle flits", lp))
    if (thr != 0 && (lp == 0 || lp > (win + slot - 1) / slot + 1))
      `uvm_error(get_type_name(), $sformatf(
                 "T1-L22: LP heartbeat %0d flits in %0d cycles (threshold %0d, BUGS/017 interim)",
                 lp, win, thr))
    // Mode changes while traffic runs must not lose or corrupt anything.
    traffic_nb(AOU_T1_BOTH_DIRS, num_txns);
    repeat ($urandom_range(4, 1)) begin
      wait_cycles($urandom_range(400, 20));
      lp_mode(1'($urandom_range(1)), $urandom_range(2) == 0 ? 0 : $urandom_range(255, 1));
    end
    wait_traffic();
    drain();
    lp_mode(1'b0, -1);
    idle_flits(win);
    lp = idle_n;
    if (lp < win / FLIT_CYCLES / 4)
      `uvm_error(get_type_name(), $sformatf("T1-L20: %0d idle flits after TX_LP_MODE returned to 0",
                                            lp))
    sw_deactivate();
  endtask

  // idle_n: DUT flits received by the remote die in `win` cycles, after a settling
  // time for credit returns.
  task idle_flits(int unsigned win);
    int unsigned c0;
    wait_cycles(2000);
    c0 = env.l3.model.rx_flits;
    wait_cycles(win);
    idle_n = env.l3.model.rx_flits - c0;
  endtask
endclass
