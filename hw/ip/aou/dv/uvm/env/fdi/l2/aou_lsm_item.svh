// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One Adapter-initiated link event for aou_lsm_driver.
class aou_lsm_item extends uvm_sequence_item;
  `uvm_object_utils(aou_lsm_item)

  rand aou_lsm_ev_e kind;
  rand int unsigned cycles;  // dwell time; 0 lets the driver pick from cfg

  // How the event ends, when not as usual (LSM_UNKNOWN: as usual):
  //   LSM_EV_RETRAIN              LinkError, LinkReset or Disabled instead of Active;
  //   LSM_EV_LINK_RESET/DISABLED  LinkError before Reset (an escalation);
  //   LSM_EV_ABORT                LinkError, LinkReset or Disabled, or Reset: the
  //                               Adapter, still in Reset, drops pl_inband_pres.
  aou_lsm_state_e to = LSM_UNKNOWN;
  // LSM_EV_ABORT only: where the bringup (or, with in_l1, the PM exit from L1)
  // is abandoned; `gap` cycles after the waking pl_clk_req (LSM_AB_WAKE; 0 sends
  // the status first and the clk_req after, which only a LinkError may do) or
  // after the DUT's Active request (LSM_AB_REQ_ACTIVE); hold_wake_ack keeps
  // pl_wake_ack low until the abort.
  aou_lsm_abort_e at = LSM_AB_RESET;
  bit             in_l1 = 1'b0;
  int unsigned    gap = 0;
  bit             hold_wake_ack = 1'b0;

  constraint c_cycles {
    kind inside {[LSM_EV_BRINGUP:LSM_EV_ABORT]};
    soft cycles == 0;
    cycles <= 100000;
  }

  function new(string name = "aou_lsm_item");
    super.new(name);
  endfunction

  function string convert2string();
    string s = $sformatf("%s cycles=%0d", kind.name(), cycles);
    if (to != LSM_UNKNOWN) s = {s, " to=", to.name()};
    if (kind == LSM_EV_ABORT)
      s = {s, $sformatf(" at=%s in_l1=%0b gap=%0d hold_wake_ack=%0b", at.name(), in_l1, gap,
                        hold_wake_ack)};
    return s;
  endfunction
endclass
