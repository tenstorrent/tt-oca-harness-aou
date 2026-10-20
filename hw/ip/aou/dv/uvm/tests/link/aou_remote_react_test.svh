// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die re-activates in the flit after its DeactivateAck
// (aou_remote_react_vseq).
class aou_remote_react_test extends aou_base_test;
  `uvm_component_utils(aou_remote_react_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_remote_react_vseq";
    num_txns = 10;
  endfunction
endclass
