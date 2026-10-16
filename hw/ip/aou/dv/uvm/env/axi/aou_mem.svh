// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Sparse byte memory. A byte never written reads as a hash of the seed and its
// address, so two memories with the same seed start identical without storing
// anything. Error regions make accesses that touch them return SLVERR or DECERR;
// bytes inside an error region are never written.
class aou_mem extends uvm_object;
  `uvm_object_utils(aou_mem)

  bit [63:0] seed;

  protected bit [7:0]  mem_q[bit [63:0]];
  protected bit [63:0] err_lo[$];
  protected bit [63:0] err_hi[$];
  protected bit [1:0]  err_resp[$];
  // Exclusive monitor (AXI4 A7.2): one reservation per ID.
  protected bit [63:0] excl_addr[bit [9:0]];
  protected int unsigned excl_bytes[bit [9:0]];

  function new(string name = "aou_mem");
    super.new(name);
    seed = {$urandom(), $urandom()};
  endfunction

  function bit [7:0] init_byte(bit [63:0] a);
    bit [63:0] z = a ^ seed;
    z = z + 64'h9E37_79B9_7F4A_7C15;
    z = (z ^ (z >> 30)) * 64'hBF58_476D_1CE4_E5B9;
    z = (z ^ (z >> 27)) * 64'h94D0_49BB_1331_11EB;
    z = z ^ (z >> 31);
    return z[7:0];
  endfunction

  function bit [7:0] read_byte(bit [63:0] a);
    if (mem_q.exists(a)) return mem_q[a];
    return init_byte(a);
  endfunction

  function void write_byte(bit [63:0] a, bit [7:0] v);
    mem_q[a] = v;
  endfunction

  function bit is_written(bit [63:0] a);
    return mem_q.exists(a);
  endfunction

  function void get_written(ref bit [63:0] addrs[$]);
    foreach (mem_q[a]) addrs.push_back(a);
  endfunction

  // [lo, hi] inclusive. resp is AOU_AXI_SLVERR or AOU_AXI_DECERR.
  function void add_error_region(bit [63:0] lo, bit [63:0] hi, bit [1:0] resp);
    err_lo.push_back(lo);
    err_hi.push_back(hi);
    err_resp.push_back(resp);
  endfunction

  function void clear_error_regions();
    err_lo.delete();
    err_hi.delete();
    err_resp.delete();
  endfunction

  // Worst response for one byte: DECERR over SLVERR over OKAY.
  function bit [1:0] byte_resp(bit [63:0] a);
    bit [1:0] r = AOU_AXI_OKAY;
    foreach (err_lo[i])
      if (a >= err_lo[i] && a <= err_hi[i] && err_resp[i] > r) r = err_resp[i];
    return r;
  endfunction

  // Worst response over the active lanes of beat i (strobes do not matter).
  function bit [1:0] beat_resp(aou_axi_txn t, int unsigned i);
    bit [1:0] r = AOU_AXI_OKAY;
    bit [1:0] b;
    if (err_lo.size() == 0) return r;
    for (int unsigned l = t.lane_lo(i); l <= t.lane_hi(i); l++) begin
      b = byte_resp(t.beat_base(i) + 64'(l));
      if (b > r) r = b;
    end
    return r;
  endfunction

  function bit [1:0] txn_resp(aou_axi_txn t);
    bit [1:0] r = AOU_AXI_OKAY;
    bit [1:0] b;
    for (int unsigned i = 0; i < t.beats(); i++) begin
      b = beat_resp(t, i);
      if (b > r) r = b;
    end
    return r;
  endfunction

  // Write the strobed bytes of t that lie outside every error region.
  function void write_txn(aou_axi_txn t);
    bit [7:0] b[bit [63:0]];
    t.to_bytes(b);
    foreach (b[a]) begin
      if (byte_resp(a) == AOU_AXI_OKAY) begin
        mem_q[a] = b[a];
        clear_excl(a);
      end
    end
  endfunction

  // Data of beat i of read t, bus-aligned; inactive lanes are zero.
  function bit [1023:0] read_beat(aou_axi_txn t, int unsigned i);
    bit [1023:0] d = '0;
    bit [63:0] base = t.beat_base(i);
    for (int unsigned l = t.lane_lo(i); l <= t.lane_hi(i); l++)
      d[8*l +: 8] = read_byte(base + 64'(l));
    return d;
  endfunction

  function void excl_reserve(bit [9:0] id, bit [63:0] a, int unsigned n);
    excl_addr[id]  = a;
    excl_bytes[id] = n;
  endfunction

  // True when ID id holds a reservation for exactly [a, a+n).
  function bit excl_check(bit [9:0] id, bit [63:0] a, int unsigned n);
    return excl_addr.exists(id) && excl_addr[id] == a && excl_bytes[id] == n;
  endfunction

  protected function void clear_excl(bit [63:0] a);
    bit [9:0] ids[$];
    foreach (excl_addr[id])
      if (a >= excl_addr[id] && a < excl_addr[id] + 64'(excl_bytes[id])) ids.push_back(id);
    foreach (ids[k]) begin
      excl_addr.delete(ids[k]);
      excl_bytes.delete(ids[k]);
    end
  endfunction

  // A subordinate's write: error regions win and an exclusive write lands only
  // with a matching reservation (EXOKAY); a failed exclusive gets OKAY and
  // writes nothing. A normal write that hits an error region still writes its
  // bytes outside the region.
  function bit [1:0] axi_write(aou_axi_txn t, bit exclusive_en);
    bit [1:0] r = txn_resp(t);
    if (r != AOU_AXI_OKAY) begin
      if (!t.lock) write_txn(t);
      return r;
    end
    if (t.lock) begin
      if (exclusive_en && excl_check(t.id, t.addr, t.beats() * t.beat_bytes())) begin
        write_txn(t);
        return AOU_AXI_EXOKAY;
      end
      return AOU_AXI_OKAY;
    end
    write_txn(t);
    return AOU_AXI_OKAY;
  endfunction

  // Call when a read is accepted: an exclusive read takes a reservation.
  function void axi_read_start(aou_axi_txn t, bit exclusive_en);
    if (t.lock && exclusive_en) excl_reserve(t.id, t.addr, t.beats() * t.beat_bytes());
  endfunction

  // A subordinate's response for read beat i.
  function bit [1:0] axi_read_resp(aou_axi_txn t, int unsigned i, bit exclusive_en);
    bit [1:0] r = beat_resp(t, i);
    if (r == AOU_AXI_OKAY && t.lock && exclusive_en) r = AOU_AXI_EXOKAY;
    return r;
  endfunction

  // Same seed, error regions and contents as src.
  function void copy_from(aou_mem src);
    bit [63:0] addrs[$];
    seed = src.seed;
    mem_q.delete();
    src.get_written(addrs);
    foreach (addrs[k]) mem_q[addrs[k]] = src.read_byte(addrs[k]);
    clear_error_regions();
    src.get_error_regions(err_lo, err_hi, err_resp);
  endfunction

  function void get_error_regions(ref bit [63:0] lo[$], ref bit [63:0] hi[$],
                                  ref bit [1:0] resp[$]);
    foreach (err_lo[i]) begin
      lo.push_back(err_lo[i]);
      hi.push_back(err_hi[i]);
      resp.push_back(err_resp[i]);
    end
  endfunction
endclass
