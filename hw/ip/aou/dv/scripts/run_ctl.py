#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Change a running regression through its run_list.py control file.

  run_ctl.py <ctlfile>                    print the current settings
  run_ctl.py <ctlfile> jobs=20            set one or more keys

run_list.py prints the control file's path when it starts
(out/<build>/<rid>.ctl by default) and applies a change within a few seconds.
The file is rewritten atomically, so run_list.py never reads half of it. Keys:

  jobs=N         runs in flight at most (N >= 1); running jobs are never killed
  pause=0|1      1 stops launching; running jobs finish
  drain=0|1      1 lets running jobs finish, then run_list.py exits
  priority=P     scheduler priority of jobs launched from now on ('' = default)
  queue=Q        scheduler queue of jobs launched from now on ('' = default)
  order=O        fifo (run-list order), shortest (shortest test first, from
                 build/metrics.jsonl) or failed-first (tests that failed before)
"""

import os
import re
import sys
import tempfile

ORDERS = ("fifo", "shortest", "failed-first")
KEYS = ("jobs", "pause", "drain", "priority", "queue", "order")
_TRUE = ("1", "true", "yes", "on")
_FALSE = ("0", "false", "no", "off")


def check(key, value):
    """Return the normalized value of key, or raise ValueError."""
    value = value.strip()
    if key == "jobs":
        if not re.fullmatch(r"\d+", value) or int(value) < 1:
            raise ValueError(f"jobs must be an integer >= 1, not {value!r}")
        return int(value)
    if key in ("pause", "drain"):
        if value.lower() in _TRUE:
            return True
        if value.lower() in _FALSE:
            return False
        raise ValueError(f"{key} must be 0 or 1, not {value!r}")
    if key in ("priority", "queue"):
        if value and not re.fullmatch(r"[\w.-]+", value):
            raise ValueError(f"{key} must be a plain name or number, not {value!r}")
        return value
    if key == "order":
        if value not in ORDERS:
            raise ValueError(f"order must be one of {', '.join(ORDERS)}, not {value!r}")
        return value
    raise ValueError(f"unknown key {key!r} (keys: {', '.join(KEYS)})")


def text(value):
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def parse(content):
    """key=value lines of a control file, unvalidated; '#' starts a comment."""
    values = {}
    for line in content.splitlines():
        line = line.split("#", 1)[0].strip()
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def read(path):
    with open(path, encoding="utf-8") as fh:
        return parse(fh.read())


def write(path, updates, header=None):
    """Set the keys in updates (raw strings or values), keeping the rest of the
    file, and replace the file atomically. header (lines) starts a new file."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except FileNotFoundError:
        lines = []
    if header is not None:
        lines = list(header)
    todo = {k: text(v) for k, v in updates.items()}
    for i, line in enumerate(lines):
        key = line.split("#", 1)[0].split("=", 1)[0].strip()
        if "=" in line.split("#", 1)[0] and key in todo:
            lines[i] = f"{key}={todo.pop(key)}"
    lines += [f"{k}={v}" for k, v in todo.items()]
    fd, tmp = tempfile.mkstemp(prefix=".", suffix=".tmp", dir=os.path.dirname(os.path.abspath(path)))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        os.chmod(tmp, 0o664)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    path, sets = argv[0], argv[1:]
    if not os.path.exists(path):
        sys.exit(f"run_ctl: no control file {path}")
    updates = {}
    for item in sets:
        if "=" not in item:
            sys.exit(f"run_ctl: expected key=value, not {item!r}")
        key, value = item.split("=", 1)
        try:
            updates[key.strip()] = text(check(key.strip(), value))
        except ValueError as e:
            sys.exit(f"run_ctl: {e}")
    if updates:
        write(path, updates)
    for key, value in read(path).items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
