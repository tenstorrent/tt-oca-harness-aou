#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for gen_readme.py and gh_import.py's body transform.

Builds fixture drafts under a temporary directory.
Run from hw/ip/aou/dv: python3 -I scripts/bugs/test_gen_readme.py
"""

import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_readme  # noqa: E402
import gh_import  # noqa: E402

GOOD = {
    "kind": "dut-bug", "severity": "high", "state": "open", "status": '"open; fix verified"',
    "area": "[rx-core]", "needs": "[owner-decision]", "blocked_by": "[]", "related": "[]",
    "fix_branch": "bugfix/BUGS-001-x", "fix_pushed": "true", "fix_verdict": "accepted",
    "issue_github": "",
}
CONFIG = "areas:\n  rx-core: {description: RX}\n  credit: {description: credit}\n"
README = "# Drafts\n\nintro\n\n%s\nold\n%s\n\ntail\n" % (gen_readme.BEGIN, gen_readme.END)


def draft_text(bid, title, **over):
    meta = dict(GOOD)
    meta.update(over)
    fm = "".join(f"{k}: {v}\n" for k, v in meta.items() if v is not None)
    return f"---\n{fm}---\n# {bid}: {title}\n\n- **Impact:** x.\n\n## Summary\n\nText.\n"


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.write("README.md", README)
        self.write("github.yaml", CONFIG)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        with open(os.path.join(self.dir, name), "w", encoding="utf-8") as fh:
            fh.write(text)

    def add(self, bid, title="T", **over):
        self.write(f"{bid}-slug.md", draft_text(bid, title, **over))

    def errors(self, allow_private=False):
        return gen_readme.load(self.dir, allow_private)[1]

    def assertError(self, fragment, allow_private=False):
        errs = self.errors(allow_private)
        self.assertTrue(any(fragment in e for e in errs), f"{fragment!r} not in {errs}")

    def run_main(self, *args):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = gen_readme.main(["--dir", self.dir, *args])
        return rc, err.getvalue()


class ParseTest(Fixture):
    def test_parse_reads_meta_and_title(self):
        self.add("001", "First bug", related='["002"]')
        self.add("002", "Second", fix_branch=None, fix_pushed="false", fix_verdict="none")
        drafts, errs = gen_readme.load(self.dir)
        self.assertEqual(errs, [])
        d = drafts[0]
        self.assertEqual((d.id, d.title, d.get("kind"), d.get("related")),
                         ("001", "First bug", "dut-bug", ["002"]))
        self.assertTrue(d.get("fix_pushed"))
        self.assertIsNone(drafts[1].get("issue_github"))

    def test_template_and_readme_are_skipped(self):
        self.add("001")
        self.write("TEMPLATE.md", "---\nkind: bogus\n---\n# NNN: x\n")
        drafts, errs = gen_readme.load(self.dir)
        self.assertEqual(([d.id for d in drafts], errs), (["001"], []))

    def test_no_front_matter(self):
        self.write("001-x.md", "# 001: x\n")
        self.assertError("no YAML front matter")

    def test_bad_yaml(self):
        self.write("001-x.md", "---\nkind: [\n---\n# 001: x\n")
        self.assertError("not valid YAML")

    def test_missing_title(self):
        self.write("001-x.md", "---\nkind: dut-bug\n---\n# 002: wrong id\n")
        self.assertError("no '# 001: <title>' heading")


class ValidateTest(Fixture):
    def test_unknown_key(self):
        self.add("001", colour="red")
        self.assertError("unknown key 'colour'")

    def test_issue_gitlab_is_unknown(self):
        self.add("001", issue_gitlab="")
        self.assertError("unknown key 'issue_gitlab'")

    def test_title_length(self):
        self.add("001", "x" * gen_readme.MAX_TITLE)
        self.assertEqual(self.errors(), [])
        self.add("001", "x" * (gen_readme.MAX_TITLE + 1))
        self.assertError(f"title is {gen_readme.MAX_TITLE + 1} characters, more than 72")

    def test_missing_required(self):
        self.add("001", severity=None)
        self.assertError("missing required key 'severity'")

    def test_missing_list_key(self):
        self.add("001", related=None)
        self.assertError("missing required key 'related'")

    def test_bad_enums(self):
        for key, value in (("kind", "bug"), ("severity", "urgent"), ("state", "wip"),
                           ("fix_verdict", "maybe")):
            with self.subTest(key=key):
                self.add("001", **{key: value})
                self.assertError(f"{key} {value!r} is not one of")

    def test_bad_needs(self):
        self.add("001", needs="[review]")
        self.assertError("needs value 'review' is not one of")

    def test_area_not_in_vocabulary(self):
        self.add("001", area="[gpu]")
        self.assertError("area value 'gpu' is not one of")

    def test_area_unchecked_without_config(self):
        os.remove(os.path.join(self.dir, "github.yaml"))
        self.add("001", area="[anything]")
        orig = gen_readme.HERE
        gen_readme.HERE = self.dir   # no github.yaml next to the "script" either
        try:
            self.assertEqual(self.errors(), [])
        finally:
            gen_readme.HERE = orig

    def test_area_count(self):
        self.add("001", area="[]")
        self.assertError("area needs 1-3 values")

    def test_status_must_be_string(self):
        self.add("001", status="42")
        self.assertError("status must be a quoted string")

    def test_fix_pushed_bool(self):
        self.add("001", fix_pushed="yes please")
        self.assertError("fix_pushed must be true or false")

    def test_list_not_list(self):
        self.add("001", blocked_by='"002"')
        self.assertError("blocked_by must be a list")

    def test_unquoted_id(self):
        self.add("001", related="[2]")
        self.assertError("is not a quoted draft id")

    def test_missing_targets(self):
        for key in ("blocked_by", "related"):
            with self.subTest(key=key):
                self.add("001", **{key: '["009"]'})
                self.assertError(f"{key} refers to missing draft 009")

    def test_self_reference(self):
        self.add("001", related='["001"]')
        self.assertError("related refers to itself")

    def test_merged_needs_target(self):
        self.add("001", state="merged", fix_branch=None, fix_verdict="none")
        self.assertError("state merged needs merged_into")

    def test_merged_into_missing(self):
        self.add("001", state="merged", merged_into='"005"', fix_branch=None, fix_verdict="none")
        self.assertError("merged_into refers to missing draft 005")

    def test_merged_into_merged(self):
        self.add("001", state="merged", merged_into='"002"', fix_branch=None, fix_verdict="none")
        self.add("002", state="merged", merged_into='"003"', fix_branch=None, fix_verdict="none")
        self.add("003")
        self.assertError("merged_into 002, which is itself merged")

    def test_merged_with_fix_branch(self):
        self.add("001", state="merged", merged_into='"002"')
        self.add("002")
        self.assertError("a merged draft has no fix_branch")

    def test_merged_into_on_open(self):
        self.add("001", merged_into='"002"')
        self.add("002")
        self.assertError("merged_into is only for state merged")

    def test_closed_needs_reason(self):
        self.add("001", state="closed")
        self.assertError("state closed needs closed_reason")
        self.add("001", state="closed", closed_reason="wontfix")
        self.assertError("state closed needs closed_reason")

    def test_closed_reason_on_open(self):
        self.add("001", closed_reason="completed")
        self.assertError("closed_reason is only for state closed")

    def test_resolved_needs_resolved_by(self):
        self.add("001", state="resolved")
        self.assertError("state resolved needs resolved_by")
        self.add("001", state="resolved", resolved_by='"PR 89"')
        self.assertError("resolved_by value 'PR 89' is not a quoted PR")
        self.add("001", state="resolved", resolved_by='["#89", "1a2b3c4d"]')
        self.assertEqual(self.errors(), [])
        self.add("001", state="resolved", resolved_by='"o/r#89"')
        self.assertEqual(self.errors(), [])

    def test_resolved_by_only_for_resolved(self):
        self.add("001", resolved_by='"#89"')
        self.assertError("resolved_by is only for state resolved")

    def test_branch_without_verdict(self):
        self.add("001", fix_verdict="none")
        self.assertError("fix_branch is set but fix_verdict is none")

    def test_tracker_private_only(self):
        self.add("001", tracker="[KEY-1]")
        self.assertError("'tracker' is for private drafts only")
        self.assertEqual(self.errors(allow_private=True), [])

    def test_errors_fail_main(self):
        self.add("001", kind="bug")
        rc, err = self.run_main("--check")
        self.assertEqual(rc, 1)
        self.assertIn("001-slug.md: kind 'bug'", err)


class RenderTest(Fixture):
    def make_set(self):
        self.add("001", "Root", related='["004"]')
        self.add("002", "Child", state="merged", merged_into='"001"', fix_branch=None,
                 fix_pushed="false", fix_verdict="none", status='"merged into 001"')
        self.add("003", "Spec", kind="spec-doc-conflict", severity="low", fix_branch=None,
                 fix_pushed="false", fix_verdict="none", status='"open"')
        self.add("004", "Done", kind="documentation", state="closed", closed_reason="completed",
                 fix_branch=None, fix_pushed="false", fix_verdict="none", status='"closed"',
                 issue_github="https://example.invalid/issues/4")
        self.add("005", "Local fix", fix_branch="bugfix/BUGS-005-y", fix_pushed="false")

    def test_includes_derived(self):
        self.make_set()
        drafts, _ = gen_readme.load(self.dir)
        self.assertEqual({d.id: d.includes for d in drafts},
                         {"001": ["002"], "002": [], "003": [], "004": [], "005": []})

    def test_summary_line(self):
        self.make_set()
        drafts, _ = gen_readme.load(self.dir)
        self.assertEqual(gen_readme.summary(drafts),
                         "Open drafts by kind: DUT bug 2 (001, 005); Spec/doc conflict 1 (003). "
                         "Merged: 1 (002). Closed: 1 (004).")

    def test_summary_without_closed(self):
        self.add("001")
        drafts, _ = gen_readme.load(self.dir)
        self.assertEqual(gen_readme.summary(drafts),
                         "Open drafts by kind: DUT bug 1 (001). Merged: 0 ().")

    def test_table_cells(self):
        self.make_set()
        drafts, _ = gen_readme.load(self.dir)
        by_id = {d.id: d for d in drafts}
        cells = {d.id: gen_readme.item(by_id, d) for d in drafts}
        self.assertEqual(cells["001"]["related"],
                         "merged: [002](002-slug.md); [004](004-slug.md)")
        self.assertEqual(cells["002"]["branch"], "`BUGS/001`")
        self.assertEqual(cells["005"]["branch"], "`bugfix/BUGS-005-y` (not pushed)")
        self.assertEqual(cells["003"]["kind"], "Spec/doc conflict")
        self.assertEqual(cells["003"]["severity"], "Low")
        self.assertEqual(cells["004"]["issue"], "https://example.invalid/issues/4")

    def test_resolved_cells_and_summary(self):
        self.add("001", "Fixed", state="resolved", resolved_by='["#89", "1a2b3c4"]',
                 status='"fixed; bench entries to retire"')
        self.add("002")
        drafts, _ = gen_readme.load(self.dir)
        by_id = {d.id: d for d in drafts}
        self.assertEqual(gen_readme.item(by_id, by_id["001"])["resolved"], "#89, 1a2b3c4")
        self.assertEqual(gen_readme.item(by_id, by_id["002"])["resolved"], "")
        self.assertEqual(gen_readme.summary(drafts),
                         "Open drafts by kind: DUT bug 1 (002). "
                         "Resolved, follow-ups open: 1 (001). Merged: 0 ().")
        self.assertIn(",resolved,fixed; bench entries to retire,#89 1a2b3c4,",
                      gen_readme.render_csv(drafts).splitlines()[1])

    def test_resolved_issue(self):
        self.add("001", "Fixed", state="resolved", resolved_by='"#89"',
                 status='"fixed; bench entries to retire"')
        drafts, _ = gen_readme.load(self.dir)
        repo = gh_import.Repo("o/r", "abc123", [])
        issue, _ = gh_import.issue_for(drafts[0], {}, repo, {"001"}, None)
        self.assertEqual(issue["state"], "open")
        self.assertIsNone(issue["state_reason"])
        self.assertIn("status:resolved", issue["labels"])
        self.assertTrue(issue["body"].startswith(
            "**Resolved by:** #89; open until the follow-ups are done: fixed; bench entries "
            "to retire"))

    def issue(self, **over):
        self.add("001", **over)
        drafts, _ = gen_readme.load(self.dir)
        return gh_import.issue_for(drafts[0], {}, gh_import.Repo("o/r", "abc", []), {"001"},
                                   None)[0]["body"]

    def test_fix_branch_published_only_as_pushed_link(self):
        url = "https://github.com/me/r/tree/bugfix/12-x"
        self.assertNotIn("bugfix/BUGS-001-x", self.issue(fix_pushed="false"))
        self.assertNotIn("bugfix/BUGS-001-x", self.issue(fix_pushed="true"))
        self.assertTrue(self.issue(fix_branch=url).startswith(f"**Fix:** {url} (accepted)"))
        self.assertNotIn(url, self.issue(fix_branch=url, fix_pushed="false"))
        self.assertTrue(self.issue(fix_branch='"#12"').startswith("**Fix:** #12 (accepted)"))

    def test_internal_notes_dropped(self):
        text = ("# 001: T\n\n## Summary\n\nKeep.\n\n## Internal notes\n\nJira KEY-1, "
                "/proj/x\n```\n## not a heading\n```\nmore\n\n## Reproduce\n\nKeep too.\n")
        out = gh_import.strip_internal(text)
        self.assertNotIn("KEY-1", out)
        self.assertNotIn("not a heading", out)
        self.assertIn("Keep.", out)
        self.assertIn("## Reproduce\n\nKeep too.", out)

    def test_write_then_check(self):
        self.make_set()
        self.assertEqual(self.run_main("--check")[0], 1)       # README and index.csv stale
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(self.run_main("--check"), (0, ""))
        with open(os.path.join(self.dir, "README.md"), encoding="utf-8") as fh:
            text = fh.read()
        self.assertTrue(text.startswith("# Drafts\n\nintro\n\n" + gen_readme.BEGIN))
        self.assertTrue(text.endswith(gen_readme.END + "\n\ntail\n"))
        self.assertIn('"title": "Root"', text)
        with open(os.path.join(self.dir, "index.csv"), encoding="utf-8") as fh:
            rows = fh.read().splitlines()
        self.assertEqual(rows[0], ",".join(gen_readme.CSV_COLUMNS))
        self.assertTrue(rows[1].startswith("001,Root,dut-bug,high,open,"))
        self.assertIn(",002,rx-core,", rows[1])
        self.add("003", "Spec changed", kind="spec-doc-conflict", severity="low",
                 fix_branch=None, fix_pushed="false", fix_verdict="none", status='"open"')
        rc, err = self.run_main("--check")
        self.assertEqual(rc, 1)
        self.assertIn("out of date", err)

    def test_missing_markers(self):
        self.add("001")
        self.write("README.md", "no markers\n")
        rc, err = self.run_main()
        self.assertEqual(rc, 1)
        self.assertIn("missing the BEGIN/END markers", err)


class ImportTransformTest(unittest.TestCase):
    def setUp(self):
        files = ["RTL/AOU_RX_CORE.sv", "RTL/AXI4MUX_3X1/AOU_AXI_DOWN.v",
                 "DOC/MAS/overview.adoc", "hw/ip/aou/dv/expected_fail.yaml"]
        self.repo = gh_import.Repo("o/r", "abc123", files)
        self.t = gh_import.Transform(self.repo, {"001", "002"})

    def test_draft_links_and_mentions(self):
        out = self.t.body("See [002](002-x.md), [the fix](001-y.md#fix) and BUGS/001; "
                          "`BUGS/002`; branch bugfix/BUGS-001-z; BUGS/009.")
        self.assertEqual(out, "See #{002}, the fix (#{001}) and #{001}; #{002}; "
                              "branch bugfix/BUGS-001-z; BUGS/009.")
        self.assertEqual(self.t.unresolved_ids, {"009"})

    def test_permalinks(self):
        out = self.t.body("`RTL/AOU_RX_CORE.sv:668-680`, RTL/AOU_RX_CORE.sv:43. "
                          "`AOU_AXI_DOWN.v:219`, `DOC/MAS/overview.adoc:64`, `RTL/NOPE.sv`")
        base = "https://github.com/o/r/blob/abc123/"
        self.assertEqual(out, (
            f"[`RTL/AOU_RX_CORE.sv:668-680`]({base}RTL/AOU_RX_CORE.sv#L668-L680), "
            f"[RTL/AOU_RX_CORE.sv:43]({base}RTL/AOU_RX_CORE.sv#L43). "
            f"[`AOU_AXI_DOWN.v:219`]({base}RTL/AXI4MUX_3X1/AOU_AXI_DOWN.v#L219), "
            f"[`DOC/MAS/overview.adoc:64`]({base}DOC/MAS/overview.adoc?plain=1#L64), "
            "`RTL/NOPE.sv`"))
        self.assertEqual(self.t.unresolved_paths, {"RTL/NOPE.sv"})

    def test_fenced_code_untouched(self):
        text = "BUGS/001\n```verilog\n// BUGS/001 RTL/AOU_RX_CORE.sv:1\n```\nBUGS/002"
        self.assertEqual(self.t.body(text),
                         "#{001}\n```verilog\n// BUGS/001 RTL/AOU_RX_CORE.sv:1\n```\n#{002}")

    def test_resolve_placeholders(self):
        self.assertEqual(gh_import.resolve_placeholders("#{001} and #{003}", {"001": 17}),
                         "#17 and BUGS/003")


if __name__ == "__main__":
    unittest.main()
