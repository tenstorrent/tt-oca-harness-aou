// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Static per-rule, per-checker counters (see aou_rule_pkg). who is the
// checker's class name, so a rule's primary and secondary checkers are
// counted apart.
class aou_rule_log;
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

  // "RULE-LEDGER <rule> <checker> checks=<n> fires=<n>", one line per key.
  static function void lines(ref string q[$]);
    q.delete();
    foreach (checks[k]) begin
      q.push_back($sformatf("RULE-LEDGER %s checks=%0d fires=%0d", k, checks[k],
                            fires.exists(k) ? fires[k] : 0));
    end
  endfunction
endclass
