// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L1 agent of one PHY. The parent sets `cfg` (or puts an ucie_fdi_cfg in
// config_db under "cfg"); the virtual interface comes from config_db key
// "fdi_mb<phy>".
class ucie_fdi_agent extends uvm_agent;
  `uvm_component_utils(ucie_fdi_agent)

  ucie_fdi_cfg                       cfg;
  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  uvm_sequencer #(ucie_flit_item)    sqr;
  ucie_fdi_pl_driver                 drv;
  ucie_fdi_tx_responder              rsp;
  ucie_fdi_monitor                   mon;
  ucie_fdi_fcov                      fcov;  // the model's own coverage (cfg.fcov_en)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    int unsigned n;
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db #(ucie_fdi_cfg)::get(this, "", "cfg", cfg))
      cfg = ucie_fdi_cfg::type_id::create("cfg");
    if (!uvm_config_db #(virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)))::get(
            this, "", $sformatf("fdi_mb%0d", cfg.phy), vif))
      `uvm_fatal(get_type_name(), $sformatf("no fdi_mb%0d in config_db", cfg.phy))
    if (!valid_beat_bytes(cfg.beat_bytes))
      `uvm_fatal(get_type_name(), $sformatf(
                 "beat_bytes %0d: not 32, 64, 128, 256, 512 or 1024", cfg.beat_bytes))
    if (!(cfg.stream[7:4] inside {4'h0, 4'h1}) || !(cfg.stream[3:0] inside {[4'h1:4'h5]}))
      `uvm_fatal(get_type_name(), $sformatf("stream %02h is a reserved stream ID", cfg.stream))
    if (!stream_layout_modelled(cfg.stream))
      `uvm_fatal(get_type_name(), $sformatf({"stream %02h: the model carries the Format 6 ",
                 "layout of Streaming and CXL.cachemem only (r3.0 Figures 3-24, 3-25), not ",
                 "that of PCIe, CXL.io or Management Transport"}, cfg.stream))
    // The model's plusargs (README "Plusargs"; plusarg_int: also
    // +<name>@<this agent's full name>=<v>).
    if (plusarg_int("ucie_nop_pct", get_full_name(), n)) cfg.nop_pct = n;
    if (plusarg_int("ucie_fcov", get_full_name(), n)) cfg.fcov_en = n != 0;
    mon = ucie_fdi_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    mon.vif = vif;
    if (cfg.fcov_en) begin
      fcov = ucie_fdi_fcov::type_id::create($sformatf("fcov%0d", cfg.phy));
      fcov.fdi_bytes = cfg.beat_bytes;
      mon.fcov = fcov;
    end
    if (cfg.is_active) begin
      sqr = uvm_sequencer #(ucie_flit_item)::type_id::create("sqr", this);
      drv = ucie_fdi_pl_driver::type_id::create("drv", this);
      rsp = ucie_fdi_tx_responder::type_id::create("rsp", this);
      drv.cfg = cfg;
      drv.vif = vif;
      rsp.cfg = cfg;
      rsp.vif = vif;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

`ifndef VERILATOR
  // The covergroups' scores (this simulator scores them; Verilator 5.052 does
  // not, so it prints nothing).
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (fcov != null)
      `uvm_info(get_type_name(), $sformatf("phy%0d coverage: %s", cfg.phy, fcov.convert2string()),
                UVM_LOW)
  endfunction
`endif
endclass
