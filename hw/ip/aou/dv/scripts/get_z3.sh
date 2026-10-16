#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

# Verilator's randomize() needs an SMT solver at run time. Install z3 (the pip
# package ships a static binary) into .deps/z3 unless the pinned version is
# already available.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/.deps/z3"
Z3_PACKAGE_VERSION=4.15.3.0
Z3_VERSION=4.15.3

check_z3() {
  local z3_bin="$1"
  [[ -x "$z3_bin" ]] &&
    "$z3_bin" --version | grep -qF "Z3 version $Z3_VERSION"
}

if check_z3 "$DEST/bin/z3"; then
  exit 0
fi
if command -v z3 >/dev/null 2>&1 && check_z3 "$(command -v z3)"; then
  exit 0
fi
PYTHON="${PYTHON:-python3}"
rm -rf "$DEST"
"$PYTHON" -m venv "$DEST"
"$DEST/bin/pip" install --quiet "z3-solver==$Z3_PACKAGE_VERSION"
"$DEST/bin/z3" --version
