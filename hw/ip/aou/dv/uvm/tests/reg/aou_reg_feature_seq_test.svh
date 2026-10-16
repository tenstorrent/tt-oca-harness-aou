// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Every feature-programming sequence programs the fields it names
// (see aou_reg_feature_vseq).
class aou_reg_feature_seq_test extends aou_reg_base_test;
  `uvm_component_utils(aou_reg_feature_seq_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_body();
    aou_reg_feature_vseq s = aou_reg_feature_vseq::type_id::create("features");
    prep(s);
    s.start(null);
  endtask
endclass
