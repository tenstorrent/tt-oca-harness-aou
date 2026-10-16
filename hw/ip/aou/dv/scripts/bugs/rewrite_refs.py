#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Replace `BUGS/NNN` citations in the bench with the GitHub issue each draft became.

usage: rewrite_refs.py [--dir BUGS] [--root hw/ip/aou/dv] [--dry-run]

After gh_import.py --apply has written `issue_github:` into the staged drafts, every
`BUGS/NNN` in the bench (expected_fail.yaml, checkers/rules.csv, testlists, plan files,
documents, SystemVerilog comments) is replaced by `tenstorrent/tt-oca-harness-aou#<n>`,
the form scripts/check_bug_refs.py accepts. Fix-branch names (`bugfix/BUGS-NNN-...`) and
drafts whose front matter has no issue yet are left alone; those are listed, and the exit
status is 1 while any citation of an unfiled draft remains. --dry-run reports without
writing.
"""

import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_readme  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
SKIP_DIRS = {".deps", "site", "build", "out", "tools", ".git", "__pycache__"}
EXTS = {".yaml", ".yml", ".toml", ".csv", ".md", ".adoc", ".sv", ".svh", ".v", ".py", ".txt"}
REF_RE = re.compile(r"\bBUGS/(\d{3})(?![\w-])")
ISSUE_URL_RE = re.compile(r"https://github\.com/([\w.-]+/[\w.-]+)/issues/(\d+)$")


def issue_map(drafts):
    """draft id -> 'OWNER/NAME#n' for every draft with an issue_github URL."""
    out, unfiled = {}, []
    for d in drafts:
        m = ISSUE_URL_RE.match(str(d.get("issue_github") or ""))
        if m:
            out[d.id] = f"{m.group(1)}#{m.group(2)}"
        else:
            unfiled.append(d.id)
    return out, unfiled


def files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for f in sorted(filenames):
            if os.path.splitext(f)[1] in EXTS:
                yield os.path.join(dirpath, f)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", default=gen_readme.STAGING, help="staged drafts")
    ap.add_argument("--root", default=BENCH, help="tree to rewrite (default: the bench)")
    ap.add_argument("--dry-run", action="store_true", help="report; write nothing")
    args = ap.parse_args(argv)
    drafts, errs = gen_readme.load(args.dir, allow_private=True)
    if errs:
        print("\n".join(errs), file=sys.stderr)
        return 1
    mapping, unfiled = issue_map(drafts)
    known = {d.id for d in drafts}
    replaced, left, unknown = collections.Counter(), collections.Counter(), collections.Counter()
    for path in files(args.root):
        with open(path, encoding="utf-8", errors="surrogateescape") as fh:
            text = fh.read()

        def sub(m):
            bid = m.group(1)
            if bid in mapping:
                replaced[bid] += 1
                return mapping[bid]
            (left if bid in known else unknown)[bid] += 1
            return m.group(0)

        new = REF_RE.sub(sub, text)
        if new != text and not args.dry_run:
            with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(new)
    verb = "would replace" if args.dry_run else "replaced"
    print(f"rewrite_refs: {verb} {sum(replaced.values())} citation(s) of {len(replaced)} draft(s)")
    rc = 0
    if left:
        print("rewrite_refs: still cited, draft not filed: "
              + ", ".join(f"BUGS/{k} ({v})" for k, v in sorted(left.items())), file=sys.stderr)
        rc = 1
    if unknown:
        print("rewrite_refs: cited but no such draft in the staging area: "
              + ", ".join(f"BUGS/{k} ({v})" for k, v in sorted(unknown.items())), file=sys.stderr)
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
