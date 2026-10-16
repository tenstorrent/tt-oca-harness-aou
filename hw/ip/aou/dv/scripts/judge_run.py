#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Judge tt-oca-harness run_dv.py runs with the bench's grader and write results.csv.

Walks one or more run_dv run directories for the leaf result.json files
(schema 1: `item`, `seed`, `status`, `log`, `target`, `flow`), reads each
leaf's simulation log and judges it exactly as `make run` does
(scripts/check_run.py against expected_fail.yaml: PASS, XFAIL, FAIL, plus
XPASS notes), so a harness regression and a standalone one can be compared
with scripts/compare_results.py. The CSV has run_list.py's columns
(test, seed, plusargs, status, plan_ids, run_dir, name) plus harness_status,
the runner's own verdict (PASS, FAIL, ERROR, TIMEOUT, UNKNOWN; an expect_fail
leaf the runner graded PASS from an observed FAIL is written as PASS(xfail)).

Rows are grouped by target into <out-dir>/<sim>-<tb>-<target>/results.csv so
compare_results.py recovers TB and CONFIG from the directory name as it does
for run_list.py's output (--out-dir defaults to out/harness). The scenario
name (`item`) is looked up in the bench's testlist for the test class, the
plusargs and the plan IDs; an item that is not in the list is judged from
its log alone. Exit status 1 when a leaf is FAIL or when the bench's verdict
and the runner's disagree on pass/fail (listed as divergences: the runner
passing a leaf the grader fails, or failing one the grader passes or XFAILs).
"""

import argparse
import csv
import json
import os
import re
import sys

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(UVM_ROOT, "scripts"))
import check_run  # noqa: E402
import sim_cfg  # noqa: E402
import testlist  # noqa: E402

EXPECTED = os.path.join(UVM_ROOT, "expected_fail.yaml")
SIM_STATUSES = {"PASS", "FAIL", "ERROR", "TIMEOUT", "UNKNOWN", "SKIP"}


def flow_benches():
    """{sim_cfg name: tb} for the four benches."""
    out = {}
    for tb in sim_cfg.TBS:
        try:
            out[sim_cfg.load(tb).get("name", "")] = tb
        except (OSError, ValueError):
            pass
    return out


def leaves(run_dirs):
    """Every leaf result.json under the run directories: (leaf_dir, payload)."""
    for top in run_dirs:
        for root, dirs, files in os.walk(top):
            dirs.sort()
            if "result.json" not in files:
                continue
            path = os.path.join(root, "result.json")
            try:
                with open(path, encoding="utf-8") as fh:
                    data = json.load(fh)
            except (OSError, ValueError) as e:
                print(f"judge_run: {path}: {e}", file=sys.stderr)
                continue
            if not isinstance(data, dict) or "item" not in data or "seed" not in data:
                continue  # a run-level or rollup record
            if "runs" in data or "stages" in data or data.get("status") not in SIM_STATUSES:
                continue
            if not data["item"]:
                continue  # a build stage (hdl_compile) records itself with an empty item
            yield root, data


def harness_root(leaf_dir, logged):
    """The directory the leaf's repo-relative paths are rooted at (None when unknown)."""
    d = os.path.abspath(leaf_dir)
    while True:
        if logged and os.path.exists(os.path.join(d, logged)):
            return d
        if os.path.isdir(os.path.join(d, "tools", "dv")) or os.path.exists(os.path.join(d, "duts.toml")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def find_log(leaf_dir, data, root):
    """The leaf's simulation log, or None."""
    logged = data.get("log")
    candidates = []
    if logged:
        if os.path.isabs(logged):
            candidates.append(logged)
        else:
            base = root or harness_root(leaf_dir, logged)
            if base:
                candidates.append(os.path.join(base, logged))
            candidates.append(os.path.join(leaf_dir, logged))
    item = data.get("item", "")
    candidates += [os.path.join(leaf_dir, "logs", f"{item}.log"), os.path.join(leaf_dir, "sim.log")]
    for c in candidates:
        if os.path.isfile(c):
            return c
    logs_dir = os.path.join(leaf_dir, "logs")
    if os.path.isdir(logs_dir):
        logs = sorted(f for f in os.listdir(logs_dir) if f.endswith(".log"))
        if logs:
            return os.path.join(logs_dir, logs[0])
    return None


def harness_status(data):
    s = data.get("status", "")
    xf = (data.get("metadata") or {}).get("expected_fail")
    if s == "PASS" and isinstance(xf, dict) and xf.get("observed_status") == "FAIL":
        return "PASS(xfail)"
    return s


def judge_leaf(leaf_dir, data, entry, root, expected):
    """(status, run_dir) for one leaf, judged the way `make run` judges."""
    log = find_log(leaf_dir, data, root)
    if log is None:
        return "FAIL", leaf_dir
    text = open(log, encoding="utf-8", errors="replace").read()
    lines = check_run.judge(text, log, expected, entry["test"] if entry else None)
    m = re.search(r"^(PASS|XFAIL|FAIL)\b", "\n".join(lines), re.M)
    status = m.group(1) if m else "FAIL"
    if status != "FAIL" and any(ln.startswith("XPASS") for ln in lines):
        status += "+XPASS"
    return status, leaf_dir


def diverges(bench, harness):
    b_ok = bench.startswith(("PASS", "XFAIL"))
    h_ok = harness.startswith("PASS")
    return b_ok != h_ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dirs", nargs="+", help="run_dv.py run directories (searched recursively)")
    ap.add_argument("--root", help="the harness checkout the leaves' repo-relative log paths are "
                                   "rooted at (default: found from the run directory)")
    ap.add_argument("--tb", choices=sorted(sim_cfg.TBS),
                    help="the bench whose testlist names the items (default: from each leaf's `flow`)")
    ap.add_argument("--sim", default="", help="simulator for the output directory names "
                                              "(default: each leaf's `tool`)")
    ap.add_argument("--expected", default=EXPECTED, help="expected_fail.yaml")
    ap.add_argument("--out-dir", default=os.path.join(UVM_ROOT, "out", "harness"),
                    help="where <sim>-<tb>-<target>/results.csv go")
    ap.add_argument("--list-name", default="",
                    help="write results_<name>.csv instead of results.csv")
    args = ap.parse_args(argv)

    benches = flow_benches()
    plan_ids = testlist.load_plan_ids()
    ents = {}  # tb -> {name: entry}

    def entry_for(tb, name):
        if tb not in ents:
            cfg = sim_cfg.load(tb)
            path = os.path.join(UVM_ROOT, cfg.get("testlist", {}).get("path", ""))
            ents[tb] = {e["name"]: e for e in testlist.entries(path, plan_ids)} if os.path.isfile(path) else {}
        return ents[tb].get(name)

    groups = {}  # (sim, tb, target) -> rows
    divergent, n = [], 0
    for leaf_dir, data in leaves(args.run_dirs):
        tb = args.tb or benches.get(data.get("flow", ""), "t1")
        name = data["item"]
        entry = entry_for(tb, name)
        target = data.get("target") or (entry or {}).get("target") or sim_cfg.default_target(sim_cfg.load(tb))
        sim = args.sim or data.get("tool", "") or "harness"
        status, run_dir = judge_leaf(leaf_dir, data, entry, args.root, args.expected)
        hs = harness_status(data)
        row = [entry["test"] if entry else name, str(data["seed"]), entry["plusargs"] if entry else "",
               status, entry["plan_ids"] if entry else "", run_dir, name, hs]
        groups.setdefault((sim, tb, target), []).append(row)
        n += 1
        if diverges(status, hs):
            divergent.append((name, data["seed"], status, hs, run_dir))

    if not n:
        print("judge_run: no leaf result.json found", file=sys.stderr)
        return 2
    bad = 0
    for (sim, tb, target), rows in sorted(groups.items()):
        d = os.path.join(args.out_dir, f"{sim}-{tb}-{target}")
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f"results_{args.list_name}.csv" if args.list_name else "results.csv")
        rows.sort(key=lambda r: (r[0], r[2], int(r[1]) if r[1].isdigit() else r[1]))
        with open(path, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["test", "seed", "plusargs", "status", "plan_ids", "run_dir", "name", "harness_status"])
            w.writerows(rows)
        failed = [r for r in rows if not r[3].startswith(("PASS", "XFAIL"))]
        bad += len(failed)
        print(f"{len(rows) - len(failed)}/{len(rows)} PASS/XFAIL; results in {path}")
    for name, seed, status, hs, run_dir in divergent:
        print(f"divergence: {name} seed={seed} bench={status} harness={hs} {run_dir}")
    print(f"judge_run: {n} leaf run(s), {bad} FAIL, {len(divergent)} divergence(s)")
    return 1 if bad or divergent else 0


if __name__ == "__main__":
    sys.exit(main())
