// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credits/link tests (stream G): tests, included by aou_tests.sv (tb_top.sv) after aou_seq_lib_pkg.
`include "link/aou_link_act_deact_test.svh"
`include "link/aou_link_force_deact_test.svh"
`include "link/aou_zero_credit_test.svh"
`include "link/aou_credit_return_test.svh"
`include "link/aou_act_after_deact_test.svh"
`include "link/aou_rx_credit_test.svh"
`include "link/aou_act_rx_drain_test.svh"
`include "link/aou_deact_ctrl_test.svh"
`include "link/aou_remote_react_test.svh"
`include "link/aou_act_flit_test.svh"
