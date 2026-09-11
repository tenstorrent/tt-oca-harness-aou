#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# (c) 2026 Tenstorrent USA Inc
#
# Render every Mermaid diagram source under DOC/**/mermaid/ into a checked-in
# SVG in the sibling assets/ directory. Run from the repository root after
# adding or editing a .mmd source:
#   bash scripts/gen_mermaid_svgs.sh
#
# The .mmd sources are the reviewable, hand-edited source of truth; the SVGs
# they produce are committed alongside them so that rendering the .adoc docs
# never depends on Mermaid/Node/a browser at build time. Requires mmdc
# (@mermaid-js/mermaid-cli) on PATH -- install with:
#   npm install -g @mermaid-js/mermaid-cli

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v mmdc >/dev/null 2>&1; then
  echo "error: mmdc (@mermaid-js/mermaid-cli) not found on PATH" >&2
  echo "       install with: npm install -g @mermaid-js/mermaid-cli" >&2
  exit 1
fi

shopt -s nullglob
status=0
while IFS= read -r -d '' mermaid_dir; do
  assets_dir="$(dirname "$mermaid_dir")/assets"
  mkdir -p "$assets_dir"
  for src in "$mermaid_dir"/*.mmd; do
    name="$(basename "${src%.mmd}")"
    svg="$assets_dir/$name.svg"
    echo "  $src -> $svg"
    if ! mmdc -i "$src" -o "$svg"; then
      echo "error: failed to render $src" >&2
      status=1
    fi
  done
done < <(find DOC -type d -name mermaid -print0 | sort -z)

exit "$status"
