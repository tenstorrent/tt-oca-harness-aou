// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1 sequence library: every virtual sequence and the AXI/L3 sequences they
// compose, on aou_base_test_seq (uvm/env). The tests that start them are
// uvm/tests/aou_tests.sv, compiled in tb_top.sv after this package.
`timescale 1ns/1ps
package aou_seq_lib_pkg;
  import uvm_pkg::*;
  import ocah_lib_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  import aou_rule_pkg::*;
  import aou_axi_pkg::*;
  import aou_fdi_pkg::*;
  import aou_lsm_pkg::*;
  import aou_l3_pkg::*;
  import aou_reg_pkg::*;
  import aou_core_csr_uvm_pkg::*;
  import aou_t1_env_pkg::*;

  `include "aou_sanity_test_seq.svh"
  `include "aou_t1_slice_vseq.svh"
  `include "aou_t1_deact_vseq.svh"
  `include "aou_t1_remote_act_vseq.svh"
  `include "aou_t1_link_event_vseq.svh"
  `include "aou_t1_lp_mode_vseq.svh"
  `include "aou_t1_inject_vseq.svh"
  `include "aou_t1_sw_reset_vseq.svh"
  `include "aou_t1_hard_reset_vseq.svh"
  `include "aou_dpf_seqs.svh"
  `include "stress/stress_seqs.svh"
  `include "link/link_seqs.svh"
  `include "errors/errors_seqs.svh"
  `include "lifecycle/lifecycle_seqs.svh"
  `include "matrix/matrix_seqs.svh"
endpackage
