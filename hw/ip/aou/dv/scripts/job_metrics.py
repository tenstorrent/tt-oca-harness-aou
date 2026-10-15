#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Append one JSON line describing a finished build or run to the metrics file.

The output file holds the job's output, `/usr/bin/time -v` (or BSD `-l`)
statistics (peak RSS) and, for an LSF job, LSF's resource usage summary (CPU,
run time, host). For a local run the caller also passes the wall time it
measured.
"""

import argparse
import json
import re
import socket
import time

FIELDS = {
    "cpu_s": r"CPU time\s*:\s*([\d.]+) sec",
    "max_mem_mb": r"Max Memory\s*:\s*([\d.]+) MB",
    "run_s": r"Run time\s*:\s*([\d.]+) sec",
    "req_mem_gb": r"Total Requested Memory\s*:\s*([\d.]+) GB",
    "max_threads": r"Max Threads\s*:\s*(\d+)",
    "max_rss_kb": r"Maximum resident set size \(kbytes\):\s*(\d+)",
}


def parse_lsf(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    out = {}
    for key, pattern in FIELDS.items():
        m = re.search(pattern, text)
        if m:
            out[key] = float(m.group(1))
    # BSD time -l (macOS) reports peak RSS in bytes.
    m = re.search(r"^\s*(\d+)\s+maximum resident set size", text, re.M)
    if m and "max_rss_kb" not in out:
        out["max_rss_kb"] = float(m.group(1)) / 1024
    m = re.search(r"executed on host\(s\) <(?:\d+\*)?([^>]+)>", text)
    if m:
        out["host"] = m.group(1)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kind", required=True, help="build or run")
    ap.add_argument("--sim", required=True)
    ap.add_argument("--name", required=True, help="build config or test_seed")
    ap.add_argument("--rc", type=int, required=True)
    ap.add_argument("--lsf-out", help="LSF -o output file")
    ap.add_argument("--wall-s", type=float, help="wall time of a local run")
    args = ap.parse_args()

    rec = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "kind": args.kind, "sim": args.sim,
           "name": args.name, "rc": args.rc}
    rec["where"] = "local" if args.wall_s is not None else "lsf"
    if args.lsf_out:
        try:
            rec.update(parse_lsf(args.lsf_out))
        except OSError:
            pass
    if args.wall_s is not None:
        rec["host"] = socket.gethostname()
        rec["run_s"] = args.wall_s
    print(json.dumps(rec, sort_keys=True))


if __name__ == "__main__":
    main()
