// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L2 agent. The parent sets `cfg` (or puts an aou_lsm_cfg in config_db under
// "cfg"), including the L1 gates and responders of each PHY. Virtual
// interfaces come from config_db keys "fdi_lsm" and "fdi_mb<p>".
class aou_lsm_agent extends uvm_agent;
  `uvm_component_utils(aou_lsm_agent)

  aou_lsm_cfg                   cfg;
  uvm_sequencer #(aou_lsm_item) sqr;
  aou_lsm_driver                drv;
  aou_lsm_monitor               mon;

  local virtual aou_fdi_lsm_if                   lsm_vif;
  local virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string enc;
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db #(aou_lsm_cfg)::get(this, "", "cfg", cfg))
      cfg = aou_lsm_cfg::type_id::create("cfg");
    // +FDI_ENC=SPEC|RTL overrides the test's choice (runs against a DUT with a
    // BUGS/001 fix).
    if ($value$plusargs("FDI_ENC=%s", enc)) begin
      if (enc == "SPEC") cfg.fdi_enc = AOU_FDI_ENC_SPEC;
      else if (enc == "RTL") cfg.fdi_enc = AOU_FDI_ENC_RTL;
      else `uvm_fatal(get_type_name(), $sformatf("+FDI_ENC=%s: not SPEC or RTL", enc))
    end
    // +react_linkerror=0|1 overrides cfg.react_linkerror_en.
    void'($value$plusargs("react_linkerror=%b", cfg.react_linkerror_en));
    // +train_trigger=0 lets the Adapter train again after a link-down without
    // waiting for NOP->Active (an Adapter or remote die that restarts by itself).
    void'($value$plusargs("train_trigger=%b", cfg.train_trigger_en));
    void'($value$plusargs("le_mid_flit_pct=%d", cfg.le_mid_flit_pct));
    void'($value$plusargs("park_idle_phy=%b", cfg.park_idle_phy));
    if (cfg.n_phy < 1 || cfg.n_phy > 2)
      `uvm_fatal(get_type_name(), $sformatf("n_phy %0d not 1 or 2", cfg.n_phy))
    if (!uvm_config_db #(virtual aou_fdi_lsm_if)::get(this, "", "fdi_lsm", lsm_vif))
      `uvm_fatal(get_type_name(), "no fdi_lsm in config_db")
    for (int p = 0; p < cfg.n_phy; p++)
      if (!uvm_config_db #(virtual aou_fdi_mb_if #(.DATA_W(BUS_W)))::get(
              this, "", $sformatf("fdi_mb%0d", p), mb_vif[p]))
        `uvm_fatal(get_type_name(), $sformatf("no fdi_mb%0d in config_db", p))
    if (cfg.n_phy == 1) mb_vif[1] = mb_vif[0];
    `uvm_info(get_type_name(), cfg.convert2string(), UVM_LOW)
    mon = aou_lsm_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    mon.lsm_vif = lsm_vif;
    mon.mb_vif = mb_vif;
    if (cfg.is_active) begin
      sqr = uvm_sequencer #(aou_lsm_item)::type_id::create("sqr", this);
      drv = aou_lsm_driver::type_id::create("drv", this);
      drv.cfg = cfg;
      drv.lsm_vif = lsm_vif;
      drv.mb_vif = mb_vif;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
