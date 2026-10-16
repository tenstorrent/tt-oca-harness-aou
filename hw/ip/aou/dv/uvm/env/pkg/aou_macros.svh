// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Testbench-wide macros. Include after uvm_macros.svh.

`ifndef AOU_MACROS_SVH
`define AOU_MACROS_SVH

// randomize() must never fail silently: without a constraint solver Verilator
// returns 0 and leaves every field zero.
`define AOU_RANDOMIZE(OBJ) \
  if (OBJ.randomize() == 0) \
    `uvm_fatal("RANDOMIZE", {"randomize() failed for ", `"OBJ`"})

`define AOU_RANDOMIZE_WITH(OBJ, CONSTRAINTS) \
  if ((OBJ.randomize() with CONSTRAINTS) == 0) \
    `uvm_fatal("RANDOMIZE", {"randomize() with {...} failed for ", `"OBJ`"})

`endif  // AOU_MACROS_SVH
