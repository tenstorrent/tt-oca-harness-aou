// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Early write response (plan 16.1-16.10, 16.13-16.15, 16.17; old F3, F8).
// +early_en=0|1|per_rp programs EARLY_BRESP_EN on every RP before activation
// (per_rp: a random setting per RP, at least one on and one off, 16.15); local writes are
// bufferable with +dp_buf_pct probability; +dp_ids=same interleaves bufferable
// and non-bufferable writes on one ID. aou_early_bresp_chk checks that only
// bufferable writes with the feature on get B before the remote completion.
// +early_err=1 adds two rounds of a bufferable write the remote die answers
// with SLVERR, then DECERR: the early OKAY stands, INT_EARLY_RESP_ERR rises and
// WRITE_EARLY_RESPONSE_RP0 captures ID and type until W1C (16.4-16.7).
// +early_full=1 (16.11/16.12): every write bufferable and single-beat, the
// remote die answers each one +early_lat cycles (default 2000) after it, so
// the early table fills to its WR_MO_CNT (32) entries and drains as the
// actual B responses arrive; the env's aou_t1_early_tbl_chk checks the AW
// stall and its release (FEAT-R15/R16), the vseq WRITE_RESP_DONE once drained.
// +early_over=1 with +early_full=1 (16.17): the env's early-table checker also
// reports INT_EARLY_WDT_ERR while an AW waits at the limit (FEAT-R21 is not
// checked: O_PENDING_CNT_OVER, BUGS/005, was removed by PR #89 for the watchdog).
// +early_toggle=1 (16.14): two traffic phases; between them, with every write
// done and WRITE_RESP_DONE = 1 on every RP (MAS 3.7.8), each RP's
// EARLY_BRESP_EN is inverted, and the second phase must follow the new setting.
// Writes only, so no read races a write that was answered early.
class aou_early_bresp_test extends aou_dp_base_test;
  `uvm_component_utils(aou_early_bresp_test)

  aou_early_bresp_chk chk;
  bit                 early_en[4] = '{1, 1, 1, 1};
  int unsigned        err_rounds;
  int                 early_full;
  int                 early_over;
  int                 early_toggle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_early_bresp_vseq";
  endfunction

  function bit all_on();
    for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) if (!early_en[r]) return 1'b0;
    return 1'b1;
  endfunction

  function void set_knobs();
    int v;
    string s;
    if ($value$plusargs("early_en=%s", s)) begin
      if (s == "per_rp") begin
        int unsigned on = $urandom_range(AOU_T1_RP_COUNT - 1);
        if (AOU_T1_RP_COUNT < 2) `uvm_fatal(get_type_name(), "+early_en=per_rp needs several RPs")
        foreach (early_en[r]) early_en[r] = 1'($urandom_range(1));
        early_en[on] = 1'b1;
        early_en[(on + 1) % AOU_T1_RP_COUNT] = 1'b0;
      end else begin
        foreach (early_en[r]) early_en[r] = s.atoi() != 0;
      end
    end
    if ($value$plusargs("early_err=%d", v) && v != 0) err_rounds = 2;
    if (err_rounds > 0 && !all_on()) `uvm_fatal(get_type_name(), "+early_err needs +early_en=1")
    void'($value$plusargs("early_toggle=%d", early_toggle));
    void'($value$plusargs("early_over=%d", early_over));
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) k.feat.early_resp[r] = int'(early_en[r]);
    k.dir = AOU_T1_L2R;
    k.lens = '{0, 1, 3, 7};
    k.wr_pct = 100;
    k.bufferable_pct = 50;
    k.n = 64;
    void'($value$plusargs("early_full=%d", early_full));
    if (early_toggle != 0) begin
      if (early_full != 0 || err_rounds > 0)
        `uvm_fatal(get_type_name(), "+early_toggle excludes +early_full and +early_err")
      k.phases = 2;
      k.n = 32;
    end
    if (early_over != 0 && early_full == 0)
      `uvm_fatal(get_type_name(), "+early_over needs +early_full=1")
    if (early_full != 0) begin
      if (!all_on()) `uvm_fatal(get_type_name(), "+early_full needs +early_en=1")
      k.lens = '{0};
      k.bufferable_pct = 100;
      k.n = 96;
    end
    uvm_config_db#(int unsigned)::set(null, "*", "early_err_rounds", err_rounds);
    uvm_config_db#(int)::set(null, "*", "early_full", early_full);
    uvm_config_db#(int)::set(null, "*", "early_toggle", early_toggle);
  endfunction

  function void configure_test();
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named(k.profile);
    // Remote write latency only fills the table if the responses overlap.
    if (early_full != 0) cfg.l3_cfg.resp_fork = 1'b1;
    for (int unsigned i = 0; i < err_rounds; i++)
      for (int unsigned r = 0; r < cfg.n_rp; r++) begin
        bit [63:0] lo = aou_early_bresp_vseq::ERR_BASE + 64'(i) * 64'h1000 + 64'(r) * p.rp_stride;
        cfg.remote_cfg.mem.add_error_region(lo, lo + 64'hFFF, aou_early_bresp_vseq::resp(i));
      end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_early_bresp_chk::type_id::create("chk", this);
    chk.early_en = early_en;
    chk.n_rp = AOU_T1_RP_COUNT;
    uvm_config_db#(aou_early_bresp_chk)::set(null, "*", "early_chk", chk);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (env.s_mgr[r]) env.s_mgr[r].ap.connect(chk.s_fifo.analysis_export);
    env.remote.ap.connect(chk.remote_fifo.analysis_export);
    env.early_tbl.over_chk = (early_over != 0);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    int unsigned n_err = err_rounds * cfg.n_rp;
    bit any_on = 1'b0;
    super.end_of_elaboration_phase(phase);
    // Some RP answers early in some phase (a toggle turns every RP on in one).
    for (int unsigned r = 0; r < cfg.n_rp; r++) any_on |= early_en[r] || early_toggle != 0;
    if (any_on) begin
      // The early OKAY replaces the remote error the scoreboard expects.
      if (n_err > 0) env.expects.add("AXI-S01", n_err, n_err);
      // TB gap: the scoreboard compares remote memory when B arrives, which an
      // early B precedes; the end-of-test memory comparison still applies.
      env.expects.add("AXI-S02", 0, 100000);
    end
    if (n_err > 0) env.expects.add("INT_EARLY_RESP_ERR", err_rounds, n_err);
  endfunction
endclass
