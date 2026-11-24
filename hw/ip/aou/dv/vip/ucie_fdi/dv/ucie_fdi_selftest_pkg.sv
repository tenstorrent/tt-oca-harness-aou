// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// Self-test of the UCIe FDI model: the model's Adapter side against a
// loopback Protocol Layer stub, with an end-to-end scoreboard.

package ucie_fdi_selftest_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie_fdi_pkg::*;
  import ucie_lsm_pkg::*;

  `include "ucie_pl_stub.svh"
  `include "ucie_fdi_selftest_env.svh"
  `include "ucie_fdi_selftest_tests.svh"
endpackage
