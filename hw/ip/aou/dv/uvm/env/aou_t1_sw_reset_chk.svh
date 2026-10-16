// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// S-port handshakes while the DUT core is held in software reset (T1-L28, BUGS/021).
// AOU_SW_RESET resets AOU_CORE but not the AXI ports, so the local managers keep
// driving them. An AW, W or AR beat the DUT accepts on a clock edge where its core
// is held in reset is gone the next cycle, while the manager has handed it over:
// later W beats pair with the wrong AW, or a write is acknowledged and lost.
// Interim expectation (BUGS/021): no S-port AW, W or AR handshake while the core's
// software reset is asserted. The core reset is internal to the DUT, so the top
// reads it into aou_rst_if.core_rst_n; I_RESETN (which also resets the ports) is
// not a software reset and is excluded.
// With the BUGS/021 fix's guard (AOU_DUT_SW_RESET_GUARD), the guard owns an RP's
// pins from the core reset to the end of its drain (aou_rst_if.port_iso) and itself
// accepts the W beats owed by AWs accepted earlier, answering them with SLVERR.
// In that window only an AR, a W with no earlier AW to pair with, or an AW whose W
// burst did not already arrive (AXI allows W before AW) is flagged.
//
// Stale RX W beat across the software reset (T1-L29, BUGS/007). The RX W FIFO
// that feeds the M port sits on I_RESETN, not the software reset, so a W beat
// still in it when the core comes out of AOU_SW_RESET belongs to a write the core
// no longer knows. It is never drained, and it holds AOU_RX_FIFO_PENDING, which
// blocks the next ActivateReq. Interim expectation: no RX W beat pending at the
// release of the software reset is still pending L29_CYCLES later.
//
// DFT scan mode (T1-DFT01, integration guide 3.13.1): TIEL_DFT_MODESCAN=1
// neutralises the software reset path, so with I_RESETN high the core reset
// stays de-asserted. One report per scan window.
class aou_t1_sw_reset_chk extends uvm_component;
  `uvm_component_utils(aou_t1_sw_reset_chk)

  aou_axi_vif_t      vif[];
  virtual aou_rst_if rst_vif;
  int unsigned       reports;
  int unsigned       stale_reports;

  localparam int unsigned L29_CYCLES = 1000;
`ifdef AOU_DUT_SW_RESET_GUARD
  localparam bit GUARD = 1'b1;
`else
  localparam bit GUARD = 1'b0;
`endif

  typedef struct {
    time         t;
    realtime     rt;
    int unsigned rp;
    string       what;
    bit          owed;
  } hs_t;

  // Clock edges in the reset window, as a mask of RPs: the core held in software
  // reset or, with the guard, the RP's ports isolated.
  protected bit [7:0] in_reset[time];
  // Per RP, AWs minus completed W bursts on the pins, and whether a W burst is open
  // (the guard's own bookkeeping of owed beats).
  protected int  wbal[];
  protected bit  wmid[];
  // Handshakes of edges the reset sampler may not have processed yet.
  protected hs_t pend[$];
  // The current scan window: cycles, cycles with the core reset asserted, start.
  protected int unsigned scan_cyc;
  protected int unsigned scan_bad;
  protected time         scan_t0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    if (rst_vif == null || vif.size() == 0) return;
    fork
      forever begin
        @(rst_vif.mon_cb);
        if (rst_vif.mon_cb.rst_n !== 1'b1) continue;
        if (GUARD && rst_vif.mon_cb.port_iso != 8'h00)
          in_reset[$time] = rst_vif.mon_cb.port_iso;
        else if (!GUARD && rst_vif.mon_cb.core_rst_n === 1'b0)
          in_reset[$time] = 8'hff;
      end
      watch_stale_rx_w();
      watch_dft_scan();
    join_none
    wbal = new[vif.size()];
    wmid = new[vif.size()];
    foreach (vif[r]) begin
      automatic int unsigned rr = r;
      fork
        watch(rr);
      join_none
    end
  endtask

  protected task watch_dft_scan();
    forever begin
      @(rst_vif.mon_cb);
      if (rst_vif.mon_cb.dft_modescan === 1'b1 && rst_vif.mon_cb.rst_n === 1'b1) begin
        if (scan_cyc == 0) scan_t0 = $time;
        scan_cyc++;
        // The mux is combinational; allow the first cycle for the switch.
        if (scan_cyc > 1 && rst_vif.mon_cb.core_rst_n !== 1'b1) scan_bad++;
      end else begin
        close_scan();
      end
    end
  endtask

  protected function void close_scan();
    if (scan_cyc == 0) return;
    if (scan_bad != 0) begin
      `uvm_error(get_type_name(), $sformatf({"T1-DFT01: the core reset was asserted for %0d of ",
                 "%0d cycles of the scan window from %0t (integration guide 3.13.1: ",
                 "TIEL_DFT_MODESCAN=1 de-asserts the software reset)"}, scan_bad, scan_cyc,
                 scan_t0))
    end
    scan_cyc = 0;
    scan_bad = 0;
  endfunction

  protected task watch_stale_rx_w();
    bit          core_in_rst;
    bit [7:0]    stale;
    int unsigned held;
    realtime     rel_t;
    forever begin
      @(rst_vif.mon_cb);
      if (rst_vif.mon_cb.rst_n !== 1'b1) begin
        core_in_rst = 1'b0;
        stale = '0;
        continue;
      end
      if (rst_vif.mon_cb.core_rst_n === 1'b0) begin
        core_in_rst = 1'b1;
        stale = '0;
        continue;
      end
      if (core_in_rst) begin
        core_in_rst = 1'b0;
        stale = rst_vif.mon_cb.rx_w_pend;
        held = 0;
        rel_t = $realtime;
        continue;
      end
      if (stale == '0) continue;
      stale &= rst_vif.mon_cb.rx_w_pend;
      if (stale != '0 && ++held == L29_CYCLES) begin
        stale_reports++;
        `uvm_error(get_type_name(),
                   $sformatf({"T1-L29: RX W beat pending (RP mask %0h) at the AOU_SW_RESET ",
                              "release at %0t still pending %0d cycles later; it holds ",
                              "AOU_RX_FIFO_PENDING (BUGS/007 interim)"},
                             stale, rel_t, L29_CYCLES))
        stale = '0;
      end
    end
  endtask

  // Clocking blocks of different interfaces on one clock update in no fixed
  // order, so an edge's handshakes are judged at a later edge.
  protected task watch(int unsigned r);
    bit aw_hs, w_hs, wlast;
    forever begin
      @(vif[r].mon_cb);
      judge($time);
      if (vif[r].mon_cb.resetn !== 1'b1) begin
        wbal[r] = 0;
        wmid[r] = 1'b0;
        continue;
      end
      aw_hs = vif[r].mon_cb.awvalid === 1'b1 && vif[r].mon_cb.awready === 1'b1;
      w_hs  = vif[r].mon_cb.wvalid === 1'b1 && vif[r].mon_cb.wready === 1'b1;
      wlast = vif[r].mon_cb.wlast === 1'b1;
      if (aw_hs)
        pend.push_back('{$time, $realtime, r,
                         $sformatf("AW (ID %0h, AWLEN %0d)", vif[r].mon_cb.awid,
                                   vif[r].mon_cb.awlen), GUARD && wbal[r] < 0});
      if (w_hs)
        pend.push_back('{$time, $realtime, r, $sformatf("W (WLAST %0b)", wlast),
                         GUARD && (wbal[r] > 0 || wmid[r])});
      if (vif[r].mon_cb.arvalid === 1'b1 && vif[r].mon_cb.arready === 1'b1)
        pend.push_back('{$time, $realtime, r,
                         $sformatf("AR (ID %0h, ARLEN %0d)", vif[r].mon_cb.arid,
                                   vif[r].mon_cb.arlen), 1'b0});
      if (aw_hs && !(w_hs && wlast)) wbal[r]++;
      else if (!aw_hs && w_hs && wlast) wbal[r]--;
      if (w_hs) wmid[r] = !wlast;
    end
  endtask

  protected function void judge(time cutoff);
    hs_t keep[$];
    foreach (pend[i]) begin
      if (pend[i].t >= cutoff) begin
        keep.push_back(pend[i]);
      end else if (!pend[i].owed && in_reset.exists(pend[i].t) &&
                   in_reset[pend[i].t][pend[i].rp]) begin
        reports++;
        `uvm_error(get_type_name(),
                   $sformatf({"T1-L28: s_axi%0d %s handshaken at %0t while the DUT core is ",
                              "held in AOU_SW_RESET (BUGS/021 interim)"},
                             pend[i].rp, pend[i].what, pend[i].rt))
      end
    end
    pend = keep;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    judge($time + 1);
    close_scan();
  endfunction
endclass
