// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The model's rule ledger. Every checker of the model counts each evaluation of
// a rule (check) and each violation it finds (fire), whether or not a test
// expected it, keyed by rule ID and the checker instance, so a rule that is
// never evaluated shows up and two links (or a passive monitor beside an
// active one) keep their own counts. lines() returns one
// "RULE-LEDGER <rule> <checker class> checks=<n> fires=<n> at=<instance>" line
// per key; a bench prints them at the end of a test next to its own ledger,
// if it keeps one.
class ucie_rule_log;
  static int unsigned checks[string];
  static int unsigned fires[string];

  static function string key(string rule, uvm_component who);
    return {rule, " ", who.get_type_name(), " ", who.get_full_name()};
  endfunction

  static function void check(string rule, uvm_component who, int unsigned n = 1);
    string k;
    if (n == 0) return;
    k = key(rule, who);
    if (checks.exists(k)) checks[k] += n;
    else checks[k] = n;
  endfunction

  static function void fire(string rule, uvm_component who);
    string k = key(rule, who);
    if (fires.exists(k)) fires[k]++;
    else fires[k] = 1;
    if (!checks.exists(k)) checks[k] = 1;
  endfunction

  static function void clear();
    checks.delete();
    fires.delete();
  endfunction

  static function void lines(ref string q[$]);
    q.delete();
    foreach (checks[k]) begin
      string rule, cls, inst;
      int unsigned a = 0, b;
      while (k[a] != " ") a++;
      b = a + 1;
      while (k[b] != " ") b++;
      rule = k.substr(0, a - 1);
      cls = k.substr(a + 1, b - 1);
      inst = k.substr(b + 1, k.len() - 1);
      q.push_back($sformatf("RULE-LEDGER %s %s checks=%0d fires=%0d at=%s", rule, cls, checks[k],
                            fires.exists(k) ? fires[k] : 0, inst));
    end
  endfunction
endclass
