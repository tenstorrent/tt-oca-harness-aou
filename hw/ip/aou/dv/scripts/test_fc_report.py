#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for fc_report.py: union over passing runs only, AXI4 text
reports read as groups, zero-hit bins kept as holes, plan IDs carried and checked.
Run: python3 scripts/test_fc_report.py
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fc_report  # noqa: E402


def fc_json(hits):
    """One group g with coverpoint cp (bins a, b) and cross x over it."""
    return {"format": "aou-fc/1", "test": "t", "groups": [
        {"group": "g", "spec": "", "plan_ids": [], "samples": sum(hits),
         "points": [
             {"point": "cp", "kind": "coverpoint", "outside": 1,
              "bins": [{"bin": "a", "hits": hits[0], "spec": "", "plan_ids": []},
                       {"bin": "b", "hits": hits[1], "spec": "", "plan_ids": []}]},
             {"point": "x", "kind": "cross", "outside": 0,
              "bins": [{"bin": "a,a", "hits": 0, "spec": "", "plan_ids": []}]}]}]}


AXI4 = """Run        : r
#BINDATA v1
#IFACE axi_tx_rp0
BIN cg_b|cp_b_resp|okay 3
BIN cg_b|cp_b_resp|slverr 0
BIN cg_aw|cx_size_x_len|bytes_0_X_beat_1 1
PLAN cg_b cp_b_resp okay 4.22
PLAN cg_aw cx_size_x_len *,beat_1 4.1 4.10
#ENDIFACE
#ENDBINDATA
"""


class FcReportTest(unittest.TestCase):
    def run_dir(self, root, name, verdict, hits, rid="00"):
        d = os.path.join(root, f"{name}.rid.{rid}.seed.1.time.0.uid.0")
        os.makedirs(d)
        with open(os.path.join(d, "verdict.txt"), "w", encoding="utf-8") as fh:
            fh.write(f"{verdict}: sim.log\n")
        with open(os.path.join(d, "fc.json"), "w", encoding="utf-8") as fh:
            json.dump(fc_json(hits), fh)
        with open(os.path.join(d, f"aou_axi4_fc.{name}.txt"), "w", encoding="utf-8") as fh:
            fh.write(AXI4)

    def test_merge(self):
        with tempfile.TemporaryDirectory() as root:
            self.run_dir(root, "t1", "PASS", [2, 0])
            self.run_dir(root, "t2", "PASS", [1, 0])
            self.run_dir(root, "t3", "FAIL", [0, 5])
            db, counts = fc_report.merge(root)
            self.assertEqual(counts["PASS"], 2)
            self.assertEqual(counts["FAIL"], 1)
            cp = db["groups"]["g"]["points"]["cp"]
            self.assertEqual(cp["bins"]["a"], {"hits": 3, "runs": 2, "spec": "", "plan_ids": []})
            self.assertEqual(cp["bins"]["b"]["hits"], 0)   # only the FAIL run hit it
            self.assertEqual(cp["outside"], 2)
            self.assertEqual(fc_report.tally(db["groups"]["g"]["points"]), (1, 3))
            b = db["groups"]["axi4.axi_tx_rp0.cg_b"]["points"]["cp_b_resp"]["bins"]
            self.assertEqual((b["okay"]["hits"], b["slverr"]["hits"]), (6, 0))
            x = db["groups"]["axi4.axi_tx_rp0.cg_aw"]["points"]["cx_size_x_len"]
            self.assertEqual((x["kind"], list(x["bins"])), ("cross", ["bytes_0,beat_1"]))
            holes = io.StringIO()
            fc_report.write_holes(holes, db)
            self.assertIn("    cp: b\n", holes.getvalue())
            self.assertIn("    cp_b_resp: slverr\n", holes.getvalue())

    def test_plan_ids(self):
        with tempfile.TemporaryDirectory() as root:
            self.run_dir(root, "t1", "PASS", [1, 0])
            self.run_dir(root, "t2", "PASS", [1, 0])
            path = os.path.join(root, sorted(os.listdir(root))[0], "fc.json")
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            data["groups"][0]["plan_ids"] = ["8.1"]
            data["groups"][0]["points"][0]["bins"][0]["plan_ids"] = ["8.1", "4.10"]
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh)
            db, _ = fc_report.merge(root)
            self.assertEqual(db["groups"]["g"]["plan_ids"], ["8.1"])
            self.assertEqual(db["groups"]["g"]["points"]["cp"]["bins"]["a"]["plan_ids"], ["8.1", "4.10"])
            grp = db["groups"]["axi4.axi_tx_rp0.cg_b"]["points"]["cp_b_resp"]["bins"]
            self.assertEqual((grp["okay"]["plan_ids"], grp["slverr"]["plan_ids"]), (["4.22"], []))
            x = db["groups"]["axi4.axi_tx_rp0.cg_aw"]["points"]["cx_size_x_len"]["bins"]
            self.assertEqual(x["bytes_0,beat_1"]["plan_ids"], ["4.1", "4.10"])   # text, once

    def test_match_bin(self):
        m = fc_report.match_bin
        self.assertTrue(m("c[0]|c[2],*", "c[2],tx"))
        self.assertFalse(m("c[0]", "c0"))              # only '*' is special
        self.assertFalse(m("*", "a,b"))                # one glob per crossed point
        self.assertTrue(m("expiry_*", "expiry_rp[3]"))

    def test_check_plan_ids(self):
        with tempfile.TemporaryDirectory() as root:
            items = os.path.join(root, "items.yaml")
            with open(items, "w", encoding="utf-8") as fh:
                fh.write("- id: '4.1'\n  title: a\n- id: '4.10'\n  title: b\n  merged_into: '4.1'\n"
                         "- id: '4.2'\n  title: c\n  dropped: no\n")
            os.makedirs(os.path.join(root, "uvm"))
            os.makedirs(os.path.join(root, "cov"))
            with open(os.path.join(root, "uvm", "a.svh"), "w", encoding="utf-8") as fh:
                fh.write('g.plan("4.1 4.10"); g.plan("4.2", "cp"); $display("9.9");\n')
            with open(os.path.join(root, "uvm", "b.svh"), "w", encoding="utf-8") as fh:
                fh.write('$display("9.8");\n')            # no plan(): not a declaration
            with open(os.path.join(root, "cov", "c.svh"), "w", encoding="utf-8") as fh:
                fh.write('localparam string FC_PLAN[1] = \'{"cg_b cp_b_resp okay 4.1 7.7"};\n')
            problems = fc_report.check_plan_ids(items, root)
            self.assertEqual(len(problems), 4, problems)
            text = "\n".join(problems)
            for s in ("4.10 is merged into 4.1", "4.2 is dropped", "9.9 is not an item", "7.7 is not an item"):
                self.assertIn(s, text)

    def test_rid(self):
        # Runs of two regressions in one out/<build>: --rid merges only one of them.
        with tempfile.TemporaryDirectory() as root:
            self.run_dir(root, "t1", "PASS", [2, 0], rid="a")
            self.run_dir(root, "t1", "PASS", [0, 4], rid="a.b")
            self.run_dir(root, "t2", "FAIL", [0, 5], rid="a")
            db, counts = fc_report.merge(root, "a")
            self.assertEqual((counts["PASS"], counts["FAIL"]), (1, 1))
            self.assertEqual(db["groups"]["g"]["points"]["cp"]["bins"]["b"]["hits"], 0)
            _, counts = fc_report.merge(root)
            self.assertEqual((counts["PASS"], counts["FAIL"]), (2, 1))

    def test_illegal_and_spec(self):
        with tempfile.TemporaryDirectory() as root:
            self.run_dir(root, "t1", "PASS", [1, 0])
            path = os.path.join(root, os.listdir(root)[0], "fc.json")
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            bins = data["groups"][0]["points"][0]["bins"]
            bins[1]["spec"] = "v0.8"
            bins.append({"bin": "bad", "hits": 2, "spec": "", "illegal": True, "plan_ids": []})
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh)
            db, _ = fc_report.merge(root)
            pts = db["groups"]["g"]["points"]
            # The illegal bin is out, and so is the revision-tagged one.
            self.assertEqual(fc_report.tally(pts), (1, 2))
            self.assertEqual(fc_report.tally(pts, "v0.8"), (0, 1))
            # An rtl-limit tag stays apart the same way; a stimulus note doesn't.
            self.assertTrue(fc_report.is_apart("rtl-limit"))
            self.assertFalse(fc_report.is_apart("rare"))
            self.assertEqual(fc_report.illegal_hits(db), [("g", "cp", "bad", 2)])
            text = io.StringIO()
            fc_report.write_summary(text, db, {"PASS": 1}, "b")
            self.assertIn("v0.8-tagged bins: 0/1 hit; not in the total above", text.getvalue())
            self.assertIn("1/2   ", text.getvalue())
            self.assertIn("ILLEGAL BIN HIT: g.cp bad (2 hits)", text.getvalue())
            holes = io.StringIO()
            fc_report.write_holes(holes, db)
            self.assertIn("    cp: b [v0.8]\n", holes.getvalue())

    def test_stimulus_tag_stays_in_total(self):
        with tempfile.TemporaryDirectory() as root:
            self.run_dir(root, "t1", "PASS", [1, 0])
            path = os.path.join(root, os.listdir(root)[0], "fc.json")
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            data["groups"][0]["points"][0]["bins"][1]["spec"] = "rare"
            data["groups"][0]["points"][0]["bins"][0]["spec"] = "v0.9draft"
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh)
            db, _ = fc_report.merge(root)
            pts = db["groups"]["g"]["points"]
            self.assertEqual(fc_report.tally(pts), (0, 2))          # rare in, v0.9draft out
            text = io.StringIO()
            fc_report.write_summary(text, db, {"PASS": 1}, "b")
            self.assertIn("rare-tagged bins: 0/1 hit, counted in the total; without them 2/4",
                          text.getvalue())
            self.assertIn("v0.9draft-tagged bins: 1/1 hit; not in the total above", text.getvalue())

    def test_report_files(self):
        with tempfile.TemporaryDirectory() as root:
            self.run_dir(root, "t1", "PASS", [1, 1])
            rep = os.path.join(root, "merged", "fc")
            sys.argv = ["fc_report.py", root, "-o", rep]
            with contextlib.redirect_stdout(io.StringIO()) as out:
                fc_report.main()
            self.assertIn("1 passing run(s) merged; 0 excluded", out.getvalue())
            for f in ("summary.txt", "holes.txt", "index.html", "fc_merged.json"):
                self.assertTrue(os.path.exists(os.path.join(rep, f)), f)
            with open(os.path.join(rep, "index.html"), encoding="utf-8") as fh:
                page = fh.read()
            self.assertNotIn("http", page.replace("http-equiv", ""))


if __name__ == "__main__":
    unittest.main()
