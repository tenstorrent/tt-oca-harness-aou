// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// FDI bringup on the real DUT, RTL state encoding:
// 1. reset; the L2 agent runs the Adapter side of bringup (clk_req
//    handshake, inband_pres) with pl_clk_req released, so the DUT waits in
//    WAIT_PRESENCE until I_SW_ACTIVATE_START;
// 2. the DUT reaches Active (O_FDI_LINK_UP); empty flits with cancels,
//    poisoned cancelled halves and bubbles go to the DUT RX;
// 3. APB AOU_INIT.activate_start (0x08 bit 0) makes the core send an
//    ActivateReq, which the L1 monitor must capture on the DUT TX;
// 4. link events (Retrain, L1 entry/exit) and more flits.
// The bringup model and the L1/L2 rule checks run throughout.
class aou_fdi_t1_bringup_test extends uvm_test;
  `uvm_component_utils(aou_fdi_t1_bringup_test)

  aou_fdi_t1_env  env;
  aou_fdi_msg_log msg_log;
  uvm_tlm_analysis_fifo #(aou_flit_item) tx_fifo;

  virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)) apb_vif;
  virtual aou_fdi_lsm_if lsm_vif;

  int unsigned link_timeout = 20000;
  int unsigned n_flits_sent;
  bit          saw_linkreset;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = aou_fdi_t1_env::type_id::create("env", this);
    msg_log = aou_fdi_msg_log::type_id::create("msg_log");
    tx_fifo = new("tx_fifo", this);
    if (!uvm_config_db #(virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)))::get(
            this, "", "apb", apb_vif))
      `uvm_fatal(get_type_name(), "no apb in config_db")
    if (!uvm_config_db #(virtual aou_fdi_lsm_if)::get(this, "", "fdi_lsm", lsm_vif))
      `uvm_fatal(get_type_name(), "no fdi_lsm in config_db")
    configure();
  endfunction

  virtual function void configure();
    env.lsm_cfg.fdi_enc = AOU_FDI_ENC_RTL;
    env.lsm_cfg.clk_req_hold_bringup = 1'b0;
    foreach (env.fdi_cfg[p]) env.fdi_cfg[p].trdy_policy = AOU_TRDY_HOLES;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.fdi[0].mon.ap_tx.connect(tx_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    apb_vif.drv_cb.psel <= 1'b0;
    apb_vif.drv_cb.penable <= 1'b0;
    apb_vif.drv_cb.pwrite <= 1'b0;
    apb_vif.drv_cb.paddr <= '0;
    apb_vif.drv_cb.pwdata <= '0;
    fork
      collect_tx();
      watch_linkreset();
    join_none

    while (lsm_vif.mon_cb.rst_n !== 1'b1 || lsm_vif.mon_cb.pl_inband_pres !== 1'b1)
      @(lsm_vif.mon_cb);
    repeat (20) @(lsm_vif.mon_cb);
    if (!env.lsm_cfg.clk_req_hold_bringup) begin
      // The DUT waits in WAIT_PRESENCE; losing presence sends it back to RESET.
      env.lsm.drv.do_inband_drop(30);
      repeat (10) @(lsm_vif.mon_cb);
    end
    `uvm_info(get_type_name(), "pulsing I_SW_ACTIVATE_START", UVM_LOW)
    env.lsm.drv.pulse_sw(LSM_SW_ACTIVATE, 2);
    wait_link_up("bringup");

    send_flits(16, 50);
    pre_activate();
    `uvm_info(get_type_name(), "APB write AOU_INIT.activate_start", UVM_LOW)
    apb_write(32'h0000_0008, 32'h0000_0001);
    wait_activate_req();

    link_events();
    send_flits(8, 25);
    repeat (200) @(lsm_vif.mon_cb);
    phase.drop_objection(this);
  endtask

  // Runs with the link Active and the AoU core still deactivated.
  virtual task pre_activate();
  endtask

  virtual task link_events();
    aou_lsm_retrain_seq retrain = aou_lsm_retrain_seq::type_id::create("retrain");
    aou_lsm_l1_seq l1 = aou_lsm_l1_seq::type_id::create("l1");
    `uvm_info(get_type_name(), "Adapter-initiated Retrain", UVM_LOW)
    retrain.start(env.lsm.sqr);
    wait_link_up("retrain");
    send_flits(4, 50);
    `uvm_info(get_type_name(), "L1 entry and exit", UVM_LOW)
    l1.start(env.lsm.sqr);
    wait_link_up("L1 exit");
  endtask

  task send_flits(int unsigned n, int unsigned cancel_pct);
    aou_flit_seq seq = aou_flit_seq::type_id::create("flits");
    seq.n_flits = n;
    seq.cancel_pct = cancel_pct;
    seq.bubble_pct = 20;
    seq.start(env.fdi[0].sqr);
    n_flits_sent += n;
  endtask

  task wait_link_up(string what);
    int unsigned n;
    while (!(lsm_vif.mon_cb.fdi_link_up === 1'b1 && env.lsm.drv.link_active)) begin
      @(lsm_vif.mon_cb);
      if (++n == link_timeout) begin
        `uvm_error(get_type_name(), $sformatf("%s: link not up after %0d cycles", what, n))
        return;
      end
    end
    `uvm_info(get_type_name(), $sformatf("%s: link up", what), UVM_LOW)
  endtask

  task wait_activate_req();
    int unsigned n;
    while (msg_log.n_activate_req == 0) begin
      @(lsm_vif.mon_cb);
      if (++n == link_timeout) begin
        `uvm_error(get_type_name(), "no ActivateReq from the DUT TX")
        return;
      end
    end
    `uvm_info(get_type_name(), $sformatf("ActivateReq seen after %0d cycles", n), UVM_LOW)
  endtask

  task apb_write(bit [31:0] addr, bit [31:0] data);
    @(apb_vif.drv_cb);
    apb_vif.drv_cb.psel <= 1'b1;
    apb_vif.drv_cb.penable <= 1'b0;
    apb_vif.drv_cb.pwrite <= 1'b1;
    apb_vif.drv_cb.paddr <= addr;
    apb_vif.drv_cb.pwdata <= data;
    @(apb_vif.drv_cb);
    apb_vif.drv_cb.penable <= 1'b1;
    do @(apb_vif.drv_cb); while (apb_vif.drv_cb.pready !== 1'b1);
    if (apb_vif.drv_cb.pslverr !== 1'b0)
      `uvm_error(get_type_name(), $sformatf("APB write 0x%0h: PSLVERR", addr))
    apb_vif.drv_cb.psel <= 1'b0;
    apb_vif.drv_cb.penable <= 1'b0;
  endtask

  local task collect_tx();
    forever begin
      aou_flit_item f;
      tx_fifo.get(f);
      msg_log.log_flit(f);
    end
  endtask

  local task watch_linkreset();
    forever begin
      @(lsm_vif.mon_cb);
      if (lsm_vif.mon_cb.int_req_linkreset === 1'b1 && !saw_linkreset) begin
        saw_linkreset = 1'b1;
        `uvm_error(get_type_name(), "the DUT requested LinkReset (O_AOU_REQ_LINKRESET)")
      end
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (msg_log.n_activate_req == 0) `uvm_error(get_type_name(), "no ActivateReq captured")
    // A flit abandoned by a LinkError mid-flit (+le_mid_flit_pct) never arrives.
    if (env.fdi[0].mon.n_rx_flits + env.fdi_cfg[0].gate.n_abandoned != n_flits_sent)
      `uvm_error(get_type_name(), $sformatf("monitor saw %0d RX flits, %0d sent, %0d abandoned",
                                            env.fdi[0].mon.n_rx_flits, n_flits_sent,
                                            env.fdi_cfg[0].gate.n_abandoned))
    // With checks on, the model has already reported each mismatch.
    if (env.lsm.mon.model != null && env.lsm.mon.model.n_mismatch != 0 && !env.lsm_cfg.checks_en)
      `uvm_error(get_type_name(), $sformatf("bringup model: %0d mismatches",
                                            env.lsm.mon.model.n_mismatch))
  endfunction

  // The rule ledger (checkers/aou_rule_log.svh) for scripts/rule_inventory.py.
  function void report_phase(uvm_phase phase);
    string q[$];
    super.report_phase(phase);
    aou_rule_log::lines(q);
    foreach (q[i]) `uvm_info(get_type_name(), q[i], UVM_NONE)
  endfunction
endclass
