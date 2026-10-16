#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Test-plan status from the testlists and the runs under out/.

Reads docs/test_plan_items.yaml, every bench's testlist aggregate (the
[testlist] of its sim config, with testlists/plan_ids.yaml for the plan
items each scenario covers) and the run directories
out/<build>/<test>.rid.*/. A run belongs to a scenario when its test class,
its plusargs (from run.sh, ignoring the seed, wave, coverage and FDI_ENC
arguments) and its build (TB and CONFIG from the build directory name) match
the scenario; a scenario without `target` matches every T1 config, as
scripts/run_list.py runs it on any. Each item is then:

  covered      a PASS run of an entry that lists it
  xfail-only   no PASS, only XFAIL runs (known DUT bugs, named)
  failing      no PASS, at least one FAIL run
  blocked      no runs; every scenario listing it is tagged `blocked`
  not covered  no entry lists it, or its entries have no judged runs

Only PASS counts, as for coverage. A run's verdict is the PASS/XFAIL/FAIL line
of its verdict.txt (scripts/check_run.py). Runs without one are unjudged and
ignored unless --judge, which judges their sim.log with check_run.py's rules
(read-only); a run whose sim.log is still being written is skipped. Merged items
report through their surviving ID; dropped items are listed but not counted.
"""

import argparse
import csv
import glob
import io
import os
import re
import sys
import time
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_run  # noqa: E402
import listyaml  # noqa: E402
import sim_cfg  # noqa: E402
import testlist  # noqa: E402

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATUSES = ["covered", "xfail-only", "failing", "blocked", "not covered"]
TBS = {"reg", "axi_selftest", "t1", "l3_unit"}


def t1_configs():
    """The T1 CONFIG names: the plain targets of aou_sim_cfg.toml."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sim_cfg
    return set(sim_cfg.t1_configs())


CONFIGS = t1_configs()
# Plusargs the Makefile adds itself: seed, coverage and wave arguments.
# Arguments the Makefile and run_list.py add to every run (seed, waves, coverage
# outputs, FDI_ENC), not part of what a run-list entry asks for.
INFRA_ARG = re.compile(r"^\+(UVM_TESTNAME=|ntb_random_seed=|verilator\+|AXI4_FC_|aou_fc_json=|aou_config=|FDI_ENC=|waves\b)")
VERDICT_RE = re.compile(r"^(PASS|XFAIL|FAIL)\b")


def build_key(build):
    """(tb, config) from a build directory name such as vcs-t1-1x512-sp64-cov.

    CONFIG names contain '-', so the config is matched as a whole name after the TB.
    A name without a known TB (an old build) gives tb "", which matches no entry."""
    tb, config, flags = "", "", []
    rest = build.split("-", 1)[1] if "-" in build else ""
    head, _, tail = rest.partition("-")
    if head in TBS:
        tb, rest = head, tail
    for c in sorted(CONFIGS, key=len, reverse=True):
        if rest == c or rest.startswith(c + "-"):
            config, rest = c, rest[len(c) + 1:]
            break
    flags = rest.split("-") if rest else []
    if "noaxi" in flags:
        config += "-noaxi"
    return tb, config


def norm_plusargs(text):
    return tuple(sorted(t for t in (text or "").split() if t.startswith("+") and not INFRA_ARG.match(t)))


def run_plusargs(run_sh):
    with open(run_sh, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "+UVM_TESTNAME=" in line:
                return norm_plusargs(line.split("2>&1")[0])
    return None


def load_entries(paths, aliases, known, plan_ids=None):
    entries, unknown = [], defaultdict(set)
    for path in paths:
        for e in testlist.entries(path, plan_ids):
            if not e["test"]:
                continue
            tb = e["tb"]
            ids = []
            for pid in testlist.ids(e["plan_ids"]):
                if pid not in known:
                    unknown[pid].add(e["list"] + ".toml")
                ids.append(aliases.get(pid, pid))
            entries.append({
                "test": e["test"], "name": e["name"], "tb": tb,
                "config": e["target"] or ("*" if tb in ("t1", "reg") else ""),
                "seeds": set(e["seeds"]), "seeds_run": set(),
                "plusargs": norm_plusargs(e["plusargs"]), "plan_ids": ids,
                "blocked": e["blocked"], "list": e["list"] + ".toml",
                "verdicts": Counter(), "bugs": set(),
            })
    return entries, unknown


def read_verdict(run, args):
    """PASS/XFAIL/FAIL with the bug IDs, 'unjudged' or 'incomplete'."""
    vfile, log = os.path.join(run, "verdict.txt"), os.path.join(run, "sim.log")
    lines = None
    if os.path.exists(vfile):
        with open(vfile, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    elif args.judge and os.path.exists(log):
        with open(log, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if "UVM Report Summary" not in text and time.time() - os.path.getmtime(log) < args.settle * 60:
            return "incomplete", set()
        test = os.path.basename(run).split(".rid.")[0]
        lines = check_run.judge(text, log, args.expected, test)
    elif args.judge:
        return "incomplete", set()
    if lines is None:
        return "unjudged", set()
    verdict = next((m.group(1) for m in map(VERDICT_RE.match, reversed(lines)) if m), None)
    if verdict is None:
        return "incomplete", set()
    bugs = set()
    for line in lines:
        if line.startswith("XFAIL"):
            m = re.search(r"all known \(([^)]*)\)", line)
            bugs.update(b.strip() for b in (m.group(1).split(",") if m else []) if b.strip())
    return verdict, bugs


def scan_runs(out_dir, entries, args):
    index = defaultdict(list)
    for e in entries:
        index[(e["test"], e["tb"], e["config"], e["plusargs"])].append(e)
    runs = Counter()
    unmatched = Counter()
    for run in sorted(glob.glob(os.path.join(out_dir, "*", "*.rid.*"))):
        if not os.path.isdir(run):
            continue
        build = os.path.basename(os.path.dirname(run))
        if "-esc-" in build:
            continue
        test = os.path.basename(run).split(".rid.")[0]
        run_sh = os.path.join(run, "run.sh")
        plusargs = run_plusargs(run_sh) if os.path.exists(run_sh) else None
        if plusargs is None:
            runs["incomplete"] += 1
            continue
        verdict, bugs = read_verdict(run, args)
        runs[verdict] += 1
        if verdict not in ("PASS", "XFAIL", "FAIL"):
            continue
        tb, config = build_key(build)
        hits = index.get((test, tb, config, plusargs), []) + index.get((test, tb, "*", plusargs), [])
        if not hits:
            unmatched[(build, test, " ".join(plusargs))] += 1
            continue
        runs["matched"] += 1
        m = re.search(r"\.seed\.(\d+)\.", os.path.basename(run))
        for e in hits:
            if m:
                e["seeds_run"].add(int(m.group(1)))
            e["verdicts"][verdict] += 1
            e["bugs"] |= bugs
    return runs, unmatched


def entry_label(e):
    cfg = f" [{e['tb']}{'/' + e['config'] if e['config'] not in ('', '*') else ''}"
    seeds = f", seeds {len(e['seeds'] & e['seeds_run'])}/{len(e['seeds'])}]"
    return e["test"] + (" " + " ".join(e["plusargs"]) if e["plusargs"] else "") + cfg + seeds


def item_status(entries):
    if not entries:
        return "not covered", "no run-list entry"
    v = Counter()
    bugs = set()
    for e in entries:
        v += e["verdicts"]
        if not e["verdicts"]["PASS"]:
            bugs |= e["bugs"]
    passing = [e for e in entries if e["verdicts"]["PASS"]]
    if passing:
        extra = f"; also {v['FAIL']} FAIL" if v["FAIL"] else ""
        return "covered", f"{v['PASS']} PASS: " + "; ".join(entry_label(e) for e in passing[:3]) + \
            (f" (+{len(passing) - 3} more)" if len(passing) > 3 else "") + extra
    if v["FAIL"]:
        return "failing", f"{v['FAIL']} FAIL, {v['XFAIL']} XFAIL: " + \
            "; ".join(entry_label(e) for e in entries if e["verdicts"]["FAIL"])
    if v["XFAIL"]:
        return "xfail-only", f"{v['XFAIL']} XFAIL ({', '.join(sorted(bugs)) or 'bug not named'})"
    if all(e["blocked"] for e in entries):
        return "blocked", "; ".join(sorted({e["blocked"] for e in entries}))
    return "not covered", "no judged run of " + "; ".join(entry_label(e) for e in entries[:2]) + \
        (f" (+{len(entries) - 2} more)" if len(entries) > 2 else "")


def evaluate(args):
    items = listyaml.load(args.items)
    known = {i["id"] for i in items}
    aliases = {i["id"]: i["merged_into"] for i in items if i.get("merged_into")}
    # escape.toml lists bug re-introductions, not plan coverage; escape builds
    # (-esc-<id>) carry known bugs and are skipped in scan_runs.
    paths = args.runlist or [os.path.join(UVM_ROOT, sim_cfg.load(tb)["testlist"]["path"])
                             for tb in ("t1", "reg", "l3_unit", "axi_selftest")]
    side = testlist.load_plan_ids(args.plan_ids) if args.plan_ids else None
    entries, unknown = load_entries(paths, aliases, known, side)
    runs, unmatched = scan_runs(args.out_dir, entries, args)
    by_item = defaultdict(list)
    for e in entries:
        for pid in dict.fromkeys(e["plan_ids"]):
            by_item[pid].append(e)
    rows = []
    for it in items:
        if it.get("merged_into"):
            status, ev = "merged", f"reports as {it['merged_into']}"
        elif it.get("dropped"):
            status, ev = "dropped", it["dropped"]
        else:
            status, ev = item_status(by_item.get(it["id"], []))
        rows.append({**it, "status": status, "evidence": ev})
    return rows, runs, unmatched, unknown, paths


def counts(rows):
    c = Counter(r["status"] for r in rows)
    return c


def md_escape(s):
    return str(s).replace("|", "\\|")


def render_md(rows, runs, unmatched, unknown, paths, args):
    out = io.StringIO()
    w = out.write
    active = [r for r in rows if r["status"] in STATUSES]
    c = counts(rows)
    w("# Test-plan status\n\n")
    w(f"Runs under `{os.path.relpath(args.out_dir, UVM_ROOT) if args.out_dir.startswith(UVM_ROOT) else args.out_dir}`: "
      f"{runs['PASS'] + runs['XFAIL'] + runs['FAIL']} judged ({runs['PASS']} PASS, {runs['XFAIL']} XFAIL, "
      f"{runs['FAIL']} FAIL), {runs['matched']} matched to run-list entries, "
      f"{sum(unmatched.values())} unmatched, {runs['unjudged']} unjudged (no verdict.txt"
      f"{'' if args.judge else '; --judge to judge them'}), {runs['incomplete']} incomplete. "
      f"Run lists: {', '.join(os.path.basename(p) for p in paths)}.\n\n")
    w("## Summary\n\n| Status | Items | P0 | P1 | P2 |\n|---|---|---|---|---|\n")
    for s in STATUSES:
        pc = Counter(r["priority"] for r in active if r["status"] == s)
        w(f"| {s} | {c[s]} | {pc['P0']} | {pc['P1']} | {pc['P2']} |\n")
    pc = Counter(r["priority"] for r in active)
    w(f"| **total** | **{len(active)}** | {pc['P0']} | {pc['P1']} | {pc['P2']} |\n\n")
    w(f"{c['merged']} duplicate items report through their surviving ID and {c['dropped']} are dropped; "
      f"neither is counted above.\n\n")
    w("## Per section\n\n| Section | Items | Covered | XFAIL only | Failing | Blocked | Not covered | Merged | Dropped |\n"
      "|---|---|---|---|---|---|---|---|---|\n")
    secs = {}
    for r in rows:
        secs.setdefault((r["section"], r["section_title"]), Counter())[r["status"]] += 1
    for (sec, title), sc in sorted(secs.items(), key=lambda kv: int(kv[0][0].split(".")[1])):
        n = sum(sc[s] for s in STATUSES)
        w(f"| {sec} {title} | {n} | " + " | ".join(str(sc[s]) for s in STATUSES) +
          f" | {sc['merged']} | {sc['dropped']} |\n")
    w("\n## Items\n\n| ID | Pri | Title | Status | Evidence |\n|---|---|---|---|---|\n")
    for r in rows:
        title = r["title"] if len(r["title"]) <= 90 else r["title"][:87] + "..."
        w(f"| {r['id']} | {r['priority']} | {md_escape(title)} | {r['status']} | {md_escape(r['evidence'])} |\n")
    if unknown:
        w("\n## Run-list plan IDs not in the plan\n\n")
        for pid, lists in sorted(unknown.items()):
            w(f"- {pid} ({', '.join(sorted(lists))})\n")
    if unmatched:
        w("\n## Runs that match no run-list entry\n\n| Build | Test | Plusargs | Runs |\n|---|---|---|---|\n")
        for (build, test, pa), n in sorted(unmatched.items()):
            w(f"| {build} | {test} | {md_escape(pa) or '-'} | {n} |\n")
    return out.getvalue()


def render_csv(rows):
    out = io.StringIO()
    cw = csv.writer(out)
    cw.writerow(["id", "section", "priority", "status", "title", "evidence"])
    for r in rows:
        cw.writerow([r["id"], r["section"], r["priority"], r["status"], r["title"], r["evidence"]])
    return out.getvalue()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--items", default=os.path.join(UVM_ROOT, "docs", "test_plan_items.yaml"))
    ap.add_argument("--runlist", action="append",
                    help="testlist (repeatable; default: every bench's aggregate from its sim config)")
    ap.add_argument("--plan-ids", default=None,
                    help="scenario -> plan items sidecar (default testlists/plan_ids.yaml)")
    ap.add_argument("--out-dir", default=os.path.join(UVM_ROOT, "out"), help="directory holding <build>/ run dirs")
    ap.add_argument("--expected", default=os.path.join(UVM_ROOT, "expected_fail.yaml"))
    ap.add_argument("--judge", action="store_true", help="judge runs that have no verdict.txt from their sim.log")
    ap.add_argument("--settle", type=float, default=10,
                    help="with --judge: a sim.log without a report summary changed within this many minutes "
                         "is still running (default 10)")
    ap.add_argument("--format", choices=["md", "csv"], default="md")
    ap.add_argument("-o", "--output", help="write here instead of stdout")
    args = ap.parse_args(argv)
    args.out_dir = os.path.abspath(args.out_dir)

    rows, runs, unmatched, unknown, paths = evaluate(args)
    text = render_csv(rows) if args.format == "csv" else render_md(rows, runs, unmatched, unknown, paths, args)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)
    c = counts(rows)
    print("plan status: " + ", ".join(f"{c[s]} {s}" for s in STATUSES) +
          f" ({c['merged']} merged, {c['dropped']} dropped)" + (f" -> {args.output}" if args.output else ""),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
