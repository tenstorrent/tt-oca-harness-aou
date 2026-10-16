// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Register tests. They need only the APB port, so they run on aou_reg_top
// (make TB=reg) until the T1 top takes them over.
`timescale 1ns/1ps

package aou_reg_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import aou_apb_pkg::*;
  import aou_reg_pkg::*;

  `include "aou_reg_base_test.svh"
  `include "aou_reg_hw_reset_test.svh"
  `include "aou_reg_bit_bash_test.svh"
  `include "aou_reg_access_test.svh"
  `include "aou_reg_reserved_test.svh"
  `include "aou_reg_alias_test.svh"
  `include "aou_reg_feature_seq_test.svh"
endpackage
