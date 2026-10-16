// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// aou_link_act_deact_vseq with every deactivation forced through
// AOU_CON0.DEACTIVATE_FORCE (plan 2.7). The DUT then sends DeactivateReq
// with PropertyReq=1, which the spec does not allow (BUGS/010).
class aou_link_force_deact_vseq extends aou_link_act_deact_vseq;
  `uvm_object_utils(aou_link_force_deact_vseq)

  function new(string name = "aou_link_force_deact_vseq");
    super.new(name);
    force_dflt = 1'b1;
  endfunction
endclass
