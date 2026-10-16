// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Single-beat transfers of every AxSIZE (plan 4.1-4.8, 5.1-5.8, 11.13), aligned,
// full strobes, each write read back (7.1-7.3, 7.10), both directions. The
// scoreboard checks bytes, OKAY responses and RLAST on every transfer (4.22,
// 5.18, 5.20). +dp_size picks sizes, +dp_len adds beats (128 B as 2 x 64 B),
// +remote_bytes=128 lets the remote die send 128 B beats (WriteData1024).
class aou_dp_size_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_size_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.sizes = '{0, 1, 2, 3, 4, 5, 6, 7};
    k.lens = '{0};
    k.align = aou_dp_knobs::DP_ALIGN_ALIGNED;
    k.strb = aou_dp_knobs::DP_STRB_FULL;
    k.loopback = 1'b1;
    k.batch = 8;
    k.wr_pct = 100;
    k.n = 48;
  endfunction
endclass
