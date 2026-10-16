// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Ack and MsgCredit time-outs, LinkReset and recovery (aou_linkreset_timeout_vseq).
class aou_linkreset_timeout_test extends aou_base_test;
  `uvm_component_utils(aou_linkreset_timeout_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_linkreset_timeout_vseq";
    num_txns = 10;
  endfunction
endclass
