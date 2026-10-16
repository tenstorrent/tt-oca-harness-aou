// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Rule ledger (checkers/rules.csv, docs/checker_inventory.md): every checker
// counts each evaluation of a rule (check) and each violation it finds
// (fire), whether or not a test expected it. At the end of a test the counts
// are printed as "RULE-LEDGER <rule> checks=<n> fires=<n>" lines, which
// scripts/rule_inventory.py collects, so a checker that never runs shows up.
package aou_rule_pkg;

  `include "aou_rule_log.svh"

endpackage
