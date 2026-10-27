// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// FDI link events with AoU traffic: Adapter-initiated Retrain while traffic
// runs both ways, then L1 entry/exit and a clk_req wake on an idle link, then
// more traffic. Retrain and L1 are transparent to AOU_CORE (MAS 7.3.7): ENABLED
// and every transaction survive.
class aou_t1_link_event_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_t1_link_event_vseq)

  function new(string name = "aou_t1_link_event_vseq");
    super.new(name);
  endfunction

  task body();
    link_up();
    activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    traffic_nb(AOU_T1_BOTH_DIRS, num_txns, null);
    wait_cycles($urandom_range(2000, 200));
    link_event(LSM_EV_RETRAIN);
    wait_cycles($urandom_range(1000, 100));
    link_event(LSM_EV_RETRAIN);
    wait_traffic();
    drain();
    link_event(LSM_EV_L1_ENTRY);
    wait_cycles(200);
    link_event(LSM_EV_L1_EXIT);
    link_event(LSM_EV_CLK_WAKE);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
  endtask
endclass
