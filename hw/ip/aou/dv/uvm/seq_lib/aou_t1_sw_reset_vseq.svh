// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AOU_SW_RESET between traffic phases: BUGS/007 interim expectation (every
// SFR and the activation state reset); the remote side recovers, activation
// runs again and traffic passes.
class aou_t1_sw_reset_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_sw_reset_vseq)

  function new(string name = "aou_t1_sw_reset_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
    sw_reset();
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
  endtask
endclass
