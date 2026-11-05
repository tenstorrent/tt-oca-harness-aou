// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data-path traffic for the packing tests (aou_pack_test, +pk=), with two
// twists some modes use: `bursts` makes L3 hold its credited messages back in random windows
// while traffic runs, so they leave as dense backlogs (full flits, mixed
// types); `act_cycles` deactivates and reactivates the link between traffic
// phases, so Activation messages meet traffic and credit grants. `wreq_bursts`
// holds only the remote WriteReqs (their WriteData still goes), so each
// release sends a backlog of requests: up to 8 WriteReq starts per half flit.
class aou_pack_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_pack_vseq)

  bit          bursts;
  bit          wreq_bursts;
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
    wreq_bursts = (pk == "wreq8");
    if (pk == "act") act_cycles = 3;
  endtask

  task burst_loop();
    while (!stop_bursts) begin
      wait_cycles($urandom_range(400, 100));
      if (stop_bursts) break;
      if (wreq_bursts) cfg.l3_cfg.pol.hold_wreq_rps = '1;
      else hold_remote_tx();
      wait_cycles($urandom_range(300, 100));
      if (wreq_bursts) begin
        cfg.l3_cfg.pol.hold_wreq_rps = '0;
        env.l3.model.kick();
      end else release_remote_tx();
    end
  endtask

  task scenario();
    if (bursts || wreq_bursts) begin
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
    if (wreq_bursts) begin
      cfg.l3_cfg.pol.hold_wreq_rps = '0;
      env.l3.model.kick();
    end else release_remote_tx();
  endtask
endclass
