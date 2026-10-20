#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
#
# Unpack Arm's AXI4 protocol checker (Axi4PC, BP063) into the git-ignored
# .deps/BP063/, where the Makefile finds it (AXI4PC_DIR). Optional: without a
# tarball this does nothing. Arm's download needs an account and acceptance of
# its licence, so the user fetches BP063 from
# https://developer.arm.com/downloads/view/BP063 and names the tarball:
#
#   make setup AXI4PC_TGZ=<path>/BP063-r0p1-00rel0.tgz
#
# The licence allows use but not redistribution: never commit what this unpacks.
# AXI4PC_ROOT overrides the destination.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${AXI4PC_ROOT:-$HERE/.deps/BP063}"
TGZ="${AXI4PC_TGZ:-}"

found() { compgen -G "$DEST/*/sva/Axi4PC.sv" >/dev/null || [[ -f "$DEST/sva/Axi4PC.sv" ]]; }

if [[ -z "$TGZ" ]]; then
  found && echo "Axi4PC in $DEST"
  exit 0
fi
[[ -f "$TGZ" ]] || { echo "AXI4PC_TGZ=$TGZ: no such file" >&2; exit 1; }
# Members must stay inside the destination and include Axi4PC.sv.
members="$(tar -tzf "$TGZ")"
if grep -qE '(^/|(^|/)\.\.(/|$))' <<<"$members"; then
  echo "$TGZ: refusing an archive with absolute or .. member paths" >&2; exit 1
fi
grep -q 'sva/Axi4PC\.sv$' <<<"$members" || { echo "$TGZ: no sva/Axi4PC.sv; is it BP063?" >&2; exit 1; }
mkdir -p "$DEST"
tar -xzf "$TGZ" -C "$DEST"
found || { echo "$TGZ unpacked into $DEST, but no */sva/Axi4PC.sv there" >&2; exit 1; }
echo "Axi4PC $(basename "$TGZ") -> $DEST"
