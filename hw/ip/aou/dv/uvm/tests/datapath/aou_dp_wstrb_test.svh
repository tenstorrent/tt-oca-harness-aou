// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Write strobe patterns (+dp_strb=full|partial|sparse|zero; plan 4.18-4.21,
// 4.29): full strobes (WriteDataFull), fixed partial patterns (0x55, 0xAA,
// 0x0F, ...), two strobes per beat, and all-zero strobes (nothing written,
// OKAY). Single beats and short bursts, read back, both directions.
class aou_dp_wstrb_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_wstrb_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.lens = '{0, 1, 3};
    k.align = aou_dp_knobs::DP_ALIGN_ANY;
    k.strb = aou_dp_knobs::DP_STRB_PARTIAL;
    k.loopback = 1'b1;
    k.batch = 8;
    k.wr_pct = 100;
    k.n = 48;
  endfunction
endclass
