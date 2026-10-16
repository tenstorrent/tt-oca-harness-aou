#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Compare two sets of results.csv files: did any run get worse?

Each side is a directory tree (or explicit CSV files) holding results*.csv as
scripts/run_list.py and scripts/judge_run.py write them. A run is identified by
(test, plusargs, TB, CONFIG, seed), where TB and CONFIG come from the CSV's
build directory name <sim>-<tb>-<config>[-assert] (--sim-agnostic drops the
simulator from the key; by default a simulator compares with itself). Plusargs
are compared as a set of tokens, so their order does not matter.

Degradations (exit status 1 when there is one):
  PASS -> XFAIL/FAIL/missing, XFAIL -> FAIL/missing, and a run that is on the
  baseline side only (dropped) or that no longer finished with a verdict.
Reported separately, not degradations:
  XPASS notes appearing or disappearing, XFAIL -> PASS (a bug may be fixed, or
  a check went missing: review), FAIL -> PASS/XFAIL (fixed), and runs that are
  on the after side only (new).

Usage:
  compare_results.py BASELINE AFTER [-o report.md] [--sim-agnostic]
  compare_results.py --baseline b/results_g1a.csv --after a/results_g1a.csv
"""

import argparse
import csv
import os
import re
import sys
from collections import Counter

BUILD_RE = re.compile(r"^(?P<sim>[a-z]+)-(?P<tb>t1|reg|l3_unit|axi_selftest)(?:-(?P<config>.+))?$")
RANK = {"PASS": 0, "XFAIL": 1, "FAIL": 2}


def find_csvs(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for root, dirs, files in os.walk(p):
            dirs.sort()
            for name in sorted(files):
                if re.fullmatch(r"results(_.*)?\.csv", name):
                    yield os.path.join(root, name)


def build_of(csv_path):
    """(sim, tb, config) from the CSV's directory name; ('', '', '') when it is not a build dir."""
    m = BUILD_RE.match(os.path.basename(os.path.dirname(os.path.abspath(csv_path))))
    if not m:
        return "", "", ""
    return m.group("sim"), m.group("tb"), m.group("config") or ""


def split_status(status):
    """('PASS'|'XFAIL'|'FAIL', xpass_note)."""
    base, _, note = (status or "").partition("+")
    return base if base in RANK else "FAIL", note == "XPASS"


# +aou_config names the build's CONFIG, which the key already carries from the
# build directory; whether an entry spells it out must not split the comparison.
REDUNDANT_ARG = re.compile(r"^\+aou_config=")


def norm_args(text):
    return " ".join(sorted(a for a in (text or "").split() if not REDUNDANT_ARG.match(a)))


def load(paths, sim_agnostic=False):
    """{key: row} over every CSV; key = (sim?, tb, config, test, plusargs, seed)."""
    rows = {}
    dups = []
    for path in find_csvs(paths):
        sim, tb, config = build_of(path)
        with open(path, newline="", encoding="utf-8") as fh:
            for r in csv.DictReader(fh):
                key = ("" if sim_agnostic else sim, tb, config, r["test"], norm_args(r.get("plusargs")),
                       r["seed"])
                r = dict(r, sim=sim, tb=tb, config=config, csv=path)
                if key in rows:
                    dups.append(key)
                rows[key] = r
    return rows, dups


def label(key):
    sim, tb, config, test, plusargs, seed = key
    build = "-".join(x for x in (sim, tb, config) if x)
    return f"{build} {test} seed={seed}" + (f" {plusargs}" if plusargs else "")


def compare(base, after):
    """Classify every key of either side; returns {category: [(key, from, to)]}."""
    out = {"degraded": [], "dropped": [], "new": [], "fixed": [], "xfail_to_pass": [],
           "xpass_changed": [], "same": []}
    for key in sorted(set(base) | set(after)):
        b, a = base.get(key), after.get(key)
        if a is None:
            out["dropped"].append((key, b["status"], "missing"))
            continue
        if b is None:
            out["new"].append((key, "missing", a["status"]))
            continue
        bs, bx = split_status(b["status"])
        as_, ax = split_status(a["status"])
        if RANK[as_] > RANK[bs]:
            out["degraded"].append((key, b["status"], a["status"]))
        elif bs == "XFAIL" and as_ == "PASS":
            out["xfail_to_pass"].append((key, b["status"], a["status"]))
        elif bs == "FAIL" and as_ != "FAIL":
            out["fixed"].append((key, b["status"], a["status"]))
        elif bx != ax:
            out["xpass_changed"].append((key, b["status"], a["status"]))
        else:
            out["same"].append((key, b["status"], a["status"]))
    return out


TITLES = [("degraded", "Degradations (verdict got worse)"),
          ("dropped", "Dropped (baseline only)"),
          ("xfail_to_pass", "XFAIL -> PASS (bug fixed, or a check went missing: review)"),
          ("fixed", "Fixed (FAIL -> PASS/XFAIL)"),
          ("xpass_changed", "XPASS note appeared or disappeared"),
          ("new", "New (after only)")]


def report(result, base_n, after_n, dups):
    lines = ["# Result comparison", "",
             f"Baseline runs: {base_n}; after: {after_n}; unchanged: {len(result['same'])}.", ""]
    lines += ["| Category | Runs |", "|---|---|"]
    lines += [f"| {title} | {len(result[cat])} |" for cat, title in TITLES]
    if dups:
        lines += ["", f"Duplicate keys (last one wins): {len(dups)}"]
    for cat, title in TITLES:
        if not result[cat]:
            continue
        lines += ["", f"## {title}", "", "| Run | Baseline | After |", "|---|---|---|"]
        lines += [f"| {label(k)} | {b} | {a} |" for k, b, a in result[cat]]
    counts = Counter(split_status(a)[0] for _, _, a in result["same"])
    if counts:
        lines += ["", "Unchanged by verdict: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))]
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("baseline", nargs="?", help="directory tree or CSV of the baseline")
    ap.add_argument("after", nargs="?", help="directory tree or CSV of the after state")
    ap.add_argument("--baseline", dest="baseline_paths", action="append", default=[],
                    help="more baseline trees/CSVs (repeatable)")
    ap.add_argument("--after", dest="after_paths", action="append", default=[],
                    help="more after trees/CSVs (repeatable)")
    ap.add_argument("--sim-agnostic", action="store_true",
                    help="compare across simulators (drop the simulator from the run key)")
    ap.add_argument("-o", "--output", help="write the Markdown report here as well")
    args = ap.parse_args(argv)
    b_paths = ([args.baseline] if args.baseline else []) + args.baseline_paths
    a_paths = ([args.after] if args.after else []) + args.after_paths
    if not b_paths or not a_paths:
        ap.error("a baseline and an after side are required")

    base, dups_b = load(b_paths, args.sim_agnostic)
    after, dups_a = load(a_paths, args.sim_agnostic)
    if not base:
        print("compare_results: no results*.csv on the baseline side", file=sys.stderr)
        return 2
    if not after:
        print("compare_results: no results*.csv on the after side", file=sys.stderr)
        return 2
    result = compare(base, after)
    text = report(result, len(base), len(after), dups_b + dups_a)
    print(text, end="")
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text)
    bad = len(result["degraded"]) + len(result["dropped"])
    print(f"compare_results: {bad} degradation(s)", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
