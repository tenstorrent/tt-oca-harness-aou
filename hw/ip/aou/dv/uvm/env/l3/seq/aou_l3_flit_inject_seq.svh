// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Injection on the next flit built: invert MsgStart[flip_start] (AOU-R4/R5),
// a wrong FDId (AOU-R9), or a raw MsgCredit value (an RP out of range is
// AOU-R14; credit in DISABLED is AOU-R26). Fields left at -1 do nothing.
class aou_l3_flit_inject_seq extends aou_l3_base_seq;
  `uvm_object_utils(aou_l3_flit_inject_seq)

  int flip_start = -1;
  int fdid = -1;
  int msg_credit = -1;

  function new(string name = "aou_l3_flit_inject_seq");
    super.new(name);
  endfunction

  task body();
    aou_packer pk = p_sequencer.model.pk;
    pk.inj_flip_start = flip_start;
    pk.inj_fdid = fdid;
    pk.inj_msg_credit = msg_credit;
    p_sequencer.model.kick();
  endtask
endclass
