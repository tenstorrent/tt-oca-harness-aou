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
  // 1: the bringup holds pl_clk_req from before pl_inband_pres until the state
  // has left Reset (UCIe r3.0 §10.2.3.2 rule 5's recommendation). 0: it
  // releases it as pl_inband_pres rises, so a Protocol Layer may gate its
  // clocks in Reset and must wake by itself to request Active; pl_clk_req is
  // raised again before pl_rx_active_req and the exit from Reset (rules 5 and
  // 7), so both settings are within r3.0.
  bit           clk_req_hold_bringup = 1'b1;
  bit           rebringup_after_down = 1'b1; // LinkError/LinkReset events end with a bringup
  // Cycles to wait for a DUT request or acknowledge (a liveness bound: among
  // them the NOP->Active in Reset, FDI-R33); 0 waits forever.
  int unsigned  req_timeout = 20000;
  // Answer the Protocol Layer between events: its lp_linkerror (with
  // react_linkerror_en too), its PM exit, and with restart_on PL or EITHER the
  // NOP->Active that restarts a link left in Reset.
  bit           react_en = 1'b1;
  bit           react_linkerror_en = 1'b1;
  // What restarts the training after LinkError/LinkReset/Disabled -> Reset
  // (UCIe r3.0 §10.3.3.8: the Protocol Layer's NOP->Active on lp_state_req,
  // which the Adapter must pass on "even if pl_inband_pres = 0", or the
  // Adapter's own decision to bring the link up). LSM_RESTART_SW: software on
  // the UCIe controller, sw_restart_delay cycles after the entry to Reset;
  // LSM_RESTART_PL: the Protocol Layer's NOP->Active in that Reset (a
  // Protocol Layer that never gives it is reported after req_timeout cycles);
  // LSM_RESTART_EITHER: whichever comes first. With PL or EITHER the Adapter
  // also answers the trigger between events, so a link a test left down
  // (rebringup_after_down 0) comes up on it. +ucie_restart_on=sw|pl|either.
  ucie_lsm_restart_e restart_on = LSM_RESTART_SW;
  // Cycles the Adapter stays in Reset after a link-down before software
  // restarts the training (LSM_RESTART_SW, EITHER); 0 trains at once. The
  // agent randomises it in [50:1500] unless +sw_restart_delay=N sets it.
  int unsigned  sw_restart_delay = 300;
  // Chance (percent) an Active entry from Reset or from a Retrain entered from
  // Active starts with the rx_active handshake before the Protocol Layer has
  // requested Active, as when the remote die's Active request arrives first
  // (UCIe r3.0 §10.2.7 rule 1: pl_rx_active_req may rise in Reset or Retrain;
  // §10.2.8 step 4: the Adapter answers the remote Req.Active once the
  // Protocol Layer's Receiver is ready). In Reset it comes after
  // pl_inband_pres, under pl_clk_req (§10.2.3.2 rule 5). 0 (default) waits for
  // the request. +ucie_remote_active_first_pct=N.
  int unsigned  remote_active_first_pct = 0;
  // Chance an Adapter-initiated LinkError is entered mid-flit: without the flit
  // boundary, while a flit is in flight in either direction (UCIe r3.0
  // §10.3.3.7 needs neither a stall nor a boundary). +le_mid_flit_pct.
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
  // The model's own covergroups (ucie_lsm_fcov); +ucie_fcov=0|1 overrides it.
  bit           fcov_en = 1'b1;
  // Liveness bounds of the Protocol Layer checks where UCIe r3.0 orders two
  // events but gives no time between them; 0 turns the check off.
  // FDI-R19, R28: cycles lp_clk_ack and lp_rx_active_sts may stay high after
  // their request fell (r3.0 10.2.3.2 rule 3, 10.2.7 rule 4).
  int unsigned  hs_fall_timeout = 1000;
  // FDI-R16: a request that leaves a clock-gated state needs lp_wake_req high
  // in its cycle, or rising at most this many cycles after it (r3.0 §10.2.3.1
  // rule 5 lets the request go first); 0 asks for it in the very cycle of the
  // request.
  int unsigned  wake_req_window = 16;
  // FDI-R20, a self-check of the Adapter: a level signal (pl_inband_pres,
  // pl_rx_active_req, pl_phyinl1, pl_phyinl2, pl_phyinrecenter) that moves
  // while the Protocol Layer may be clock gated needs a pl_clk_req handshake;
  // r3.0 §10.2.3.2 rule 5 lets the signal move first but gives no time, so
  // pl_clk_req must rise within this many cycles (a liveness bound).
  int unsigned  clk_req_window = 16;
  // A LinkError the Adapter must hold because lp_linkerror stays 1 (r3.0 Table
  // 10-3): report it once (an info) after this many cycles past the dwell (0:
  // never). The Adapter keeps waiting either way; holding is legal.
  int unsigned  linkerror_hold_report = 0;

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
                      "clk_hold=%0b restart_on=%s sw_restart_delay=%0d ",
                      "remote_active_first_pct=%0d ",
                      "protocol=%04b speedmode=%03b max_speedmode=%0b lnk_cfg=%03b recenter=%0b"},
                     n_phy, active_phy, lat_min, lat_max, auto_bringup,
                     clk_req_hold_bringup, restart_on.name(), sw_restart_delay,
                     remote_active_first_pct, protocol, speedmode, max_speedmode, lnk_cfg,
                     recenter_en);
  endfunction
endclass
