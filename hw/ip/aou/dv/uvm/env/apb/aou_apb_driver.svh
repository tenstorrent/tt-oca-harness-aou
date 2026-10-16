// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// APB3 requester. Drives SETUP then ACCESS, holds ACCESS while PREADY is low, and
// returns PRDATA/PSLVERR in the request item. Every drive and sample goes
// through drv_cb, so the loop below always resumes on a PCLK edge.
class aou_apb_driver extends uvm_driver #(aou_apb_item);
  `uvm_component_utils(aou_apb_driver)

  aou_apb_cfg cfg;
  virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)) vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) `uvm_fatal(get_type_name(), "no aou_apb_cfg set by the agent")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    drive_idle();
    forever begin
      wait_reset_released();
      if (cfg.hold) begin
        drive_idle();
        @(vif.drv_cb);
        continue;
      end
      seq_item_port.try_next_item(req);
      if (req == null) begin
        drive_idle();
        @(vif.drv_cb);
        continue;
      end
      drive_transfer(req);
      seq_item_port.item_done();
      if (!cfg.back_to_back) idle_gap();
    end
  endtask

  // Waits until PRESETN is high, leaving the bus idle meanwhile.
  task wait_reset_released();
    if (vif.drv_cb.presetn === 1'b1) return;
    drive_idle();
    do @(vif.drv_cb); while (vif.drv_cb.presetn !== 1'b1);
  endtask

  task idle_gap();
    int unsigned n;
    n = cfg.min_idle_cycles;
    if (cfg.max_idle_cycles > cfg.min_idle_cycles)
      n = $urandom_range(cfg.max_idle_cycles, cfg.min_idle_cycles);
    if (n == 0) return;
    drive_idle();
    repeat (n) @(vif.drv_cb);
  endtask

  function void drive_idle();
    vif.drv_cb.psel    <= 1'b0;
    vif.drv_cb.penable <= 1'b0;
  endfunction

  // Called on a PCLK edge; returns on the edge that completes the transfer.
  task drive_transfer(aou_apb_item it);
    it.t_start = $time;
    it.wait_cycles = 0;
    vif.drv_cb.psel    <= 1'b1;
    vif.drv_cb.penable <= 1'b0;
    vif.drv_cb.paddr   <= it.addr;
    vif.drv_cb.pwrite  <= (it.dir == AOU_APB_WRITE);
    vif.drv_cb.pwdata  <= (it.dir == AOU_APB_WRITE) ? it.data : '0;
    @(vif.drv_cb);
    vif.drv_cb.penable <= 1'b1;
    @(vif.drv_cb);
    while (vif.drv_cb.pready !== 1'b1) begin
      if (vif.drv_cb.presetn !== 1'b1) begin
        `uvm_info(get_type_name(), {"reset during transfer, abandoned: ", it.convert2string()},
                  UVM_LOW)
        it.slverr = 1'b1;
        drive_idle();
        return;
      end
      it.wait_cycles++;
      @(vif.drv_cb);
    end
    it.slverr = vif.drv_cb.pslverr;
    if (it.dir == AOU_APB_READ) it.data = vif.drv_cb.prdata;
    it.t_end = $time;
    // Without back-to-back the bus goes idle now; with it, the next SETUP (or
    // the idle drive when nothing is queued) overrides these on this edge.
    vif.drv_cb.penable <= 1'b0;
    if (!cfg.back_to_back) vif.drv_cb.psel <= 1'b0;
    `uvm_info(get_type_name(), it.convert2string(), UVM_HIGH)
  endtask
endclass
