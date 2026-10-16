// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1 SV-UVM test include manifest, `include`d in module scope by tb/tb_top.sv
// under `ifdef UVM (the harness compile-order contract: tests are not a
// package). Thin classes on aou_base_test (ocah_test) that set aou_t1_env_cfg
// and name a virtual sequence from aou_seq_lib_pkg (docs/ARCHITECTURE.md,
// "Tests"). Scenario names and plan items: testlists/.
`include "uvm_macros.svh"
`include "aou_macros.svh"
`include "aou_base_test.svh"
`include "aou_sanity_test.svh"
`include "aou_t1_slice_test.svh"
`include "aou_t1_deact_test.svh"
`include "aou_t1_remote_act_test.svh"
`include "aou_t1_link_event_test.svh"
`include "aou_t1_lp_mode_test.svh"
`include "aou_t1_inject_test.svh"
`include "aou_t1_sw_reset_test.svh"
`include "aou_t1_hard_reset_test.svh"
`include "aou_dpf_tests.svh"
`include "stress/stress_tests.svh"
`include "link/link_tests.svh"
`include "errors/errors_tests.svh"
`include "lifecycle/lifecycle_tests.svh"
`include "matrix/matrix_tests.svh"
