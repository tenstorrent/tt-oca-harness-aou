// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Samples the link-state signals every clock, checks the Protocol Layer
// (DUT) side of the FDI handshakes, steps the bringup model and publishes a
// sample on `ap` whenever a signal changes.
class aou_lsm_monitor extends uvm_monitor;
  `uvm_component_utils(aou_lsm_monitor)

  virtual aou_fdi_lsm_if lsm_vif;
  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];
  aou_lsm_cfg       cfg;
  aou_lsm_cov       cov;
  aou_bringup_model model;

  uvm_analysis_port #(aou_lsm_obs) ap;

  aou_lsm_obs cur;   // latest sample

  local aou_lsm_obs prev;
  local int unsigned clk_ack_late;
  local int unsigned rx_sts_late;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg.cov_en) cov = aou_lsm_cov::type_id::create("cov");
    if (cfg.model_en) begin
      model = aou_bringup_model::type_id::create("model");
      model.cfg = cfg;
      model.cov = cov;
    end
  endfunction

  task run_phase(uvm_phase phase);
    prev = aou_lsm_obs::type_id::create("prev");
    forever begin
      @(lsm_vif.mon_cb);
      cur = capture();
      if (cur.rst_n && prev.rst_n) check_rules(cur, prev);
      if (model != null) model.step(cur);
      if (cur.rst_n && (cur.sts != prev.sts || cur.req != prev.req) && cov != null)
        cov.sample_link(prev.sts, cur.sts, cur.req, cfg.fdi_enc);
      if (changed(cur, prev)) ap.write(cur);
      prev = cur;
    end
  endtask

  local function aou_lsm_obs capture();
    aou_lsm_obs o = aou_lsm_obs::type_id::create("obs");
    o.rst_n          = lsm_vif.mon_cb.rst_n === 1'b1;
    if (cfg.n_phy > 1 && lsm_vif.mon_cb.phy_type === 1'b1)
      o.pl_state_sts = mb_vif[1].mon_cb.pl_state_sts;
    else
      o.pl_state_sts = mb_vif[0].mon_cb.pl_state_sts;
    o.sts            = sts_decode(o.pl_state_sts, cfg.fdi_enc);
    o.inband_pres    = lsm_vif.mon_cb.pl_inband_pres === 1'b1;
    o.clk_req        = lsm_vif.mon_cb.pl_clk_req === 1'b1;
    o.wake_ack       = lsm_vif.mon_cb.pl_wake_ack === 1'b1;
    o.rx_active_req  = lsm_vif.mon_cb.pl_rx_active_req === 1'b1;
    o.lp_state_req   = lsm_vif.mon_cb.lp_state_req;
    o.req            = req_decode(o.lp_state_req, cfg.fdi_enc);
    o.wake_req       = lsm_vif.mon_cb.lp_wake_req === 1'b1;
    o.clk_ack        = lsm_vif.mon_cb.lp_clk_ack === 1'b1;
    o.rx_active_sts  = lsm_vif.mon_cb.lp_rx_active_sts === 1'b1;
    o.linkerror      = lsm_vif.mon_cb.lp_linkerror === 1'b1;
    o.sw_activate    = lsm_vif.mon_cb.sw_activate_start === 1'b1;
    o.sw_deactivate  = lsm_vif.mon_cb.sw_deactivate_start === 1'b1;
    o.sw_retrain     = lsm_vif.mon_cb.sw_retrain_req === 1'b1;
    o.sw_linkerror   = lsm_vif.mon_cb.sw_linkerror_inject === 1'b1;
    o.fsm_state      = lsm_vif.mon_cb.fdi_fsm_state;
    o.link_up        = lsm_vif.mon_cb.fdi_link_up === 1'b1;
    o.int_activate   = lsm_vif.mon_cb.int_activate_start === 1'b1;
    o.int_deactivate = lsm_vif.mon_cb.int_deactivate_start === 1'b1;
    o.req_linkreset  = lsm_vif.mon_cb.int_req_linkreset === 1'b1;
    o.act_st_disabled = lsm_vif.mon_cb.act_st_disabled === 1'b1;
    return o;
  endfunction

  local function bit changed(aou_lsm_obs a, aou_lsm_obs b);
    return a.rst_n != b.rst_n || a.pl_state_sts != b.pl_state_sts ||
           a.inband_pres != b.inband_pres || a.clk_req != b.clk_req ||
           a.wake_ack != b.wake_ack || a.rx_active_req != b.rx_active_req ||
           a.lp_state_req != b.lp_state_req || a.wake_req != b.wake_req ||
           a.clk_ack != b.clk_ack || a.rx_active_sts != b.rx_active_sts ||
           a.linkerror != b.linkerror ||
           a.fsm_state != b.fsm_state || a.link_up != b.link_up;
  endfunction

  local int unsigned n_chk[string];

  local function void err(string rule, string msg);
    if (!cfg.checks_en) return;
    aou_rule_log::fire(rule, get_type_name());
    `uvm_error(get_type_name(), $sformatf("%s: %s", rule, msg))
  endfunction

  local function void chk(string rule);
    if (!cfg.checks_en) return;
    n_chk[rule] = n_chk.exists(rule) ? n_chk[rule] + 1 : 1;
  endfunction

  local function void check_rules(aou_lsm_obs c, aou_lsm_obs p);
    if (c.lp_state_req != p.lp_state_req) begin
      chk("FDI-R46");
      chk("FDI-R56");
      if (cfg.fdi_enc == AOU_FDI_ENC_SPEC) chk("FDI-R47");
    end
    if (c.req == LSM_REQ_ACTIVE && p.req != LSM_REQ_ACTIVE && c.sts == LSM_RESET) chk("FDI-R33");
    // UCIe r1.1 8.2.3.1: a request that leaves Reset or PM (Active, LinkReset,
    // Disabled; Table 8-3) needs the wake handshake, so lp_wake_req is already
    // high when the request changes. Echoing L1/L2 or NOP leaves nothing.
    // The r3.0 wake handshake rules extend this to every state where clock gating is
    // permitted, which adds LinkReset and Disabled (8.2.3).
    if (c.req != p.req && c.req inside {LSM_REQ_ACTIVE, LSM_REQ_LINKRESET, LSM_REQ_DISABLED} &&
        p.sts inside {LSM_RESET, LSM_L1, LSM_L2, LSM_LINKRESET, LSM_DISABLED}) begin
      chk("FDI-R16");
      if (!c.wake_req)
        err("FDI-R16", $sformatf("lp_state_req %s -> %s in %s with lp_wake_req low", p.req.name(),
                                 c.req.name(), p.sts.name()));
    end
    if (c.clk_ack != p.clk_ack) begin
      chk("FDI-R18");
      chk("FDI-R19");
    end
    if (c.rx_active_sts != p.rx_active_sts) begin
      chk("FDI-R26");
      chk("FDI-R28");
    end
    if (c.wake_ack != p.wake_ack) begin
      chk("FDI-R14");
      chk("FDI-R15");
    end
    if (c.rx_active_req && !p.rx_active_req) chk("FDI-R25");
    if (p.sts == LSM_ACTIVE && c.sts != LSM_ACTIVE) chk("FDI-R29");
    if (c.req == LSM_REQ_RESERVED && c.lp_state_req != p.lp_state_req)
      err("FDI-R46", $sformatf("lp_state_req 0x%0h is reserved in the %s encoding",
                               c.lp_state_req, cfg.fdi_enc.name()));
    if (c.req == LSM_REQ_L2 && p.req != LSM_REQ_L2)
      err("FDI-R56", $sformatf("lp_state_req 0x%0h requests L2, which the DUT does not implement",
                               c.lp_state_req));
    if (cfg.fdi_enc == AOU_FDI_ENC_SPEC && c.req == LSM_REQ_RETRAIN && p.req != LSM_REQ_RETRAIN)
      err("FDI-R47", "Retrain request outside Raw Format");
    if (c.req == LSM_REQ_ACTIVE && p.req != LSM_REQ_ACTIVE && c.sts == LSM_RESET &&
        p.req != LSM_REQ_NOP)
      err("FDI-R33", $sformatf("Active request in Reset not preceded by NOP (was %s)",
                               p.req.name()));
    if (c.clk_ack && !p.clk_ack && !p.clk_req)
      err("FDI-R18", "lp_clk_ack rose without pl_clk_req in the previous cycle");
    clk_ack_late = (c.clk_ack && !c.clk_req) ? clk_ack_late + 1 : 0;
    if (clk_ack_late == cfg.ref_slack + 1)
      err("FDI-R19", "lp_clk_ack stays high after pl_clk_req fell");
    if (c.rx_active_sts && !p.rx_active_sts && !p.rx_active_req)
      err("FDI-R26", "lp_rx_active_sts rose without pl_rx_active_req in the previous cycle");
    rx_sts_late = (c.rx_active_sts && !c.rx_active_req) ? rx_sts_late + 1 : 0;
    if (rx_sts_late == cfg.ref_slack + 1)
      err("FDI-R28", "lp_rx_active_sts stays high after pl_rx_active_req fell");
    // Adapter-side rules, kept here as a self-check of the L2 driver.
    if (c.wake_ack && !p.wake_ack && !p.wake_req)
      err("FDI-R14", "pl_wake_ack rose without lp_wake_req in the previous cycle");
    if (!c.wake_ack && p.wake_ack && p.wake_req)
      err("FDI-R15", "pl_wake_ack fell while lp_wake_req was high");
    if (c.rx_active_req && !p.rx_active_req &&
        !(p.rx_active_sts == 1'b0 && p.sts inside {LSM_RESET, LSM_RETRAIN, LSM_ACTIVE}))
      err("FDI-R25", $sformatf("pl_rx_active_req rose in %s with lp_rx_active_sts=%0b",
                               p.sts.name(), p.rx_active_sts));
    if (p.sts == LSM_ACTIVE && !(c.sts inside {LSM_ACTIVE, LSM_LINKERROR}) &&
        (p.rx_active_req || p.rx_active_sts))
      err("FDI-R29", $sformatf("left Active for %s with rx_active req/sts still high",
                               c.sts.name()));
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (n_chk[r]) aou_rule_log::check(r, get_type_name(), n_chk[r]);
    n_chk.delete();
    if (model != null) begin
      model.final_check();
      foreach (model.n_cmp[r]) aou_rule_log::check(r, "aou_bringup_model", model.n_cmp[r]);
      foreach (model.n_bad[r]) for (int unsigned i = 0; i < model.n_bad[r]; i++)
        aou_rule_log::fire(r, "aou_bringup_model");
      model.n_cmp.delete();
      model.n_bad.delete();
    end
  endfunction

  function void report_phase(uvm_phase phase);
    if (model != null)
      `uvm_info(get_type_name(), $sformatf("bringup model: final state %s, %0d mismatches",
                                           model.st.name(), model.n_mismatch), UVM_LOW)
  endfunction
endclass
