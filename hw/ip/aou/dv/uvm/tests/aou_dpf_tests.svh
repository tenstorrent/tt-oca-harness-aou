// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data-path and feature tests (stream F): tests, included by aou_tests.sv (tb_top.sv) after aou_seq_lib_pkg.
`include "datapath/aou_msg_stats.svh"
`include "features/aou_agg_chk.svh"
`include "features/aou_dest_rp_chk.svh"
`include "datapath/aou_dp_base_test.svh"
`include "datapath/aou_dp_size_test.svh"
`include "datapath/aou_dp_burst_test.svh"
`include "datapath/aou_dp_wstrb_test.svh"
`include "datapath/aou_dp_unaligned_test.svh"
`include "datapath/aou_dp_b_zero_test.svh"
`include "datapath/aou_dp_outstanding_test.svh"
`include "datapath/aou_dp_packing_test.svh"
`include "datapath/aou_dp_random_test.svh"
`include "datapath/aou_attr_test.svh"
`include "datapath/aou_chan_test.svh"
`include "features/aou_split_test.svh"
`include "features/aou_aggregator_test.svh"
`include "features/aou_early_bresp_test.svh"
`include "features/aou_qos_test.svh"
`include "features/aou_dest_rp_test.svh"
`include "features/aou_lp_mode_test.svh"
