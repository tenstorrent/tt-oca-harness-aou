#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Validate the TOML testlists against the harness schema and this bench (make lint).

Checks, for each bench's aggregate (the [testlist] of its sim config):
  - every list loads: known keys only, includes resolve, scenario and group names
    unique, each group's expected_count equals its member count, members defined;
  - every scenario's `module.uvm` names a test class defined under uvm/tests (the
    scenario-to-class binding), its `target` is a target of the sim config and
    its `run_modes` are run modes of the sim config;
  - `expect_fail_match` compiles and comes with `expect_fail`;
  - a scenario tagged `blocked` is in no group and has its reason in plan_ids.yaml;
  - the `all` group holds every scenario that is not blocked;
  - plan_ids.yaml names only scenarios, and every T1-area and register scenario
    has plan IDs (the sanity scenario of all.toml is the gate, not plan coverage);
  - escape.toml loads and each [[escapes]] entry names a test class (or "none"),
    an escape/<escape>.patch, a signature that compiles and a known target.
Exit 1 with one line per problem.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_cfg  # noqa: E402
import testlist  # noqa: E402

UVM_ROOT = testlist.UVM_ROOT
# Where each bench's test classes live (uvm/tests/aou_tests.sv includes the T1 ones; the
# other benches' packages are their own directories).
NOT_T1 = {"reg", "l3_unit", "axi_selftest"}
TEST_DIRS = {
    "t1": None,  # every uvm/tests subdirectory but NOT_T1
    "reg": ["uvm/tests/reg"],
    "l3_unit": ["uvm/tests/l3_unit"],
    "axi_selftest": ["uvm/tests/axi_selftest"],
}
CLASS_RE = re.compile(r"^\s*class\s+(\w+)\s+extends", re.M)
ESCAPE_KEYS = {"test", "escape", "tb", "target", "args", "seed", "reseed", "build", "signature", "note"}


def test_dirs(tb):
    if TEST_DIRS[tb] is not None:
        return TEST_DIRS[tb]
    root = os.path.join(UVM_ROOT, "uvm", "tests")
    return ["uvm/tests"] + sorted(os.path.join("uvm", "tests", d) for d in os.listdir(root)
                                  if os.path.isdir(os.path.join(root, d)) and d not in NOT_T1)


def test_classes(tb):
    out = set()
    for d in test_dirs(tb):
        for path in glob.glob(os.path.join(UVM_ROOT, d, "*.svh")):
            with open(path, encoding="utf-8", errors="replace") as fh:
                out |= set(CLASS_RE.findall(fh.read()))
    return out


def check_bench(tb, side, problems):
    cfg = sim_cfg.load(tb)
    path = os.path.join(UVM_ROOT, cfg.get("testlist", {}).get("path", ""))
    tag = os.path.relpath(path, UVM_ROOT)
    try:
        tests, groups = testlist.load(path)
    except testlist.TestlistError as e:
        problems.append(str(e))
        return
    targets = set(sim_cfg.targets(cfg))
    modes = set(cfg.get("run_modes", {}))
    classes = test_classes(tb)
    members = {n for g in groups.values() for n in g}
    for name, t in tests.items():
        src = os.path.relpath(t["_source"], UVM_ROOT)
        cls = testlist.uvm_class(t)
        if cls is None:
            problems.append(f"{src}: {name}: no UVM class binding (module.uvm)")
        elif cls not in classes:
            problems.append(f"{src}: {name}: module.uvm {cls} is not a test class under "
                            f"{', '.join(test_dirs(tb))}")
        if t.get("target") and t["target"] not in targets:
            problems.append(f"{src}: {name}: target {t['target']} is not a target of {testlist.BENCH_OF.get(tb, tb)}'s sim config")
        for m in t.get("run_modes", []):
            if m not in modes:
                problems.append(f"{src}: {name}: run mode {m} is not in the sim config's [run_modes]")
        if t.get("expect_fail_match"):
            if not t.get("expect_fail"):
                problems.append(f"{src}: {name}: expect_fail_match without expect_fail")
            try:
                re.compile(t["expect_fail_match"])
            except re.error as e:
                problems.append(f"{src}: {name}: expect_fail_match does not compile: {e}")
        if "expect_fail" in t and not (isinstance(t["expect_fail"], str) and t["expect_fail"].strip()):
            problems.append(f"{src}: {name}: expect_fail must be a non-empty string (the defect)")
        for key in ("seed", "reseed", "timeout_sec"):
            if key in t and (not isinstance(t[key], int) or t[key] < 1):
                problems.append(f"{src}: {name}: {key} must be a positive integer")
        blocked = "blocked" in t.get("tags", [])
        if blocked and name in members:
            problems.append(f"{src}: {name}: blocked but listed in a group")
        if blocked and not side["blocked"].get(name):
            problems.append(f"{src}: {name}: blocked without a reason in plan_ids.yaml")
        if not blocked and "all" in groups and name not in groups["all"]:
            problems.append(f"{src}: {name}: not in the `all` group")
        is_gate = t["_source"] == path and tb == "t1"
        if tb in ("t1", "reg") and not is_gate and name not in side["plan_ids"]:
            problems.append(f"{src}: {name}: not in plan_ids.yaml (give it plan IDs, or '' for none)")
    for g, names in groups.items():
        for n in names:
            if n not in tests:
                problems.append(f"{tag}: group {g}: member {n} is not a scenario")
    for name in list(side["plan_ids"]) + list(side["blocked"]):
        if tb == "t1" and name not in tests and not any(name in testlist.load(os.path.join(
                UVM_ROOT, sim_cfg.load(b).get("testlist", {}).get("path", "")))[0] for b in ("reg", "l3_unit", "axi_selftest")):
            problems.append(f"plan_ids.yaml: {name} is not a scenario of any aggregate")
    print(f"check_testlists: {tag}: {len(tests)} scenarios, {len(groups)} groups, "
          f"{sum(1 for t in tests.values() if 'blocked' in t.get('tags', []))} blocked")


def check_escape(problems):
    path = os.path.join(UVM_ROOT, "testlists", "escape.toml")
    try:
        data = sim_cfg.load_toml(path)
    except (OSError, ValueError) as e:
        problems.append(f"testlists/escape.toml: {e}")
        return
    classes = {tb: test_classes(tb) for tb in ("t1", "reg")}
    targets = set(sim_cfg.targets(sim_cfg.load("t1")))
    for e in data.get("escapes", []):
        for k in e:
            if k not in ESCAPE_KEYS:
                problems.append(f"testlists/escape.toml: {e.get('test')}: unknown key {k}")
        tb = e.get("tb", "t1")
        if e.get("test") != "none" and e.get("test") not in classes.get(tb, set()):
            problems.append(f"testlists/escape.toml: {e.get('test')} is not a test class of TB={tb}")
        if not os.path.isfile(os.path.join(UVM_ROOT, "escape", f"{e.get('escape')}.patch")):
            problems.append(f"testlists/escape.toml: {e.get('test')}: no escape/{e.get('escape')}.patch")
        if e.get("target") and e["target"] not in targets:
            problems.append(f"testlists/escape.toml: {e.get('test')}: unknown target {e['target']}")
        try:
            re.compile(e.get("signature", ""))
        except re.error as ex:
            problems.append(f"testlists/escape.toml: {e.get('test')}: signature does not compile: {ex}")
    print(f"check_testlists: testlists/escape.toml: {len(data.get('escapes', []))} escapes")


def main():
    problems = []
    try:
        side = testlist.load_plan_ids()
    except testlist.TestlistError as e:
        print(f"check_testlists: {e}", file=sys.stderr)
        return 1
    for tb in ("t1", "reg", "l3_unit", "axi_selftest"):
        check_bench(tb, side, problems)
    check_escape(problems)
    for p in problems:
        print(f"check_testlists: {p}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
