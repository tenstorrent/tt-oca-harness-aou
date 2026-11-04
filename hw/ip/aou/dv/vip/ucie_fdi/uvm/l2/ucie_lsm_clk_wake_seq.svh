// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// one pl_clk_req handshake.
class ucie_lsm_clk_wake_seq extends ucie_lsm_event_seq;
  `uvm_object_utils(ucie_lsm_clk_wake_seq)

  function new(string name = "ucie_lsm_clk_wake_seq");
    super.new(name);
    ev_kind = LSM_EV_CLK_WAKE;
  endfunction
endclass
