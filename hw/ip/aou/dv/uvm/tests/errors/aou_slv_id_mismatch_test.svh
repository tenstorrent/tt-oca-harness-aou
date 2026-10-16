// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Subordinate-side ID mismatch on every RP (aou_slv_id_mismatch_vseq). No
// traffic: only unsolicited responses from the remote die.
class aou_slv_id_mismatch_test extends aou_base_test;
  `uvm_component_utils(aou_slv_id_mismatch_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_slv_id_mismatch_vseq";
    min_l2r = 0;
    min_r2l = 0;
  endfunction
endclass
