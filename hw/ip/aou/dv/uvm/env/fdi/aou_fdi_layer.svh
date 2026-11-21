// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bench's layer on the UCIe FDI model: what about the FDI is the DUT's
// rather than UCIe's.
// - The DUT's bringup pins (aou_bringup_if): I_PHY_TYPE (the PHY the DUT
//   follows, lsm_cfg.active_phy) and the bringup software pins, back to idle
//   at time 0 and on every reset; pulse_sw() pulses a software pin.
// - The reference model of the DUT's bringup controller (aou_bringup_model),
//   stepped every clock with the model's link-state sample and the bringup
//   pins of the same clock, and the DUT-specific rule that the DUT never
//   requests L2.
// - The bench's FDI coverage: link state and bringup FSM (aou_lsm_cov) and
//   the mainband (aou_fdi_cov, one collector for every PHY).
// It follows the link state as an observer of the model's link-state monitor.
// The env creates it and, in connect_phase, calls attach() with the model's
// link-state agent.
class aou_fdi_layer extends uvm_component implements ucie_lsm_observer;
  `uvm_component_utils(aou_fdi_layer)

  virtual aou_bringup_if brg_vif;
  ucie_lsm_cfg           cfg;      // the link-state agent's (attach)
  bit                    model_en = 1'b1;
  aou_bringup_model      model;
  aou_lsm_cov            lsm_cov;
  aou_fdi_cov            fdi_cov;

  local int unsigned     n_r56;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual aou_bringup_if)::get(this, "", "aou_bringup", brg_vif))
      `uvm_fatal(get_type_name(), "no aou_bringup in config_db")
    if (model_en) model = aou_bringup_model::type_id::create("model");
  endfunction

  // Follow the link state of the model's link-state agent and collect the
  // mainband coverage of its PHYs (ucie_lsm_agent::phy).
  function void attach(ucie_lsm_agent lsm);
    cfg = lsm.cfg;
    lsm.mon.add_observer(this);
    if (cfg.cov_en) lsm_cov = aou_lsm_cov::type_id::create("lsm_cov");
    if (model != null) begin
      model.cfg = cfg;
      model.cov = lsm_cov;
    end
    foreach (lsm.phy[p]) begin
      if (!lsm.phy[p].cfg.cov_en) continue;
      if (fdi_cov == null) fdi_cov = aou_fdi_cov::type_id::create("fdi_cov");
      lsm.phy[p].mon.cov = fdi_cov;
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      drive_idle();
      @(negedge brg_vif.rst_n);
    end
  endtask

  local task drive_idle();
    brg_vif.drv_cb.phy_type <= cfg.active_phy == 1;
    set_sw(LSM_SW_ACTIVATE, 1'b0);
    set_sw(LSM_SW_LINKERROR, 1'b0);
  endtask

  local task set_sw(aou_lsm_sw_e which, bit v);
    case (which)
      LSM_SW_ACTIVATE: brg_vif.drv_cb.sw_activate_start <= v;
      default:         brg_vif.drv_cb.sw_linkerror_inject <= v;
    endcase
  endtask

  // Pulse one of the DUT's bringup software pins. Safe to call from a test
  // while a link event runs.
  task pulse_sw(aou_lsm_sw_e which, int unsigned cycles = 1);
    @(brg_vif.drv_cb);
    set_sw(which, 1'b1);
    repeat (cycles) @(brg_vif.drv_cb);
    set_sw(which, 1'b0);
  endtask

  // ucie_lsm_observer: every clock, after the model's own link-state rules.
  virtual function void observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev);
    if (cur.rst_n && prev.rst_n) begin
      // The DUT does not implement L2 (integration guide 6.6.6 GAP-3), so it
      // never requests it.
      if (cur.lp_state_req != prev.lp_state_req) n_r56++;
      if (cur.req == LSM_REQ_L2 && prev.req != LSM_REQ_L2 && cfg.checks_en) begin
        aou_rule_log::fire("FDI-R56", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
                   "FDI-R56: lp_state_req 0x%0h requests L2, which the DUT does not implement",
                   cur.lp_state_req))
      end
    end
    if (lsm_cov != null && cur.rst_n && (cur.sts != prev.sts || cur.req != prev.req))
      lsm_cov.sample_link(prev.sts, cur.sts, cur.req);
    if (model != null) model.step(cur, sample_brg());
  endfunction

  // The bringup pins of this clock.
  local function aou_brg_obs_t sample_brg();
    aou_brg_obs_t b;
    b.sw_activate     = brg_vif.mon_cb.sw_activate_start === 1'b1;
    b.sw_linkerror    = brg_vif.mon_cb.sw_linkerror_inject === 1'b1;
    b.fsm_state       = brg_vif.mon_cb.fdi_fsm_state;
    b.link_up         = brg_vif.mon_cb.fdi_link_up === 1'b1;
    b.int_activate    = brg_vif.mon_cb.int_activate_start === 1'b1;
    b.req_linkreset   = brg_vif.mon_cb.int_req_linkreset === 1'b1;
    b.act_st_disabled = brg_vif.mon_cb.act_st_disabled === 1'b1;
    b.sw_reset        = brg_vif.mon_cb.sw_reset === 1'b1;
    return b;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (cfg != null && cfg.checks_en) aou_rule_log::check("FDI-R56", get_type_name(), n_r56);
    n_r56 = 0;
    if (model != null) begin
      model.final_check();
      foreach (model.n_cmp[r])
        aou_rule_log::check(aou_bringup_model::RULE[r], "aou_bringup_model", model.n_cmp[r]);
      foreach (model.n_bad[r]) for (int unsigned i = 0; i < model.n_bad[r]; i++)
        aou_rule_log::fire(aou_bringup_model::RULE[r], "aou_bringup_model");
      model.n_cmp = '{default: 0};
      model.n_bad = '{default: 0};
    end
  endfunction

  function void report_phase(uvm_phase phase);
    if (model != null)
      `uvm_info(get_type_name(), $sformatf("bringup model: final state %s, %0d mismatches",
                                           model.st.name(), model.n_mismatch), UVM_LOW)
  endfunction
endclass
