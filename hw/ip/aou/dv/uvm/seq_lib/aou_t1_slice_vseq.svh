// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// G1a slice: bring the link up, activate (random initiator and order), then
// random traffic in both directions, the #56 unaligned/narrow sequence and
// the #64 zero-cycle-B sequence both ways, and drain.
class aou_t1_slice_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_slice_vseq)

  function new(string name = "aou_t1_slice_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    traffic(AOU_T1_BOTH_DIRS, num_txns, aou_t1_traffic_cfg::named("rand"));
    traffic(AOU_T1_BOTH_DIRS, 0, aou_t1_traffic_cfg::named("unaligned"));
    traffic(AOU_T1_BOTH_DIRS, 32, aou_t1_traffic_cfg::named("b_zero"));
    drain();
  endtask
endclass
