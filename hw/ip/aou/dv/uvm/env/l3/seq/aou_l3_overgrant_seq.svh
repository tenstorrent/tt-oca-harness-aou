// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Advertise n credits the modelled RX buffer does not have, on one RP and
// class. Legal on the wire (the DUT's counter saturates, 6.4); it tests
// saturation and how the DUT uses the extra credit.
class aou_l3_overgrant_seq extends aou_l3_base_seq;
  `uvm_object_utils(aou_l3_overgrant_seq)

  aou_cred_class_e cls = AOU_CC_WREQ;
  int unsigned     n = 128;

  function new(string name = "aou_l3_overgrant_seq");
    super.new(name);
  endfunction

  task body();
    p_sequencer.model.crd.inject_overgrant(int'(rp), cls, n);
    p_sequencer.model.kick();
  endtask
endclass
