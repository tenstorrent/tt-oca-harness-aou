#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

# PeakRDL at the versions the repository pins (requirements.txt), used to
# generate the UVM register model from the unmodified RDL.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
DEST="$HERE/.deps/peakrdl"
[[ -x "$DEST/bin/peakrdl" ]] && exit 0
PYTHON="${PYTHON:-python3}"
"$PYTHON" -m venv "$DEST"
"$DEST/bin/pip" install --quiet $(grep -E '^peakrdl(-cli|-uvm)?==' "$ROOT/requirements.txt")
"$DEST/bin/peakrdl" --version
