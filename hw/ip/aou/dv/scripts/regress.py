#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Build and run the whole regression: every bench, build configuration and testlist.

    make regress [SIM=vcs|verilator] [RID=<rid>] [CONFIGS="<config> ..."] [COV=1]
                 [RTL_PATCH=<abs path>] [ITEMS="<group|scenario> ..."] [RUN_JOBS=N]
                 [BENCHES="t1 reg assert l3_unit axi_selftest"] [STEPS=build,run,summary]
                 [RERUN_FAILED=<rid>] [DRY_RUN=1]

(or python3 scripts/regress.py --help for the same options). The steps, in order:

  build    make build for every build the regression needs: the T1 and register benches
           for every CONFIG (COV=1 builds with coverage), RTL_ASSERT=1 for every CONFIG
           that has a <CONFIG>-assert target, and the two model unit benches (l3_unit,
           axi_selftest).
  run      scripts/run_list.py once per build: T1 runs every testlist all.toml includes
           (--per-list) except the assertions list, which runs on the -assert builds; the
           register bench runs registers.toml, the unit benches their own lists. A build
           that already has results for this RID is skipped, so repeating the step after
           an interruption runs only what is missing.
  cov      (COV=1) make cov_report per CONFIG for this RID's passing runs (the register
           bench's folded in), then the union over the CONFIGs: code coverage (VCS urg,
           or verilator_coverage) and functional coverage (fc_report.py).
  summary  One table per bench (T1, reg, assert, l3_unit, axi_selftest) of PASS, XFAIL,
           FAIL and XPASS from the results CSVs run_list.py wrote, with every FAIL and
           XPASS run listed and the command that reruns it with waves.

Builds and runs go through make, so LSF works as it does for make build/run: with bsub
on PATH every build and run_list.py is started at once and each job is submitted
through LSF; with LSF=0 they run one after another on this host. Whatever else is
given to make regress (LSF_QUEUE, AXI4PC=0, LSF_EXTRA_OPTS, ...) reaches those makes.

RTL assertions (the -assert builds) are VCS-only: on Verilator they are skipped with a
note. The unit benches have no DUT, so they build without coverage under COV=1.

Logs, the exact commands, the state and summary.md go to out/regress/<RID>/; the run
directories and results CSVs are where make run and run_list.py put them,
out/<build>/. The exit status is 1 when any run is FAIL or XPASS, when a build
produced no results or when a step failed, else 0.
"""

import argparse
import csv
import glob
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import passing_runs  # noqa: E402
import sim_cfg  # noqa: E402
import testlist  # noqa: E402

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sim_cfg.ROOT
MAKE = os.environ.get("MAKE") or shutil.which("gmake") or "make"
STEPS = ("build", "run", "cov", "summary")
BENCHES = ("t1", "reg", "assert", "l3_unit", "axi_selftest")
SECTION = {"t1": "T1", "reg": "reg", "assert": "assert", "l3_unit": "l3_unit",
           "axi_selftest": "axi_selftest"}
ASSERT_LIST = "testlists/assertions.toml"
T1_LIST = "testlists/all.toml"
RID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
VERDICTS = ("PASS", "XFAIL", "FAIL")


class Unit:
    """One build and the run_list.py call on it."""

    def __init__(self, bench, config=None):
        self.bench, self.config = bench, config
        self.tb = "t1" if bench in ("t1", "assert") else bench
        self.target = None
        if config:
            self.target = config + ("-assert" if bench == "assert" else "")
        self.build = ""
        self.lists, self.items = [], None

    @property
    def label(self):
        return f"{self.bench}-{self.config}" if self.config else self.bench


def die(msg):
    print(f"regress: {msg}", file=sys.stderr)
    sys.exit(2)


def make(*argv, capture=True):
    p = subprocess.run([MAKE, "-s", "--no-print-directory", *argv], cwd=UVM_ROOT,
                       capture_output=capture, text=True, check=False)
    if p.returncode:
        err = (p.stderr or p.stdout or "").strip().splitlines()
        die(f"make {' '.join(argv)}: {err[-1] if err else 'failed'}")
    return p.stdout


def build_vars(args, u):
    """The make variables that select a unit's build (run_list.py passes the same)."""
    cov = args.cov if u.bench in ("t1", "reg") else "0"
    out = [f"SIM={args.sim}", f"TB={u.tb}", f"COV={cov}"]
    if u.config:
        out.append(f"CONFIG={u.config}")
    out.append(f"RTL_ASSERT={1 if u.bench == 'assert' else 0}")
    if args.rtl_patch and u.config:
        out.append(f"RTL_PATCH={args.rtl_patch}")
    return out


def list_names(path):
    """The group and scenario names a testlist (with its includes) defines."""
    tests, groups = testlist.load(os.path.join(UVM_ROOT, path))
    return set(tests) | set(groups)


def results_files(out_root, build, rid):
    d = os.path.join(out_root, build)
    esc = glob.escape(rid)
    return sorted(set(glob.glob(os.path.join(d, f"results*.rid.{esc}.csv")))
                  | set(glob.glob(os.path.join(d, f"results_rid.{esc}.csv"))))


def read_rows(out_root, build, rid):
    rows = []
    for path in results_files(out_root, build, rid):
        with open(path, newline="", encoding="utf-8") as fh:
            rows += list(csv.DictReader(fh))
    return rows


def planned_runs(args, u):
    """The runs run_list.py plans for a build (its --dry-run), or None if it cannot say."""
    p = subprocess.run(run_cmd(args, u) + ["--dry-run"], cwd=UVM_ROOT, capture_output=True,
                       text=True, check=False)
    m = re.search(r"^(\d+) run\(s\)", p.stdout, re.M)
    return int(m.group(1)) if m else None


def verdict(status):
    """(PASS|XFAIL|FAIL, XPASS note) of a run_list.py status; anything unknown is FAIL."""
    base, _, note = (status or "").partition("+")
    return (base if base in VERDICTS else "FAIL"), note == "XPASS"


def failed_names(out_root, build, rid):
    """The scenarios with a FAIL or XPASS run in that RID's results of a build."""
    names = []
    for r in read_rows(out_root, build, rid):
        base, xpass = verdict(r.get("status"))
        name = r.get("name") or r.get("test")
        if (base == "FAIL" or xpass) and name not in names:
            names.append(name)
    return names


def plan(args):
    """The units of this regression and the notes about what was left out."""
    notes = []
    t1_cfg = sim_cfg.load("t1")
    t1_targets = sim_cfg.targets(t1_cfg)
    configs = [t for t in t1_targets if not t.endswith("-assert")]
    assert_configs = [t[:-len("-assert")] for t in t1_targets if t.endswith("-assert")]
    if args.configs:
        bad = [c for c in args.configs if c not in configs]
        if bad:
            die(f"unknown CONFIGS {' '.join(bad)}; use some of {' '.join(configs)}")
        configs = [c for c in configs if c in args.configs]
    benches = args.benches or list(BENCHES)
    bad = [b for b in benches if b not in BENCHES]
    if bad:
        die(f"unknown BENCHES {' '.join(bad)}; use some of {' '.join(BENCHES)}")
    if "assert" in benches and args.sim != "vcs":
        notes.append(f"assert: skipped; the RTL assertions use SVA ranges, so the -assert builds "
                     f"are VCS-only (SIM={args.sim})")
        benches = [b for b in benches if b != "assert"]
    if args.cov == "1":
        for b in ("l3_unit", "axi_selftest"):
            if b in benches:
                notes.append(f"{b}: no DUT, so built and run without coverage")
        if "assert" in benches:
            notes.append("assert: the -assert builds are run without coverage")

    units = []
    for b in benches:
        if b in ("t1", "reg"):
            units += [Unit(b, c) for c in configs]
        elif b == "assert":
            units += [Unit(b, c) for c in configs if c in assert_configs]
            left = [c for c in configs if c not in assert_configs]
            if left:
                notes.append(f"assert: no -assert target for {' '.join(left)}")
        else:
            units.append(Unit(b))

    t1_includes = ["testlists/" + i for i in sim_cfg.load_toml(os.path.join(UVM_ROOT, T1_LIST))
                   .get("includes", [])]
    kept = []
    for u in units:
        if u.bench == "t1":
            agg, full = T1_LIST, [lst for lst in t1_includes if lst != ASSERT_LIST]
        elif u.bench == "assert":
            agg = full = ASSERT_LIST
        else:
            agg = full = sim_cfg.load(u.tb)["testlist"]["path"]
        full = full if isinstance(full, list) else [full]
        if args.rerun_failed:
            u.build = make("build-name", *build_vars(args, u)).split()[-1]
            names = failed_names(args.out_root, u.build, args.rerun_failed)
            if not names:
                notes.append(f"{u.label}: no FAIL or XPASS in rid {args.rerun_failed}; not rerun")
                continue
            u.lists, u.items = [agg], names
        elif args.items:
            have = list_names(agg)
            items = [i for i in args.items if i in have]
            if not items:
                notes.append(f"{u.label}: none of ITEMS defined in {agg}; skipped")
                continue
            u.lists, u.items = [agg], items
        else:
            u.lists = full
        kept.append(u)
    for u in kept:
        if not u.build:
            u.build = make("build-name", *build_vars(args, u)).split()[-1]
    return kept, configs, notes


def build_cmd(args, u):
    return [MAKE, "--no-print-directory", "build", *build_vars(args, u)]


def run_cmd(args, u):
    cmd = [sys.executable, os.path.join(UVM_ROOT, "scripts", "run_list.py"), "--sim", args.sim,
           "--tb", u.tb, "--cov", args.cov if u.bench in ("t1", "reg") else "0", "--rid", args.rid,
           "-j", str(args.jobs), "--per-list", "--out-dir", os.path.join(args.out_root, u.build)]
    if u.target:
        cmd += ["--target", u.target]
    if args.rtl_patch and u.config:
        cmd += ["--rtl-patch", args.rtl_patch]
    if args.reseed:
        cmd += ["--reseed", str(args.reseed)]
    # The lists go before --items, which takes every word after it.
    cmd += [os.path.join(UVM_ROOT, lst) for lst in u.lists]
    return cmd + (["--items", *u.items] if u.items else [])


def bsub_prefix(args, name, log):
    """The bench's own bsub line (make lsf-bsub) for a job make does not submit itself."""
    line = make("lsf-bsub", f"SIM={args.sim}").strip()
    return shlex.split(line) + ["-J", f"aou_{name}", "-R", f"rusage[mem={args.cov_mem}]",
                                "-o", log + ".lsf"]


def cov_cmds(args, units, configs, regdir, write=True):
    """make cov_report per CONFIG, then the union job (regress.py --union)."""
    t1 = {u.config: u for u in units if u.bench == "t1"}
    reg = {u.config: u for u in units if u.bench == "reg"}
    jobs, union = [], {"sim": args.sim, "rid": args.rid, "out_root": args.out_root,
                       "rtl_patch": args.rtl_patch, "configs": []}
    for c in configs:
        if c not in t1:
            continue
        cmd = [MAKE, "--no-print-directory", "cov_report", f"SIM={args.sim}", "TB=t1", "COV=1",
               f"CONFIG={c}", f"COV_RID={args.rid}", f"OUT_DIR={os.path.join(args.out_root, t1[c].build)}"]
        if args.rtl_patch:
            cmd.append(f"RTL_PATCH={args.rtl_patch}")
        if c not in reg:
            cmd.append("COV_WITH=")
        jobs.append((f"cov-{c}", cmd))
        union["configs"].append({"config": c, "t1": t1[c].build,
                                 "reg": reg[c].build if c in reg else None})
    if write:
        with open(os.path.join(regdir, "union.json"), "w", encoding="utf-8") as fh:
            json.dump(union, fh, indent=1)
    ujob = None
    if args.sim in ("vcs", "verilator") and union["configs"]:
        ujob = ("cov-union", [sys.executable, os.path.abspath(__file__), "--union",
                              os.path.join(regdir, "union.json")])
    return jobs, ujob


# -----------------------------------------------------------------------------
# Running the jobs of a step
# -----------------------------------------------------------------------------
class Runner:
    def __init__(self, args, regdir):
        self.args, self.regdir = args, regdir
        self.logs = os.path.join(regdir, "logs")
        os.makedirs(self.logs, exist_ok=True)

    def record(self, step, jobs):
        with open(os.path.join(self.regdir, "commands.sh"), "a", encoding="utf-8") as fh:
            fh.write(f"# {step} at {time.strftime('%Y-%m-%d %H:%M:%S')}, from hw/ip/aou/dv\n")
            for _, cmd in jobs:
                fh.write(shlex.join(cmd) + "\n")
            fh.write("\n")

    def execute(self, step, jobs, lsf_job=False):
        """Run (name, cmd) jobs, all at once under LSF, else one after another; {name: rc}."""
        if lsf_job and self.args.lsf:
            jobs = [(n, bsub_prefix(self.args, n, os.path.join(self.logs, n + ".log")) + c)
                    for n, c in jobs]
        self.record(step, jobs)
        rcs, live = {}, []

        def start(name, cmd):
            log = os.path.join(self.logs, name + ".log")
            fh = open(log, "w", encoding="utf-8")  # pylint: disable=consider-using-with
            p = subprocess.Popen(cmd, cwd=UVM_ROOT, stdout=fh, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, start_new_session=True)
            live.append((name, p, fh, log, time.time()))

        def reap(block):
            for item in list(live):
                name, p, fh, log, t0 = item
                if p.poll() is None and not block:
                    continue
                rc = p.wait()
                fh.close()
                live.remove(item)
                rcs[name] = rc
                state = "ok" if rc == 0 else f"rc={rc}"
                print(f"regress: {step} {name}: {state} ({fmt_s(time.time() - t0)}); {log}",
                      flush=True)
                if block:
                    return

        try:
            for name, cmd in jobs:
                start(name, cmd)
                if not self.args.lsf:
                    reap(block=True)
            while live:
                reap(block=False)
                if live:
                    time.sleep(1)
        except KeyboardInterrupt:
            for _, p, _, _, _ in live:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            for _, p, fh, _, _ in live:
                p.wait()
                fh.close()
            die(f"interrupted in {step}; repeat with RID={self.args.rid} to resume")
        return rcs


def fmt_s(s):
    s = int(s)
    return f"{s // 3600}h{s % 3600 // 60:02d}m" if s >= 3600 else f"{s // 60}m{s % 60:02d}s"


def live_runs(out_root, builds):
    """Control files of run_list.py processes still running in these builds' out dirs."""
    live = []
    for b in builds:
        for ctl in glob.glob(os.path.join(out_root, b, "*.ctl")):
            try:
                with open(ctl, encoding="utf-8") as fh:
                    m = re.search(r"^# run_list pid (\d+)", fh.read(), re.M)
                if m:
                    os.kill(int(m.group(1)), 0)
                    live.append(ctl)
            except (OSError, ValueError):
                pass
    return live


def load_state(regdir):
    try:
        with open(os.path.join(regdir, "state.json"), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_state(regdir, state):
    with open(os.path.join(regdir, "state.json"), "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=1, sort_keys=True)


# -----------------------------------------------------------------------------
# Coverage union over the configurations
# -----------------------------------------------------------------------------
def union(spec_path):
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    sim, rid, out_root = spec["sim"], spec["rid"], spec["out_root"]
    udir = os.path.join(os.path.dirname(spec_path), "union")
    os.makedirs(udir, exist_ok=True)
    build_root = os.path.join(UVM_ROOT, "build")

    def run(cmd):
        print("+ " + shlex.join(cmd), flush=True)
        subprocess.run(cmd, cwd=UVM_ROOT, check=True)

    if sim == "vcs":
        tests, vdbs = [], []
        for c in spec["configs"]:
            path = os.path.join(out_root, c["t1"], "merged", "tests.txt")
            if not os.path.exists(path):
                sys.exit(f"union: no {path}; make cov_report for {c['config']} failed")
            with open(path, encoding="utf-8") as fh:
                tests += [ln for ln in fh.read().splitlines() if ln.strip()]
            vdbs += [os.path.join(build_root, b, "cov", "simv.vdb") for b in (c["t1"], c["reg"]) if b]
        with open(os.path.join(udir, "tests.txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(tests) + "\n")
        run(["urg", "-full64", "-dir", *vdbs, "-map", "AOU_CORE_TOP", "-tests",
             os.path.join(udir, "tests.txt"), "-format", "both", "-report", os.path.join(udir, "urg"),
             "-log", os.path.join(udir, "urg.log")])
        # The whole dashboard: its module-definition table is the first database's
        # modules only; the instance rows carry the union. urg merges a module of another
        # configuration only where its shape matches (warning UCAPI-MAP-SHAPEMISMATCH otherwise).
        with open(os.path.join(udir, "urg", "dashboard.txt"), encoding="utf-8") as fh:
            text = fh.read()
        text = text[text.find("Number of tests"):] if "Number of tests" in text else text
    else:
        dats = [os.path.join(out_root, c["t1"], "merged", "merged.dat") for c in spec["configs"]]
        missing = [d for d in dats if not os.path.exists(d)]
        if missing:
            sys.exit(f"union: no {missing[0]}; make cov_report failed for that config")
        merged = os.path.join(udir, "merged.dat")
        run(["verilator_coverage", "--write", merged, *dats])
        run(["verilator_coverage", "--write-info", os.path.join(udir, "merged.info"), merged])
        rtl = (os.path.join(build_root, spec["configs"][0]["t1"], "rtl") if spec["rtl_patch"] else ROOT)
        p = subprocess.run([sys.executable, os.path.join(UVM_ROOT, "scripts", "cov_summary.py"),
                            "--src-dir", os.path.join(rtl, "RTL"), merged], cwd=UVM_ROOT,
                           capture_output=True, text=True, check=True)
        text = p.stdout
    with open(os.path.join(udir, "summary.txt"), "w", encoding="utf-8") as fh:
        fh.write(text)
    print(text)

    # Functional coverage: every passing T1 run of this RID, all configurations.
    allpass = os.path.join(udir, "allpass")
    shutil.rmtree(allpass, ignore_errors=True)
    os.makedirs(allpass)
    for c in spec["configs"]:
        for d in passing_runs.scan(os.path.join(out_root, c["t1"]), rid)[0]:
            os.symlink(d, os.path.join(allpass, f"{c['config']}.{os.path.basename(d)}"))
    # The links go once the report is written: tools that walk out/** would count those
    # runs twice.
    try:
        run([sys.executable, os.path.join(UVM_ROOT, "scripts", "fc_report.py"), allpass,
             "-o", os.path.join(udir, "fc"), "--rid", rid])
    finally:
        shutil.rmtree(allpass, ignore_errors=True)
    return 0


# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
def rerun_hint(args, u, r):
    cmd = ["make", "run", f"SIM={args.sim}", f"TB={u.tb}"]
    if u.config:
        cmd.append(f"CONFIG={u.config}")
    if u.bench == "assert":
        cmd.append("RTL_ASSERT=1")
    if args.cov == "1" and u.bench in ("t1", "reg"):
        cmd.append("COV=1")
    if args.rtl_patch and u.config:
        cmd.append(f"RTL_PATCH={args.rtl_patch}")
    cmd += [f"TEST={r.get('test')}", f"SEED={r.get('seed')}"]
    if r.get("plusargs"):
        cmd.append(f"PLUSARGS={r['plusargs']}")
    cmd += [f"RID={args.rid}-w", "WAVES=1"]
    return shlex.join(cmd)


def summary(args, units, notes, state, regdir):
    lines = [f"# Regression {args.rid}", "",
             f"SIM={args.sim}, {len({u.config for u in units if u.config})} configuration(s), "
             f"{len(units)} build(s); results in out/<build>/results_*.rid.{args.rid}.csv", ""]
    lines += [f"- {n}" for n in notes] + ([""] if notes else [])
    bad, missing, total = [], [], {"runs": 0, "PASS": 0, "XFAIL": 0, "FAIL": 0, "XPASS": 0}
    for bench in BENCHES:
        us = [u for u in units if u.bench == bench]
        if not us:
            continue
        lines += [f"## {SECTION[bench]}", "", "| build | runs | PASS | XFAIL | FAIL | XPASS |",
                  "|---|---|---|---|---|---|"]
        sec = dict.fromkeys(total, 0)
        for u in us:
            rows = read_rows(args.out_root, u.build, args.rid)
            if not rows:
                rc = state.get("builds", {}).get(u.build)
                why = (f"build failed (rc={rc}, {os.path.join(regdir, 'logs', 'build-' + u.label + '.log')})"
                       if rc not in (None, 0) else
                       f"no results for rid {args.rid} (see {os.path.join(regdir, 'logs', 'run-' + u.label + '.log')})")
                missing.append(f"{u.build}: {why}")
                lines.append(f"| {u.build} | - | - | - | - | - |")
                continue
            c = dict.fromkeys(total, 0)
            for r in rows:
                base, xpass = verdict(r.get("status"))
                c["runs"] += 1
                c[base] += 1
                c["XPASS"] += xpass
                if base == "FAIL" or xpass:
                    bad.append((u, r))
            want = planned_runs(args, u)
            if want is not None and c["runs"] < want:
                rc = state.get("runs", {}).get(u.build)
                missing.append(f"{u.build}: {c['runs']} of {want} runs have results (drained or "
                               f"interrupted{'' if rc is None else f', run_list.py rc={rc}'}; see "
                               f"{os.path.join(regdir, 'logs', 'run-' + u.label + '.log')})")
            for k in c:
                sec[k] += c[k]
            lines.append(f"| {u.build} | " + " | ".join(str(c[k]) for k in total) + " |")
        for k in sec:
            total[k] += sec[k]
        lines += [f"| total | " + " | ".join(str(sec[k]) for k in total) + " |", ""]
    lines.append("XPASS runs are counted under their verdict too: an expected failure that did "
                 "not occur, whose expected_fail.yaml entry needs review.")
    lines.append("")
    if bad:
        lines += [f"## FAIL and XPASS runs ({len(bad)})", ""]
        for u, r in bad:
            lines.append(f"- {r.get('status')} {u.build} {r.get('name') or r.get('test')} "
                         f"seed={r.get('seed')}: {r.get('run_dir')}")
            lines.append(f"  rerun with waves: `{rerun_hint(args, u, r)}`")
        again = shlex.join(["make", "regress", f"SIM={args.sim}", f"RERUN_FAILED={args.rid}"]
                           + (["COV=1"] if args.cov == "1" else [])
                           + ([f"RTL_PATCH={args.rtl_patch}"] if args.rtl_patch else []))
        lines += ["", f"Rerun every failing scenario (all its seeds) under a new RID: `{again}`", ""]
    if missing:
        lines += [f"## Builds with missing results ({len(missing)})", ""] + [f"- {m}" for m in missing] + [""]
    if state.get("cov_failed"):
        lines += ["## Coverage", "", f"- failed: {', '.join(state['cov_failed'])} "
                                     f"(logs in {os.path.join(regdir, 'logs')})", ""]
    elif args.cov == "1" and os.path.isdir(os.path.join(regdir, "union")):
        lines += ["## Coverage", "", f"- per configuration: out/<T1 cov build>/merged/; union over "
                                     f"the configurations: {os.path.join(regdir, 'union')}", ""]
    ok = not bad and not missing and not state.get("cov_failed")
    lines.append(f"Result: {'PASS' if ok else 'FAIL'}: {total['runs']} runs, {total['PASS']} PASS, "
                 f"{total['XFAIL']} XFAIL, {total['FAIL']} FAIL, {total['XPASS']} XPASS"
                 + (f", {len(missing)} build(s) with missing results" if missing else ""))
    text = "\n".join(lines) + "\n"
    with open(os.path.join(regdir, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write(text)
    print(text, end="")
    print(f"regress: summary in {os.path.join(regdir, 'summary.md')}")
    return 0 if ok else 1


# -----------------------------------------------------------------------------
def words(text):
    return text.split() if text else []


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", default="vcs" if shutil.which("vcs") else "verilator",
                    choices=["vcs", "verilator"])
    ap.add_argument("--rid", default="", help="regression ID (default r<yymmdd>-<hhmm>); reuse it "
                                              "to resume")
    ap.add_argument("--configs", default="", help="CONFIGs, space separated (default: every "
                                                   "configuration, make configs)")
    ap.add_argument("--benches", default="", help=f"benches, space separated (default: {' '.join(BENCHES)})")
    ap.add_argument("--cov", default="0", choices=["0", "1"], help="COV=1 builds and runs, then the "
                                                                   "cov step")
    ap.add_argument("--rtl-patch", default="", help="RTL_PATCH=<absolute path> for the DUT builds")
    ap.add_argument("--items", default="", help="groups or scenarios, space separated, run on every "
                                                 "bench whose testlist defines them (default: everything)")
    ap.add_argument("--rerun-failed", default="", metavar="RID",
                    help="run only the scenarios that had a FAIL or XPASS run in that earlier RID")
    ap.add_argument("--reseed", type=int, default=0, help="run_list.py --reseed N")
    ap.add_argument("-j", "--jobs", type=int, default=0,
                    help="runs in flight per run_list.py (default 8 under LSF, else the CPU count)")
    ap.add_argument("--steps", default="", help=f"comma separated, of {','.join(STEPS)} (default: "
                                                 "build,run,summary, plus cov with COV=1)")
    ap.add_argument("--lsf", default="", choices=["", "0", "1"],
                    help="1: start the jobs at once, LSF takes them (default: 1 when bsub is on PATH)")
    ap.add_argument("--cov-mem", default="16GB", help="LSF memory of each coverage job, with a unit")
    ap.add_argument("--dry-run", action="store_true", help="print the plan; build and run nothing")
    ap.add_argument("--out-root", default=os.path.join(UVM_ROOT, "out"), help=argparse.SUPPRESS)
    ap.add_argument("--union", metavar="JSON", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    if args.union:
        return union(args.union)

    args.out_root = os.path.abspath(args.out_root)
    args.rid = args.rid or time.strftime("r%y%m%d-%H%M")
    for name, rid in (("RID", args.rid), ("RERUN_FAILED", args.rerun_failed)):
        if rid and not RID_RE.match(rid):
            die(f"{name} '{rid}': letters, digits, _ and - only")
    if args.rerun_failed == args.rid:
        die("RERUN_FAILED needs a new RID, not the one it reruns")
    if args.rerun_failed and args.items:
        die("give ITEMS or RERUN_FAILED, not both")
    if not re.fullmatch(r"[0-9]+(MB|GB)", args.cov_mem):
        die(f"COV_MEM needs a unit (16GB, 16000MB), not '{args.cov_mem}'")
    if args.rtl_patch:
        args.rtl_patch = os.path.abspath(args.rtl_patch)
        if not os.path.isfile(args.rtl_patch):
            die(f"no patch {args.rtl_patch}")
    args.lsf = (args.lsf or os.environ.get("LSF") or ("1" if shutil.which("bsub") else "0")) == "1"
    args.jobs = args.jobs or (8 if args.lsf else os.cpu_count() or 1)
    args.configs, args.benches, args.items = words(args.configs), words(args.benches), words(args.items)
    steps = [s.strip() for s in args.steps.split(",") if s.strip()] if args.steps else \
        ["build", "run"] + (["cov"] if args.cov == "1" else []) + ["summary"]
    bad = [s for s in steps if s not in STEPS]
    if bad:
        die(f"unknown STEPS {','.join(bad)}; use some of {','.join(STEPS)}")
    if "cov" in steps and args.cov != "1":
        die("the cov step needs COV=1")
    steps = [s for s in STEPS if s in steps]

    units, configs, notes = plan(args)
    regdir = os.path.join(args.out_root, "regress", args.rid)
    head = (f"regress: rid {args.rid}, SIM={args.sim}, {'LSF' if args.lsf else 'this host (LSF=0)'}, "
            f"steps {','.join(steps)}; {len(units)} build(s)")
    print(head)
    for n in notes:
        print(f"regress: note: {n}")

    if args.dry_run:
        total = 0
        for step in steps:
            if step == "build":
                jobs = [(u.label, build_cmd(args, u)) for u in units]
            elif step == "run":
                jobs = [(u.label, run_cmd(args, u)) for u in units]
            elif step == "cov":
                jobs, ujob = cov_cmds(args, units, configs, regdir, write=False)
                jobs += [ujob] if ujob else []
            else:
                print(f"\n# summary: read out/<build>/results_*.rid.{args.rid}.csv of the "
                      f"{len(units)} builds, write {os.path.join(regdir, 'summary.md')}")
                continue
            print(f"\n# {step}: {len(jobs)} job(s)" + (", through LSF" if step == "cov" and args.lsf else ""))
            for name, cmd in jobs:
                extra = ""
                if step == "run":
                    p = subprocess.run(cmd + ["--dry-run"], cwd=UVM_ROOT, capture_output=True,
                                       text=True, check=False)
                    m = re.search(r"^(\d+) run\(s\)", p.stdout, re.M)
                    n = int(m.group(1)) if m else 0
                    total += n
                    extra = f"   # {n} run(s)" if m else f"   # {(p.stderr.strip() or '?').splitlines()[-1]}"
                print(shlex.join(cmd).replace(UVM_ROOT + os.sep, "") + extra)
        if "run" in steps:
            print(f"\n# {total} run(s) in all")
        return 0

    os.makedirs(regdir, exist_ok=True)
    state = load_state(regdir)
    runner = Runner(args, regdir)
    t_start = time.time()
    rc = 0
    for step in steps:
        t0 = time.time()
        if step == "summary":
            rc = summary(args, units, notes, state, regdir)
            continue
        print(f"regress: {step} started {time.strftime('%Y-%m-%d %H:%M:%S')}", flush=True)
        if step == "build":
            live = live_runs(args.out_root, [u.build for u in units])
            if live:
                die(f"run_list.py is still running ({' '.join(live[:3])}); a build now would "
                    f"replace the simulator under its runs")
            rcs = runner.execute("build", [("build-" + u.label, build_cmd(args, u)) for u in units])
            state.setdefault("builds", {}).update({u.build: rcs["build-" + u.label] for u in units})
            save_state(regdir, state)
            failed = [u for u in units if rcs["build-" + u.label]]
            units_ok = [u for u in units if u not in failed]
            if failed:
                print(f"regress: {len(failed)} build(s) failed; their runs are skipped: "
                      + " ".join(u.build for u in failed))
        elif step == "run":
            todo = []
            for u in units:
                if "build" in steps and u not in units_ok:
                    continue
                have = len(read_rows(args.out_root, u.build, args.rid))
                if have:
                    # A drained or interrupted run_list.py leaves results short of its plan.
                    want = planned_runs(args, u)
                    if want is not None and have >= want:
                        print(f"regress: run {u.label}: {u.build} has results for rid {args.rid}; skipped")
                        continue
                    print(f"regress: run {u.label}: {u.build} has {have} of {want} runs for rid "
                          f"{args.rid}; running it again")
                todo.append(("run-" + u.label, run_cmd(args, u)))
            print(f"regress: {len(todo)} run_list.py job(s), -j {args.jobs} each; control files "
                  f"out/<build>/{args.rid}.ctl (scripts/run_ctl.py)", flush=True)
            rcs = runner.execute("run", todo)
            state.setdefault("runs", {}).update(
                {u.build: rcs["run-" + u.label] for u in units if "run-" + u.label in rcs})
            save_state(regdir, state)
        elif step == "cov":
            jobs, ujob = cov_cmds(args, units, configs, regdir)
            rcs = runner.execute("cov", jobs, lsf_job=True)
            failed = [n for n, r in rcs.items() if r]
            if ujob and not failed:
                failed += [n for n, r in runner.execute("cov", [ujob], lsf_job=True).items() if r]
            elif not ujob:
                print(f"regress: no coverage union for SIM={args.sim}")
            state["cov_failed"] = failed
            save_state(regdir, state)
        print(f"regress: {step} done in {fmt_s(time.time() - t0)}", flush=True)
    print(f"regress: rid {args.rid} took {fmt_s(time.time() - t_start)}; logs in {regdir}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
