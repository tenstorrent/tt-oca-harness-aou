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
endclass
