// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power mode: AOU_CON0.TX_LP_MODE and TX_LP_MODE_THRESHOLD (-1: unchanged).
class aou_reg_lp_mode_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_lp_mode_seq)

  int enable = 1;
  int threshold = -1;

  function new(string name = "aou_reg_lp_mode_seq");
    super.new(name);
  endfunction

  task body();
    want(rm.aou_con0.tx_lp_mode, enable);
    want(rm.aou_con0.tx_lp_mode_threshold, threshold);
    commit();
  endtask
endclass
