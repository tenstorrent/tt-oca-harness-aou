#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Histogram of outstanding AXI transactions on an interface, from a waveform.

Write: +1 on each AW handshake, -1 on each B handshake.
Read:  +1 on each AR handshake, -1 on each R handshake with RLAST.
Handshakes are sampled just before each rising edge of the interface clock, so
the clock's phase doesn't matter. Reads FST, VCD or FSDB through waveio.py.

Signal names are matched loosely: any case, an optional I_/O_ (or i_/o_)
direction prefix and an optional _i/_o suffix. So
`top.s_axi[0].awvalid`, `top.u_dut.I_AXI_S_AWVALID` and `top.m_axi_awvalid_o`
are all found. An interface is printed as its scope plus the common name stem.

  axi_outstanding.py --list waves.fsdb
  axi_outstanding.py waves.fsdb --if 'top.s_axi[0].' --dir write
"""

import argparse
import bisect
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import waveio  # noqa: E402

ROLES = {
    "write": ("awvalid", "awready", "bvalid", "bready", None),
    "read": ("arvalid", "arready", "rvalid", "rready", "rlast"),
}
CLOCK_NAMES = ("clk", "aclk", "clock", "clk_in")
# Clocking-block copies duplicate the real interface signals.
CB_RE = re.compile(r"\.\w*_cb\.")
LEAF_RE = re.compile(r"^(?:[io]_)?(.*?)(?:_[io])?$", re.I)


def split(name):
    """(scope, normalized leaf) for a range-free name, or None."""
    if CB_RE.search(name):
        return None
    scope, _, leaf = name.rpartition(".")
    m = LEAF_RE.match(leaf)
    return (scope, m.group(1).lower()) if m else None


class Scope:
    """Every signal directly in one scope, indexed by normalized leaf name."""

    def __init__(self, names, scope):
        self.by_name = {}
        for n in names:
            parts = split(n)
            if parts and parts[0] == scope:
                self.by_name.setdefault(parts[1], n)


def list_interfaces(names):
    """{key: {"scope", "stem", "dirs", "packed"}}; key is what --if takes."""
    found = {}
    for n, width in names.items():
        parts = split(n)
        if not parts or not re.search(r"(aw|ar)valid$", parts[1]):
            continue
        scope, leaf = parts
        stem = leaf[:-7]
        ent = found.setdefault(f"{scope}.{stem}", {"scope": scope, "stem": stem, "dirs": set(), "packed": False})
        ent["dirs"].add("write" if leaf.endswith("awvalid") else "read")
        ent["packed"] |= width > 1
    return found


class Sampled:
    """A signal's value strictly before a given time (what a flop captures)."""

    def __init__(self, ch):
        self.times = [t for t, _ in ch]
        self.vals = [v for _, v in ch]

    def before(self, t):
        i = bisect.bisect_left(self.times, t) - 1
        return self.vals[i] if i >= 0 else "x"


def find_clock(sc, stem):
    for name in [stem + c for c in CLOCK_NAMES] + list(CLOCK_NAMES):
        if name in sc.by_name:
            return sc.by_name[name]
    return None


def histogram(args, wave, names, ent, direction):
    sc = Scope(names, ent["scope"])
    paths = {}
    for tag, role in zip(("qv", "qr", "sv", "sr", "l"), ROLES[direction]):
        if role is None:
            continue
        hit = args.sig.get(role) or sc.by_name.get(ent["stem"] + role)
        if not hit:
            sys.exit(f"no {role} for {ent['scope']}.{ent['stem']}* in that scope; "
                     f"pass --sig {role}=<full path>")
        paths[tag] = hit
    clk_path = waveio.strip_range(args.clock)[0] if args.clock else find_clock(sc, ent["stem"])
    if clk_path not in names:
        sys.exit(f"no signal {clk_path} in the waves")
    if not clk_path:
        sys.exit(f"no clock found in {ent['scope']}; pass --clock <full path>")
    for p in paths.values():
        if p not in names:
            sys.exit(f"no signal {p} in the waves")
    ch = wave.changes(list(paths.values()) + [clk_path])
    edges = [t for t, v in ch[clk_path] if waveio.is_one(v)]
    lo = args.from_fs if args.from_fs is not None else (edges[0] if edges else 0)
    hi = args.to_fs if args.to_fs is not None else (edges[-1] if edges else 0)
    edges = [t for t in edges if lo <= t <= hi]
    if len(edges) < 2:
        sys.exit(f"clock {clk_path} has fewer than two rising edges in the window")
    sig = {tag: Sampled(ch[p]) for tag, p in paths.items()}

    level, peak, issued, done, negative = 0, 0, 0, 0, 0
    cycles_at, issued_at = {}, {}
    for t in edges:
        # The level held during the cycle that ends at this edge.
        cycles_at[level] = cycles_at.get(level, 0) + 1
        req = waveio.is_one(sig["qv"].before(t)) and waveio.is_one(sig["qr"].before(t))
        rsp = waveio.is_one(sig["sv"].before(t)) and waveio.is_one(sig["sr"].before(t))
        if rsp and "l" in sig:
            rsp = waveio.is_one(sig["l"].before(t))
        if req:
            issued_at[level] = issued_at.get(level, 0) + 1
            issued += 1
        level += int(req) - int(rsp)
        done += int(rsp)
        if level < 0:
            negative += 1
            level = 0
        peak = max(peak, level)

    return {
        "name": f"{ent['scope']}.{ent['stem']}", "direction": direction, "clock": clk_path,
        "period_fs": (edges[-1] - edges[0]) / (len(edges) - 1), "window": (edges[0], edges[-1]),
        "cycles": len(edges), "issued": issued, "done": done, "left": level, "peak": peak,
        "negative": negative, "cycles_at": cycles_at, "issued_at": issued_at, "paths": paths,
    }


def fmt_time(fs):
    return waveio.fmt_time(round(fs))


def report(h, csv_fh=None):
    total = h["cycles"]
    busy = total - h["cycles_at"].get(0, 0)
    weighted = sum(k * v for k, v in h["cycles_at"].items())
    print(f"{h['name']}  {h['direction']}  clock {h['clock']} ({fmt_time(h['period_fs'])})  "
          f"window {fmt_time(h['window'][0])}..{fmt_time(h['window'][1])} ({total} cycles)")
    print(f"issued {h['issued']}  completed {h['done']}  still outstanding {h['left']}  peak {h['peak']}  "
          f"mean {weighted / total:.2f} (all cycles), {weighted / busy if busy else 0:.2f} (busy cycles)")
    if h["negative"]:
        print(f"WARNING: {h['negative']} responses with nothing outstanding (protocol error, or a window "
              "that starts mid-traffic; move --from to an idle point)")
    print(f"{'level':>5}  {'cycles':>9}  {'%time':>6}  {'issued at':>9}")
    top = max(h["cycles_at"].values())
    for k in range(max(h["cycles_at"]) + 1):
        c = h["cycles_at"].get(k, 0)
        bar = "#" * max(1 if c else 0, round(40 * c / top))
        print(f"{k:>5}  {c:>9}  {100 * c / total:>5.1f}%  {h['issued_at'].get(k, 0):>9}  {bar}")
        if csv_fh:
            csv_fh.write(f"{h['name']},{h['direction']},{k},{c},{h['issued_at'].get(k, 0)}\n")
    print()


def time_fs(text):
    try:
        return waveio.time_fs(text)
    except ValueError as err:
        raise argparse.ArgumentTypeError(str(err)) from err


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("wave", help="FST, VCD or FSDB file")
    ap.add_argument("--list", action="store_true", help="list AXI interfaces and exit")
    ap.add_argument("--if", dest="names", action="append", help="interface as --list prints it; repeatable")
    ap.add_argument("--dir", choices=("write", "read", "both"), default="both")
    ap.add_argument("--clock", help="clock path (default: a clk/aclk/clock signal in the interface's scope)")
    ap.add_argument("--from", dest="from_fs", type=time_fs, help="window start, e.g. 270ns")
    ap.add_argument("--to", dest="to_fs", type=time_fs, help="window end")
    ap.add_argument("--sig", action="append", default=[], metavar="ROLE=PATH",
                    help="override one signal, e.g. bvalid=top.u_dut.O_RX_AXI_S_BVALID; repeatable")
    ap.add_argument("--csv", help="also write name,direction,level,cycles,issued_at rows here")
    args = ap.parse_args()
    sig = {}
    for item in args.sig:
        role, _, path = item.partition("=")
        if role.lower() not in {r for rs in ROLES.values() for r in rs if r} or not path:
            ap.error(f"--sig takes ROLE=PATH with ROLE one of awvalid..rlast: {item!r}")
        sig[role.lower()] = waveio.strip_range(path)[0]
    args.sig = sig

    wave = waveio.open_wave(args.wave)
    names = wave.names()
    found = list_interfaces(names)
    if args.list or not args.names:
        if not found:
            sys.exit("no AXI interfaces (no *awvalid / *arvalid signals) in the waves")
        scopes = {}
        for key in sorted(found):
            e = found[key]
            sc = scopes.setdefault(e["scope"], Scope(names, e["scope"]))
            missing = [r for d in sorted(e["dirs"]) for r in ROLES[d]
                       if r and e["stem"] + r not in sc.by_name]
            note = "  (vector-packed: not supported)" if e["packed"] else ""
            if missing:
                note += f"  (missing {','.join(missing)}: pass --sig)"
            print(f"{key}\t{','.join(sorted(e['dirs']))}{note}")
        return
    csv_fh = open(args.csv, "w", encoding="utf-8") if args.csv else None
    if csv_fh:
        csv_fh.write("name,direction,level,cycles,issued_at\n")
    for name in args.names:
        ent = found.get(name) or found.get(name.lower())
        if ent is None:
            sys.exit(f"{name!r} is not an AXI interface in the waves; --list shows them")
        if ent["packed"]:
            sys.exit(f"{name} is vector-packed (one valid bit per port); pick a per-port interface")
        for d in sorted(ent["dirs"]) if args.dir == "both" else [args.dir]:
            if d not in ent["dirs"]:
                sys.exit(f"{name} has no {d} channels")
            report(histogram(args, wave, names, ent, d), csv_fh)
    if csv_fh:
        csv_fh.close()


if __name__ == "__main__":
    waveio.ensure_pywellen()
    main()
