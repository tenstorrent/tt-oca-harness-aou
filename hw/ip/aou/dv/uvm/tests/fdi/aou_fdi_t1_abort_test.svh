// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test, then the Adapter abandoning a bringup or a PM exit from
// L1 part-way (aou_lsm_driver::do_abort), once at every point, in random
// order, with flits between:
// - from Reset: LinkError before pl_inband_pres (status first, or pl_clk_req
//   first); LinkError with the DUT waiting for a trigger, one cycle after the
//   waking pl_clk_req, and with pl_wake_ack held back; LinkReset or Disabled
//   with pl_wake_ack held back; LinkError, LinkReset or Disabled after the DUT
//   requested Active, before the Active entry; and pl_inband_pres falling
//   again, with pl_wake_ack held back or after the Active request (UCIe r3.0
//   §10.2.3: the DUT must return lp_state_req to NOP);
// - from L1: LinkError before the pl_clk_req; LinkError, LinkReset or
//   Disabled one cycle after it, with pl_wake_ack held back, and after the
//   DUT requested Active.
// pl_clk_req always comes before a LinkReset or Disabled (UCIe r3.0 §10.2.3.2
// rule 7) and before or after a LinkError (rule 6). LinkReset or Disabled
// straight from L1 or from the DUT waiting for a trigger needs the request in
// the same cycle as the status change, so neither is sent. After a LinkError
// the DUT holds the link down until software's AOU_SW_RESET (the bringup
// test's background software), then the Adapter trains again. The bringup
// model checks every DUT output throughout; the test only provides the
// stimulus.
class aou_fdi_t1_abort_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_abort_test)

  typedef struct {
    bit             in_l1;
    aou_lsm_abort_e at;
    aou_lsm_state_e to;
    int unsigned    gap;
    bit             hold;
  } abort_t;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.req_timeout = 4000;
    // Every bringup after an abort holds pl_clk_req, so the DUT leaves
    // WAIT_PRESENCE on it (no software activation pulse is needed).
    env.lsm_cfg.clk_req_hold_bringup = 1'b1;
  endfunction

  local function abort_t mk(bit in_l1, aou_lsm_abort_e at, aou_lsm_state_e to, int unsigned gap,
                            bit hold);
    abort_t a;
    a.in_l1 = in_l1;
    a.at = at;
    a.to = to;
    a.gap = gap;
    a.hold = hold;
    return a;
  endfunction

  // LinkReset or Disabled, picked at random.
  local function aou_lsm_state_e down();
    return ($urandom_range(1) != 0) ? LSM_DISABLED : LSM_LINKRESET;
  endfunction

  task link_events();
    abort_t q[$];
    // Reset: before presence, the DUT in RESET.
    q.push_back(mk(1'b0, LSM_AB_RESET, LSM_LINKERROR, 0, 1'b0));
    q.push_back(mk(1'b0, LSM_AB_RESET, LSM_LINKERROR, $urandom_range(4, 1), 1'b0));
    // Reset with presence: WAIT_PRESENCE, WAKE_ASSERT, WAKE_WAIT_ACK.
    q.push_back(mk(1'b0, LSM_AB_WAKE, LSM_LINKERROR, 0, 1'b0));
    q.push_back(mk(1'b0, LSM_AB_WAKE, LSM_LINKERROR, 1, 1'b0));
    q.push_back(mk(1'b0, LSM_AB_WAKE, LSM_LINKERROR, $urandom_range(30, 3), 1'b1));
    q.push_back(mk(1'b0, LSM_AB_WAKE, down(), $urandom_range(30, 3), 1'b1));
    q.push_back(mk(1'b0, LSM_AB_WAKE, LSM_RESET, $urandom_range(30, 3), 1'b1));
    // Reset, the DUT requesting Active: REQ_ACTIVE.
    q.push_back(mk(1'b0, LSM_AB_REQ_ACTIVE, LSM_LINKERROR, $urandom_range(3), 1'b0));
    q.push_back(mk(1'b0, LSM_AB_REQ_ACTIVE, down(), $urandom_range(3), 1'b0));
    q.push_back(mk(1'b0, LSM_AB_REQ_ACTIVE, LSM_RESET, $urandom_range(3), 1'b0));
    // L1: L1, L1_CLK_WAKE, WAKE_WAIT_ACK, REQ_ACTIVE.
    q.push_back(mk(1'b1, LSM_AB_WAKE, LSM_LINKERROR, 0, 1'b0));
    q.push_back(mk(1'b1, LSM_AB_WAKE, LSM_LINKERROR, 1, 1'b0));
    q.push_back(mk(1'b1, LSM_AB_WAKE, down(), 1, 1'b0));
    q.push_back(mk(1'b1, LSM_AB_WAKE, LSM_LINKERROR, $urandom_range(30, 3), 1'b1));
    q.push_back(mk(1'b1, LSM_AB_WAKE, down(), $urandom_range(30, 3), 1'b1));
    q.push_back(mk(1'b1, LSM_AB_REQ_ACTIVE, LSM_LINKERROR, $urandom_range(3), 1'b0));
    q.push_back(mk(1'b1, LSM_AB_REQ_ACTIVE, down(), $urandom_range(3), 1'b0));
    q.shuffle();
    foreach (q[i]) begin
      aou_lsm_event_seq s = aou_lsm_event_seq::type_id::create("abort");
      s.ev_kind = LSM_EV_ABORT;
      s.ev_in_l1 = q[i].in_l1;
      s.ev_at = q[i].at;
      s.ev_to = q[i].to;
      s.ev_gap = q[i].gap;
      s.ev_hold_wake_ack = q[i].hold;
      `uvm_info(get_type_name(), $sformatf("abort %0d/%0d: %s at %s, to %s, gap %0d, wake_ack %s",
                i + 1, q.size(), q[i].in_l1 ? "L1" : "Reset", q[i].at.name(), q[i].to.name(),
                q[i].gap, q[i].hold ? "held" : "free"), UVM_LOW)
      s.start(env.lsm.sqr);
      wait_link_up($sformatf("abort %0d", i + 1));
      send_flits(2, 25);
    end
  endtask
endclass
