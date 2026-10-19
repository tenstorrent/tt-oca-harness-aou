#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for run_list.py's live control (and run_ctl.py).

A fake `make` on PATH stands in for `make run`: it logs when each run is
submitted, starts and ends, and prints what the real flow prints (run directory,
bsub's job-submitted and dispatch lines, the verdict). Nothing is simulated and
nothing goes to LSF. Run: python3 scripts/test_run_list.py

Tests that assert on concurrency or on when a change takes effect hold the fake
runs at a gate and release them explicitly, and wait for run_list's own log
lines rather than sleeping: on a loaded host process start-up alone can outlast
any fixed sleep.
"""

import ast
import contextlib
import csv
import io
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS)
import run_ctl  # noqa: E402
import run_list  # noqa: E402
import stale_build  # noqa: E402

FAKE_MAKE = textwrap.dedent("""\
    #!/usr/bin/env python3
    import fcntl, os, struct, sys, termios, time
    if "job-hooks" in sys.argv:
        if os.environ.get("FAKE_HOOKS"):
            bmod = sys.executable + " " + os.environ["FAKE_BIN"] + "/bmod"
            print("JOB_MODIFY_PRIORITY=" + bmod + " -sp {priority} {job}")
            print("JOB_MODIFY_QUEUE=" + bmod + " -q {queue} {job}")
        sys.exit(0)
    if "stale-check" in sys.argv:
        print(os.environ.get("FAKE_STALE", ""), file=sys.stderr)
        sys.exit(0)
    if "build-name" in sys.argv:
        print("fake-build")
        sys.exit(0)
    v = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    if os.environ.get("FAKE_ARGS"):
        with open(os.environ["FAKE_ARGS"], "a") as fh:
            fh.write(repr(sys.argv[1:]) + "\\n")
    gate = os.environ.get("FAKE_GATE", "")

    def event(kind):
        line = "%s %.3f %s %s %d prio=%s queue=%s\\n" % (kind, time.time(), v["TEST"], v["SEED"], os.getpid(),
                                                        v.get("JOB_PRIORITY", ""), v.get("JOB_QUEUE", ""))
        fd = os.open(os.environ["FAKE_EVENTS"], os.O_WRONLY | os.O_APPEND | os.O_CREAT)
        os.write(fd, line.encode())
        os.close(fd)

    def hold(name):
        # Until the test creates <gate>/<name> or <gate>/all (or removes the gate).
        while os.path.isdir(gate) and not any(os.path.exists(os.path.join(gate, n)) for n in (name, "all")):
            time.sleep(0.02)

    def unread():
        return struct.unpack("i", fcntl.ioctl(1, termios.FIONREAD, b"\\0" * 4))[0]

    run_dir = os.path.join(v["OUT_DIR"], v["TEST"] + ".seed." + v["SEED"])
    os.makedirs(run_dir)
    print("Run directory: " + run_dir, flush=True)
    print("Job <%d> is submitted to queue <%s>." % (os.getpid(), v.get("JOB_QUEUE") or "normal"), flush=True)
    if gate:
        # "submit" once run_list has read the job ID line, so a test can act on it.
        while unread() and os.path.isdir(gate):
            time.sleep(0.01)
        event("submit")
    if gate and os.environ.get("FAKE_PEND_GATE"):
        hold("dispatch")
    else:
        time.sleep(float(os.environ.get("FAKE_PEND", "0")))
    print("<<Starting on fakehost>>", flush=True)
    event("start")
    if gate:
        hold(v["TEST"] + "." + v["SEED"])
    else:
        time.sleep(float(os.environ.get("FAKE_SLEEP", "1.5")))
    event("end")
    if os.environ.get("FAKE_XPASS"):
        print("XPASS: expected failure did not occur (BUGS/000: X); review the entry", flush=True)
    print(("FAIL" if "fail" in v["TEST"] else "PASS") + " " + v["TEST"], flush=True)
""")

FAKE_BMOD = textwrap.dedent("""\
    #!/usr/bin/env python3
    import os, sys
    with open(os.environ["FAKE_BMOD_LOG"], "a") as fh:
        fh.write(" ".join(sys.argv[1:]) + "\\n")
    print("Parameters of job <%s> are being changed" % sys.argv[-1])
""")


class RunListControl(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.bin = os.path.join(self.dir, "bin")
        os.makedirs(self.bin)
        for name, text in (("make", FAKE_MAKE), ("bmod", FAKE_BMOD)):
            path = os.path.join(self.bin, name)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            os.chmod(path, 0o755)
        self.n = 0
        self.events = self.bmod_log = self.ctl = self.gate = self.log = ""
        self.gates, self.procs = [], []

    def tearDown(self):
        # A failed test may leave fake runs held or run_list alive: let them go first.
        for gate in self.gates:
            self.release(gate=gate)
        for proc in self.procs:
            if proc.poll() is None:
                proc.kill()
            proc.communicate()
        shutil.rmtree(self.dir, ignore_errors=True)

    def runlist(self, name, entries):
        path = os.path.join(self.dir, name + ".toml")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("schema_version = 1\n")
            for test, seeds in entries:
                fh.write(f'[[tests]]\nname = "{test}"\nseed = 1\nreseed = {seeds}\n\n')
        return path

    def start(self, lists, *opts, sleep=1.5, pend=0.0, gated=False, pend_gate=False, hooks=False,
              xpass=False, env_extra=None):
        """Start run_list.py. gated: each fake run holds after it starts until release();
        pend_gate: it also holds before it starts (submitted, not dispatched)."""
        self.n += 1
        out = os.path.join(self.dir, f"out{self.n}")
        self.events = os.path.join(self.dir, f"events{self.n}")
        self.bmod_log = os.path.join(self.dir, f"bmod{self.n}")
        self.args_log = os.path.join(self.dir, f"args{self.n}")
        self.gate = os.path.join(self.dir, f"gate{self.n}") if gated else ""
        if gated:
            os.makedirs(self.gate)
            self.gates.append(self.gate)
        # run_list starts $MAKE before gmake or make; point it at the fake.
        env = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"], FAKE_BIN=self.bin,
                   MAKE=os.path.join(self.bin, "make"),
                   FAKE_EVENTS=self.events, FAKE_SLEEP=str(sleep), FAKE_PEND=str(pend),
                   FAKE_BMOD_LOG=self.bmod_log, FAKE_HOOKS="1" if hooks else "",
                   FAKE_XPASS="1" if xpass else "", FAKE_ARGS=self.args_log, FAKE_GATE=self.gate,
                   FAKE_PEND_GATE="1" if pend_gate else "")
        env.pop("LSF_EXTRA_OPTS", None)
        env.update(env_extra or {})
        cmd = [sys.executable, os.path.join(SCRIPTS, "run_list.py"), "--rid", "t", "--out-dir", out,
               *opts, *lists]
        proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.procs.append(proc)
        self.ctl = os.path.join(out, "t.ctl")
        self.log = os.path.join(out, "t.log")
        return proc, out

    def release(self, name="all", gate=None):
        """Let held fake runs go: 'all', 'dispatch' (pend_gate) or '<test>.<seed>'."""
        with open(os.path.join(gate or self.gate, name), "w", encoding="utf-8"):
            pass

    def finish(self, proc, timeout=120):
        text, _ = proc.communicate(timeout=timeout)
        return proc.returncode, text

    def wait_until(self, cond, what, timeout=60):
        """Poll for cond(); the timeout only bounds a failing test, it never decides a pass."""
        end = time.time() + timeout
        while time.time() < end:
            if cond():
                return
            time.sleep(0.05)
        self.fail(f"timed out waiting for {what}")

    def read_events(self, kind=None):
        if not os.path.exists(self.events):
            return []
        with open(self.events, encoding="utf-8") as fh:
            return [e for e in (line.split() for line in fh) if kind is None or e[0] == kind]

    def wait_events(self, kind, n):
        self.wait_until(lambda: len(self.read_events(kind)) >= n, f"{n} {kind} event(s)")

    def wait_starts(self, n):
        self.wait_events("start", n)

    def log_text(self):
        try:
            with open(self.log, encoding="utf-8") as fh:
                return fh.read()
        except FileNotFoundError:
            return ""

    def wait_log(self, text):
        """Wait for run_list to log text, i.e. to have applied a change."""
        self.wait_until(lambda: text in self.log_text(), f"{text!r} in the run log")

    def wait_ctl(self):
        self.wait_until(lambda: os.path.exists(self.ctl), "the control file")

    def concurrency(self, t0=0.0, t1=float("inf")):
        """Most runs in flight at any instant in [t0, t1]."""
        steps = sorted((float(e[1]), 1 if e[0] == "start" else -1) for e in self.read_events()
                       if e[0] in ("start", "end"))
        live = best = 0
        for t, d in steps:
            live += d
            if t0 <= t <= t1:
                best = max(best, live)
        return best

    @staticmethod
    def rows(path, out):
        with open(path, newline="", encoding="utf-8") as fh:
            return [[c.replace(out, "<out>") for c in row] for row in csv.reader(fh)]

    def test_jobs_change_mid_run(self):
        lst = self.runlist("a", [("t_a", 6), ("t_b", 2)])
        proc, base = self.start([lst], "-j", "3", sleep=0.1)
        rc, _ = self.finish(proc)
        self.assertEqual(rc, 0)
        baseline = self.rows(os.path.join(base, "results.csv"), base)

        proc, out = self.start([lst], "-j", "1", gated=True)
        self.wait_starts(1)
        t_set = time.time()
        run_ctl.write(self.ctl, {"jobs": 4})
        # The first run is still held, so the three new ones run beside it.
        self.wait_starts(4)
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertEqual(self.concurrency(0, t_set), 1)
        self.assertEqual(self.concurrency(), 4)
        self.assertRegex(text, r"\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] ctl: jobs 1 -> 4 \(control file\)")
        self.assertIn("ctl: jobs 1 -> 4", self.log_text())
        self.assertEqual(self.rows(os.path.join(out, "results.csv"), out), baseline)
        self.assertEqual(len(baseline), 9)

    def test_pause_and_resume(self):
        lst = self.runlist("a", [("t_a", 6)])
        proc, out = self.start([lst], "-j", "2", gated=True)
        self.wait_starts(2)
        run_ctl.write(self.ctl, {"pause": 1})
        self.wait_log("ctl: pause 0 -> 1")
        self.release()
        self.wait_log("t_a seed=1 ")
        self.wait_log("t_a seed=2 ")
        # Both slots are free and run_list has seen them free; a launch now would be a bug.
        time.sleep(2 * run_list.POLL_S)
        self.assertEqual(len(self.read_events("start")), 2)
        self.assertEqual(self.concurrency(), 2)
        run_ctl.write(self.ctl, {"pause": 0})
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertIn("ctl: pause 0 -> 1", text)
        self.assertIn("ctl: pause 1 -> 0", text)
        self.assertEqual(len(self.rows(os.path.join(out, "results.csv"), out)), 7)

    def test_drain(self):
        lst = self.runlist("a", [("t_a", 6)])
        proc, out = self.start([lst], "-j", "2", gated=True)
        self.wait_starts(2)
        run_ctl.write(self.ctl, {"drain": 1})
        self.wait_log("ctl: drain 0 -> 1")
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 1, text)
        self.assertEqual(len(self.read_events("start")), 2)
        self.assertEqual(len(self.read_events("end")), 2)
        self.assertIn("drained; 4 run(s) not launched", text)
        self.assertEqual(text.count("\nnotrun "), 4)
        self.assertEqual([r[:2] for r in self.rows(os.path.join(out, "results.csv"), out)[1:]],
                         [["t_a", "1"], ["t_a", "2"]])

    def test_ctl_removed_at_exit(self):
        lst = self.runlist("a", [("t_a", 2)])
        proc, _ = self.start([lst], "-j", "2", gated=True)
        self.wait_ctl()
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertFalse(os.path.exists(self.ctl))

    def test_ctl_removed_on_sigterm(self):
        lst = self.runlist("a", [("t_a", 4)])
        proc, _ = self.start([lst], "-j", "1", gated=True)
        self.wait_starts(1)
        proc.terminate()
        self.finish(proc)
        self.assertFalse(os.path.exists(self.ctl))
        # The orphaned fake run finishes before tearDown removes its directory.
        self.release()
        self.wait_events("end", 1)

    def test_ctl_of_another_run_kept(self):
        path = os.path.join(self.dir, "other.ctl")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"# run_list pid {os.getpid() + 1}: x\njobs=1\n")
        run_list.remove_ctl(path)
        self.assertTrue(os.path.exists(path))

    def test_signals(self):
        lst = self.runlist("a", [("t_a", 6)])
        proc, _ = self.start([lst], "-j", "1", gated=True)
        self.wait_starts(1)
        proc.send_signal(signal.SIGUSR1)
        self.wait_log("ctl: jobs 1 -> 2 (SIGUSR1)")
        proc.send_signal(signal.SIGUSR1)
        self.wait_log("ctl: jobs 2 -> 3 (SIGUSR1)")
        self.wait_starts(3)
        self.assertEqual(run_ctl.read(self.ctl)["jobs"], "3")
        proc.send_signal(signal.SIGUSR2)
        self.wait_log("ctl: jobs 3 -> 2 (SIGUSR2)")
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertIn("ctl: jobs 1 -> 2 (SIGUSR1)", text)
        self.assertIn("ctl: jobs 2 -> 3 (SIGUSR1)", text)
        self.assertIn("ctl: jobs 3 -> 2 (SIGUSR2)", text)
        self.assertEqual(self.concurrency(), 3)

    def test_lists_share_one_pool(self):
        la = self.runlist("la", [("t_a", 3)])
        lb = self.runlist("lb", [("t_b", 2), ("t_fail", 1)])
        proc, out = self.start([la, lb], "-j", "2", "--per-list", gated=True)
        self.wait_starts(2)
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 1, text)
        self.assertEqual(self.concurrency(), 2)
        self.assertEqual(len(self.rows(os.path.join(out, "results_la.csv"), out)), 4)
        self.assertEqual(len(self.rows(os.path.join(out, "results_lb.csv"), out)), 4)
        self.assertIn("3/3 PASS/XFAIL; results in", text)
        self.assertIn("2/3 PASS/XFAIL; results in", text)
        self.assertFalse(os.path.exists(os.path.join(out, "results.csv")))

    def test_priority_and_queue(self):
        lst = self.runlist("a", [("t_a", 4)])
        proc, _ = self.start([lst], "-j", "2", gated=True, pend_gate=True, hooks=True)
        # Both runs submitted, job IDs read by run_list, neither dispatched.
        self.wait_events("submit", 2)
        run_ctl.write(self.ctl, {"priority": 7, "queue": "q2"})

        def bmod_calls():
            try:
                with open(self.bmod_log, encoding="utf-8") as fh:
                    return sorted(line.split()[0:2] for line in fh)
            except FileNotFoundError:
                return []
        self.wait_until(lambda: len(bmod_calls()) >= 4, "4 bmod calls")
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertEqual(bmod_calls(), [["-q", "q2"], ["-q", "q2"], ["-sp", "7"], ["-sp", "7"]])
        starts = self.read_events("start")
        self.assertEqual(sorted(e[5:] for e in starts if e[3] in ("3", "4")),
                         [["prio=7", "queue=q2"]] * 2)
        self.assertIn("ctl: priority '' -> 7 (control file)", text)

    def test_failed_first(self):
        lst = self.runlist("a", [("t_a", 2), ("t_b", 2)])
        out = os.path.join(self.dir, "out1")
        os.makedirs(out)
        with open(os.path.join(out, "results.csv"), "w", encoding="utf-8") as fh:
            fh.write("test,seed,plusargs,status,plan_ids,run_dir\nt_b,1,,FAIL,1.1,x\n")
        proc, _ = self.start([lst], "-j", "1", "--order", "failed-first", sleep=0.2)
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertEqual([e[2] for e in self.read_events("start")], ["t_b", "t_b", "t_a", "t_a"])

    def test_pass_with_xpass_notes(self):
        lst = self.runlist("a", [("t_a", 2)])
        proc, out = self.start([lst], "-j", "2", sleep=0.2, xpass=True)
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertNotIn("XPASS+XPASS", text)
        self.assertEqual([r[3] for r in self.rows(os.path.join(out, "results.csv"), out)[1:]],
                         ["PASS+XPASS", "PASS+XPASS"])

    def make_args(self):
        with open(self.args_log, encoding="utf-8") as fh:
            return [ast.literal_eval(line) for line in fh]

    def test_make_vars_forwarded(self):
        lst = self.runlist("a", [("t_a", 2)])
        excl = '-R "select[hname!=hostA]"'
        proc, _ = self.start([lst], "--fdi-enc", "SPEC", "--lsf-extra-opts", excl, sleep=0.1)
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        for argv in self.make_args():
            self.assertIn("FDI_ENC=SPEC", argv)
            self.assertIn("LSF_EXTRA_OPTS=" + excl, argv)
        proc, _ = self.start([lst], sleep=0.1, env_extra={"LSF_EXTRA_OPTS": excl})
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        for argv in self.make_args():
            self.assertFalse(any(a.startswith("FDI_ENC=") for a in argv))
            self.assertIn("LSF_EXTRA_OPTS=" + excl, argv)

    def test_stale_build_warned_once(self):
        lst = self.runlist("a", [("t_a", 3)])
        warning = "WARNING: STALE BUILD /x/build/vcs-t1-1x512-sp64"
        proc, _ = self.start([lst], "--escape", "pr28", sleep=0.1, env_extra={"FAKE_STALE": warning})
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertEqual(text.count("STALE BUILD"), 1)
        self.assertIn(warning, self.log_text())
        for argv in self.make_args():
            self.assertIn("STALE_CHECK=0", argv)
            self.assertIn("ESCAPE=pr28", argv)

    def test_bad_value_ignored(self):
        lst = self.runlist("a", [("t_a", 3)])
        proc, _ = self.start([lst], "-j", "1", gated=True)
        self.wait_starts(1)
        with open(self.ctl, "a", encoding="utf-8") as fh:
            fh.write("jobs=many\n")
        self.wait_log("ctl: ignored jobs=many")
        self.release()
        rc, text = self.finish(proc)
        self.assertEqual(rc, 0, text)
        self.assertIn("ctl: ignored jobs=many", text)
        self.assertEqual(self.concurrency(), 1)


class Verdict(unittest.TestCase):

    def test_pass_with_xpass_notes(self):
        text = ("XPASS: expected failure did not occur (BUGS/001: FDI-M01); review the entry\n"
                "XPASS: expected failure did not occur (BUGS/002: FDI-M07); review the entry\n"
                "PASS aou_fdi_t1_bringup_spec_test (2 entries not hit)\n")
        self.assertEqual(run_list.verdict(text), "PASS+XPASS")

    def test_verdicts(self):
        self.assertEqual(run_list.verdict("PASS t\n"), "PASS")
        self.assertEqual(run_list.verdict("XPASS: x\nXFAIL t\n"), "XFAIL+XPASS")
        self.assertEqual(run_list.verdict("XPASS: x\nFAIL t\n"), "FAIL")
        self.assertEqual(run_list.verdict("XPASS: x\n"), "FAIL")
        self.assertEqual(run_list.verdict(""), "FAIL")


class StaleBuild(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.src = os.path.join(self.dir, "src")
        self.build = os.path.join(self.dir, "build")
        os.makedirs(os.path.join(self.src, "out"))
        os.makedirs(self.build)
        self.files = {}
        for name, age in (("a.sv", 100), ("b.svh", 100), ("notes.md", 0), ("out/x.sv", 0)):
            self.touch(name, age)
        self.stamp = os.path.join(self.build, "build.stamp")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def touch(self, name, age, base=None):
        path = os.path.join(self.src, name) if base is None else os.path.join(base, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("x\n")
        t = time.time() - age
        os.utime(path, (t, t))
        return path

    def check(self, defines=("A=1", "B")):
        return stale_build.check(self.stamp, os.path.join(self.build, "simv"), list(defines), [self.src])

    def test_current(self):
        with open(self.stamp, "w", encoding="utf-8") as fh:
            fh.write("A=1\nB\n")
        t = time.time() - 50
        os.utime(self.stamp, (t, t))
        # notes.md and out/ are newer but are not sources.
        self.assertEqual(self.check(), [])

    def test_newer_source_and_defines(self):
        with open(self.stamp, "w", encoding="utf-8") as fh:
            fh.write("A=1\nB\n")
        t = time.time() - 50
        os.utime(self.stamp, (t, t))
        self.touch("b.svh", 10)
        reasons = self.check(defines=("A=2", "B"))
        self.assertIn("1 source file(s) changed", reasons[0])
        self.assertTrue(reasons[1].endswith("b.svh"))
        self.assertEqual(reasons[-1], "compile defines changed: -A=1, +A=2")

    def test_no_stamp_falls_back_to_binary(self):
        self.assertEqual(self.check(), [])
        self.touch("simv", 50, self.build)
        self.assertEqual(self.check(defines=("other",)), [])
        self.touch("a.sv", 10)
        self.assertEqual(len(self.check()), 2)


class RunCtl(unittest.TestCase):

    def test_edit_keeps_comments(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "x.ctl")
            run_ctl.write(path, {"jobs": 2, "pause": False}, header=["# head"])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_ctl.main([path, "jobs=20", "order=shortest"]), 0)
            with open(path, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), "# head\njobs=20\npause=0\norder=shortest\n")
            with self.assertRaises(SystemExit):
                run_ctl.main([path, "jobs=0"])
            with self.assertRaises(SystemExit):
                run_ctl.main([path, "colour=red"])
            self.assertEqual(os.listdir(d), ["x.ctl"])


if __name__ == "__main__":
    unittest.main()
