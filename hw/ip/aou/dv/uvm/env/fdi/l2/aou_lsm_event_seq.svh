// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Sends one link event; the named subclasses fix `ev_kind`.
class aou_lsm_event_seq extends uvm_sequence #(aou_lsm_item);
  `uvm_object_utils(aou_lsm_event_seq)

  aou_lsm_ev_e ev_kind = LSM_EV_IDLE;
  int unsigned ev_cycles;   // dwell; 0 lets the driver pick

  function new(string name = "aou_lsm_event_seq");
    super.new(name);
  endfunction

  task body();
    aou_lsm_item it = aou_lsm_item::type_id::create("ev");
    start_item(it);
    `AOU_RANDOMIZE_WITH(it, { kind == ev_kind; cycles == ev_cycles; })
    finish_item(it);
  endtask
endclass
