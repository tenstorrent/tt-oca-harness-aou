// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Samples the link-state signals every clock and checks the Protocol Layer
// side of the FDI handshakes (UCIe r3.0 §10.2.3-10.2.8), and the Protocol
// Layer outputs on each FDI that the negotiated protocol rules out (DLLPs,
// Retimer credits). Where r3.0 orders two events but gives no time between
// them (a request and a wake handshake that follows it, a request falling and
// its acknowledge following), the bound is a liveness knob of ucie_lsm_cfg. A
// protocol layer, checker or scoreboard that follows the link state implements
// ucie_lsm_observer and registers with add_observer(); every clock, after the
// rule checks, each observer gets this clock's sample and the previous one.
// Everything is decided from the interfaces, so the monitor works the same in
// passive mode, where its Adapter-side rules check a real Adapter.
class ucie_lsm_monitor extends uvm_monitor;
  `uvm_component_utils(ucie_lsm_monitor)

  virtual ucie_fdi_lsm_if lsm_vif;
  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];
  ucie_lsm_cfg       cfg;

  ucie_lsm_obs_t     cur;   // latest sample
  ucie_lsm_obs_t     prev;  // the one before

  local ucie_lsm_observer observers[$];
  local int unsigned clk_ack_late;
  local int unsigned rx_sts_late;
  local int unsigned wake_wait;  // cycles a request has waited for lp_wake_req; 0: none
  local ucie_lsm_state_e wake_from;  // ... and the clock-gated state it leaves
  local bit          prev_vld;
  local bit          prev_dllp[2];
  local bit          prev_crd[2];
  local bit          prev_cc[2];
  local bit [2:0]    phy_lvl;      // pl_phyinl1, pl_phyinl2, pl_phyinrecenter this clock
  local bit [2:0]    prev_phy_lvl; // ... and the previous one
  local int unsigned lvl_wait;     // FDI-R20: cycles a level move waits for pl_clk_req; 0: none
  local ucie_lsm_state_e lvl_in;   // ... and the state it moved in
  local bit          le_ack_wait;  // FDI-R21: a LinkError entered before its pl_clk_req was acked
  local ucie_lsm_state_e le_from;  // ... and the state it left

  // Rule evaluations for the ledger, by index; flushed in check_phase.
  typedef enum int {
    R14, R15, R16, R18, R19, R20, R21, R22, R25, R26, R28, R29, R46, R47, R49, R61, R62, R63,
    R65, N_RULES
  } rule_e;
  local static const string RULE[N_RULES] = '{
      "FDI-R14", "FDI-R15", "FDI-R16", "FDI-R18", "FDI-R19", "FDI-R20",
      "FDI-R21", "FDI-R22", "FDI-R25", "FDI-R26", "FDI-R28",
      "FDI-R29", "FDI-R46", "FDI-R47", "FDI-R49", "FDI-R61", "FDI-R62", "FDI-R63",
      "FDI-R65"};
  local int unsigned n_chk[N_RULES];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void add_observer(ucie_lsm_observer o);
    observers.push_back(o);
  endfunction

  task run_phase(uvm_phase phase);
    prev = obs_reset();
    forever begin
      @(lsm_vif.mon_cb);
      capture();
      if (cur.rst_n && prev.rst_n) begin
        check_rules();
        check_clk_req(cur, prev);
        check_status();
        for (int p = 0; p < cfg.n_phy && p < 2; p++) check_phy_outputs(p);
      end else begin
        wake_wait = 0;
        lvl_wait = 0;
        le_ack_wait = 1'b0;
        prev_vld = 1'b0;
        prev_dllp = '{default: 1'b0};
        prev_crd = '{default: 1'b0};
        prev_cc = '{default: 1'b0};
      end
      foreach (observers[i]) observers[i].observe(cur, prev);
      prev = cur;
      prev_phy_lvl = phy_lvl;
    end
  endtask

  local function void capture();
    cur.rst_n          = lsm_vif.mon_cb.rst_n === 1'b1;
    if (cfg.n_phy > 1 && cfg.active_phy == 1)
      cur.pl_state_sts = mb_vif[1].mon_cb.pl_state_sts;
    else
      cur.pl_state_sts = mb_vif[0].mon_cb.pl_state_sts;
    cur.sts            = sts_decode(cur.pl_state_sts);
    cur.inband_pres    = lsm_vif.mon_cb.pl_inband_pres === 1'b1;
    cur.clk_req        = lsm_vif.mon_cb.pl_clk_req === 1'b1;
    cur.wake_ack       = lsm_vif.mon_cb.pl_wake_ack === 1'b1;
    cur.rx_active_req  = lsm_vif.mon_cb.pl_rx_active_req === 1'b1;
    cur.lp_state_req   = lsm_vif.mon_cb.lp_state_req;
    cur.req            = req_decode(cur.lp_state_req);
    cur.wake_req       = lsm_vif.mon_cb.lp_wake_req === 1'b1;
    cur.clk_ack        = lsm_vif.mon_cb.lp_clk_ack === 1'b1;
    cur.rx_active_sts  = lsm_vif.mon_cb.lp_rx_active_sts === 1'b1;
    cur.linkerror      = lsm_vif.mon_cb.lp_linkerror === 1'b1;
    phy_lvl = {lsm_vif.mon_cb.pl_phyinl1 === 1'b1, lsm_vif.mon_cb.pl_phyinl2 === 1'b1,
               lsm_vif.mon_cb.pl_phyinrecenter === 1'b1};
  endfunction

  local function void err(rule_e r, string msg);
    if (!cfg.checks_en) return;
    ucie_rule_log::fire(RULE[r], this);
    `uvm_error(get_type_name(), $sformatf("%s: %s", RULE[r], msg))
  endfunction

  local function void chk(rule_e r);
    n_chk[r]++;
  endfunction

  local function void check_rules();
    ucie_lsm_obs_t c = cur;
    ucie_lsm_obs_t p = prev;
    if (c.lp_state_req != p.lp_state_req) begin
      chk(R46);
      chk(R47);
    end
    check_wake(c, p);
    if (c.clk_ack != p.clk_ack) begin
      chk(R18);
      chk(R19);
    end
    if (c.rx_active_sts != p.rx_active_sts) begin
      chk(R26);
      chk(R28);
    end
    if (c.wake_ack != p.wake_ack) begin
      chk(R14);
      chk(R15);
    end
    if (c.rx_active_req && !p.rx_active_req) chk(R25);
    if (p.sts == LSM_ACTIVE && c.sts != LSM_ACTIVE) chk(R29);
    if (c.req == LSM_REQ_RESERVED && c.lp_state_req != p.lp_state_req)
      err(R46, $sformatf("lp_state_req 0x%0h is reserved", c.lp_state_req));
    if (c.req == LSM_REQ_RETRAIN && p.req != LSM_REQ_RETRAIN)
      err(R47, "Retrain request outside Raw Format");
    // An Active request in Reset that does not follow a NOP (held into Reset,
    // or straight from another request) is no violation: UCIe r3.0 §10.3.3.1
    // rule 1 only makes it no request, which the driver does not take
    // (FDI-R33 there); ucie_lsm_fcov covers it.
    if (c.clk_ack && !p.clk_ack && !p.clk_req)
      err(R18, "lp_clk_ack rose without pl_clk_req in the previous cycle");
    // r3.0 §10.2.3.2 rule 3 and §10.2.7 rule 4 order the falls, with no time:
    // hs_fall_timeout is a liveness bound (0: off).
    clk_ack_late = (c.clk_ack && !c.clk_req) ? clk_ack_late + 1 : 0;
    if (cfg.hs_fall_timeout != 0 && clk_ack_late == cfg.hs_fall_timeout + 1)
      err(R19, $sformatf("lp_clk_ack still high %0d cycles after pl_clk_req fell",
                         cfg.hs_fall_timeout));
    if (c.rx_active_sts && !p.rx_active_sts && !p.rx_active_req)
      err(R26, "lp_rx_active_sts rose without pl_rx_active_req in the previous cycle");
    rx_sts_late = (c.rx_active_sts && !c.rx_active_req) ? rx_sts_late + 1 : 0;
    if (cfg.hs_fall_timeout != 0 && rx_sts_late == cfg.hs_fall_timeout + 1)
      err(R28, $sformatf("lp_rx_active_sts still high %0d cycles after pl_rx_active_req fell",
                         cfg.hs_fall_timeout));
    // Adapter-side rules: a self-check of the L2 driver, and in passive mode a
    // check of the Adapter the monitor watches.
    if (c.wake_ack && !p.wake_ack && !p.wake_req)
      err(R14, "pl_wake_ack rose without lp_wake_req in the previous cycle");
    if (!c.wake_ack && p.wake_ack && p.wake_req)
      err(R15, "pl_wake_ack fell while lp_wake_req was high");
    if (c.rx_active_req && !p.rx_active_req &&
        !(p.rx_active_sts == 1'b0 && p.sts inside {LSM_RESET, LSM_RETRAIN, LSM_ACTIVE}))
      err(R25, $sformatf("pl_rx_active_req rose in %s with lp_rx_active_sts=%0b", p.sts.name(),
                         p.rx_active_sts));
    if (p.sts == LSM_ACTIVE && !(c.sts inside {LSM_ACTIVE, LSM_LINKERROR}) &&
        (p.rx_active_req || p.rx_active_sts))
      err(R29, $sformatf("left Active for %s with rx_active req/sts still high", c.sts.name()));
    // r3.0 Table 10-3 lp_linkerror: the Adapter stays in LinkError "as long as
    // lp_linkerror=1" (and §10.3.3.7 leaves it on the Protocol Layer's request
    // only with lp_linkerror = 0). p.linkerror is what the Adapter saw when it
    // changed the status.
    if (p.sts == LSM_LINKERROR && c.sts != LSM_LINKERROR) begin
      chk(R49);
      if (p.linkerror)
        err(R49, $sformatf("left LinkError for %s while lp_linkerror was 1", c.sts.name()));
    end
  endfunction

  // FDI-R16, UCIe r3.0 §10.2.3.1: a request that moves away from a state where
  // clock gating is permitted (Reset, LinkReset, Disabled, PM; §10.2.3) uses the
  // wake handshake. That is a change of lp_state_req to Active, LinkReset or
  // Disabled, or lp_linkerror rising (echoing L1/L2 or NOP leaves nothing).
  // The handshake must be under way at the request: lp_wake_req high in that
  // cycle. Rule 5 lets the request change without waiting for pl_wake_ack, so
  // lp_wake_req may instead rise after it, within wake_req_window cycles (a
  // liveness bound; r3.0 has none) and before the status leaves the gated
  // state: a handshake that comes only after the transition was not used for
  // it. An lp_wake_req that fell before the request does not count, even with
  // pl_wake_ack still high: the Protocol Layer has withdrawn its wake request
  // (rule 3 has it fall first, ending the handshake), and the Adapter may gate
  // its clocks again from then on.
  local function void check_wake(ucie_lsm_obs_t c, ucie_lsm_obs_t p);
    bit gated = p.sts inside {LSM_RESET, LSM_L1, LSM_L2, LSM_LINKRESET, LSM_DISABLED};
    bit by_req = c.req != p.req && c.req inside {LSM_REQ_ACTIVE, LSM_REQ_LINKRESET,
                                                 LSM_REQ_DISABLED};
    bit by_le = c.linkerror && !p.linkerror;
    if (gated && (by_req || by_le)) begin
      chk(R16);
      if (c.wake_req || wake_wait != 0) return;
      wake_from = p.sts;
      if (cfg.wake_req_window == 0) wake_late();
      else wake_wait = 1;
      return;
    end
    if (wake_wait == 0) return;
    if (c.wake_req) wake_wait = 0;
    else if (c.sts != wake_from || ++wake_wait > cfg.wake_req_window) wake_late();
  endfunction

  local function void wake_late();
    err(R16, $sformatf({"a request leaving %s (lp_state_req or lp_linkerror) without lp_wake_req ",
                        "high in its cycle or rising within %0d cycles after it, before the ",
                        "status moved on"},
                       wake_from.name(), cfg.wake_req_window));
    wake_wait = 0;
  endfunction

  // Adapter-side, a self-check of the L2 driver: the pl_clk_req handshake
  // around what a Protocol Layer may miss while its clocks are gated (UCIe r3.0
  // §10.2.3: in Reset, LinkReset, Disabled and PM; lsm_gated).
  //  FDI-R22, §10.2.3.2 rule 7: a status change out of such a state to anything
  //    but LinkError has pl_clk_req high in the clock before it (raised before
  //    the change and held until it).
  //  FDI-R21, rule 6: a change from such a state to LinkError has pl_clk_req
  //    high before it too, or else lp_clk_ack answers pl_clk_req before the
  //    next status change ("Adapter must wait for lp_clk_ack before performing
  //    another state transition").
  //  FDI-R20, rule 5: a move of pl_inband_pres, pl_rx_active_req, pl_phyinl1,
  //    pl_phyinl2 or pl_phyinrecenter in such a state is seen with lp_clk_ack
  //    high (the Protocol Layer's clocks run), or a handshake follows: the
  //    signal may move first, but pl_clk_req must then rise within
  //    clk_req_window cycles (a liveness bound; r3.0 gives none) and stay high
  //    until lp_clk_ack. Waiting for lp_clk_ack itself is the Protocol Layer's
  //    part (FDI-R18 in the driver).
  local function void check_clk_req(ucie_lsm_obs_t c, ucie_lsm_obs_t p);
    bit moved = c.sts != p.sts;
    if (le_ack_wait && moved) begin
      err(R21, $sformatf({"%s -> LinkError without pl_clk_req before it, then -> %s with no ",
                          "lp_clk_ack answering pl_clk_req in between"}, le_from.name(),
                         c.sts.name()));
      le_ack_wait = 1'b0;
    end
    if (c.clk_req && c.clk_ack) le_ack_wait = 1'b0;
    if (moved && lsm_gated(p.sts)) begin
      if (c.sts == LSM_LINKERROR) begin
        chk(R21);
        if (!p.clk_req && !(c.clk_req && c.clk_ack)) begin
          le_ack_wait = 1'b1;
          le_from = p.sts;
        end
      end else begin
        chk(R22);
        if (!p.clk_req)
          err(R22, $sformatf("pl_state_sts %s -> %s without pl_clk_req asserted before the change",
                             p.sts.name(), c.sts.name()));
      end
    end
    if (lvl_wait != 0) begin
      if (c.clk_ack) begin
        lvl_wait = 0;
      end else if (!c.clk_req) begin
        if (p.clk_req) lvl_late("pl_clk_req fell before lp_clk_ack answered it");
        else if (++lvl_wait > cfg.clk_req_window)
          lvl_late($sformatf("no pl_clk_req within %0d cycles", cfg.clk_req_window));
      end
    end
    if (lsm_gated(p.sts) && {c.inband_pres, c.rx_active_req, phy_lvl} !=
                            {p.inband_pres, p.rx_active_req, prev_phy_lvl}) begin
      chk(R20);
      if (!c.clk_ack && lvl_wait == 0) begin
        lvl_wait = 1;
        lvl_in = p.sts;
      end
    end
  endfunction

  local function void lvl_late(string why);
    err(R20, {"a level signal (pl_inband_pres, pl_rx_active_req, pl_phyinl1/l2/recenter) moved ",
              "in ", lvl_in.name(), " without a pl_clk_req handshake: ", why});
    lvl_wait = 0;
  endfunction

  // Adapter-side: pl_protocol_vld is 1 whenever pl_inband_pres is 1 in Reset
  // (the Protocol Layer samples pl_protocol then), and falls only on entry to
  // LinkError or Reset (r3.0 Table 10-3 pl_protocol_vld).
  local function void check_status();
    bit vld = lsm_vif.mon_cb.pl_protocol_vld === 1'b1;
    if (cur.inband_pres && cur.sts == LSM_RESET) begin
      chk(R65);
      if (!vld) err(R65, "pl_inband_pres is 1 in Reset with pl_protocol_vld 0");
    end
    if (!vld && prev_vld) begin
      chk(R65);
      if (!(cur.sts != prev.sts && cur.sts inside {LSM_LINKERROR, LSM_RESET}))
        err(R65, $sformatf("pl_protocol_vld fell in %s, not on entry to LinkError or Reset",
                           cur.sts.name()));
    end
    prev_vld = vld;
  endfunction

  // Protocol Layer outputs the link rules out (UCIe r3.0 Table 10-3):
  // lp_corrupt_crc only when the protocol includes CXL.cachemem, no DLLPs when
  // it is Streaming (lp_dllp: not used for Streaming), and no Retimer credits
  // (the model has no Retimer; on FDI they exist for Raw Format only). One
  // report per assertion.
  local function void check_phy_outputs(int unsigned p);
    bit dllp = mb_vif[p].mon_cb.lp_dllp_valid !== 1'b0;
    bit crd = mb_vif[p].mon_cb.lp_retimer_crd !== 1'b0;
    bit cc = mb_vif[p].mon_cb.lp_corrupt_crc !== 1'b0;
    if (!protocol_has_cachemem(cfg.protocol)) begin
      chk(R61);
      if (cc && !prev_cc[p])
        err(R61, $sformatf("phy%0d lp_corrupt_crc=%0b with protocol %04b (no CXL.cachemem)", p,
                           mb_vif[p].mon_cb.lp_corrupt_crc, cfg.protocol));
    end
    prev_cc[p] = cc;
    if (protocol_is_streaming(cfg.protocol)) begin
      chk(R62);
      if (dllp && !prev_dllp[p])
        err(R62, $sformatf("phy%0d lp_dllp_valid=%0b with protocol %04b (Streaming)", p,
                           mb_vif[p].mon_cb.lp_dllp_valid, cfg.protocol));
    end
    chk(R63);
    if (crd && !prev_crd[p])
      err(R63, $sformatf("phy%0d lp_retimer_crd=%0b: no Retimer, and Format 6 is not Raw", p,
                         mb_vif[p].mon_cb.lp_retimer_crd));
    prev_dllp[p] = dllp;
    prev_crd[p] = crd;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (cfg.checks_en)
      foreach (n_chk[r]) ucie_rule_log::check(RULE[r], this, n_chk[r]);
    n_chk = '{default: 0};
  endfunction
endclass
