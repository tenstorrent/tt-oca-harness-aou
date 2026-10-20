#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

# Elaborate AOU_FDI_CHECKER (Verilator, lint only) with each configuration it is
# meant to refuse, and require both the refusal and its diagnostic, so a guard
# that stops firing fails make lint. Logs go to build/lint/checker_elaboration/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERILATOR="${VERILATOR:-verilator}"
CHK="$HERE/uvm/env/checker"
SOURCES=("$CHK/aou_fdi_wire_pkg.sv" "$CHK/aou_fdi_checker_pkg.sv" "$CHK/AOU_FDI_CHECKER.sv")
LOG_DIR="$HERE/build/lint/checker_elaboration"
mkdir -p "$LOG_DIR"

run_rejected() {
  local name="$1" expected="$2"
  shift 2
  local log="$LOG_DIR/$name.log"
  if "$VERILATOR" --lint-only --timing -sv \
      -Wno-ASCRANGE -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET \
      -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
      --top-module AOU_FDI_CHECKER "${SOURCES[@]}" "$@" >"$log" 2>&1; then
    echo "ERROR: $name elaborated successfully" >&2
    return 1
  fi
  if ! grep -Fq "$expected" "$log"; then
    cat "$log"
    echo "ERROR: $name failed without the expected diagnostic: $expected" >&2
    return 1
  fi
  echo "PASS: $name"
}

run_rejected unsupported_fdi "unsupported FDI_IF_BYTES" -GFDI_IF_BYTES=48
run_rejected unknown_profile "is not a posture" -GCHK_PROFILE=99
run_rejected no_checks "every rule group is disabled" \
  -GSTRUCT_EN=0 -GFRAMING_EN=0 -GACT_SEQ_EN=0 -GMSG_ORDER_EN=0 -GCREDIT_EN=0
run_rejected no_stream "neither flit stream is observed" -GOBS_LP_EN=0 -GOBS_PL_EN=0
run_rejected incompatible_one_stream "one stream" -GOBS_PL_EN=0
run_rejected zero_width "must be at least 1" -GVIOL_CNT_WD=0
run_rejected zero_capacity "must hold at least 1 credit" -GCRD_CAPACITY=0
run_rejected rp_count_range "1..4" -GRP_COUNT=5
run_rejected fdid_range "FDId field is two bits" -GFDID=4
run_rejected enable_not_boolean "is not 0 or 1" -GCREDIT_EN=2

echo "Checker elaboration guards PASS"
