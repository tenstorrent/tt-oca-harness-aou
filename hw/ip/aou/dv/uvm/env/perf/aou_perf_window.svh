// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One performance window of docs/perf_scenarios.yaml on one CONFIG, as the
// generated aou_perf_windows table lists it for aou_perf_vseq. weight[r] is
// the number of transactions RP r issues per period of the pattern on each
// issuing side; the sequence issues a whole number of periods.
class aou_perf_window extends uvm_object;
  `uvm_object_utils(aou_perf_window)

  string       config_name;
  string       scenario;
  string       win_name;
  string       dir;           // l2r, r2l or both: which sides issue
  int unsigned wr_pct;
  int unsigned beats;         // burst length; AxSIZE narrows to keep a burst within 4 KB
  int unsigned bytes;         // fixed transfer size instead of beats (0: none)
  int unsigned offset;        // start address modulo 4 KB
  bit          partial;       // every write beat partly strobed (WriteData)
  int unsigned weight[4];

  function new(string name = "aou_perf_window");
    super.new(name);
  endfunction

  function void init(string c, string scn, string wn, string d, int wp, int nb, int by,
                     int off, bit part, int unsigned wt[4]);
    config_name = c;
    scenario = scn;
    win_name = wn;
    dir = d;
    wr_pct = wp;
    beats = nb;
    bytes = by;
    offset = off;
    partial = part;
    weight = wt;
  endfunction

  // AxSIZE in bytes of this window's bursts on a bus of width bytes.
  function int unsigned axsize(int unsigned width);
    int unsigned s = width;
    while (beats * s > 4096 && s > 1) s /= 2;
    return s;
  endfunction

  function string convert2string();
    return $sformatf("%s %s/%s %s wr=%0d%% beats=%0d%s weights=%p", config_name, scenario, win_name,
                     dir, wr_pct, beats, partial ? " partial" : "", weight);
  endfunction
endclass
