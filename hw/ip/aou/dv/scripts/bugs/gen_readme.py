#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Validate the staged bug drafts' front matter and regenerate their index.csv and README table.

The drafts (NNN-*.md) live in the git-ignored staging area BUGS/ at the repository root
(hw/ip/aou/dv/AGENTS.md "Reporting bugs"); the record is the GitHub issue each becomes. Each
draft starts with YAML front matter (see TEMPLATE.md next to this script); the ID comes from
the file name and the title from the `# NNN: title` heading. index.csv and the table between
the BEGIN/END markers in README.md are generated from them, in the staging area.

usage: gen_readme.py [--dir DIR] [--allow-private]          rewrite index.csv and README.md
       gen_readme.py [--dir DIR] [--allow-private] --check  exit 1 on a schema error or if
                                                            either file is out of date
DIR defaults to BUGS/ at the repository root. --allow-private accepts the `tracker` key
(internal tracker references), which an issue body must not carry.
"""
import argparse
import collections
import csv
import glob
import io
import json
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
# The staging area: BUGS/ at the repository root (this script is six levels below it).
STAGING = os.path.abspath(os.path.join(HERE, *([os.pardir] * 6), "BUGS"))
BEGIN = "<!-- BEGIN table generated from the drafts' front matter by gen_readme.py -->"
END = "<!-- END generated table -->"
DRAFT_GLOB = "[0-9][0-9][0-9]-*.md"
MAX_TITLE = 72            # characters after "NNN: "; a short issue title, detail goes in the body

KINDS = {
    "dut-bug": "DUT bug",
    "rtl-doc-mismatch": "RTL/doc mismatch",
    "spec-doc-conflict": "Spec/doc conflict",
    "documentation": "Documentation",
    "testbench": "Testbench",
}
SEVERITIES = {"high": "High", "medium": "Medium", "low": "Low"}
# open: the problem stands. resolved: a merged PR or commit fixed it (DUT, documentation or
# spec), but follow-ups (testbench, test plan, ...) keep the draft and its issue open.
# merged: folded into another draft. closed: done (closed_reason says how).
STATES = ("open", "resolved", "merged", "closed")
CLOSED_REASONS = ("completed", "not-planned")
NEEDS = ("owner-decision", "spec-clarification", "docs")
VERDICTS = ("accepted", "proposal", "rejected", "none")
PRIVATE_KEYS = ("tracker",)
LIST_KEYS = ("area", "needs", "blocked_by", "related")
REQUIRED = ("kind", "severity", "state", "status", "fix_verdict") + LIST_KEYS
OPTIONAL = ("merged_into", "closed_reason", "resolved_by", "fix_branch", "fix_pushed",
            "issue_github") + PRIVATE_KEYS
ID_LISTS = ("blocked_by", "related")
# What resolved a draft: a PR (#89, or owner/repo#89) or a commit SHA (7-40 hex digits).
RESOLVED_BY_RE = re.compile(r"(?:[\w.-]+/[\w.-]+)?#\d+|[0-9a-f]{7,40}")

CSV_COLUMNS = ["id", "title", "kind", "severity", "state", "status", "resolved_by", "merged_into",
               "includes",
               "area", "needs", "blocked_by", "related", "fix_branch", "fix_pushed",
               "fix_verdict", "issue_github"]
FIELDS = [
    ("id", "ID"),
    ("title", "Title"),
    ("kind", "Kind"),
    ("severity", "Severity"),
    ("status", "Status"),
    ("resolved", "Resolved by"),
    ("related", "Related"),
    ("branch", "Fix branch"),
    ("issue", "Issue"),
]


class Draft:
    def __init__(self, path, meta, title, body):
        self.path = path
        self.file = os.path.basename(path)
        self.id = self.file[:3]
        self.meta = meta
        self.title = title
        self.body = body          # everything after the front matter
        self.includes = []        # drafts merged into this one (derived)

    def get(self, key, default=None):
        v = self.meta.get(key)
        return default if v is None else v


def split_front_matter(text):
    """Return (front matter text, rest), or (None, text) if the file has none."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 3)
    if end < 0:
        return None, text
    return text[4:end + 1], text[end + 5:]


def parse(path):
    """Parse one draft. Returns (Draft or None, [errors])."""
    name = os.path.basename(path)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fm, rest = split_front_matter(text)
    if fm is None:
        return None, [f"{name}: no YAML front matter (--- ... ---) at the top"]
    try:
        meta = yaml.safe_load(fm)
    except yaml.YAMLError as exc:
        return None, [f"{name}: front matter is not valid YAML: {exc}"]
    if not isinstance(meta, dict):
        return None, [f"{name}: front matter must be a mapping"]
    m = re.search(rf"^# {name[:3]}: (.+)$", rest, re.M)
    if not m:
        return None, [f"{name}: no '# {name[:3]}: <title>' heading"]
    return Draft(path, meta, m.group(1).strip(), rest), []


def is_id(v):
    return isinstance(v, str) and re.fullmatch(r"\d{3}", v) is not None


def check_list(d, key, allowed=None, lo=0, hi=None):
    v = d.meta.get(key)
    if not isinstance(v, list):
        return [f"{d.file}: {key} must be a list (use [] for none)"]
    errs = []
    if len(v) < lo or (hi is not None and len(v) > hi):
        errs.append(f"{d.file}: {key} needs {lo}-{hi} values, has {len(v)}")
    if len(set(map(str, v))) != len(v):
        errs.append(f"{d.file}: {key} has duplicates")
    for x in v:
        if allowed is not None and x not in allowed:
            errs.append(f"{d.file}: {key} value {x!r} is not one of {', '.join(allowed)}")
    return errs


def check_enum(d, key, allowed):
    v = d.meta.get(key)
    if v is not None and v not in allowed:
        return [f"{d.file}: {key} {v!r} is not one of {', '.join(allowed)}"]
    return []


def validate(drafts, areas=None, allow_private=False):
    """Schema and cross-reference checks. areas: allowed area names, or None to skip."""
    errs = []
    by_id = {d.id: d for d in drafts}
    for d in drafts:
        m = d.meta
        if len(d.title) > MAX_TITLE:
            errs.append(f"{d.file}: title is {len(d.title)} characters, more than {MAX_TITLE}; "
                        "keep it short and move the detail into the Summary")
        for k in m:
            if k not in REQUIRED + OPTIONAL:
                errs.append(f"{d.file}: unknown key {k!r}")
            elif k in PRIVATE_KEYS and not allow_private:
                errs.append(f"{d.file}: {k!r} is for private drafts only (--allow-private)")
        for k in REQUIRED:
            if k not in m or (k not in LIST_KEYS and m[k] in (None, "")):
                errs.append(f"{d.file}: missing required key {k!r}")
        errs += check_enum(d, "kind", KINDS)
        errs += check_enum(d, "severity", SEVERITIES)
        errs += check_enum(d, "state", STATES)
        errs += check_enum(d, "fix_verdict", VERDICTS)
        if m.get("status") is not None and not isinstance(m["status"], str):
            errs.append(f"{d.file}: status must be a quoted string")
        if m.get("fix_pushed") is not None and not isinstance(m["fix_pushed"], bool):
            errs.append(f"{d.file}: fix_pushed must be true or false")
        if "area" in m:
            errs += check_list(d, "area", sorted(areas) if areas is not None else None, 1, 3)
        if "needs" in m:
            errs += check_list(d, "needs", NEEDS)
        if "tracker" in m and allow_private:
            errs += check_list(d, "tracker")
        for k in ID_LISTS:
            if k not in m:
                continue
            errs += check_list(d, k)
            for x in m[k] if isinstance(m[k], list) else []:
                if not is_id(x):
                    errs.append(f"{d.file}: {k} value {x!r} is not a quoted draft id like \"001\"")
                elif x not in by_id:
                    errs.append(f"{d.file}: {k} refers to missing draft {x}")
                elif x == d.id:
                    errs.append(f"{d.file}: {k} refers to itself")
        state = m.get("state")
        mi = m.get("merged_into")
        if state == "merged":
            if not mi:
                errs.append(f"{d.file}: state merged needs merged_into")
            elif not is_id(mi):
                errs.append(f"{d.file}: merged_into {mi!r} is not a quoted draft id like \"001\"")
            elif mi not in by_id:
                errs.append(f"{d.file}: merged_into refers to missing draft {mi}")
            elif by_id[mi].get("state") == "merged":
                errs.append(f"{d.file}: merged_into {mi}, which is itself merged")
            if m.get("fix_branch"):
                errs.append(f"{d.file}: a merged draft has no fix_branch (its fix is on {mi}'s)")
        elif mi:
            errs.append(f"{d.file}: merged_into is only for state merged")
        rb = m.get("resolved_by")
        if state == "resolved":
            refs = rb if isinstance(rb, list) else [rb] if rb not in (None, "") else []
            if not refs:
                errs.append(f"{d.file}: state resolved needs resolved_by "
                            "(a PR such as \"#89\", a commit SHA, or a list of them)")
            for r in refs:
                if not isinstance(r, str) or not RESOLVED_BY_RE.fullmatch(r):
                    errs.append(f"{d.file}: resolved_by value {r!r} is not a quoted PR "
                                "(\"#89\", \"owner/repo#89\") or commit SHA")
        elif rb not in (None, "", []):
            errs.append(f"{d.file}: resolved_by is only for state resolved")
        cr = m.get("closed_reason")
        if state == "closed":
            if cr not in CLOSED_REASONS:
                errs.append(f"{d.file}: state closed needs closed_reason "
                            f"({' or '.join(CLOSED_REASONS)})")
        elif cr:
            errs.append(f"{d.file}: closed_reason is only for state closed")
        if m.get("fix_branch") and m.get("fix_verdict") == "none":
            errs.append(f"{d.file}: fix_branch is set but fix_verdict is none")
    return errs


def load_config(directory):
    """github.yaml from DIR, else from next to this script; {} if neither exists."""
    for base in (directory, HERE):
        path = os.path.join(base, "github.yaml")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                return yaml.safe_load(fh) or {}
    return {}


def load(directory, allow_private=False):
    """Parse and validate every draft in DIR. Returns (drafts, errors)."""
    drafts, errs = [], []
    for path in sorted(glob.glob(os.path.join(directory, DRAFT_GLOB))):
        d, e = parse(path)
        errs += e
        if d:
            drafts.append(d)
    cfg = load_config(directory)
    areas = set(cfg["areas"]) if cfg.get("areas") else None
    errs += validate(drafts, areas, allow_private)
    by_id = {d.id: d for d in drafts}
    for d in drafts:
        mi = d.get("merged_into")
        if d.get("state") == "merged" and mi in by_id:
            by_id[mi].includes.append(d.id)
    return drafts, errs


def link(by_id, bid):
    return f"[{bid}]({by_id[bid].file})" if bid in by_id else bid


def branch_cell(by_id, d):
    # A merged draft's fix, if any, is on the branch of the draft it was merged into.
    if d.get("state") == "merged":
        target = by_id.get(d.get("merged_into"))
        return f"`BUGS/{target.id}`" if target and target.get("fix_branch") else ""
    if not d.get("fix_branch"):
        return ""
    return f"`{d.get('fix_branch')}`" + ("" if d.get("fix_pushed") else " (not pushed)")


def resolved_refs(d):
    """resolved_by as a list of strings (it may be one string or a list)."""
    rb = d.get("resolved_by")
    return [] if rb in (None, "") else [str(x) for x in (rb if isinstance(rb, list) else [rb])]


def issue_cell(d):
    refs = [str(d.get("issue_github"))] if d.get("issue_github") else []
    refs += [str(t) for t in d.get("tracker", [])]
    return ", ".join(refs)


def item(by_id, d):
    related = []
    if d.includes:
        related.append("merged: " + ", ".join(link(by_id, b) for b in d.includes))
    if d.get("related"):
        related.append(", ".join(link(by_id, b) for b in d.get("related")))
    return {
        "id": link(by_id, d.id),
        "title": d.title,
        "kind": KINDS[d.get("kind")],
        "severity": SEVERITIES[d.get("severity")],
        "status": d.get("status"),
        "resolved": ", ".join(resolved_refs(d)),
        "related": "; ".join(related),
        "branch": branch_cell(by_id, d),
        "issue": issue_cell(d),
    }


def summary(drafts):
    open_by = collections.defaultdict(list)
    resolved, merged, closed = [], [], []
    for d in drafts:
        state = d.get("state")
        if state == "resolved":
            resolved.append(d.id)
        elif state == "merged":
            merged.append(d.id)
        elif state == "closed":
            closed.append(d.id)
        else:
            open_by[d.get("kind")].append(d.id)
    parts = [f"{KINDS[k]} {len(open_by[k])} ({', '.join(open_by[k])})" for k in KINDS if open_by[k]]
    text = f"Open drafts by kind: {'; '.join(parts)}. "
    if resolved:
        text += f"Resolved, follow-ups open: {len(resolved)} ({', '.join(resolved)}). "
    text += f"Merged: {len(merged)} ({', '.join(merged)})."
    if closed:
        text += f" Closed: {len(closed)} ({', '.join(closed)})."
    return text


def render_table(drafts):
    by_id = {d.id: d for d in drafts}
    # One field or item per line, so a row change is a one-line diff.
    dump = lambda v: json.dumps(v, ensure_ascii=False)
    fields = ",\n".join("  " + dump({"key": k, "label": lbl, "sortable": True}) for k, lbl in FIELDS)
    items = ",\n".join("  " + dump(item(by_id, d)) for d in drafts)
    return "\n".join([
        BEGIN,
        "",
        "```json:table",
        '{"filter": true, "markdown": true,',
        ' "fields": [',
        fields,
        " ],",
        ' "items": [',
        items,
        " ]}",
        "```",
        "",
        summary(drafts),
        "",
        END,
    ])


def render_csv(drafts):
    def cell(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, list):
            return " ".join(map(str, v))
        return "" if v is None else str(v)

    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(CSV_COLUMNS)
    for d in drafts:
        row = {"id": d.id, "title": d.title, "includes": d.includes,
               "resolved_by": resolved_refs(d)}
        w.writerow([cell(row[c] if c in row else d.meta.get(c)) for c in CSV_COLUMNS])
    return buf.getvalue()


def render_readme(text, drafts, name="README.md"):
    if BEGIN not in text or END not in text:
        raise ValueError(f"{name}: missing the BEGIN/END markers")
    head, rest = text.split(BEGIN, 1)
    tail = rest.split(END, 1)[1]
    return head + render_table(drafts) + tail


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", default=STAGING,
                    help="drafts directory (default: BUGS/ at the repository root)")
    ap.add_argument("--check", action="store_true",
                    help="validate; exit 1 if index.csv or README.md is out of date")
    ap.add_argument("--allow-private", action="store_true",
                    help="accept the private-only tracker key")
    args = ap.parse_args(argv)
    drafts, errs = load(args.dir, args.allow_private)
    if not drafts and not errs:
        errs.append(f"{args.dir}: no {DRAFT_GLOB} drafts")
    if errs:
        print("\n".join(errs), file=sys.stderr)
        return 1
    readme = os.path.join(args.dir, "README.md")
    index = os.path.join(args.dir, "index.csv")
    with open(readme, encoding="utf-8") as fh:
        old_readme = fh.read()
    try:
        new_readme = render_readme(old_readme, drafts, readme)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1
    new_index = render_csv(drafts)
    old_index = None
    if os.path.exists(index):
        with open(index, encoding="utf-8") as fh:
            old_index = fh.read()
    stale = [(p, new) for p, old, new in ((readme, old_readme, new_readme),
                                          (index, old_index, new_index)) if old != new]
    if args.check:
        if stale:
            print(f"out of date: {', '.join(p for p, _ in stale)}; run gen_readme.py"
                  + ("" if os.path.abspath(args.dir) == STAGING else f" --dir {args.dir}"),
                  file=sys.stderr)
            return 1
        return 0
    for path, new in stale:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
