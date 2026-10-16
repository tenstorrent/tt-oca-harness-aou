// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Performance (plan 2.10): aou_perf_vseq's windows (+perf_scn=S1..S5, or
// +perf_mode=lat|bw|drain) measured by aou_perf_mon into perf.txt and
// perf.json (docs/PERF_JSON.md) in the run directory. aou_perf_chk gates every
// bandwidth window against the committed d2d_model targets (T1-P02..P04); the
// latency and drain windows are report only. The scoreboard still checks every
// byte. aou_perf_seq replaces the random traffic with each window's exact
// pattern. scripts/perf_report.py tabulates the runs.
// The env knobs a seed would otherwise pick and that change the traffic shape
// are fixed, so every seed and simulator measures the same bench:
// +perf_r_interleave=0|1 (local subordinates interleave R beats across IDs,
// default 0), +perf_w_before_aw=0|1 (default 1), +perf_resp_fork=0|1 (remote
// responder serves requests concurrently, default 0).
// The remote die sends every full-strobe write beat as WriteDataFull
// (+perf_remote_full_pct=<pct>, default 100), as the DUT does.
// Managers keep +perf_slots outstanding (default 32): with the drivers'
// default 16 the remote die's reads could not cover their round trip when
// both sides read, and the bench, not the DUT, set the rate.
// The remote die advertises enough credit that it is never the limit (the
// DUT's counters hold 2048 per class); +perf_l3_depth=env keeps the env's
// smaller defaults.
class aou_perf_test extends aou_dp_base_test;
  `uvm_component_utils(aou_perf_test)

  aou_perf_mon mon;
  aou_perf_chk chk;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_perf_vseq";
  endfunction

  function void set_knobs();
    k.dir = AOU_T1_BOTH_DIRS;
    k.n = 32;
  endfunction

  function void configure_test();
    string mode;
    // Drain mode runs local reads only.
    if ($value$plusargs("perf_mode=%s", mode) && mode == "drain") min_r2l = 0;
    // One-sided bandwidth windows (+perf_dir).
    if ($value$plusargs("perf_dir=%s", mode)) begin
      if (mode == "l2r") min_r2l = 0;
      if (mode == "r2l") min_l2r = 0;
    end
    // Steady state only: no L1 cancels, bubbles or gaps on the flits to the DUT.
    cfg.l1_cancel_pct = 0;
    cfg.l1_bubble_pct = 0;
    cfg.l1_gap_pct = 0;
    foreach (cfg.fdi_cfg[p]) cfg.fdi_cfg[p].trdy_policy = AOU_TRDY_ALWAYS;
    // Long windows (768 KB per link at the slowest link) must not trip the
    // traffic watchdog.
    cfg.drain_timeout = 2000000;
    pin_knobs();
    outstanding();
    deep_credits();
  endfunction

  function void pin_knobs();
    int v;
    bit ilv = 1'b0;
    bit wfirst = 1'b1;
    bit fork_rsp = 1'b0;
    if ($value$plusargs("perf_r_interleave=%d", v)) ilv = (v != 0);
    if ($value$plusargs("perf_w_before_aw=%d", v)) wfirst = (v != 0);
    if ($value$plusargs("perf_resp_fork=%d", v)) fork_rsp = (v != 0);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      cfg.m_sub_cfg[r].r_interleave_en = ilv;
      cfg.s_mgr_cfg[r].w_before_aw_en = wfirst;
    end
    cfg.l3_cfg.resp_fork = fork_rsp;
  endfunction

  // Every manager keeps +perf_slots (default 32, the DUT's S_*_MO_CNT)
  // transactions outstanding each way; aou_perf_vseq gives its sequences as
  // many address slots.
  function void outstanding();
    int unsigned n = 32;
    void'($value$plusargs("perf_slots=%d", n));
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      cfg.s_mgr_cfg[r].max_wr_outstanding = n;
      cfg.s_mgr_cfg[r].max_rd_outstanding = n;
      cfg.r_mgr_cfg[r].max_wr_outstanding = n;
      cfg.r_mgr_cfg[r].max_rd_outstanding = n;
    end
  endfunction

  function void deep_credits();
    string s;
    if ($value$plusargs("perf_l3_depth=%s", s) && s == "env") return;
    cfg.l3_cfg.rx_depth = '{512, 512, 2048, 2048, 512};
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    aou_axi_rand_seq::type_id::set_type_override(aou_perf_seq::get_type());
    mon = aou_perf_mon::type_id::create("mon", this);
    chk = aou_perf_chk::type_id::create("chk", this);
    chk.cfg = cfg;
    mon.beat_bytes = cfg.fdi_cfg[cfg.lsm_cfg.active_phy].beat_bytes;
    mon.cfg = cfg;
    void'($value$plusargs("perf_mode=%s", mon.perf_mode));
    uvm_config_db#(aou_perf_mon)::set(null, "*", "perf_mon", mon);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.l3 = env.l3;
    mon.vif = env.lsm_vif;
    mon.regs = env.regs.model;
    void'($value$plusargs("perf_remote_full_pct=%d", mon.remote_full_pct));
    foreach (env.rmgr.drv[r]) env.rmgr.drv[r].full_pct = mon.remote_full_pct;
    foreach (env.s_mgr[r]) env.s_mgr[r].ap.connect(mon.loc_fifo.analysis_export);
    env.rmgr.ap.connect(mon.rem_fifo.analysis_export);
    env.l3.ap_rx_msg.connect(mon.dut_fifo.analysis_export);
    env.l3.ap_tx_msg.connect(mon.tb_fifo.analysis_export);
    mon.res_ap.connect(chk.imp);
  endfunction
endclass
