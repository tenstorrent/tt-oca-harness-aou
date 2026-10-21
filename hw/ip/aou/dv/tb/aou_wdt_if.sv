// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The write-transaction watchdog's observation points for aou_t1_wdt_chk
// (config_db key "wdt"), sampled on the core clock. tb_top assigns them:
//   aw_hs[r], b_hs[r]: RP r's early-response controller ports, the S-side AW
//     handshake (the S-port pins) and the M-side B handshake (the remote die's
//     actual B, which with early response on never reaches a pin); 0 for RPs
//     the build does not have.
//   en, thr, mask: the SFR's WDT_EN outputs, WDT_THRESHOLD and
//     INT_EARLY_WDT_MASK.
//   status[r]: WRITE_EARLY_RESPONSE_RPr.WDT_TRANS_TIMEOUT_ERR, the SFR's
//     internal register (white-box).
//   pin: INT_EARLY_WDT_ERR.
//   p*: the SFR's APB port on the core clock (behind the asynchronous bridge),
//     so a W1C or a read is seen in the cycle the SFR acts on it.
//   core_rst_n: the core reset (I_RESETN and AOU_SW_RESET); rst_n: I_RESETN.
interface aou_wdt_if (input logic clk);
  logic        core_rst_n;
  logic        rst_n;
  logic [3:0]  aw_hs;
  logic [3:0]  b_hs;
  logic [3:0]  en;
  logic [31:0] thr;
  logic        mask;
  logic [3:0]  status;
  logic        pin;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic        pready;
  logic [15:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;

  clocking mon_cb @(posedge clk);
    input core_rst_n, rst_n, aw_hs, b_hs, en, thr, mask, status, pin, psel, penable, pwrite,
          pready, paddr, pwdata, prdata;
  endclocking
endinterface
