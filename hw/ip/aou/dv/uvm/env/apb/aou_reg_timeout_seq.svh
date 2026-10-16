// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link time-outs: LP_LINKRESET.MSGCREDIT_TIME_OUT_VALUE and ACK_TIME_OUT_VALUE,
// AOU_INIT.DEACTIVATE_TIME_OUT_VALUE (-1: unchanged).
class aou_reg_timeout_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_timeout_seq)

  int msgcredit = -1;
  int ack = -1;
  int deactivate = -1;

  function new(string name = "aou_reg_timeout_seq");
    super.new(name);
  endfunction

  task body();
    want(rm.lp_linkreset.msgcredit_time_out_value, msgcredit);
    want(rm.lp_linkreset.ack_time_out_value, ack);
    want(rm.aou_init.deactivate_time_out_value, deactivate);
    commit();
  endtask
endclass
