// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AOU_FDI_CHECKER's reporting ports, for aou_fdi_chk_adapter. The instance
// that drives them connects O_* to these signals and I_ERR_CLEAR to
// err_clear.
interface aou_fdi_checker_if (input logic clk);
  import aou_fdi_checker_pkg::*;

  logic                       rst_n;
  logic [VIOL_CLASS_CNT-1:0]  violation;
  logic                       trigger;
  logic [15:0]                viol_cnt;
  logic                       capture_valid;
  logic [VIOL_CODE_WD-1:0]    capture_code;
  logic                       capture_dir;
  logic [31:0]                capture_flit_seq;
  logic [5:0]                 capture_granule_idx;
  logic [39:0]                capture_granule;
  logic [VIOL_CLASS_CNT-1:0]  check_enabled;
  logic [31:0]                lp_flit_seq;
  logic [31:0]                pl_flit_seq;
  logic [XVIOL_CLASS_CNT-1:0] xchk_violation;
  logic                       err_clear;
  // Per direction (0 LP, 1 PL), driven by the top from the checker's findings:
  // the classes seen since the last clear and the flit of the first one.
  logic [1:0][VIOL_CLASS_CNT-1:0] dir_violation;
  logic [1:0][31:0]               dir_flit_seq;

  clocking mon_cb @(posedge clk);
    input rst_n, violation, trigger, viol_cnt, capture_valid, capture_code, capture_dir,
          capture_flit_seq, capture_granule_idx, capture_granule, check_enabled,
          lp_flit_seq, pl_flit_seq, xchk_violation, dir_violation, dir_flit_seq;
  endclocking

  clocking drv_cb @(posedge clk);
    output err_clear;
  endclocking
endinterface
