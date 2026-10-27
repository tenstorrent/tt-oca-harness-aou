#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for regress.py (make regress).

A fake `make` on PATH stands in for make build, make run and the query targets:
it logs every call, builds nothing, and prints what the real flow prints (the run
directory, check_run.py's verdict). regress.py drives the real run_list.py over
the real sim configs and testlists, restricted with --items so a run takes
seconds. Nothing is simulated and nothing goes to LSF. Run:
python3 scripts/test_regress.py
"""

import csv
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
REGRESS = os.path.join(SCRIPTS, "regress.py")
UVM_ROOT = os.path.dirname(SCRIPTS)


def planned(tb, testlist, items):
    """The test of each run run_list.py plans on 1x512-sp64 (its --dry-run), so the expected
    counts follow the testlists instead of being written into this test."""
    p = subprocess.run([sys.executable, "-I", os.path.join(SCRIPTS, "run_list.py"), "--tb", tb,
                        "--target", "1x512-sp64", "--dry-run", os.path.join(UVM_ROOT, testlist),
                        "--items", *items.split()], capture_output=True, text=True, check=True)
    return [ln.split()[1] for ln in p.stdout.splitlines() if ln.startswith("run ")]

FAKE_MAKE = textwrap.dedent("""\
    #!/usr/bin/env python3
    import os, sys
    v = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a and not a.startswith("-"))
    goal = next(a for a in sys.argv[1:] if "=" not in a and not a.startswith("-"))
    with open(os.environ["FAKE_LOG"], "a") as fh:
        fh.write(goal + " " + " ".join(f"{k}={v[k]}" for k in sorted(v)) + "\\n")
    if goal in ("stale-check", "job-hooks"):
        sys.exit(0)
    if goal == "lsf-bsub":
        print("bsub -K -q normal -env all")
        sys.exit(0)
    tb = v.get("TB", "t1")
    name = v.get("SIM", "vcs") + "-" + tb
    if tb in ("t1", "reg"):
        name += "-" + v.get("CONFIG", "1x512-sp64")
    name += "-cov" if v.get("COV") == "1" else ""
    name += "-assert" if v.get("RTL_ASSERT") == "1" else ""
    if goal == "build-name":
        print(name)
        sys.exit(0)
    if goal == "build":
        sys.exit(1 if name in os.environ.get("FAKE_BUILD_FAIL", "").split() else 0)
    if goal == "run":
        test = v["TEST"]
        run_dir = os.path.join(v["OUT_DIR"], f"{test}.rid.{v['RID']}.seed.{v['SEED']}.uid.{os.getpid()}")
        os.makedirs(run_dir)
        print("Run directory: " + run_dir, flush=True)
        if test in os.environ.get("FAKE_XPASS", "").split():
            print("XPASS: expected failure did not occur; review the entry")
        print(("FAIL" if test in os.environ.get("FAKE_FAIL", "").split() else "PASS") + " " + test)
        sys.exit(0)
    sys.exit("fake make: unknown goal " + goal)
""")


class Regress(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.bin = os.path.join(self.dir, "bin")
        os.makedirs(self.bin)
        path = os.path.join(self.bin, "make")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(FAKE_MAKE)
        os.chmod(path, 0o700)
        self.out = os.path.join(self.dir, "out")
        self.log = os.path.join(self.dir, "make.log")
        self.env = {k: v for k, v in os.environ.items() if k not in ("MAKEFLAGS", "MFLAGS", "MAKELEVEL", "LSF")}
        self.env.update(PATH=self.bin + os.pathsep + os.environ["PATH"], MAKE=path, FAKE_LOG=self.log)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def regress(self, *argv, **env):
        e = dict(self.env, **env)
        return subprocess.run([sys.executable, REGRESS, "--out-root", self.out, "--lsf", "0", "-j", "4",
                               "--configs", "1x512-sp64", *argv], env=e, capture_output=True, text=True,
                              check=False, timeout=600)

    def calls(self, goal):
        try:
            with open(self.log, encoding="utf-8") as fh:
                return [ln.split(" ", 1)[1].strip() for ln in fh if ln.startswith(goal + " ")]
        except FileNotFoundError:
            return []

    def test_dry_run_verilator(self):
        p = self.regress("--sim", "verilator", "--rid", "d1", "--dry-run")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("assert: skipped", p.stdout)
        self.assertIn("# build: 4 job(s)", p.stdout)     # t1, reg, l3_unit, axi_selftest
        self.assertIn("run(s) in all", p.stdout)
        self.assertEqual(self.calls("build"), [])
        self.assertEqual(self.calls("run"), [])
        self.assertFalse(os.path.exists(os.path.join(self.out, "regress")))

    def test_dry_run_vcs_cov(self):
        p = self.regress("--sim", "vcs", "--rid", "d2", "--cov", "1", "--dry-run")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("RTL_ASSERT=1", p.stdout)
        self.assertIn("TB=t1 COV=1 CONFIG=1x512-sp64", p.stdout)
        self.assertIn("TB=l3_unit COV=0", p.stdout)
        self.assertIn("cov_report SIM=vcs TB=t1 COV=1 CONFIG=1x512-sp64 COV_RID=d2", p.stdout)
        self.assertIn("--union", p.stdout)
        self.assertIn("COV_EL=cov/config/vcs/cov_exclude.el", p.stdout)

    def test_items_skip_benches_without_them(self):
        p = self.regress("--sim", "vcs", "--rid", "d3", "--items", "smoke", "--dry-run")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("assert-1x512-sp64: none of ITEMS", p.stdout)
        self.assertIn("--items smoke", p.stdout)

    def test_run_summary_resume_rerun(self):
        items = ("--items", "smoke assertions")
        p = self.regress("--sim", "vcs", "--rid", "r1", *items,
                         FAKE_FAIL="aou_fdi_t1_bringup_test", FAKE_XPASS="aou_reg_hw_reset_test")
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertEqual(len(self.calls("build")), 5)    # t1, reg, assert, l3_unit, axi_selftest
        self.assertIn("RTL_ASSERT=1", " ".join(self.calls("build")))
        with open(os.path.join(self.out, "regress", "r1", "summary.md"), encoding="utf-8") as fh:
            summary = fh.read()
        for sec in ("## T1", "## reg", "## assert", "## l3_unit", "## axi_selftest"):
            self.assertIn(sec, summary)
        t1 = planned("t1", "testlists/all.toml", "smoke assertions")
        nf = t1.count("aou_fdi_t1_bringup_test")
        reg = planned("reg", "testlists/registers.toml", "smoke")
        nx = reg.count("aou_reg_hw_reset_test")
        self.assertTrue(nf and nx)
        self.assertIn(f"| vcs-t1-1x512-sp64 | {len(t1)} | {len(t1) - nf} | 0 | {nf} | 0 |", summary)
        self.assertIn(f"| vcs-reg-1x512-sp64 | {len(reg)} | {len(reg)} | 0 | 0 | {nx} |", summary)
        self.assertIn("FAIL vcs-t1-1x512-sp64 aou_fdi_t1_bringup_test", summary)
        self.assertIn("TEST=aou_fdi_t1_bringup_test SEED=", summary)
        self.assertIn("Result: FAIL", summary)
        self.assertTrue(os.path.exists(os.path.join(self.out, "regress", "r1", "commands.sh")))
        runs = len(self.calls("run"))

        # Resume: every build has results for r1, so nothing is run again.
        p = self.regress("--sim", "vcs", "--rid", "r1", *items, "--steps", "run,summary")
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertEqual(len(self.calls("run")), runs)
        self.assertEqual(len(self.calls("build")), 5)
        self.assertIn("has results for rid r1; skipped", p.stdout)

        # Rerun the failures under a new RID: only the T1 and reg builds have any.
        p = self.regress("--sim", "vcs", "--rid", "r2", "--rerun-failed", "r1")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(len(self.calls("build")), 7)
        new = [c for c in self.calls("run") if "RID=r2" in c]
        self.assertEqual(sorted({c.split("TEST=")[1].split()[0] for c in new}),
                         ["aou_fdi_t1_bringup_test", "aou_reg_hw_reset_test"])
        self.assertIn("Result: PASS", p.stdout)

    def test_partial_results(self):
        # A drained or interrupted run_list.py leaves a results file short of its plan.
        items = ("--items", "smoke", "--benches", "t1")
        n = len(planned("t1", "testlists/all.toml", "smoke"))
        p = self.regress("--sim", "vcs", "--rid", "p1", *items)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        files = glob.glob(os.path.join(self.out, "vcs-t1-1x512-sp64", "results*.rid.p1.csv"))
        with open(files[0], newline="", encoding="utf-8") as fh:
            rows = list(csv.reader(fh))
        with open(files[0], "w", newline="", encoding="utf-8") as fh:
            csv.writer(fh).writerows(rows[:-1])
        p = self.regress("--sim", "vcs", "--rid", "p1", *items, "--steps", "summary")
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertIn(f"vcs-t1-1x512-sp64: {n - 1} of {n} runs have results", p.stdout)
        self.assertIn("Result: FAIL", p.stdout)
        runs = len(self.calls("run"))
        p = self.regress("--sim", "vcs", "--rid", "p1", *items, "--steps", "run,summary")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn(f"has {n - 1} of {n} runs for rid p1; running it again", p.stdout)
        self.assertEqual(len(self.calls("run")), runs + n)
        self.assertIn("Result: PASS", p.stdout)

    def test_build_failure(self):
        p = self.regress("--sim", "vcs", "--rid", "b1", "--items", "smoke", "--benches", "t1 reg",
                         FAKE_BUILD_FAIL="vcs-reg-1x512-sp64")
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertNotIn("TB=reg", " ".join(self.calls("run")))
        self.assertIn("vcs-reg-1x512-sp64: build failed", p.stdout)
        rows = []
        for f in glob.glob(os.path.join(self.out, "vcs-t1-1x512-sp64", "results*.rid.b1.csv")):
            with open(f, newline="", encoding="utf-8") as fh:
                rows += list(csv.DictReader(fh))
        self.assertEqual(len(rows), len(planned("t1", "testlists/all.toml", "smoke")))

    def test_rebuild_failure_on_reused_rid(self):
        # Results from an earlier build under the same RID must not hide a failed rebuild.
        items = ("--items", "smoke", "--benches", "t1")
        p = self.regress("--sim", "vcs", "--rid", "f1", *items)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        p = self.regress("--sim", "vcs", "--rid", "f1", *items, FAKE_BUILD_FAIL="vcs-t1-1x512-sp64")
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertIn("vcs-t1-1x512-sp64: build failed", p.stdout)
        self.assertIn("Result: FAIL", p.stdout)

    def test_bad_options(self):
        self.assertNotEqual(self.regress("--rid", "a b", "--dry-run").returncode, 0)
        self.assertNotEqual(self.regress("--cov-mem", "16000", "--dry-run").returncode, 0)
        self.assertNotEqual(self.regress("--steps", "cov", "--dry-run").returncode, 0)
        self.assertNotEqual(self.regress("--rid", "x", "--rerun-failed", "x").returncode, 0)


if __name__ == "__main__":
    unittest.main()
