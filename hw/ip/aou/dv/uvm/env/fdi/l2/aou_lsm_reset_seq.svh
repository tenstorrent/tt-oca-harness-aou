// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Active to LinkReset (Reset in the RTL encoding) and a new bringup.
class aou_lsm_reset_seq extends aou_lsm_event_seq;
  `uvm_object_utils(aou_lsm_reset_seq)

  function new(string name = "aou_lsm_reset_seq");
    super.new(name);
    ev_kind = LSM_EV_LINK_RESET;
  endfunction
endclass
