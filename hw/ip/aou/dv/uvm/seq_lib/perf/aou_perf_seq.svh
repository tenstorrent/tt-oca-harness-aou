// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Performance-window traffic: aou_dp_seq with every shape choice pinned, so a
// window issues exactly the pattern its target was computed for, on every seed
// and simulator. Writes and reads alternate evenly at the profile's wr_pct
// (wr_pct 50: read, write, read, ...); every burst is INCR, aligned at its
// slot, of the knobs' first length; AxSIZE is the bus width, narrowed until the
// burst fits in 4 KB; IDs cycle (DP_ID_UNIQUE); AxCACHE is modifiable so the
// DUT may split. aou_perf_test installs it in place of aou_axi_rand_seq.
class aou_perf_seq extends aou_dp_seq;
  `uvm_object_utils(aou_perf_seq)

  protected int unsigned wr_acc;

  function new(string name = "aou_perf_seq");
    super.new(name);
  endfunction

  protected virtual function void shape_txn(aou_axi_txn t, bit [63:0] base);
    int unsigned sz = p_sequencer.cfg.max_size();
    int unsigned ln = (knobs.lens.size() > 0) ? knobs.lens[0] : 15;
    bit wr;
    while (((ln + 1) << sz) > 4096 && sz > 0) sz--;
    wr_acc += wr_pct;
    wr = (wr_acc >= 100);
    if (wr) wr_acc -= 100;
    n_shape++;
    t.dir   = wr ? AOU_AXI_WR : AOU_AXI_RD;
    t.id    = pick_id();
    t.addr  = base;
    t.len   = 8'(ln);
    t.size  = 3'(sz);
    t.burst = AOU_AXI_INCR;
    t.lock  = 1'b0;
    t.cache = 4'b0010;
    t.prot  = knobs.prot;
    t.qos   = 4'd0;
    if (wr) begin
      t.fill_wdata(AOU_AXI_STRB_FULL);
      if (knobs.strb != aou_dp_knobs::DP_STRB_FULL)
        foreach (t.strb[i]) t.strb[i] &= strb_pattern(i);
    end
  endfunction
endclass
