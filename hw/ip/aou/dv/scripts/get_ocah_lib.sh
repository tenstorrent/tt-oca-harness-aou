#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
#
# Fetch the pinned OCAH shared framework library (ocah_lib and the
# ocah_checker evidence base it composes) from the public tt-oca-harness
# repository into the git-ignored .deps/ocah_lib/ as a sparse checkout, so
# the library sits at the same hw/common/dv/vip/... paths the harness's
# sources.toml manifests name. aou_base_test / aou_base_test_seq extend its
# ocah_test / ocah_sequence. Vendored into the harness, the library comes
# from the harness tree instead and this script is not run.
#
# OCAH_LIB_ROOT overrides the destination; OCAH_LIB_REF the pin (for a
# local probe of a newer library; the committed pin is what CI uses).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OCAH_LIB_ROOT:-$HERE/.deps/ocah_lib}"
URL="${OCAH_LIB_URL:-https://github.com/tenstorrent/tt-oca-harness.git}"
REF="${OCAH_LIB_REF:-1391eb24074976e694660372281e4d84c5483a7f}"
PATHS=(hw/common/dv/vip/ocah_lib/uvm hw/common/dv/vip/ocah_checker/uvm)

if [[ -f "$DEST/hw/common/dv/vip/ocah_lib/uvm/ocah_lib_pkg.sv" ]]; then
  actual="$(git -C "$DEST" rev-parse HEAD)"
  [[ "$actual" == "$REF" ]] || { echo "ocah_lib at $actual, expected $REF" >&2; exit 1; }
  exit 0
fi

mkdir -p "$DEST"
git -C "$DEST" init -q
git -C "$DEST" remote add origin "$URL" 2>/dev/null || git -C "$DEST" remote set-url origin "$URL"
git -C "$DEST" sparse-checkout set --no-cone "${PATHS[@]}"
git -C "$DEST" fetch -q --depth 1 origin "$REF"
git -C "$DEST" checkout -q --detach FETCH_HEAD
echo "ocah_lib $REF -> $DEST"
