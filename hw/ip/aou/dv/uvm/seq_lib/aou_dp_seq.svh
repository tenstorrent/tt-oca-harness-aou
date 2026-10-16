// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Directed-random data-path traffic shaped by aou_dp_knobs. Tests install it
// as a factory override of aou_axi_rand_seq, so the env's traffic() runs it on
// any manager (local S port or remote die) with the profile's count, window,
// ID limit and length limit. Like its parent, every in-flight transaction owns
// its own 4KB slot. INCR only: the AoU wire has no AxBURST (spec 2.5).
class aou_dp_seq extends aou_axi_rand_seq;
  `uvm_object_utils(aou_dp_seq)

  aou_dp_knobs knobs;

  protected int unsigned n_shape;
  protected bit [9:0]    next_id;
  protected int unsigned n_attr[2] = '{0, 0};   // attr_sweep steps: writes, reads

  // AXI4 A4.4 Table A4-5: the AxCACHE encodings that are not reserved.
  static const bit [3:0] LEGAL_CACHE[10] = '{4'h0, 4'h1, 4'h2, 4'h3, 4'h6, 4'h7, 4'hA, 4'hB,
                                              4'hE, 4'hF};

  function new(string name = "aou_dp_seq");
    super.new(name);
  endfunction

  task body();
    aou_axi_txn wr_q[$];
    aou_axi_txn t;
    int unsigned bsz;
    get_knobs();
    pick_slots();
    bsz = (knobs.batch == 0) ? num_slots : knobs.batch;
    if (bsz > num_slots) bsz = num_slots;
    `uvm_info(get_type_name(), $sformatf("%0d txns on %s: %s", num_txns,
                                         p_sequencer.get_full_name(), knobs.convert2string()),
              UVM_MEDIUM)
    for (int unsigned n = 0; n < num_txns; ) begin
      wr_q.delete();
      for (int unsigned b = 0; b < bsz && n < num_txns; b++, n++) begin
        int slot;
        slot_sem.get(1);
        slot = free_slot();
        slot_busy[slot] = 1'b1;
        t = new_txn($sformatf("dp%0d", n));
        shape_txn(t, slot_base[slot]);
        send(t);
        if (knobs.loopback && t.dir == AOU_AXI_WR) wr_q.push_back(t);
      end
      if (knobs.batch != 0 || knobs.loopback) wait_all();
      // Read back what the batch wrote, from the same slots.
      foreach (wr_q[i]) begin
        aou_axi_txn r = new_txn($sformatf("dp_rb%0d", i));
        r.copy(wr_q[i]);
        r.set_name($sformatf("dp_rb%0d", i));
        r.dir = AOU_AXI_RD;
        r.data.delete();
        r.strb.delete();
        r.rresp.delete();
        slot_sem.get(1);
        mark_busy(r.addr);
        send(r);
      end
      if (wr_q.size() > 0) wait_all();
    end
    wait_all();
  endtask

  protected function void get_knobs();
    if (knobs == null && !uvm_config_db#(aou_dp_knobs)::get(null, "*", "dp_knobs", knobs)) begin
      knobs = aou_dp_knobs::type_id::create("knobs");
      knobs.apply_plusargs();
    end
  endfunction

  protected function void mark_busy(bit [63:0] a);
    foreach (slot_base[k]) if (slot_base[k] == {a[63:12], 12'h000}) slot_busy[k] = 1'b1;
  endfunction

  protected function int unsigned pick(int unsigned q[$], int unsigned lo, int unsigned hi);
    int unsigned c[$];
    foreach (q[i]) if (q[i] >= lo && q[i] <= hi) c.push_back(q[i]);
    if (c.size() == 0) return $urandom_range(hi, lo);
    // Cycle through the list so short runs still cover every listed value.
    return c[n_shape % c.size()];
  endfunction

  protected function bit [127:0] strb_pattern(int unsigned beat);
    bit [127:0] p;
    bit [7:0] pats[6] = '{8'h55, 8'hAA, 8'h0F, 8'hF0, 8'h3C, 8'h81};
    case (knobs.strb)
      aou_dp_knobs::DP_STRB_PARTIAL: begin
        bit [7:0] b = pats[(n_shape + beat) % 6];
        for (int unsigned k = 0; k < 16; k++) p[8*k +: 8] = b;
      end
      aou_dp_knobs::DP_STRB_SPARSE: begin
        p = '0;
        p[$urandom_range(127)] = 1'b1;
        p[$urandom_range(127)] = 1'b1;
      end
      default: p = '0;
    endcase
    return p;
  endfunction

  protected function bit [9:0] pick_id();
    case (knobs.ids)
      aou_dp_knobs::DP_ID_SAME:   return knobs.id_value;
      aou_dp_knobs::DP_ID_UNIQUE: begin
        next_id = (int'(next_id) >= int'(knobs.max_id)) ? 10'd0 : next_id + 10'd1;
        return next_id;
      end
      aou_dp_knobs::DP_ID_HIGH:   return 10'($urandom_range(10'h3FF, 10'h3F0));
      default: begin
        int unsigned hi = (knobs.max_id < 32'(max_id)) ? knobs.max_id : 32'(max_id);
        return 10'($urandom_range(hi));
      end
    endcase
  endfunction

  protected virtual function void shape_txn(aou_axi_txn t, bit [63:0] base);
    int unsigned msz = p_sequencer.cfg.max_size();
    int unsigned sz;
    int unsigned ln;
    int unsigned nb;
    int unsigned bytes;
    int unsigned off;
    bit wr = knobs.attr_sweep ? (n_shape % 2 == 0) : ($urandom_range(99) < wr_pct);
    sz = knobs.full_size ? msz : pick(knobs.sizes, 0, msz);
    ln = pick(knobs.lens, 0, (knobs.lens.size() > 0) ? 255 : int'(max_len));
    n_shape++;
    nb = 1 << sz;
    // Keep the burst inside the 4KB slot.
    if ((ln + 1) * nb > 4096) ln = 4096 / nb - 1;
    bytes = (ln + 1) * nb;
    // Aligned start: a multiple of the size anywhere the burst fits.
    off = nb * $urandom_range((4096 - bytes) / nb);
    if (knobs.align == aou_dp_knobs::DP_ALIGN_UNALIGNED && sz > 0)
      off += $urandom_range(nb - 1, 1);
    else if (knobs.align == aou_dp_knobs::DP_ALIGN_ANY && $urandom_range(1) == 1)
      off += $urandom_range(nb - 1);
    t.dir   = wr ? AOU_AXI_WR : AOU_AXI_RD;
    t.id    = pick_id();
    t.addr  = base + 64'(off);
    t.len   = 8'(ln);
    t.size  = 3'(sz);
    t.burst = AOU_AXI_INCR;
    t.lock  = 1'b0;
    t.cache = {2'b00, 1'($urandom_range(1)), 1'($urandom_range(99) < knobs.bufferable_pct)};
    t.prot  = knobs.prot;
    t.qos   = (knobs.qos.size() > 0) ? 4'(knobs.qos[$urandom_range(knobs.qos.size() - 1)]) : 4'd0;
    if (knobs.attr_sweep) begin
      int unsigned k = n_attr[wr ? 0 : 1];
      n_attr[wr ? 0 : 1] = k + 1;
      t.cache = LEGAL_CACHE[k % 10];
      t.prot  = 3'(k);
      t.qos   = 4'(k);
    end
    if (t.crosses_4k()) `uvm_fatal(get_type_name(), {"shape crosses 4KB: ", t.convert2string()})
    if (wr) begin
      case (knobs.strb)
        aou_dp_knobs::DP_STRB_FULL:   t.fill_wdata(AOU_AXI_STRB_FULL);
        aou_dp_knobs::DP_STRB_RANDOM: t.fill_wdata(AOU_AXI_STRB_RANDOM);
        aou_dp_knobs::DP_STRB_MIXED:  t.fill_wdata(AOU_AXI_STRB_MIXED);
        default: begin
          t.fill_wdata(AOU_AXI_STRB_FULL);
          foreach (t.strb[i]) t.strb[i] &= strb_pattern(i);
        end
      endcase
    end
  endfunction

  virtual function void on_done(aou_axi_txn t);
    foreach (slot_base[k]) begin
      if (slot_base[k] == {t.addr[63:12], 12'h000}) begin
        slot_busy[k] = 1'b0;
        slot_sem.put(1);
        return;
      end
    end
    `uvm_error(get_type_name(), $sformatf("completed txn in no slot: %s", t.convert2string()))
  endfunction
endclass
