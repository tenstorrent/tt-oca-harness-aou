// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI ID mismatch on the M and S ports, every RP (aou_id_mismatch_vseq).
class aou_id_mismatch_test extends aou_base_test;
  `uvm_component_utils(aou_id_mismatch_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_id_mismatch_vseq";
    num_txns = 10;
  endfunction

  // An unsolicited remote response on a lane the asymmetric RP mapping merges
  // reaches the port its ID's low bits name, through a remap table with no
  // entry for it; MAS 3.10.5 does not define the outcome, so these
  // injections keep the mapping off merged routes.
  function void configure();
    cfg.rp_map_pct = 0;
  endfunction
endclass
