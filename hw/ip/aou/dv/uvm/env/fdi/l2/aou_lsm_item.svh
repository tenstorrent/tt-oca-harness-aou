// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One Adapter-initiated link event for aou_lsm_driver.
class aou_lsm_item extends uvm_sequence_item;
  `uvm_object_utils(aou_lsm_item)

  rand aou_lsm_ev_e kind;
  rand int unsigned cycles;  // dwell time; 0 lets the driver pick from cfg

  constraint c_cycles {
    kind inside {[LSM_EV_BRINGUP:LSM_EV_DISABLED]};
    soft cycles == 0;
    cycles <= 100000;
  }

  function new(string name = "aou_lsm_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s cycles=%0d", kind.name(), cycles);
  endfunction
endclass
