// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Samples the link-state signals every clock and checks the Protocol Layer
// (DUT) side of the FDI handshakes (UCIe r1.1 8.2.3-8.2.8), and the Protocol
// Layer outputs on each FDI that the negotiated protocol rules out (DLLPs,
// Retimer credits). A protocol layer,
// checker or scoreboard that follows the link state implements
// ucie_lsm_observer and registers with add_observer(); every clock, after the
// rule checks, each observer gets this clock's sample and the previous one.
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
  local bit          prev_vld;
  local bit          prev_dllp[2];
  local bit          prev_crd[2];
  local bit          prev_cc[2];

  // Rule evaluations for the ledger, by index; flushed in check_phase.
  typedef enum int {
    R14, R15, R16, R18, R19, R25, R26, R28, R29, R33, R46, R47, R61, R62, R63, R65, N_RULES
  } rule_e;
  local static const string RULE[N_RULES] = '{
      "FDI-R14", "FDI-R15", "FDI-R16", "FDI-R18", "FDI-R19", "FDI-R25", "FDI-R26", "FDI-R28",
      "FDI-R29", "FDI-R33", "FDI-R46", "FDI-R47", "FDI-R61", "FDI-R62", "FDI-R63", "FDI-R65"};
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
        check_status();
        for (int p = 0; p < cfg.n_phy && p < 2; p++) check_phy_outputs(p);
      end else begin
        prev_vld = 1'b0;
        prev_dllp = '{default: 1'b0};
        prev_crd = '{default: 1'b0};
        prev_cc = '{default: 1'b0};
      end
      foreach (observers[i]) observers[i].observe(cur, prev);
      prev = cur;
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
  endfunction

  local function void err(rule_e r, string msg);
    if (!cfg.checks_en) return;
    ucie_rule_log::fire(RULE[r], get_type_name());
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
    if (c.req == LSM_REQ_ACTIVE && p.req != LSM_REQ_ACTIVE && c.sts == LSM_RESET) chk(R33);
    // UCIe r1.1 8.2.3.1: a request that leaves Reset or PM (Active, LinkReset,
    // Disabled; Table 8-3) needs the wake handshake, so lp_wake_req is already
    // high when the request changes. Echoing L1/L2 or NOP leaves nothing.
    // The r3.0 wake handshake rules extend this to every state where clock gating is
    // permitted, which adds LinkReset and Disabled (8.2.3).
    if (c.req != p.req && c.req inside {LSM_REQ_ACTIVE, LSM_REQ_LINKRESET, LSM_REQ_DISABLED} &&
        p.sts inside {LSM_RESET, LSM_L1, LSM_L2, LSM_LINKRESET, LSM_DISABLED}) begin
      chk(R16);
      if (!c.wake_req)
        err(R16, $sformatf("lp_state_req %s -> %s in %s with lp_wake_req low", p.req.name(),
                           c.req.name(), p.sts.name()));
    end
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
    if (c.req == LSM_REQ_ACTIVE && p.req != LSM_REQ_ACTIVE && c.sts == LSM_RESET &&
        p.req != LSM_REQ_NOP)
      err(R33, $sformatf("Active request in Reset not preceded by NOP (was %s)", p.req.name()));
    if (c.clk_ack && !p.clk_ack && !p.clk_req)
      err(R18, "lp_clk_ack rose without pl_clk_req in the previous cycle");
    clk_ack_late = (c.clk_ack && !c.clk_req) ? clk_ack_late + 1 : 0;
    if (clk_ack_late == cfg.ref_slack + 1)
      err(R19, "lp_clk_ack stays high after pl_clk_req fell");
    if (c.rx_active_sts && !p.rx_active_sts && !p.rx_active_req)
      err(R26, "lp_rx_active_sts rose without pl_rx_active_req in the previous cycle");
    rx_sts_late = (c.rx_active_sts && !c.rx_active_req) ? rx_sts_late + 1 : 0;
    if (rx_sts_late == cfg.ref_slack + 1)
      err(R28, "lp_rx_active_sts stays high after pl_rx_active_req fell");
    // Adapter-side rules, kept here as a self-check of the L2 driver.
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
      foreach (n_chk[r]) ucie_rule_log::check(RULE[r], get_type_name(), n_chk[r]);
    n_chk = '{default: 0};
  endfunction
endclass
