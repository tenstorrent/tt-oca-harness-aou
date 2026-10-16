#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Check checkers/rules.csv against the rule IDs the testbench uses.

Emitted IDs are rule IDs inside SystemVerilog string literals (report
messages, rule-ledger keys, expectation keys). A string literal counts when the
ID's family (the part before the first '-') is one rules.csv already uses, or
when the literal starts with "<ID>:" (a report of a new family). Comments and
the run-list/expected-fail YAML only reference IDs.

Errors (exit status 1):
  - an emitted or referenced ID with no row in rules.csv;
  - a row that is never emitted, unless its checker is "via <rule>",
    "by construction ...", "n/a ..." or "not checked", its scope is N/A, or it
    is in EXEMPT below with the reason;
  - a "via <rule>" row naming a rule with no row; a duplicated row.
"""

import argparse
import csv
import os
import re
import sys

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ID = r"[A-Z][A-Z0-9]*-[A-Z][A-Z0-9]*[0-9]"
ID_RE = re.compile(r"(?<![A-Za-z0-9_-])(" + ID + r")(?![A-Za-z0-9_])")
LEAD_RE = re.compile(r"^(" + ID + r"):")
SKIP_DIRS = {".deps", "site", "build", "out", "tools", ".git"}
UNEMITTED_OK = ("via ", "by construction", "n/a", "not checked")

# Rows that are checked but whose ID is never in a testbench string literal.
EXEMPT = {
    "REG-R01": "reported by UVM's uvm_reg_hw_reset_seq, whose messages carry no rule ID",
}


def load_rules(path):
    rows, dups = {}, []
    with open(path, encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["rule"] in rows:
                dups.append(r["rule"])
            rows[r["rule"]] = r
    return rows, dups


def sv_split(text):
    """(string literals, comment text) of a SystemVerilog source."""
    strings, comments = [], []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            comments.append(text[i:j])
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            comments.append(text[i:j])
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            strings.append(text[i + 1:j])
            i = j + 1
        else:
            i += 1
    return strings, comments


def sources(root, exts):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for f in sorted(filenames):
            if f.endswith(exts):
                yield os.path.join(dirpath, f)


def scan(root, families):
    """({id: first emitting file}, {id: first referencing file})."""
    emitted, referenced = {}, {}
    for path in sources(root, (".sv", ".svh")):
        with open(path, encoding="utf-8", errors="replace") as fh:
            strings, comments = sv_split(fh.read())
        rel = os.path.relpath(path, root)
        for s in strings:
            lead = LEAD_RE.match(s)
            for m in ID_RE.finditer(s):
                rid = m.group(1)
                if rid.split("-")[0] in families or (lead and lead.group(1) == rid):
                    emitted.setdefault(rid, rel)
        for c in comments:
            for m in ID_RE.finditer(c):
                if m.group(1).split("-")[0] in families:
                    referenced.setdefault(m.group(1), rel)
    for path in sources(root, (".yaml", ".toml")):
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for m in ID_RE.finditer(text):
            if m.group(1).split("-")[0] in families:
                referenced.setdefault(m.group(1), os.path.relpath(path, root))
    return emitted, referenced


def check(rules_path, root):
    rules, dups = load_rules(rules_path)
    families = {k.split("-")[0] for k in rules}
    emitted, referenced = scan(root, families)
    errors = [f"rules.csv: {r} has more than one row" for r in dups]
    for rid, where in sorted(emitted.items()):
        if rid not in rules:
            errors.append(f"{where}: {rid} is emitted but has no row in rules.csv")
    for rid, where in sorted(referenced.items()):
        if rid not in rules and rid not in emitted:
            errors.append(f"{where}: {rid} is referenced but has no row in rules.csv")
    for rid, row in sorted(rules.items()):
        checker = (row.get("checker") or "").strip()
        via = re.match(r"via (\S+)", checker)
        if via and via.group(1) not in rules:
            errors.append(f"rules.csv: {rid} is checked via {via.group(1)}, which has no row")
        if rid in emitted:
            if rid in EXEMPT:
                errors.append(f"rules.csv: {rid} is emitted; drop it from EXEMPT")
            continue
        if (rid in EXEMPT or checker.startswith(UNEMITTED_OK)
                or (row.get("scope") or "").strip() == "N/A"):
            continue
        errors.append(f"rules.csv: {rid} ({checker}) is never emitted by the testbench")
    for rid in sorted(set(EXEMPT) - set(rules)):
        errors.append(f"check_rules.py: EXEMPT lists {rid}, which has no row")
    return errors, len(rules), len(emitted)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rules", default=os.path.join(UVM_ROOT, "uvm", "env", "checkers", "rules.csv"))
    ap.add_argument("--root", default=UVM_ROOT, help="testbench tree to scan")
    args = ap.parse_args()
    errors, nrules, nemitted = check(args.rules, args.root)
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        return 1
    print(f"check_rules: {nrules} rules, {nemitted} emitted, all listed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
