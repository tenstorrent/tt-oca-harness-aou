// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Interrupt masks (AOU_INTERRUPT_MASK); 1 masks a source, -1 leaves it unchanged.
class aou_reg_int_mask_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_int_mask_seq)

  int si0_id_mismatch = -1;
  int mi0_id_mismatch = -1;
  int early_resp = -1;
  int msgcredit_timeout = -1;
  int invalid_actmsg = -1;
  int deact_ack = -1;
  int act_ack = -1;

  function new(string name = "aou_reg_int_mask_seq");
    super.new(name);
  endfunction

  // Sets every mask to m.
  function void set_all(int m);
    si0_id_mismatch = m;
    mi0_id_mismatch = m;
    early_resp = m;
    msgcredit_timeout = m;
    invalid_actmsg = m;
    deact_ack = m;
    act_ack = m;
  endfunction

  task body();
    want(rm.aou_interrupt_mask.int_si0_id_mismatch_mask, si0_id_mismatch);
    want(rm.aou_interrupt_mask.int_mi0_id_mismatch_mask, mi0_id_mismatch);
    want(rm.aou_interrupt_mask.int_early_resp_mask, early_resp);
    want(rm.aou_interrupt_mask.int_req_linkreset_msgcredit_timeout_mask, msgcredit_timeout);
    want(rm.aou_interrupt_mask.int_req_linkreset_invalid_actmsg_mask, invalid_actmsg);
    want(rm.aou_interrupt_mask.int_req_linkreset_deact_ack_mask, deact_ack);
    want(rm.aou_interrupt_mask.int_req_linkreset_act_ack_mask, act_ack);
    commit();
  endtask
endclass
