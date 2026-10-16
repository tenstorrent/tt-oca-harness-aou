#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

# Verilator's randomize() needs an SMT solver at run time. Install z3 (the pip
# package ships a static binary) into .deps/z3 unless one is already on PATH.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/.deps/z3"
if [[ -x "$DEST/bin/z3" ]] || command -v z3 >/dev/null 2>&1; then
  exit 0
fi
PYTHON="${PYTHON:-python3}"
"$PYTHON" -m venv "$DEST"
"$DEST/bin/pip" install --quiet z3-solver
"$DEST/bin/z3" --version
