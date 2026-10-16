#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Functional coverage report: union-merge of the passing runs under out/<build>/.

Each COV=1 run writes fc.json (cov/aou_fc_pkg.sv: every testbench covergroup,
every declared bin with its hit count) and aou_axi4_fc.<run>.txt (the AXI4
monitors bound to the DUT, cov/aou_axi4_coverage_mod.sv), which is read as
groups axi4.<interface>.<covergroup>. A bin counts as covered when any passing
run hit it; bins are counted here, not by a simulator's covergroup engine, so
VCS and Verilator reports compare bin for bin. Only PASS runs count
(passing_runs.py).

  fc_report.py out/vcs-t1-1x512-sp64-cov -o out/vcs-t1-1x512-sp64-cov/merged/fc

writes summary.txt (bins hit/total per group and point), holes.txt (every bin
no run hit), fc_merged.json (the merged database) and index.html (the same,
self-contained). Group percentages are hit bins over all bins of the group,
crosses included; a covergroup's own percentage weights each coverpoint and
cross equally instead, so the two differ.

Ignored bins never reach fc.json. Illegal bins (marked "illegal") are not
counted; a hit on one is listed. Bins tagged with a spec revision ("spec":
"v0.8") stay in every count and are also totalled apart, so the holes only a
v0.8 partner or DUT can close are visible as such.
"""

import argparse
import glob
import html
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import merge_axi4_fc  # noqa: E402
import passing_runs  # noqa: E402


def new_db():
    return {"groups": {}}


def point_of(db, group, point, kind):
    g = db["groups"].setdefault(group, {"spec": "", "plan_ids": [], "samples": 0,
                                        "points": {}})
    return g, g["points"].setdefault(point, {"kind": kind, "outside": 0, "bins": {}})


def add_bin(pt, name, hits, spec="", plan_ids=(), illegal=False):
    b = pt["bins"].setdefault(name, {"hits": 0, "runs": 0, "spec": spec,
                                     "plan_ids": list(plan_ids)})
    if illegal:
        b["illegal"] = True
    b["hits"] += hits
    b["runs"] += 1 if hits else 0
    if spec and not b["spec"]:
        b["spec"] = spec
    for pid in plan_ids:
        if pid not in b["plan_ids"]:
            b["plan_ids"].append(pid)


def merge_fc_json(db, path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    for grp in data["groups"]:
        for p in grp["points"]:
            g, pt = point_of(db, grp["group"], p["point"], p["kind"])
            pt["outside"] += p.get("outside", 0)
            for b in p["bins"]:
                add_bin(pt, b["bin"], b["hits"], b.get("spec", ""), b.get("plan_ids", []),
                        b.get("illegal", False))
        g["samples"] += grp.get("samples", 0)
        if grp.get("spec") and not g["spec"]:
            g["spec"] = grp["spec"]
        for pid in grp.get("plan_ids", []):
            if pid not in g["plan_ids"]:
                g["plan_ids"].append(pid)


def merge_axi4_txt(db, path):
    """aou_axi4_fc.<run>.txt BIN lines "cg|cp|bin" per interface, as groups axi4.<if>.<cg>."""
    counts, stats, names = {}, {}, []
    merge_axi4_fc.parse_file(path, counts, _Stats(stats), names)
    for iface in sorted(counts):
        for key in sorted(counts[iface]):
            cg, cp, b = key.split("|", 2)
            _, pt = point_of(db, f"axi4.{iface}.{cg}", cp, "cross" if cp.startswith("cx_")
                             else "coverpoint")
            add_bin(pt, b.replace("_X_", ","), counts[iface][key])


class _Stats(dict):
    """merge_axi4_fc keeps per-interface statistics this report doesn't use."""

    def __missing__(self, key):
        self[key] = {}
        return self[key]


def counted(p):
    """The bins of a point that count: every bin but the illegal ones."""
    return {n: b for n, b in p["bins"].items() if not b.get("illegal")}


def tally(points, spec=None):
    """(hit, total) over the counted bins; with spec, only bins tagged with it."""
    bins = [b for p in points.values() for b in counted(p).values()
            if spec is None or b.get("spec") == spec]
    return sum(1 for b in bins if b["hits"]), len(bins)


def specs(db):
    return sorted({b["spec"] for g in db["groups"].values() for p in g["points"].values()
                   for b in p["bins"].values() if b.get("spec")})


def illegal_hits(db):
    return [(g, pn, bn, b["hits"]) for g, grp in sorted(db["groups"].items())
            for pn, p in grp["points"].items() for bn, b in p["bins"].items()
            if b.get("illegal") and b["hits"]]


def pct(hit, total):
    return 100.0 * hit / total if total else 0.0


def merge(out_dir):
    runs, counts = passing_runs.scan(out_dir)
    db = new_db()
    no_data = []
    for run in runs:
        fc = os.path.join(run, "fc.json")
        axi4 = sorted(glob.glob(os.path.join(run, "aou_axi4_fc.*.txt")))
        if os.path.exists(fc):
            merge_fc_json(db, fc)
        for path in axi4:
            merge_axi4_txt(db, path)
        if not os.path.exists(fc) or not axi4:
            no_data.append(os.path.basename(run))
    db["runs"] = [os.path.basename(r) for r in runs]
    db["verdicts"] = counts
    db["runs_without_fc_data"] = no_data
    return db, counts


def write_summary(fh, db, counts, build):
    w = fh.write
    w(f"Functional coverage: {build}\n")
    w(passing_runs.summary(counts) + "\n")
    if db["runs_without_fc_data"]:
        w(f"passing runs missing fc.json or the AXI4 report: {len(db['runs_without_fc_data'])}"
          f" ({', '.join(db['runs_without_fc_data'])})\n")
    tags = specs(db)
    w("\n%-36s %12s %8s%s\n" % ("GROUP", "BINS HIT", "%",
                                "".join(" %12s" % f"{t} HIT" for t in tags)))
    w("-" * (58 + 13 * len(tags)) + "\n")
    th = tt = 0
    st = {t: [0, 0] for t in tags}
    for name in sorted(db["groups"]):
        pts = db["groups"][name]["points"]
        hit, total = tally(pts)
        th += hit
        tt += total
        cols = ""
        for t in tags:
            sh, stt = tally(pts, t)
            st[t][0] += sh
            st[t][1] += stt
            cols += " %12s" % (f"{sh}/{stt}" if stt else "-")
        w("%-36s %5d/%-6d %7.2f%%%s\n" % (name, hit, total, pct(hit, total), cols))
    w("-" * (58 + 13 * len(tags)) + "\n")
    w("%-36s %5d/%-6d %7.2f%%%s\n" % ("TOTAL", th, tt, pct(th, tt),
                                     "".join(" %12s" % f"{st[t][0]}/{st[t][1]}" for t in tags)))
    for t in tags:
        oh, ot = th - st[t][0], tt - st[t][1]
        w(f"{t}-tagged bins: {st[t][0]}/{st[t][1]} hit; without them {oh}/{ot} "
          f"({pct(oh, ot):.2f}%)\n")
    for g, pn, bn, n in illegal_hits(db):
        w(f"ILLEGAL BIN HIT: {g}.{pn} {bn} ({n} hits)\n")
    w("\n")
    for name in sorted(db["groups"]):
        g = db["groups"][name]
        hit, total = tally(g["points"])
        w(f"{name}  {hit}/{total} ({pct(hit, total):.2f}%), {g['samples']} samples\n")
        for pname, p in g["points"].items():
            cb = counted(p)
            ph = sum(1 for b in cb.values() if b["hits"])
            out = f", {p['outside']} outside every bin" if p["outside"] else ""
            w("    %-26s %-10s %4d/%-4d %7.2f%%%s\n" % (pname, p["kind"], ph, len(cb),
                                                       pct(ph, len(cb)), out))
    return th, tt


def write_holes(fh, db):
    for name in sorted(db["groups"]):
        holes = [(pn, bn + (f" [{b['spec']}]" if b.get("spec") else ""))
                 for pn, p in db["groups"][name]["points"].items()
                 for bn, b in counted(p).items() if not b["hits"]]
        if not holes:
            continue
        fh.write(f"{name}: {len(holes)} hole(s)\n")
        for pn in dict.fromkeys(pn for pn, _ in holes):
            fh.write(f"    {pn}: {' '.join(bn for p2, bn in holes if p2 == pn)}\n")


CSS = """
:root{--bg:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#e3e3e8;--ok:#2e7d32;--part:#b26a00;
--bad:#c62828;--bar:#e9e9ee;--card:#f7f7f9}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#ececf0;--mut:#9a9aa2;
--line:#2c2c31;--ok:#66bb6a;--part:#ffb74d;--bad:#ef5350;--bar:#2a2a2f;--card:#1e1e21}}
body{margin:0;background:var(--bg);color:var(--fg);
font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px}
h1{font-size:20px;margin:0 0 4px}p.meta{color:var(--mut);margin:2px 0}
table{border-collapse:collapse;width:100%;margin:12px 0}
th,td{text-align:left;padding:4px 8px;border-bottom:1px solid var(--line);
font-variant-numeric:tabular-nums}
th{color:var(--mut);font-weight:600}td.n{text-align:right}
.bar{display:inline-block;width:120px;height:8px;background:var(--bar);border-radius:4px;
vertical-align:middle;overflow:hidden}.bar i{display:block;height:100%}
details{background:var(--card);border:1px solid var(--line);border-radius:8px;
margin:8px 0;padding:6px 12px}summary{cursor:pointer;font-weight:600}
.holes{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:var(--bad);
word-break:break-word}.wrap{overflow-x:auto}
"""


def colour(p):
    return "var(--ok)" if p >= 100 else "var(--part)" if p >= 50 else "var(--bad)"


def bar(p):
    return f'<span class="bar"><i style="width:{p:.1f}%;background:{colour(p)}"></i></span>'


def write_html(fh, db, counts, build):
    e = html.escape
    out = [f"<!doctype html><html lang=en><head><meta charset=utf-8>"
           f"<meta name=viewport content='width=device-width,initial-scale=1'>"
           f"<title>Functional coverage {e(build)}</title><style>{CSS}</style></head><body><main>",
           f"<h1>Functional coverage: {e(build)}</h1>",
           f"<p class=meta>{e(passing_runs.summary(counts))}</p>"]
    if db["runs_without_fc_data"]:
        out.append(f"<p class=meta>{len(db['runs_without_fc_data'])} passing run(s) without "
                   f"fc.json or the AXI4 report</p>")
    th = tt = 0
    rows = []
    for name in sorted(db["groups"]):
        hit, total = tally(db["groups"][name]["points"])
        th += hit
        tt += total
        rows.append(f"<tr><td><a href='#{e(name)}'>{e(name)}</a></td><td class=n>{hit}/{total}"
                    f"</td><td class=n>{pct(hit, total):.2f}%</td><td>{bar(pct(hit, total))}"
                    f"</td></tr>")
    out.append(f"<p class=meta>Total {th}/{tt} bins ({pct(th, tt):.2f}%)</p>")
    for t in specs(db):
        sh, stt = (sum(x) for x in zip(*(tally(g["points"], t) for g in db["groups"].values())))
        out.append(f"<p class=meta>{e(t)}-tagged bins (counted above, holes marked "
                   f"[{e(t)}]): {sh}/{stt} hit; without them {th - sh}/{tt - stt} "
                   f"({pct(th - sh, tt - stt):.2f}%)</p>")
    for g, pn, bn, n in illegal_hits(db):
        out.append(f"<p class=meta>Illegal bin hit: {e(g)}.{e(pn)} {e(bn)} ({n})</p>")
    out.append("<div class=wrap><table><tr><th>Group</th><th>Bins hit</th><th>%</th><th></th>"
               "</tr>" + "".join(rows) + "</table></div>")
    for name in sorted(db["groups"]):
        g = db["groups"][name]
        hit, total = tally(g["points"])
        out.append(f"<details id='{e(name)}'><summary>{e(name)}: {hit}/{total} "
                   f"({pct(hit, total):.2f}%)</summary><div class=wrap><table><tr><th>Point</th>"
                   f"<th>Kind</th><th>Bins hit</th><th>%</th><th>Outside</th><th>Holes</th></tr>")
        for pn, p in g["points"].items():
            cb = counted(p)
            ph = sum(1 for b in cb.values() if b["hits"])
            holes = " ".join(bn + (f" [{b['spec']}]" if b.get("spec") else "")
                             for bn, b in cb.items() if not b["hits"])
            out.append(f"<tr><td>{e(pn)}</td><td>{p['kind']}</td><td class=n>{ph}/"
                       f"{len(cb)}</td><td class=n>{pct(ph, len(cb)):.1f}%</td>"
                       f"<td class=n>{p['outside']}</td><td class=holes>{e(holes)}</td></tr>")
        out.append("</table></div></details>")
    out.append("</main></body></html>\n")
    fh.write("\n".join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out_dir", help="out/<build>, holding the run directories")
    ap.add_argument("-o", "--report-dir", required=True)
    args = ap.parse_args()

    build = os.path.basename(os.path.normpath(args.out_dir))
    db, counts = merge(args.out_dir)
    print(passing_runs.summary(counts))
    if not db["groups"]:
        sys.exit("fc_report: no fc.json in the passing runs; run them with COV=1")
    os.makedirs(args.report_dir, exist_ok=True)
    with open(os.path.join(args.report_dir, "fc_merged.json"), "w", encoding="utf-8") as fh:
        json.dump(db, fh, indent=1)
    with open(os.path.join(args.report_dir, "holes.txt"), "w", encoding="utf-8") as fh:
        write_holes(fh, db)
    with open(os.path.join(args.report_dir, "index.html"), "w", encoding="utf-8") as fh:
        write_html(fh, db, counts, build)
    text = io.StringIO()
    th, tt = write_summary(text, db, counts, build)
    with open(os.path.join(args.report_dir, "summary.txt"), "w", encoding="utf-8") as fh:
        fh.write(text.getvalue())
    # The per-group table: everything up to the first per-point detail.
    print(text.getvalue().split("\n\n")[1])
    print(f"fc_report: {th}/{tt} bins ({pct(th, tt):.2f}%); report in {args.report_dir}")


if __name__ == "__main__":
    main()
