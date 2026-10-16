// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
// Derived from PR #80 intf/aou_apb_if.sv (VNCHIPLabs, Apache-2.0): ports, signals
// and clocking blocks; the protocol checks are new.

// APB3 requester-side interface (AMBA APB protocol, issue B: PREADY and PSLVERR,
// no PPROT/PSTRB). The agent drives through drv_cb and observes through mon_cb.
//
// The protocol assertions follow the interface checks of amiq_apb
// (https://github.com/amiq-consulting/amiq_apb, (C) 2014 AMIQ Consulting,
// Apache-2.0), rewritten for APB3 and limited to |->, |=> and sampled-value
// functions. The PREADY time-out check lives in the monitor.

`timescale 1ns/1ps

interface aou_apb_if #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
) (
    input logic pclk,
    input logic presetn
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  logic              psel;
  logic              penable;
  logic [ADDR_W-1:0] paddr;
  logic              pwrite;
  logic [DATA_W-1:0] pwdata;
  logic [DATA_W-1:0] prdata;
  logic              pready;
  logic              pslverr;

  // Tests that inject protocol errors on purpose clear this.
  bit checks_en = 1'b1;

  clocking drv_cb @(posedge pclk);
    output psel, penable, paddr, pwrite, pwdata;
    input prdata, pready, pslverr, presetn;
  endclocking

  clocking mon_cb @(posedge pclk);
    input psel, penable, paddr, pwrite, pwdata, prdata, pready, pslverr, presetn;
  endclocking

  // -------------------------------------------------------------------------
  // Protocol checks. Rule IDs are listed in checkers/rules.csv.
  // -------------------------------------------------------------------------
  wire access = psel && penable;
  wire done   = psel && penable && pready;

  // APB-R01: the requester holds the bus idle during reset.
  apb_r01_idle_in_reset: assert property (
    @(posedge pclk) disable iff (!checks_en)
      !presetn |-> psel !== 1'b1 && penable !== 1'b1)
  else `uvm_error("aou_apb_if", "APB-R01: PSEL/PENABLE asserted during reset")

  // APB-R02: PSEL and PENABLE are never X/Z out of reset.
  apb_r02_ctrl_known: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      !$isunknown({psel, penable}))
  else `uvm_error("aou_apb_if", "APB-R02: PSEL or PENABLE is X/Z")

  // APB-R03: address and direction are known while selected.
  apb_r03_addr_known: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      psel |-> !$isunknown({paddr, pwrite}))
  else `uvm_error("aou_apb_if", "APB-R03: PADDR or PWRITE is X/Z while PSEL is high")

  // APB-R04: write data is known while a write is selected.
  apb_r04_wdata_known: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      psel && pwrite |-> !$isunknown(pwdata))
  else `uvm_error("aou_apb_if", "APB-R04: PWDATA is X/Z during a write")

  // APB-R05: PENABLE is only asserted together with PSEL.
  apb_r05_enable_needs_sel: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      penable |-> psel)
  else `uvm_error("aou_apb_if", "APB-R05: PENABLE high without PSEL")

  // APB-R06: a SETUP cycle is always followed by an ACCESS cycle.
  apb_r06_setup_to_access: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      psel && !penable |=> psel && penable)
  else `uvm_error("aou_apb_if", "APB-R06: SETUP cycle not followed by ACCESS")

  // APB-R07: an ACCESS cycle with PREADY low is extended.
  apb_r07_wait_holds_access: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      access && !pready |=> psel && penable)
  else `uvm_error("aou_apb_if", "APB-R07: ACCESS dropped while PREADY was low")

  // APB-R08: PENABLE drops after the transfer completes (IDLE or a new SETUP).
  apb_r08_enable_drops: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      done |=> !penable)
  else `uvm_error("aou_apb_if", "APB-R08: PENABLE still high after the completing cycle")

  // APB-R09: PADDR is stable from SETUP until the transfer completes.
  apb_r09_addr_stable: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      psel && !done |=> $stable(paddr))
  else `uvm_error("aou_apb_if", "APB-R09: PADDR changed during a transfer")

  // APB-R10: PWRITE is stable from SETUP until the transfer completes.
  apb_r10_write_stable: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      psel && !done |=> $stable(pwrite))
  else `uvm_error("aou_apb_if", "APB-R10: PWRITE changed during a transfer")

  // APB-R11: PWDATA is stable from SETUP until a write completes.
  apb_r11_wdata_stable: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      psel && pwrite && !done |=> $stable(pwdata))
  else `uvm_error("aou_apb_if", "APB-R11: PWDATA changed during a write")

  // APB-R12: PREADY and PSLVERR are known in every ACCESS cycle.
  apb_r12_resp_known: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      access |-> !$isunknown({pready, pslverr}))
  else `uvm_error("aou_apb_if", "APB-R12: PREADY or PSLVERR is X/Z during ACCESS")

  // APB-R13: read data is known when a successful read completes.
  apb_r13_rdata_known: assert property (
    @(posedge pclk) disable iff (!presetn || !checks_en)
      done && !pwrite && !pslverr |-> !$isunknown(prdata))
  else `uvm_error("aou_apb_if", "APB-R13: PRDATA is X/Z when a read completes")

endinterface
