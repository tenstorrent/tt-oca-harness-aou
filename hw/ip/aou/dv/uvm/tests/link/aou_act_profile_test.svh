// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Profile exchange in the ActivateReq (AoU v0.8 Ch. 11): the DUT announces the
// Basic Profile (PROFILE_CFG_RPn read-only 0/0/0), PROFILE_RMT_RPn store the
// remote die's (aou_act_profile_vseq).
class aou_act_profile_test extends aou_base_test;
  `uvm_component_utils(aou_act_profile_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_act_profile_vseq";
    num_txns = 10;
  endfunction
endclass
