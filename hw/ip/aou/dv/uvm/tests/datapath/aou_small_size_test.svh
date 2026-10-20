// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Register-like accesses: every AxSIZE below 5 (1 to 16 bytes), unaligned
// starts, partial strobes, single beats with a few 2- and 4-beat bursts, both
// directions, each write read back. The scoreboard checks the bytes. Along the
// way, a narrow read gets ReadData256 (AoU 5.7: ReadData DLENGTH is
// max(ARSIZE, 256 bits); AOU-R13 on the DUT's ReadData) and a narrow write's
// WriteData is at least 256 bits (T1-L4A02). +remote_bytes sets the remote
// die's widths, so a mixed build puts every pairing under small requests.
class aou_small_size_test extends aou_dp_base_test;
  `uvm_component_utils(aou_small_size_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.dir = AOU_T1_BOTH_DIRS;
    k.sizes = '{0, 1, 2, 3, 4, 2, 3};
    k.lens = '{0, 0, 0, 1, 0, 3};
    k.align = aou_dp_knobs::DP_ALIGN_UNALIGNED;
    k.strb = aou_dp_knobs::DP_STRB_PARTIAL;
    k.loopback = 1'b1;
    k.batch = 8;
    k.wr_pct = 100;
    k.n = 56;
  endfunction
endclass
