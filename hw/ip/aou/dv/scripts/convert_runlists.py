#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""One-time conversion of the YAML run lists into the TOML testlists.

Run once when the bench moved to the tt-oca-dv layout; kept for the record of
how each file was derived. The TOML is hand-maintained from then on.

  convert_runlists.py --yaml-dir <old testlists/> --out testlists/ \
      [--expected-fail expected_fail.yaml] [--baseline-results <dir of results*.csv>]

For every <area>.yaml (one entry per test, seeds, plusargs, config, plan_ids,
blocked): a <area>.toml with one [[tests]] entry per YAML entry, named after
the test and, when the same test appears more than once in the T1 lists, its
plusargs (and target, and area) until the name is unique; `module = { uvm =
<class> }`, `target` from `config:`, `seed`/`reseed` from `seeds:` (every YAML
list names seeds 1..N), `args` from the plusargs, `tags`/`run_modes` the area,
and a [[groups]] entry per area with its expected_count. `blocked:` entries get
the `blocked` tag, their reason in a comment and in plan_ids.yaml, and belong to
no group (the harness schema has no key for a scenario that must not run).
all.toml includes the T1 areas and defines the aou_sanity_test scenario and
the smoke, functional and all groups; registers.yaml becomes registers.toml
(the register bench's aggregate); assertions.yaml entries go on the
<CONFIG>-assert targets; escape.yaml becomes escape.toml ([[escapes]], read by
escape.py only). The plan IDs go to plan_ids.yaml, keyed by scenario name.

With --expected-fail and --baseline-results, an entry whose every baseline
run was XFAIL and whose test has bug-specific expected_fail entries (no
`requires:`, `seed_dependent:` or `when_re:`) gets `expect_fail` (the bugs) and
`expect_fail_match` (their checks), so the harness grader judges it XFAIL too;
check_run.py stays the standalone grader for everything else.
"""

import argparse
import csv
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import listyaml  # noqa: E402

HEADER = "# SPDX-License-Identifier: Apache-2.0\n# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc\n"
T1_AREAS = ["g1a", "g1b", "t1_api", "fdi", "datapath", "features", "stress", "link", "errors",
            "err_int", "lifecycle", "matrix", "perf", "assertions"]
FUNCTIONAL = ["g1a", "g1b", "t1_api", "fdi", "datapath", "features", "link", "errors", "err_int",
              "lifecycle"]
SMOKE_T1 = ["aou_sanity_test", "aou_t1_slice_test", "aou_t1_deact_test", "aou_fdi_t1_bringup_test"]
AREA_DESC = {
    "g1a": "Gate G1a: the thin end-to-end slice on T1",
    "g1b": "Gate G1b: remote activation, link events, low-power",
    "t1_api": "The T1 test-layer API: injection, SW and hard reset, slices",
    "fdi": "FDI L1/L2 against the DUT: bring-up, link error, link down, link stress",
    "datapath": "Data path (stream F)",
    "features": "Features (stream F)",
    "stress": "Stress (stream F)",
    "link": "Credits and link (stream G)",
    "errors": "Error injection (stream G)",
    "err_int": "Error and interrupt registers (stream G)",
    "lifecycle": "Reset, low-power and link events (stream G)",
    "matrix": "Configuration matrix (stream J)",
    "perf": "Performance data (stream J)",
    "assertions": "The RTL's ASSERTION_ON checks (plan 11.18) on the <CONFIG>-assert targets",
    "registers": "Register tests on the APB-only register bench (TB=reg)",
}
NO_DUT = {
    "l3_unit": ("The L3 protocol model and AOU_FDI_CHECKER unit bench (TB=l3_unit, no DUT)",
                ["aou_l3_codec_test", "aou_l3_credit_test", "aou_l3_crossflit_test", "aou_l3_dest_rp_test",
                 "aou_l3_inject_test", "aou_l3_link_test", "aou_l3_loopback_test", "aou_l3_unit_env_test"],
                "aou_l3_codec_test"),
    "axi_selftest": ("The AXI L4 agent and scoreboard self-test bench (TB=axi_selftest, no DUT)",
                     ["aou_axi_selftest_test", "aou_axi_selftest_neg_test", "aou_axi_sb_reset_test"],
                     "aou_axi_selftest_test"),
}


def entry_comments(path):
    """Per entry (file order), the comment lines written above or inside it in the YAML,
    the file's header block excluded; carried into the TOML so no note is lost."""
    out, pending, cur, seen_entry = [], [], None, False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip()
            if re.match(r"^-\s+\w+:", line):
                cur = list(pending) if seen_entry else []
                out.append(cur)
                pending, seen_entry = [], True
            elif line.lstrip().startswith("#"):
                text = line.lstrip()[1:].strip()
                if cur is not None and line.startswith(" "):
                    cur.append(text)
                elif seen_entry:
                    pending.append(text)
            elif not line.strip():
                if cur is not None and pending:
                    pass
                cur = None
    return out


def header_comments(path):
    """The YAML file's own header notes (its comment block before the first entry),
    without the SPDX lines and the `Run with:` usage line."""
    out = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip()
            if re.match(r"^-\s+\w+:", line):
                break
            if line.startswith("#"):
                text = line[1:].strip()
                if text.startswith("SPDX-") or text.startswith("Run with:") or "run_list.py" in text:
                    continue
                out.append(text)
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return out


def q(s):
    """A TOML basic string."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def arr(items):
    return "[" + ", ".join(q(x) for x in items) + "]"


def seeds_of(text):
    """The YAML seeds field -> (seed, reseed); every list uses 1..N."""
    text = (text or "1").strip()
    if re.fullmatch(r"\d+", text):
        return 1, int(text)
    vals = []
    for part in text.split(","):
        m = re.fullmatch(r"(\d+)-(\d+)", part.strip())
        vals += list(range(int(m.group(1)), int(m.group(2)) + 1)) if m else [int(part)]
    if vals != list(range(vals[0], vals[0] + len(vals))):
        sys.exit(f"seeds {text!r} are not contiguous; add one entry per seed by hand")
    return vals[0], len(vals)


def slug(plusargs):
    out = []
    for tok in plusargs.split():
        tok = tok.lstrip("+").replace("=", "-").replace(",", "_").replace("/", "_").replace(":", "_")
        out.append(re.sub(r"[^A-Za-z0-9_.-]", "", tok))
    return ".".join(out)


def unique_names(rows):
    """Assign rows (dicts with test, plusargs, target, area) unique names, adding
    the plusargs, then the target, then the area only where needed."""
    def key(r, level):
        parts = [r["test"]]
        if level >= 1 and r["plusargs"]:
            parts.append(slug(r["plusargs"]))
        if level >= 2 and r["target"]:
            parts.append(r["target"])
        if level >= 3:
            parts.append(r["area"])
        return ".".join(parts)

    names = {}
    for level in range(4):
        counts = {}
        for r in rows:
            if "name" in r:
                continue
            counts[key(r, level)] = counts.get(key(r, level), 0) + 1
        for r in rows:
            if "name" in r:
                continue
            k = key(r, level)
            if counts[k] == 1 and k not in names:
                r["name"] = k
                names[k] = r
    for i, r in enumerate(rows):
        if "name" not in r:
            r["name"] = f"{key(r, 3)}.{i}"
    return rows


def load_baseline(results_dir):
    """{(test, plusargs, build-config or ''): set(status)} from results*.csv under out/<build>/."""
    out = {}
    if not results_dir:
        return out
    for path in glob.glob(os.path.join(results_dir, "**", "results*.csv"), recursive=True):
        build = os.path.basename(os.path.dirname(path))
        m = re.match(r"^[a-z]+-(t1|reg)(?:-(.+?))?(-assert)?$", build)
        if not m:
            continue
        config = (m.group(2) or "") + (m.group(3) or "")
        with open(path, newline="", encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                k = (row["test"], " ".join(row.get("plusargs", "").split()), config)
                out.setdefault(k, set()).add(row["status"].split("+")[0])
    return out


def rx_escape(text):
    """Escape only the regex metacharacters, so the match stays readable."""
    return re.sub(r"([.^$*+?{}\[\]\\|()])", r"\\\1", text)


def deterministic_fails(expected_path):
    """{test: [(bug, regex)]} for bug-specific entries without seed or run conditions."""
    out = {}
    if not expected_path:
        return out
    for e in listyaml.load(expected_path):
        if e.get("requires") or e.get("seed_dependent") or e.get("when_re"):
            continue
        rx = e.get("check_re") or rx_escape(e.get("check", ""))
        if rx:
            out.setdefault(e["test"], []).append((e.get("bug", "bug not named"), rx))
    return out


def expect_fail_for(row, baseline, det):
    """(reason, regex) when every baseline run of this entry was XFAIL and the test
    has bug-specific entries; otherwise None."""
    if row["test"] not in det or not baseline:
        return None
    cfg = row["target"]
    statuses = set()
    for (t, p, c), s in baseline.items():
        if t == row["test"] and p == " ".join(row["plusargs"].split()) and (not cfg or c == cfg):
            statuses |= s
    if not statuses or statuses != {"XFAIL"}:
        return None
    bugs = sorted({b for b, _ in det[row["test"]]})
    rx = "|".join(dict.fromkeys(r for _, r in det[row["test"]]))
    return ", ".join(bugs) + " (expected_fail.yaml)", rx


def write_area(path, area, rows, desc, bench_note="", notes=()):
    lines = [HEADER.rstrip(), "", "schema_version = 1", "", f"# {desc}."]
    if bench_note:
        lines.append(f"# {bench_note}")
    if notes:
        lines.append("#")
        lines += [f"# {n}" if n else "#" for n in notes]
        lines.append("#")
    lines.append("# Scenario -> test-plan items: plan_ids.yaml. Scenario names are unique across")
    lines.append("# every list all.toml includes; a name carries the plusargs, target or area only")
    lines.append("# where the test alone would repeat.")
    for r in rows:
        lines.append("")
        for c in r.get("comments", []):
            lines.append(f"# {c}" if c else "#")
        if r.get("blocked"):
            lines.append(f"# blocked: {r['blocked']}")
        lines.append("[[tests]]")
        lines.append(f"name = {q(r['name'])}")
        lines.append(f"module = {{ uvm = {q(r['test'])} }}")
        if r["target"]:
            lines.append(f"target = {q(r['target'])}")
        lines.append(f"seed = {r['seed']}")
        if r["reseed"] != 1:
            lines.append(f"reseed = {r['reseed']}")
        tags = [area] + (["blocked"] if r.get("blocked") else [])
        lines.append(f"tags = {arr(tags)}")
        lines.append(f"run_modes = {arr([area])}")
        if r["plusargs"]:
            lines.append(f"args = {arr(r['plusargs'].split())}")
        if r.get("expect_fail"):
            lines.append(f"expect_fail = {q(r['expect_fail'][0])}")
            lines.append(f"expect_fail_match = {q(r['expect_fail'][1])}")
    members = [r["name"] for r in rows if not r.get("blocked")]
    lines += ["", "[[groups]]", f"name = {q(area)}", f"expected_count = {len(members)}", "tests = ["]
    lines += [f"  {q(n)}," for n in members]
    lines.append("]")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def write_group(name, members, comment=None):
    lines = ["", "[[groups]]"]
    if comment:
        lines.insert(1, f"# {comment}")
    lines += [f"name = {q(name)}", f"expected_count = {len(members)}", "tests = ["]
    lines += [f"  {q(n)}," for n in members]
    lines.append("]")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--yaml-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--expected-fail", default="")
    ap.add_argument("--baseline-results", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    baseline = load_baseline(a.baseline_results)
    det = deterministic_fails(a.expected_fail)

    plan_ids, blocked = {}, {}
    # T1 areas: names unique across all of them.
    rows = []
    for area in T1_AREAS:
        ypath = os.path.join(a.yaml_dir, f"{area}.yaml")
        comments = entry_comments(ypath)
        for i, e in enumerate(listyaml.load(ypath)):
            if not e.get("test"):
                continue
            seed, reseed = seeds_of(e.get("seeds"))
            target = e.get("config", "")
            if area == "assertions":
                target = (target or "1x512-sp64") + "-assert"
            rows.append({"area": area, "test": e["test"], "plusargs": " ".join((e.get("plusargs") or "").split()),
                         "target": target, "seed": seed, "reseed": reseed, "comments": comments[i],
                         "plan_ids": ",".join(listyaml.ids(e.get("plan_ids"))), "blocked": e.get("blocked", "")})
    unique_names(rows)
    for r in rows:
        r["expect_fail"] = expect_fail_for(r, baseline, det)
        plan_ids[r["name"]] = r["plan_ids"]
        if r["blocked"]:
            blocked[r["name"]] = r["blocked"]
    for area in T1_AREAS:
        write_area(os.path.join(a.out, f"{area}.toml"), area, [r for r in rows if r["area"] == area],
                   AREA_DESC[area], notes=header_comments(os.path.join(a.yaml_dir, f"{area}.yaml")))

    # all.toml: the T1 aggregate.
    by_area = {area: [r["name"] for r in rows if r["area"] == area and not r["blocked"]] for area in T1_AREAS}
    functional = []
    for area in FUNCTIONAL:
        functional += [n for n in by_area[area] if n not in functional]
    everything = ["aou_sanity_test"] + [r["name"] for r in rows if not r["blocked"]]
    lines = [HEADER.rstrip(), "", "schema_version = 1", "",
             "# The T1 bench's aggregate (aou_sim_cfg.toml [testlist]): the per-area lists, the",
             "# sanity scenario and the groups that span areas. Every group name below and in the",
             "# included lists is an --items target of run_list.py and of the harness runner.",
             f"includes = {arr([f'{area}.toml' for area in T1_AREAS])}",
             "",
             "# The bring-up gate's pair: aou_sanity_test runs aou_sanity_test_seq through",
             "# ocah_test's run_single_scenario (link up, activate, traffic both ways, drain).",
             "[[tests]]", 'name = "aou_sanity_test"', 'module = { uvm = "aou_sanity_test" }', "seed = 1",
             'tags = ["smoke"]', 'run_modes = ["smoke"]']
    lines += write_group("smoke", SMOKE_T1, "Bring-up gate: the sanity scenario and the G1a slice (make/CI smoke)")
    lines += write_group("functional", functional,
                         "Functional areas (no stress, matrix, perf or assertion builds)")
    lines += write_group("all", everything, "Every runnable T1 scenario; run_list.py skips entries whose target differs")
    with open(os.path.join(a.out, "all.toml"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    # registers.toml: the register bench's aggregate.
    reg_rows = []
    ypath = os.path.join(a.yaml_dir, "registers.yaml")
    comments = entry_comments(ypath)
    for i, e in enumerate(listyaml.load(ypath)):
        if not e.get("test"):
            continue
        seed, reseed = seeds_of(e.get("seeds"))
        reg_rows.append({"area": "registers", "test": e["test"], "plusargs": " ".join((e.get("plusargs") or "").split()),
                         "target": e.get("config", ""), "seed": seed, "reseed": reseed, "comments": comments[i],
                         "plan_ids": ",".join(listyaml.ids(e.get("plan_ids"))), "blocked": e.get("blocked", "")})
    unique_names(reg_rows)
    for r in reg_rows:
        r["expect_fail"] = expect_fail_for(r, baseline, det)
        plan_ids[r["name"]] = r["plan_ids"]
        if r["blocked"]:
            blocked[r["name"]] = r["blocked"]
    write_area(os.path.join(a.out, "registers.toml"), "registers", reg_rows, AREA_DESC["registers"],
               "The register bench's aggregate (aou_reg_sim_cfg.toml [testlist]).", notes=header_comments(ypath))
    with open(os.path.join(a.out, "registers.toml"), "a", encoding="utf-8") as fh:
        fh.write("\n".join(write_group("smoke", ["aou_reg_hw_reset_test"], "Bring-up gate of the register bench")) + "\n")
        fh.write("\n".join(write_group("all", [r["name"] for r in reg_rows if not r["blocked"]])) + "\n")

    # The no-DUT benches: one scenario per test class, seed 1.
    for area, (desc, tests, smoke) in NO_DUT.items():
        nrows = [{"area": area, "test": t, "plusargs": "", "target": "", "seed": 1, "reseed": 1, "name": t,
                  "plan_ids": "", "blocked": ""} for t in tests]
        write_area(os.path.join(a.out, f"{area}.toml"), area, nrows, desc,
                   f"The bench's aggregate (aou_{area}_sim_cfg.toml [testlist]).")
        with open(os.path.join(a.out, f"{area}.toml"), "a", encoding="utf-8") as fh:
            fh.write("\n".join(write_group("smoke", [smoke])) + "\n")
            fh.write("\n".join(write_group("all", tests)) + "\n")

    # escape.toml: standalone-only.
    lines = [HEADER.rstrip(), "", "schema_version = 1", "",
             "# Bug-escape suite (acceptance A3), read by scripts/escape.py (make escape) only: every",
             "# real bug fixed on main, re-introduced by escape/<escape>.patch on a build-time copy",
             "# of RTL/, must make the test fail with `signature` (a regex matched against the",
             "# UVM_ERROR/UVM_FATAL lines) while the same run passes on the clean build. Keys: test",
             "# (UVM class, or \"none\" for a compile-time catch), escape, signature, tb (t1 or reg;",
             "# default t1), target, args, seed, reseed, build (the simulator whose compile catches",
             "# it), note. [[escapes]] is this bench's own schema, not the harness's [[tests]]."]
    lines += ["#"] + [f"# {n}" if n else "#" for n in header_comments(os.path.join(a.yaml_dir, "escape.yaml"))]
    ypath = os.path.join(a.yaml_dir, "escape.yaml")
    comments = entry_comments(ypath)
    for i, e in enumerate(listyaml.load(ypath)):
        if not e.get("test"):
            continue
        lines.append("")
        lines += [f"# {c}" if c else "#" for c in comments[i]]
        lines += ["[[escapes]]", f"test = {q(e['test'])}", f"escape = {q(e['escape'])}"]
        if e.get("tb"):
            lines.append(f"tb = {q(e['tb'])}")
        if e.get("config"):
            lines.append(f"target = {q(e['config'])}")
        if e.get("plusargs"):
            lines.append(f"args = {arr(e['plusargs'].split())}")
        if e.get("seeds"):
            seed, reseed = seeds_of(e.get("seeds"))
            lines.append(f"seed = {seed}")
            if reseed != 1:
                lines.append(f"reseed = {reseed}")
        if e.get("build"):
            lines.append(f"build = {q(e['build'])}")
        lines.append(f"signature = {q(e['signature'])}")
        if e.get("note"):
            lines.append(f"note = {q(e['note'])}")
    with open(os.path.join(a.out, "escape.toml"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    # plan_ids.yaml
    lines = [HEADER.rstrip(), "#",
             "# Sidecar of the TOML testlists: what the harness schema has no key for.",
             "# plan_ids: the test-plan items (docs/test_plan_items.yaml IDs) a scenario covers,",
             "# by scenario name; plan_status.py joins it with the lists. blocked: why a scenario",
             "# must not run yet (it also carries the `blocked` tag and belongs to no group).",
             "# scripts/check_testlists.py checks every name here is a scenario and every",
             "# T1/register scenario has plan IDs ('' states that it covers none).", "", "plan_ids:"]
    lines += [f"  {n}: '{v}'" for n, v in plan_ids.items()]
    lines += ["", "blocked:"]
    lines += [f"  {n}: '{v}'" for n, v in blocked.items()]
    with open(os.path.join(a.out, "plan_ids.yaml"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    n_xf = sum(1 for r in rows + reg_rows if r.get("expect_fail"))
    print(f"convert_runlists: {len(rows)} T1 scenarios, {len(reg_rows)} register scenarios, "
          f"{len(blocked)} blocked, {n_xf} with expect_fail, {len(plan_ids)} with plan IDs -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
