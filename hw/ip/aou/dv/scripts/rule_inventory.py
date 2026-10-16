#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Checker inventory: AoU and FDI rules -> primary checker -> evidence.

Reads checkers/rules.csv (rule, checker, secondary, scope, description,
reference) and the rule ledger every T1 run prints at its end
("RULE-LEDGER <rule> <checker> checks=<n> fires=<n>", checkers/aou_rule_log.svh)
from the runs under out/. For each rule of the two normative lists (AOU-R1..R45,
the AoU spec's checkable rules; FDI-R01..R41, the UCIe r1.1 FDI handshake rules)
it reports the primary checker, the test that exercises it most, and the
evidence: fires in a passing negative test (the test expected them), in an
escape run (a re-introduced DUT bug), and checks in passing runs.

A checker named "via AOU-Rn" reports under that rule's ID; its evidence is that
rule's. Scope DUT: the rule binds the DUT; MODEL: it binds our model of the partner
(remote die or Adapter: self-checked, or held by construction); N/A: the DUT's interface cannot
exercise it (the reason is in the description).

Writes docs/checker_inventory.md (or -o) and prints the summary counts.
"""

import argparse
import csv
import glob
import os
import re
import sys
from collections import defaultdict

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = re.compile(r"RULE-LEDGER (\S+) (\S+) checks=(\d+) fires=(\d+)")
NORMATIVE = [f"AOU-R{i}" for i in range(1, 46)] + [f"FDI-R{i:02d}" for i in range(1, 42)]


def load_rules(path):
    with open(path, encoding="utf-8") as fh:
        return {r["rule"]: r for r in csv.DictReader(fh)}


def verdict_of(run):
    p = os.path.join(run, "verdict.txt")
    if not os.path.exists(p):
        return "unjudged"
    with open(p, encoding="utf-8", errors="replace") as fh:
        first = fh.readline().strip()
    return first.split(":")[0].split()[0] if first else "unjudged"


def scan(out_dir):
    """{(rule, checker): {"checks": n, "fires": [(test, n, verdict, build)], ...}}"""
    led = defaultdict(lambda: {"checks": 0, "check_tests": defaultdict(int), "fires": []})
    nruns = 0
    for run in sorted(glob.glob(os.path.join(out_dir, "*", "*.rid.*"))):
        log = os.path.join(run, "sim.log")
        if not os.path.exists(log):
            continue
        build = os.path.basename(os.path.dirname(run))
        test = os.path.basename(run).split(".rid.")[0]
        verdict = verdict_of(run)
        escape = "-esc-" in build
        lines = []
        with open(log, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                m = LEDGER.search(ln)
                if m:
                    lines.append(m.groups())
        if not lines:
            continue
        nruns += 1
        for rule, who, checks, fires in lines:
            e = led[(rule, who)]
            checks, fires = int(checks), int(fires)
            # Hits count on the DUT only (T1 builds); unit benches check our models.
            if verdict in ("PASS", "XFAIL") and not escape and "-t1-" in build:
                e["checks"] += checks
                e["check_tests"][test] += checks
            if fires:
                kind = "escape" if escape else ("negative" if verdict in ("PASS", "XFAIL")
                                                else "failing")
                e["fires"].append((test, fires, kind, build))
    return led, nruns


def primary_of(row):
    """(class name or None, via-rule or None, kind) of the checker column."""
    c = (row.get("checker") or "").strip()
    m = re.match(r"via (\S+)", c)
    if m:
        return None, m.group(1), "via"
    if c.startswith("by construction"):
        return c, None, "construction"
    if c.startswith("n/a") or c.startswith("not checked") or not c:
        return None, None, "none"
    if any(sep in c for sep in (";", "/", ",")):
        return c, None, "multiple"
    return c, None, "checker"


def evidence(led, rule, who):
    e = led.get((rule, who))
    if e is None:
        return 0, [], ""
    top = max(e["check_tests"].items(), key=lambda kv: kv[1])[0] if e["check_tests"] else ""
    return e["checks"], e["fires"], top


def fmt_fires(fires):
    best = {}
    for test, n, kind, build in fires:
        k = (kind, test)
        best[k] = best.get(k, 0) + n
    order = {"negative": 0, "escape": 1, "failing": 2}
    parts = [f"{kind}: {test} ({n})" for (kind, test), n in
             sorted(best.items(), key=lambda kv: (order[kv[0][0]], -kv[1]))[:3]]
    return "; ".join(parts)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rules", default=os.path.join(UVM_ROOT, "uvm", "env", "checkers", "rules.csv"))
    ap.add_argument("--out-dir", default=os.path.join(UVM_ROOT, "out"))
    ap.add_argument("-o", "--output", default=os.path.join(UVM_ROOT, "docs", "checker_inventory.md"))
    args = ap.parse_args()

    rules = load_rules(args.rules)
    led, nruns = scan(args.out_dir)
    missing_rows = [r for r in NORMATIVE if r not in rules]
    if missing_rows:
        print("rules.csv lacks normative rules: " + " ".join(missing_rows), file=sys.stderr)
        return 1

    rows, counts = [], defaultdict(list)
    for rule in NORMATIVE:
        row = rules[rule]
        scope = (row.get("scope") or "").strip()
        who, via, kind = primary_of(row)
        ev_rule, ev_who = rule, who
        if kind == "via":
            vrow = rules.get(via, {})
            ev_rule, ev_who = via, primary_of(vrow)[0]
        checks, fires, top = evidence(led, ev_rule, ev_who) if ev_who else (0, [], "")
        good_fire = [f for f in fires if f[2] in ("negative", "escape")]
        if scope == "N/A":
            status = "n/a"
        elif kind == "none":
            status = "missing"
        elif kind == "multiple":
            status = "duplicated"
        elif kind == "construction":
            status = "by construction"
        elif checks == 0 and not fires:
            status = "never runs"
        elif good_fire:
            status = "fired"
        else:
            status = "hit"
        if scope != "N/A" and kind in ("checker", "via") and not good_fire:
            counts["never fired"].append(rule)
        counts[status].append(rule)
        if scope != "N/A" and kind in ("checker", "via"):
            counts["one primary"].append(rule)
        prim = row.get("checker", "")
        rows.append((rule, scope, row.get("description", ""), prim, row.get("secondary", ""),
                     top, checks, fmt_fires(fires), status))

    total = len(NORMATIVE)
    applicable = [r for r in NORMATIVE if (rules[r].get("scope") or "") != "N/A"]
    lines = [
        "<!--", "SPDX-License-Identifier: Apache-2.0",
        "SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc", "-->", "",
        "# Checker inventory", "",
        "Generated by `scripts/rule_inventory.py` (`make rule_inventory`) from "
        "`checkers/rules.csv` and the rule ledgers of the runs under `out/`; edit the CSV, "
        "not this file. The normative lists are the AoU specification's 45 checkable rules "
        "(v0.7 is the default; rules that exist only in v0.8 are marked) and the 41 FDI "
        "handshake rules of UCIe r1.1 chapter 8. Rule texts are summaries; the reference "
        "column of the CSV gives the section.", "",
        "Scope: **DUT** rules bind the DUT and are checked on its outputs. **MODEL** rules "
        "bind the partner the testbench models (the Adapter or the remote die, our L1/L2/L3 "
        "models): they are self-checked or held by construction. **N/A** rules cannot be exercised through this DUT's interface. A "
        "checker written `via AOU-Rn` reports under that rule's ID.", "",
        "Evidence: *checks* counts the rule's evaluations by its primary checker in "
        "passing clean T1 runs (hits on the DUT); *fired* lists runs where it reported a "
        "violation: a *negative* test that expected it (injection, including the L3 unit "
        "bench), an *escape* run (a re-introduced main bug or an RTL mutation, "
        "`make escape`) or a *failing* run. Status *fired* means fired in a negative, "
        "escape or mutation run; *hit* means only evaluated in passing runs.", "",
        f"Runs with a ledger: {nruns}.", "",
        "## Summary", "",
        "| | Rules |", "|---|---|",
        f"| Normative rules | {total} (AoU 45, FDI 41) |",
        f"| Applicable (DUT or MODEL) | {len(applicable)} |",
        f"| N/A for this DUT | {len(counts['n/a'])} |",
        f"| Exactly one primary checker | {len(counts['one primary'])} |",
        f"| Held by construction (model side) | {len(counts['by construction'])} |",
        f"| Missing a checker | {len(counts['missing'])} {' '.join(counts['missing'])} |",
        f"| Two or more primary checkers | {len(counts['duplicated'])} "
        f"{' '.join(counts['duplicated'])} |",
        f"| Checker never runs | {len(counts['never runs'])} {' '.join(counts['never runs'])} |",
        f"| Fired in a negative test, escape or mutation run | {len(counts['fired'])} |",
        f"| Hit in passing runs only (never fired) | {len(counts['hit'])} "
        f"{' '.join(counts['hit'])} |",
        f"| Primary never fired (hit-only plus never-runs) | {len(counts['never fired'])} |",
        "",
        "## Rules", "",
        "| Rule | Scope | Rule (summary) | Primary checker | Secondary | Exercised by | Checks | "
        "Fired | Status |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append("| " + " | ".join(str(x).replace("|", "/") for x in r) + " |")
    extra = sorted((k for k in rules if k.startswith(("AOU-", "FDI-")) and k not in NORMATIVE),
                   key=lambda s: (s.split("-")[0], s))
    if extra:
        lines += ["", "## Additional AoU/FDI rules", "",
                  "Rules the testbench checks beyond the two normative lists.", "",
                  "| Rule | Checker | Rule (summary) | Checks | Fired |", "|---|---|---|---|---|"]
        for k in extra:
            who, _, _ = primary_of(rules[k])
            checks, fires, _ = evidence(led, k, who) if who else (0, [], "")
            lines.append(f"| {k} | {rules[k]['checker']} | {rules[k]['description']} | {checks} | "
                         f"{fmt_fires(fires)} |")
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    quiet = ("one primary", "fired", "n/a", "by construction")
    for k in ("one primary", "by construction", "n/a", "missing", "duplicated", "never runs",
              "fired", "hit", "never fired"):
        print(f"{k:16} {len(counts[k]):3} {'' if k in quiet else ' '.join(counts[k])}")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
