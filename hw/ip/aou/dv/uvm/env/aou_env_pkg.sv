// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

package aou_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import aou_axi_pkg::*;

  `uvm_analysis_imp_decl(_local_mgr)
  `uvm_analysis_imp_decl(_local_sub)
  `uvm_analysis_imp_decl(_remote)

  `include "aou_scoreboard.svh"
endpackage
