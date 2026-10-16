#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

# Create a new, unique run directory and print its path:
#   <out>/<test>.rid.<rid>.seed.<seed>.time.<YYYY.MM.DD-HH.MM.SS>.uid.<uid>
# The layout matches ttem's, so its tools can parse our run names. mkdir is
# atomic, so concurrent runs of the same test and seed never share a directory.
set -euo pipefail
out=$1 test=$2 rid=$3 seed=$4
mkdir -p "$out"
for _ in 1 2 3 4 5 6 7 8; do
  ts=$(date +%Y.%m.%d-%H.%M.%S)
  uid=$(date +%s%N | cut -c9-)$$
  dir="$out/$test.rid.$rid.seed.$seed.time.$ts.uid.$uid"
  if mkdir "$dir" 2>/dev/null; then
    echo "$dir"
    exit 0
  fi
done
echo "new_run_dir: could not create a unique run directory under $out" >&2
exit 1
