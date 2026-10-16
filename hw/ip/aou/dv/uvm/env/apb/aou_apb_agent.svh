// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// APB3 requester agent. It owns the register adapter; connect_reg_map() makes a
// register map use this agent and connect_predictor() wires explicit prediction
// from the monitor, so the mirror follows what was observed on the bus.
class aou_apb_agent extends uvm_agent;
  `uvm_component_utils(aou_apb_agent)

  aou_apb_cfg         cfg;
  aou_apb_driver      drv;
  aou_apb_sequencer   sqr;
  aou_apb_monitor     mon;
  aou_apb_reg_adapter reg_adapter;
  uvm_analysis_port #(aou_apb_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db#(aou_apb_cfg)::get(this, "", "cfg", cfg))
      cfg = aou_apb_cfg::type_id::create("cfg");
    if (cfg.vif == null &&
        !uvm_config_db#(virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)))::get(
            this, "", cfg.vif_key, cfg.vif))
      `uvm_fatal(get_type_name(), {"no aou_apb_if under config_db key '", cfg.vif_key, "'"})
    mon = aou_apb_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = aou_apb_sequencer::type_id::create("sqr", this);
      drv = aou_apb_driver::type_id::create("drv", this);
      drv.cfg = cfg;
    end
    reg_adapter = aou_apb_reg_adapter::type_id::create("reg_adapter");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = mon.ap;
    if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

  // Front-door accesses through map go out on this agent.
  function void connect_reg_map(uvm_reg_map map);
    if (sqr == null) `uvm_fatal(get_type_name(), "connect_reg_map needs an active agent")
    map.set_sequencer(sqr, reg_adapter);
  endfunction

  // Explicit prediction: the mirror of map changes only on observed transfers.
  // Call from connect_phase, after build_phase has created the agent.
  function void connect_predictor(uvm_reg_predictor #(aou_apb_item) predictor,
                                  uvm_reg_map map);
    predictor.map     = map;
    predictor.adapter = reg_adapter;
    map.set_auto_predict(0);
    mon.ap.connect(predictor.bus_in);
  endfunction

  // Returns on the first PCLK edge with PRESETN high.
  task wait_reset_released();
    do @(cfg.vif.mon_cb); while (cfg.vif.mon_cb.presetn !== 1'b1);
  endtask

  task wait_cycles(int unsigned n);
    repeat (n) @(cfg.vif.mon_cb);
  endtask
endclass
