// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// pl_inband_pres low for a while (meant for Reset).
class aou_lsm_inband_drop_seq extends aou_lsm_event_seq;
  `uvm_object_utils(aou_lsm_inband_drop_seq)

  function new(string name = "aou_lsm_inband_drop_seq");
    super.new(name);
    ev_kind = LSM_EV_INBAND_DROP;
  endfunction
endclass
