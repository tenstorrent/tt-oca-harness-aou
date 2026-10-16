#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Run the bench's (target, scenario, seed) grid through tt-oca-harness run_dv.py.

run_dv.py's regression mode assigns random seeds, so a run that is to be
compared with the standalone baseline seed for seed is swept one leaf at a
time: for every target, one `--build-only` invocation, then for every
scenario of the group and every seed in its `seed`..`seed+reseed-1` range one
`--run-only --stage sim --items <scenario> --seed <n>` invocation, at most -j
at a time (the executor, `lsf` by default, runs the simulation itself). The
run directories go under <out>/<target>/<scenario>__s<seed>; afterwards

    python3 scripts/judge_run.py --root <harness> <out>

grades every leaf with the bench's grader and writes results.csv per target.

The harness checkout is given with --root (or $OCAH_ROOT); the bench must be
vendored into it (duts.toml entries aou, aou_reg, aou_l3_unit,
aou_axi_selftest). The group and the targets default to the whole bench on
every non-assert target; `--group assertions --targets <c>-assert ...` sweeps
the assertion scenarios. Scenarios pinned to another target and blocked
scenarios are skipped, as run_list.py skips them.
"""

import argparse
import concurrent.futures
import os
import shlex
import subprocess
import sys
import threading
import time

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(UVM_ROOT, "scripts"))
import sim_cfg  # noqa: E402
import testlist  # noqa: E402

DUT_OF = {"t1": "aou", "reg": "aou_reg", "l3_unit": "aou_l3_unit", "axi_selftest": "aou_axi_selftest"}


def run_dv_cmd(args, extra):
    cmd = [sys.executable, os.path.join(args.root, "tools", "dv", "run_dv.py"),
           "--dut", DUT_OF[args.tb], "--framework", "uvm", "--tool", args.sim]
    if args.executor:
        cmd += ["--executor", args.executor]
    cmd += extra + args.extra
    return cmd


def run(cmd, log_path, dry_run, cwd):
    if dry_run:
        print(" ".join(shlex.quote(c) for c in cmd))
        return 0
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w", encoding="utf-8") as fh:
        fh.write(" ".join(shlex.quote(c) for c in cmd) + "\n\n")
        fh.flush()
        try:
            return subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, cwd=cwd).returncode
        except OSError as e:
            fh.write(f"sweep: {e}\n")
            return 127


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=os.environ.get("OCAH_ROOT", ""),
                    help="tt-oca-harness checkout with the bench vendored (default: $OCAH_ROOT)")
    ap.add_argument("--tb", default="t1", choices=sorted(DUT_OF))
    ap.add_argument("--sim", default="vcs")
    ap.add_argument("--executor", default="lsf", help="run_dv executor (default lsf; '' for the default)")
    ap.add_argument("--group", default="all", help="testlist group or scenario names, comma-separated")
    ap.add_argument("--targets", nargs="*", help="targets to sweep (default: every non-assert target)")
    ap.add_argument("--seeds", type=int, default=0,
                    help="cap the seeds per scenario (default: the scenario's seed..seed+reseed-1)")
    ap.add_argument("--out", default="", help="run directories go here (default: <root>/build/aou-sweep)")
    ap.add_argument("-j", "--jobs", type=int, default=16, help="concurrent run_dv invocations")
    ap.add_argument("--no-build", action="store_true", help="skip the --build-only pass")
    ap.add_argument("--dry-run", action="store_true", help="print the commands only")
    ap.add_argument("extra", nargs="*", help="extra run_dv.py options after --")
    args = ap.parse_args(argv)
    if not args.root or not os.path.isfile(os.path.join(args.root, "tools", "dv", "run_dv.py")):
        ap.error("--root must name a tt-oca-harness checkout (tools/dv/run_dv.py)")
    args.root = os.path.abspath(args.root)
    args.out = os.path.abspath(args.out or os.path.join(args.root, "build", "aou-sweep"))

    cfg = sim_cfg.load(args.tb)
    all_targets = sim_cfg.targets(cfg)
    targets = args.targets or [t for t in all_targets if not t.endswith("-assert")]
    for t in targets:
        if t not in all_targets:
            ap.error(f"unknown target {t}; targets: {' '.join(all_targets)}")
    path = os.path.join(UVM_ROOT, cfg["testlist"]["path"])
    items = [x for x in args.group.split(",") if x]
    scenarios = [e for e in testlist.select(path, items) if not e["blocked"]]

    jobs = []
    for target in targets:
        for e in scenarios:
            if e["target"] and e["target"] != target:
                continue
            seeds = e["seeds"][:args.seeds] if args.seeds else e["seeds"]
            for s in seeds:
                jobs.append((target, e["name"], s))
    print(f"sweep: {len(jobs)} leaf run(s) on {len(targets)} target(s) -> {args.out}", flush=True)

    if not args.no_build:
        for target in targets:
            cmd = run_dv_cmd(args, ["--build-only", "--target", target,
                                    "--run-dir", os.path.join(args.out, target, "build")])
            rc = run(cmd, os.path.join(args.out, target, "build", "sweep.log"), args.dry_run, args.root)
            print(f"build  {target}: {'ok' if rc == 0 else f'FAILED rc={rc}'}", flush=True)
            if rc != 0 and not args.dry_run:
                return 1

    lock = threading.Lock()
    done = [0, 0]

    def one(job):
        target, name, seed = job
        run_dir = os.path.join(args.out, target, f"{name}__s{seed}")
        cmd = run_dv_cmd(args, ["--run-only", "--stage", "sim", "--items", name, "--seed", str(seed),
                                "--target", target, "--run-dir", run_dir])
        t0 = time.time()
        rc = run(cmd, os.path.join(run_dir, "sweep.log"), args.dry_run, args.root)
        with lock:
            done[0] += 1
            done[1] += rc != 0
            print(f"[{done[0]}/{len(jobs)}] {'ok ' if rc == 0 else 'rc=' + str(rc)} {target} {name} "
                  f"seed={seed} ({time.time() - t0:.0f}s)", flush=True)
        return rc

    with concurrent.futures.ThreadPoolExecutor(max_workers=1 if args.dry_run else max(1, args.jobs)) as ex:
        list(ex.map(one, jobs))
    print(f"sweep: {done[0]} run(s), {done[1]} with a non-zero run_dv status; "
          f"judge with: python3 scripts/judge_run.py --root {args.root} {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
