// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Error-injection tests (stream G): tests, included by aou_tests.sv (tb_top.sv) after aou_seq_lib_pkg.
`include "errors/aou_invalid_actmsg_test.svh"
`include "errors/aou_linkreset_timeout_test.svh"
`include "errors/aou_rx_msg_error_test.svh"
`include "errors/aou_axi_err_resp_test.svh"
`include "errors/aou_id_mismatch_test.svh"
`include "errors/aou_int_test.svh"
`include "errors/aou_credit_violation_test.svh"
`include "errors/aou_before_enable_test.svh"
`include "errors/aou_slv_id_mismatch_test.svh"
`include "errors/aou_rdata_wide_test.svh"
