// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reset to Active.
class ucie_lsm_bringup_seq extends ucie_lsm_event_seq;
  `uvm_object_utils(ucie_lsm_bringup_seq)

  function new(string name = "ucie_lsm_bringup_seq");
    super.new(name);
    ev_kind = LSM_EV_BRINGUP;
  endfunction
endclass
