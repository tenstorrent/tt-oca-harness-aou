#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Performance targets from the d2d-compare packing model (d2d_model.py).

The model is an optional external dependency: point D2D_COMPARE at a checkout
of d2d-compare. The generated tables record no model version, so they change only
when a target does. Without it,
`check` still judges runs against the committed table.

Directions are link directions, as in perf.json (docs/PERF_JSON.md): l2r is
the link from the DUT to the remote die (DUT TX: local requests and write
data at the local RP width, plus responses to remote requests at the remote
width), r2l the reverse. The gated value is application bytes delivered per
core cycle on that link (the FDI clock equals the core clock). Efficiency
(application bytes / wire bytes) and duty (flit slots used) are diagnostics.

  perf_model.py targets [--optional] [-o uvm/env/perf/aou_perf_targets.svh]
      Generate the committed target table from docs/perf_scenarios.yaml,
      uvm/env/perf/perf_overrides.yaml and the aou_sim_cfg.toml targets, and the
      window table uvm/env/perf/aou_perf_windows.svh the perf sequence runs.
  perf_model.py check [--out-dir out] [-o out/perf_check.md]
      Judge every out/**/perf.json against the committed table; with
      D2D_COMPARE set, also recompute the table and each run's own model
      and report drift. Exit 1 on drift or a failing verdict.
  perf_model.py run <perf.json>
      Print the model for each window of one run (JSON).
"""

import argparse
import glob
import json
import math
import os
import re
import sys
from fractions import Fraction
from functools import reduce

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import listyaml  # noqa: E402

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIOS = os.path.join(UVM_ROOT, "docs", "perf_scenarios.yaml")
OVERRIDES = os.path.join(UVM_ROOT, "uvm", "env", "perf", "perf_overrides.yaml")
TARGETS = os.path.join(UVM_ROOT, "uvm", "env", "perf", "aou_perf_targets.svh")
WINDOWS = os.path.join(UVM_ROOT, "uvm", "env", "perf", "aou_perf_windows.svh")
SIM_CFG = os.path.join(UVM_ROOT, "aou_sim_cfg.toml")

DEFAULT_TOL = 0.03          # gate: measured >= (1 - tol) x model
EPS_BYTES = 256             # above-model margin: one flit per window (quantization only)
REMOTE_BYTES_DEFAULT = 64   # aou_t1_env_cfg.remote_bytes
AXI_4K = 4096
FDI_PHY_BYTES = {0: [32], 1: [64], 2: [128], 3: [32, 64], 4: [64, 128]}   # FDI_CONFIG -> PHY widths
DIRS = ("l2r", "r2l")
DRIFT_REL = 1e-4

_MODEL = None


# -----------------------------------------------------------------------------
# d2d-compare
# -----------------------------------------------------------------------------
def model():
    """The d2d_model module from $D2D_COMPARE; exits if it is not set."""
    global _MODEL
    if _MODEL is None:
        root = os.environ.get("D2D_COMPARE")
        if not root or not os.path.exists(os.path.join(root, "d2d_model.py")):
            sys.exit("perf_model: set D2D_COMPARE to a d2d-compare checkout (d2d_model.py)")
        sys.path.insert(0, os.path.abspath(root))
        import d2d_model  # noqa: E402
        _MODEL = d2d_model
    return _MODEL


def port_of(m, width):
    for p, w in m.PORT_W.items():
        if w == width:
            return p
    raise ValueError(f"d2d_model has no {8 * width}-bit port")


# -----------------------------------------------------------------------------
# Model of one window
# -----------------------------------------------------------------------------
def _txns(m, side, g=None):
    """side: [(kind, size, offset, width, beat, partial, count)] -> one period of Txns,
    counts divided by g (default: their gcd). width is the issuing port's data bytes,
    beat the transfer's AxSIZE bytes."""
    g = g or reduce(math.gcd, [e[-1] for e in side if e[-1] > 0], 0) or 1
    out = []
    for kind, size, offset, width, beat, partial, count in side:
        out += [m.Txn(kind, size, offset % AXI_4K, port_of(m, width), partial,
                      beat if beat < width else 0)] * (count // g)
    return out


def model_window(fdi_bytes, local, remote):
    """Saturated model of a window. local/remote: the traffic each side puts on the
    link as [(kind 'R'|'W', bytes, offset, port bytes, AxSIZE bytes, partial strobes,
    count)]; empty when that side issues nothing. Bursts travel the link whole: the
    DUT's transaction splitter acts on the requests it receives, at its manager port,
    not on what its subordinate port sends. Returns {dir: {bpc, eff, duty, msgs}}."""
    m = model()
    cfg = m.Config(fdi_bytes=fdi_bytes, fdi_ghz=1.0)
    # One period for both sides together: the model issues both lists at the same
    # rate, so the sides keep their transaction-count ratio.
    g = reduce(math.gcd, [e[-1] for e in local + remote if e[-1] > 0], 0) or 1
    lt, rt = _txns(m, local, g), _txns(m, remote, g)
    if not lt and not rt:
        raise ValueError("window with no traffic")
    if lt:
        sc = m.Scenario("bench", lt, remote_txns=rt or None)
        ab, ba = "l2r", "r2l"
    else:
        sc = m.Scenario("bench", rt)      # the remote die's requests travel B->A here
        ab, ba = "r2l", "l2r"
    r = m.run_dirs(m.AoU(cfg), sc)
    out = {}
    for d, k in ((ab, "AB"), (ba, "BA")):
        out[d] = {"bpc": r["Bpb_" + k], "eff": r["eff_" + k], "duty": r["util_" + k],
                  "msgs": r["msgs_" + k]}
    return out


def mix_fractions(msgs):
    """Message mix as fractions of the data-path messages (credits/activation excluded)."""
    keep = {k: v for k, v in msgs.items()
            if k.startswith(("Read", "Write"))}
    tot = sum(keep.values()) or 1
    return {k: v / tot for k, v in keep.items()}


# -----------------------------------------------------------------------------
# Configs and scenarios
# -----------------------------------------------------------------------------
def read_configs(sim_cfg_path=SIM_CFG):
    """{CONFIG: {rp_bytes: [..per RP..], phy_bytes: [..per PHY..]}} from the T1 sim config's targets."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sim_cfg
    out = {}
    for c, row in sim_cfg.t1_configs(sim_cfg.load_toml(sim_cfg_path)).items():
        out[c] = {"rp_bytes": [w // 8 for w in row["rp_widths"]], "phy_bytes": FDI_PHY_BYTES[row["fdi"]]}
    return out


def load_scenarios(path=SCENARIOS):
    return listyaml.load(path)


def _ilist(v):
    return [int(x) for x in (v if isinstance(v, list) else str(v).split(","))]


def axsize(beats, width):
    """AxSIZE bytes of a `beats`-beat burst on a `width`-byte bus: the bus width, or
    narrower where the burst would exceed 4 KB (docs/perf_scenarios.yaml)."""
    s = width
    while beats * s > AXI_4K and s > 1:
        s //= 2
    return s


def _shares(w, conf):
    """(RPs, share of the transactions per RP, [(kind, fraction)], den): den x share x
    fraction is a whole number of transactions per period for every RP and kind."""
    n = len(conf["rp_bytes"])
    rps = list(range(n)) if w.get("rps", "all") == "all" else [r for r in _ilist(w["rps"]) if r < n]
    if "widest_pct" in w:
        wide = max(rps, key=lambda r: (conf["rp_bytes"][r], -r))
        pct = Fraction(int(w["widest_pct"]), 100)
        others = [r for r in rps if r != wide]
        share = {r: (pct if r == wide else (1 - pct) / len(others)) if others else 1 for r in rps}
    else:
        share = {r: Fraction(1, len(rps)) for r in rps}
    wr = Fraction(int(w.get("wr_pct", 0)), 100)
    kinds = [k for k in (("W", wr), ("R", 1 - wr)) if k[1] > 0]
    den = reduce(lambda a, b: a * b // math.gcd(a, b),
                 [(s * f).denominator for s in share.values() for _, f in kinds], 1)
    return rps, share, kinds, den


def rp_weights(w, conf):
    """Transactions per RP and issuing side in one period of the window's pattern
    (0 for an RP without traffic); the perf sequence issues a multiple of it."""
    rps, share, _, den = _shares(w, conf)
    return [int(share[r] * den) if r in rps else 0 for r in range(len(conf["rp_bytes"]))]


def window_sides(w, conf):
    """Issued traffic of a scenario window on a config: (local, remote), or None
    when a burst would cross 4 KB on some issuing side."""
    n = len(conf["rp_bytes"])
    rps, share, kinds, den = _shares(w, conf)
    rb = _ilist(w.get("remote_bytes", REMOTE_BYTES_DEFAULT))
    rem = [rb[r] if r < len(rb) else rb[0] for r in range(n)]
    offset = int(w.get("offset", 0))
    partial = w.get("strb", "full") == "partial"

    def side(widths):
        out = []
        for r in rps:
            if "bytes" in w:
                beat, size = widths[r], int(w["bytes"])
            else:
                beat, size = axsize(int(w["beats"]), widths[r]), int(w["beats"]) * axsize(
                    int(w["beats"]), widths[r])
            if offset + size > AXI_4K:
                return None
            for k, f in kinds:
                cnt = int(share[r] * f * den)
                if cnt:
                    e = (k, size, offset, widths[r], beat, partial and k == "W", cnt)
                    out.append(e)
        return out

    loc, rem_side = side(conf["rp_bytes"]), side(rem)
    if loc is None or rem_side is None:
        return None
    td = w.get("traffic_dir", "both")
    return (loc if td in ("l2r", "both") else [], rem_side if td in ("r2l", "both") else [])


def load_overrides(path=OVERRIDES):
    out = {}
    if not os.path.exists(path):
        return out
    for e in listyaml.load(path):
        key = (e["config"], int(e.get("active_phy", 0)), e["scenario"], e["window"], e["dir"])
        if not e.get("reason"):
            sys.exit(f"perf_overrides: entry {key} has no reason")
        out[key] = {"tol": float(e["tol"]), "reason": e["reason"]}
    return out


def gen_windows(optional=False, configs=None):
    """[(config, scenario window entry)] for every window a config runs (in file order)."""
    configs = configs or read_configs()
    out = []
    for w in load_scenarios():
        if w.get("optional") == "yes" and not optional:
            continue
        names = list(configs) if w.get("configs", "all") == "all" else w["configs"]
        for c in configs:
            if c in names and window_sides(w, configs[c]) is not None:
                out.append((c, w))
    return out


def gen_targets(optional=False, configs=None):
    """[{config, active_phy, scenario, window, dir, model, eff, duty, tol, eps, reason, mix}]"""
    configs = configs or read_configs()
    ovr = load_overrides()
    rows = []
    for c, w in gen_windows(optional, configs):
        sides = window_sides(w, configs[c])
        for phy, fdi in enumerate(configs[c]["phy_bytes"]):
            res = model_window(fdi, *sides)
            for d in DIRS:
                if res[d]["bpc"] <= 0:
                    continue        # no data on this link: nothing to gate
                key = (c, phy, w["scenario"], w["window"], d)
                o = ovr.get(key, {})
                rows.append(dict(config=c, active_phy=phy, scenario=w["scenario"],
                                 window=w["window"], dir=d, model=res[d]["bpc"],
                                 eff=res[d]["eff"], duty=res[d]["duty"],
                                 tol=o.get("tol", DEFAULT_TOL), eps=EPS_BYTES,
                                 reason=o.get("reason", ""),
                                 mix=mix_fractions(res[d]["msgs"])))
    return rows


def key_of(r):
    return f"{r['config']}|{r['active_phy']}|{r['scenario']}|{r['window']}|{r['dir']}"


# -----------------------------------------------------------------------------
# The committed tables (SystemVerilog)
# -----------------------------------------------------------------------------
SVH_HEAD = """\
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// GENERATED by scripts/perf_model.py (make perf_targets). Do not edit.
// Performance targets from d2d-compare's d2d_model.py, for the windows of
// docs/perf_scenarios.yaml, with uvm/env/perf/perf_overrides.yaml applied.
// Key: "<CONFIG>|<active PHY>|<scenario>|<window>|<dir>", dir = link (l2r: DUT TX).
// model: application bytes per core cycle on that link, saturated. aou_perf_chk
// passes a link when measured >= (1 - tol) x model and measured <= model + eps /
// cycles (eps: one flit of bytes, measurement quantization only). eff and duty are
// the model's packing efficiency and FDI duty on that link (diagnostics). mix: the
// share of each data-path message type on the link (T1-P04). A link without
// application data has no entry.
class aou_perf_targets;
  static real         model[string];
  static real         eff[string];
  static real         duty[string];
  static real         tol[string];
  static int unsigned eps_bytes[string];
  static string       reason[string];
  static real         mix_frac[string];   // "<key>#<message>"
  static bit          loaded;

  static function string key(string cfg_name, int unsigned phy, string scenario, string window,
                             string dir);
    return $sformatf("%s|%0d|%s|%s|%s", cfg_name, phy, scenario, window, dir);
  endfunction

  static function bit has(string k);
    load();
    return model.exists(k);
  endfunction

  // Model share of message type msg on the link of key k (0 when the model sends none).
  static function real mix_of(string k, string msg);
    load();
    return mix_frac.exists({k, "#", msg}) ? mix_frac[{k, "#", msg}] : 0.0;
  endfunction

  static function void add(string k, real m, real e, real d, real t, int unsigned eps,
                           string r = "");
    model[k] = m;
    eff[k] = e;
    duty[k] = d;
    tol[k] = t;
    eps_bytes[k] = eps;
    reason[k] = r;
  endfunction

  static function void mix(string k, string msg, real f);
    mix_frac[{k, "#", msg}] = f;
  endfunction

  static function void load();
    if (loaded) return;
    loaded = 1'b1;
"""
SVH_TAIL = """\
  endfunction
endclass
"""
ADD_RE = re.compile(r'^\s*add\("([^"]+)", ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), (\d+)'
                    r'(?:,\s*"((?:[^"\\]|\\.)*)")?\);')
MIX_RE = re.compile(r'^\s*mix\("([^"]+)", "([^"]+)", ([-\d.e]+)\);')

WIN_HEAD = """\
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// GENERATED by scripts/perf_model.py (make perf_targets). Do not edit.
// The windows of docs/perf_scenarios.yaml each CONFIG runs, in file order, for
// aou_perf_vseq (+perf_scn=<scenario>). A window whose bursts would cross 4 KB on
// some issuing side is left out for that CONFIG. aou_perf_targets holds their
// targets.
class aou_perf_windows;
  static aou_perf_window wins[$];
  static bit             loaded;

  // weight: transactions per RP and issuing side in one period of the pattern.
  static function void add(string c, string scn, string name, string dir, int wr_pct,
                           int beats, int bytes, int offset, bit partial, int w0, int w1,
                           int w2, int w3);
    aou_perf_window w = aou_perf_window::type_id::create(name);
    w.init(c, scn, name, dir, wr_pct, beats, bytes, offset, partial, '{w0, w1, w2, w3});
    wins.push_back(w);
  endfunction

  // The windows of scenario scn on CONFIG c.
  static function void of(string c, string scn, ref aou_perf_window q[$]);
    load();
    q.delete();
    foreach (wins[i]) if (wins[i].config_name == c && wins[i].scenario == scn) q.push_back(wins[i]);
  endfunction

  static function void load();
    if (loaded) return;
    loaded = 1'b1;
"""


def write_windows_svh(path, optional=False, configs=None):
    configs = configs or read_configs()
    lines = [WIN_HEAD]
    for c, w in gen_windows(optional, configs):
        wt = (rp_weights(w, configs[c]) + [0, 0, 0])[:4]
        lines.append(
            f'    add("{c}", "{w["scenario"]}", "{w["window"]}", "{w.get("traffic_dir", "both")}", '
            f'{int(w.get("wr_pct", 0))}, {int(w.get("beats", 0))}, {int(w.get("bytes", 0))}, '
            f'{int(w.get("offset", 0))}, {int(w.get("strb", "full") == "partial")}, '
            f'{", ".join(str(x) for x in wt)});\n')
    lines.append(SVH_TAIL)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(lines))


def write_svh(rows, path=TARGETS):
    lines = [SVH_HEAD]
    for r in rows:
        args = f'"{key_of(r)}", {r["model"]:.4f}, {r["eff"]:.4f}, {r["duty"]:.4f}, ' \
               f'{r["tol"]:.4f}, {r["eps"]}'
        if r["reason"]:
            reason = r["reason"].replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'    add({args}, "{reason}");\n')
        else:
            lines.append(f"    add({args});\n")
        for msg, f in sorted((r.get("mix") or {}).items()):
            lines.append(f'    mix("{key_of(r)}", "{msg}", {f:.6f});\n')
    lines.append(SVH_TAIL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(lines))


def read_svh(path=TARGETS):
    """{key: {model, eff, duty, tol, eps, reason, mix}} from the committed table."""
    rows = {}
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as fh:
        text = fh.read().splitlines()
    for line in text:
        mm = ADD_RE.match(line)
        if mm:
            rows[mm.group(1)] = dict(model=float(mm.group(2)), eff=float(mm.group(3)),
                                     duty=float(mm.group(4)), tol=float(mm.group(5)),
                                     eps=int(mm.group(6)), reason=mm.group(7) or "", mix={})
        mm = MIX_RE.match(line)
        if mm and mm.group(1) in rows:
            rows[mm.group(1)]["mix"][mm.group(2)] = float(mm.group(3))
    return rows


# -----------------------------------------------------------------------------
# Runs
# -----------------------------------------------------------------------------
def run_sides(build, win):
    """(local, remote) traffic of a perf.json window on the link, from txn_hist."""
    full_pct = int(build.get("remote_full_pct", 100))
    rpb = build.get("rp_bytes") or []
    rmb = build.get("remote_bytes") or []
    local, remote = [], []
    for h in win.get("txn_hist", []):
        k, rp = h["kind"], int(h.get("rp", 0))
        partial = (k == "W") and not (h.get("full_strb", True) and build.get("writefull", True))
        beat = int(h["beat_bytes"])
        if h["init"] == "l2r":
            width = int(rpb[rp]) if rp < len(rpb) else beat
            local.append((k, int(h["bytes"]), int(h.get("offset_mod_4k", 0)), width, beat,
                          partial, int(h["count"])))
            continue
        width = int(rmb[rp]) if rp < len(rmb) else beat
        ent = (k, int(h["bytes"]), int(h.get("offset_mod_4k", 0)), width, beat, partial,
               int(h["count"]))
        if k == "W" and not partial and full_pct < 100:
            # the remote die sends WriteDataFull for only full_pct % of its full-strobe writes
            c = ent[6]
            nf = round(c * full_pct / 100)
            remote += [e for e in (ent[:5] + (False, nf), ent[:5] + (True, c - nf)) if e[6]]
        else:
            remote.append(ent)
    return local, remote


def model_run(perf):
    """{window: model_window(...)} for the bandwidth windows of one perf.json."""
    b = perf["build"]
    out = {}
    for w in perf.get("windows", []):
        if not w.get("txn_hist") or w.get("scenario") in ("lat", "drain"):
            continue
        out[w["name"]] = model_window(int(b["beat_bytes"]), *run_sides(b, w))
    return out


def measured(win, d):
    """The gated figures of link d: steady-state bytes/cycle, the whole window's message
    counts (window_msgs; full.msgs_by_msg in older perf.json) and mix_cap, the link's
    saturated capacity for the messages it carried in the steady state."""
    x = (win.get("dir") or {}).get(d) or {}
    if not x.get("cycles"):
        return None
    ss, full = x.get("ss") or {}, x.get("full") or {}
    cap = ss.get("mix_cap")
    return dict(bpc=x["app_bytes"] / x["cycles"], cycles=x["cycles"],
                ss_ok=bool(ss.get("ss_ok")), duty=x.get("duty"), mix_cap=cap or 0.0,
                msgs=(win.get("window_msgs") or {}).get(d) or full.get("msgs_by_msg")
                or ss.get("msgs_by_msg") or {})


MIX_ABS = 1.0       # T1-P04: a message count may differ from the model's share by
MIX_REL = 0.002     # max(MIX_ABS, MIX_REL x data-path messages on the link)


def mix_error(msgs, model_mix):
    """Largest |count - model share x total| over the data-path messages, and the bound."""
    keep = {k: v for k, v in msgs.items() if k.startswith(("Read", "Write"))}
    tot = sum(keep.values())
    if not tot or not model_mix:
        return 0.0, 0.0
    err = max(abs(keep.get(x, 0) - model_mix.get(x, 0.0) * tot) for x in set(keep) | set(model_mix))
    return err, max(MIX_ABS, MIX_REL * tot)


def judge(meas, tgt):
    """PASS, or the failed checks joined by '+': BELOW (T1-P02), ABOVE (T1-P03), MIX
    (T1-P04), SHORT (steady state below min_ss_flits); NO_TARGET without a target.
    Returns (verdict, measured/model). The above-model bound follows the steady
    state's messages: max(model, mix_cap) + eps / cycles (aou_perf_chk)."""
    if tgt is None:
        return "NO_TARGET", None
    m = tgt["model"]
    ratio = meas["bpc"] / m if m else None
    bad = []
    if meas["bpc"] > max(m, meas.get("mix_cap", 0.0)) + tgt["eps"] / meas["cycles"]:
        bad.append("ABOVE")
    if meas["bpc"] < (1 - tgt["tol"]) * m:
        bad.append("BELOW")
    err, lim = mix_error(meas.get("msgs") or {}, tgt.get("mix") or {})
    if err > lim:
        bad.append("MIX")
    if "ss_ok" in meas and not meas["ss_ok"]:
        bad.append("SHORT")
    return ("+".join(bad) or "PASS"), ratio


def collect(out_dir):
    """[(run_dir, perf)] for every out/**/perf.json."""
    res = []
    for p in sorted(glob.glob(os.path.join(out_dir, "**", "perf.json"), recursive=True)):
        try:
            with open(p, encoding="utf-8") as fh:
                res.append((os.path.dirname(p), json.load(fh)))
        except (OSError, ValueError) as e:
            print(f"skip {p}: {e}", file=sys.stderr)
    return res


def run_verdict(run_dir):
    try:
        with open(os.path.join(run_dir, "verdict.txt"), encoding="utf-8") as fh:
            return fh.read().split()[0].rstrip(":")
    except (OSError, IndexError):
        return "?"


def judge_runs(out_dir, table, live=False):
    """Rows: one per (run, bandwidth window, link with data or a target)."""
    rows = []
    for run_dir, perf in collect(out_dir):
        b = perf.get("build", {})
        own = {}
        if live:
            try:
                own = model_run(perf)
            except (KeyError, ValueError) as e:
                print(f"{run_dir}: no run model: {e}", file=sys.stderr)
        for w in perf.get("windows", []):
            if w.get("scenario") in ("lat", "drain", None, ""):
                continue
            for d in DIRS:
                k = f"{b.get('config', '')}|{b.get('active_phy', 0)}|{w['scenario']}|{w['name']}|{d}"
                tgt = table.get(k)
                meas = measured(w, d)
                if meas is None or meas["bpc"] <= 0:
                    if tgt is None:
                        continue
                    meas = dict(bpc=0.0, cycles=1.0, ss_ok=False, duty=0.0, msgs={})
                verdict, ratio = judge(meas, tgt)
                r = dict(run=os.path.relpath(run_dir, out_dir), build=os.path.basename(
                    os.path.dirname(run_dir)), run_verdict=run_verdict(run_dir), key=k,
                    config=b.get("config", ""), active_phy=b.get("active_phy", 0),
                    sim=b.get("sim", ""), seed=b.get("seed"), scenario=w["scenario"],
                    window=w["name"], dir=d, measured=meas["bpc"],
                    model=tgt["model"] if tgt else None, tol=tgt["tol"] if tgt else None,
                    ratio=ratio, verdict=verdict, duty=meas["duty"])
                if tgt:
                    r["mix_err"] = mix_error(meas.get("msgs") or {}, tgt.get("mix") or {})[0]
                if w["name"] in own:
                    r["run_model"] = own[w["name"]][d]["bpc"]
                rows.append(r)
    return rows


def _f(v, fmt="{:.2f}"):
    return "-" if v is None else fmt.format(v)


def cmd_check(args):
    table = read_svh()
    live = bool(os.environ.get("D2D_COMPARE"))
    lines = ["# Performance check", "",
             f"Committed table: `uvm/env/perf/aou_perf_targets.svh`, {len(table)} targets.", ""]
    bad = 0
    if live:
        opt = any(k.split("|")[2] == "S6" for k in table)
        fresh = {key_of(r): r for r in gen_targets(optional=opt)}
        drift = []
        for k in sorted(set(fresh) | set(table)):
            a, t = fresh.get(k), table.get(k)
            if a is None or t is None or abs(a["tol"] - t["tol"]) > 1e-9 or \
                    abs(a["model"] - t["model"]) > max(DRIFT_REL * t["model"], 5e-5) or \
                    any(abs(a["mix"].get(x, 0) - t["mix"].get(x, 0)) > 2e-6
                        for x in set(a["mix"]) | set(t["mix"])):
                drift.append((k, a and a["model"], t and t["model"]))
        lines += [f"Live model (D2D_COMPARE). Drift against the table: {len(drift)}.", ""]
        if drift:
            lines += ["| key | live model | table |", "|---|---|---|"]
            lines += [f"| {k} | {_f(a, '{:.4f}')} | {_f(t, '{:.4f}')} |" for k, a, t in drift]
            lines.append("")
        bad += len(drift)
    else:
        lines += ["D2D_COMPARE not set: no drift check, no per-run model.", ""]
    rows = judge_runs(args.out_dir, table, live)
    lines += ["Check: BELOW (T1-P02), ABOVE (T1-P03), MIX (T1-P04), SHORT (steady state below "
              "min_ss_flits). mix err: largest message-count difference from the model's mix.",
              "", "| run | verdict | window | dir | measured B/cyc | model | ratio | check | "
              "run model | mix err |", "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['run']} | {r['run_verdict']} | {r['window']} | {r['dir']} | "
                     f"{_f(r['measured'])} | {_f(r['model'])} | {_f(r['ratio'], '{:.3f}')} | "
                     f"{r['verdict']} | {_f(r.get('run_model'))} | {_f(r.get('mix_err'), '{:.1f}')} |")
        bad += not r["verdict"].startswith("PASS")
    text = "\n".join(lines) + "\n"
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(text)
    print(f"perf_check: {len(rows)} window links judged, {bad} drift/failing")
    return 1 if bad else 0


def cmd_targets(args):
    rows = gen_targets(optional=args.optional)
    write_svh(rows, args.output)
    write_windows_svh(args.windows, optional=args.optional)
    print(f"wrote {args.output}: {len(rows)} targets; {args.windows}")
    return 0


def cmd_run(args):
    with open(args.perf_json, encoding="utf-8") as fh:
        res = model_run(json.load(fh))
    json.dump(res, sys.stdout, indent=1, sort_keys=True)
    print()
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("targets")
    t.add_argument("--optional", action="store_true", help="include optional windows (S6)")
    t.add_argument("-o", "--output", default=TARGETS)
    t.add_argument("--windows", default=WINDOWS)
    c = sub.add_parser("check")
    c.add_argument("--out-dir", default=os.path.join(UVM_ROOT, "out"))
    c.add_argument("-o", "--output")
    r = sub.add_parser("run")
    r.add_argument("perf_json")
    args = ap.parse_args()
    return {"targets": cmd_targets, "check": cmd_check, "run": cmd_run}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
