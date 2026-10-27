// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Sends one link event; the named subclasses fix `ev_kind`. The ev_to,
// ev_at, ev_in_l1, ev_gap and ev_hold_wake_ack fields go to the item's
// to, at, in_l1, gap and hold_wake_ack (aou_lsm_item).
class aou_lsm_event_seq extends uvm_sequence #(aou_lsm_item);
  `uvm_object_utils(aou_lsm_event_seq)

  aou_lsm_ev_e    ev_kind = LSM_EV_IDLE;
  int unsigned    ev_cycles;   // dwell; 0 lets the driver pick
  aou_lsm_state_e ev_to = LSM_UNKNOWN;
  aou_lsm_abort_e ev_at = LSM_AB_RESET;
  bit             ev_in_l1 = 1'b0;
  int unsigned    ev_gap = 0;
  bit             ev_hold_wake_ack = 1'b0;

  function new(string name = "aou_lsm_event_seq");
    super.new(name);
  endfunction

  task body();
    aou_lsm_item it = aou_lsm_item::type_id::create("ev");
    start_item(it);
    `AOU_RANDOMIZE_WITH(it, { kind == ev_kind; cycles == ev_cycles; })
    it.to = ev_to;
    it.at = ev_at;
    it.in_l1 = ev_in_l1;
    it.gap = ev_gap;
    it.hold_wake_ack = ev_hold_wake_ack;
    finish_item(it);
  endtask
endclass
