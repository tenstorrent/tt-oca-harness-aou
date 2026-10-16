// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Register layer: the generated AoU core register model wired to the APB agent,
// the field policy, register checks and feature-programming sequences.
`timescale 1ns/1ps

package aou_reg_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import aou_apb_pkg::*;
  import aou_core_csr_uvm_pkg::*;

  typedef enum bit [1:0] {
    AOU_REG_ACTIVATE,
    AOU_REG_DEACTIVATE,
    AOU_REG_FORCE_DEACTIVATE
  } aou_reg_activation_op_e;

  `include "aou_reg_burstlen_cb.svh"
  `include "aou_reg_policy.svh"
  `include "aou_reg_env.svh"
  `include "aou_reg_base_seq.svh"
  // Register checks
  `include "aou_reg_access_seq.svh"
  `include "aou_reg_reserved_seq.svh"
  `include "aou_reg_alias_seq.svh"
  // Feature programming
  `include "aou_reg_activation_seq.svh"
  `include "aou_reg_split_seq.svh"
  `include "aou_reg_aggregator_seq.svh"
  `include "aou_reg_early_resp_seq.svh"
  `include "aou_reg_qos_seq.svh"
  `include "aou_reg_dest_rp_seq.svh"
  `include "aou_reg_lp_mode_seq.svh"
  `include "aou_reg_int_mask_seq.svh"
  `include "aou_reg_error_info_seq.svh"
  `include "aou_reg_timeout_seq.svh"
  `include "aou_reg_feature_vseq.svh"
endpackage
