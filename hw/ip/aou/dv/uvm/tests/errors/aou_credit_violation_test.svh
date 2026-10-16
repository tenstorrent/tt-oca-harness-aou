// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// ReadReqs beyond the DUT's advertised credit (aou_credit_violation_vseq).
class aou_credit_violation_test extends aou_base_test;
  `uvm_component_utils(aou_credit_violation_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_credit_violation_vseq";
    num_txns = 10;
  endfunction

  // The injected reads must all be in flight at once.
  function void configure();
    cfg.r_mgr_cfg[0].max_rd_outstanding = 512;
  endfunction
endclass
