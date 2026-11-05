#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Compare the RX latency windows of two aou_perf_test +perf_mode=rxlat runs.

    rx_lat_compare.py --base <perf.txt|run dir> --new <perf.txt|run dir> [--label A B]
                      [--metric avg|max|min] [--markdown]

Reads the rxlat.<window>.<kind>.<stat>, rxlat_first.*, rxcrd.* and rxrate.* lines
aou_rx_lat_mon writes (docs/fdi-rx-plan.md 13) and prints one table per metric
family: window, kind, base, new, delta (new - base, in DUT clock cycles for the
latencies, messages per cycle for the rate). Windows or kinds present in only
one run are listed with the other column empty. Exit status 0.
"""

import argparse
import os
import sys


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, "perf.txt")
    vals = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            try:
                vals[parts[0]] = float(parts[1])
            except ValueError:
                pass
    return vals


def rows(vals, family, stat):
    """{(window, kind): value} for metrics family.window.kind.stat (or family.window.kind)."""
    out = {}
    for k, v in vals.items():
        p = k.split(".")
        if p[0] != family:
            continue
        if family == "rxrate":
            if len(p) == 3:
                out[(p[1], p[2])] = v
        elif len(p) == 4 and p[3] == stat:
            out[(p[1], p[2])] = v
    return out


def window_order(name):
    # idle, stream, loaded, mixed; then by name
    for i, pre in enumerate(("idle", "stream", "loaded", "mixed")):
        if name.startswith(pre):
            return (i, name)
    return (9, name)


def fmt(v):
    return "" if v is None else f"{v:.4g}"


def table(title, base, new, labels, markdown):
    keys = sorted(set(base) | set(new), key=lambda k: (window_order(k[0]), k[1]))
    if not keys:
        return
    head = ["window", "kind", labels[0], labels[1], "delta"]
    lines = []
    for k in keys:
        b = base.get(k)
        n = new.get(k)
        d = "" if b is None or n is None else f"{n - b:+.4g}"
        lines.append([k[0], k[1], fmt(b), fmt(n), d])
    print(f"\n{title}")
    if markdown:
        print("| " + " | ".join(head) + " |")
        print("|" + "---|" * len(head))
        for l in lines:
            print("| " + " | ".join(l) + " |")
    else:
        w = [max(len(x[i]) for x in [head] + lines) for i in range(len(head))]
        print("  ".join(h.ljust(w[i]) for i, h in enumerate(head)))
        for l in lines:
            print("  ".join(c.ljust(w[i]) for i, c in enumerate(l)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--label", nargs=2, default=["base", "new"])
    ap.add_argument("--metric", default="avg", choices=["avg", "max", "min"])
    ap.add_argument("--markdown", action="store_true")
    a = ap.parse_args()
    b = load(a.base)
    n = load(a.new)
    m = a.metric
    table(f"RX latency, last granule at FDI to AXI handshake, cycles ({m})",
          rows(b, "rxlat", m), rows(n, "rxlat", m), a.label, a.markdown)
    table("RX latency from the first granule, cycles (avg)",
          rows(b, "rxlat_first", "avg"), rows(n, "rxlat_first", "avg"), a.label, a.markdown)
    table(f"Credit return after the AXI handshake, cycles ({m if m != 'min' else 'avg'})",
          rows(b, "rxcrd", m if m != "min" else "avg"), rows(n, "rxcrd", m if m != "min" else "avg"),
          a.label, a.markdown)
    table("Messages presented per window cycle",
          rows(b, "rxrate", ""), rows(n, "rxrate", ""), a.label, a.markdown)
    return 0


if __name__ == "__main__":
    sys.exit(main())
