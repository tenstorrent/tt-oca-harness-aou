// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Sends one link event of kind `ev_kind` (of() makes one). The ev_to,
// ev_at, ev_in_l1, ev_gap and ev_hold_wake_ack fields go to the item's
// to, at, in_l1, gap and hold_wake_ack (ucie_lsm_item).
class ucie_lsm_event_seq extends uvm_sequence #(ucie_lsm_item);
  `uvm_object_utils(ucie_lsm_event_seq)

  ucie_lsm_ev_e    ev_kind = LSM_EV_IDLE;
  int unsigned    ev_cycles;   // dwell; 0 lets the driver pick
  ucie_lsm_state_e ev_to = LSM_UNKNOWN;
  ucie_lsm_abort_e ev_at = LSM_AB_RESET;
  bit             ev_in_l1 = 1'b0;
  int unsigned    ev_gap = 0;
  bit             ev_hold_wake_ack = 1'b0;

  function new(string name = "ucie_lsm_event_seq");
    super.new(name);
  endfunction

  // An event sequence of the given kind, e.g. of(LSM_EV_RETRAIN).start(sqr).
  static function ucie_lsm_event_seq of(ucie_lsm_ev_e kind, string name = "ev");
    ucie_lsm_event_seq s = ucie_lsm_event_seq::type_id::create(name);
    s.ev_kind = kind;
    return s;
  endfunction

  task body();
    ucie_lsm_item it = ucie_lsm_item::type_id::create("ev");
    start_item(it);
    `UCIE_RANDOMIZE_WITH(it, { kind == ev_kind; cycles == ev_cycles; })
    it.to = ev_to;
    it.at = ev_at;
    it.in_l1 = ev_in_l1;
    it.gap = ev_gap;
    it.hold_wake_ack = ev_hold_wake_ack;
    finish_item(it);
  endtask
endclass
