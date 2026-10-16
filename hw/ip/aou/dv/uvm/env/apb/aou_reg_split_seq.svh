// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Splitter limits of one RP: AXI_SPLIT_TR_RPn.MAX_ARBURSTLEN / MAX_AWBURSTLEN
// (beats - 1; -1 leaves a field unchanged).
class aou_reg_split_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_split_seq)

  int unsigned rp = 0;
  int          max_arburstlen = -1;
  int          max_awburstlen = -1;

  function new(string name = "aou_reg_split_seq");
    super.new(name);
  endfunction

  task body();
    uvm_reg rg = rm.get_reg_by_name($sformatf("axi_split_tr_rp%0d", rp));
    want(field(rg, "max_arburstlen"), max_arburstlen);
    want(field(rg, "max_awburstlen"), max_awburstlen);
    commit();
  endtask
endclass
