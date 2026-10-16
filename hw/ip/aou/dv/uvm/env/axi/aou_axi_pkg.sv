// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L4: the VIP-neutral AXI transaction, the AXI4 manager and subordinate agents,
// the pin monitor, the sparse memory and the remote-die AXI model (L4a).
package aou_axi_pkg;
  import uvm_pkg::*;
  import aou_fc_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  `include "aou_fc_macros.svh"

  typedef enum bit {AOU_AXI_WR, AOU_AXI_RD} aou_axi_dir_e;

  localparam bit [1:0] AOU_AXI_FIXED = 2'b00;
  localparam bit [1:0] AOU_AXI_INCR  = 2'b01;
  localparam bit [1:0] AOU_AXI_WRAP  = 2'b10;

  localparam bit [1:0] AOU_AXI_OKAY   = 2'b00;
  localparam bit [1:0] AOU_AXI_EXOKAY = 2'b01;
  localparam bit [1:0] AOU_AXI_SLVERR = 2'b10;
  localparam bit [1:0] AOU_AXI_DECERR = 2'b11;

  localparam int unsigned AOU_AXI_MAX_DATA_BYTES = 128;

  // Write strobe patterns for generated writes. MIXED picks full, random or
  // all-zero strobes per beat.
  typedef enum {AOU_AXI_STRB_FULL, AOU_AXI_STRB_RANDOM, AOU_AXI_STRB_MIXED} aou_axi_strb_e;

  typedef enum {
    AOU_AXI_DLY_ZERO,    // always 0 cycles
    AOU_AXI_DLY_FIXED,   // always fixed_cycles
    AOU_AXI_DLY_RANGE,   // uniform in [min_cycles, max_cycles]
    AOU_AXI_DLY_BURSTY   // RANGE, with a stall_pct chance of [stall_min, stall_max]
  } aou_axi_dly_mode_e;

  typedef enum {
    AOU_AXI_TIMING_ZERO,      // no delays anywhere; zero-cycle B and R
    AOU_AXI_TIMING_RANDOM,    // short random delays on every channel
    AOU_AXI_TIMING_STALL,     // mostly fast, with occasional long stalls
    AOU_AXI_TIMING_SLOW_SUB,  // slow ready and long response latency
    AOU_AXI_TIMING_SLOW_MGR   // slow valid and slow B/R ready
  } aou_axi_timing_e;

  typedef virtual aou_axi_bus_if #(.DATA_W(1024)) aou_axi_vif_t;

  `include "aou_axi_txn.svh"
  `include "aou_axi_delay.svh"
  `include "aou_axi_timing.svh"
  `include "aou_mem.svh"
  `include "aou_axi_cfg.svh"
  `include "aou_axi_mgr_item.svh"
  `include "aou_axi_mon_item.svh"
  `include "aou_axi_sequencer.svh"
  `include "aou_axi_mgr_driver.svh"
  `include "aou_axi_sub_driver.svh"
  `include "aou_axi_fc_bins.svh"
  `include "aou_axi_monitor.svh"
  `include "aou_axi_mgr_agent.svh"
  `include "aou_axi_sub_agent.svh"
  `include "aou_remote_axi_model.svh"
  `include "aou_axi_base_seq.svh"
  `include "aou_axi_rand_seq.svh"
  `include "aou_axi_unaligned_wr_seq.svh"
  `include "aou_axi_b_zero_seq.svh"
endpackage
