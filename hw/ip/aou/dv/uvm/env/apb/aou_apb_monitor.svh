// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Publishes one item per completed APB transfer, on the PCLK edge that
// completes it, and checks the PREADY time-out (APB-R14).
class aou_apb_monitor extends uvm_monitor;
  `uvm_component_utils(aou_apb_monitor)

  aou_apb_cfg cfg;
  virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)) vif;
  uvm_analysis_port #(aou_apb_item) ap;

  int unsigned n_transfers;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) `uvm_fatal(get_type_name(), "no aou_apb_cfg set by the agent")
    vif = cfg.vif;
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned waits;
    time t_setup;
    bit in_transfer;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.presetn !== 1'b1) begin
        in_transfer = 1'b0;
        continue;
      end
      if (vif.mon_cb.psel !== 1'b1) begin
        in_transfer = 1'b0;
        continue;
      end
      if (vif.mon_cb.penable !== 1'b1) begin
        // SETUP cycle.
        in_transfer = 1'b1;
        waits = 0;
        t_setup = $time;
        continue;
      end
      if (vif.mon_cb.pready !== 1'b1) begin
        waits++;
        if (waits == cfg.max_wait_cycles + 1)
          `uvm_error(get_type_name(), $sformatf(
              "APB-R14: PREADY low for more than %0d ACCESS cycles at PADDR 0x%08h",
              cfg.max_wait_cycles, vif.mon_cb.paddr))
        continue;
      end
      publish(waits, in_transfer ? t_setup : $time);
      in_transfer = 1'b0;
    end
  endtask

  function void publish(int unsigned waits, time t_setup);
    aou_apb_item it = aou_apb_item::type_id::create("it");
    it.dir         = vif.mon_cb.pwrite ? AOU_APB_WRITE : AOU_APB_READ;
    it.addr        = vif.mon_cb.paddr;
    it.data        = vif.mon_cb.pwrite ? vif.mon_cb.pwdata : vif.mon_cb.prdata;
    it.slverr      = vif.mon_cb.pslverr;
    it.wait_cycles = waits;
    it.t_start     = t_setup;
    it.t_end       = $time;
    n_transfers++;
    `uvm_info(get_type_name(), it.convert2string(), UVM_HIGH)
    ap.write(it);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("%0d APB transfers observed", n_transfers), UVM_LOW)
  endfunction
endclass
