// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Random legal AXI4 traffic. Each in-flight transaction owns a distinct 4KB
// slot (num_slots pages picked at random in [addr_lo, addr_hi]; a window with
// fewer pages is a fatal error), so in-flight transactions never overlap and
// the golden memory is unambiguous; a slot is reused once its transaction
// completes.
//
// Sizes: an ordinary request is 32 bytes up to the bus (AxSIZE 5 or more),
// so small requests stay infrequent and absent unless asked for. Small
// requests (register-like accesses, AxSIZE below 5, under 32 bytes) come only
// from +small_size_pct=N: N% of requests (default 0). Their AxSIZE is
// drawn from +small_size_wt=w0,w1,w2,w3,w4 (weights of AxSIZE 0..4; default
// 2,4,45,45,4: 4- and 8-byte accesses common, 1-, 2- and 16-byte rare). They
// are single-beat INCR, except +small_burst_pct=N% of them (default 10) are
// 2-4 beats. aou_dp_seq extends this sequence and takes the same knobs.
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
  // Ordinary requests are at least min_len+1 beats (at most max_len+1 wins).
  bit [7:0]    min_len   = 8'd0;
  aou_axi_strb_e strb_mode = AOU_AXI_STRB_MIXED;
  int unsigned small_size_pct  = 0;
  int unsigned small_size_wt[5] = '{2, 4, 45, 45, 4};
  int unsigned small_burst_pct = 10;

  protected bit [63:0] slot_base[$];
  protected bit        slot_busy[$];
  protected semaphore  slot_sem;

  function new(string name = "aou_axi_rand_seq");
    super.new(name);
  endfunction

  task body();
    aou_axi_txn t;
    int slot;
    small_plusargs();
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

  // +small_size_pct, +small_size_wt and +small_burst_pct over the defaults.
  function void small_plusargs();
    string s;
    int unsigned q[$];
    int start = 0;
    void'($value$plusargs("small_size_pct=%d", small_size_pct));
    void'($value$plusargs("small_burst_pct=%d", small_burst_pct));
    if (!$value$plusargs("small_size_wt=%s", s)) return;
    for (int i = 0; i <= s.len(); i++) begin
      if (i == s.len() || s[i] == ",") begin
        if (i > start) q.push_back(s.substr(start, i - 1).atoi());
        start = i + 1;
      end
    end
    if (q.size() != 5)
      `uvm_fatal(get_type_name(), {"+small_size_wt needs five weights (AxSIZE 0..4): ", s})
    foreach (q[i]) small_size_wt[i] = q[i];
  endfunction

  // A small request, small_size_pct% of the time: its AxSIZE (0..4, weighted)
  // and length (one beat, or 2-4 beats small_burst_pct% of the time).
  function bit pick_small(output bit [2:0] sz, output bit [7:0] ln);
    int unsigned tot = 0;
    int unsigned r;
    sz = 3'd0;
    ln = 8'd0;
    if (small_size_pct == 0 || $urandom_range(99) >= small_size_pct) return 1'b0;
    foreach (small_size_wt[i]) tot += small_size_wt[i];
    if (tot == 0) return 1'b0;
    r = $urandom_range(tot - 1);
    foreach (small_size_wt[i]) begin
      if (r < small_size_wt[i]) begin
        sz = 3'(i);
        break;
      end
      r -= small_size_wt[i];
    end
    if ($urandom_range(99) < small_burst_pct) ln = 8'($urandom_range(3, 1));
    return 1'b1;
  endfunction

  // num_slots distinct pages, in random order, from the window's pages: a
  // shuffle of the page indices, of which the first num_slots are kept. Only
  // the positions the shuffle touches are stored (perm), so a wide window
  // costs no more than a narrow one, and the loop runs exactly num_slots
  // times. A window with fewer pages than num_slots stops the test.
  protected function void pick_slots();
    bit [63:0] lo_pg = addr_lo >> 12;
    bit [63:0] n_sl  = 64'(num_slots);
    bit [63:0] n_pg;
    bit [63:0] perm[bit [63:0]];   // shuffled index at position i (i if absent)
    bit [63:0] j;
    bit [63:0] pi;
    bit [63:0] pj;
    if (addr_hi < addr_lo)
      `uvm_fatal(get_type_name(), $sformatf("empty address window [0x%0h, 0x%0h]",
                                            addr_lo, addr_hi))
    n_pg = (addr_hi >> 12) - lo_pg + 64'd1;   // at most 2^52: never wraps to 0
    if (n_sl > n_pg)
      `uvm_fatal(get_type_name(), $sformatf(
        "num_slots %0d exceeds the %0d 4KB pages in [0x%0h, 0x%0h]",
        num_slots, n_pg, addr_lo, addr_hi))
    slot_base.delete();
    slot_busy.delete();
    for (bit [63:0] i = 0; i < n_sl; i++) begin
      j  = i + ({$urandom(), $urandom()} % (n_pg - i));
      pi = perm.exists(i) ? perm[i] : i;
      pj = perm.exists(j) ? perm[j] : j;
      perm[j] = pi;
      slot_base.push_back((lo_pg + pj) << 12);
      slot_busy.push_back(1'b0);
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
    bit [2:0]    ssz;
    bit [7:0]    sln;
    bit          is_small;
    bit [2:0]    mn;
    wr = ($urandom_range(99) < wr_pct);
    l  = ($urandom_range(99) < lock_pct) && p_sequencer.cfg.lock_en;
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
    if (b != AOU_AXI_WRAP && lmin < min_len) lmin = min_len;
    if (lmax < lmin) lmax = lmin;
    // A FIXED burst is at most 16 beats (AXI4 A3.4.1), whatever min_len asks.
    if (b == AOU_AXI_FIXED && lmax > 15) lmax = 15;
    if (lmax > max_len) lmax = max_len;
    if (lmin > lmax) lmin = lmax;
    full_size = ($urandom_range(1) == 1);
    // A long burst at the full bus width may not fit in 4 KB (AXI4 A3.4.1).
    if (((int'(lmin) + 1) << msz) > 4096) full_size = 1'b0;
    is_small = pick_small(ssz, sln) && !l;
    mn = (msz < 3'd5) ? msz : 3'd5;   // a bus under 32 bytes has no ordinary size
    if (is_small) begin
      b = AOU_AXI_INCR;
      full_size = 1'b0;
    end
    if (l) begin
      `AOU_RANDOMIZE_WITH(t, {
        dir == (wr ? AOU_AXI_WR : AOU_AXI_RD);
        lock == 1'b1;
        io -> burst == b;
        id <= max_id;
        addr >= base; addr <= base + 64'hfff;
      })
    end else if (is_small) begin
      `AOU_RANDOMIZE_WITH(t, {
        dir == (wr ? AOU_AXI_WR : AOU_AXI_RD);
        lock == 1'b0;
        burst == b;
        id <= max_id;
        size == ssz; len == sln;
        addr >= base; addr <= base + 64'hfff;
      })
    end else begin
      `AOU_RANDOMIZE_WITH(t, {
        dir == (wr ? AOU_AXI_WR : AOU_AXI_RD);
        lock == 1'b0;
        burst == b;
        id <= max_id;
        len >= lmin; len <= lmax;
        size >= mn;
        full_size -> size == msz;
        addr >= base; addr <= base + 64'hfff;
      })
    end
    if (wr) t.fill_wdata(strb_mode);
  endfunction
endclass
