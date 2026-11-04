// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The model's rule ledger. Every checker of the model counts each evaluation of
// a rule (check) and each violation it finds (fire), whether or not a test
// expected it, keyed by rule ID and the checker's class name, so a rule that
// is never evaluated shows up. lines() returns one
// "RULE-LEDGER <rule> <checker> checks=<n> fires=<n>" line per key; a bench
// prints them at the end of a test next to its own ledger, if it keeps one.
class ucie_rule_log;
  static int unsigned checks[string];
  static int unsigned fires[string];

  static function string key(string rule, string who);
    return {rule, " ", who};
  endfunction

  static function void check(string rule, string who, int unsigned n = 1);
    string k = key(rule, who);
    if (n == 0) return;
    if (checks.exists(k)) checks[k] += n;
    else checks[k] = n;
  endfunction

  static function void fire(string rule, string who);
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
      q.push_back($sformatf("RULE-LEDGER %s checks=%0d fires=%0d", k, checks[k],
                            fires.exists(k) ? fires[k] : 0));
    end
  endfunction
endclass
