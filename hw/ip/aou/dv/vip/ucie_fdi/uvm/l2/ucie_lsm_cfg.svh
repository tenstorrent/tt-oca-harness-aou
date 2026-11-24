// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class ucie_lsm_cfg extends uvm_object;
  `uvm_object_utils(ucie_lsm_cfg)

  // FDIs (PHYs) under this link state, 1 or 2. UCIe defines one FDI per
  // Protocol Layer to Adapter connection, each with its own link state (r3.0
  // §10.2, §10.2.8: "the same sequence happens independently for each
  // Protocol Layer stack"): for several stacks, build one link-state agent per
  // FDI, each with n_phy 1. n_phy 2 is a mirrored mode beyond UCIe, for a
  // Protocol Layer that follows one of two FDIs through one set of handshakes
  // (one lp_state_req, wake, clock and rx_active handshake): both FDIs report
  // the same pl_state_sts, the Protocol Layer follows active_phy's, and the
  // monitor samples that one.
  int unsigned  n_phy = 1;
  int unsigned  active_phy = 0;
  // Mirrored mode: the FDI the Protocol Layer does not follow stays in Reset
  // with its mainband closed and no stalls, instead of mirroring the followed
  // FDI's state, so the Protocol Layer must take state and stalls from the
  // followed one (+ucie_park_idle_phy).
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
  // Cycles to wait for a Protocol Layer request or acknowledge (a liveness bound: among
  // them the NOP->Active in Reset, FDI-R33); 0 waits forever.
  int unsigned  req_timeout = 20000;
  // Answer the Protocol Layer's requests (UCIe r3.0 Table 10-4): lp_state_req
  // LinkReset and Disabled wherever the table says "Yes", lp_linkerror in
  // every state (with react_linkerror_en too), the Active request that ends
  // LinkReset, Disabled or LinkError (with down_exit_on PL or EITHER), its PM
  // exit, and with restart_on PL or EITHER the NOP->Active that restarts a
  // link left in Reset. A request answered while an Adapter event runs
  // abandons the event. 0: the Adapter only runs its own events.
  bit           react_en = 1'b1;
  bit           react_linkerror_en = 1'b1;
  // What ends LinkReset, Disabled and LinkError (-> Reset). LSM_EXIT_INTERNAL:
  // the Adapter's internal request after the dwell (software clearing the
  // error, a reset pin; r3.0 §10.3.3.5 rule 1, §10.3.3.6, §10.3.3.7);
  // LSM_EXIT_PL: only the Protocol Layer's lp_state_req Active (Table 10-4:
  // Active is considered in those states), taken from the second clock of the
  // state on, out of LinkError only with lp_linkerror 0 and after
  // linkerror_min_res clocks there; a Protocol Layer that never asks keeps the
  // link down (legal, so no bound). LSM_EXIT_EITHER: whichever comes first.
  // +ucie_down_exit=internal|pl|either.
  ucie_lsm_exit_e down_exit_on = LSM_EXIT_INTERNAL;
  // Minimum residency in LinkError before a request-driven exit (r3.0
  // §10.3.3.7: "a minimum residency time in LinkError of 16 ms"). A scaled
  // stand-in for simulation: 16 ms would be millions of clocks.
  int unsigned  linkerror_min_res = 200;
  // The remote die's answer to a LinkReset or Disabled request the Adapter
  // passes on over the sideband (r3.0 §10.3.3.8 Implementation Note): 0
  // answers at once (after the Adapter's own latency), N an extra delay drawn
  // in [0:N] clocks for the sideband response. No delay when the link is
  // already down and not training (Reset without pl_inband_pres, LinkReset),
  // which the same note lets the Adapter complete locally.
  int unsigned  remote_rsp_max = 0;
  // Chance a LinkReset or Disabled request answered in Retrain, or in Reset
  // once pl_inband_pres is 1, first goes through Active (r3.0 §10.3.3.4 rule
  // 2, §10.3.3.1 rules 2 and 3: "permitted to transition through Active
  // State"); 0 goes straight to the requested state (§10.3.3.8).
  int unsigned  linkdown_via_active_pct = 0;
  // What restarts the training after LinkError/LinkReset/Disabled -> Reset
  // (UCIe r3.0 §10.3.3.8: the Protocol Layer's NOP->Active on lp_state_req,
  // which the Adapter must pass on "even if pl_inband_pres = 0", or the
  // Adapter's own decision to bring the link up). LSM_RESTART_SW: the
  // Adapter's own decision (software restarting the training, say),
  // sw_restart_delay cycles after the entry to Reset;
  // LSM_RESTART_PL: the Protocol Layer's NOP->Active in that Reset (a
  // Protocol Layer that never gives it is reported after req_timeout cycles);
  // LSM_RESTART_EITHER: whichever comes first. With PL or EITHER the Adapter
  // also answers the trigger between events, so a link a test left down
  // (rebringup_after_down 0) comes up on it. +ucie_restart_on=sw|pl|either.
  ucie_lsm_restart_e restart_on = LSM_RESTART_SW;
  // Cycles the Adapter stays in Reset after a link-down before it restarts
  // the training on its own (LSM_RESTART_SW, EITHER); 0 trains at once. The
  // agent keeps the value set here; +ucie_sw_restart_delay=N overrides it.
  // A bench that wants many delays draws one per run itself.
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
  // §10.3.3.7 needs neither a stall nor a boundary). +ucie_le_mid_flit_pct.
  int unsigned  le_mid_flit_pct = 0;
  // Cycles the Adapter forwards RX flits in Reset before Active. UCIe r3.0
  // §10.2.7 rule 3: with pl_rx_active_req and lp_rx_active_sts both 1 the
  // Receiver is in Active state if pl_state_sts is Reset, Retrain or Active,
  // as when the remote die went Active first and its Rsp.Active is still on
  // the sideband. On every Active entry from Reset, after the rx_active
  // handshake, the RX mainband opens for rx_early cycles before pl_state_sts
  // moves to Active; TX still waits for Active. 0 (off) keeps RX flits to
  // Active. +ucie_rx_early=N.
  int unsigned  rx_early = 0;

  // What the Adapter reports as negotiated and how the link runs (UCIe r3.0
  // Table 10-3). The format is always Format 6
  // (pl_protocol_flitfmt 0110b); pl_protocol_vld rises with pl_inband_pres and
  // falls on the next entry to LinkError or Reset. FDI has no rate of its own:
  // pl_speedmode and pl_max_speedmode only report the PHY's rate as an
  // encoding. The defaults: Streaming, the pl_speedmode encoding for 32 GT/s,
  // a x16 module.
  bit [3:0]     protocol = UCIE_PROTO_STREAMING;  // pl_protocol
  bit [2:0]     speedmode = 3'b101;    // pl_speedmode: 101b, the encoding for 32 GT/s
  bit           max_speedmode = 1'b0;  // pl_max_speedmode: 0, a PHY rate of at most 32 GT/s
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
  // their request fell (r3.0 §10.2.3.2 rule 3, §10.2.7 rule 4).
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
  // pl_clk_req must be high by this many cycles after the move (a liveness
  // bound); 0 asks for it by the cycle after the move, as 1 does.
  int unsigned  clk_req_window = 16;
  // Clocks from a pl_inband_pres drop in Reset (do_inband_drop,
  // LSM_EV_INBAND_DROP) to the pl_clk_req that covers it. 0 (default):
  // pl_clk_req rises in the clock of the drop. N: the drop comes first and the
  // drop's pl_clk_req rises N clocks later. That is exact when lp_clk_ack is
  // low at the drop; if a previous handshake's lp_clk_ack is still high, the
  // request waits for it to fall first, as at 0, and the check of a level
  // move (FDI-R20) excuses that wait. If pl_clk_req is already up for the
  // running job, the pin does not move. UCIe r3.0 §10.2.3.2 rule 5 lets a
  // level signal transition without waiting for lp_clk_ack and asks only
  // that the transition be observed through the handshake; its explicit
  // "before OR after pl_clk_req asserts" names assertion only, so the drop
  // first is permitted by inference, not by an explicit sentence. Figure
  // 10-13 shows the request first, and rule 5 strongly recommends that a
  // bringup keep pl_clk_req up until the status leaves Reset or presence drops
  // (clk_req_hold_bringup 1), which makes the order moot: a less common but
  // legal Adapter. At most clk_req_window (1 when that is 0), which FDI-R20
  // accepts; the driver refuses more with an error and uses that bound.
  // +ucie_inband_drop_clk_lag=N.
  int unsigned  inband_drop_clk_lag = 0;
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
                      "remote_active_first_pct=%0d down_exit_on=%s linkerror_min_res=%0d ",
                      "remote_rsp_max=%0d linkdown_via_active_pct=%0d inband_drop_clk_lag=%0d ",
                      "protocol=%04b speedmode=%03b max_speedmode=%0b lnk_cfg=%03b recenter=%0b"},
                     n_phy, active_phy, lat_min, lat_max, auto_bringup,
                     clk_req_hold_bringup, restart_on.name(), sw_restart_delay,
                     remote_active_first_pct, down_exit_on.name(), linkerror_min_res,
                     remote_rsp_max, linkdown_via_active_pct, inband_drop_clk_lag, protocol,
                     speedmode, max_speedmode, lnk_cfg, recenter_en);
  endfunction
endclass
