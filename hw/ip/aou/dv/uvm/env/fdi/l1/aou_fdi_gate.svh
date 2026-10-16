// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Shared between L2 and the L1 components of one PHY. L2 opens the gate when
// the link is Active and closes it before leaving Active; L1 then stops at the
// next flit boundary in each direction and reports quiet().
class aou_fdi_gate extends uvm_object;
  `uvm_object_utils(aou_fdi_gate)

  bit open = 1'b0;     // L2: mainband may run
  bit rx_busy = 1'b0;  // PL driver is inside a flit (including its replays)
  bit tx_busy = 1'b0;  // TX responder has seen part of a DUT flit
  // L2 left Active mid-flit (LinkError, UCIe r1.1 8.3.3.7): L1 abandons the
  // flits in progress at once instead of finishing them. Cleared when the
  // gate opens again.
  bit abort = 1'b0;
  int unsigned n_abandoned;  // RX flits the PL driver abandoned on an abort
  // Bumped when the link is reset under the layers above (env reset
  // contract): a flit the PL driver fetched before is dropped, not sent.
  int unsigned epoch;

  function new(string name = "aou_fdi_gate");
    super.new(name);
  endfunction

  function bit quiet();
    return !rx_busy && !tx_busy;
  endfunction
endclass
