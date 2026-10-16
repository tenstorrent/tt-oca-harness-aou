# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Read waveforms (FST, VCD, FSDB) through one small interface.

Backends, chosen per file:
- FST, VCD, GHW: pywellen (BSD-3; `make setup` installs it into .deps/pywellen).
- FSDB: an external query tool when WAVEIO_WQ names a directory holding a
  `wq` CLI (search/changes subcommands, `<time><unit> <value>` lines);
  otherwise Verdi's fsdb2vcd converts the file once (cached next to it as
  <name>.fsdb.vcd, about 40x the FSDB size) and pywellen reads the VCD.

Names are full hierarchical paths without a bit range (`top.if.id`); widths
are reported separately. Times are integer femtoseconds. Values are strings:
`0x...` when every bit is 0/1, otherwise a binary string such as `xxxx`.
"""

import fnmatch
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PYWELLEN_PYTHONS = (
    os.environ.get("PYWELLEN_PYTHON", ""),
    os.path.join(HERE, "..", ".deps", "pywellen", "bin", "python"),
    os.path.expanduser("~/.local/share/pywellen/bin/python"),
)
RANGE_RE = re.compile(r"^(.*?)\[(\d+):(\d+)\]$")
UNIT_FS = {"fs": 1, "ps": 10**3, "ns": 10**6, "us": 10**9, "ms": 10**12, "s": 10**15}


def ensure_pywellen():
    """Re-run the calling script under a Python that has pywellen, if needed."""
    try:
        import pywellen  # noqa: F401
        return
    except ImportError:
        pass
    if os.environ.get("WAVEIO_REEXEC"):
        sys.exit("pywellen is not importable; run `make setup` or set PYWELLEN_PYTHON")
    for py in PYWELLEN_PYTHONS:
        if py and os.access(py, os.X_OK):
            os.environ["WAVEIO_REEXEC"] = "1"
            os.execv(py, [py, "-I", os.path.abspath(sys.argv[0])] + sys.argv[1:])
    # No pywellen anywhere: FSDB can still go through WAVEIO_WQ.


def time_fs(text):
    """'709ns' -> femtoseconds. A unit is required."""
    m = re.fullmatch(r"(\d+(?:\.\d+)?)(fs|ps|ns|us|ms)", text or "")
    if not m:
        raise ValueError(f"time needs a unit (fs, ps, ns, us, ms): {text!r}")
    return round(float(m.group(1)) * UNIT_FS[m.group(2)])


def fmt_time(fs):
    for unit in ("ns", "ps"):
        if fs % UNIT_FS[unit] == 0:
            return f"{fs // UNIT_FS[unit]}{unit}"
    return f"{fs}fs"


def fmt_value(val):
    if isinstance(val, int):
        return hex(val)
    s = str(val).lower()
    return "0x" + format(int(s, 2), "x") if s and set(s) <= {"0", "1"} else s


def is_one(value):
    return value in ("0x1", "1", "0b1")


def strip_range(name):
    m = RANGE_RE.match(name)
    if not m:
        return name, None
    return m.group(1), abs(int(m.group(2)) - int(m.group(3))) + 1


class PywellenWave:
    def __init__(self, path):
        import pywellen
        self._pw = pywellen
        self.path = path
        self.wave = pywellen.Waveform(path)
        ts = self.wave.timescale
        self.scale_fs = int(ts.factor) * UNIT_FS[str(ts.unit).split(".")[-1]]
        self.vars = {}
        for v in self.wave.all_vars():
            self.vars.setdefault(v.full_name, v)

    def names(self):
        out = {}
        for n, v in self.vars.items():
            bw = v.bitwidth() if callable(v.bitwidth) else v.bitwidth
            out[n] = bw or 1
        return out

    def changes(self, names):
        want = [self.vars[n] for n in names]
        by_id = {}
        for n in names:
            by_id.setdefault(str(self.vars[n].signal_id), []).append(n)
        out = {n: [] for n in names}

        def cb(t, sid, val):
            for n in by_id.get(str(sid), ()):
                out[n].append((t * self.scale_fs, fmt_value(val)))

        self._pw.Waveform(self.path, stream_only=True).stream_changes(cb, want)
        return out


class ExternalWqWave:
    CHANGE_RE = re.compile(r"^(\d+)(fs|ps|ns)\s+(\S+)")

    def __init__(self, path, root):
        self.path = path
        self.wq = [sys.executable, "-I", os.path.join(root, "wq")]
        self.full = {}  # name without range -> dumped name with range
        self.width = {}
        for line in self._run("search", "--kind", "regex", "--limit", "0", "."):
            name, width = strip_range(line)
            self.full.setdefault(name, line)
            self.width.setdefault(name, width or 1)

    def _run(self, cmd, *rest):
        res = subprocess.run(self.wq + [cmd, self.path, *rest], capture_output=True, text=True, check=False)
        if res.returncode != 0:
            sys.exit(f"{self.wq[-1]} {cmd} failed: {res.stderr.strip() or res.stdout.strip()}")
        return [ln.strip() for ln in res.stdout.splitlines() if ln.strip()]

    def names(self):
        return dict(self.width)

    def changes(self, names):
        out = {}
        for n in names:
            out[n] = []
            for line in self._run("changes", "--limit", "0", self.full[n]):
                m = self.CHANGE_RE.match(line)
                if m:
                    out[n].append((int(m.group(1)) * UNIT_FS[m.group(2)], fmt_value(m.group(3))))
        return out


def fsdb_to_vcd(path):
    vcd = path + ".vcd"
    if os.path.exists(vcd) and os.path.getmtime(vcd) >= os.path.getmtime(path):
        return vcd
    tool = shutil.which("fsdb2vcd") or (os.path.join(os.environ["VERDI_HOME"], "bin", "fsdb2vcd")
                                        if os.environ.get("VERDI_HOME") else None)
    if not tool or not os.path.exists(tool):
        sys.exit("reading FSDB needs Verdi's fsdb2vcd (load the Verdi/VCS module) or WAVEIO_WQ")
    # fsdb2vcd writes fsdb2vcdLog/ into its working directory; keep it next to the VCD.
    res = subprocess.run([tool, os.path.abspath(path), "-o", os.path.abspath(vcd)], capture_output=True,
                         text=True, check=False, cwd=os.path.dirname(os.path.abspath(vcd)))
    if res.returncode != 0 or not os.path.exists(vcd):
        sys.exit(f"fsdb2vcd failed: {res.stderr.strip() or res.stdout.strip()}")
    return vcd


def open_wave(path):
    if not os.path.exists(path):
        sys.exit(f"no such waveform: {path}")
    if path.endswith(".fsdb"):
        root = os.environ.get("WAVEIO_WQ")
        if root and os.path.exists(os.path.join(root, "wq")):
            return ExternalWqWave(path, root)
        path = fsdb_to_vcd(path)
    try:
        return PywellenWave(path)
    except ImportError:
        sys.exit("reading FST/VCD needs pywellen: run `make setup` or set PYWELLEN_PYTHON")


def match(names, pattern, kind="auto"):
    """Names matching a suffix, glob or regex pattern (auto: glob if it has * or ?)."""
    if kind == "auto":
        kind = "glob" if any(c in pattern for c in "*?") else "suffix"
    if kind == "regex":
        rx = re.compile(pattern)
        return [n for n in names if rx.search(n)]
    if kind == "glob":
        return [n for n in names if fnmatch.fnmatchcase(n, pattern)]
    return [n for n in names if n == pattern or n.endswith("." + pattern) or n.endswith(pattern)]
