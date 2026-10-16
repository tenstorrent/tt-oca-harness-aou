#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Warn when a build is older than its sources or was compiled with other defines.

`make build` writes <build>/build.stamp: the compile defines, one per line, with
the build's start time as its modification time. This compares that time with
the newest RTL and testbench source and the recorded defines with the current
ones. Builds from before the stamp existed fall back to the simulator binary's
time and skip the defines. It only warns (stderr) and always exits 0; it never
rebuilds. `make run` calls it (STALE_CHECK=0 skips it); scripts/run_list.py
calls it once through `make stale-check` and runs with STALE_CHECK=0.
"""

import argparse
import os
import sys
import time

SOURCE_EXT = (".sv", ".svh", ".v", ".vh", ".f", ".cc", ".c", ".h", ".rdl")
PRUNE = {".deps", "build", "out", "site", ".git", "__pycache__"}


def sources(paths):
    """(mtime, path) of every source file under the given files and directories."""
    for top in paths:
        if os.path.isfile(top):
            yield os.path.getmtime(top), top
            continue
        for root, dirs, files in os.walk(top):
            dirs[:] = [d for d in dirs if d not in PRUNE]
            for name in files:
                if name.endswith(SOURCE_EXT):
                    path = os.path.join(root, name)
                    try:
                        yield os.path.getmtime(path), path
                    except OSError:
                        pass


def check(stamp, simv, defines, src):
    """The reasons the build is stale (empty when it is current or there is no build)."""
    if os.path.exists(stamp):
        built = os.path.getmtime(stamp)
        with open(stamp, encoding="utf-8") as fh:
            old = fh.read().split()
    elif simv and os.path.exists(simv):
        built, old = os.path.getmtime(simv), None
    else:
        return []
    reasons = []
    newer = sorted((s for s in sources(src) if s[0] > built), reverse=True)
    if newer:
        when = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(built))
        reasons.append(f"{len(newer)} source file(s) changed since the build started ({when}); newest:")
        reasons += [f"  {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(t))}  {p}" for t, p in newer[:5]]
        if len(newer) > 5:
            reasons.append(f"  ... and {len(newer) - 5} more")
    if old is not None and sorted(old) != sorted(defines):
        gone, added = sorted(set(old) - set(defines)), sorted(set(defines) - set(old))
        reasons.append("compile defines changed: "
                       + ", ".join([f"-{d}" for d in gone] + [f"+{d}" for d in added]))
    return reasons


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build-dir", required=True)
    ap.add_argument("--simv", default="", help="the binary, for builds without build.stamp")
    ap.add_argument("--defines", default="", help="the current compile defines, space-separated")
    ap.add_argument("--rebuild", default="make build", help="the command to suggest")
    ap.add_argument("src", nargs="*", help="source files (taken whatever their type) and directories")
    args = ap.parse_args(argv)
    reasons = check(os.path.join(args.build_dir, "build.stamp"), args.simv, args.defines.split(), args.src)
    if reasons:
        bar = "*" * 78
        print("\n".join([bar, f"WARNING: STALE BUILD {args.build_dir}", *reasons,
                         f"Runs use the old binary. Rebuild: {args.rebuild}", bar]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
