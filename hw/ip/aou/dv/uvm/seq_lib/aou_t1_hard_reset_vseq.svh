// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// I_RESETN/I_PRESETN mid-test on a quiet link: the env flushes, the link and
// activation come back, and traffic passes again.
class aou_t1_hard_reset_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_hard_reset_vseq)

  function new(string name = "aou_t1_hard_reset_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    for (int i = 0; i < 3; i++) begin
      traffic(AOU_T1_BOTH_DIRS, num_txns / 4 + 1, null);
      drain();
      hard_reset(i == 1 ? AOU_T1_RST_CORE : AOU_T1_RST_BOTH);
    end
    traffic(AOU_T1_BOTH_DIRS, num_txns / 4 + 1, null);
    drain();
  endtask
endclass
