#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Query a waveform (FST, VCD or FSDB) from the command line, as short text.

  waveq.py search  <wave> <pattern> [--kind suffix|glob|regex]
  waveq.py changes <wave> <signal> [--from T] [--to T]
  waveq.py at      <wave> <signal>... --time T
  waveq.py multi   <wave> <signal>... --clock <clk> [--from T] [--to T] [--every]
  waveq.py find    <wave> <signal> --eq V | --neq V [--from T] [--to T]

Signals are full paths without a bit range (`top.if.id`, not `top.if.id[9:0]`);
`search` prints them with their width. Times need a unit (`709ns`). `multi`
samples just before each rising edge of --clock and numbers rows by edge, from
0 at the first edge in the file. Values print as hex when every bit is 0/1,
otherwise as bits (`xxxx`).
"""

import argparse
import bisect
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import waveio  # noqa: E402


def resolve(names, sig):
    name = waveio.strip_range(sig)[0]
    if name not in names:
        hits = waveio.match(names, name.rpartition(".")[2])
        hint = f"; did you mean {', '.join(hits[:3])}" if hits else ""
        sys.exit(f"no signal {name}{hint}")
    return name


def in_window(t, args):
    return (args.from_fs is None or t >= args.from_fs) and (args.to_fs is None or t <= args.to_fs)


def value_before(ch, t):
    """Value strictly before t (what a flop captures at an edge at t)."""
    i = bisect.bisect_left([x for x, _ in ch], t) - 1
    return ch[i][1] if i >= 0 else "x"


def value_at(ch, t):
    i = bisect.bisect_right([x for x, _ in ch], t) - 1
    return ch[i][1] if i >= 0 else "x"


def cmd_search(wave, names, args):
    hits = waveio.match(names, args.pattern, args.kind)
    for n in sorted(hits)[: args.limit or None]:
        print(f"{n}\t{names[n]}")
    if not hits:
        sys.exit(f"no signal matches {args.pattern!r}")


def cmd_changes(wave, names, args):
    name = resolve(names, args.signal)
    for t, v in wave.changes([name])[name]:
        if in_window(t, args):
            print(f"{waveio.fmt_time(t)} {v}")


def cmd_at(wave, names, args):
    sigs = [resolve(names, s) for s in args.signals]
    ch = wave.changes(sigs)
    for s in sigs:
        print(f"{s}={value_at(ch[s], args.time)}")


def cmd_multi(wave, names, args):
    sigs = [resolve(names, s) for s in args.signals]
    clk = resolve(names, args.clock)
    ch = wave.changes(sigs + [clk])
    edges = [t for t, v in ch[clk] if waveio.is_one(v)]
    short = {s: s.rpartition(".")[2] for s in sigs}
    prev = None
    for i, t in enumerate(edges):
        if not in_window(t, args):
            continue
        row = tuple(value_before(ch[s], t) for s in sigs)
        if args.every or row != prev:
            cols = " ".join(f"{short[s]}={v}" for s, v in zip(sigs, row))
            print(f"edge={i} t={waveio.fmt_time(t)} {cols}")
        prev = row


def cmd_find(wave, names, args):
    name = resolve(names, args.signal)
    want = waveio.fmt_value(int(args.eq if args.eq is not None else args.neq, 0))
    match_eq = args.eq is not None
    start = None
    ch = [(t, v) for t, v in wave.changes([name])[name]]
    for i, (t, v) in enumerate(ch):
        hit = (v == want) == match_eq
        if hit and start is None:
            start = t
        elif not hit and start is not None:
            if in_window(start, args) or in_window(t, args):
                print(f"{waveio.fmt_time(start)}..{waveio.fmt_time(t)}")
            start = None
    if start is not None and in_window(start, args):
        print(f"{waveio.fmt_time(start)}..end")


def time_arg(text):
    try:
        return waveio.time_fs(text)
    except ValueError as err:
        raise argparse.ArgumentTypeError(str(err)) from err


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, windowed=True):
        p = sub.add_parser(name)
        p.add_argument("wave")
        p.set_defaults(fn=fn)
        if windowed:
            p.add_argument("--from", dest="from_fs", type=time_arg)
            p.add_argument("--to", dest="to_fs", type=time_arg)
        return p

    p = add("search", cmd_search, windowed=False)
    p.add_argument("pattern")
    p.add_argument("--kind", choices=("auto", "suffix", "glob", "regex"), default="auto")
    p.add_argument("--limit", type=int, default=0)
    p = add("changes", cmd_changes)
    p.add_argument("signal")
    p = add("at", cmd_at, windowed=False)
    p.add_argument("signals", nargs="+")
    p.add_argument("--time", type=time_arg, required=True)
    p = add("multi", cmd_multi)
    p.add_argument("signals", nargs="+")
    p.add_argument("--clock", required=True)
    p.add_argument("--every", action="store_true", help="a row for every edge, not only on change")
    p = add("find", cmd_find)
    p.add_argument("signal")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--eq", help="value, e.g. 1, 0x3, 0b101")
    g.add_argument("--neq")
    args = ap.parse_args()

    wave = waveio.open_wave(args.wave)
    args.fn(wave, wave.names(), args)


if __name__ == "__main__":
    waveio.ensure_pywellen()
    main()
