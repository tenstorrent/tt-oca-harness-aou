// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One coverpoint or cross of an aou_fc_group. A coverpoint's bins are value
// ranges; a sample lands in the first bin that holds it, or counts as outside
// (a value the covergroup does not bin). A cross bin is one combination of its
// coverpoints' bins, numbered in mixed radix with the last coverpoint fastest.
//
// A bin is a target (KIND_BIN), ignored (KIND_IGNORE: a combination that can't
// mean what it says; not written to fc.json) or illegal (KIND_ILLEGAL: out of
// the denominator, written with its hits). An illegal bin that names a rule is
// itself the check and reports a hit under that rule; one without a rule is
// checked elsewhere. A cross cell over an ignored or illegal coverpoint bin is
// ignored. spec tags a bin with the spec revision it needs ("v0.8"); tagged
// bins stay targets, and reports show them separately.
class aou_fc_point;
  localparam byte KIND_BIN     = 0;
  localparam byte KIND_IGNORE  = 1;
  localparam byte KIND_ILLEGAL = 2;

  string           name;
  string           group_name;
  bit              is_cross;
  string           bin_name[$];
  int              lo[$];
  int              hi[$];
  byte             kind[$];
  string           spec[$];
  string           rule[$];
  int unsigned     comp[$];       // cross: coverpoint indices in the group
  int unsigned     hits[$];
  longint unsigned outside;
  int              cur = -1;      // bin of the latest sample, -1 when outside

  function new(string point_name, bit cross_point = 1'b0, string grp = "");
    name = point_name;
    is_cross = cross_point;
    group_name = grp;
  endfunction

  function void bin(string n, int l, int h, byte k = KIND_BIN, string r = "");
    foreach (lo[i]) begin
      if (l <= hi[i] && h >= lo[i])
        `uvm_error("aou_fc_point", $sformatf("%s: bin %s overlaps bin %s", name, n, bin_name[i]))
    end
    bin_name.push_back(n);
    lo.push_back(l);
    hi.push_back(h);
    kind.push_back(k);
    spec.push_back("");
    rule.push_back(r);
    hits.push_back(0);
  endfunction

  // n[l] .. n[h], one bin per value, as SV names the bins of `bins n[]`.
  function void vals(string n, int l, int h);
    for (int v = l; v <= h; v++) bin($sformatf("%s[%0d]", n, v), v, v);
  endfunction

  function int unsigned num_bins();
    return hits.size();
  endfunction

  // Sets the kind (and rule) of every bin matching pat; fatal when none does.
  // pat has one glob per coverpoint of a cross, comma-separated; a glob has
  // '|'-separated alternatives, each of which may use '*'.
  function void mark(string pat, byte k, string r = "");
    int unsigned n = 0;
    foreach (bin_name[b]) begin
      if (match_bin(pat, bin_name[b])) begin
        kind[b] = k;
        rule[b] = r;
        n++;
      end
    end
    if (n == 0)
      `uvm_fatal("aou_fc_point", $sformatf("%s.%s: no bin matches %s", group_name, name, pat))
  endfunction

  function void tag(string pat, string s);
    int unsigned n = 0;
    foreach (bin_name[b]) begin
      if (match_bin(pat, bin_name[b])) begin
        spec[b] = s;
        n++;
      end
    end
    if (n == 0)
      `uvm_fatal("aou_fc_point", $sformatf("%s.%s: no bin matches %s", group_name, name, pat))
  endfunction

  static function bit match_bin(string pat, string bn);
    string pf[$];
    string bf[$];
    split(pat, ",", pf);
    split(bn, ",", bf);
    if (pf.size() != bf.size()) return 1'b0;
    foreach (pf[i]) begin
      string alts[$];
      bit any = 1'b0;
      split(pf[i], "|", alts);
      foreach (alts[a]) if (glob(alts[a], bf[i])) any = 1'b1;
      if (!any) return 1'b0;
    end
    return 1'b1;
  endfunction

  static function void split(string s, string sep, ref string out[$]);
    string w = "";
    out.delete();
    for (int i = 0; i <= s.len(); i++) begin
      if (i == s.len() || s.substr(i, i) == sep) begin
        out.push_back(w);
        w = "";
      end else begin
        w = {w, s.substr(i, i)};
      end
    end
  endfunction

  // '*' matches any run of characters; everything else matches itself.
  static function bit glob(string p, string s);
    int pi = 0;
    int si = 0;
    int star = -1;
    int resume = 0;
    while (si < s.len()) begin
      if (pi < p.len() && p.substr(pi, pi) == "*") begin
        star = pi;
        pi = pi + 1;
        resume = si;
      end else if (pi < p.len() && p.substr(pi, pi) == s.substr(si, si)) begin
        pi = pi + 1;
        si = si + 1;
      end else if (star >= 0) begin
        pi = star + 1;
        resume = resume + 1;
        si = resume;
      end else begin
        return 1'b0;
      end
    end
    while (pi < p.len() && p.substr(pi, pi) == "*") pi = pi + 1;
    return pi == p.len();
  endfunction

  function void hit(int unsigned b);
    hits[b]++;
    if (kind[b] == KIND_ILLEGAL && rule[b] != "")
      `uvm_error("aou_fc_point", $sformatf("%s: illegal coverage bin %s.%s %s hit", rule[b],
                                           group_name, name, bin_name[b]))
  endfunction

  function void sample(int v);
    cur = -1;
    foreach (lo[i]) begin
      if (v >= lo[i] && v <= hi[i]) begin
        cur = i;
        break;
      end
    end
    if (cur < 0) outside++;
    else hit(cur);
  endfunction

  // Cross bins are created when the cross is declared, after its coverpoints.
  function void make_cross(aou_fc_point cps[$]);
    int unsigned n = 1;
    foreach (comp[k]) n *= cps[comp[k]].num_bins();
    for (int unsigned b = 0; b < n; b++) begin
      bin_name.push_back(cross_name(cps, b));
      kind.push_back(cross_excluded(cps, b) ? KIND_IGNORE : KIND_BIN);
      spec.push_back("");
      rule.push_back("");
      hits.push_back(0);
    end
  endfunction

  function bit cross_excluded(aou_fc_point cps[$], int unsigned b);
    for (int k = comp.size() - 1; k >= 0; k--) begin
      aou_fc_point p = cps[comp[k]];
      if (p.kind[b % p.num_bins()] != KIND_BIN) return 1'b1;
      b /= p.num_bins();
    end
    return 1'b0;
  endfunction

  function string cross_name(aou_fc_point cps[$], int unsigned b);
    string s = "";
    for (int k = comp.size() - 1; k >= 0; k--) begin
      aou_fc_point p = cps[comp[k]];
      s = (k == comp.size() - 1) ? p.bin_name[b % p.num_bins()]
                                 : {p.bin_name[b % p.num_bins()], ",", s};
      b /= p.num_bins();
    end
    return s;
  endfunction

  function void sample_cross(aou_fc_point cps[$]);
    int unsigned b = 0;
    foreach (comp[k]) begin
      if (cps[comp[k]].cur < 0) begin
        cur = -1;
        outside++;
        return;
      end
      b = b * cps[comp[k]].num_bins() + cps[comp[k]].cur;
    end
    cur = b;
    hit(b);
  endfunction
endclass
