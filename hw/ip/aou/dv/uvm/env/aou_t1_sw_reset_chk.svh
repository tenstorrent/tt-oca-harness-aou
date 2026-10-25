// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Checks around the software reset (AOU_CON0.AOU_SW_RESET). The core reset is
// internal to the DUT, so the top reads it into aou_rst_if.core_rst_n. The reset
// itself loses every AXI transaction in flight or queued in AOU_CORE (MAS 7.3.6);
// the bench's AXI agents reset with the core, so nothing here judges the AXI
// handshakes the reset cuts.
//
// RX FIFO contents across the software reset (T1-L29). The RX FIFOs
// (AOU_FIFO_RP) share the core reset, so the core leaves AOU_SW_RESET with
// every one of them empty (MAS 7.3.6, integration guide 3.1.1): a message kept
// across the reset would belong to a transaction the reset lost, hold
// AOU_RX_FIFO_PENDING and block the next ActivateReq, or be presented on an AXI
// port as part of the wrong transaction (a W beat lands under the subordinate's
// next AW, since the W channel is in order). Checked at the release of the
// software reset for every channel of every RP, and on the M ports for the W
// case: no W handshake after the release may be a beat pending at it.
//
// DFT scan mode (T1-DFT01, integration guide 3.13.1): TIEL_DFT_MODESCAN=1
// neutralises the software reset path, so with I_RESETN high the core reset
// stays de-asserted. One report per scan window.
class aou_t1_sw_reset_chk extends uvm_component;
  `uvm_component_utils(aou_t1_sw_reset_chk)

  virtual aou_rst_if rst_vif;
  aou_axi_vif_t      m_vif[];   // the DUT's M ports, per RP
  int unsigned       stale_reports;
  int unsigned       releases;   // software reset releases seen

  // RPs whose RX W FIFO was not empty at the last software reset release and
  // whose M port has not handshaken a W beat since (watch_release sets,
  // watch_m_port clears).
  protected bit [7:0] stale_owed;

  // The current scan window: cycles, cycles with the core reset asserted, start.
  protected int unsigned scan_cyc;
  protected int unsigned scan_bad;
  protected time         scan_t0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    if (rst_vif == null) return;
    fork
      watch_release();
      watch_dft_scan();
    join_none
    foreach (m_vif[r]) begin
      automatic int unsigned rr = r;
      fork
        watch_m_port(rr);
      join_none
    end
  endtask

  // The first W handshake on m_axi<r> after a software reset release that left
  // RP r's RX W FIFO non-empty is the beat the reset should have dropped.
  protected task watch_m_port(int unsigned r);
    forever begin
      @(m_vif[r].mon_cb);
      if (m_vif[r].mon_cb.resetn !== 1'b1 || !stale_owed[r]) continue;
      if (m_vif[r].mon_cb.wvalid === 1'b1 && m_vif[r].mon_cb.wready === 1'b1) begin
        stale_owed[r] = 1'b0;
        stale_reports++;
        `uvm_error(get_type_name(),
                   $sformatf({"T1-L29: stale RX W beat delivered on m_axi%0d at %0t (WLAST %0b): ",
                              "a beat of a write AOU_SW_RESET lost, kept in the RX W FIFO across ",
                              "the reset; the subordinate pairs it with its next AW"},
                             r, $realtime, m_vif[r].mon_cb.wlast))
      end
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

  // At the first core clock with the core out of AOU_SW_RESET (I_RESETN high,
  // core_rst_n back to 1) no RX FIFO presents an entry: the FIFOs were in reset
  // until that edge, and nothing new can have been pushed yet.
  protected task watch_release();
    bit core_in_rst;
    forever begin
      @(rst_vif.mon_cb);
      if (rst_vif.mon_cb.rst_n !== 1'b1) begin
        core_in_rst = 1'b0;
        stale_owed = '0;
        continue;
      end
      if (rst_vif.mon_cb.core_rst_n === 1'b0) begin
        core_in_rst = 1'b1;
        continue;
      end
      if (!core_in_rst) continue;
      core_in_rst = 1'b0;
      releases++;
      stale_owed = rst_vif.mon_cb.rx_w_pend;
      if (rst_vif.mon_cb.rx_pend != '0) begin
        stale_reports++;
        `uvm_error(get_type_name(),
                   $sformatf({"T1-L29: RX FIFO entry pending (RP mask %0h, W mask %0h) at the ",
                              "AOU_SW_RESET release at %0t: the RX FIFOs are on the core reset ",
                              "and leave it empty"},
                             rst_vif.mon_cb.rx_pend, rst_vif.mon_cb.rx_w_pend, $realtime))
      end
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    close_scan();
  endfunction

  function void report_phase(uvm_phase phase);
    if (rst_vif == null) return;
    `uvm_info(get_type_name(), $sformatf("%0d AOU_SW_RESET release(s), %0d stale RX FIFO report(s)",
                                         releases, stale_reports), UVM_LOW)
  endfunction
endclass
