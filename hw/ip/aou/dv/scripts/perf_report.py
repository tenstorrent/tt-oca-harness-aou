#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Tabulate the performance data (plan 2.10) of aou_perf_test runs.

Reads out/<build>/aou_perf_test.*/perf.txt ("metric value" per line, written by
aou_perf_mon) from every run whose verdict.txt says PASS, and writes a Markdown
report: a summary per build (one row per build, the key metrics as columns)
and every metric in full. Every run that wrote perf.json, whatever its verdict,
also gets a row per window link in "Against the model": measured steady-state
bytes/cycle against the committed d2d_model target
(uvm/env/perf/aou_perf_targets.svh, scripts/perf_model.py), the ratio, the gate's
verdict (what aou_perf_chk decided in the run) and the run's verdict (PASS,
XFAIL with the known bug, FAIL). --rid limits both sections to one regression.

  perf_report.py [--out-dir out] [--rid RID] [-o out/perf_report.md]
"""

import argparse
import glob
import os
import re
import sys
from collections import defaultdict

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_model  # noqa: E402

# (column heading, metric, plan item)
SUMMARY = [
    ("wr B/cyc l2r", "bw_wr.l2r.bytes_per_cycle", "10.1"),
    ("wr B/cyc r2l", "bw_wr.r2l.bytes_per_cycle", "10.1"),
    ("rd B/cyc l2r", "bw_rd.l2r.bytes_per_cycle", "10.2"),
    ("rd B/cyc r2l", "bw_rd.r2l.bytes_per_cycle", "10.2"),
    ("mix B/cyc l2r+r2l", "bw_mix.total.bytes_per_cycle", "10.3"),
    ("wr lat l2r", "lat_wr.l2r.lat_avg", "10.4"),
    ("wr lat r2l", "lat_wr_r2l.r2l.lat_avg", "10.4"),
    ("rd lat l2r", "lat_rd.l2r.lat_avg", "10.5"),
    ("rd lat r2l", "lat_rd_r2l.r2l.lat_avg", "10.5"),
    ("crd ret avg", "bw_wr.credit_return.avg", "10.6"),
    ("drain grant->last", "drain.grant_to_last", "10.7"),
    ("TX flits/cyc (peak)", "bw_wr.dut_tx_flits_per_cycle", "10.8"),
    ("TX gran/flit", "bw_mix.dut_tx_granules_per_flit", "10.8"),
    ("RTT AR->FDI/far/FDI->R", "lat_rd.l2r.rt", "10.9"),
]


def mode_of(run_dir):
    try:
        text = open(os.path.join(run_dir, "run.sh"), encoding="utf-8").read()
    except OSError:
        return "?"
    m = re.search(r"\+perf_mode=(\w+)", text)
    return m.group(1) if m else "bw"


def passed(run_dir):
    try:
        return open(os.path.join(run_dir, "verdict.txt"), encoding="utf-8").read().startswith("PASS")
    except OSError:
        return False


def rid_ok(run_dir, rid):
    return not rid or f".rid.{rid}." in os.path.basename(run_dir)


def collect(out_dir, rid=None):
    """{build: {metric: [values]}} and per-build run counts."""
    data, runs = defaultdict(lambda: defaultdict(list)), defaultdict(int)
    for perf in sorted(glob.glob(os.path.join(out_dir, "*", "aou_perf_test.*", "perf.txt"))):
        run_dir = os.path.dirname(perf)
        if not passed(run_dir) or not rid_ok(run_dir, rid):
            continue
        build = os.path.basename(os.path.dirname(run_dir))
        runs[build] += 1
        vals = {}
        for line in open(perf, encoding="utf-8"):
            parts = line.split()
            if len(parts) == 2:
                vals[parts[0]] = float(parts[1])
        if "bw_mix.l2r.bytes_per_cycle" in vals:
            vals["bw_mix.total.bytes_per_cycle"] = (vals["bw_mix.l2r.bytes_per_cycle"] +
                                                    vals.get("bw_mix.r2l.bytes_per_cycle", 0.0))
        for k, v in vals.items():
            data[build][k].append(v)
    return data, runs


def fmt(vals):
    return f"{sum(vals) / len(vals):.2f}" if vals else "-"


def model_section(out_dir, rid=None):
    """One row per (run, bandwidth window, link): measured against the model."""
    table = perf_model.read_svh()
    rows = [r for r in perf_model.judge_runs(out_dir, table)
            if rid_ok(os.path.join(out_dir, r["run"]), rid)]
    if not rows:
        return []
    lines = ["## Against the model", "",
             "Steady-state application bytes per cycle on each link (l2r: DUT TX, r2l: DUT RX)",
             "from perf.json, against the committed d2d_model targets. Gate: PASS, or BELOW",
             "(T1-P02, under (1 - tol) x model), ABOVE (T1-P03), MIX (T1-P04), SHORT (steady",
             "state under min_ss_flits), NO_TARGET. Run: the run's verdict against",
             "expected_fail.yaml.", "",
             "| build | PHY | scenario | window | link | measured | model | ratio | gate | run |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for r in sorted(rows, key=lambda r: (r["build"], r["active_phy"], r["scenario"], r["run"],
                                         r["window"], r["dir"])):
        model = "-" if r["model"] is None else f"{r['model']:.2f}"
        ratio = "-" if r["ratio"] is None else f"{r['ratio']:.3f}"
        lines.append(f"| {r['build']} | {r['active_phy']} | {r['scenario']} | {r['window']} | "
                     f"{r['dir']} | {r['measured']:.2f} | {model} | {ratio} | {r['verdict']} | "
                     f"{r['run_verdict']} |")
    return lines + [""]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", default=os.path.join(UVM_ROOT, "out"))
    ap.add_argument("--rid", help="only runs of this run ID")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()
    data, runs = collect(args.out_dir, args.rid)
    model = model_section(args.out_dir, args.rid)
    if not data and not model:
        print("no aou_perf_test runs with perf.txt or perf.json", file=sys.stderr)
        return 1
    lines = ["# Performance data (plan 2.10)", "",
             "Passing `aou_perf_test` runs only; averages over runs. Bytes and flits per",
             "1 GHz core cycle; latencies in cycles. Report only, no thresholds.", "",
             "| build | runs | " + " | ".join(f"{h} ({p})" for h, _, p in SUMMARY) + " |",
             "|---|---|" + "---|" * len(SUMMARY)]
    for build in sorted(data):
        d = data[build]
        cells = []
        for _, metric, _ in SUMMARY:
            if metric.endswith(".rt"):
                cells.append("/".join(fmt(d.get(f"{metric}_{k}", []))
                                      for k in ("to_fdi", "far_side", "from_fdi")))
            else:
                peak = d.get("bw_wr.fdi_peak_flits_per_cycle") if "flits" in metric else None
                cells.append(fmt(d.get(metric, [])) + (f" ({fmt(peak)})" if peak else ""))
        lines.append(f"| {build} | {runs[build]} | " + " | ".join(cells) + " |")
    lines += [""] + model
    lines += ["## All metrics", ""]
    for build in sorted(data):
        lines += [f"### {build}", "", "| metric | value |", "|---|---|"]
        lines += [f"| {k} | {fmt(v)} |" for k, v in sorted(data[build].items())]
        lines.append("")
    text = "\n".join(lines) + "\n"
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
