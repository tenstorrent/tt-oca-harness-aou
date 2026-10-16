#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for listyaml, gen_plan_items, plan_status and check_run.

Builds fixture plans, run lists and run directories under a temporary
directory. Run: python3 scripts/test_plan_status.py
"""

import contextlib
import io
import itertools
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_run  # noqa: E402
import gen_plan_items  # noqa: E402
import listyaml  # noqa: E402
import plan_status  # noqa: E402

PLAN = """\
## 2. Test Plan

### 2.1 Link Activation Tests

| ID | Test File | Description | Coverage Goals | Priority | Status |
| :---- | :---- | :---- | :---- | :---- | :---- |
| 1.1 | flits_test | Handshake | FSM | P0 | 100% |
| 1.2 | flits_test | **[NEG]** Simultaneous | Concurrent | P1 | |

### 2.10 Performance Tests

| ID | Test File | Description | Coverage Goals | Priority | Status |
| :---- | :---- | :---- | :---- | :---- | :---- |
| 10.1 | tput_test | Write throughput | BW | P1 | |
| 10.10 | gh issue #64 B zero cycles | Backpressure | P1 | |

## 3. Coverage Metrics

| 3.1 | not | an | item | P0 | |
"""

ITEMS = """\
- id: '1.1'
  section: '2.1'
  section_title: Link
  title: covered item
  priority: P0
- id: '1.2'
  section: '2.1'
  section_title: Link
  title: xfail item
  priority: P1
- id: '1.3'
  section: '2.1'
  section_title: Link
  title: failing item
  priority: P1
- id: '1.4'
  section: '2.1'
  section_title: Link
  title: blocked item
  priority: P2
- id: '1.10'
  section: '2.1'
  section_title: Link
  title: not covered item
  priority: P2
- id: '1.5'
  section: '2.1'
  section_title: Link
  title: duplicate of 1.1
  priority: P1
  merged_into: '1.1'
- id: '1.6'
  section: '2.1'
  section_title: Link
  title: obsolete
  priority: P2
  dropped: not in this RTL
"""

RUNLIST = """\
schema_version = 1
[[tests]]
name = "t_pass"
module = { uvm = "t_pass" }
target = "1x512-sp64"
seed = 1
reseed = 2
args = ["+a=1", "+b=2"]
[[tests]]
name = "t_xfail"
seed = 1
reseed = 2
[[tests]]
name = "t_fail"
module = { uvm = "t_fail" }
target = "4x512-sp64"
[[tests]]
name = "t_blocked"
tags = ["blocked"]
[[tests]]
name = "t_norun"
"""
PLAN_IDS = """\
plan_ids:
  t_pass: '1.5'
  t_xfail: '1.2'
  t_fail: '1.3,1.2'
  t_blocked: '1.4'
  t_norun: '1.10,9.9'
blocked:
  t_blocked: 'BUGS/099'
"""


UID = itertools.count()


def make_run(out, build, test, args, verdict=None, log=None, run_sh=True, age=3600):
    d = os.path.join(out, build, f"{test}.rid.00.seed.1.time.x.uid.{next(UID)}")
    os.makedirs(d)
    if run_sh:
        with open(os.path.join(d, "run.sh"), "w") as fh:
            fh.write(f"set -o pipefail\ncd {d}\n/b/simv +UVM_TESTNAME={test} +ntb_random_seed=1 "
                     f"+AXI4_FC_RPT_DIR={d} {args} 2>&1 | tee {d}/sim.log\n")
    if verdict is not None:
        with open(os.path.join(d, "verdict.txt"), "w") as fh:
            fh.write(verdict)
    if log is not None:
        p = os.path.join(d, "sim.log")
        with open(p, "w") as fh:
            fh.write(log)
        os.utime(p, (time.time() - age, time.time() - age))
    return d


class ListYaml(unittest.TestCase):
    def test_parse(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "x.yaml")
            with open(p, "w") as fh:
                fh.write("# c\n- test: a  # trailing\n  plan_ids: [4.1, 4.10]\n  q: 'it''s: #x'\n"
                         "  note: >-\n    two\n    lines\n- test: b\n  plusargs: \"+x=1,2\"\n")
            e = listyaml.load(p)
            self.assertEqual(e[0], {"test": "a", "plan_ids": ["4.1", "4.10"], "q": "it's: #x", "note": "two lines"})
            self.assertEqual(listyaml.ids("4.1,4.10"), ["4.1", "4.10"])
            self.assertEqual(listyaml.ids("4.1 4.10"), ["4.1", "4.10"])
            with open(p, "w") as fh:
                fh.write(listyaml.dump([{"id": "4.10", "t": "a: b", "l": ["1.2"]}], ["id", "t", "l"]))
            self.assertEqual(listyaml.load(p), [{"id": "4.10", "t": "a: b", "l": ["1.2"]}])


class GenPlanItems(unittest.TestCase):
    def test_parse_and_correct(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "plan.md")
            with open(p, "w") as fh:
                fh.write(PLAN)
            items = gen_plan_items.parse_plan(p)
            self.assertEqual([i["id"] for i in items], ["1.1", "1.2", "10.1", "10.10"])
            self.assertEqual(items[1]["title"], "[NEG] Simultaneous")
            self.assertEqual(items[3]["section"], "2.10")
            self.assertIsNone(items[3]["old_test"])
            errs = gen_plan_items.apply_corrections(items, [
                {"id": "1.2", "merged_into": "1.1", "note": "dup"},
                {"id": "10.1", "title": "new words", "note": "fixed"},
            ])
            self.assertEqual(errs, [])
            self.assertEqual(items[2]["old_title"], "Write throughput")
            errs = gen_plan_items.apply_corrections(items, [
                {"id": "10.10", "merged_into": "1.2", "note": "chain"},
                {"id": "7.7", "note": "x"}, {"id": "1.1", "title": "no note"},
            ])
            self.assertEqual(len(errs), 3)

    def test_added_item(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "plan.md")
            with open(p, "w") as fh:
                fh.write(PLAN)
            items = gen_plan_items.parse_plan(p)
            errs = gen_plan_items.apply_corrections(items, [
                {"id": "1.3", "added": "AoU 8.2", "title": "new", "priority": "P2", "note": "gap"},
            ])
            self.assertEqual(errs, [])
            self.assertEqual([i["id"] for i in items], ["1.1", "1.2", "1.3", "10.1", "10.10"])
            self.assertEqual((items[2]["section_title"], items[2]["added"]), ("Link Activation Tests", "AoU 8.2"))
            errs = gen_plan_items.apply_corrections(items, [
                {"id": "1.1", "added": "x", "title": "t", "priority": "P1", "note": "exists"},
                {"id": "10.2", "added": "x", "title": "t", "priority": "P1", "note": "out of order"},
                {"id": "5.1", "added": "x", "title": "t", "priority": "P1", "note": "no section"},
            ])
            self.assertEqual(len(errs), 3)


class PlanStatus(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.items = os.path.join(t, "items.yaml")
        self.rl = os.path.join(t, "rl.toml")
        self.pids = os.path.join(t, "plan_ids.yaml")
        self.out = os.path.join(t, "out")
        self.exp = os.path.join(t, "expected_fail.yaml")
        for path, text in ((self.items, ITEMS), (self.rl, RUNLIST), (self.pids, PLAN_IDS), (self.exp, "")):
            with open(path, "w") as fh:
                fh.write(text)
        o = self.out
        os.makedirs(o)
        # Plusargs order, wave and coverage arguments don't matter.
        make_run(o, "vcs-t1-1x512-sp64-cov", "t_pass", "+b=2 +a=1 +waves", "XPASS: stale entry\nPASS: log\n")
        make_run(o, "vcs-t1-1x512-sp64", "t_pass", "+a=1", "PASS: log\n")              # other plusargs
        make_run(o, "vcs-t1-4x512-sp64", "t_pass", "+a=1 +b=2", "PASS: log\n")            # other config
        make_run(o, "verilator-t1-1x512-sp64", "t_xfail", "", "XFAIL: 1 error(s), all known (BUGS/001): l\n")
        make_run(o, "vcs-t1-4x512-sp64", "t_fail", "", "FAIL: 1 unexpected error(s) in l\n  UVM_ERROR x\n")
        make_run(o, "vcs-t1-1x512-sp64", "t_xfail", "", None, run_sh=False)            # being created
        make_run(o, "vcs-t1-1x512-sp64", "t_xfail", "", None, log="UVM_INFO\n")        # unjudged
        make_run(o, "vcs-t1-4x512-sp64", "t_xfail", "", "PASS: log\n")                    # no config: any
        make_run(o, "vcs-t1-1x512-sp64", "t_norun", "", None, log="still running\n", age=0)

    def tearDown(self):
        self.tmp.cleanup()

    def run_ps(self, *extra):
        buf, err = io.StringIO(), io.StringIO()
        argv = ["--items", self.items, "--runlist", self.rl, "--plan-ids", self.pids, "--out-dir", self.out,
                "--expected", self.exp, *extra]
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
            plan_status.main(argv)
        return buf.getvalue(), err.getvalue()

    def statuses(self, *extra):
        out, _ = self.run_ps("--format", "csv", *extra)
        return {row.split(",")[0]: row.split(",")[3] for row in out.splitlines()[1:]}

    def test_statuses(self):
        st = self.statuses()
        self.assertEqual(st, {"1.1": "covered", "1.2": "covered", "1.3": "failing", "1.4": "blocked",
                              "1.10": "not covered", "1.5": "merged", "1.6": "dropped"})

    def test_infra_plusargs_ignored(self):
        with open(self.rl, "a") as fh:
            fh.write('[[tests]]\nname = "t_inf"\ntarget = "1x512-sp64"\nargs = ["+k=1"]\n')
        with open(self.pids, "a") as fh:
            fh.write("plan_ids:\n  t_inf: '1.10'\n")
        make_run(self.out, "vcs-t1-1x512-sp64-fix-p", "t_inf", "+k=1 +x=2 +FDI_ENC=SPEC", "PASS: log\n")
        self.assertEqual(self.statuses()["1.10"], "not covered")
        make_run(self.out, "vcs-t1-1x512-sp64-fix-p", "t_inf",
                 f"+FDI_ENC=SPEC +k=1 +aou_fc_json={self.out}/fc.json +waves", "PASS: log\n")
        self.assertEqual(self.statuses()["1.10"], "covered")

    def test_xfail_only_names_bug(self):
        with open(self.rl, "a") as fh:
            fh.write('[[tests]]\nname = "t_x2"\ntarget = "4x512-sp64"\n')
        with open(self.pids, "a") as fh:
            fh.write("plan_ids:\n  t_x2: '1.4'\n")
        make_run(self.out, "vcs-t1-4x512-sp64", "t_x2", "", "XFAIL: 2 error(s), all known (BUGS/002, BUGS/003): l\n")
        out, _ = self.run_ps()
        row = next(line for line in out.splitlines() if line.startswith("| 1.4 "))
        self.assertIn("xfail-only", row)
        self.assertIn("BUGS/002, BUGS/003", row)

    def test_markdown_summary(self):
        out, err = self.run_ps()
        self.assertIn("| covered | 2 | 1 | 1 | 0 |", out)
        self.assertIn("| 2.1 Link | 5 | 2 | 0 | 1 | 1 | 1 | 1 | 1 |", out)
        self.assertIn("- 9.9 (rl.toml)", out)
        self.assertIn("| vcs-t1-1x512-sp64 | t_pass | +a=1 | 1 |", out)
        self.assertIn("2 unjudged", out)
        self.assertIn("1 incomplete", out)
        self.assertIn("2 covered, 0 xfail-only, 1 failing, 1 blocked, 1 not covered", err)
        self.assertIn("t_pass +a=1 +b=2 [t1/1x512-sp64, seeds 1/2]", out)

    def test_judge(self):
        log = "UVM_INFO x\n--- UVM Report Summary ---\n"
        make_run(self.out, "vcs-t1-1x512-sp64", "t_norun", "", None, log=log)
        out, _ = self.run_ps("--judge")
        self.assertIn("0 unjudged", out)
        self.assertIn("2 incomplete", out)  # no run.sh, and a log still being written
        self.assertEqual(self.statuses("--judge")["1.10"], "covered")


class BuildKey(unittest.TestCase):
    def test_hyphenated_configs(self):
        for build, want in (("vcs-t1-1x512-sp64-cov", ("t1", "1x512-sp64")),
                            ("verilator-t1-2xmix-tp64_128", ("t1", "2xmix-tp64_128")),
                            ("vcs-reg-4xmix4211-sp128-cov-fix-p", ("reg", "4xmix4211-sp128")),
                            ("vcs-t1-2x512-tp32_64-noaxi", ("t1", "2x512-tp32_64-noaxi")),
                            ("vcs-l3_unit", ("l3_unit", "")), ("vcs", ("", ""))):
            self.assertEqual(plan_status.build_key(build), want, build)


class CheckRun(unittest.TestCase):
    EXPECTED = ("- test: t\n  bug: B1\n  check: 'R1: cut'\n  seed_dependent: true\n"
                "- test: t\n  bug: B1\n  check: 'V8: stall'\n  requires: B1\n  seed_dependent: true\n"
                "- test: t\n  bug: B2\n  check: 'V8: stall'\n  requires: B2\n  seed_dependent: true\n")

    def judge(self, *errors):
        log = "".join(f"UVM_ERROR x @ 1: r [c] {e}\n" for e in errors) + "--- UVM Report Summary ---\n"
        with tempfile.TemporaryDirectory() as t:
            path = os.path.join(t, "ef.yaml")
            with open(path, "w") as fh:
                fh.write(self.EXPECTED)
            lines = check_run.judge(log, "sim.log", path, "t")
            return next(x for x in lines if x.startswith(("PASS", "XFAIL", "FAIL")))

    def test_follow_on_needs_its_bug(self):
        self.assertTrue(self.judge("V8: stall").startswith("FAIL"))

    def test_follow_on_with_specific(self):
        self.assertEqual(self.judge("V8: stall", "R1: cut"), "XFAIL: 2 error(s), all known (B1): sim.log")

    def test_specific_alone(self):
        self.assertTrue(self.judge("R1: cut").startswith("XFAIL"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
