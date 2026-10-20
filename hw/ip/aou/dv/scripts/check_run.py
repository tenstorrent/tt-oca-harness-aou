#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Judge a run's sim.log against expected_fail.yaml.

PASS   no UVM_ERROR/UVM_FATAL, and the log reached the UVM report summary.
XFAIL  every error matches an expected-fail entry for this test (known DUT bug).
FAIL   any error that no entry explains, or no report summary (crash, hang, kill).
An entry that matched nothing is reported as XPASS (the bug may be fixed, so
review the entry), unless it is marked `seed_dependent: true`. Exit status is 0 for PASS and XFAIL, 1 otherwise.

An entry with `requires: <bug>` is a follow-on: a generic symptom (traffic did
not complete, not drained, ...) that the bug causes but that any other failure
could cause too. It explains an error only when an entry without `requires:`
for that bug, a bug-specific check, matched another error of the same run, so
a follow-on entry can never hide a new failure on its own.

An entry may give `check_re:` (a Python regular expression searched in the
error) instead of `check:`, for a bug whose signature is spread over fields of
one message (a rule ID and the transaction's size and address, say).

An entry with `when_re:` (a regular expression) applies only to runs whose log
matches it, e.g. one CONFIG of a test that runs on several: elsewhere it neither
explains errors nor reports XPASS.

The UVM_FATAL that stops a run after +aou_axi4pc_max Axi4PC errors
(uvm/env/axi4pc/aou_axi4pc_pkg.sv) adds nothing of its own: the run is judged
by the errors before it.
"""

import argparse
import re
import sys

ERR_RE = re.compile(r"^#?\s*(UVM_ERROR|UVM_FATAL)\s+(?!:)(.*)$")
TEST_RE = re.compile(r"\+UVM_TESTNAME=(\S+)|Running test (\S+)\.\.\.")
AXI4PC_STOP_RE = re.compile(r"\[AXI4PC\] \d+ Axi4PC violations, stopping")


def load_entries(path):
    """Read the simple list-of-maps YAML used by expected_fail.yaml."""
    entries, cur = [], None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            # Only whole-line comments: check strings may contain '#'.
            line = raw.rstrip()
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = re.match(r"^\s*(-\s+)?(\w+):\s*(.*)$", line)
            if not m:
                continue
            if m.group(1):
                cur = {}
                entries.append(cur)
            val = m.group(3).strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
                val = val[1:-1]
            if cur is not None:
                cur[m.group(2)] = val
    return entries


def judge(text, log, expected, test=None):
    """Return the verdict lines for one sim.log's text (last line PASS/XFAIL/FAIL)."""
    if not test:
        m = TEST_RE.search(text)
        test = next((g for g in (m.groups() if m else ()) if g), "")

    if "UVM Report Summary" not in text:
        return [f"FAIL: no UVM report summary (crash, kill or timeout): {log}"]

    errors = [m.group(0).strip() for m in map(ERR_RE.match, text.splitlines()) if m]
    errors = [e for e in errors if not AXI4PC_STOP_RE.search(e)]
    entries = [e for e in load_entries(expected) if e.get("test") in (test, "*")
               and (not e.get("when_re") or re.search(e["when_re"], text, re.M))]
    used, bugs = set(), set()

    def match(err, follow_on, evidenced=frozenset()):
        for i, e in enumerate(entries):
            if e.get("check_re"):
                if not re.search(e["check_re"], err):
                    continue
            elif not e.get("check") or e["check"] not in err:
                continue
            req = e.get("requires")
            if (req is not None) == follow_on and (req is None or req in evidenced):
                return i
        return None

    # Bug-specific entries first: they decide which bugs this run evidences.
    pending = []
    for err in errors:
        hit = match(err, False)
        if hit is None:
            pending.append(err)
        else:
            used.add(hit)
            bugs.add(entries[hit].get("bug", "?"))
    evidenced = frozenset(bugs)
    unexplained = []
    for err in pending:
        hit = match(err, True, evidenced)
        if hit is None:
            unexplained.append(err)
        else:
            used.add(hit)

    out = []
    for i, e in enumerate(entries):
        if i not in used and e.get("seed_dependent") != "true":
            out.append(f"XPASS: expected failure did not occur ({e.get('bug', '?')}: {e.get('check') or e.get('check_re', '')}); review the entry")

    if unexplained:
        out.append(f"FAIL: {len(unexplained)} unexpected error(s) in {log}")
        out += [f"  {err[:200]}" for err in unexplained[:10]]
    elif errors:
        out.append(f"XFAIL: {len(errors)} error(s), all known ({', '.join(sorted(bugs))}): {log}")
    else:
        out.append(f"PASS: {log}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log")
    ap.add_argument("--test", help="test name (default: read from the log)")
    ap.add_argument("--expected", required=True, help="expected_fail.yaml")
    args = ap.parse_args()

    text = open(args.log, encoding="utf-8", errors="replace").read()
    lines = judge(text, args.log, args.expected, args.test)
    print("\n".join(lines))
    return 1 if any(line.startswith("FAIL") for line in lines) else 0


if __name__ == "__main__":
    sys.exit(main())
