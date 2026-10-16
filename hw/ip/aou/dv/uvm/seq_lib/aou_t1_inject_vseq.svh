// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3 error injection through the expectation registry: after traffic, the
// remote die sends a CrdtGrant with RsvdZero bits set (AOU-R11) and then a
// message with a reserved MSGTYPE (AOU-R3); the checkers must flag both. The DUT's reaction is unspecified (BUGS/012):
// INT_REQ_LINKRESET is allowed, nothing else.
class aou_t1_inject_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_inject_vseq)

  function new(string name = "aou_t1_inject_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
    expect_event("AOU-R11", 1, 0);
    expect_event("AOU-R3", 1, 0);
    expect_event("INT_REQ_LINKRESET", 0, 0);
    inject("rsvd", 1);
    wait_cycles(500);
    inject("bad_type", 0);
    wait_cycles(2000);
  endtask
endclass
