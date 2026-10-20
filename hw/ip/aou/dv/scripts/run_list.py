#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Run scenarios of the TOML testlists through `make run`, in parallel.

    run_list.py [--tb t1] [--target 1x512-sp64] [--items <group|scenario> ...] [testlist ...]

The testlists are the harness-schema TOML of testlists/ (scripts/testlist.py):
`[[tests]]` scenarios with module.uvm, seed/reseed, args, target, tags, and
`[[groups]]`. Without a testlist argument the bench's aggregate (the [testlist]
of its sim config: all.toml for TB=t1, registers.toml for TB=reg, ...) is read;
--items names the groups or scenarios to run (default: every scenario the
lists define). A scenario carries seeds seed..seed+reseed-1 (--reseed N caps
that at N). A scenario whose target differs from --target is skipped (TB=t1 and
reg), as is one tagged `blocked` (its reason is in testlists/plan_ids.yaml).
Each run is judged by scripts/check_run.py (make run calls it); results go to
out/<build>/results.csv with the scenario name, its test class and plan IDs.
The build must exist (make build ... first); it is never rebuilt here, but a
build older than its sources or compile defines is reported once, loudly, at
the start (make stale-check).
Several testlists share one pool of -j runs; with --per-list each list a
scenario is defined in (an area of all.toml, say) gets its own
results_<list>.csv and summary line.
Exit status 0 when every run is PASS or XFAIL and drain left none out.
"""

import argparse
import csv
import json
import os
import queue
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_ctl  # noqa: E402
import sim_cfg  # noqa: E402
import testlist  # noqa: E402

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLL_S = 1.0
# GNU Make 4: $MAKE when set (as under make), else gmake where installed (macOS ships 3.81).
MAKE = os.environ.get("MAKE") or shutil.which("gmake") or "make"
# What `bsub -K` prints as a job is submitted and dispatched (the Makefile passes it through).
JOB_ID_RE = re.compile(r"^Job <(\d+)> is submitted")
JOB_START_RE = re.compile(r"^<<Starting on ")

CONTROL_HELP = """\
live control:
  At startup run_list.py writes a control file, out/<build>/<rid>.ctl (or
  --ctl PATH), and prints its path. It re-reads the file every second and
  applies each change, logging it with a timestamp and old -> new values on
  stdout and in the run log next to the file (<rid>.log). The file is removed
  when run_list exits (normally, on error or on SIGTERM), so an existing file
  means a live run. Edit it by hand or with scripts/run_ctl.py, which rewrites
  it atomically:

    scripts/run_ctl.py out/<build>/<rid>.ctl jobs=20

  jobs=N        runs in flight at most; lowering it never kills a running job
  pause=1       stop launching (running jobs finish); pause=0 resumes
  drain=1       let running jobs finish, then exit without launching the rest
  priority=P    scheduler priority of runs launched from now on (make
                JOB_PRIORITY; bsub -sp under LSF)
  queue=Q       scheduler queue of runs launched from now on (make JOB_QUEUE;
                bsub -q under LSF)
  order=O       fifo, shortest (by past run time in build/metrics.jsonl) or
                failed-first (tests that failed in earlier results or this run)

  When the site defines JOB_MODIFY_PRIORITY / JOB_MODIFY_QUEUE (site/site.mk,
  e.g. `bmod -sp {priority} {job}`), a priority or queue change also goes to
  this process's own runs that are submitted but not yet dispatched. Jobs this
  process did not submit are never touched.

  Signals: SIGUSR1 raises jobs by 1, SIGUSR2 lowers it by 1 (kill -USR1 <pid>).
"""


class Run:
    """One scenario/seed. job_id and started come from make's output while it runs."""

    def __init__(self, idx, lst, test, seed, plusargs, plan_ids, name=None):
        self.idx, self.lst = idx, lst
        self.test, self.seed, self.plusargs, self.plan_ids = test, seed, plusargs, plan_ids
        self.name = name or test
        self.job_id, self.started, self.run_dir, self.status = None, False, "", ""

    def result(self):
        return self.test, self.seed, self.plusargs, self.status, self.plan_ids, self.run_dir, self.name


def build_vars(args):
    """The make variables that select the build."""
    out = [f"TB={args.tb}", f"SIM={args.sim}", f"CONFIG={args.config}", f"COV={args.cov}"]
    if args.rtl_assert:
        out.append("RTL_ASSERT=1")
    if args.escape:
        out.append(f"ESCAPE={args.escape}")
    if args.rtl_patch:
        out.append(f"RTL_PATCH={args.rtl_patch}")
    if args.axi4pc:
        out.append(f"AXI4PC={args.axi4pc}")
    return out


def stale_warning(args):
    """make stale-check's warning for this build, or '' (current, no build, or make failed)."""
    cmd = [MAKE, "-s", "--no-print-directory", "stale-check", *build_vars(args)]
    try:
        p = subprocess.run(cmd, cwd=UVM_ROOT, capture_output=True, text=True, check=False)
    except OSError:
        return ""
    return (p.stdout + p.stderr).strip() if p.returncode == 0 else ""


def make_cmd(args, run, priority, queue_name):
    # The build was checked for staleness once at start; don't repeat it per run.
    cmd = [MAKE, "--no-print-directory", "run", *build_vars(args), f"TEST={run.test}", f"SEED={run.seed}",
           f"RID={args.rid}", "STALE_CHECK=0"]
    if args.out_dir:
        cmd.append(f"OUT_DIR={args.out_dir}")
    if args.fdi_enc:
        cmd.append(f"FDI_ENC={args.fdi_enc}")
    if args.lsf_extra_opts:
        cmd.append(f"LSF_EXTRA_OPTS={args.lsf_extra_opts}")
    if priority:
        cmd.append(f"JOB_PRIORITY={priority}")
    if queue_name:
        cmd.append(f"JOB_QUEUE={queue_name}")
    if run.plusargs:
        cmd.append(f"PLUSARGS={run.plusargs}")
    return cmd


def run_one(cmd, run, done):
    out = []
    try:
        with subprocess.Popen(cmd, cwd=UVM_ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, bufsize=1) as p:
            for line in p.stdout:
                out.append(line)
                m = JOB_ID_RE.match(line)
                if m:
                    run.job_id = m.group(1)
                elif JOB_START_RE.match(line):
                    run.started = True
                else:
                    m = re.match(r"Run directory: (\S+)", line)
                    if m:
                        run.run_dir = m.group(1)
    except OSError as e:
        out.append(f"run_list: {e}\n")
    run.status = verdict("".join(out))
    done.put(run)


def verdict(text):
    """The run's status from make run's output: PASS, XFAIL or FAIL, +XPASS if XPASS notes."""
    # XPASS lines are notes check_run.py prints before the verdict, not a verdict.
    m = re.search(r"^(PASS|XFAIL|FAIL)\b.*$", text, re.M)
    status = m.group(1) if m else "FAIL"
    if re.search(r"^XPASS", text, re.M) and status != "FAIL":
        status += "+XPASS"
    return status


def show(value):
    return run_ctl.text(value) or "''"


class Log:
    """Prints to stdout and appends to the run log."""

    def __init__(self, path):
        self.fh = open(path, "a", encoding="utf-8")  # pylint: disable=consider-using-with

    def __call__(self, msg, stamp=True):
        line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}" if stamp else msg
        print(line, flush=True)
        self.fh.write(line + "\n")
        self.fh.flush()


class Control:
    """The live settings, kept in step with the control file."""

    def __init__(self, path, log, initial):
        self.path, self.log = path, log
        self.state = dict(initial)
        self.seen = {k: run_ctl.text(v) for k, v in initial.items()}
        self.bad = {}

    def get(self, key):
        return self.state[key]

    def poll(self):
        """Apply what changed in the file since it was last read; return [(key, old, new)]."""
        try:
            values = run_ctl.read(self.path)
        except FileNotFoundError:
            return []
        changes = []
        for key, raw in values.items():
            if self.seen.get(key) == raw:
                continue
            try:
                new = run_ctl.check(key, raw)
            except ValueError as e:
                if self.bad.get(key) != raw:
                    self.log(f"ctl: ignored {key}={raw}: {e}")
                    self.bad[key] = raw
                continue
            self.seen[key] = raw
            self.bad.pop(key, None)
            old = self.state[key]
            if new != old:
                self.state[key] = new
                self.log(f"ctl: {key} {show(old)} -> {show(new)} (control file)")
                changes.append((key, old, new))
        return changes

    def bump_jobs(self, delta, why):
        old = self.state["jobs"]
        new = max(1, old + delta)
        self.log(f"ctl: jobs {old} -> {new} ({why})")
        if new != old:
            self.state["jobs"] = new
            self.seen["jobs"] = str(new)
            run_ctl.write(self.path, {"jobs": new})


def ctl_paths(args, out_dir):
    """The control file and run log. Another live run_list with the same rid keeps its
    file; this process then gets <rid>.<pid>.ctl."""
    if args.ctl:
        ctl = os.path.abspath(args.ctl)
    else:
        ctl = os.path.join(out_dir, f"{args.rid}.ctl")
        owner = None
        try:
            with open(ctl, encoding="utf-8") as fh:
                m = re.search(r"^# run_list pid (\d+)", fh.read(), re.M)
                owner = int(m.group(1)) if m else None
        except FileNotFoundError:
            pass
        if owner and owner != os.getpid():
            try:
                os.kill(owner, 0)
                ctl = os.path.join(out_dir, f"{args.rid}.{os.getpid()}.ctl")
            except ProcessLookupError:
                pass
            except PermissionError:
                ctl = os.path.join(out_dir, f"{args.rid}.{os.getpid()}.ctl")
    return ctl, os.path.splitext(ctl)[0] + ".log"


def remove_ctl(path):
    """Delete the control file at exit, so run_ctl.py can't edit a file nobody reads. Only a
    file this process owns: another live run_list may have taken the path over."""
    try:
        with open(path, encoding="utf-8") as fh:
            m = re.search(r"^# run_list pid (\d+)", fh.read(), re.M)
        if m and int(m.group(1)) == os.getpid():
            os.remove(path)
    except FileNotFoundError:
        pass


def job_hooks(args):
    """The site's commands for changing a submitted job (none unless it defines them)."""
    cmd = [MAKE, "-s", "--no-print-directory", "job-hooks", f"TB={args.tb}", f"SIM={args.sim}",
           f"CONFIG={args.config}"]
    try:
        p = subprocess.run(cmd, cwd=UVM_ROOT, capture_output=True, text=True, check=False)
    except OSError:
        return {}
    hooks = {}
    for line in p.stdout.splitlines():
        key, _, value = line.partition("=")
        if key in ("JOB_MODIFY_PRIORITY", "JOB_MODIFY_QUEUE") and value.strip():
            hooks[key] = value.strip()
    return hooks


class Order:
    """Sort keys for the order setting."""

    def __init__(self, args, out_dir):
        self.args, self.out_dir = args, out_dir
        self._times, self._failed = None, None
        self.failed_now = set()

    def times(self):
        if self._times is None:
            runs = {}
            try:
                with open(os.path.join(UVM_ROOT, "build", "metrics.jsonl"), encoding="utf-8") as fh:
                    for line in fh:
                        try:
                            m = json.loads(line)
                        except ValueError:
                            continue
                        if m.get("kind") == "run" and m.get("sim") == self.args.sim and "run_s" in m:
                            runs.setdefault(m.get("name", "").split(".rid.")[0], []).append(float(m["run_s"]))
            except OSError:
                pass
            self._times = {t: sum(v) / len(v) for t, v in runs.items()}
        return self._times

    def failed(self):
        if self._failed is None:
            self._failed = set()
            for name in os.listdir(self.out_dir):
                if re.fullmatch(r"results(_.*)?\.csv", name):
                    with open(os.path.join(self.out_dir, name), newline="", encoding="utf-8") as fh:
                        self._failed |= {row.get("test") for row in csv.DictReader(fh)
                                         if not row.get("status", "").startswith(("PASS", "XFAIL"))}
        return self._failed

    def key(self, order):
        if order == "shortest":
            times = self.times()
            return lambda r: (times.get(r.test, float("inf")), r.idx)
        if order == "failed-first":
            failed = self.failed() | self.failed_now
            return lambda r: (r.test not in failed, r.idx)
        return lambda r: r.idx


def modify_pending(ctl, hooks, running, key, value):
    """Apply a priority/queue change to this process's submitted, undispatched jobs."""
    pending = sorted((r for r in running if r.job_id and not r.started), key=lambda r: r.idx)
    hook = hooks.get(f"JOB_MODIFY_{key.upper()}")
    if not pending:
        ctl.log(f"ctl: no submitted job of this run is waiting to start; {key} applies to new runs")
        return
    if not hook or not value:
        why = f"no JOB_MODIFY_{key.upper()} hook" if not hook else "no value to set"
        ctl.log(f"ctl: {len(pending)} pending job(s) keep their {key} ({why})")
        return
    for r in pending:
        cmd = [tok.format(job=r.job_id, **{key: value}) for tok in shlex.split(hook)]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, check=False)
            lines = (p.stdout + p.stderr).strip().splitlines()
            msg = f"rc={p.returncode} {lines[-1] if lines else ''}"
        except OSError as e:
            msg = str(e)
        ctl.log(f"ctl: {' '.join(cmd)}: {msg}")


def write_results(log, out_dir, name, group):
    rows = sorted((r.result() for r in group), key=lambda r: (r[0], r[2], int(r[1]) if r[1].isdigit() else r[1]))
    csv_path = os.path.join(out_dir, f"results_{name}.csv" if name else "results.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["test", "seed", "plusargs", "status", "plan_ids", "run_dir", "name"])
        w.writerows(rows)
    bad = [r for r in rows if not r[3].startswith(("PASS", "XFAIL"))]
    log(f"{len(rows) - len(bad)}/{len(rows)} PASS/XFAIL; results in {csv_path}", stamp=False)
    return bool(bad)


def schedule(args, ctl, order, runs):
    """Launch runs as the control settings allow until all are done (or drained)."""
    signals = []
    signal.signal(signal.SIGUSR1, lambda *_: signals.append(1))
    signal.signal(signal.SIGUSR2, lambda *_: signals.append(-1))
    hooks = None
    pending, running, results = list(runs), set(), []
    done = queue.Queue()
    while True:
        for key, _, new in ctl.poll():
            if key in ("priority", "queue"):
                hooks = job_hooks(args) if hooks is None else hooks
                modify_pending(ctl, hooks, running, key, new)
        while signals:
            delta = signals.pop(0)
            ctl.bump_jobs(delta, "SIGUSR1" if delta > 0 else "SIGUSR2")
        if not running and (not pending or ctl.get("drain")):
            return results, pending
        if not ctl.get("pause") and not ctl.get("drain"):
            keyfn = order.key(ctl.get("order"))
            while pending and len(running) < ctl.get("jobs"):
                r = min(pending, key=keyfn)
                pending.remove(r)
                running.add(r)
                cmd = make_cmd(args, r, ctl.get("priority"), ctl.get("queue"))
                threading.Thread(target=run_one, args=(cmd, r, done), daemon=True).start()
        try:
            r = done.get(timeout=POLL_S)
        except queue.Empty:
            continue
        while r is not None:
            running.discard(r)
            results.append(r)
            if not r.status.startswith(("PASS", "XFAIL")):
                order.failed_now.add(r.test)
            ctl.log(f"{r.status:6} {r.name} seed={r.seed} {r.plusargs} {r.run_dir}", stamp=False)
            try:
                r = done.get_nowait()
            except queue.Empty:
                r = None


def main():
    ap = argparse.ArgumentParser(description=__doc__, epilog=CONTROL_HELP,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runlist", nargs="*", help="testlist(s) (default: the bench's aggregate); all share "
                                                "one pool of -j runs")
    ap.add_argument("--items", nargs="+", default=None, metavar="ITEM",
                    help="groups or scenarios to run (default: every scenario of the lists)")
    ap.add_argument("--sim", default="vcs")
    ap.add_argument("--tb", default="t1", choices=["t1", "reg", "l3_unit", "axi_selftest"])
    ap.add_argument("--target", "--config", dest="target", default=None,
                    help="the build target ([targets.<name>] of the sim config; default: its "
                         "[defaults].target). <name>-assert is the RTL_ASSERT=1 build")
    ap.add_argument("--cov", default="0")
    ap.add_argument("--rid", default="rl")
    ap.add_argument("--rtl-assert", action="store_true",
                    help="run on the RTL_ASSERT=1 build (the RTL's ASSERTION_ON checks); the same as "
                         "a --target ending in -assert")
    ap.add_argument("--reseed", type=int, default=None,
                    help="run at most N seeds of each scenario (default: its reseed)")
    ap.add_argument("--axi4pc", default="", choices=["", "0", "1"],
                    help="make AXI4PC for the build (default: make's, on when .deps/BP063/ is there)")
    ap.add_argument("--escape", default="", help="run on the ESCAPE=<id> build (escape/)")
    ap.add_argument("--rtl-patch", default="", help="run on the RTL_PATCH=<absolute path> build")
    ap.add_argument("--fdi-enc", default="", choices=["", "SPEC", "RTL"],
                    help="FDI state encoding of every run (make FDI_ENC, +FDI_ENC)")
    ap.add_argument("--lsf-extra-opts", default=os.environ.get("LSF_EXTRA_OPTS", ""),
                    help="extra bsub options for every run (make LSF_EXTRA_OPTS; default: "
                         "$LSF_EXTRA_OPTS)")
    ap.add_argument("-j", "--jobs", type=int, default=8, help="concurrent runs at start (default 8)")
    ap.add_argument("--test", help="only this test")
    ap.add_argument("--dry-run", action="store_true", help="print the runs and exit")
    ap.add_argument("--per-list", action="store_true",
                    help="write results_<runlist>.csv per run list instead of one results.csv")
    ap.add_argument("--ctl", help="control file (default out/<build>/<rid>.ctl); the settings of an "
                                  "existing file are applied at start")
    ap.add_argument("--order", default="fifo", choices=run_ctl.ORDERS, help="launch order at start")
    ap.add_argument("--priority", default="", help="scheduler priority at start (JOB_PRIORITY)")
    ap.add_argument("--queue", default="", help="scheduler queue at start (JOB_QUEUE)")
    ap.add_argument("--out-dir", default="", help="run directories and results (default out/<build>)")
    args = ap.parse_args()
    if args.jobs < 1:
        ap.error("-j must be at least 1")
    for key in ("priority", "queue"):
        try:
            run_ctl.check(key, getattr(args, key))
        except ValueError as e:
            ap.error(str(e))
    if args.reseed is not None and args.reseed < 1:
        ap.error("--reseed must be at least 1")
    cfg = sim_cfg.load(args.tb)
    if not args.runlist:
        args.runlist = [os.path.join(UVM_ROOT, cfg["testlist"]["path"])]
    # The target selects the build: CONFIG, and RTL_ASSERT=1 for a <CONFIG>-assert target.
    if args.tb in ("t1", "reg"):
        target = args.target or sim_cfg.default_target(cfg)
        if args.rtl_assert and not target.endswith("-assert"):
            target += "-assert"
        if target not in sim_cfg.targets(cfg):
            ap.error(f"--target {target} is not a target of the TB={args.tb} sim config; "
                     f"one of {' '.join(sim_cfg.targets(cfg))}")
        args.rtl_assert = target.endswith("-assert")
        args.target = target
        args.config = target[:-len("-assert")] if args.rtl_assert else target
    else:
        args.target = args.config = "default"

    runs = []
    lists_of = {}
    try:
        for path in args.runlist:
            for e in testlist.select(path, args.items):
                if args.test and e["test"] != args.test:
                    continue
                lst = lists_of.setdefault(e["list"], len(lists_of))
                if e["blocked"]:
                    print(f"skip   {e['name']}: blocked: {e['blocked']}")
                elif e["tb_fixed"] and e["tb"] != args.tb:
                    print(f"skip   {e['name']}: tb {e['tb']} (running {args.tb})")
                elif args.tb in ("t1", "reg") and e["target"] and e["target"] != args.target:
                    print(f"skip   {e['name']}: target {e['target']} (running {args.target})")
                else:
                    seeds = e["seeds"][:args.reseed] if args.reseed else e["seeds"]
                    for s in seeds:
                        runs.append(Run(len(runs), lst, e["test"], str(s), e["plusargs"], e["plan_ids"], e["name"]))
    except testlist.TestlistError as e:
        ap.error(str(e))
    names = list(lists_of)
    if args.dry_run:
        for r in runs:
            print(f"run    {r.name} seed={r.seed} {r.plusargs}")
        print(f"{len(runs)} run(s)")
        return 0
    # From make, so the name follows every build variant (-axi4pc is on by default when BP063 is there).
    p = subprocess.run([MAKE, "-s", "--no-print-directory", "build-name", *build_vars(args)],
                       cwd=UVM_ROOT, capture_output=True, text=True, check=False)
    if p.returncode or not p.stdout.split():
        ap.error(f"make build-name: {(p.stderr.strip() or 'no build name').splitlines()[-1]}")
    build = p.stdout.split()[-1]
    out_dir = os.path.abspath(args.out_dir) if args.out_dir else os.path.join(UVM_ROOT, "out", build)
    if args.out_dir:
        args.out_dir = out_dir
    os.makedirs(out_dir, exist_ok=True)

    ctl_path, log_path = ctl_paths(args, out_dir)
    log = Log(log_path)
    ctl = Control(ctl_path, log, {"jobs": args.jobs, "pause": False, "drain": False,
                                  "priority": args.priority, "queue": args.queue, "order": args.order})
    if args.ctl and os.path.exists(ctl_path):
        ctl.seen = {}
        ctl.poll()
    run_ctl.write(ctl_path, ctl.state, header=[
        f"# run_list pid {os.getpid()}: {' '.join(args.runlist)} ({build}, rid {args.rid})",
        "# Edit and save, or: scripts/run_ctl.py <this file> jobs=N. See run_list.py --help."])
    log(f"run_list: {len(runs)} run(s) from {len(args.runlist)} list(s), pid {os.getpid()}, "
        f"jobs={ctl.get('jobs')}")
    log(f"run_list: control file {ctl_path}")
    log(f"run_list: run log {log_path}")
    stale = stale_warning(args)
    if stale:
        log(stale, stamp=False)

    # SIGTERM (e.g. bkill of the driver) must still reach the finally below.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        results, notrun = schedule(args, ctl, Order(args, out_dir), runs)
    finally:
        remove_ctl(ctl_path)
    if notrun:
        log(f"run_list: drained; {len(notrun)} run(s) not launched:")
        for r in sorted(notrun, key=lambda r: r.idx):
            log(f"notrun {r.test} seed={r.seed} {r.plusargs}", stamp=False)
    bad = bool(notrun)
    if args.per_list:
        for i, name in enumerate(names):
            bad |= write_results(log, out_dir, name, [r for r in results if r.lst == i])
    else:
        bad |= write_results(log, out_dir, None, results)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
