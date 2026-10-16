// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Activate, traffic, deactivate from a random side, re-activate, traffic,
// for n_rounds rounds.
class aou_t1_deact_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_deact_vseq)

  int unsigned n_rounds = 3;

  function new(string name = "aou_t1_deact_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    for (int unsigned i = 0; i < n_rounds; i++) begin
      activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
      traffic(AOU_T1_BOTH_DIRS, num_txns / n_rounds + 1, null);
      drain();
      case ($urandom_range(2))
        0: deactivate(AOU_T1_BY_APB);
        1: deactivate(AOU_T1_BY_REMOTE);
        default: deactivate(AOU_T1_BY_BOTH);
      endcase
    end
    activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    traffic(AOU_T1_BOTH_DIRS, num_txns / n_rounds + 1, null);
    drain();
  endtask
endclass
