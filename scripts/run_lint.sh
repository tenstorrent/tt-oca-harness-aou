#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Tenstorrent USA Inc
#
# Verilator semantic lint check for AOU_TOP
# Complements scripts/run_verible_lint.sh (style/structural checks).
#
# Verilator catches elaboration-aware issues that Verible cannot:
#   - Signal width mismatches (WIDTHEXPAND / WIDTHTRUNC)
#   - Blocking assignments in sequential blocks (BLKSEQ)
#   - Latch inference (LATCH)
#   - Implicit net declarations (IMPLICIT)
#   - Incomplete case statements (CASEINCOMPLETE)
#
# Scope: AOU_TOP (the turnkey FDI bringup wrapper around AOU_CORE_TOP).
# The single-PHY parameter configuration is exercised; TWO_PHY ports are
# gated by `ifdef TWO_PHY` and excluded from this build. Two passes are run:
# the parameter defaults, and TX_NXT_PACKING_EN=1 (the registered TX packer
# output stage), so both generate arms of AOU_TX_CORE are elaborated.
#
# Usage:  bash scripts/run_lint.sh
#         (run from the repository root)
#
# Override the Verilator binary location via VERILATOR:
#   VERILATOR=/path/to/verilator bash scripts/run_lint.sh

set -euo pipefail
export AOU_CORE_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERILATOR="${VERILATOR:-verilator}"
LOG_DIR="${AOU_CORE_HOME}/logs"
mkdir -p "${LOG_DIR}"

# Verilator lint of AOU_TOP. $1: log file; $2...: extra Verilator options
# (parameter overrides). Under pipefail the pipeline's status is Verilator's;
# `|| rc=$?` keeps `set -e` from ending the script before the summary.
# Connectivity defects are bugs, not style: list them again after the (many)
# width warnings so they are not lost in the log, and fail on them even
# where the width warnings are tolerated.
lint_pass() {
    local log_file="$1"; shift
    local rc=0
    $VERILATOR \
        --lint-only \
        --timing \
        -Wall \
        -Wno-DECLFILENAME \
        -Wno-UNUSEDSIGNAL \
        -Wno-UNUSEDPARAM \
        -Wno-PINCONNECTEMPTY \
        "$@" \
        --top-module AOU_TOP \
        -f "${AOU_CORE_HOME}/RTL/filelist.f" 2>&1 | tee "${log_file}" || rc=$?

    local warnings errors connectivity
    warnings=$(grep -ci 'warning' "${log_file}" 2>/dev/null || true)
    errors=$(grep -ci 'error' "${log_file}" 2>/dev/null || true)
    connectivity=$(grep -E '^%Warning-(UNDRIVEN|IMPLICIT|MULTIDRIVEN|PINMISSING|PINNOCONNECT):' \
        "${log_file}" 2>/dev/null || true)
    echo ""
    echo "Verilator lint complete: ${errors} error(s), ${warnings} warning(s)"
    if [[ -n "${connectivity}" ]]; then
        echo "Connectivity warnings (undriven, implicit or multiply driven nets, missing pins):"
        echo "${connectivity}"
        rc=1
    fi
    echo "Full log: ${log_file}"
    return $rc
}

RC=0
echo "Verilator lint: AOU_TOP (parameter defaults)"
lint_pass "${LOG_DIR}/verilator_lint.log" || RC=$?
echo ""
echo "Verilator lint: AOU_TOP (TX_NXT_PACKING_EN=1)"
lint_pass "${LOG_DIR}/verilator_lint_nxt.log" -GTX_NXT_PACKING_EN=1 || RC=$?
exit $RC
