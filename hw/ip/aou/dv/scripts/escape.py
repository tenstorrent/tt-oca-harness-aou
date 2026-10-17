#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Bug-escape suite: does the testbench catch every bug fixed on main?

For each [[escapes]] entry of testlists/escape.toml, the test runs on the clean build
and on the ESCAPE=<id> build (RTL/ copy with escape/<id>.patch applied).
An entry catches its bug when the clean run passes (PASS/XFAIL) and the escape
run fails with an error line matching the entry's signature. A bug is CAUGHT
when one of its entries catches it, else ESCAPED. Entries with `build: <sim>`
are caught only by that simulator's compile; they count as NOT-RUN unless
that simulator is the one selected.

Builds go through `make build` (LSF), runs through `make run`. The report is
printed and written to out/escape/escape_report.md. Exit status 1 when a bug
escaped or a clean run failed.
"""

import argparse
import concurrent.futures
import os
import re
import subprocess
import sys

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(UVM_ROOT, "scripts"))
import sim_cfg  # noqa: E402
import testlist  # noqa: E402
import run_list  # noqa: E402

ERR = re.compile(r"^UVM_(ERROR|FATAL) .*@")


def make(args, *extra):
    cmd = [run_list.MAKE, "--no-print-directory", f"SIM={args.sim}", *extra]
    if args.lsf_extra_opts:
        cmd.append(f"LSF_EXTRA_OPTS={args.lsf_extra_opts}")
    # Started from `make escape`: the parent's command-line variables (MAKEFLAGS)
    # must not leak into the clean and escape builds; LSF_EXTRA_OPTS goes on explicitly.
    env = {k: v for k, v in os.environ.items()
           if k not in ("MAKEFLAGS", "MFLAGS", "MAKELEVEL", "LSF_EXTRA_OPTS")}
    p = subprocess.run(cmd, cwd=UVM_ROOT, capture_output=True, text=True, env=env)
    return p.returncode, p.stdout + p.stderr


def build_args(tb, config, escape):
    a = [f"TB={tb}"]
    if tb == "t1":
        a.append(f"CONFIG={config}")
    if escape:
        a.append(f"ESCAPE={escape}")
    return a


def do_build(args, key):
    tb, config, escape = key
    rc, out = make(args, "build", *build_args(tb, config, escape))
    return key, rc, out


def do_run(args, e, seed, escape):
    extra = build_args(e["tb"], e["config"], escape) + [
        f"TEST={e['test']}", f"SEED={seed}", f"RID={args.rid}"]
    if e.get("plusargs"):
        extra.append(f"PLUSARGS={e['plusargs']}")
    _, out = make(args, "run", *extra)
    m = re.search(r"Run directory: (\S+)", out)
    run_dir = m.group(1) if m else ""
    m = re.search(r"^(PASS|XFAIL|FAIL|XPASS)\b", out, re.M)
    verdict = m.group(1) if m else "FAIL"
    errs = []
    log = os.path.join(run_dir, "sim.log")
    if os.path.exists(log):
        with open(log, encoding="utf-8", errors="replace") as fh:
            errs = [ln.rstrip() for ln in fh if ERR.match(ln)]
    return verdict, run_dir, errs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runlist", nargs="?",
                    default=os.path.join(UVM_ROOT, "testlists", "escape.toml"))
    ap.add_argument("--sim", default="vcs")
    ap.add_argument("--rid", default="esc")
    ap.add_argument("--escape", help="only this escape id")
    ap.add_argument("--no-build", action="store_true", help="reuse existing builds")
    ap.add_argument("--lsf-extra-opts", default=os.environ.get("LSF_EXTRA_OPTS", ""),
                    help="extra bsub options for every build and run (make LSF_EXTRA_OPTS; "
                         "default: $LSF_EXTRA_OPTS, which `make escape LSF_EXTRA_OPTS=..` sets)")
    ap.add_argument("-j", "--jobs", type=int, default=8)
    args = ap.parse_args()

    entries = []
    default_target = sim_cfg.default_target(sim_cfg.load("t1"))
    for e in sim_cfg.load_toml(args.runlist).get("escapes", []):
        if args.escape and e.get("escape") != args.escape:
            continue
        e = dict(e)
        e.setdefault("tb", "t1")
        e["config"] = e.get("target", default_target)
        e["plusargs"] = " ".join(e.get("args", []))
        e["seeds"] = testlist.seeds_of(e)
        entries.append(e)
    sim_entries = [e for e in entries if not e.get("build")]

    if not args.no_build:
        keys = set()
        for e in sim_entries:
            keys.add((e["tb"], e["config"], ""))
            keys.add((e["tb"], e["config"], e["escape"]))
        for e in entries:
            if e.get("build") == args.sim:
                keys.add(("t1", e["config"], e["escape"]))
        build_only = {e["escape"]: e for e in entries if e.get("build") == args.sim}
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
            for key, rc, out in ex.map(lambda k: do_build(args, k), sorted(keys)):
                tag = f"{key[0]}/{key[1]}{' ' + key[2] if key[2] else ''}"
                print(f"build  {tag}: {'ok' if rc == 0 else 'FAILED'}", flush=True)
                e = build_only.get(key[2])
                if e is not None:
                    name = f"{args.sim}-t1-{key[1]}-esc-{key[2]}"
                    log = os.path.join(UVM_ROOT, "build", name, "build.log")
                    text = open(log, encoding="utf-8", errors="replace").read() \
                        if os.path.exists(log) else out
                    e["result"] = "CAUGHT" if rc != 0 and re.search(e["signature"], text) \
                        else "ESCAPED"
                elif rc != 0:
                    print(out[-3000:])
                    return 1

    jobs = []
    for e in sim_entries:
        for s in e["seeds"]:
            jobs.append((e, s))

    def one(job):
        e, s = job
        clean = do_run(args, e, s, "")
        esc = do_run(args, e, s, e["escape"])
        return e, s, clean, esc

    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for e, s, clean, esc in ex.map(one, jobs):
            sig = re.compile(e["signature"])
            hit = next((ln for ln in esc[2] if sig.search(ln)), "")
            clean_ok = clean[0] in ("PASS", "XFAIL")
            caught = clean_ok and esc[0] == "FAIL" and bool(hit)
            res = "CAUGHT" if caught else ("CLEAN-FAILS" if not clean_ok else "ESCAPED")
            e.setdefault("seed_results", []).append(res)
            rows.append((e["escape"], e["test"], e.get("plusargs", ""), e["tb"], e["config"], s,
                         clean[0], esc[0], res, hit.split("] ", 1)[-1][:120], esc[1]))
            print(f"{res:11} {e['escape']:5} {e['test']} seed={s} {e.get('plusargs', '')} "
                  f"clean={clean[0]} escape={esc[0]}", flush=True)
    for e in sim_entries:
        r = e.get("seed_results", [])
        e["result"] = ("CAUGHT" if r and all(x == "CAUGHT" for x in r)
                       else "CLEAN-FAILS" if "CLEAN-FAILS" in r else "ESCAPED")

    bugs = {}
    for e in entries:
        res = e.get("result", "NOT-RUN")
        prev = bugs.get(e["escape"], "NOT-RUN")
        order = ["CAUGHT", "CLEAN-FAILS", "ESCAPED", "NOT-RUN"]
        bugs[e["escape"]] = min(prev, res, key=order.index)

    out_dir = os.path.join(UVM_ROOT, "out", "escape")
    os.makedirs(out_dir, exist_ok=True)
    lines = ["# Bug-escape suite", "",
             f"Simulator {args.sim}; run list {os.path.relpath(args.runlist, UVM_ROOT)}.", "",
             "| Escape | Result |", "|---|---|"]
    lines += [f"| {b} | {r} |" for b, r in sorted(bugs.items())]
    lines += ["", "| Escape | Test | Plusargs | TB/config | Seed | Clean | Escape run | Result | "
              "First matching error | Escape run directory |", "|" + "---|" * 10]
    for r in rows:
        lines.append(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]}/{r[4]} | {r[5]} | {r[6]} | {r[7]} | "
                     f"{r[8]} | {r[9].replace('|', '/')} | {os.path.relpath(r[10], UVM_ROOT) if r[10] else ''} |")
    for e in entries:
        if e.get("build"):
            lines.append(f"| {e['escape']} | ({e['build']} build) | | | | | | "
                         f"{e.get('result', 'NOT-RUN')} | {e.get('note', '')} | |")
    report = "\n".join(lines) + "\n"
    with open(os.path.join(out_dir, "escape_report.md"), "w", encoding="utf-8") as fh:
        fh.write(report)
    print()
    for b, r in sorted(bugs.items()):
        print(f"{b:6} {r}")
    print(f"report: {os.path.join(out_dir, 'escape_report.md')}")
    bad = [b for b, r in bugs.items() if r in ("ESCAPED", "CLEAN-FAILS")]
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
