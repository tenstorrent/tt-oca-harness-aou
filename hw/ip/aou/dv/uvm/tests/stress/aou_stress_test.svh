// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Random traffic in both directions on every RP under stimulus a real remote
// die would not produce (plan 7.16, with 6.3/6.9 for the layouts). Plusargs:
//   +st_pol=dut|sparse|min|max|random|split   L3 packer policy (split: every
//            message longer than 1-7 granules crosses the flit boundary)
//   +st_crd=dut|hdr|grant|mixed|slow          credit return to the DUT: header
//            MsgCredit only, CrdtGrant only, both mixed per flit, or the
//            request and response classes returned 4-32 flits after consume
//   +st_bp=none|aw|w|ar|b|r|all|fdi           back-pressure extreme: long
//            random stalls on one AXI channel at both ends (W and R per beat),
//            on all of them, or on the FDI (bursty pl_trdy, gaps and bubbles
//            in the flits to the DUT); none runs every channel at full rate
//   +st_stall_max=N                           longest AXI stall, in cycles
//            (default 300); over 1000 holds a ready or valid low for longer
//            than the DUT's own pipelines ever wait
//   +st_require_m_b_stall=1                   require an observed M-side B
//            stall, AXI-R03 checking and a completed release without abort
class aou_stress_test extends aou_dp_base_test;
  `uvm_component_utils(aou_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.lens = '{0, 1, 3, 7, 15, 31};
    k.strb = aou_dp_knobs::DP_STRB_MIXED;
    k.wr_pct = 50;
    k.num_slots = 32;
    k.n = 96;
  endfunction

  static int unsigned stall_max = 300;

  function void check_phase(uvm_phase phase);
    bit observed = 1'b0;
    int unsigned require_stall = 0;
    string why;
    super.check_phase(phase);
    void'($value$plusargs("st_require_m_b_stall=%d", require_stall));
    if (require_stall == 0) return;
    foreach (env.m_sub[r]) begin
      aou_axi_monitor mon = env.m_sub[r].mon;
      `uvm_info(get_type_name(), $sformatf(
          {"M_B_STALL rp=%0d entries=%0d cycles=%0d sustained=%0d releases=%0d ",
           "checks=%0d handshakes=%0d aborts=%0d"},
          r, mon.n_b_stall_entries, mon.n_b_stall_cycles, mon.n_b_stall_sustained,
          mon.n_b_stall_releases,
          mon.n_b_stability_checks, mon.n_b_handshakes, mon.n_b_observation_aborts), UVM_LOW)
      if (mon.cfg.checks_en && mon.n_b_stall_entries > 0 && mon.n_b_stall_sustained > 0 &&
          mon.n_b_qualified_releases > 0 && mon.n_b_stability_checks > 0 &&
          mon.n_b_handshakes > 0 && mon.n_b_observation_aborts == 0 && mon.n_aborted == 0)
        observed = 1'b1;
    end
    if (!observed || env.outstanding(why) != 0)
      `uvm_error(get_type_name(),
                 "M_B_STALL_NOT_REACHED: no checked, released M-side B stall or drain")
  endfunction

  static function void stall(aou_axi_delay d);
    d.set_bursty(0, 0, 15, 40, stall_max);
  endfunction

  function void configure_test();
    string pol = "dut";
    string crd = "dut";
    string bp = "none";
    aou_l3_cfg l3 = cfg.l3_cfg;
    void'($value$plusargs("st_pol=%s", pol));
    void'($value$plusargs("st_crd=%s", crd));
    void'($value$plusargs("st_bp=%s", bp));
    void'($value$plusargs("st_stall_max=%d", stall_max));
    if (stall_max < 40)
      `uvm_fatal(get_type_name(), $sformatf("+st_stall_max=%0d is below 40", stall_max))
    case (pol)
      "sparse": l3.pol.set_sparse();
      "min":    l3.pol.set_min_density();
      "max":    l3.pol.set_max_density();
      "random": l3.pol.set_random();
      "split":  l3.pol.split_at = $urandom_range(7, 1);
      "dut":    l3.pol.set_dut_like();
      default: `uvm_fatal(get_type_name(), {"bad +st_pol=", pol})
    endcase
    case (crd)
      "hdr":   l3.pol.cred_method = AOU_CRM_HDR;
      "grant": l3.pol.cred_method = AOU_CRM_GRANT;
      "mixed": l3.pol.cred_method = AOU_CRM_MIXED;
      "slow": begin
        // WDATA stays returned on receipt (aou_t1_env_cfg: L3 needs a whole
        // burst before it consumes any of it); the delay counts flits.
        foreach (l3.ret_policy[c]) if (c != AOU_CC_WDATA) l3.ret_policy[c] = AOU_RET_DELAYED;
        l3.ret_delay = $urandom_range(32, 4);
      end
      "dut": ;
      default: `uvm_fatal(get_type_name(), {"bad +st_crd=", crd})
    endcase
    // Every channel at full rate, then stalls only where asked.
    cfg.remote_lat_max = 0;
    foreach (cfg.s_mgr_cfg[r]) begin
      aou_axi_timing m = cfg.s_mgr_cfg[r].timing;
      aou_axi_timing s = cfg.m_sub_cfg[r].timing;
      m.apply(AOU_AXI_TIMING_ZERO);
      s.apply(AOU_AXI_TIMING_ZERO);
      if (bp inside {"aw", "all"}) begin stall(m.aw_valid); stall(s.aw_ready); end
      if (bp inside {"w", "all"})  begin stall(m.w_valid);  stall(s.w_ready);  end
      if (bp inside {"ar", "all"}) begin stall(m.ar_valid); stall(s.ar_ready); end
      if (bp inside {"b", "all"})  begin stall(m.b_ready);  stall(s.b_lat);    end
      if (bp inside {"r", "all"})  begin stall(m.r_ready);  stall(s.r_beat); stall(s.r_lat); end
    end
    if (bp inside {"b", "r", "all"}) cfg.remote_lat_max = stall_max;
    if (bp == "fdi") begin
      foreach (cfg.fdi_cfg[p]) begin
        cfg.fdi_cfg[p].trdy_policy = AOU_TRDY_BURSTY;
        cfg.fdi_cfg[p].burst_max = 64;
      end
      cfg.l1_gap_pct = 50;
      cfg.l1_bubble_pct = 30;
    end
    if (!(bp inside {"none", "aw", "w", "ar", "b", "r", "all", "fdi"}))
      `uvm_fatal(get_type_name(), {"bad +st_bp=", bp})
    `uvm_info(get_type_name(), $sformatf("pol=%s crd=%s bp=%s: %s", pol, crd, bp,
                                         l3.convert2string()), UVM_LOW)
  endfunction
endclass
