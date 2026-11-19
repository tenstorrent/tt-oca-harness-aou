#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# (c) 2026 Tenstorrent USA Inc
#
# Render every Mermaid diagram source under DOC/**/mermaid/ into a checked-in
# SVG in the sibling assets/ directory. Run from the repository root after
# adding or editing a .mmd source:
#   bash scripts/gen_mermaid_svgs.sh             # every source
#   bash scripts/gen_mermaid_svgs.sh <file>...   # only the sources named
#
# The .mmd sources are the reviewable, hand-edited source of truth; the SVGs
# they produce are committed alongside them so that rendering the .adoc docs
# never depends on Mermaid/Node/a browser at build time. Requires mmdc
# (@mermaid-js/mermaid-cli) on PATH -- install with:
#   npm install -g @mermaid-js/mermaid-cli
# DOC/mermaid-config.json pins the "classic" look (mermaid-cli 11+ defaults to
# the hand-drawn "neo" look, which renders differently and several times
# larger) and wraps sequence-diagram text so long notes are not clipped.
#
# A flowchart keeps its labels as SVG text ('htmlLabels': false in the source's
# init line; HTML labels are dropped outside a browser). Mermaid writes such a
# label as one <tspan> per word and adds empty <rect/> placeholders; the script
# joins the words of a line into one <tspan> and removes the placeholders, which
# browsers draw the same and Asciidoctor PDF needs to place the text at all.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v mmdc >/dev/null 2>&1; then
  echo "error: mmdc (@mermaid-js/mermaid-cli) not found on PATH" >&2
  echo "       install with: npm install -g @mermaid-js/mermaid-cli" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  sources=("$@")
else
  sources=()
  while IFS= read -r -d '' src; do
    sources+=("$src")
  done < <(find DOC -type f -path '*/mermaid/*.mmd' -print0 | sort -z)
fi

status=0
for src in "${sources[@]}"; do
  assets_dir="$(dirname "$(dirname "$src")")/assets"
  mkdir -p "$assets_dir"
  name="$(basename "${src%.mmd}")"
  svg="$assets_dir/$name.svg"
  echo "  $src -> $svg"
  if mmdc -c DOC/mermaid-config.json -i "$src" -o "$svg.tmp.svg"; then
    sed -E \
      -e 's/<tspan [^>]*class="text-inner-tspan"[^>]*>([^<]*)<\/tspan>/\1/g' \
      -e 's/<rect\/>//g' \
      -e 's/<rect class="background" style="stroke: none"\/>//g' \
      "$svg.tmp.svg" > "$svg"
    rm -f "$svg.tmp.svg"
  else
    rm -f "$svg.tmp.svg"
    echo "error: failed to render $src" >&2
    status=1
  fi
done

exit "$status"
