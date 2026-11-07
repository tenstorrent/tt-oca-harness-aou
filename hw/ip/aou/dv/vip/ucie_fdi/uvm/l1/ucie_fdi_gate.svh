// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Shared between L2 and the L1 components of one PHY. L2 opens the gate when
// the link is Active and closes it before leaving Active; L1 then stops at the
// next flit boundary in each direction, finishes a stall handshake under way,
// and reports quiet().
class ucie_fdi_gate extends uvm_object;
  `uvm_object_utils(ucie_fdi_gate)

  bit open = 1'b0;     // L2: mainband may run
  // L2: only the RX mainband may run, before Active (pl_state_sts still Reset
  // after the rx_active handshake, UCIe r3.0 §10.2.7 rule 3; +fdi_rx_early).
  bit rx_early = 1'b0;
  bit rx_busy = 1'b0;  // PL driver is inside a flit (including its replays)
  bit tx_busy = 1'b0;  // TX responder has seen part of a DUT flit (set_tx_busy)
  // TX responder: a stall handshake is under way, from pl_stallreq rising
  // until lp_stallack has fallen again (all four phases, UCIe r3.0 §10.3.2
  // rule 9).
  bit stall_busy = 1'b0;
  // L2 leaves Active for LinkError without waiting for a stall handshake under
  // way (r3.0 §10.3.3.7: "It is not required to complete the stallreq/ack
  // handshake before entering this state"): the TX responder then raises
  // pl_trdy only to finish a started flit, stall or not, and the handshake
  // runs on in LinkError. Cleared when the gate opens again.
  bit stall_cut = 1'b0;
  local realtime tx_done_t = -1.0;  // when tx_busy last fell
  // L2 left Active mid-flit (LinkError, UCIe r3.0 §10.3.3.7): L1 abandons the
  // flits in progress at once instead of finishing them. Cleared when the
  // gate opens again.
  bit abort = 1'b0;
  int unsigned n_abandoned;  // RX flits the PL driver abandoned on an abort
  // L1: a framing error was flagged on pl_error; L2 retrains the link. L2
  // clears it whenever it closes the gate.
  bit retrain_req = 1'b0;
  // Bumped when the link is reset under the layers above (env reset
  // contract): a flit the PL driver fetched before is dropped, not sent.
  int unsigned epoch;

  function new(string name = "ucie_fdi_gate");
    super.new(name);
  endfunction

  // The PL driver may start an RX flit.
  function bit rx_open();
    return open || rx_early;
  endfunction

  // The TX responder updates tx_busy on every clock edge. It falls on the edge
  // of a flit's last transfer, and on that same edge the Protocol Layer may
  // legally raise lp_valid for its next flit. quiet() stays false until the
  // following edge, so L2 never changes pl_state_sts on the edge of the last
  // transfer, whichever order the simulator runs the two processes in.
  function void set_tx_busy(bit b);
    if (tx_busy && !b) tx_done_t = $realtime;
    tx_busy = b;
  endfunction

  // No flit in progress either way: with stall_cut set, L2 may enter
  // LinkError.
  function bit at_boundary();
    return !rx_busy && !tx_busy && tx_done_t != $realtime;
  endfunction

  // At a flit boundary and no stall handshake under way: L2 may change
  // pl_state_sts. A stand-alone stall the gate's closing caught is completed
  // first, so pl_trdy, which the handshake raises, is low again before the
  // status leaves Active (r3.0 Table 10-3 pl_trdy; §10.3.2 rule 3 forbids
  // cutting the handshake short).
  function bit quiet();
    return at_boundary() && !stall_busy;
  endfunction
endclass
