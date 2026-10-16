// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Orphan responses on the M ports after AOU_SW_RESET (T1-L26, BUGS/024).
// The software reset leaves the AXI ports alone, so an R or B beat the local
// subordinate presented before it stays presented (AXI4 A3.2.1), while the
// DUT's pending-transaction state is gone: no later event can make the DUT
// want that beat. Interim expectation (BUGS/024): the DUT accepts it (and may
// flag the ID mismatch) within `bound` cycles of the reset. A beat presented
// since before an AOU_SW_RESET and still not accepted `bound` cycles after it,
// or at the end of the test, is reported once. A reset of the bus itself
// (I_RESETN) withdraws the beat and ends the watch.
class aou_t1_orphan_chk extends uvm_component;
  `uvm_component_utils(aou_t1_orphan_chk)

  aou_axi_vif_t vif[];
  int unsigned  bound = 5000;
  int unsigned  reports;

  protected longint unsigned cycle;
  protected longint unsigned sw_reset_cycle;
  protected int unsigned     sw_resets;
  // Per port and channel (0 R, 1 B): a held beat that an AOU_SW_RESET caught.
  protected bit              caught[][2];
  protected bit              done[][2];
  protected bit              was_held[][2];
  protected bit [9:0]        held_id[][2];
  protected time             held_since[][2];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void note_sw_reset();
    sw_resets++;
    sw_reset_cycle = cycle;
    foreach (vif[r]) begin
      if (vif[r] == null) continue;
      caught[r][0] = vif[r].mon_cb.rvalid === 1'b1 && vif[r].mon_cb.rready !== 1'b1;
      caught[r][1] = vif[r].mon_cb.bvalid === 1'b1 && vif[r].mon_cb.bready !== 1'b1;
    end
  endfunction

  task run_phase(uvm_phase phase);
    caught = new[vif.size()];
    done = new[vif.size()];
    was_held = new[vif.size()];
    held_id = new[vif.size()];
    held_since = new[vif.size()];
    if (vif.size() == 0) return;
    fork
      forever begin
        @(vif[0].mon_cb);
        cycle++;
      end
    join_none
    foreach (vif[r]) begin
      automatic int unsigned rr = r;
      fork
        watch(rr);
      join_none
    end
  endtask

  protected task watch(int unsigned r);
    forever begin
      bit held[2];
      @(vif[r].mon_cb);
      held[0] = vif[r].mon_cb.rvalid === 1'b1 && vif[r].mon_cb.rready !== 1'b1;
      held[1] = vif[r].mon_cb.bvalid === 1'b1 && vif[r].mon_cb.bready !== 1'b1;
      for (int c = 0; c < 2; c++) begin
        if (!held[c] || vif[r].mon_cb.resetn !== 1'b1) begin
          caught[r][c] = 1'b0;
          done[r][c] = 1'b0;
          was_held[r][c] = 1'b0;
          continue;
        end
        if (!was_held[r][c]) begin
          was_held[r][c] = 1'b1;
          held_since[r][c] = $time;
          held_id[r][c] = (c == 0) ? vif[r].mon_cb.rid : vif[r].mon_cb.bid;
        end
        if (caught[r][c] && !done[r][c] && cycle - sw_reset_cycle >= 64'(bound)) begin
          done[r][c] = 1'b1;
          flag(r, c, $sformatf("%0d cycles after AOU_SW_RESET", cycle - sw_reset_cycle));
        end
      end
    end
  endtask

  protected function void flag(int unsigned r, int c, string when);
    reports++;
    `uvm_error(get_type_name(), $sformatf({"T1-L26: orphan %s beat on m_axi%0d, ID %0h, presented ",
                                           "since %0t, still held with %s low %s (BUGS/024 ",
                                           "interim)"},
                                          c == 0 ? "R" : "B", r, held_id[r][c], held_since[r][c],
                                          c == 0 ? "RREADY" : "BREADY", when))
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (caught[r, c])
      if (caught[r][c] && !done[r][c]) begin
        done[r][c] = 1'b1;
        flag(r, c, "at end of test");
      end
  endfunction
endclass
