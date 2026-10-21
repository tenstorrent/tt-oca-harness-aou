// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Write-transaction watchdog (plan 16.17-16.23; MAS software-operation 7.2.6):
// aou_wdt_vseq hangs writes until the watchdog expires, clears it, resets the
// device and hangs them again; the env's aou_t1_wdt_chk judges every step.
// The case is +wdt_case=expiry|near_miss|masked|multi_rp (default expiry).
// near_miss: AW handshakes restart the count just before the threshold
// (needs a threshold of at least 8); masked: INT_EARLY_WDT_MASK set, then
// cleared with the status set; multi_rp: every RP hangs (several RPs).
// The threshold is +wdt_thr=T core cycles (default 300; 0 is legal). The
// device reset (+wdt_reset=sw|hard: AOU_SW_RESET or I_RESETN), the RP that
// hangs (+wdt_rp=r, not with multi_rp) and EARLY_BRESP_EN on every RP
// (+early_en=0|1; the watchdog counts either way) are random per seed unless
// given. WDT_EN is set on every RP; only the RPs that hang have writes
// outstanding.
class aou_wdt_test extends aou_dp_base_test;
  `uvm_component_utils(aou_wdt_test)

  string       wdt_case = "expiry";
  int unsigned thr = 300;
  string       reset_kind;
  int unsigned rps;
  int unsigned early_en;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_wdt_vseq";
  endfunction

  function void set_knobs();
    int unsigned n = AOU_T1_RP_COUNT;
    int unsigned rp = $urandom_range(n - 1);
    int unsigned n_wr = $urandom_range(8, 1);
    reset_kind = ($urandom_range(1) == 1) ? "sw" : "hard";
    early_en = $urandom_range(1);
    void'($value$plusargs("wdt_case=%s", wdt_case));
    void'($value$plusargs("wdt_thr=%d", thr));
    void'($value$plusargs("wdt_reset=%s", reset_kind));
    void'($value$plusargs("wdt_rp=%d", rp));
    void'($value$plusargs("early_en=%d", early_en));
    if (!(wdt_case inside {"expiry", "near_miss", "masked", "multi_rp"}))
      `uvm_fatal(get_type_name(), {"unknown +wdt_case=", wdt_case})
    if (!(reset_kind inside {"sw", "hard"}))
      `uvm_fatal(get_type_name(), {"unknown +wdt_reset=", reset_kind})
    if (wdt_case == "near_miss" && thr < 8)
      `uvm_fatal(get_type_name(), "+wdt_case=near_miss needs +wdt_thr of at least 8")
    if (rp >= n) `uvm_fatal(get_type_name(), $sformatf("+wdt_rp=%0d: the build has %0d RPs", rp, n))
    if (wdt_case == "multi_rp") begin
      if (n < 2) `uvm_fatal(get_type_name(), "+wdt_case=multi_rp needs several RPs")
      rps = (1 << n) - 1;
    end else begin
      rps = 1 << rp;
    end
    if (wdt_case == "near_miss") n_wr = 1;
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    for (int unsigned r = 0; r < n; r++) begin
      k.feat.early_resp[r] = int'(early_en != 0);
      k.feat.wdt_en[r] = 1;
    end
    k.feat.wdt_threshold = int'(thr);
    if (wdt_case == "masked") k.feat.mask_early_wdt = 1;
    k.dir = AOU_T1_L2R;
    k.lens = '{0, 1, 3};
    k.wr_pct = 100;
    k.bufferable_pct = 50;
    k.n = n_wr;
    uvm_config_db#(string)::set(null, "*", "wdt_case", wdt_case);
    uvm_config_db#(int unsigned)::set(null, "*", "wdt_thr", thr);
    uvm_config_db#(string)::set(null, "*", "wdt_reset", reset_kind);
    uvm_config_db#(int unsigned)::set(null, "*", "wdt_rps", rps);
    uvm_config_db#(int unsigned)::set(null, "*", "wdt_n_wr", n_wr);
  endfunction

  function void configure_test();
    // The hung writes' responses wait in parallel, not one after another.
    cfg.l3_cfg.resp_fork = 1'b1;
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    // TB gap: the scoreboard compares remote memory when B arrives, which an
    // early B precedes; the end-of-test memory comparison still applies.
    if (early_en != 0) env.expects.add("AXI-S02", 0, 100000);
  endfunction
endclass
