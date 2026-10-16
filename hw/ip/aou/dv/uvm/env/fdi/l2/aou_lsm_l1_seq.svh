// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L1 entry (stallreq/ack first), `cycles` in L1, then a remote-initiated exit.
class aou_lsm_l1_seq extends aou_lsm_event_seq;
  `uvm_object_utils(aou_lsm_l1_seq)

  function new(string name = "aou_lsm_l1_seq");
    super.new(name);
    ev_kind = LSM_EV_L1_ENTRY;
  endfunction

  task body();
    aou_lsm_ev_e evs[3] = '{LSM_EV_L1_ENTRY, LSM_EV_IDLE, LSM_EV_L1_EXIT};
    foreach (evs[i]) begin
      aou_lsm_item it = aou_lsm_item::type_id::create("ev");
      start_item(it);
      `AOU_RANDOMIZE_WITH(it, { kind == evs[i]; cycles == ev_cycles; })
      finish_item(it);
    end
  endtask
endclass
