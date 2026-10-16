// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Performance gate (plan 10.x): judges every bandwidth window aou_perf_mon
// measures against the d2d_model targets committed in aou_perf_targets, per
// link (l2r: DUT TX, r2l: DUT RX), keyed "<CONFIG>|<active PHY>|<scenario>|
// <window>|<link>". Passive: it only reads the monitor's results.
// T1-P02: the link's steady-state delivered bytes/cycle is at least
//   (1 - tol) x model (tol 0.03 unless uvm/env/perf/perf_overrides.yaml says
//   otherwise). A link that carried data with no target, or a target whose
//   link carried none, fails as NO_TARGET.
// T1-P03: ABOVE_MAX: the link is not above max(model, mix_cap) + one flit of
//   bytes over the steady-state cycles. mix_cap is the model's saturated
//   packing of the messages the link actually carried in the steady state:
//   when the other link runs short, or one kind of transaction runs ahead of
//   the other by up to the outstanding depth, a link can carry more than the
//   model's rate for the window's pattern, but never more than its own
//   messages fit in. Above the bound means the model or the measurement is
//   wrong: confirm the measurement, then fix the model (or the DUT sends
//   messages smaller than the spec's).
// T1-P04: every data-path message type crossed the link, over the whole
//   window, in the model's share: |count - share x total| <= max(1, 0.2% of
//   total). A mismatch means the model was fed the wrong traffic (split
//   length, strobes, widths), or the DUT sends other messages than the spec's.
// Efficiency and FDI duty are diagnostics in perf.json, not gated.
class aou_perf_chk extends uvm_component;
  `uvm_component_utils(aou_perf_chk)

  uvm_analysis_imp #(aou_perf_result, aou_perf_chk) imp;

  aou_t1_env_cfg cfg;
  string         config_name;
  real           mix_rel = 0.002;
  int unsigned   n_links;
  int unsigned   n_fail;

  protected string msg_names[12] = '{"ReadReq", "WriteReq", "WriteResp", "ReadData256",
                                     "ReadData512", "ReadData1024", "WriteData256",
                                     "WriteData512", "WriteData1024", "WriteDataFull256",
                                     "WriteDataFull512", "WriteDataFull1024"};

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("aou_config=%s", config_name));
  endfunction

  static function bit data_path(string k);
    return (k.len() > 4 && k.substr(0, 3) == "Read") || (k.len() > 5 && k.substr(0, 4) == "Write");
  endfunction

  function void write(aou_perf_result r);
    for (int l = 0; l < 2; l++) judge(r, l);
  endfunction

  protected function void judge(aou_perf_result r, int l);
    string dn = (l == 0) ? "l2r" : "r2l";
    string k = aou_perf_targets::key(config_name, cfg.lsm_cfg.active_phy, r.scenario,
                                     r.win_name, dn);
    real   m;
    real   lo;
    real   hi;
    real   ratio;
    string verdict = "PASS";
    if (!aou_perf_targets::has(k)) begin
      if (!r.data[l]) return;
      n_links++;
      n_fail++;
      `uvm_error(get_type_name(), $sformatf({"T1-P02: NO_TARGET %s: link measured %0.3f B/cycle; ",
                                             "aou_perf_targets (d2d_model %s) has no target"},
                                            k, r.bpc[l], aou_perf_targets::model_hash))
      return;
    end
    n_links++;
    m = aou_perf_targets::model[k];
    if (!r.data[l]) begin
      n_fail++;
      `uvm_error(get_type_name(), $sformatf({"T1-P02: NO_TARGET %s: no data on the link, ",
                                             "model %0.3f"}, k, m))
      return;
    end
    ratio = r.bpc[l] / m;
    lo = (1.0 - aou_perf_targets::tol[k]) * m;
    hi = ((r.mix_cap[l] > m) ? r.mix_cap[l] : m) +
         real'(aou_perf_targets::eps_bytes[k]) / r.cycles[l];
    if (!r.ss_ok[l])
      `uvm_error(get_type_name(), $sformatf({"T1-P01: %s: steady state of %0d flits is below the ",
                                             "minimum; the window is too short to judge"},
                                            k, r.flits[l]))
    if (r.bpc[l] < lo) begin
      verdict = "BELOW";
      `uvm_error(get_type_name(), $sformatf({"T1-P02: %s below target: %0.3f B/cycle, ",
                                             "model %0.3f, ratio %0.4f < %0.3f"}, k, r.bpc[l], m,
                                            ratio,
                                            1.0 - aou_perf_targets::tol[k]))
    end
    if (r.bpc[l] > hi) begin
      verdict = "ABOVE";
      `uvm_error(get_type_name(), $sformatf({"T1-P03: ABOVE_MAX %s: %0.3f B/cycle, model %0.3f, ",
                                             "bound %0.3f (ratio %0.4f)"}, k, r.bpc[l], m, hi,
                                            ratio))
    end
    if (!mix_ok(r, l, k)) verdict = {verdict, "+MIX"};
    if (verdict != "PASS") n_fail++;
    `uvm_info(get_type_name(), $sformatf("PERF_GATE %s measured %0.3f model %0.3f ratio %0.4f %s",
                                         k, r.bpc[l], m, ratio, verdict), UVM_LOW)
  endfunction

  // T1-P04 over the whole window's messages on link l.
  protected function bit mix_ok(aou_perf_result r, int l, string k);
    int unsigned n[string];
    int unsigned tot = 0;
    real         lim;
    string       bad = "";
    foreach (msg_names[i]) n[msg_names[i]] = r.msgs(l, msg_names[i]);
    if (l == 0) begin
      foreach (r.msgs_l2r[x]) if (data_path(x)) n[x] = r.msgs_l2r[x];
    end else begin
      foreach (r.msgs_r2l[x]) if (data_path(x)) n[x] = r.msgs_r2l[x];
    end
    foreach (n[x]) tot += n[x];
    lim = real'(tot) * mix_rel;
    if (lim < 1.0) lim = 1.0;
    foreach (n[x]) begin
      real e = aou_perf_targets::mix_of(k, x) * real'(tot);
      real d = real'(n[x]) - e;
      if (d > lim || -d > lim) bad = {bad, $sformatf(" %s %0d (model %0.1f)", x, n[x], e)};
    end
    if (bad == "") return 1'b1;
    `uvm_error(get_type_name(), $sformatf({"T1-P04: %s message mix differs from the model ",
                                           "(of %0d):%s"}, k, tot, bad))
    return 1'b0;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("PERF_GATE %0d links judged, %0d failed (d2d_model %s)",
                                         n_links, n_fail, aou_perf_targets::model_hash), UVM_LOW)
  endfunction
endclass
