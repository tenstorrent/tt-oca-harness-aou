// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Functional coverage service: per-bin hit counts of every testbench
// covergroup, kept apart from the simulator's covergroup engine and written to
// <run>/fc.json, which scripts/fc_report.py union-merges across passing runs.
// Below every layer, so any layer can feed it.
package aou_fc_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "aou_fc_point.svh"
  `include "aou_fc_group.svh"
  `include "aou_fc_db.svh"
endpackage
