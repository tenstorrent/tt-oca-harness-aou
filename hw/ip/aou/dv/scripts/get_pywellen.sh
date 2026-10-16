#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

# The wave tools (scripts/waveio.py) read FST and VCD with pywellen (BSD-3,
# the wellen library behind the Surfer viewer). Install it into .deps/pywellen.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/.deps/pywellen"
VERSION=0.25.6
if [[ -x "$DEST/bin/python" ]] && "$DEST/bin/python" -I -c "import pywellen" 2>/dev/null; then
  exit 0
fi
PYTHON="${PYTHON:-python3}"
"$PYTHON" -m venv "$DEST"
"$DEST/bin/pip" install --quiet "pywellen==$VERSION"
"$DEST/bin/python" -I -c "import importlib.metadata as m; print('pywellen', m.version('pywellen'))"
