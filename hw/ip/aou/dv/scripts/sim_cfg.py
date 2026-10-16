#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Read the bench's <dut>_sim_cfg.toml for the standalone Makefile and scripts.

The sim configs (aou_sim_cfg.toml, aou_reg_sim_cfg.toml, aou_l3_unit_sim_cfg.toml,
aou_axi_selftest_sim_cfg.toml) are written for the tt-oca-harness runner: paths
are repository-root relative, the bench at hw/ip/aou/dv (the harness's
hw/<group>/<dut>/dv convention, the same path in both repositories) and the
OCAH shared library at hw/common/dv/vip. Standalone, this module resolves the
bench paths against this repository and the library against the git-ignored
.deps/ocah_lib checkout, so the Makefile compiles the same ordered sources with
the same per-target defines and no second copy of either exists.

Command line (every command takes --tb t1|reg|l3_unit|axi_selftest, default t1):
  sim_cfg.py targets                 the target names, one per line
  sim_cfg.py default-target          the default target
  sim_cfg.py top                     the top module
  sim_cfg.py defines --target T      the target's defines, space separated (NAME or NAME=VALUE)
  sim_cfg.py filelist --target T     +incdir+ lines and the ordered sources, then the top
  sim_cfg.py configs                 the CONFIG table (make configs)
  sim_cfg.py check                   validate every sim config: files exist, targets agree
                                     across the T1 and register benches, keys are the
                                     harness's

TOML is read with tomllib (Python 3.11+); on older interpreters a small
parser covering what these files use (tables, arrays of tables, inline
tables, strings, integers, booleans, arrays) stands in.
"""

import argparse
import os
import re
import sys

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The bench's path in the repository: hw/ip/aou/dv, three levels below the root.
DV_PREFIX = "hw/ip/aou/dv/"
ROOT = os.path.abspath(os.path.join(UVM_ROOT, *([os.pardir] * (DV_PREFIX.count("/")))))
# Config paths -> standalone paths. The bench's paths resolve against this
# repository; the OCAH library the harness supplies from its own tree comes
# from .deps/ocah_lib.
OCAH_PREFIX = "hw/common/dv/vip/"
OCAH_LIB_ROOT = os.environ.get("OCAH_LIB_ROOT") or os.path.join(UVM_ROOT, ".deps", "ocah_lib")

TBS = {
    "t1": "aou_sim_cfg.toml",
    "reg": "aou_reg_sim_cfg.toml",
    "l3_unit": "aou_l3_unit_sim_cfg.toml",
    "axi_selftest": "aou_axi_selftest_sim_cfg.toml",
}

# The harness runner's key sets (tools/dv/runlib/config.py), so `check` catches a
# key --validate-configs would reject without needing the harness.
TOP_LEVEL_KEYS = {
    "schema_version", "name", "profile", "kind", "framework", "default_framework", "visibility",
    "runnability", "license", "default_tool", "tools", "description", "scheduler", "defaults",
    "target_defaults", "native", "testlist", "build", "cocotb", "c_build", "run_modes",
    "targets", "coverage", "pass_fail", "sim", "formal", "dut", "tb", "frameworks",
}
BUILD_KEYS = {
    "top_module", "top_file", "filelist", "bender_filelist", "work_dir", "common_bender_targets",
    "bender_targets", "incdirs", "stubs", "sources", "source_lists", "exclude_files", "options",
    "verilator", "xcelium", "vcs",
}
TARGET_KEYS = {
    "description", "build_dir", "work_dir", "filelist", "bender_filelist", "bender_targets",
    "defines", "flags", "sources", "stubs", "exclude_files", "tools",
}
RUN_MODE_KEYS = {"description", "timeout_sec", "args", "plusargs"}


# -----------------------------------------------------------------------------
# TOML
# -----------------------------------------------------------------------------
def load_toml(path):
    """Parse a TOML file into dicts/lists (tomllib, or the subset parser below)."""
    try:
        import tomllib  # Python 3.11+
    except ImportError:
        tomllib = None
    with open(path, "rb") as fh:
        data = fh.read()
    if tomllib is not None:
        return tomllib.loads(data.decode("utf-8"))
    return _SubsetToml(data.decode("utf-8"), path).parse()


class _SubsetToml:
    """Tables, arrays of tables, dotted keys, inline tables, arrays, strings,
    integers, floats, booleans and comments: the TOML these files use."""

    def __init__(self, text, path):
        self.text = text
        self.path = path
        self.pos = 0
        self.line = 1

    def error(self, msg):
        raise ValueError(f"{self.path}:{self.line}: {msg}")

    # -- lexing helpers --------------------------------------------------------
    def peek(self, n=1):
        return self.text[self.pos:self.pos + n]

    def advance(self, n=1):
        for ch in self.text[self.pos:self.pos + n]:
            if ch == "\n":
                self.line += 1
        self.pos += n

    def skip_ws(self, newlines):
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in " \t\r" or (newlines and ch == "\n"):
                self.advance()
            elif ch == "#":
                while self.pos < len(self.text) and self.text[self.pos] != "\n":
                    self.advance()
            else:
                break

    def expect(self, s):
        if not self.text.startswith(s, self.pos):
            self.error(f"expected {s!r}")
        self.advance(len(s))

    # -- grammar ---------------------------------------------------------------
    def parse(self):
        root = {}
        cur = root
        while True:
            self.skip_ws(True)
            if self.pos >= len(self.text):
                return root
            if self.peek(2) == "[[":
                self.advance(2)
                keys = self.parse_key_path()
                self.skip_ws(False)
                self.expect("]]")
                parent = root
                for k in keys[:-1]:
                    parent = parent.setdefault(k, {})
                    if isinstance(parent, list):
                        parent = parent[-1]
                arr = parent.setdefault(keys[-1], [])
                if not isinstance(arr, list):
                    self.error(f"{'.'.join(keys)} is not an array of tables")
                cur = {}
                arr.append(cur)
            elif self.peek() == "[":
                self.advance()
                keys = self.parse_key_path()
                self.skip_ws(False)
                self.expect("]")
                cur = root
                for k in keys:
                    cur = cur.setdefault(k, {})
                    if isinstance(cur, list):
                        cur = cur[-1]
            else:
                keys = self.parse_key_path()
                self.skip_ws(False)
                self.expect("=")
                self.skip_ws(False)
                value = self.parse_value()
                tgt = cur
                for k in keys[:-1]:
                    tgt = tgt.setdefault(k, {})
                if keys[-1] in tgt:
                    self.error(f"duplicate key {keys[-1]}")
                tgt[keys[-1]] = value
            self.skip_ws(False)
            if self.pos < len(self.text) and self.text[self.pos] != "\n":
                self.error("trailing characters")

    def parse_key_path(self):
        keys = []
        while True:
            self.skip_ws(False)
            if self.peek() == '"':
                keys.append(self.parse_string())
            else:
                m = re.compile(r"[A-Za-z0-9_-]+").match(self.text, self.pos)
                if not m:
                    self.error("expected a key")
                keys.append(m.group(0))
                self.advance(len(m.group(0)))
            self.skip_ws(False)
            if self.peek() == ".":
                self.advance()
                continue
            return keys

    def parse_string(self):
        quote = self.peek()
        if self.peek(3) in ('"""', "'''"):
            self.error("multi-line strings are not used in sim configs")
        self.advance()
        out = []
        while True:
            if self.pos >= len(self.text):
                self.error("unterminated string")
            ch = self.text[self.pos]
            if ch == quote:
                self.advance()
                return "".join(out)
            if ch == "\\" and quote == '"':
                esc = self.text[self.pos + 1]
                mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
                if esc not in mapping:
                    self.error(f"unsupported escape \\{esc}")
                out.append(mapping[esc])
                self.advance(2)
                continue
            if ch == "\n":
                self.error("newline in string")
            out.append(ch)
            self.advance()

    def parse_value(self):
        ch = self.peek()
        if ch in "\"'":
            return self.parse_string()
        if ch == "[":
            self.advance()
            items = []
            while True:
                self.skip_ws(True)
                if self.peek() == "]":
                    self.advance()
                    return items
                items.append(self.parse_value())
                self.skip_ws(True)
                if self.peek() == ",":
                    self.advance()
                elif self.peek() != "]":
                    self.error("expected ',' or ']'")
        if ch == "{":
            self.advance()
            table = {}
            self.skip_ws(False)
            if self.peek() == "}":
                self.advance()
                return table
            while True:
                keys = self.parse_key_path()
                self.skip_ws(False)
                self.expect("=")
                self.skip_ws(False)
                tgt = table
                for k in keys[:-1]:
                    tgt = tgt.setdefault(k, {})
                tgt[keys[-1]] = self.parse_value()
                self.skip_ws(False)
                if self.peek() == ",":
                    self.advance()
                    self.skip_ws(False)
                    continue
                self.expect("}")
                return table
        m = re.compile(r"true|false|[+-]?\d[\d_]*(\.\d+)?([eE][+-]?\d+)?").match(self.text, self.pos)
        if not m:
            self.error("unsupported value")
        tok = m.group(0)
        self.advance(len(tok))
        if tok == "true":
            return True
        if tok == "false":
            return False
        if m.group(1) or m.group(2):
            return float(tok.replace("_", ""))
        return int(tok.replace("_", ""))


# -----------------------------------------------------------------------------
# Sim config access
# -----------------------------------------------------------------------------
def cfg_path(tb):
    if tb not in TBS:
        sys.exit(f"sim_cfg: unknown TB {tb}; use one of {', '.join(sorted(TBS))}")
    return os.path.join(UVM_ROOT, TBS[tb])


def load(tb="t1"):
    return load_toml(cfg_path(tb))


def map_path(p):
    """A repository-root-relative path -> absolute standalone path."""
    if p.startswith(DV_PREFIX):
        return os.path.join(ROOT, p)
    if p.startswith(OCAH_PREFIX):
        return os.path.join(OCAH_LIB_ROOT, p)
    sys.exit(f"sim_cfg: {p}: neither under {DV_PREFIX} nor {OCAH_PREFIX}")


def targets(cfg):
    return [n for n, v in cfg.get("targets", {}).items() if isinstance(v, dict)]


def default_target(cfg):
    return cfg.get("defaults", {}).get("target", "default")


def target_defines(cfg, name):
    """Ordered defines of a target: [target_defaults.default] then [targets.<name>]."""
    if name not in cfg.get("targets", {}):
        sys.exit(f"sim_cfg: no target {name}; use one of {' '.join(targets(cfg))}")
    out = []
    for d in cfg.get("target_defaults", {}).get("default", {}).get("defines", []):
        if d not in out:
            out.append(d)
    for d in cfg["targets"][name].get("defines", []):
        if d not in out:
            out.append(d)
    return out


def define_value(defines, name, default=None):
    for d in defines:
        k, _, v = d.partition("=")
        if k == name:
            return v if _ else ""
    return default


def filelist(cfg):
    """(incdirs, sources, top_file) as absolute standalone paths, source_lists expanded first."""
    build = cfg.get("build", {})
    incdirs, sources = [], []
    for sl in build.get("source_lists", []):
        frag = load_toml(map_path(sl))
        for d in frag.get("incdirs", []):
            p = map_path(d)
            if p not in incdirs:
                incdirs.append(p)
        for s in frag.get("sources", []):
            p = map_path(s)
            if p not in sources:
                sources.append(p)
    for d in build.get("incdirs", []):
        p = map_path(d)
        if p not in incdirs:
            incdirs.append(p)
    for s in build.get("sources", []):
        p = map_path(s)
        if p not in sources:
            sources.append(p)
    top = map_path(build["top_file"]) if build.get("top_file") else None
    return incdirs, sources, top


# -----------------------------------------------------------------------------
# The CONFIG table (make configs)
# -----------------------------------------------------------------------------
FDI_NAMES = {0: "SP_32B", 1: "SP_64B", 2: "SP_128B", 3: "TP_32B_64B", 4: "TP_64B_128B"}
FDI_PHY_BYTES = {0: [32], 1: [64], 2: [128], 3: [32, 64], 4: [64, 128]}


def config_row(cfg, name):
    """RP count, RP widths, FDI_CONFIG, PHYs, peer width and purpose of a T1 target."""
    defs = target_defines(cfg, name)
    n = int(define_value(defs, "AOU_RP_COUNT", "1"))
    base = define_value(defs, "AOU_RP_DATA_W", "512")
    widths = [int(define_value(defs, f"AOU_RP{i}_DATA_W", base)) for i in range(n)]
    fdi = int(define_value(defs, "AOU_FDI_CONFIG", "1"))
    return {
        "config": name,
        "rp_count": n,
        "rp_widths": widths,
        "fdi": fdi,
        "fdi_name": FDI_NAMES.get(fdi, str(fdi)),
        "phys": 2 if fdi in (3, 4) else 1,
        "peer_w": int(define_value(defs, "AOU_PEER_MAX_W", "1024")),
        "assert": "ASSERTION_ON" in defs,
        "description": cfg["targets"][name].get("description", ""),
    }


def t1_configs(cfg=None):
    """{CONFIG: row} for the plain (non -assert) T1 targets, in file order."""
    cfg = cfg or load("t1")
    return {n: config_row(cfg, n) for n in targets(cfg) if not n.endswith("-assert")}


def print_configs(cfg):
    fmt = "%-17s %-3s %-20s %-12s %-4s %-5s %s"
    print(fmt % ("CONFIG", "RPs", "RP widths", "FDI_CONFIG", "PHYs", "Peer", "Purpose"))
    for n, r in t1_configs(cfg).items():
        print(fmt % (n, r["rp_count"], "/".join(map(str, r["rp_widths"])), r["fdi_name"],
                     r["phys"], r["peer_w"], r["description"]))
    print()
    print("NxW: N remote ports (RPs) x W-bit RP AXI data width; mix: mixed RP widths (listed);")
    print("mix<digits>: one digit per RP, RP0 first, its width in 256-bit units (1=256, 2=512, 4=1024);")
    print("sp<B>: single PHY, B-byte FDI (FDI_CFG_SP_<B>B); tp<B1>_<B2>: two PHYs, B1- and B2-byte FDI")
    print("(FDI_CFG_TP_<B1>B_<B2>B, built with TWO_PHY); -p<W>: AXI_PEER_DIE_MAX_DATA_WD W bits")
    print("(Peer column; 1024 without the suffix); -rxf: non-default RX FIFO depths, RS_EN=0.")
    print("<CONFIG>-assert: the same build with the RTL's ASSERTION_ON checks compiled in.")


# -----------------------------------------------------------------------------
# check
# -----------------------------------------------------------------------------
def check():
    errors = []

    def bad(msg):
        errors.append(msg)

    cfgs = {}
    for tb, fname in TBS.items():
        path = os.path.join(UVM_ROOT, fname)
        try:
            cfg = load_toml(path)
        except (OSError, ValueError) as e:
            bad(f"{fname}: {e}")
            continue
        cfgs[tb] = cfg
        for k in cfg:
            if k not in TOP_LEVEL_KEYS:
                bad(f"{fname}: unknown top-level key {k}")
        build = cfg.get("build", {})
        for k in build:
            if k not in BUILD_KEYS:
                bad(f"{fname}: unknown [build] key {k}")
        for name, t in cfg.get("targets", {}).items():
            for k in t:
                if k not in TARGET_KEYS:
                    bad(f"{fname}: unknown [targets.{name}] key {k}")
            # The runner needs a build directory per target, and targets that differ
            # only in defines must not share one.
            if not t.get("build_dir"):
                bad(f"{fname}: [targets.{name}] has no build_dir")
        for name, rm in cfg.get("run_modes", {}).items():
            for k in rm:
                if k not in RUN_MODE_KEYS:
                    bad(f"{fname}: unknown [run_modes.{name}] key {k}")
        if cfg.get("default_framework") != "uvm":
            bad(f"{fname}: default_framework must be uvm (this bench has no other framework)")
        if default_target(cfg) not in targets(cfg):
            bad(f"{fname}: [defaults].target {default_target(cfg)} is not a target")
        # The harness's native profile defaults [defaults].run_mode to "smoke"; a
        # bench without that run mode must name its own.
        run_mode = cfg.get("defaults", {}).get("run_mode", "smoke")
        if run_mode not in cfg.get("run_modes", {}):
            bad(f"{fname}: [defaults].run_mode {run_mode} is not a [run_modes.*] entry")
        if "frameworks" not in cfg or "uvm" not in cfg["frameworks"]:
            bad(f"{fname}: the runner needs a [frameworks.uvm] table to select the framework")
        if "timescale" in cfg.get("build", {}).get("vcs", {}):
            bad(f"{fname}: [build.vcs].timescale duplicates the harness simulator default; omit it")
        # One path space for both consumers: the bench is hw/ip/aou/dv in the
        # harness too, so no path may name a vendored root (filelist() only
        # walks the sources; this catches work_dir, filelist and stage paths).
        with open(os.path.join(UVM_ROOT, fname)) as fh:
            for ln, line in enumerate(fh, 1):
                if '"vendor/' in line.split("#", 1)[0]:
                    bad(f"{fname}:{ln}: path under vendor/; write it as {DV_PREFIX}...")
        try:
            incdirs, sources, top = filelist(cfg)
        except SystemExit as e:
            bad(str(e))
            continue
        for p in incdirs:
            if not os.path.isdir(p):
                bad(f"{fname}: incdir {p} does not exist")
        for p in sources + ([top] if top else []):
            if not os.path.isfile(p):
                bad(f"{fname}: source {p} does not exist")
        if not top:
            bad(f"{fname}: [build].top_file is required")
        if not build.get("top_module"):
            bad(f"{fname}: [build].top_module is required")
        tl = cfg.get("testlist", {}).get("path")
        if tl and not os.path.isfile(os.path.join(UVM_ROOT, tl)):
            bad(f"{fname}: testlist {tl} does not exist")
    # The register bench takes the T1 configurations so its coverage merges into T1's.
    if "t1" in cfgs and "reg" in cfgs:
        t1 = {n: target_defines(cfgs["t1"], n) for n in targets(cfgs["t1"])}
        reg = {n: target_defines(cfgs["reg"], n) for n in targets(cfgs["reg"])}
        if set(t1) != set(reg):
            bad(f"T1 and register bench targets differ: {sorted(set(t1) ^ set(reg))}")
        for n in set(t1) & set(reg):
            a = [d for d in t1[n] if d != "AOU_T1_AXI_AGENTS"]
            if a != reg[n]:
                bad(f"target {n}: T1 defines {a} != register bench defines {reg[n]}")
    for e in errors:
        print(f"sim_cfg: {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"sim_cfg: {len(cfgs)} sim configs, {len(targets(cfgs['t1']))} T1 targets, all files present")
    return 0


# -----------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["targets", "default-target", "top", "defines", "filelist",
                                        "configs", "check"])
    ap.add_argument("--tb", default="t1", choices=sorted(TBS))
    ap.add_argument("--target", default=None)
    a = ap.parse_args(argv)
    if a.command == "check":
        return check()
    cfg = load(a.tb)
    target = a.target or default_target(cfg)
    if a.command == "targets":
        print("\n".join(targets(cfg)))
    elif a.command == "default-target":
        print(default_target(cfg))
    elif a.command == "top":
        print(cfg["build"]["top_module"])
    elif a.command == "defines":
        print(" ".join(target_defines(cfg, target)))
    elif a.command == "filelist":
        incdirs, sources, top = filelist(cfg)
        for d in incdirs:
            print(f"+incdir+{d}")
        for s in sources:
            print(s)
        if top:
            print(top)
    elif a.command == "configs":
        print_configs(cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
