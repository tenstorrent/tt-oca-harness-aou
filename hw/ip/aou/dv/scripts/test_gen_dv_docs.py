#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for gen_dv_docs.py's covergroup inventory: comments are not read as code,
every covergroup sits in its class or module, and every covergroup has a coverage-service
group of the same name.
Run: python3 scripts/test_gen_dv_docs.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_dv_docs  # noqa: E402

SRC = """// The sample_*() functions sample the covergroup that reads them.
/* covergroup boxed; cp: coverpoint x; endgroup */
class my_cov extends uvm_object;
  covergroup cg_a;
    cp_x: coverpoint x {
      bins a = {0};   // 4KB page boundary: crossing is illegal
    }
    x_ab: cross cp_x, cp_y;
  endgroup
  function new();
    fc = db.group("env.cg_a", fresh);   // "not // a comment" stays a string
  endfunction
endclass
"""


class GenDvDocsTest(unittest.TestCase):
    def test_comments_are_not_code(self):
        stripped = gen_dv_docs.strip_comments(SRC)
        self.assertNotIn("reads them", stripped)
        self.assertNotIn("boxed", stripped)
        self.assertNotIn("boundary", stripped)
        self.assertIn('"env.cg_a"', stripped)
        self.assertEqual(stripped.count("\n"), SRC.count("\n"))

    def test_parse(self):
        got = gen_dv_docs.parse_covergroups(SRC, "x.svh")
        self.assertEqual(got, [("cg_a", "my_cov", "x.svh", ["cp_x"], ["x_ab"])])
        self.assertEqual(gen_dv_docs.service_groups({"x.svh": SRC}), {"cg_a": "env.cg_a"})

    def test_sources(self):
        groups = gen_dv_docs.covergroups()   # exits when a group has no report name
        names = [g[0] for g in groups]
        self.assertEqual(len(names), len(set(names)))
        self.assertIn("cg_act_fsm", names)
        self.assertNotIn("that", names)
        for g, rep, comp, path, cps, xs in groups:
            self.assertTrue(comp, f"{g} has no component")
            self.assertEqual(rep.rsplit(".", 1)[-1], g)
            self.assertNotIn("boundary", xs)


if __name__ == "__main__":
    unittest.main()
