#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for check_run's handling of the RTL's own assertions.

Feeds VCS and Verilator assertion reports to check_run.judge() and reads the
verdict back the way run_list.py, regress.py, plan_status.py and passing_runs.py
do. Nothing is simulated. Run: python3 scripts/test_check_run.py
"""

import argparse
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_run  # noqa: E402
import passing_runs  # noqa: E402
import plan_status  # noqa: E402
import regress  # noqa: E402
import run_list  # noqa: E402

SUMMARY = "--- UVM Report Summary ---\n"
WLAST = "/w/aou/RTL/AOU_AXI_WLAST_GEN.v"
REMAP = "/w/aou/RTL/AOU_ID_REMAPPER.sv"
SCOPE = "tb_top.u_dut.u_aou_core_top.u_aou_core.gen_aou_core_rp[3].u_aou_core_rp.u_wlast_gen"


def vcs_fail(path, line, label, severity, start=395500, end=895500):
    """One VCS concurrent-assertion failure: header, offending term, severity line, message."""
    out = f'"{path}", {line}: {SCOPE}.{label}: started at {start}ps failed at {end}ps\n'
    out += "\tOffending 'O_S_AWREADY'\n"
    if severity:
        out += f'{severity}: "{path}", {line}: {SCOPE}.{label}: at time {end} ps\n'
        out += f"[{end}] {SCOPE}.{label}: AWREADY not seen within 500 cycles of AWVALID\n"
    return out


class CheckRunRtlAsserts(unittest.TestCase):
    EXPECTED = ("- test: t\n  bug: tenstorrent/tt-oca-harness-aou#999\n"
                "  check_re: 'RTL assertion error: AOU_ID_REMAPPER\\.sv:\\d+: .*hit_onehot'\n"
                "  seed_dependent: true\n")

    def judge(self, body):
        with tempfile.TemporaryDirectory() as t:
            path = os.path.join(t, "ef.yaml")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(self.EXPECTED)
            return check_run.judge("UVM_INFO start\n" + body + SUMMARY, "sim.log", path, "t")

    def verdict(self, body):
        return next(x for x in self.judge(body) if x.startswith(("PASS", "XFAIL", "FAIL")))

    def test_ordinary_log_unchanged(self):
        body = ('Warning-[TFIPC] Too few instance port connections\n'
                'Warning: "/w/aou/hw/ip/aou/dv/tb/aou_axi4pc_gate.sv", 40: tb_top.g.a: at time 5 ps\n'
                '%Warning: tb_top.sv:12: $value$plusargs ignored\n')
        self.assertEqual(self.judge(body), ["PASS: sim.log"])

    def test_vcs_error_fails(self):
        lines = self.judge(vcs_fail(REMAP, 239, "aou_id_remapper_entry_mo_assertion", "Error"))
        self.assertEqual(lines[0], "FAIL: 1 unexpected error(s) in sim.log")
        self.assertEqual(lines[1], f"  RTL assertion error: AOU_ID_REMAPPER.sv:239: "
                                   f"{SCOPE}.aou_id_remapper_entry_mo_assertion")

    def test_vcs_fatal_and_default_action_fail(self):
        body = vcs_fail(REMAP, 1, "a_fatal", "Fatal") + vcs_fail(REMAP, 2, "a_default", None)
        lines = self.judge(body)
        self.assertEqual(lines[0], "FAIL: 2 unexpected error(s) in sim.log")
        self.assertTrue(lines[1].startswith("  RTL assertion fatal: AOU_ID_REMAPPER.sv:1: "))
        self.assertTrue(lines[2].startswith("  RTL assertion error: AOU_ID_REMAPPER.sv:2: "))

    def test_expected_entry_explains_error(self):
        body = vcs_fail(REMAP, 239, "aou_id_remapper_hit_onehot_assertion", "Error")
        self.assertEqual(self.verdict(body),
                         "XFAIL: 1 error(s), all known (tenstorrent/tt-oca-harness-aou#999): sim.log")

    def test_vcs_warnings_counted_once_each(self):
        body = (vcs_fail(WLAST, 247, "ready_valid_assertion", "Warning")
                + vcs_fail(WLAST, 256, "s_awvalid_s_wvalid_assertion", "Warning")
                + vcs_fail(WLAST, 247, "ready_valid_assertion", "Warning", 900000, 1400000))
        self.assertEqual(self.judge(body), ["PASS: sim.log (3 RTL assertion warnings)"])

    def test_warning_kept_with_failure(self):
        body = (vcs_fail(WLAST, 247, "ready_valid_assertion", "Warning")
                + vcs_fail(REMAP, 239, "aou_id_remapper_entry_mo_assertion", "Error"))
        self.assertEqual(self.verdict(body),
                         "FAIL: 1 unexpected error(s) in sim.log (1 RTL assertion warning)")

    def test_rtl_patch_copy_counts(self):
        path = "/w/aou/hw/ip/aou/dv/build/vcs-t1-x-assert-fix-p/rtl/AOU_AXI_WLAST_GEN.v"
        body = vcs_fail(path, 247, "ready_valid_assertion", "Warning")
        self.assertEqual(self.verdict(body), "PASS: sim.log (1 RTL assertion warning)")

    def test_verilator(self):
        warn = (f"[896000] %Warning: AOU_AXI_WLAST_GEN.v:252: TOP.{SCOPE}: "
                f"[896000] TOP.{SCOPE}: AWREADY not seen within 500 cycles of AWVALID\n")
        self.assertEqual(self.verdict(warn * 2), "PASS: sim.log (2 RTL assertion warnings)")
        err = (f"[5000] %Error: AOU_ID_REMAPPER.sv:232: Assertion failed in TOP.{SCOPE}: "
               "[5000] x: Multiple entries match the same WID.\n"
               "%Error: AOU_ID_REMAPPER.sv:232: Verilog $stop\n")
        lines = self.judge(err)
        self.assertEqual(lines[0], "FAIL: 1 unexpected error(s) in sim.log")
        self.assertTrue(lines[1].startswith("  RTL assertion error: AOU_ID_REMAPPER.sv:232: "
                                            "Assertion failed in TOP."))
        bench = "[5000] %Error: aou_t1_tb_chk.sv:10: Assertion failed in TOP.tb_top: x\n"
        self.assertEqual(self.verdict(bench), "PASS: sim.log")

    def test_verdict_readers(self):
        line = "PASS: out/b/t.rid.r.seed.1.time.0.uid.0/sim.log (3 RTL assertion warnings)"
        self.assertEqual(run_list.verdict(line + "\n"), "PASS")
        self.assertEqual(regress.verdict(run_list.verdict(line + "\n")), ("PASS", False))
        xfail = "XFAIL: 1 error(s), all known (B1): sim.log (1 RTL assertion warning)"
        with tempfile.TemporaryDirectory() as t:
            run = os.path.join(t, "t.rid.r.seed.1.time.0.uid.0")
            os.mkdir(run)
            with open(os.path.join(run, "verdict.txt"), "w", encoding="utf-8") as fh:
                fh.write(line + "\n")
            self.assertEqual(passing_runs.scan(t)[0], [run])
            args = argparse.Namespace(judge=False)
            self.assertEqual(plan_status.read_verdict(run, args), ("PASS", set()))
            with open(os.path.join(run, "verdict.txt"), "w", encoding="utf-8") as fh:
                fh.write(xfail + "\n")
            self.assertEqual(plan_status.read_verdict(run, args), ("XFAIL", {"B1"}))
            self.assertEqual(passing_runs.scan(t)[0], [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
