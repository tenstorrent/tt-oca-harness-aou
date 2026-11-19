#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# (c) 2026 Tenstorrent USA Inc
#
# Render WaveDrom timing-diagram sources under DOC/**/wavedrom/ into checked-in
# SVGs in the sibling assets/ directory. Run from the repository root after
# adding or editing a .json5 source:
#   bash scripts/gen_wavedrom_svgs.sh             # every source
#   bash scripts/gen_wavedrom_svgs.sh <file>...   # only the sources named
#
# The .json5 sources (WaveJSON, https://wavedrom.com/tutorial.html) are the
# reviewable, hand-edited source of truth; the SVGs they produce are committed
# alongside them so that rendering the .adoc docs never depends on
# WaveDrom/Node at build time. Requires wavedrom-cli on PATH -- install with:
#   npm install -g wavedrom-cli
# WaveDrom draws on a transparent background; the script gives the SVG a white
# one, like the Mermaid figures, so it stays readable on a dark page.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v wavedrom-cli >/dev/null 2>&1; then
  echo "error: wavedrom-cli not found on PATH" >&2
  echo "       install with: npm install -g wavedrom-cli" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  sources=("$@")
else
  sources=()
  while IFS= read -r -d '' src; do
    sources+=("$src")
  done < <(find DOC -type f -path '*/wavedrom/*.json5' -print0 | sort -z)
fi

status=0
for src in "${sources[@]}"; do
  assets_dir="$(dirname "$(dirname "$src")")/assets"
  mkdir -p "$assets_dir"
  name="$(basename "${src%.json5}")"
  svg="$assets_dir/$name.svg"
  echo "  $src -> $svg"
  if wavedrom-cli -i "$src" -s "$svg.tmp"; then
    # the root <svg> tag opens the file: add the white background to it only
    sed '1s/<svg /<svg style="background-color: white;" /' "$svg.tmp" > "$svg"
    rm -f "$svg.tmp"
  else
    rm -f "$svg.tmp"
    echo "error: failed to render $src" >&2
    status=1
  fi
done

exit "$status"
