// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Performance windows (plan 2.10) for aou_perf_mon, with no added delay in
// any local agent or the remote model. Stimulus only: aou_perf_chk judges the
// bandwidth windows against uvm/env/perf/aou_perf_targets.svh.
//   +perf_scn=<S1..S5>  the windows of that scenario on this CONFIG
//          (docs/perf_scenarios.yaml, generated into aou_perf_windows): per RP
//          and issuing side a whole number of periods of the window's pattern,
//          sized so every link with data carries at least +perf_kb=<KB>
//          (default 768) of payload, or +perf_n=<n> periods. aou_perf_seq pins
//          every shape choice (10.1-10.3, 10.8, 10.10-10.13; credit return
//          delay 10.6 over the whole run).
//   +perf_mode:
//   lat    one transaction in flight at a time on RP0: writes, then reads, each
//          way (10.4, 10.5, 10.9; round trip split at FDI)
//   bw     S1's both-sides windows bw_wr, bw_rd, bw_mix; with +perf_dir=l2r|r2l
//          S1's one-sided windows of that side instead.
//   drain  the remote die advertises no ReadReq credit; local reads queue in
//          the DUT; then one grant per RP releases them (10.7)
// +perf_slots=<n> sets the transactions each manager keeps outstanding
// (default 32; see aou_perf_test).
class aou_perf_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_perf_vseq)

  aou_perf_mon mon;
  string       mode = "bw";
  string       scn;

  function new(string name = "aou_perf_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    if (!uvm_config_db#(aou_perf_mon)::get(null, "*", "perf_mon", mon))
      `uvm_fatal(get_type_name(), "no perf_mon in config_db")
    void'($value$plusargs("perf_mode=%s", mode));
    if ($value$plusargs("perf_scn=%s", scn)) mode = "scn";
  endtask

  function void full_rate();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      cfg.s_mgr_cfg[r].timing.apply(AOU_AXI_TIMING_ZERO);
      cfg.m_sub_cfg[r].timing.apply(AOU_AXI_TIMING_ZERO);
    end
    cfg.remote_cfg.timing.b_lat.set_zero();
    cfg.remote_cfg.timing.r_lat.set_zero();
  endfunction

  function aou_t1_traffic_cfg prof(int wr_pct, int unsigned slots, bit [3:0] m);
    aou_t1_traffic_cfg p = make_profile();
    p.wr_pct = wr_pct;
    p.num_slots = slots;
    p.rp_mask = m;
    return p;
  endfunction

  // A window starts from an idle DUT whose credits have all come back.
  task window(string name, aou_t1_dir_e dir, int unsigned n, aou_t1_traffic_cfg p,
              bit one = 1'b0, string scenario = "");
    string dn = (dir == AOU_T1_L2R) ? "l2r" : (dir == AOU_T1_R2L) ? "r2l" : "both";
    drain();
    wait_cycles(200);
    mon.open(name, one, scenario, dn, p.wr_pct);
    traffic(dir, n, p);
    mon.close();
  endtask

  // Periods of window w's pattern: +perf_n, or enough that every link that
  // carries data gets at least +perf_kb of it.
  function int unsigned periods(aou_perf_window w);
    int unsigned n;
    int unsigned kb = 768;
    longint      link[2] = '{0, 0};   // data bytes per period: [0] l2r, [1] r2l
    longint      lo = 0;
    bit          loc = (w.dir != "r2l");
    bit          rem = (w.dir != "l2r");
    if ($value$plusargs("perf_n=%d", n)) return n;
    void'($value$plusargs("perf_kb=%d", kb));
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      longint lb = longint'(w.beats) * w.axsize(cfg.rp_bytes[r]);
      longint rb = longint'(w.beats) * w.axsize(cfg.remote_bytes_of(r));
      longint wn = longint'(w.weight[r]) * longint'(w.wr_pct);
      longint rn = longint'(w.weight[r]) * (longint'(100) - longint'(w.wr_pct));
      if (w.bytes != 0) begin
        lb = longint'(w.bytes);
        rb = longint'(w.bytes);
      end
      if (loc) begin
        link[0] += wn * lb;
        link[1] += rn * lb;
      end
      if (rem) begin
        link[1] += wn * rb;
        link[0] += rn * rb;
      end
    end
    foreach (link[l]) if (link[l] > 0 && (lo == 0 || link[l] < lo)) lo = link[l];
    if (lo == 0) `uvm_fatal(get_type_name(), {"window with no data: ", w.convert2string()})
    // link[] is in hundredths of a period's bytes (wr_pct)
    return int'((longint'(kb) * 1024 * 100 + lo - 1) / lo);
  endfunction

  // One scenario window: every RP with weight issues its share at once, each
  // side as the window's direction says.
  task scn_window(aou_perf_window w, int unsigned slots);
    aou_t1_dir_e d = (w.dir == "l2r") ? AOU_T1_L2R :
                     (w.dir == "r2l") ? AOU_T1_R2L : AOU_T1_BOTH_DIRS;
    int unsigned m = periods(w);
    if (w.bytes != 0)
      `uvm_fatal(get_type_name(), {"fixed-size windows not supported: ", w.win_name})
    k.lens = '{w.beats - 1};
    k.strb = w.partial ? aou_dp_knobs::DP_STRB_PARTIAL : aou_dp_knobs::DP_STRB_FULL;
    `uvm_info(get_type_name(), $sformatf("window %s x%0d periods", w.convert2string(), m),
              UVM_LOW)
    drain();
    wait_cycles(200);
    mon.open(w.win_name, 1'b0, w.scenario, w.dir, int'(w.wr_pct));
    for (int unsigned r = 0; r < cfg.n_rp; r++)
      if (w.weight[r] != 0) traffic_nb(d, m * w.weight[r], prof(w.wr_pct, slots, 4'(1 << r)));
    wait_traffic();
    mon.close();
  endtask

  // The windows of scenario s on this CONFIG whose names end in suffix ("": all).
  task run_scenario(string s, int unsigned slots, string suffix = "");
    aou_perf_window q[$];
    string c = "";
    int    n = 0;
    void'($value$plusargs("aou_config=%s", c));
    aou_perf_windows::of(c, s, q);
    foreach (q[i]) begin
      string wn = q[i].win_name;
      if (suffix != "" && (wn.len() < suffix.len() ||
                           wn.substr(wn.len() - suffix.len(), wn.len() - 1) != suffix)) continue;
      scn_window(q[i], slots);
      n++;
    end
    if (n == 0) `uvm_fatal(get_type_name(), $sformatf("no %s window for CONFIG '%s'", s, c))
  endtask

  task body();
    int unsigned slots = 32;
    string       pd = "both";
    void'($value$plusargs("perf_slots=%d", slots));
    // Remote ReadReq credit is withheld from activation in drain mode.
    if (mode == "drain") begin
      link_up();
      cfg.l3_cfg.rx_depth[AOU_CC_RREQ] = 0;
      env.l3.model.crd.reset_link();
    end else begin
      link_up();
    end
    activate(AOU_T1_BY_APB, AOU_T1_ORDER_RANDOM);
    full_rate();
    k.full_size = 1'b1;
    k.align = aou_dp_knobs::DP_ALIGN_ALIGNED;
    k.strb = aou_dp_knobs::DP_STRB_FULL;
    k.ids = aou_dp_knobs::DP_ID_UNIQUE;
    mon.writefull = 1'b1;
    case (mode)
      "lat": begin
        k.lens = '{0};
        window("lat_wr", AOU_T1_L2R, num_txns, prof(100, 1, 4'h1), 1'b1, "lat");
        window("lat_rd", AOU_T1_L2R, num_txns, prof(0, 1, 4'h1), 1'b1, "lat");
        window("lat_wr_r2l", AOU_T1_R2L, num_txns, prof(100, 1, 4'h1), 1'b1, "lat");
        window("lat_rd_r2l", AOU_T1_R2L, num_txns, prof(0, 1, 4'h1), 1'b1, "lat");
      end
      "scn": run_scenario(scn, slots);
      "bw": begin
        void'($value$plusargs("perf_dir=%s", pd));
        // S1's both-sides windows are the ones without a direction suffix.
        if (pd == "both") begin
          run_scenario("S1", slots, "bw_wr");
          run_scenario("S1", slots, "bw_rd");
          run_scenario("S1", slots, "bw_mix");
        end else begin
          run_scenario("S1", slots, {"_", pd});
        end
      end
      "drain": begin
        aou_l3_overgrant_seq g = aou_l3_overgrant_seq::type_id::create("g");
        k.lens = '{0};
        mon.open("drain", 1'b0, "drain", "l2r", 0);
        traffic_nb(AOU_T1_L2R, 16, prof(0, 16, 4'hF));
        wait_cycles(2000);
        if (n_traffic == 0)
          `uvm_error(get_type_name(), "T1-P01: reads completed with no ReadReq credit")
        mon.grant_at($time);
        g.cls = AOU_CC_RREQ;
        g.n = 16;
        for (int unsigned r = 0; r < cfg.n_rp; r++) begin
          g.rp = 2'(r);
          g.start(p_sequencer.l3_sqr);
        end
        wait_traffic();
        mon.close();
        mon.drain_report();
      end
      default: `uvm_fatal(get_type_name(), {"unknown +perf_mode=", mode})
    endcase
    drain();
  endtask
endclass
