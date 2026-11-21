// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// The bench's layer on the UCIe FDI model (vip/ucie_fdi): what about the
// FDI is AoU's or the DUT's rather than UCIe's. The DUT's bringup pins
// (aou_bringup_if) driven and sampled with the link state, the reference
// model of the DUT's bringup controller (integrator guide §3.14-3.16, §6.6),
// and the bench's FDI coverage collectors, all held by aou_fdi_layer, an
// observer of the model's link-state monitor.

package aou_fdi_layer_pkg;
  import uvm_pkg::*;
  import aou_rule_pkg::*;
  import aou_fc_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_fc_macros.svh"
  import ucie_fdi_pkg::*;
  import ucie_lsm_pkg::*;

  // States of the bringup controller (integrator guide §6.6)
  typedef enum bit [3:0] {
    BRG_RESET,
    BRG_WAIT_PRESENCE,
    BRG_WAKE_ASSERT,
    BRG_WAKE_WAIT_ACK,
    BRG_REQ_ACTIVE,
    BRG_ACTIVE,
    BRG_LINKERROR,
    BRG_RETRAIN,
    BRG_L1,
    BRG_L1_CLK_WAKE,
    BRG_LINKDOWN         // Adapter in LinkReset/Disabled
  } aou_brg_state_e;

  // Bringup software pins of the DUT (integrator guide §3.15)
  typedef enum bit {
    LSM_SW_ACTIVATE,
    LSM_SW_LINKERROR
  } aou_lsm_sw_e;

  // The DUT's bringup pins of one clock (aou_bringup_if), sampled by
  // aou_fdi_layer next to the model's link-state sample.
  typedef struct {
    bit         sw_activate;
    bit         sw_linkerror;
    logic [3:0] fsm_state;
    bit         link_up;
    bit         int_activate;
    bit         req_linkreset;
    bit         act_st_disabled;
    bit         sw_reset;
  } aou_brg_obs_t;

  `include "l1/aou_fdi_fc_bins.svh"
  `include "l1/aou_fdi_cov.svh"
  `include "l2/aou_lsm_fc_bins.svh"
  `include "l2/aou_lsm_cov.svh"
  `include "l2/aou_bringup_model.svh"
  `include "aou_fdi_layer.svh"

endpackage
