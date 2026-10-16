#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Check how expected_fail.yaml names its bugs.

The record of a DUT bug is its GitHub issue on tenstorrent/tt-oca-harness-aou
(AGENTS.md "Reporting bugs"), so a `bug:` or `requires:` value is

  tenstorrent/tt-oca-harness-aou#<number>   a filed issue, or
  BUGS/NNN                                  a draft still staged in the git-ignored
                                            BUGS/ directory, not filed yet.

Anything else is an error (exit status 1). Staged citations are allowed, since a
failure is tied to its bug before the user files the issue, but they are counted
and listed so they do not linger: scripts/bugs/rewrite_refs.py replaces them once
the drafts are filed. --no-staged makes a staged citation an error too (the
end state, once every draft is filed).
"""

import argparse
import collections
import os
import re
import sys

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPECTED = os.path.join(UVM_ROOT, "expected_fail.yaml")
REPO = "tenstorrent/tt-oca-harness-aou"
ISSUE_RE = re.compile(r"^%s#[1-9][0-9]*$" % re.escape(REPO))
STAGED_RE = re.compile(r"^BUGS/[0-9]{3}$")
FIELD_RE = re.compile(r"^\s*-?\s*(bug|requires):\s*(.*?)\s*(?:#.*)?$")


def scan(path):
    """-> (issue citations, staged citations, bad lines) of the bug/requires fields."""
    issues, staged, bad = collections.Counter(), collections.Counter(), []
    with open(path, encoding="utf-8") as fh:
        for ln, line in enumerate(fh, 1):
            m = FIELD_RE.match(line)
            if not m:
                continue
            value = m.group(2).strip().strip("'\"")
            if ISSUE_RE.match(value):
                issues[value] += 1
            elif STAGED_RE.match(value):
                staged[value] += 1
            else:
                bad.append(f"{os.path.relpath(path, UVM_ROOT)}:{ln}: {m.group(1)}: {value!r} "
                           f"is neither {REPO}#<n> nor BUGS/NNN")
    return issues, staged, bad


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--expected", default=EXPECTED, help="expected_fail.yaml")
    ap.add_argument("--no-staged", action="store_true",
                    help="a BUGS/NNN citation is an error (every draft has been filed)")
    args = ap.parse_args(argv)
    issues, staged, bad = scan(args.expected)
    for b in bad:
        print(b, file=sys.stderr)
    if staged:
        ids = ", ".join(f"{k} ({v})" for k, v in sorted(staged.items()))
        msg = (f"check_bug_refs: {sum(staged.values())} citation(s) of {len(staged)} staged "
               f"draft(s) not yet filed as issues: {ids}")
        if args.no_staged:
            print(msg, file=sys.stderr)
            bad.append(msg)
        else:
            print(msg)
    print(f"check_bug_refs: {sum(issues.values())} citation(s) of {len(issues)} GitHub issue(s), "
          f"{sum(staged.values())} of {len(staged)} staged draft(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
