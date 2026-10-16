#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Per-module summary of a Verilator coverage.dat (module definition view).

A point counts as covered when any instance of its module hit it, matching
the module-definition scores URG and IMC report, so the tables line up.
"""

import argparse
import collections
import os
import re
import sys

POINT_RE = re.compile(r"^C '(.*)' (\d+)$")
TYPES = ("line", "branch", "expr", "toggle", "covergroup")


def parse(path, src_dir):
    """Yield (module, type, point key, count) for points in files under src_dir."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            m = POINT_RE.match(raw.rstrip("\n"))
            if not m:
                continue
            fields = dict(kv.split("\x02", 1) for kv in m.group(1).split("\x01")[1:] if "\x02" in kv)
            if src_dir and not fields.get("f", "").startswith(src_dir):
                continue
            # Verilator names each parameterization MODULE__<hash>; fold them into
            # one module definition, as URG and IMC do.
            module = fields.get("page", "").partition("/")[2].split("__")[0]
            key = tuple(fields.get(k) for k in ("f", "l", "n", "o", "bin"))
            yield module, fields.get("t", ""), key, int(m.group(2))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dat", help="coverage .dat file (merge first with verilator_coverage --write)")
    ap.add_argument("--src-dir", default="", help="only count points in files under this directory")
    args = ap.parse_args()
    src_dir = os.path.join(os.path.abspath(args.src_dir), "") if args.src_dir else ""

    hit = collections.defaultdict(dict)  # (module, type) -> {key: covered}
    for module, kind, key, count in parse(args.dat, src_dir):
        points = hit[(module, kind)]
        points[key] = points.get(key, False) or count > 0

    modules = sorted({m for m, _ in hit})
    if not modules:
        sys.exit("no coverage points in %s" % args.dat)

    def cell(cov, total):
        if not total:
            return "-".center(17)
        return ("%6.2f %s" % (100.0 * cov / total, "%d/%d" % (cov, total))).ljust(17)

    print("%-32s " % "Module" + " ".join(t.upper().ljust(17) for t in TYPES))
    totals = {t: [0, 0] for t in TYPES}
    for module in modules:
        cells = []
        for t in TYPES:
            points = hit.get((module, t), {})
            cov, total = sum(points.values()), len(points)
            totals[t][0] += cov
            totals[t][1] += total
            cells.append(cell(cov, total))
        print("%-32s " % module + " ".join(cells))
    print("%-32s " % "TOTAL" + " ".join(cell(*totals[t]) for t in TYPES))


if __name__ == "__main__":
    main()
