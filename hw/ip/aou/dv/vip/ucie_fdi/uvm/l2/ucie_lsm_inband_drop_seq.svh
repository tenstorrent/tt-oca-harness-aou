// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// pl_inband_pres low for a while (meant for Reset).
class ucie_lsm_inband_drop_seq extends ucie_lsm_event_seq;
  `uvm_object_utils(ucie_lsm_inband_drop_seq)

  function new(string name = "ucie_lsm_inband_drop_seq");
    super.new(name);
    ev_kind = LSM_EV_INBAND_DROP;
  endfunction
endclass
