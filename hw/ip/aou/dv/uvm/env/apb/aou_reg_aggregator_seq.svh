// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI aggregator enable of one RP (AOU_CON0.RPn_AXI_AGGREGATOR_EN).
class aou_reg_aggregator_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_aggregator_seq)

  int unsigned rp = 0;
  int          enable = 1;

  function new(string name = "aou_reg_aggregator_seq");
    super.new(name);
  endfunction

  task body();
    want(field(rm.aou_con0, $sformatf("rp%0d_axi_aggregator_en", rp)), enable);
    commit();
  endtask
endclass
