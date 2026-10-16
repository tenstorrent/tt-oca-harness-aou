// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI4 subordinate answering from cfg.mem, plus a monitor. The config comes
// from uvm_config_db key "cfg"; ap carries the monitor's completed transactions.
class aou_axi_sub_agent extends uvm_agent;
  `uvm_component_utils(aou_axi_sub_agent)

  aou_axi_cfg        cfg;
  aou_axi_sub_driver drv;
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
    if (cfg.mem == null) cfg.mem = aou_mem::type_id::create("mem");
    ap = new("ap", this);
    if (cfg.has_monitor) begin
      mon = aou_axi_monitor::type_id::create("mon", this);
      mon.cfg = cfg;
    end
    if (cfg.is_active == UVM_ACTIVE) begin
      drv = aou_axi_sub_driver::type_id::create("drv", this);
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (mon != null) mon.ap.connect(ap);
  endfunction
endclass
