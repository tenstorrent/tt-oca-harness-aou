// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reset, low-power and link-event tests (stream G): tests, included by aou_tests.sv (tb_top.sv) after aou_seq_lib_pkg.
`include "lifecycle/aou_link_event_test.svh"
`include "lifecycle/aou_lp_mode_traffic_test.svh"
`include "lifecycle/aou_lp_mode_align_test.svh"
`include "lifecycle/aou_reset_test.svh"
`include "lifecycle/aou_dft_scan_test.svh"
