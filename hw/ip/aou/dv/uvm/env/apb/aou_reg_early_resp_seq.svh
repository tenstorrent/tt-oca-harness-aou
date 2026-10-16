// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Early write response enable of one RP (WRITE_EARLY_RESPONSE_RPn.EARLY_BRESP_EN).
class aou_reg_early_resp_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_early_resp_seq)

  int unsigned rp = 0;
  int          enable = 1;

  function new(string name = "aou_reg_early_resp_seq");
    super.new(name);
  endfunction

  task body();
    uvm_reg rg = rm.get_reg_by_name($sformatf("write_early_response_rp%0d", rp));
    want(field(rg, "early_bresp_en"), enable);
    commit();
  endtask
endclass
