#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""List the run directories under out/<build>/ whose verdict is PASS.

Coverage merges only passing runs: a FAIL or XFAIL run stopped early or went
somewhere wrong, and an unjudged run (no verdict.txt) can't be trusted. `make
run` writes each run's check_run.py verdict to <run>/verdict.txt.

  passing_runs.py out/vcs-cov                          # run directories
  passing_runs.py out/vcs-cov --file coverage.dat      # <run>/coverage.dat that exist
  passing_runs.py out/vcs-cov --names --prefix DB/     # DB/<run name>, for urg -tests
"""

import argparse
import glob
import os
import sys


def scan(out_dir):
    """(passing run directories, run count per verdict) for the runs under out_dir."""
    counts = {"PASS": 0, "XFAIL": 0, "FAIL": 0, "XPASS": 0, "unjudged": 0}
    passing = []
    for run in sorted(glob.glob(os.path.join(out_dir, "*.rid.*"))):
        if not os.path.isdir(run):
            continue
        verdict = "unjudged"
        vfile = os.path.join(run, "verdict.txt")
        if os.path.exists(vfile):
            # XPASS notes come before the verdict line, so take the last verdict word.
            with open(vfile, encoding="utf-8") as fh:
                words = [ln.split(":", 1)[0].strip() for ln in fh]
            words = [w for w in words if w in ("PASS", "XFAIL", "FAIL")]
            verdict = words[-1] if words else "unjudged"
        counts[verdict] += 1
        if verdict == "PASS":
            passing.append(run)
    return passing, counts


def summary(counts):
    """The merged/excluded line every coverage report prints."""
    excluded = sum(v for k, v in counts.items() if k != "PASS")
    detail = ", ".join(f"{v} {k}" for k, v in counts.items() if k != "PASS" and v)
    return (f"coverage: {counts['PASS']} passing run(s) merged; {excluded} excluded"
            + (f" ({detail})" if detail else ""))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out_dir")
    ap.add_argument("--file", help="print <run>/<FILE> (glob allowed) instead of the run directory")
    ap.add_argument("--names", action="store_true", help="print run names instead of paths")
    ap.add_argument("--prefix", default="", help="prefix for each printed name")
    args = ap.parse_args()

    passing, counts = scan(args.out_dir)
    for run in passing:
        if args.file:
            for f in sorted(glob.glob(os.path.join(run, args.file))):
                print(f)
        elif args.names:
            print(args.prefix + os.path.basename(run))
        else:
            print(run)
    print(summary(counts), file=sys.stderr)


if __name__ == "__main__":
    main()
