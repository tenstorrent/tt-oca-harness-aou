// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Performance-window traffic: aou_dp_seq with every shape choice pinned, so a
// window issues exactly the pattern its target was computed for, on every seed
// and simulator. Writes and reads alternate evenly at the profile's wr_pct
// (wr_pct 50: read, write, read, ...); every burst is INCR, aligned at its
// slot, of the knobs' first length; AxSIZE is the bus width (the knobs' first
// size when full_size is off), narrowed until the burst fits in 4 KB; the ID
// is the slot's index, so no two transactions in
// flight share an ID however they complete; AxCACHE is modifiable so the
// DUT may split. aou_perf_test installs it in place of aou_axi_rand_seq.
class aou_perf_seq extends aou_dp_seq;
  `uvm_object_utils(aou_perf_seq)

  protected int unsigned wr_acc;

  function new(string name = "aou_perf_seq");
    super.new(name);
  endfunction

  // A slot is busy until its transaction completes, so its index is an ID no
  // other transaction in flight holds.
  protected function bit [9:0] slot_id(bit [63:0] base);
    foreach (slot_base[k]) if (slot_base[k] == base) return 10'(k);
    `uvm_fatal(get_type_name(), $sformatf("address %0h is no slot's base", base))
    return '0;
  endfunction

  protected virtual function void shape_txn(aou_axi_txn t, bit [63:0] base);
    int unsigned sz = (!knobs.full_size && knobs.sizes.size() > 0) ?
                      knobs.sizes[0] : p_sequencer.cfg.max_size();
    int unsigned ln = (knobs.lens.size() > 0) ? knobs.lens[0] : 15;
    bit wr;
    if (sz > p_sequencer.cfg.max_size()) sz = p_sequencer.cfg.max_size();
    while (((ln + 1) << sz) > 4096 && sz > 0) sz--;
    wr_acc += wr_pct;
    wr = (wr_acc >= 100);
    if (wr) wr_acc -= 100;
    n_shape++;
    t.dir   = wr ? AOU_AXI_WR : AOU_AXI_RD;
    t.id    = slot_id(base);
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
