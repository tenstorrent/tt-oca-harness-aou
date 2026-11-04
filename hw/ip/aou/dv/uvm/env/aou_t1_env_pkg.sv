// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1 environment: one AOU_TOP against layered models (docs/AOU_TB_ARCH.adoc,
// "Topology" and "Test layer API"). The env, its configuration, the virtual
// sequencer and the base virtual sequence every T1 test composes.
`timescale 1ns/1ps
package aou_t1_env_pkg;
  import uvm_pkg::*;
  import ocah_lib_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  `include "aou_fc_macros.svh"
  import aou_axi_pkg::*;
  import aou_fc_pkg::*;
  import aou_env_pkg::*;
  import aou_fdi_pkg::*;
  import aou_lsm_pkg::*;
  import aou_l3_pkg::*;
  import aou_rule_pkg::*;
  import aou_apb_pkg::*;
  import aou_reg_pkg::*;
  import aou_core_csr_uvm_pkg::*;
  import aou_rule_pkg::*;
  import aou_fc_pkg::*;
  import aou_axi4pc_pkg::*;
  `include "aou_t1_xfer_fc_bins.svh"

`ifdef TWO_PHY
  localparam int AOU_T1_N_PHY = 2;
`else
  localparam int AOU_T1_N_PHY = 1;
`endif
`ifdef AOU_FDI_CONFIG
  localparam int AOU_T1_FDI_CONFIG = `AOU_FDI_CONFIG;
`else
  localparam int AOU_T1_FDI_CONFIG = 1;
`endif
`ifdef AOU_RP_COUNT
  localparam int AOU_T1_RP_COUNT = `AOU_RP_COUNT;
`else
  localparam int AOU_T1_RP_COUNT = 1;
`endif
`ifdef AOU_RP_DATA_W
  localparam int AOU_T1_RP_BYTES = `AOU_RP_DATA_W / 8;
`else
  localparam int AOU_T1_RP_BYTES = 64;
`endif
  // Per-RP AXI data bytes (Makefile CONFIG: AOU_RP<n>_DATA_W, default AOU_RP_DATA_W)
`ifdef AOU_RP0_DATA_W
  localparam int AOU_T1_RP0_BYTES = `AOU_RP0_DATA_W / 8;
`else
  localparam int AOU_T1_RP0_BYTES = AOU_T1_RP_BYTES;
`endif
`ifdef AOU_RP1_DATA_W
  localparam int AOU_T1_RP1_BYTES = `AOU_RP1_DATA_W / 8;
`else
  localparam int AOU_T1_RP1_BYTES = AOU_T1_RP_BYTES;
`endif
`ifdef AOU_RP2_DATA_W
  localparam int AOU_T1_RP2_BYTES = `AOU_RP2_DATA_W / 8;
`else
  localparam int AOU_T1_RP2_BYTES = AOU_T1_RP_BYTES;
`endif
`ifdef AOU_RP3_DATA_W
  localparam int AOU_T1_RP3_BYTES = `AOU_RP3_DATA_W / 8;
`else
  localparam int AOU_T1_RP3_BYTES = AOU_T1_RP_BYTES;
`endif

  // How the remote die sizes its WriteReqs (aou_t1_remote_mgr_driver).
  typedef enum int {AOU_RWREQ_AWSIZE, AOU_RWREQ_UPSIZE, AOU_RWREQ_DUT_LIKE} aou_t1_rwreq_e;

  // The widest AoU data message, 1024 bits (the DUT's AXI_PEER_DIE_MAX_DATA_WD, a
  // localparam): the remote die model is never wider than this.
  localparam int AOU_T1_PEER_MAX_BYTES = 128;

  function automatic int unsigned aou_t1_rp_bytes(int unsigned r);
    case (r)
      0: return AOU_T1_RP0_BYTES;
      1: return AOU_T1_RP1_BYTES;
      2: return AOU_T1_RP2_BYTES;
      default: return AOU_T1_RP3_BYTES;
    endcase
  endfunction
  // RX FIFO depth per RP and credit class (AW, AR, W, R, B, in aou_cred_class_e
  // order). AW, AR and B hold one message per entry; W and R are granule
  // stores, so their depth is in granules (one credit each). AOU_RX_FIFO_ALT
  // (CONFIG *-rxf) gives every RP and class its own non-default depth, which
  // the top passes to AOU_TOP with the request/response register slices off;
  // otherwise these are the integration guide's defaults (section 2: 44, and
  // 600 granules for W and R, 960 with a 256 B FDI), which the top leaves to
  // the RTL.
`ifdef AOU_RX_FIFO_ALT
  localparam int AOU_T1_RX_DEPTH[4][5] = '{'{24, 16, 300, 240, 20}, '{12, 30, 150, 120, 13},
                                          '{20, 20, 420, 360, 16}, '{16, 12, 210, 180, 14}};
  localparam int AOU_T1_RX_RS_EN = 0;
`else
  localparam int AOU_T1_RX_WR_DEPTH = (AOU_T1_FDI_CONFIG == 5) ? 960 : 600;
  localparam int AOU_T1_RX_DEPTH[4][5] =
      '{4{'{44, 44, AOU_T1_RX_WR_DEPTH, AOU_T1_RX_WR_DEPTH, 44}}};
  localparam int AOU_T1_RX_RS_EN = 1;
`endif
  // Outstanding limits the top builds AOU_TOP with (integration guide section 2;
  // the defaults unless a build defines AOU_M_MO_CNT or AOU_S_MO_CNT). M_RD_MO_CNT
  // and M_WR_MO_CNT size each RP's M-port pending-ID tables, S_WR_MO_CNT its
  // early-response table; the checkers take their limits from here.
`ifdef AOU_M_MO_CNT
  localparam int AOU_T1_M_MO_CNT = `AOU_M_MO_CNT;
`else
  localparam int AOU_T1_M_MO_CNT = 32;
`endif
`ifdef AOU_S_MO_CNT
  localparam int AOU_T1_S_MO_CNT = `AOU_S_MO_CNT;
`else
  localparam int AOU_T1_S_MO_CNT = 32;
`endif

  // FDI beat bytes per PHY for each FDI_CONFIG (integrator guide §3.10)
  localparam int AOU_T1_BEAT0 = (AOU_T1_FDI_CONFIG == 0 || AOU_T1_FDI_CONFIG == 3) ? 32 :
                                (AOU_T1_FDI_CONFIG == 2) ? 128 :
                                (AOU_T1_FDI_CONFIG == 5) ? 256 : 64;
  localparam int AOU_T1_BEAT1 = (AOU_T1_FDI_CONFIG == 4) ? 128 : 64;

  // The most credit the DUT may advertise for RP r and class c (MAS 3.9, all
  // PROFEXTLEN 0): request and response FIFO entries hold one message each
  // (WriteReq and ReadReq 3 granules, WriteResp 1); the W and R granule
  // stores give one credit per granule of depth.
  function automatic int unsigned aou_t1_rx_max_credit(int unsigned r, int unsigned c);
    int unsigned d = AOU_T1_RX_DEPTH[r][c];
    case (c)
      0, 1:    return d * 3;
      default: return d;
    endcase
  endfunction

  // Who starts activation or deactivation.
  typedef enum {
    AOU_T1_BY_APB,     // DUT: AOU_INIT.ACTIVATE_START / DEACTIVATE_START
    AOU_T1_BY_PIN,     // DUT: I_SW_ACTIVATE_START (deactivation: the register, as BY_APB)
    AOU_T1_BY_REMOTE,  // remote die: L3 ActivateReq / DeactivateReq
    AOU_T1_BY_BOTH,    // APB and L3, ordered by aou_t1_order_e
    AOU_T1_BY_RANDOM
  } aou_t1_who_e;

  typedef enum {
    AOU_T1_DUT_FIRST,
    AOU_T1_REMOTE_FIRST,
    AOU_T1_SIMULTANEOUS,
    AOU_T1_ORDER_RANDOM
  } aou_t1_order_e;

  typedef enum {
    AOU_T1_L2R,   // local managers at the S ports to the remote memory
    AOU_T1_R2L,   // remote managers through L3 to the M ports and local memory
    AOU_T1_BOTH_DIRS
  } aou_t1_dir_e;

  typedef enum {
    AOU_T1_SEQ_RAND,       // aou_axi_rand_seq
    AOU_T1_SEQ_UNALIGNED,  // aou_axi_unaligned_wr_seq (#56)
    AOU_T1_SEQ_B_ZERO      // aou_axi_b_zero_seq (#64), zero delays end to end
  } aou_t1_seq_kind_e;

  typedef enum {
    AOU_T1_RST_CORE,   // I_RESETN
    AOU_T1_RST_APB,    // I_PRESETN
    AOU_T1_RST_BOTH
  } aou_t1_rst_e;

  `uvm_analysis_imp_decl(_dbg_mport)
  `uvm_analysis_imp_decl(_dbg_remote)
  `uvm_analysis_imp_decl(_dbg_remote_req)

  `include "aou_t1_traffic_cfg.svh"
  `include "aou_t1_feature_cfg.svh"
  `include "aou_t1_env_cfg.svh"
  `include "aou_t1_expect_catcher.svh"
  `include "aou_t1_expect.svh"
  `include "aou_t1_reset_agent.svh"
  `include "aou_t1_env_fc_bins.svh"
  `include "aou_t1_status.svh"
  `include "aou_t1_flit_bridge.svh"
  `include "aou_t1_l1_pump_seq.svh"
  `include "aou_t1_l4a_adapter.svh"
  `include "aou_t1_remote_mgr_driver.svh"
  `include "aou_t1_remote_mgr.svh"
  `include "aou_t1_reg_env.svh"
  `include "aou_t1_field_seq.svh"
  `include "aou_t1_reads_seq.svh"
  `include "aou_t1_sw_isr.svh"
  `include "aou_t1_axi4pc_ctl.svh"
  `include "aou_t1_mo_fc_bins.svh"
  `include "aou_t1_mo_chk.svh"
  `include "aou_t1_sw_reset_chk.svh"
  `include "aou_t1_lp_cfg_chk.svh"
  `include "aou_t1_force_deact_chk.svh"
  `include "aou_t1_dbg_fifo_chk.svh"
  `include "aou_t1_crd_flow_chk.svh"
  `include "aou_t1_crd_rr_chk.svh"
  `include "aou_t1_crd_block_chk.svh"
  `include "aou_t1_wr_order_chk.svh"
  `include "aou_t1_early_tbl_chk.svh"
  `include "aou_t1_wdt_chk.svh"
  `include "aou_t1_xfer_cov.svh"
  `include "aou_t1_attr_chk.svh"
  `include "aou_t1_rx_fifo_chk.svh"
  `include "aou_t1_rx_align_chk.svh"
  `include "aou_t1_rx_granule_chk.svh"
  // Checkers and performance model classes the virtual sequences compose
  // (uvm/env/chk, uvm/env/perf); the tests that configure them live in uvm/tests.
  `include "chk/aou_early_bresp_chk.svh"
  `include "chk/aou_split_chk.svh"
  `include "chk/aou_flit_counter.svh"
  `include "chk/aou_qos_order_chk.svh"
  `include "chk/aou_mrp_chk.svh"
  `include "perf/aou_perf_result.svh"
  `include "perf/aou_perf_window.svh"
  `include "perf/aou_perf_windows.svh"
  `include "perf/aou_perf_targets.svh"
  `include "perf/aou_perf_mon.svh"
  `include "perf/aou_rx_lat_mon.svh"
  `include "perf/aou_perf_chk.svh"
  typedef class aou_t1_env;
  `include "aou_t1_vseqr.svh"
  `include "aou_t1_env.svh"
  `include "aou_base_test_seq.svh"
endpackage
