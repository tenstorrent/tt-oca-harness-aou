// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// L1/L2 self-tests on the T1 top: a small environment with the FDI agents of
// every PHY and the link-state agent, and bringup tests.

package aou_fdi_test_pkg;
  import uvm_pkg::*;
  import aou_rule_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  import aou_fdi_pkg::*;
  import aou_lsm_pkg::*;
  import aou_axi_pkg::*;
  import aou_t1_env_pkg::aou_t1_rx_align_chk;

`ifdef TWO_PHY
  localparam int N_PHY = 2;
`else
  localparam int N_PHY = 1;
`endif
`ifdef AOU_RP_COUNT
  localparam int FDI_T1_RP_COUNT = `AOU_RP_COUNT;
`else
  localparam int FDI_T1_RP_COUNT = 1;
`endif
`ifdef AOU_FDI_CONFIG
  localparam int FDI_CONFIG = `AOU_FDI_CONFIG;
`else
  localparam int FDI_CONFIG = 1;
`endif
  // Beat bytes per PHY for each FDI_CONFIG (integrator guide §3.10)
  localparam int BEAT0 = (FDI_CONFIG == 0 || FDI_CONFIG == 3) ? 32 : (FDI_CONFIG == 2) ? 128 : 64;
  localparam int BEAT1 = (FDI_CONFIG == 4) ? 128 : 64;

  `include "aou_fdi_msg_log.svh"
  `include "aou_fdi_t1_env.svh"
  `include "aou_fdi_t1_bringup_test.svh"
  `include "aou_fdi_t1_bringup_spec_test.svh"
  `include "aou_fdi_t1_linkerror_spec_test.svh"
  `include "aou_fdi_t1_linkdown_spec_test.svh"
  `include "aou_fdi_t1_link_stress_test.svh"
  `include "aou_fdi_t1_abort_test.svh"
endpackage
