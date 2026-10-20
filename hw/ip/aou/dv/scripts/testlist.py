#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Reader for the TOML testlists (testlists/*.toml) and their plan_ids.yaml sidecar.

The testlists follow the tt-oca-harness runner's schema: `[[tests]]` entries
with name, module = { uvm = "<class>" }, optional target, seed, reseed, args,
tags, run_modes, expect_fail, expect_fail_match; `includes` of other lists;
`[[groups]]` with name, tests and expected_count. Scenario names are unique
across a list and everything it includes. What the harness schema has no key
for lives next to the lists in testlists/plan_ids.yaml: the test-plan items a
scenario covers and, for a scenario that must not run yet, why it is blocked
(blocked scenarios also carry the `blocked` tag and belong to no group).

    tests, groups = load(path)        # name -> entry dict, name -> [names]
    for e in entries(path):           # flat view run_list.py / plan_status.py use
        e["name"], e["test"], e["seeds"], e["plusargs"], e["target"], e["plan_ids"], ...

The bench each list belongs to (TB=t1|reg|l3_unit|axi_selftest) is the one
whose sim config names it (BENCH_OF below); the register, L3 unit and AXI
self-test lists are aggregates of their own.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_cfg  # noqa: E402

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTLIST_DIR = os.path.join(UVM_ROOT, "testlists")
PLAN_IDS = os.path.join(TESTLIST_DIR, "plan_ids.yaml")
# Which bench a list runs on: the T1 aggregate and its areas, then the others.
BENCH_OF = {"registers": "reg", "l3_unit": "l3_unit", "axi_selftest": "axi_selftest"}
TEST_KEYS = {"name", "module", "target", "seed", "reseed", "timeout_sec", "tags", "run_modes", "tools",
             "firmware", "expect_fail", "expect_fail_match", "args", "overrides"}
GROUP_KEYS = {"name", "tests", "expected_count"}
LIST_KEYS = {"schema_version", "includes", "tests", "groups", "escapes"}


class TestlistError(Exception):
    pass


def bench_of(path, default="t1"):
    """The bench a list runs on: by name, T1 for the other lists shipped in testlists/,
    and default for a list from elsewhere, which has no bench of its own."""
    name = os.path.splitext(os.path.basename(path))[0]
    if name in BENCH_OF:
        return BENCH_OF[name]
    return "t1" if os.path.dirname(os.path.abspath(path)) == TESTLIST_DIR else default


def load(path, _stack=None):
    """(tests, groups) of a list with its includes expanded; raises TestlistError."""
    path = os.path.abspath(path)
    stack = _stack or []
    if path in stack:
        raise TestlistError(f"{path}: include cycle through {' -> '.join(stack)}")
    try:
        data = sim_cfg.load_toml(path)
    except (OSError, ValueError) as e:
        raise TestlistError(f"{path}: {e}") from e
    for k in data:
        if k not in LIST_KEYS:
            raise TestlistError(f"{path}: unknown top-level key {k}")
    tests, groups = {}, {}
    base = os.path.dirname(path)
    for inc in data.get("includes", []):
        inc_tests, inc_groups = load(os.path.join(base, inc), stack + [path])
        for n, t in inc_tests.items():
            if n in tests:
                raise TestlistError(f"{path}: duplicate test {n} after including {inc}")
            tests[n] = t
        for n, g in inc_groups.items():
            if n in groups:
                raise TestlistError(f"{path}: duplicate group {n} after including {inc}")
            groups[n] = g
    for t in data.get("tests", []):
        if not isinstance(t, dict) or not isinstance(t.get("name"), str) or not t["name"]:
            raise TestlistError(f"{path}: a [[tests]] entry has no name")
        for k in t:
            if k not in TEST_KEYS:
                raise TestlistError(f"{path}: {t['name']}: unknown key {k}")
        if t["name"] in tests:
            raise TestlistError(f"{path}: duplicate test {t['name']}")
        t = dict(t)
        t["_source"] = path
        tests[t["name"]] = t
    for g in data.get("groups", []):
        if not isinstance(g, dict) or not isinstance(g.get("name"), str):
            raise TestlistError(f"{path}: a [[groups]] entry has no name")
        for k in g:
            if k not in GROUP_KEYS:
                raise TestlistError(f"{path}: group {g['name']}: unknown key {k}")
        if g["name"] in groups:
            raise TestlistError(f"{path}: duplicate group {g['name']}")
        members = list(g.get("tests", []))
        if "expected_count" in g and g["expected_count"] != len(members):
            raise TestlistError(f"{path}: group {g['name']} lists {len(members)} tests but "
                                f"expected_count is {g['expected_count']}")
        groups[g["name"]] = members
    return tests, groups


def uvm_class(entry):
    """The UVM test class a scenario binds to, or None when UVM is out of scope."""
    mod = entry.get("module", entry["name"])
    if isinstance(mod, dict):
        v = mod.get("uvm")
        return v if isinstance(v, str) else None
    return mod


def seeds_of(entry):
    """seed..seed+reseed-1 (seed 1, reseed 1 by default)."""
    seed = int(entry.get("seed", 1))
    return list(range(seed, seed + int(entry.get("reseed", 1))))


def load_plan_ids(path=PLAN_IDS):
    """{'plan_ids': {name: 'a,b'}, 'blocked': {name: 'reason'}} from the sidecar."""
    out = {"plan_ids": {}, "blocked": {}}
    section = None
    try:
        fh = open(path, encoding="utf-8")
    except FileNotFoundError:
        return out
    with fh:
        for raw in fh:
            line = raw.rstrip()
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = re.match(r"^(plan_ids|blocked):\s*$", line)
            if m:
                section = m.group(1)
                continue
            m = re.match(r"^\s+([A-Za-z0-9_.+-]+):\s*(.*)$", line)
            if not m or section is None:
                raise TestlistError(f"{path}: cannot parse line {line!r}")
            val = m.group(2).strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
                val = val[1:-1]
            out[section][m.group(1)] = val
    return out


def entries(path, plan_ids=None):
    """Flat entries of one list (includes expanded), in file order:
    name, test (UVM class), seeds, plusargs, target, tags, run_modes, expect_fail,
    expect_fail_match, plan_ids, blocked, tb, tb_fixed (False for a custom list, which runs
    on whichever bench is selected), list (the file that defines it)."""
    tests, _ = load(path)
    side = plan_ids if plan_ids is not None else load_plan_ids()
    out = []
    for name, t in tests.items():
        out.append({
            "name": name,
            "test": uvm_class(t),
            "seeds": seeds_of(t),
            "plusargs": " ".join(t.get("args", [])),
            "target": t.get("target", ""),
            "tags": list(t.get("tags", [])),
            "run_modes": list(t.get("run_modes", [])),
            "expect_fail": t.get("expect_fail", ""),
            "expect_fail_match": t.get("expect_fail_match", ""),
            "plan_ids": side["plan_ids"].get(name, ""),
            "blocked": side["blocked"].get(name, "") or ("blocked" in t.get("tags", []) and "blocked") or "",
            "tb": bench_of(t["_source"]),
            "tb_fixed": bench_of(t["_source"], None) is not None,
            "list": os.path.splitext(os.path.basename(t["_source"]))[0],
        })
    return out


def select(path, items=None, plan_ids=None):
    """The entries named by items (group names or scenario names; all when None)."""
    tests, groups = load(path)
    ents = {e["name"]: e for e in entries(path, plan_ids)}
    if not items:
        return list(ents.values())
    names = []
    for it in items:
        if it in groups:
            names += [n for n in groups[it] if n not in names]
        elif it in tests:
            if it not in names:
                names.append(it)
        else:
            raise TestlistError(f"{path}: no group or test named {it}; groups: {', '.join(groups)}")
    missing = [n for n in names if n not in ents]
    if missing:
        raise TestlistError(f"{path}: group members not defined: {', '.join(missing)}")
    return [ents[n] for n in names]


def ids(text):
    """'1.1,1.2' or ['1.1', '1.2'] -> ['1.1', '1.2']."""
    if isinstance(text, list):
        return [str(x).strip() for x in text if str(x).strip()]
    return [x.strip() for x in str(text or "").split(",") if x.strip()]
