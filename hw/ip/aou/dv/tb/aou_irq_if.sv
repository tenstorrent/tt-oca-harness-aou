// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The DUT's interrupt outputs and activation status, sampled on the core
// clock for the T1 interrupt watcher.
interface aou_irq_if (input logic clk);
  logic rst_n;
  logic int_req_linkreset;
  logic int_si0_id_mismatch;
  logic int_mi0_id_mismatch;
  logic int_early_resp_err;
  logic int_activate_start;
  logic int_deactivate_start;
  logic act_st_disabled;
  logic act_st_enabled;
  // White-box: AOU_CORE's per-type subordinate ID-mismatch aggregates, which
  // AOU_CORE_TOP ORs into INT_SI0_ID_MISMATCH (main #76).
  logic slv_rid_agg;
  logic slv_bid_agg;
  // White-box: each RP's early-response O_PENDING_CNT_OVER, which AOU_CORE_RP
  // leaves unconnected although the MAS calls it an interrupt (BUGS/005).
  logic [3:0] pend_over;

  clocking mon_cb @(posedge clk);
    input rst_n, int_req_linkreset, int_si0_id_mismatch, int_mi0_id_mismatch,
          int_early_resp_err, int_activate_start, int_deactivate_start, act_st_disabled,
          act_st_enabled, slv_rid_agg, slv_bid_agg, pend_over;
  endclocking
endinterface
