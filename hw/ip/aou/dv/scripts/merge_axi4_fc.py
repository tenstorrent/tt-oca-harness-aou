#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) Tenstorrent USA Inc
"""
merge_axi4_fc.py - True union merge of AXI4 functional-coverage text reports.

Each simulation writes one per-run report (aou_axi4_fc.<run>.txt) containing a
machine-readable "#BINDATA" region with per-bin hit counts. This script unions
those bins across runs (a bin is covered if hit in ANY run) and recomputes the
merged coverage, which - unlike merging percentages - is mathematically correct.

Usage:
  python3 merge_axi4_fc.py run1.txt run2.txt [...] [-o merged.txt]
  python3 merge_axi4_fc.py --glob 'aou_axi4_fc.*.txt' -o merged.txt

Output: a merged report (stdout and/or -o file) with per-interface and overall
union coverage, plus the list of still-uncovered bins (holes).
"""

import argparse
import glob
import sys
from collections import defaultdict


def parse_file(path, counts, stats, run_names):
    """Parse one per-run report; accumulate union bin counts and stats."""
    in_bindata = False
    iface = None
    run = None
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if run is None and line.startswith("Run"):
                # header line "Run        : <name>"
                parts = line.split(":", 1)
                if len(parts) == 2:
                    run = parts[1].strip()
            if line.startswith("#BINDATA"):
                in_bindata = True
                continue
            if line.startswith("#ENDBINDATA"):
                in_bindata = False
                continue
            if not in_bindata:
                continue
            if line.startswith("#IFACE"):
                iface = line.split(None, 1)[1].strip()
                counts.setdefault(iface, defaultdict(int))
                continue
            if line.startswith("#ENDIFACE"):
                iface = None
                continue
            if line.startswith("#STAT") and iface is not None:
                for tok in line.split()[1:]:
                    if "=" in tok:
                        k, v = tok.split("=", 1)
                        try:
                            v = int(v)
                        except ValueError:
                            continue
                        if k.startswith("max_"):
                            stats[iface][k] = max(stats[iface].get(k, 0), v)
                        else:
                            stats[iface][k] = stats[iface].get(k, 0) + v
                continue
            if line.startswith("BIN ") and iface is not None:
                # "BIN <cg|cp|bin> <count>"
                _, key, cnt = line.split()
                counts[iface][key] += int(cnt)
    run_names.append(run if run else path)


def pct(cov, tot):
    return 100.0 * cov / tot if tot else 0.0


def avg(vals):
    """Simple mean of a list of percentages (matches SV covergroup averaging)."""
    return sum(vals) / len(vals) if vals else 0.0


def cg_pct(cg):
    """Covergroup % = mean of its coverpoint %s (covered/total per coverpoint).

    This mirrors how the per-run SystemVerilog report computes coverage
    (each coverpoint/cross weighted equally), so merged numbers are directly
    comparable to the per-run reports - and the union guarantees they only
    ever go up.
    """
    return avg([pct(d["covered"], d["total"]) for d in cg.values()])


def iface_pct(cg_map):
    """Interface total % = mean of its covergroup %s (matches SV >>> TOTAL)."""
    return avg([cg_pct(cg) for cg in cg_map.values()])


def summarize(counts):
    """Return nested structure: iface -> cg -> cp -> {total, covered, missing[]}."""
    out = {}
    for iface, bins in counts.items():
        cg_map = {}
        for key, cnt in bins.items():
            cg, cp, b = key.split("|", 2)
            cp_map = cg_map.setdefault(cg, {})
            d = cp_map.setdefault(cp, {"total": 0, "covered": 0, "missing": []})
            d["total"] += 1
            if cnt > 0:
                d["covered"] += 1
            else:
                d["missing"].append(b)
        out[iface] = cg_map
    return out


def write_report(fh, counts, stats, run_names, show_holes=True):
    summ = summarize(counts)
    w = fh.write

    w("=" * 80 + "\n")
    w("AOU RTL - AXI4 FUNCTIONAL COVERAGE (MERGED / UNION)\n")
    w("=" * 80 + "\n")
    w("Runs merged : %d  (%s)\n" % (len(run_names), ", ".join(run_names)))
    w("Interfaces  : %d\n\n" % len(summ))

    # ---- per-interface total table ----
    # TOTAL% uses the same covergroup-averaged method as the per-run SV report
    # (so it is directly comparable and only ever increases with the union).
    # "covered/total" is the raw union bin tally for transparency.
    g_cov = g_tot = 0
    iface_totals = []
    w("--- PER-INTERFACE TOTAL COVERAGE (union) ---\n")
    w("%-34s %8s   %s\n" % ("INTERFACE", "TOTAL%", "covered/total bins"))
    w("-" * 64 + "\n")
    for iface in sorted(summ):
        cov = sum(d["covered"] for cg in summ[iface].values() for d in cg.values())
        tot = sum(d["total"] for cg in summ[iface].values() for d in cg.values())
        g_cov += cov
        g_tot += tot
        itot = iface_pct(summ[iface])
        iface_totals.append(itot)
        w("%-34s %7.2f%%   %d/%d\n" % (iface, itot, cov, tot))
    w("-" * 64 + "\n")
    w("%-34s %7.2f%%   %d/%d\n\n" % ("OVERALL (mean of ifaces)", avg(iface_totals), g_cov, g_tot))

    # ---- per-interface detail ----
    w("\n" + "#" * 80 + "\n# PER-INTERFACE DETAIL (per covergroup / coverpoint)\n" + "#" * 80 + "\n\n")
    for iface in sorted(summ):
        st = stats.get(iface, {})
        w("-" * 80 + "\n")
        w("INTERFACE : %s\n" % iface)
        if st:
            w("  stats   : writes=%d reads=%d max_wr_os=%d max_rd_os=%d\n" % (
                st.get("total_wr", 0), st.get("total_rd", 0),
                st.get("max_wr_os", 0), st.get("max_rd_os", 0)))
        for cg in sorted(summ[iface]):
            cg_cov = sum(d["covered"] for d in summ[iface][cg].values())
            cg_tot = sum(d["total"] for d in summ[iface][cg].values())
            w("  %-14s %6.2f%%  (%d/%d bins)\n" % (cg, cg_pct(summ[iface][cg]), cg_cov, cg_tot))
            for cp in sorted(summ[iface][cg]):
                d = summ[iface][cg][cp]
                w("      %-26s %6.2f%%  (%d/%d)\n" % (cp, pct(d["covered"], d["total"]),
                                                      d["covered"], d["total"]))
                if show_holes and d["missing"]:
                    w("          MISSING: %s\n" % ", ".join(sorted(d["missing"])))
        w("\n")


def main():
    ap = argparse.ArgumentParser(description="Union-merge AXI4 FC text reports.")
    ap.add_argument("files", nargs="*", help="per-run report files")
    ap.add_argument("--glob", help="glob pattern for report files")
    ap.add_argument("-o", "--out", help="write merged report to this file")
    ap.add_argument("--no-holes", action="store_true", help="omit the MISSING-bin lists")
    args = ap.parse_args()

    files = list(args.files)
    if args.glob:
        files += sorted(glob.glob(args.glob))
    if not files:
        ap.error("no input files (pass files or --glob)")

    counts = {}
    stats = defaultdict(dict)
    run_names = []
    for path in files:
        parse_file(path, counts, stats, run_names)

    if not counts:
        sys.exit("error: no #BINDATA found in inputs; run with COV=1 "
                 "(and without +define+AOU_AXI4_FC_NO_TXT_RPT)")

    write_report(sys.stdout, counts, stats, run_names, show_holes=not args.no_holes)
    if args.out:
        with open(args.out, "w") as fh:
            write_report(fh, counts, stats, run_names, show_holes=not args.no_holes)
        print("\n[merge_axi4_fc] merged report written to %s" % args.out, file=sys.stderr)


if __name__ == "__main__":
    main()
