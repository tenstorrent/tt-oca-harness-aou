// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Interrupt status, masks and write-1-to-clear (aou_int_vseq).
class aou_int_test extends aou_base_test;
  `uvm_component_utils(aou_int_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_int_vseq";
    num_txns = 10;
  endfunction

  // An unsolicited remote response on a lane the asymmetric RP mapping merges
  // reaches the port its ID's low bits name, through a remap table with no
  // entry for it; MAS 3.10.5 does not define the outcome, so these
  // injections keep the mapping off merged routes.
  function void configure();
    aou_int_vseq::add_regions(cfg);
    cfg.rp_map_pct = 0;
  endfunction
endclass
