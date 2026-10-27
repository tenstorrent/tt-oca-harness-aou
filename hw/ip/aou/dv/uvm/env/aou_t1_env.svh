// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1 environment (docs/ARCHITECTURE.md, "Test layer API"). Local side: an AXI
// manager on every S port and a subordinate on every M port, all answering
// from one local memory; the APB agent with the register model. Remote side:
// L1 per PHY and L2 at FDI, L3 between L1 and the remote AXI side (the L4a
// adapter over aou_remote_axi_model for DUT requests, aou_t1_remote_mgr for
// remote-originated traffic). The scoreboard checks bytes in both directions;
// the status watcher, AOU_FDI_CHECKER adapter and expectation registry judge
// the rest.
class aou_t1_env extends uvm_env;
  `uvm_component_utils(aou_t1_env)

  aou_t1_env_cfg       cfg;
  aou_axi_mgr_agent    s_mgr[];
  aou_axi_sub_agent    m_sub[];
  aou_fdi_agent        fdi[AOU_T1_N_PHY];
  aou_lsm_agent        lsm;
  aou_l3_agent         l3;
  aou_remote_axi_model remote;
  aou_t1_l4a_adapter   l4a;
  aou_t1_remote_mgr    rmgr;
  aou_t1_flit_bridge   bridge;
  aou_apb_agent        apb;
  aou_t1_reg_env       regs;
  aou_t1_reset_agent   rst;
  aou_scoreboard       sb;
  aou_t1_status        status;
  aou_t1_sw_isr        sw_isr;
  aou_t1_axi4pc_ctl    axi4pc;
  aou_t1_mo_chk        mo_chk;
  aou_t1_sw_reset_chk  sw_rst_chk;
  aou_t1_lp_cfg_chk    lp_cfg_chk;
  aou_t1_force_deact_chk force_chk;
  aou_t1_dbg_fifo_chk  dbg_chk;
  aou_t1_crd_flow_chk  crd_chk;
  aou_t1_crd_rr_chk    crd_rr;
  aou_t1_crd_block_chk crd_blk;
  aou_t1_wr_order_chk  wr_order;
  aou_t1_early_tbl_chk early_tbl;
  aou_t1_wdt_chk       wdt_chk;
  aou_t1_attr_chk      attr_chk;
  aou_t1_xfer_cov      xfer_cov;
  aou_t1_rx_fifo_chk   rx_fifo_chk;
  aou_t1_rx_align_chk  rx_align;
  aou_fdi_chk_adapter  fdi_chk;
  aou_t1_expect        expects;   // "expect" is an SV keyword
  aou_t1_vseqr         vseqr;
  aou_t1_l1_pump_seq   pump;

  virtual aou_fdi_lsm_if lsm_vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db #(aou_t1_env_cfg)::get(this, "", "cfg", cfg))
      cfg = aou_t1_env_cfg::type_id::create("cfg");
    cfg.finalize();
    `uvm_info(get_type_name(), cfg.convert2string(), UVM_LOW)
    if (!uvm_config_db #(virtual aou_fdi_lsm_if)::get(this, "", "fdi_lsm", lsm_vif))
      `uvm_fatal(get_type_name(), "no fdi_lsm in config_db")

    expects = aou_t1_expect::type_id::create("expects", this);
    rst = aou_t1_reset_agent::type_id::create("rst", this);
    rst.apb_cfg = cfg.apb_cfg;

    s_mgr = new[cfg.n_rp];
    m_sub = new[cfg.n_rp];
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      s_mgr[r] = aou_axi_mgr_agent::type_id::create($sformatf("s_mgr%0d", r), this);
      s_mgr[r].cfg = cfg.s_mgr_cfg[r];
      m_sub[r] = aou_axi_sub_agent::type_id::create($sformatf("m_sub%0d", r), this);
      m_sub[r].cfg = cfg.m_sub_cfg[r];
    end

    foreach (fdi[p]) begin
      fdi[p] = aou_fdi_agent::type_id::create($sformatf("fdi%0d", p), this);
      fdi[p].cfg = cfg.fdi_cfg[p];
      cfg.lsm_cfg.gate.push_back(cfg.fdi_cfg[p].gate);
    end
    lsm = aou_lsm_agent::type_id::create("lsm", this);
    lsm.cfg = cfg.lsm_cfg;

    remote = aou_remote_axi_model::type_id::create("remote", this);
    remote.cfg = cfg.remote_cfg;
    l4a = aou_t1_l4a_adapter::type_id::create("l4a");
    l4a.remote = remote;
    l4a.cfg = cfg;
    cfg.l3_cfg.l4a = l4a;
    l3 = aou_l3_agent::type_id::create("l3", this);
    l3.cfg = cfg.l3_cfg;
    rmgr = aou_t1_remote_mgr::type_id::create("rmgr", this);
    rmgr.cfg = cfg.r_mgr_cfg;
    rmgr.l3 = l3;
    bridge = aou_t1_flit_bridge::type_id::create("bridge", this);

    regs = aou_t1_reg_env::type_id::create("regs", this);
    regs.apb_cfg = cfg.apb_cfg;

    sb = aou_scoreboard::type_id::create("sb", this);
    status = aou_t1_status::type_id::create("status", this);
    status.checks_en = cfg.status_en;
    sw_isr = aou_t1_sw_isr::type_id::create("sw_isr", this);
    sw_isr.enable = cfg.sw_isr_en;
    sw_isr.hold_on_deact = cfg.sw_hold_on_deact;
    sw_isr.drain_before_deact = cfg.sw_drain_before_deact;
    sw_isr.n_rp = cfg.n_rp;
    axi4pc = aou_t1_axi4pc_ctl::type_id::create("axi4pc", this);
    mo_chk = aou_t1_mo_chk::type_id::create("mo_chk", this);
    sw_rst_chk = aou_t1_sw_reset_chk::type_id::create("sw_rst_chk", this);
    lp_cfg_chk = aou_t1_lp_cfg_chk::type_id::create("lp_cfg_chk", this);
    force_chk = aou_t1_force_deact_chk::type_id::create("force_chk", this);
    dbg_chk = aou_t1_dbg_fifo_chk::type_id::create("dbg_chk", this);
    dbg_chk.cfg = cfg;
    crd_chk = aou_t1_crd_flow_chk::type_id::create("crd_chk", this);
    crd_chk.cfg = cfg;
    crd_rr = aou_t1_crd_rr_chk::type_id::create("crd_rr", this);
    crd_rr.n_rp = cfg.n_rp;
    crd_blk = aou_t1_crd_block_chk::type_id::create("crd_blk", this);
    crd_blk.cfg = cfg;
    wr_order = aou_t1_wr_order_chk::type_id::create("wr_order", this);
    rx_align = aou_t1_rx_align_chk::type_id::create("rx_align", this);
    early_tbl = aou_t1_early_tbl_chk::type_id::create("early_tbl", this);
    early_tbl.cfg = cfg;
    wdt_chk = aou_t1_wdt_chk::type_id::create("wdt_chk", this);
    wdt_chk.n_rp = cfg.n_rp;
    xfer_cov = aou_t1_xfer_cov::type_id::create("xfer_cov", this);
    if (cfg.attr_chk_en) begin
      attr_chk = aou_t1_attr_chk::type_id::create("attr_chk", this);
      attr_chk.cov = xfer_cov;
      attr_chk.l3_cfg = cfg.l3_cfg;
    end
    if (cfg.rx_fifo_chk_en) begin
      rx_fifo_chk = aou_t1_rx_fifo_chk::type_id::create("rx_fifo_chk", this);
      rx_fifo_chk.slack = cfg.rx_fifo_slack;
    end
    if (cfg.fdi_chk_en) begin
      fdi_chk = aou_fdi_chk_adapter::type_id::create("fdi_chk", this);
      fdi_chk.chk = cfg.l3_cfg.chk;
    end
    vseqr = aou_t1_vseqr::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (fdi[p]) begin
      if (cfg.fdi_cfg[p].is_active) cfg.lsm_cfg.rsp.push_back(fdi[p].rsp);
      fdi[p].mon.ap_tx.connect(bridge.l1_imp);
    end
    bridge.ap.connect(l3.rx_flit_imp);
    l3.ap_rx_msg.connect(rmgr.rx_imp);
    foreach (rmgr.drv[r]) begin
      rmgr.drv[r].clk_vif = s_mgr[0].cfg.vif;
      rmgr.drv[r].wreq_mode = cfg.remote_wreq;
    end
    apb = regs.apb;

    if (cfg.sb_en) begin
      foreach (s_mgr[r]) s_mgr[r].ap.connect(sb.local_mgr_imp);
      foreach (m_sub[r]) m_sub[r].ap.connect(sb.local_sub_imp);
      rmgr.ap.connect(sb.remote_imp);
    end
    sb.remote_mem = cfg.remote_cfg.mem;
    sb.local_mem = cfg.local_mem;

    vseqr.env = this;
    vseqr.s_mgr_sqr = new[cfg.n_rp];
    vseqr.r_mgr_sqr = new[cfg.n_rp];
    foreach (s_mgr[r]) vseqr.s_mgr_sqr[r] = s_mgr[r].sqr;
    foreach (rmgr.sqr[r]) vseqr.r_mgr_sqr[r] = rmgr.sqr[r];
    foreach (fdi[p]) vseqr.fdi_sqr[p] = fdi[p].sqr;
    vseqr.lsm_sqr = lsm.sqr;
    vseqr.l3_sqr = l3.sqr;
    vseqr.apb_sqr = regs.apb.sqr;
    vseqr.regs = regs.model;
    foreach (m_sub[r]) m_sub[r].ap.connect(dbg_chk.mport_imp);
    rmgr.ap.connect(dbg_chk.remote_imp);
    rmgr.req_ap.connect(dbg_chk.remote_req_imp);
    dbg_chk.rm = regs.model;
    dbg_chk.clk_vif = m_sub[0].cfg.vif;
    l3.ap_rx_msg.connect(crd_chk.rx_msg_imp);
    crd_chk.model = l3.model;
    crd_chk.rm = regs.model;
    crd_chk.lsm_vif = lsm_vif;
    crd_chk.s_vif = new[cfg.n_rp];
    crd_chk.m_vif = new[cfg.n_rp];
    foreach (s_mgr[r]) crd_chk.s_vif[r] = s_mgr[r].cfg.vif;
    foreach (m_sub[r]) crd_chk.m_vif[r] = m_sub[r].cfg.vif;
    foreach (fdi[p]) crd_chk.mb_vif[p] = fdi[p].vif;
    l3.ap_rx_msg.connect(crd_blk.rx_msg_imp);
    apb.mon.ap.connect(crd_blk.apb_imp);
    crd_blk.rm = regs.model;
    crd_chk.blk = crd_blk;
    l3.ap_rx_msg.connect(wr_order.rx_msg_imp);
    wr_order.model = l3.model;
    // After l3's own subscription, so the model has taken the header's credit.
    bridge.ap.connect(crd_rr.dut_flit_imp);
    crd_rr.crd = l3.model.crd;
    crd_rr.clk_vif = s_mgr[0].cfg.vif;
    fdi[cfg.lsm_cfg.active_phy].mon.ap_rx.connect(rx_align.rx_flit_imp);
    rx_align.mb_vif = fdi[cfg.lsm_cfg.active_phy].vif;
    l3.ap_tx_msg.connect(early_tbl.rem_msg_imp);
    early_tbl.rm = regs.model;
    wdt_chk.rm = regs.model;
    early_tbl.vif = new[cfg.n_rp];
    foreach (s_mgr[r]) early_tbl.vif[r] = s_mgr[r].cfg.vif;
    crd_chk.early = early_tbl;
    if (fdi_chk != null) fdi_chk.l3_cfg = cfg.l3_cfg;
    lsm.mon.ap.connect(axi4pc.lsm_imp);
    axi4pc.m_drv = new[cfg.n_rp];
    foreach (m_sub[r]) axi4pc.m_drv[r] = m_sub[r].drv;
    mo_chk.vif = new[cfg.n_rp];
    foreach (m_sub[r]) mo_chk.vif[r] = m_sub[r].cfg.vif;
    l3.ap_tx_msg.connect(mo_chk.rem_msg_imp);
    l3.ap_rx_msg.connect(mo_chk.dut_msg_imp);
    mo_chk.l3_cfg = cfg.l3_cfg;
    xfer_cov.s_vif = new[cfg.n_rp];
    xfer_cov.m_vif = new[cfg.n_rp];
    foreach (s_mgr[r]) xfer_cov.s_vif[r] = s_mgr[r].cfg.vif;
    foreach (m_sub[r]) xfer_cov.m_vif[r] = m_sub[r].cfg.vif;
    l3.ap_tx_msg.connect(xfer_cov.tb_fifo.analysis_export);
    for (int unsigned r = 0; r < cfg.n_rp && r < 4; r++) begin
      xfer_cov.dut_bytes[r] = cfg.rp_bytes[r];
      xfer_cov.rem_bytes[r] = cfg.remote_bytes_of(r);
    end
    foreach (s_mgr[r]) s_mgr[r].ap.connect(xfer_cov.req_fifo.analysis_export);
    foreach (m_sub[r]) m_sub[r].ap.connect(xfer_cov.sub_fifo.analysis_export);
    rmgr.ap.connect(xfer_cov.req_fifo.analysis_export);
    l4a.cov = xfer_cov;
    if (attr_chk != null) begin
      foreach (s_mgr[r]) s_mgr[r].ap.connect(attr_chk.loc_fifo.analysis_export);
      foreach (m_sub[r]) m_sub[r].ap.connect(attr_chk.sub_fifo.analysis_export);
      remote.ap.connect(attr_chk.far_fifo.analysis_export);
      rmgr.ap.connect(attr_chk.rmt_fifo.analysis_export);
      l3.ap_rx_msg.connect(attr_chk.dut_fifo.analysis_export);
    end
    sw_rst_chk.rst_vif = rst.vif;
    sw_rst_chk.m_vif = new[cfg.n_rp];
    foreach (m_sub[r]) sw_rst_chk.m_vif[r] = m_sub[r].cfg.vif;
    lp_cfg_chk.rm = regs.model;
    lp_cfg_chk.status = status;
    apb.mon.ap.connect(lp_cfg_chk.apb_imp);
    force_chk.apb_vif = apb.cfg.vif;
    force_chk.rst_vif = rst.vif;
    force_chk.lsm_vif = lsm_vif;
    force_chk.rm = regs.model;
    force_chk.status = status;
    force_chk.l3_cfg = cfg.l3_cfg;
    force_chk.cfg = cfg;
    foreach (fdi[p]) force_chk.mb_vif[p] = fdi[p].vif;
    l3.ap_rx_msg.connect(force_chk.dut_imp);
    rx_align.rst_vif = rst.vif;
    if (rx_fifo_chk != null) begin
      rx_fifo_chk.vif = new[cfg.n_rp];
      foreach (m_sub[r]) rx_fifo_chk.vif[r] = m_sub[r].cfg.vif;
      rx_fifo_chk.model = l3.model;
      rx_fifo_chk.status = status;
      rx_fifo_chk.rm = regs.model;
      l3.ap_rx_msg.connect(rx_fifo_chk.dut_imp);
    end
    sw_isr.status = status;
    status.model = l3.model;
    status.rm = regs.model;
    sw_isr.rm = regs.model;
    sw_isr.apb_sqr = regs.apb.sqr;
    sw_isr.mgr = new[cfg.n_rp];
    foreach (s_mgr[r]) sw_isr.mgr[r] = s_mgr[r].drv;
  endfunction

  task run_phase(uvm_phase phase);
    pump = aou_t1_l1_pump_seq::type_id::create("pump");
    pump.l3 = l3;
    pump.cancel_pct = cfg.l1_cancel_pct;
    pump.bubble_pct = cfg.l1_bubble_pct;
    pump.gap_pct = cfg.l1_gap_pct;
    pump.cancel_mix = cfg.l1_cancel_mix;
    pump.fdi = fdi[cfg.lsm_cfg.active_phy];
    status.pump = pump;
    fork
      pump.start(fdi[cfg.lsm_cfg.active_phy].sqr);
      forever begin
        rst.on_reset.wait_trigger();
        reset_flush(rst.last_which);
      end
    join_none
  endtask

  // Reset contract (docs/ARCHITECTURE.md): called on every reset the reset
  // agent drives and by the vseq once AOU_SW_RESET has put the core in reset,
  // both with bus_reset = 1: the local AXI agents are on the DUT's AXI-port
  // reset (I_RESETN and AOU_SW_RESET), so they drop their transactions and
  // restart idle with the core, as the SoC's AXI peers must (MAS 7.3.6).
  // bus_reset = 0 (abort_traffic): no reset at all, the agents keep every
  // handshake legal and only stop waiting for responses. I_PRESETN alone resets
  // only the APB side (integration guide 3.1.1): the core, the AoU link and every transaction
  // keep running, so only the local software's pending interrupt service is
  // cancelled. Otherwise the remote die (L3, its managers, the L1 pump) drops
  // everything with the link, and transactions the AXI managers (local and
  // remote) had outstanding end as aborted; the scoreboard counts them.
  virtual function void reset_flush(aou_t1_rst_e which = AOU_T1_RST_BOTH, bit bus_reset = 1'b1);
    aou_axi_txn aborted[$];
    `uvm_info(get_type_name(), $sformatf("reset: flushing the environment (%s, bus reset %0b)",
                                         which.name(), bus_reset), UVM_LOW)
    sw_isr.cancel();
    if (which == AOU_T1_RST_APB) return;
    sw_isr.hold_requests(1'b0);
    mo_chk.clear();
    status.reset_flush();
    lp_cfg_chk.reset_flush();
    force_chk.reset_flush();
    dbg_chk.reset_flush();
    crd_chk.reset_flush();
    crd_blk.reset_flush();
    wr_order.reset_flush();
    early_tbl.reset_flush();
    foreach (s_mgr[r]) begin
      s_mgr[r].drv.reset_flush(aborted, bus_reset);
      if (s_mgr[r].mon != null) s_mgr[r].mon.reset_flush(bus_reset);
    end
    foreach (m_sub[r]) begin
      if (bus_reset && m_sub[r].drv != null) m_sub[r].drv.reset_flush();
      if (m_sub[r].mon != null) m_sub[r].mon.reset_flush(bus_reset);
    end
    rmgr.reset_flush(aborted);
    l3.reset_flush();
    if (rx_fifo_chk != null) rx_fifo_chk.reset_flush();
    if (pump != null) pump.flush();
    foreach (cfg.fdi_cfg[p]) cfg.fdi_cfg[p].gate.epoch++;
    if (attr_chk != null) attr_chk.reset_flush();
    foreach (aborted[i]) sb.abort(aborted[i]);
    if (aborted.size() != 0)
      `uvm_info(get_type_name(), $sformatf("reset aborted %0d transactions", aborted.size()),
                UVM_LOW)
  endfunction

  // Brackets the APB write that requests AOU_SW_RESET (sw_reset()), from the
  // request to the core reset. The local managers' transactions on the bus in
  // the window are marked reset_outstanding: a write that completes before the
  // reset is lost or landed (the scoreboard allows either), a read may end with
  // SLVERR (MAS 7.3.6 says the reset loses it and defines no response; the
  // SLVERR is taken from the RTL). The rest are aborted by reset_flush() at the
  // core reset, as are the remote die's, which cannot complete with the link down.
  function void sw_reset_window(bit open);
    foreach (s_mgr[r]) if (s_mgr[r].mon != null) s_mgr[r].mon.sw_reset_window(open);
  endfunction

  // Ends every transaction the AXI managers (local and remote) have
  // outstanding as aborted, without any reset: for a test that gives up on
  // a DUT that stopped responding. Bursts already on the bus still finish.
  function void abort_traffic();
    aou_axi_txn aborted[$];
    foreach (s_mgr[r]) begin
      s_mgr[r].drv.reset_flush(aborted, 1'b0);
      if (s_mgr[r].mon != null) s_mgr[r].mon.reset_flush(1'b0);
    end
    rmgr.reset_flush(aborted);
    foreach (aborted[i]) sb.abort(aborted[i]);
    `uvm_info(get_type_name(), $sformatf("traffic stopped: %0d transactions aborted",
                                         aborted.size()), UVM_LOW)
  endfunction

  // Transactions still in flight anywhere in the env.
  function int unsigned outstanding(output string why);
    int unsigned n = 0;
    why = "";
    foreach (s_mgr[r]) begin
      int unsigned k = s_mgr[r].drv.outstanding();
      if (k != 0) why = {why, $sformatf(" s_mgr%0d=%0d", r, k)};
      n += k;
    end
    if (rmgr.outstanding() != 0) why = {why, $sformatf(" rmgr=%0d", rmgr.outstanding())};
    n += rmgr.outstanding();
    if (remote.outstanding() != 0) why = {why, $sformatf(" remote=%0d", remote.outstanding())};
    n += remote.outstanding();
    for (int r = 0; r < AOU_RP_MAX; r++) begin
      int unsigned k = l3.model.dut_wr_out[r] + l3.model.dut_rd_out[r];
      if (k != 0) why = {why, $sformatf(" l3_dut_req_rp%0d=%0d", r, k)};
      n += k;
    end
    if (l3.model.pk.queued_msgs() != 0)
      why = {why, $sformatf(" l3_tx_queue=%0d", l3.model.pk.queued_msgs())};
    n += l3.model.pk.queued_msgs();
    return n;
  endfunction
endclass
