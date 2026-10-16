# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Reader and writer for the list-of-maps YAML subset the plan items, the perf
scenarios and expected_fail.yaml use.

Supported: a top-level list of flat maps; scalars bare, single- or
double-quoted; inline lists `[a, b]`; folded/literal blocks (`>-`, `|`).
Every scalar stays a string, so a plan ID such as 4.10 is never read as the
number 4.1, as a full YAML loader would.
"""

import re

KEY_RE = re.compile(r"^(\s*)(-\s+)?([A-Za-z_]\w*):(?:\s+(.*))?$")


def _scalar(val):
    val = val.strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
        inner = val[1:-1]
        return inner.replace("''", "'") if val[0] == "'" else inner
    # Unquoted: a ' #' starts a trailing comment.
    return re.split(r"\s+#", val, maxsplit=1)[0].strip()


def _value(val):
    val = val.strip()
    if val.startswith("[") and val.endswith("]"):
        body = val[1:-1].strip()
        return [_scalar(v) for v in body.split(",")] if body else []
    return _scalar(val)


def load(path):
    """Return the file's entries as a list of dicts (values: str or list of str)."""
    entries, cur, block_key, block_ind, block_lines = [], None, None, 0, []

    def end_block():
        nonlocal block_key
        if block_key is not None and cur is not None:
            cur[block_key] = " ".join(s.strip() for s in block_lines).strip()
        block_key = None

    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip()
            if block_key is not None:
                ind = len(line) - len(line.lstrip())
                if not line.strip() or ind > block_ind:
                    block_lines.append(line)
                    continue
                end_block()
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = KEY_RE.match(line)
            if not m:
                continue
            if m.group(2):
                cur = {}
                entries.append(cur)
            if cur is None:
                continue
            key, val = m.group(3), m.group(4) or ""
            if val.strip() in (">-", ">", "|", "|-"):
                block_key, block_ind, block_lines = key, len(m.group(1)) + len(m.group(2) or ""), []
                continue
            cur[key] = _value(val)
    end_block()
    return entries


def ids(value):
    """Split a plan_ids/replaces value (list, comma or space separated) into strings."""
    if isinstance(value, list):
        items = value
    else:
        items = re.split(r"[,\s]+", value or "")
    return [i.strip() for i in items if i and i.strip()]


def quote(val):
    if isinstance(val, list):
        return "[" + ", ".join(quote(v) for v in val) + "]"
    val = str(val)
    if val == "" or re.search(r"[:#\[\]{}',&*!|>%@`\"]|^[-?\s]|\s$", val) or \
            re.fullmatch(r"[\d.]+|true|false|yes|no|null|~", val, re.I):
        return "'" + val.replace("'", "''") + "'"
    return val


def dump(entries, keys, header=""):
    """Format entries as YAML, keys in the given order, missing keys omitted."""
    out = [header.rstrip("\n"), ""] if header else []
    for e in entries:
        first = True
        for k in keys:
            if k not in e or e[k] is None:
                continue
            out.append(("- " if first else "  ") + f"{k}: {quote(e[k])}")
            first = False
        out.append("")
    return "\n".join(out)
