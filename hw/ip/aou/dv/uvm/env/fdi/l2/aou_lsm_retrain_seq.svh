// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Active to Retrain and back to Active.
class aou_lsm_retrain_seq extends aou_lsm_event_seq;
  `uvm_object_utils(aou_lsm_retrain_seq)

  function new(string name = "aou_lsm_retrain_seq");
    super.new(name);
    ev_kind = LSM_EV_RETRAIN;
  endfunction
endclass
