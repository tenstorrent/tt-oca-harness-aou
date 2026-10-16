// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of the T1 tests, on the shared library's ocah_test: builds aou_t1_env
// from cfg (configure() adjusts it), runs the virtual sequence named by
// vseq_type (+T1_VSEQ=<type> overrides) on env.vseqr through start_seq(),
// then checks the end of test: scoreboard drained and checked something,
// expectations met (the registry), no unexpected interrupts (the status
// watcher), AOU_FDI_CHECKER clean (its adapter). A scenario test overrides
// create_scenario_seq() instead and runs it through run_single_scenario()
// (aou_sanity_test) or inherits ocah_test's looped run_phase; the library's
// hooks name env.vseqr as the scenario sequencer and hand the sequence the
// env handle. ocah_test's report_phase prints the UVM TEST PASSED/FAILED
// banner from the global error counts.
// Plusargs: +T1_TXN=<n> transactions per RP and direction; +remote_bytes=N or
// N0,N1,.. the remote die's AXI data bytes (all RPs, or per RP); +active_phy=P
// the PHY the remote die uses in two-PHY builds (default: random per seed);
// +trdy=always|random|bursty|holes, +trdy_pct=N, +hole_pct=N, +burst_max=N the
// Adapter's pl_trdy policy on every PHY (aou_fdi_cfg), over what the test sets;
// the L1 stall and cancel knobs of aou_t1_env_cfg::l1_plusargs().
// +remote_rp_count=N the remote die's RP count (default: the DUT's);
// +rx_fifo_slack=N messages aou_t1_rx_fifo_chk allows past an RX FIFO.
class aou_base_test extends ocah_test;
  `uvm_component_utils(aou_base_test)

  aou_t1_env     env;
  aou_t1_env_cfg cfg;
  string         vseq_type = "aou_base_test_seq";
  int unsigned   num_txns = 100;
  // Minimum checked transactions per direction; 0 skips the check.
  int unsigned   min_l2r = 1;
  int unsigned   min_r2l = 1;

  function new(string name = "aou_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // ocah_test hooks: every scenario pass starts on the T1 virtual sequencer
  // with the env handle set (the sequence's pre_body takes cfg from it).
  virtual function uvm_sequencer_base scenario_sequencer();
    return env.vseqr;
  endfunction

  virtual function void plumb_scenario_seq(ocah_sequence seq);
    aou_base_test_seq vseq;
    if (!$cast(vseq, seq))
      `uvm_fatal(get_type_name(), {"not an aou_base_test_seq: ", seq.get_type_name()})
    vseq.env = env;
    vseq.num_txns = num_txns;
  endfunction

  // The link comes up inside the virtual sequences (link_up()), so the
  // library's bring-up hook has nothing to do here.
  virtual task bring_up();
  endtask

  function void build_phase(uvm_phase phase);
    string rb;
    super.build_phase(phase);
    cfg = aou_t1_env_cfg::type_id::create("cfg");
    cfg.randomize_knobs();
    void'($value$plusargs("T1_TXN=%d", num_txns));
    void'($value$plusargs("T1_VSEQ=%s", vseq_type));
    void'($value$plusargs("sw_drain=%d", cfg.sw_drain_before_deact));
    void'($value$plusargs("l3_cm0_deact=%d", cfg.l3_cm0_deact));
    void'($value$plusargs("remote_rp_count=%d", cfg.remote_rp_count));
    void'($value$plusargs("rx_fifo_slack=%d", cfg.rx_fifo_slack));
    // AOU_FDI_CHECKER knows only the DUT's RP_COUNT and would report the credits
    // a larger remote die advertises for its own extra RPs (BUGS/018).
    if (cfg.remote_rp_count > cfg.n_rp) cfg.fdi_chk_en = 1'b0;
    if ($value$plusargs("remote_bytes=%s", rb)) cfg.set_remote_bytes(rb);
    cfg.l1_plusargs();
    if (AOU_T1_N_PHY > 1) begin
      cfg.lsm_cfg.active_phy = $urandom_range(AOU_T1_N_PHY - 1);
      void'($value$plusargs("active_phy=%d", cfg.lsm_cfg.active_phy));
    end
    configure();
    trdy_knobs();
    env = aou_t1_env::type_id::create("env", this);
    env.cfg = cfg;
    uvm_top.set_timeout(20ms, 1);
  endfunction

  // Hook for tests: change cfg here.
  virtual function void configure();
  endfunction

  function void trdy_knobs();
    string pol;
    int unsigned v;
    foreach (cfg.fdi_cfg[p]) begin
      if ($value$plusargs("trdy=%s", pol)) begin
        case (pol)
          "always": cfg.fdi_cfg[p].trdy_policy = aou_fdi_pkg::AOU_TRDY_ALWAYS;
          "random": cfg.fdi_cfg[p].trdy_policy = aou_fdi_pkg::AOU_TRDY_RANDOM;
          "bursty": cfg.fdi_cfg[p].trdy_policy = aou_fdi_pkg::AOU_TRDY_BURSTY;
          "holes":  cfg.fdi_cfg[p].trdy_policy = aou_fdi_pkg::AOU_TRDY_HOLES;
          default: `uvm_fatal(get_type_name(), {"+trdy=", pol, ": not always|random|bursty|holes"})
        endcase
      end
      if ($value$plusargs("trdy_pct=%d", v)) cfg.fdi_cfg[p].trdy_pct = v;
      if ($value$plusargs("hole_pct=%d", v)) cfg.fdi_cfg[p].hole_pct = v;
      if ($value$plusargs("burst_max=%d", v)) cfg.fdi_cfg[p].burst_max = v;
    end
  endfunction

  task run_phase(uvm_phase phase);
    uvm_object obj;
    aou_base_test_seq vseq;
    phase.raise_objection(this);
    obj = uvm_factory::get().create_object_by_name(vseq_type, get_full_name(), "vseq");
    if (!$cast(vseq, obj)) `uvm_fatal(get_type_name(), {"not an aou_base_test_seq: ", vseq_type})
    `uvm_info(get_type_name(), {"running ", vseq_type}, UVM_LOW)
    start_seq(vseq);
    repeat (100) @(env.lsm_vif.mon_cb);
    check_cred_return();
    phase.drop_objection(this);
  endtask

  // AOU-R31 (credits are sent in ENABLED): with nothing outstanding anywhere,
  // every credit the DUT advertised must come back.
  task check_cred_return();
    string why;
    int unsigned n = 0;
    aou_l3_model m = env.l3.model;
    if (!m.cred_return_ready() || env.outstanding(why) != 0) return;
    while (n < cfg.l3_cfg.cred_return_cycles && m.crd.tx_short(why) != 0) begin
      @(env.lsm_vif.mon_cb);
      n++;
    end
    m.check_cred_return(n);
  endtask

  // A fatal (usually the phase time-out) prints where traffic stands.
  function void pre_abort();
    string why;
    void'(env.outstanding(why));
    `uvm_info(get_type_name(), $sformatf({"abort: outstanding:%s; sb l2r %0d/%0d r2l %0d/%0d; ",
              "l3 %s tx %0d flits rx %0d flits; rmgr %0d; remote wr/rd %0d/%0d; s_mgr0 mon ",
              "wr/rd %0d/%0d; m_sub0 mon wr/rd %0d/%0d"}, why, env.sb.n_l2r_wr, env.sb.n_l2r_rd,
              env.sb.n_r2l_wr, env.sb.n_r2l_rd, env.l3.model.lnk.state.name(),
              env.l3.model.tx_flits, env.l3.model.rx_flits, env.rmgr.outstanding(),
              env.remote.n_wr, env.remote.n_rd, env.s_mgr[0].mon.n_wr, env.s_mgr[0].mon.n_rd,
              env.m_sub[0].mon.n_wr, env.m_sub[0].mon.n_rd), UVM_NONE)
    env.l3.report_phase(null);
  endfunction

  function void check_phase(uvm_phase phase);
    string why;
    super.check_phase(phase);
    aou_rule_log::check("T1-T01", "aou_base_test");
    if (env.outstanding(why) != 0) begin
      aou_rule_log::fire("T1-T01", "aou_base_test");
      `uvm_error(get_type_name(), {"T1-T01: not drained:", why})
    end
    if (cfg.sb_en && env.sb.n_l2r_wr + env.sb.n_l2r_rd < min_l2r)
      `uvm_error(get_type_name(), $sformatf("T1-T02: scoreboard checked %0d local->remote txns",
                                            env.sb.n_l2r_wr + env.sb.n_l2r_rd))
    if (cfg.sb_en && env.sb.n_r2l_wr + env.sb.n_r2l_rd < min_r2l)
      `uvm_error(get_type_name(), $sformatf("T1-T03: scoreboard checked %0d remote->local txns",
                                            env.sb.n_r2l_wr + env.sb.n_r2l_rd))
  endfunction

  // The rule ledger (checkers/aou_rule_log.svh) for scripts/rule_inventory.py.
  function void report_phase(uvm_phase phase);
    string q[$];
    super.report_phase(phase);
    aou_rule_log::lines(q);
    foreach (q[i]) `uvm_info(get_type_name(), q[i], UVM_NONE)
  endfunction
endclass
