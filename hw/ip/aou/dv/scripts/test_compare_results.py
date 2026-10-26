#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-test of scripts/compare_results.py: python3 scripts/test_compare_results.py"""

import csv
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare_results  # noqa: E402

HEADER = ["test", "seed", "plusargs", "status", "plan_ids", "run_dir"]


def write(root, build, name, rows, rid="r1"):
    d = os.path.join(root, build)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(HEADER)
        for test, seed, args, status in rows:
            w.writerow([test, seed, args, status, "",
                        f"/o/{build}/{test}.rid.{rid}.seed.{seed}.time.2026.10.26-10.00.00.uid.1"])


class Compare(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = os.path.join(self.tmp.name, "base")
        self.after = os.path.join(self.tmp.name, "after")
        write(self.base, "vcs-t1-1x512-sp64", "results_g1a.csv", [
            ("t_same", 1, "+a=1 +b=2", "PASS"),
            ("t_worse", 1, "", "PASS"),
            ("t_xfail_fail", 1, "", "XFAIL"),
            ("t_xfail_pass", 1, "", "XFAIL"),
            ("t_fixed", 1, "", "FAIL"),
            ("t_xpass", 1, "", "XFAIL+XPASS"),
            ("t_dropped", 1, "", "PASS"),
        ])
        write(self.base, "vcs-t1-4x512-sp64", "results.csv", [("t_same", 1, "", "PASS")])
        write(self.after, "vcs-t1-1x512-sp64", "results_g1a.csv", [
            ("t_same", 1, "+b=2 +a=1", "PASS"),
            ("t_worse", 1, "", "XFAIL"),
            ("t_xfail_fail", 1, "", "FAIL"),
            ("t_xfail_pass", 1, "", "PASS"),
            ("t_fixed", 1, "", "XFAIL"),
            ("t_xpass", 1, "", "XFAIL"),
            ("t_new", 1, "", "PASS"),
        ])
        write(self.after, "vcs-t1-4x512-sp64", "results.csv", [("t_same", 1, "", "PASS")])

    def tearDown(self):
        self.tmp.cleanup()

    def classify(self, **kw):
        base, _ = compare_results.load([self.base], **kw)
        after, _ = compare_results.load([self.after], **kw)
        res = compare_results.compare(base, after)
        return {cat: sorted(k[3] for k, _, _ in rows) for cat, rows in res.items()}

    def test_categories(self):
        c = self.classify()
        self.assertEqual(c["degraded"], ["t_worse", "t_xfail_fail"])
        self.assertEqual(c["dropped"], ["t_dropped"])
        self.assertEqual(c["new"], ["t_new"])
        self.assertEqual(c["fixed"], ["t_fixed"])
        self.assertEqual(c["xfail_to_pass"], ["t_xfail_pass"])
        self.assertEqual(c["xpass_changed"], ["t_xpass"])
        self.assertEqual(c["same"], ["t_same", "t_same"])  # plusarg order ignored; both builds

    def test_norm_args_drops_the_config_name(self):
        self.assertEqual(compare_results.norm_args("+perf_scn=S1 +aou_config=1x512-sp64"), "+perf_scn=S1")
        self.assertEqual(compare_results.norm_args("+aou_config=1x512-sp64"), "")

    def test_build_key_separates_configs(self):
        base, _ = compare_results.load([self.base])
        self.assertEqual(sorted({k[2] for k in base}), ["1x512-sp64", "4x512-sp64"])
        self.assertTrue(all(k[0] == "vcs" for k in base))

    def test_sim_agnostic(self):
        os.rename(os.path.join(self.after, "vcs-t1-4x512-sp64"), os.path.join(self.after, "verilator-t1-4x512-sp64"))
        c = self.classify()
        self.assertIn("t_same", c["dropped"])
        c = self.classify(sim_agnostic=True)
        self.assertEqual(c["dropped"], ["t_dropped"])

    def test_duplicates_pair_by_occurrence(self):
        # One run key twice on each side (two lists): both pairs are compared, none is lost.
        write(self.base, "vcs-t1-1x512-sp64", "results_g1b.csv", [("t_same", 1, "+a=1 +b=2", "PASS")])
        write(self.after, "vcs-t1-1x512-sp64", "results_g1b.csv", [("t_same", 1, "+a=1 +b=2", "FAIL")])
        base, dups = compare_results.load([self.base])
        self.assertEqual(len(base), 9)
        self.assertEqual([k[3] for k in dups], ["t_same"])
        c = self.classify()
        self.assertEqual(c["degraded"], ["t_same", "t_worse", "t_xfail_fail"])
        # A third occurrence on the after side only is new, not a silent overwrite.
        write(self.after, "vcs-t1-1x512-sp64", "results_g1c.csv", [("t_same", 1, "+a=1 +b=2", "PASS")])
        self.assertEqual(self.classify()["new"], ["t_new", "t_same"])

    def test_cov_build_folds(self):
        os.rename(os.path.join(self.after, "vcs-t1-4x512-sp64"),
                  os.path.join(self.after, "vcs-t1-4x512-sp64-cov-axi4pc"))
        os.rename(os.path.join(self.base, "vcs-t1-4x512-sp64"),
                  os.path.join(self.base, "vcs-t1-4x512-sp64-axi4pc"))
        self.assertEqual(self.classify()["same"], ["t_same", "t_same"])
        self.assertEqual(compare_results.build_of("/o/vcs-t1-1x512-sp64-cov/results.csv"),
                         ("vcs", "t1", "1x512-sp64"))
        self.assertEqual(compare_results.build_of("/o/vcs-t1-2xmix-sp64-rxf-cov/r.csv"),
                         ("vcs", "t1", "2xmix-sp64-rxf"))

    def test_rid_filter(self):
        write(self.after, "vcs-t1-1x512-sp64", "results_g1a.r2.csv", [("t_worse", 1, "", "FAIL")], rid="r2")
        self.assertEqual(self.classify()["new"], ["t_new", "t_worse"])
        after, _ = compare_results.load([self.after], rid="r2")
        self.assertEqual([k[3] for k in after], ["t_worse"])
        import io
        import contextlib
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(compare_results.main([self.base, self.after, "--rid", "r1"]), 1)
            self.assertEqual(compare_results.main([self.base, self.after, "--rid", "nope"]), 2)
            self.assertEqual(compare_results.main([self.base, self.base, "--base-rid", "r1",
                                                   "--after-rid", "r1"]), 0)

    def test_main_exit_status(self):
        out = os.path.join(self.tmp.name, "report.md")
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            rc = compare_results.main([self.base, self.after, "-o", out])
        self.assertEqual(rc, 1)
        text = open(out, encoding="utf-8").read()
        self.assertIn("| Degradations (verdict got worse) | 2 |", text)
        self.assertIn("| vcs-t1-1x512-sp64 t_worse seed=1 | PASS | XFAIL |", text)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(compare_results.main([self.base, self.base]), 0)


if __name__ == "__main__":
    unittest.main()
