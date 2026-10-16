// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// INCR bursts of the listed lengths (+dp_len; plan 4.9-4.15, 5.9-5.15) at any
// size and start address, each write read back; RLAST only on the last beat
// (5.19) is checked by the AXI monitor and scoreboard. Both directions.
class aou_dp_burst_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_burst_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.lens = '{1, 3, 7, 15};
    k.align = aou_dp_knobs::DP_ALIGN_ANY;
    k.strb = aou_dp_knobs::DP_STRB_FULL;
    k.loopback = 1'b1;
    k.batch = 4;
    k.wr_pct = 100;
    k.n = 32;
  endfunction
endclass
