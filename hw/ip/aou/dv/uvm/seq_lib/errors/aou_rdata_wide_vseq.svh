// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// ReadData wider than the DUT's AXI width (plan 9.21). The MAS overview calls
// read data that exceeds the requester's AXI data width a violation and gives
// no reaction. Interim expectation (BUGS/051): the
// violating read still completes on the local S port with ARLEN+1 beats, the
// requested bytes (the remote die repeats them across the 1024-bit beat, so
// any lane choice is right) and OKAY, and the DUT goes on working: ordinary
// traffic both ways afterwards, no interrupt, no LinkReset. The always-on
// checkers judge all of it (scoreboard, AXI monitors, interrupt watcher,
// T1-T01 at the end); a DUT that never answers ends at the phase time-out.
// The remote die answers the first +wide_n=N (default 4) reads of each RP
// narrower than 1024 bits with ReadData1024; the reads are single and short
// bursts of the full RP width.
class aou_rdata_wide_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_rdata_wide_vseq)

  static const bit [63:0] WIDE_BASE = 64'h0000_0064_0000_0000;

  function new(string name = "aou_rdata_wide_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned n = arg_int("wide_n", 4);
    int unsigned n_rp_wide = 0;
    link_up();
    sw_activate();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (cfg.rp_bytes[r] >= 128) continue;
      n_rp_wide++;
      cfg.l3_cfg.rdata_wide[cfg.l3_cfg.dest_rp[r]] = n;
    end
    if (n_rp_wide == 0)
      `uvm_fatal(get_type_name(), "needs an RP narrower than 1024 bits")
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      fork
        automatic int unsigned rr = r;
        if (cfg.rp_bytes[rr] < 128) wide_reads(rr, n);
      join_none
    end
    wait fork;
    `uvm_info(get_type_name(), $sformatf("%0d reads answered with ReadData1024 on %0d RPs",
                                         cfg.l3_cfg.n_rdata_wide, n_rp_wide), UVM_LOW)
    check_traffic(num_txns);
    sw_deactivate();
  endtask

  task wide_reads(int unsigned rp, int unsigned n);
    aou_txn_list_seq s = aou_txn_list_seq::type_id::create("wide_rd");
    for (int unsigned i = 0; i < n; i++)
      s.items.push_back(mk(1'b0, rp, AOU_AXI_RD, 10'h070 + 10'(i),
                           WIDE_BASE + 64'(rp) * 64'h100_0000 + 64'(i) * 64'h400, i % 4));
    run(s, 1'b0, rp);
  endtask
endclass
