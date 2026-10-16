// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Random legal AXI4 traffic. Each in-flight transaction owns a distinct 4KB
// slot (num_slots pages picked at random in [addr_lo, addr_hi]), so in-flight
// transactions never overlap and the golden memory is unambiguous; a slot is
// reused once its transaction completes.
class aou_axi_rand_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_axi_rand_seq)

  int unsigned num_txns  = 200;
  int unsigned num_slots = 32;
  bit [63:0]   addr_lo   = 64'h0;
  bit [63:0]   addr_hi   = 64'h0000_FFFF_FFFF_FFFF;
  int unsigned wr_pct    = 50;
  int unsigned lock_pct  = 3;
  int unsigned fixed_pct = 10;
  int unsigned wrap_pct  = 15;
  bit [9:0]    max_id    = 10'd7;
  bit [7:0]    max_len   = 8'd255;
  aou_axi_strb_e strb_mode = AOU_AXI_STRB_MIXED;

  protected bit [63:0] slot_base[$];
  protected bit        slot_busy[$];
  protected semaphore  slot_sem;

  function new(string name = "aou_axi_rand_seq");
    super.new(name);
  endfunction

  task body();
    aou_axi_txn t;
    int slot;
    pick_slots();
    for (int unsigned n = 0; n < num_txns; n++) begin
      slot_sem.get(1);
      slot = free_slot();
      slot_busy[slot] = 1'b1;
      t = new_txn($sformatf("rand%0d", n));
      randomize_txn(t, slot_base[slot]);
      send(t);
    end
    wait_all();
  endtask

  protected function void pick_slots();
    bit [63:0] page;
    bit [63:0] span = (addr_hi >> 12) - (addr_lo >> 12);
    bit dup;
    slot_base.delete();
    slot_busy.delete();
    while (slot_base.size() < num_slots) begin
      page = (addr_lo >> 12) + ({$urandom(), $urandom()} % (span + 64'd1));
      dup = 1'b0;
      foreach (slot_base[k]) if (slot_base[k] == page << 12) dup = 1'b1;
      if (!dup) begin
        slot_base.push_back(page << 12);
        slot_busy.push_back(1'b0);
      end
    end
    slot_sem = new(num_slots);
  endfunction

  protected function int free_slot();
    int free[$];
    foreach (slot_busy[k]) if (!slot_busy[k]) free.push_back(k);
    return free[$urandom_range(free.size() - 1)];
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

  // Buckets come from randcase here rather than dist in constraints.
  protected function void randomize_txn(aou_axi_txn t, bit [63:0] base);
    bit [1:0]    b;
    bit          l;
    bit          wr;
    bit [7:0]    lmin;
    bit [7:0]    lmax;
    bit          full_size;
    bit [2:0]    msz = 3'(p_sequencer.cfg.max_size());
    bit          io = p_sequencer.cfg.incr_only;
    wr = ($urandom_range(99) < wr_pct);
    l  = ($urandom_range(99) < lock_pct);
    b  = AOU_AXI_INCR;
    randcase
      fixed_pct:                   b = AOU_AXI_FIXED;
      wrap_pct:                    b = AOU_AXI_WRAP;
      100 - fixed_pct - wrap_pct:  b = AOU_AXI_INCR;
    endcase
    if (io) b = AOU_AXI_INCR;
    randcase
      30: begin lmin = 0;  lmax = 0;   end
      30: begin lmin = 1;  lmax = 3;   end
      25: begin lmin = 4;  lmax = 15;  end
      15: begin lmin = 16; lmax = 255; end
    endcase
    if (b == AOU_AXI_WRAP) begin
      randcase
        1: lmin = 1;
        1: lmin = 3;
        1: lmin = 7;
        1: lmin = 15;
      endcase
      lmax = lmin;
    end
    if (b == AOU_AXI_FIXED && lmax > 15) lmax = 15;
    if (lmax > max_len) lmax = max_len;
    if (lmin > lmax) lmin = lmax;
    full_size = ($urandom_range(1) == 1);
    if (l) begin
      `AOU_RANDOMIZE_WITH(t, {
        dir == (wr ? AOU_AXI_WR : AOU_AXI_RD);
        lock == 1'b1;
        io -> burst == b;
        id <= max_id;
        addr >= base; addr <= base + 64'hfff;
      })
    end else begin
      `AOU_RANDOMIZE_WITH(t, {
        dir == (wr ? AOU_AXI_WR : AOU_AXI_RD);
        lock == 1'b0;
        burst == b;
        id <= max_id;
        len >= lmin; len <= lmax;
        full_size -> size == msz;
        addr >= base; addr <= base + 64'hfff;
      })
    end
    if (wr) t.fill_wdata(strb_mode);
  endfunction
endclass
