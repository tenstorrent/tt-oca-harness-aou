// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class ucie_lsm_cfg extends uvm_object;
  `uvm_object_utils(ucie_lsm_cfg)

  // FDIs (PHYs) of the link, 1 or 2. Every FDI reports the same pl_state_sts;
  // the Protocol Layer follows active_phy's, and the monitor samples that one.
  int unsigned  n_phy = 1;
  int unsigned  active_phy = 0;
  // Two FDIs: the one the Protocol Layer does not follow stays in Reset with
  // its mainband closed and no stalls, instead of mirroring the followed
  // FDI's state, so the Protocol Layer must take state and stalls from the
  // followed one (+park_idle_phy).
  bit           park_idle_phy = 1'b0;
  bit           is_active = 1'b1;

  // Adapter response latencies in cycles (each draw uniform in [min:max]).
  // UCIe needs at least one cycle between a request and its acknowledge.
  int unsigned  lat_min = 1;
  int unsigned  lat_max = 6;
  int unsigned  dwell_min = 8;           // time spent in Retrain, L1, LinkError, ...
  int unsigned  dwell_max = 40;

  bit           auto_bringup = 1'b1;     // bring the link up after every reset
  bit           clk_req_hold_bringup = 1'b1; // keep pl_clk_req until the state leaves Reset
  bit           rebringup_after_down = 1'b1; // LinkError/LinkReset events end with a bringup
  int unsigned  req_timeout = 20000;     // cycles to wait for a DUT request; 0 waits forever
  bit           react_en = 1'b1;         // answer the DUT's lp_linkerror
  bit           react_linkerror_en = 1'b1; // between events (both must be set)
  // After LinkError/LinkReset/Disabled -> Reset the link is restarted by
  // software on the UCIe controller, never by the DUT: the Adapter stays in
  // Reset this many cycles (software's Start UCIe Link Training) before it
  // trains again; 0 trains at once. The agent randomises it in [50:1500]
  // unless +sw_restart_delay=N sets it.
  int unsigned  sw_restart_delay = 300;
  // Chance an Adapter-initiated LinkError is entered mid-flit: without the flit
  // boundary, while a flit is in flight in either direction (UCIe r1.1
  // 8.3.3.7 needs neither a stall nor a boundary). +le_mid_flit_pct.
  int unsigned  le_mid_flit_pct = 0;
  // Cycles the Adapter forwards RX flits in Reset before Active. UCIe r1.1
  // 8.2.7: once pl_rx_active_req and lp_rx_active_sts are both 1 the
  // Receiver is Active "even though pl_state_sts might not have moved to
  // Active yet" (rule 3: Reset, Retrain or Active), as when the remote die
  // went Active first and its Rsp.Active is still on the sideband. On every
  // Active entry from Reset, after the rx_active handshake, the RX mainband
  // opens for rx_early cycles before pl_state_sts moves to Active; TX still
  // waits for Active. 0 (off) keeps RX flits to Active. +fdi_rx_early=N.
  int unsigned  rx_early = 0;

  // What the Adapter reports as negotiated and how the link runs (UCIe r3.0
  // Table 10-3). The format is always Format 6
  // (pl_protocol_flitfmt 0110b); pl_protocol_vld rises with pl_inband_pres and
  // falls on the next entry to LinkError or Reset. The defaults: Streaming, 32
  // GT/s, a x16 module.
  bit [3:0]     protocol = UCIE_PROTO_STREAMING;  // pl_protocol
  bit [2:0]     speedmode = 3'b101;    // pl_speedmode: 32 GT/s
  bit           max_speedmode = 1'b0;  // pl_max_speedmode (r3.0): at most 32 GT/s
  bit [2:0]     lnk_cfg = 3'b010;      // pl_lnk_cfg: x16
  // pl_phyinrecenter: 0 holds it low (no training reported). 1 raises it while
  // the link trains, from the bringup's pl_clk_req handshake to Active, and in
  // Retrain (r3.0 Table 10-3: training, or the Adapter not yet Active).
  bit           recenter_en = 1'b0;

  // Monitor
  bit           checks_en = 1'b1;
  bit           cov_en = 1'b1;          // for observers that collect link-state coverage
  int unsigned  ref_slack = 3;           // cycles a Protocol Layer output may lag its cause

  function new(string name = "ucie_lsm_cfg");
    super.new(name);
  endfunction

  function int unsigned lat();
    return $urandom_range(lat_max, lat_min < 1 ? 1 : lat_min);
  endfunction

  function int unsigned dwell();
    return $urandom_range(dwell_max, dwell_min);
  endfunction

  function string convert2string();
    return $sformatf({"n_phy=%0d active_phy=%0d lat=[%0d:%0d] auto_bringup=%0b ",
                      "clk_hold=%0b sw_restart_delay=%0d protocol=%04b speedmode=%03b ",
                      "max_speedmode=%0b lnk_cfg=%03b recenter=%0b"},
                     n_phy, active_phy, lat_min, lat_max, auto_bringup,
                     clk_req_hold_bringup, sw_restart_delay, protocol, speedmode, max_speedmode,
                     lnk_cfg, recenter_en);
  endfunction
endclass
