// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Active to LinkError, Reset, and a new bringup.
class aou_lsm_linkerror_seq extends aou_lsm_event_seq;
  `uvm_object_utils(aou_lsm_linkerror_seq)

  function new(string name = "aou_lsm_linkerror_seq");
    super.new(name);
    ev_kind = LSM_EV_LINKERROR;
  endfunction
endclass
