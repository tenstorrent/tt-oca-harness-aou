// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// APB3 requester agent: driver, monitor, register adapter and prediction wiring.
`timescale 1ns/1ps

package aou_apb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit {
    AOU_APB_READ,
    AOU_APB_WRITE
  } aou_apb_dir_e;

  `include "aou_apb_item.svh"
  `include "aou_apb_cfg.svh"

  typedef uvm_sequencer #(aou_apb_item) aou_apb_sequencer;

  `include "aou_apb_driver.svh"
  `include "aou_apb_monitor.svh"
  `include "aou_apb_reg_adapter.svh"
  `include "aou_apb_agent.svh"
  `include "aou_apb_rw_seq.svh"
endpackage
