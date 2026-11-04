// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Macros of the UCIe FDI model. Include after uvm_macros.svh.

`ifndef UCIE_FDI_MACROS_SVH
`define UCIE_FDI_MACROS_SVH

// randomize() must never fail silently: without a constraint solver Verilator
// returns 0 and leaves every field zero.
`define UCIE_RANDOMIZE_WITH(OBJ, CONSTRAINTS) \
  if ((OBJ.randomize() with CONSTRAINTS) == 0) \
    `uvm_fatal("RANDOMIZE", {"randomize() with {...} failed for ", `"OBJ`"})

`endif  // UCIE_FDI_MACROS_SVH
