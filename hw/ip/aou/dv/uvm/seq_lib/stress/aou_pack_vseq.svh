// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data-path traffic for the packing tests (aou_pack_test, +pk=), with two
// twists some modes use: `bursts` makes L3 hold its credited messages back in random windows
// while traffic runs, so they leave as dense backlogs (full flits, mixed
// types); `act_cycles` deactivates and reactivates the link between traffic
// phases, so Activation messages meet traffic and credit grants.
class aou_pack_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_pack_vseq)

  bit          bursts;
  int unsigned act_cycles;
  protected bit stop_bursts;

  function new(string name = "aou_pack_vseq");
    super.new(name);
  endfunction

  task pre_body();
    string pk = "crossflit";
    super.pre_body();
    void'($value$plusargs("pk=%s", pk));
    bursts = pk inside {"mixed", "full", "wresp48"};
    if (pk == "act") act_cycles = 3;
  endtask

  task burst_loop();
    while (!stop_bursts) begin
      wait_cycles($urandom_range(400, 100));
      if (stop_bursts) break;
      hold_remote_tx();
      wait_cycles($urandom_range(300, 100));
      release_remote_tx();
    end
  endtask

  task scenario();
    if (bursts) begin
      stop_bursts = 1'b0;
      fork
        burst_loop();
      join_none
    end
    for (int unsigned i = 0; i <= act_cycles; i++) begin
      if (i > 0) begin
        deactivate(($urandom_range(1) == 1) ? AOU_T1_BY_APB : AOU_T1_BY_REMOTE);
        activate(($urandom_range(1) == 1) ? AOU_T1_BY_APB : AOU_T1_BY_BOTH, AOU_T1_ORDER_RANDOM);
      end
      super.scenario();
    end
    stop_bursts = 1'b1;
    release_remote_tx();
  endtask
endclass
