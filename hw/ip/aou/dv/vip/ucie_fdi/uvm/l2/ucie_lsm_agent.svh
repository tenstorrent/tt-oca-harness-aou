// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L2 agent: the link state of one FDI (UCIe r3.0 §10.2: one FDI instance per
// Protocol Layer to Adapter connection; an Adapter that hosts several protocol
// stacks has one FDI, so one of these agents, per stack). Before build the
// parent sets `cfg` (or puts an ucie_lsm_cfg in config_db under "cfg"), sets
// `lsm_vif` (or puts it in config_db under "fdi_lsm") and adds the mainband
// agent of the FDI to `phy`: the driver closes its gate and stalls its TX
// before leaving Active, and both driver and monitor take pl_state_sts from
// its interface. With cfg.n_phy 2 two mainband agents share this link state
// (mirrored mode, see ucie_lsm_cfg). In passive mode (cfg.is_active 0) `phy`
// holds the passive mainband agents.
class ucie_lsm_agent extends uvm_agent;
  `uvm_component_utils(ucie_lsm_agent)

  ucie_lsm_cfg                   cfg;
  virtual ucie_fdi_lsm_if        lsm_vif;
  ucie_fdi_agent                 phy[$];
  uvm_sequencer #(ucie_lsm_item) sqr;
  ucie_lsm_driver                drv;
  ucie_lsm_monitor               mon;
  ucie_lsm_fcov                  fcov;  // the model's own coverage (cfg.fcov_en)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The model's plusargs for this agent (README "Plusargs"; plusarg_int):
  // each also takes +<name>@<this agent's full name>=<v>, and the unprefixed
  // names of earlier versions remain as aliases.
  local function void read_plusargs();
    string me = get_full_name();
    int unsigned n;
    string r;
    if (plusarg_int("ucie_react_linkerror", me, n, "react_linkerror"))
      cfg.react_linkerror_en = n != 0;
    // Cycles the Adapter stays in Reset after a link-down before software
    // restarts the training; a value set in the cfg stands unless this is given.
    if (plusarg_int("ucie_sw_restart_delay", me, n, "sw_restart_delay")) cfg.sw_restart_delay = n;
    if (plusarg_str("ucie_restart_on", me, r))
      case (r)
        "sw":     cfg.restart_on = LSM_RESTART_SW;
        "pl":     cfg.restart_on = LSM_RESTART_PL;
        "either": cfg.restart_on = LSM_RESTART_EITHER;
        default:  `uvm_fatal(get_type_name(), {"+ucie_restart_on: not sw, pl or either: ", r})
      endcase
    if (plusarg_str("ucie_down_exit", me, r))
      case (r)
        "internal": cfg.down_exit_on = LSM_EXIT_INTERNAL;
        "pl":       cfg.down_exit_on = LSM_EXIT_PL;
        "either":   cfg.down_exit_on = LSM_EXIT_EITHER;
        default:
          `uvm_fatal(get_type_name(), {"+ucie_down_exit: not internal, pl or either: ", r})
      endcase
    if (plusarg_int("ucie_remote_active_first_pct", me, n)) cfg.remote_active_first_pct = n;
    if (plusarg_int("ucie_le_mid_flit_pct", me, n, "le_mid_flit_pct")) cfg.le_mid_flit_pct = n;
    if (plusarg_int("ucie_rx_early", me, n, "fdi_rx_early")) cfg.rx_early = n;
    if (plusarg_int("ucie_park_idle_phy", me, n, "park_idle_phy")) cfg.park_idle_phy = n != 0;
    if (plusarg_int("ucie_fcov", me, n)) cfg.fcov_en = n != 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db #(ucie_lsm_cfg)::get(this, "", "cfg", cfg))
      cfg = ucie_lsm_cfg::type_id::create("cfg");
    read_plusargs();
    if (cfg.n_phy < 1 || cfg.n_phy > 2)
      `uvm_fatal(get_type_name(), $sformatf("n_phy %0d not 1 or 2", cfg.n_phy))
    if (phy.size() != cfg.n_phy)
      `uvm_fatal(get_type_name(), $sformatf("n_phy %0d, but %0d mainband agents in phy",
                                            cfg.n_phy, phy.size()))
    if (lsm_vif == null && !uvm_config_db #(virtual ucie_fdi_lsm_if)::get(this, "", "fdi_lsm",
                                                                           lsm_vif))
      `uvm_fatal(get_type_name(), "no lsm_vif set and no fdi_lsm in config_db")
    `uvm_info(get_type_name(), cfg.convert2string(), UVM_LOW)
    mon = ucie_lsm_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    mon.lsm_vif = lsm_vif;
    if (cfg.fcov_en) fcov = ucie_lsm_fcov::type_id::create("fcov");
    if (cfg.is_active) begin
      sqr = uvm_sequencer #(ucie_lsm_item)::type_id::create("sqr", this);
      drv = ucie_lsm_driver::type_id::create("drv", this);
      drv.cfg = cfg;
      drv.phy = phy;
      drv.lsm_vif = lsm_vif;
      drv.fcov = fcov;
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

  // The mainband interfaces come from the mainband agents, built by now.
  function void connect_phase(uvm_phase phase);
    virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];
    super.connect_phase(phase);
    foreach (phy[p]) mb_vif[p] = phy[p].vif;
    if (cfg.n_phy == 1) mb_vif[1] = mb_vif[0];
    mon.mb_vif = mb_vif;
    if (cfg.is_active) drv.mb_vif = mb_vif;
    check_link_cfg();
    if (cfg.is_active) drv.seq_item_port.connect(sqr.seq_item_export);
    if (fcov != null) mon.add_observer(fcov);
  endfunction

`ifndef VERILATOR
  // The covergroups' scores (this simulator scores them; Verilator 5.052 does
  // not, so it prints nothing).
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (fcov != null)
      `uvm_info(get_type_name(), {"link-state coverage: ", fcov.convert2string()}, UVM_LOW)
  endfunction
`endif
endclass
