// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3 unit-test top: no DUT. Two L3 models talk through aou_l3_unit_if, and
// AOU_FDI_CHECKER watches both streams at 64 bytes per beat.
`timescale 1ns/1ps
module aou_l3_unit_top;
  import uvm_pkg::*;
  import aou_l3_unit_pkg::*;

  logic clk;
  initial begin
    clk = 1'b0;
    forever #1 clk = ~clk;
  end

  logic        xchk_trigger;
  logic [15:0] xchk_cnt;
  logic        xchk_capture_valid;
  logic        xchk_capture_code;
  logic        xchk_capture_die;
  logic [1:0]  xchk_capture_chk_st;
  logic [1:0]  xchk_capture_obs_st;
  logic [31:0] xchk_capture_flit_seq;
  logic [1:0]  xchk_compared;

  aou_l3_unit_if     uif (clk);
  aou_fdi_checker_if cif (clk);

  initial begin
    uif.rst_n = 1'b0;
    cif.rst_n = 1'b0;
    repeat (4) @(posedge clk);
    uif.rst_n = 1'b1;
    cif.rst_n = 1'b1;
  end

  AOU_FDI_CHECKER #(
    .FDI_IF_BYTES (64),
    .RP_COUNT     (4),
    .FDID         (0)
  ) u_chk (
    .I_CLK                   (clk),
    .I_RESETN                (uif.rst_n),
    .I_LINK_RESET            (1'b0),
    .I_LP_VALID              (uif.lp_valid),
    .I_LP_IRDY               (uif.lp_valid),
    .I_LP_DATA               (uif.lp_data),
    .I_PL_TRDY               (1'b1),
    .I_PL_VALID              (uif.pl_valid),
    .I_PL_DATA               (uif.pl_data),
    .I_PL_FLIT_CANCEL        (1'b0),
    .I_CFG_RP_DEST_RP        (uif.dest_rp),
    .I_LP_ACT_ST_DISABLED    (1'b0),
    .I_LP_ACT_ST_ENABLED     (1'b0),
    .I_PL_ACT_ST_DISABLED    (1'b0),
    .I_PL_ACT_ST_ENABLED     (1'b0),
    .O_VIOLATION             (cif.violation),
    .O_VIOLATION_TRIGGER     (cif.trigger),
    .O_VIOLATION_CNT         (cif.viol_cnt),
    .O_CAPTURE_VALID         (cif.capture_valid),
    .O_CAPTURE_CODE          (cif.capture_code),
    .O_CAPTURE_DIR           (cif.capture_dir),
    .O_CAPTURE_FLIT_SEQ      (cif.capture_flit_seq),
    .O_CAPTURE_GRANULE_IDX   (cif.capture_granule_idx),
    .O_CAPTURE_GRANULE       (cif.capture_granule),
    .O_CHECK_ENABLED         (cif.check_enabled),
    .O_LP_FLIT_SEQ           (cif.lp_flit_seq),
    .O_PL_FLIT_SEQ           (cif.pl_flit_seq),
    .O_XCHK_VIOLATION        (cif.xchk_violation),
    .O_XCHK_TRIGGER          (xchk_trigger),
    .O_XCHK_CNT              (xchk_cnt),
    .O_XCHK_CAPTURE_VALID    (xchk_capture_valid),
    .O_XCHK_CAPTURE_CODE     (xchk_capture_code),
    .O_XCHK_CAPTURE_DIE      (xchk_capture_die),
    .O_XCHK_CAPTURE_CHK_ST   (xchk_capture_chk_st),
    .O_XCHK_CAPTURE_OBS_ST   (xchk_capture_obs_st),
    .O_XCHK_CAPTURE_FLIT_SEQ (xchk_capture_flit_seq),
    .O_XCHK_COMPARED         (xchk_compared),
    .I_ERR_CLEAR             (cif.err_clear)
  );

  aou_fdi_chk_dir_tap u_chk_dir (
    .clk           (clk),
    .rst_n         (uif.rst_n),
    .clr           (cif.err_clear),
    .go            (u_chk.w_chk_go),
    .granule_viol  (u_chk.w_granule_viol),
    .flit_seq      (u_chk.r_flit_seq),
    .dir_violation (cif.dir_violation),
    .dir_flit_seq  (cif.dir_flit_seq)
  );

  initial begin
    uvm_config_db#(virtual aou_l3_unit_if)::set(null, "*", "l3_unit", uif);
    uvm_config_db#(virtual aou_fdi_checker_if)::set(null, "*", "fdi_chk", cif);
    run_test();
  end
endmodule
