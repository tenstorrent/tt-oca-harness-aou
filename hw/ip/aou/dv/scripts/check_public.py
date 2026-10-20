#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Find site-internal references before pushing to the public repository.

Scans the tracked files at HEAD, and with --range the lines added by those
commits and their messages (history is published too). Built-in patterns
catch the generic shapes of internal references: site-style absolute paths,
private hostnames, home directories. Site-specific names (hosts, queues,
module names) live outside the repository, one regex per line, in
hw/ip/aou/dv/site/public_patterns.txt or the file named by AOU_PUBLIC_PATTERNS.

Exit status is 1 when anything matches. A line ending in the marker
`public-ok` is accepted (for example a pattern documented on purpose).
"""

import argparse
import os
import re
import subprocess
import sys

BUILTIN = [
    (r"/(proj|tools)_[a-z0-9]+/", "site filesystem path"),
    (r"\b[\w.-]+\.local(\b|:)", "private hostname"),
    (r"/home/[A-Za-z0-9_.-]+/", "home directory"),
    (r"\buser_dev/", "personal work area"),
    # Four octets, and not a spec section number (UCIe "§10.3.3.8", "section 10.2.3.1", "r3.0 10.3.3.8").
    (r"(?<![§\d.])(?<!section )(?<!\d\.\d )\b(10\.\d{1,3}|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b(?!\.\d)",
     "private IP address"),
]
SKIP_FILES = re.compile(r"\.(pdf|png|jpg|gz|tgz|zip|fsdb|fst|vcd)$")
OK_MARKER = "public-ok"


def git(*args):
    res = subprocess.run(["git", *args], capture_output=True, text=True, check=False)
    if res.returncode != 0:
        sys.exit(f"git {' '.join(args)}: {res.stderr.strip()}")
    return res.stdout


def load_patterns(uvm_root):
    pats = [(re.compile(p), why) for p, why in BUILTIN]
    path = os.environ.get("AOU_PUBLIC_PATTERNS") or os.path.join(uvm_root, "site", "public_patterns.txt")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    pats.append((re.compile(line), "site pattern"))
    else:
        print(f"note: no site pattern file ({path}); built-in patterns only", file=sys.stderr)
    return pats


def scan_lines(lines, pats, where, hits):
    for lineno, text in lines:
        if text.rstrip().endswith(OK_MARKER):
            continue
        for rx, why in pats:
            m = rx.search(text)
            if m:
                hits.append(f"{where(lineno)}: {why}: {m.group(0)!r}")
                break


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--range", help="also scan added lines and messages of commits in A..B, e.g. main..HEAD")
    ap.add_argument("paths", nargs="*", help="limit the tree scan to these paths")
    args = ap.parse_args()
    uvm_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    top = git("rev-parse", "--show-toplevel").strip()
    os.chdir(top)
    pats = load_patterns(uvm_root)
    hits = []

    for f in git("ls-files", "-z", *args.paths).split("\0"):
        if not f or SKIP_FILES.search(f) or not os.path.isfile(f):
            continue
        try:
            with open(f, encoding="utf-8") as fh:
                lines = list(enumerate(fh, 1))
        except UnicodeDecodeError:
            continue
        scan_lines(lines, pats, lambda n, f=f: f"{f}:{n}", hits)

    if args.range:
        for sha in git("rev-list", args.range).split():
            msg = git("log", "-1", "--format=%B", sha)
            scan_lines(list(enumerate(msg.splitlines(), 1)), pats, lambda n, s=sha: f"commit {s[:9]} message", hits)
            cur = None
            for line in git("show", "--format=", "--unified=0", sha, "--", *args.paths).splitlines():
                if line.startswith("+++ "):
                    cur = line[6:]
                elif line.startswith("+") and cur and not SKIP_FILES.search(cur):
                    scan_lines([(0, line[1:])], pats, lambda n, s=sha, c=cur: f"commit {s[:9]} adds to {c}", hits)

    seen = set()
    for h in hits:
        if h not in seen:
            seen.add(h)
            print(h)
    print(f"{len(seen)} internal reference(s)" if seen else "clean", file=sys.stderr)
    sys.exit(1 if seen else 0)


if __name__ == "__main__":
    main()
