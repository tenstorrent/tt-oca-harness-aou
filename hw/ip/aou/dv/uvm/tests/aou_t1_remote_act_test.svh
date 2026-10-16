// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// See aou_t1_remote_act_vseq.
class aou_t1_remote_act_test extends aou_base_test;
  `uvm_component_utils(aou_t1_remote_act_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_t1_remote_act_vseq";
  endfunction
endclass
