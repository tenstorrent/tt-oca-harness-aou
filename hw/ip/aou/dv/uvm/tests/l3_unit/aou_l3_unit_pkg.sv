// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3 unit tests (TB=l3_unit). No DUT: models talk to each other and to
// AOU_FDI_CHECKER.
`timescale 1ns/1ps
package aou_l3_unit_pkg;
  import uvm_pkg::*;
  import aou_rule_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  import aou_l3_pkg::*;

  `include "aou_l3_unit_l4a.svh"
  `include "aou_l3_unit_link.svh"
  `include "aou_l3_unit_gen.svh"
  `include "aou_l3_unit_base_test.svh"
  `include "aou_l3_codec_test.svh"
  `include "aou_l3_crossflit_test.svh"
  `include "aou_l3_credit_test.svh"
  `include "aou_l3_link_test.svh"
  `include "aou_l3_unit_env_test.svh"
  `include "aou_l3_loopback_test.svh"
  `include "aou_l3_inject_test.svh"
  `include "aou_l3_dest_rp_test.svh"
endpackage
