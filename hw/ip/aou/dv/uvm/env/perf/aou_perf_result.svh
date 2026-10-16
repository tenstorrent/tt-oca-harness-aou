// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// What aou_perf_mon measured in one window, per link (index 0: l2r, the DUT's
// TX; 1: r2l, its RX), for aou_perf_chk. bpc and cycles are the gated
// steady-state figures (the whole window's when there is no steady state);
// mix_cap is what the link could carry, saturated, with the messages it
// actually carried in the steady state (aou_perf_mon::mix_cap); msgs counts
// every message that crossed the link while the window was open.
class aou_perf_result extends uvm_object;
  `uvm_object_utils(aou_perf_result)

  string       win_name;
  string       scenario;
  string       traffic_dir;
  bit          data[2];        // the link carried application data
  real         bpc[2];
  real         cycles[2];
  bit          ss_ok[2];
  int unsigned flits[2];
  real         mix_cap[2];
  int unsigned msgs_l2r[string];
  int unsigned msgs_r2l[string];

  function new(string name = "aou_perf_result");
    super.new(name);
  endfunction

  function int unsigned msgs(int l, string k);
    if (l == 0) return msgs_l2r.exists(k) ? msgs_l2r[k] : 0;
    return msgs_r2l.exists(k) ? msgs_r2l[k] : 0;
  endfunction

  function void count(int l, string k);
    if (l == 0) msgs_l2r[k] = msgs(0, k) + 1;
    else msgs_r2l[k] = msgs(1, k) + 1;
  endfunction
endclass
