// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Stress tests (stream F): tests, included by aou_tests.sv (tb_top.sv) after aou_seq_lib_pkg.
`uvm_analysis_imp_decl(_l1tx)
`uvm_analysis_imp_decl(_l1rx)
`include "stress/aou_qos_order_test.svh"
`include "stress/aou_pack_stats.svh"
`include "stress/aou_pack_test.svh"
`include "stress/aou_pattern_test.svh"
`include "stress/aou_addr_test.svh"
`include "stress/aou_stress_test.svh"
