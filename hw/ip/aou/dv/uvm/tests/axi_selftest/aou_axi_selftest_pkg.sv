// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

package aou_axi_selftest_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  import aou_axi_pkg::*;
  import aou_env_pkg::*;

  `include "aou_axi_selftest_catcher.svh"
  `include "aou_axi_selftest_test.svh"
  `include "aou_axi_selftest_neg_test.svh"
  `include "aou_axi_sb_reset_test.svh"
endpackage
