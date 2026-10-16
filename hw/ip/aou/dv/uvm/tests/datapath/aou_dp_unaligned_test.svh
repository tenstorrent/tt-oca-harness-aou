// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Issue #56 and plan 7.11: unaligned and narrow writes at all offsets
// (aou_dp_unaligned_vseq), then unaligned narrow bursts with random strobes.
class aou_dp_unaligned_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_unaligned_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_dp_unaligned_vseq";
  endfunction

  function void set_knobs();
    k.sizes = '{0, 1, 2, 3, 4, 5};
    k.lens = '{0, 1, 2, 3, 7};
    k.align = aou_dp_knobs::DP_ALIGN_UNALIGNED;
    k.strb = aou_dp_knobs::DP_STRB_RANDOM;
    k.loopback = 1'b1;
    k.batch = 8;
    k.wr_pct = 100;
    k.n = 48;
  endfunction
endclass
