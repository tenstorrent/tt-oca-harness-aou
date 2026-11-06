// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L2 agent. Before build the parent sets `cfg` (or puts an ucie_lsm_cfg in
// config_db under "cfg") and adds the mainband agent of each PHY to `phy`:
// the driver closes their gates and stalls their TX before leaving Active.
// Virtual interfaces come from config_db keys "fdi_lsm" and "fdi_mb<p>".
class ucie_lsm_agent extends uvm_agent;
  `uvm_component_utils(ucie_lsm_agent)

  ucie_lsm_cfg                   cfg;
  ucie_fdi_agent                 phy[$];
  uvm_sequencer #(ucie_lsm_item) sqr;
  ucie_lsm_driver                drv;
  ucie_lsm_monitor               mon;

  local virtual ucie_fdi_lsm_if                   lsm_vif;
  local virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db #(ucie_lsm_cfg)::get(this, "", "cfg", cfg))
      cfg = ucie_lsm_cfg::type_id::create("cfg");
    // +react_linkerror=0|1 overrides cfg.react_linkerror_en.
    void'($value$plusargs("react_linkerror=%b", cfg.react_linkerror_en));
    // +sw_restart_delay=N: cycles the Adapter stays in Reset after a link-down
    // before software restarts the training (0: at once); random in [50:1500]
    // otherwise, so a DUT that requests anything of the link meanwhile is
    // caught at many delays.
    if (!$value$plusargs("sw_restart_delay=%d", cfg.sw_restart_delay))
      cfg.sw_restart_delay = $urandom_range(1500, 50);
    void'($value$plusargs("le_mid_flit_pct=%d", cfg.le_mid_flit_pct));
    void'($value$plusargs("fdi_rx_early=%d", cfg.rx_early));
    void'($value$plusargs("park_idle_phy=%b", cfg.park_idle_phy));
    if (cfg.n_phy < 1 || cfg.n_phy > 2)
      `uvm_fatal(get_type_name(), $sformatf("n_phy %0d not 1 or 2", cfg.n_phy))
    if (!uvm_config_db #(virtual ucie_fdi_lsm_if)::get(this, "", "fdi_lsm", lsm_vif))
      `uvm_fatal(get_type_name(), "no fdi_lsm in config_db")
    for (int p = 0; p < cfg.n_phy; p++)
      if (!uvm_config_db #(virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)))::get(
              this, "", $sformatf("fdi_mb%0d", p), mb_vif[p]))
        `uvm_fatal(get_type_name(), $sformatf("no fdi_mb%0d in config_db", p))
    if (cfg.n_phy == 1) mb_vif[1] = mb_vif[0];
    `uvm_info(get_type_name(), cfg.convert2string(), UVM_LOW)
    mon = ucie_lsm_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    mon.lsm_vif = lsm_vif;
    mon.mb_vif = mb_vif;
    if (cfg.is_active) begin
      sqr = uvm_sequencer #(ucie_lsm_item)::type_id::create("sqr", this);
      drv = ucie_lsm_driver::type_id::create("drv", this);
      drv.cfg = cfg;
      drv.phy = phy;
      drv.lsm_vif = lsm_vif;
      drv.mb_vif = mb_vif;
    end
  endfunction

  // What the Adapter reports must be encodable and agree with itself: a
  // defined protocol, a speed within the negotiated maximum (above 32 GT/s
  // needs pl_max_speedmode 1), a defined width, and a stream on every FDI that
  // names the protocol.
  local function void check_link_cfg();
    if (!protocol_defined(cfg.protocol))
      `uvm_fatal(get_type_name(), $sformatf("protocol %04b is reserved", cfg.protocol))
    if (cfg.speedmode > 3'b101 && !cfg.max_speedmode)
      `uvm_fatal(get_type_name(), $sformatf("speedmode %03b is above 32 GT/s with max_speedmode 0",
                                            cfg.speedmode))
    if (cfg.lnk_cfg == 3'b111)
      `uvm_fatal(get_type_name(), "lnk_cfg 111b is reserved")
    foreach (phy[p])
      if (!stream_fits(cfg.protocol, phy[p].cfg.stream))
        `uvm_fatal(get_type_name(), $sformatf("phy%0d stream %02h does not fit protocol %04b", p,
                                              phy[p].cfg.stream, cfg.protocol))
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    check_link_cfg();
    if (cfg.is_active) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
