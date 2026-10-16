// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI4 manager: sequencer, driver and monitor. The config comes from
// uvm_config_db key "cfg"; ap carries the monitor's completed transactions.
class aou_axi_mgr_agent extends uvm_agent;
  `uvm_component_utils(aou_axi_mgr_agent)

  aou_axi_cfg        cfg;
  aou_axi_sequencer  sqr;
  aou_axi_mgr_driver drv;
  aou_axi_monitor    mon;
  uvm_analysis_port #(aou_axi_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db#(aou_axi_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "no aou_axi_cfg under config_db key cfg")
    cfg.check_cfg(get_type_name());
    if (cfg.vif == null &&
        !uvm_config_db#(virtual aou_axi_bus_if #(.DATA_W(1024)))::get(this, "", cfg.vif_key,
                                                                       cfg.vif))
      `uvm_fatal(get_type_name(), $sformatf("no aou_axi_bus_if under config_db key '%s'",
                                            cfg.vif_key))
    ap = new("ap", this);
    if (cfg.has_monitor) begin
      mon = aou_axi_monitor::type_id::create("mon", this);
      mon.cfg = cfg;
    end
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = aou_axi_sequencer::type_id::create("sqr", this);
      drv = aou_axi_mgr_driver::type_id::create("drv", this);
      sqr.cfg = cfg;
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (mon != null) mon.ap.connect(ap);
    if (drv != null) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
