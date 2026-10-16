// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AOU_INIT deactivation controls: the DEACTIVATE_TIME_OUT_VALUE gate and
// INT_DEACTIVATE_PROPERTY (aou_deact_ctrl_vseq, +mode=tov|property).
class aou_deact_ctrl_test extends aou_base_test;
  `uvm_component_utils(aou_deact_ctrl_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_deact_ctrl_vseq";
    num_txns = 8;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
