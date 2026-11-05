// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The only AXI type the scoreboard, sequences and tests see (docs/AOU_TB_ARCH.adoc).
// data[]/strb[] hold one entry per beat with bus-aligned byte lanes: byte lane L
// of beat i is data[i][8*L +: 8] and belongs to address beat_base(i) + L.
class aou_axi_txn extends uvm_sequence_item;
  `uvm_object_utils(aou_axi_txn)

  rand aou_axi_dir_e dir;
  int unsigned       rp;
  bit                local_side = 1'b1;
  rand bit [9:0]     id;
  rand bit [63:0]    addr;
  rand bit [7:0]     len;
  rand bit [2:0]     size;
  rand bit [1:0]     burst;
  rand bit           lock;
  rand bit [3:0]     cache, qos;
  rand bit [2:0]     prot;
  // AXI USER, 16 bits (AoU v0.8 Table 31). user is AWUSER or ARUSER; wuser[]
  // holds one WUSER per W beat, ruser[] one RUSER per R beat; buser is BUSER.
  // The manager driver fills user and wuser[] from its cfg.user_mode unless
  // user_fixed says the sequence chose them; the monitors capture all five.
  // On a far-side transaction built from the DUT's messages (aou_t1_l4a_adapter,
  // aou_t1_remote_mgr_driver) they hold the FLEX fields of those messages.
  rand bit [15:0]    user;
  bit                user_fixed;
  bit [15:0]         wuser[];
  bit [15:0]         buser;
  bit [15:0]         ruser[];
  // How a write went on the link when the remote manager repacked it as a
  // WriteReq of another size (AoU lets a writer raise the size above AWSIZE):
  // the WriteReq's size and length, from addr, and the FLEX of each WriteData
  // beat in message order. link_wuser is empty when the WriteData beats are
  // the W beats (size, len and wuser[] then describe the link too).
  bit [2:0]          link_size;
  bit [7:0]          link_len;
  bit [15:0]         link_wuser[];
  int unsigned       data_bytes = 64;
  bit [1023:0]       data[];
  bit [127:0]        strb[];
  bit [1:0]          rresp[];
  bit [1:0]          bresp;
  time               t_addr, t_done;
  // Write: WLAST handshake (set by aou_axi_mgr_driver; 0 until then).
  time               t_wlast;
  // Write: handshake of each W beat (set by aou_axi_monitor; empty otherwise).
  time               t_w[];
  // Read: handshake of each R beat (set by aou_axi_monitor; empty otherwise).
  time               t_r[];
  // Set when a reset ended the transaction before its response (reset_flush);
  // response fields are then meaningless.
  bit                aborted;
  // On the bus when AOU_SW_RESET was requested (aou_axi_monitor::sw_reset_window):
  // it may end with SLVERR or not at all.
  bit                reset_outstanding;

  // AXI4 A3.4.1 burst rules and A3.1.2/A3.4 size limits.
  constraint c_axi4_legal {
    burst != 2'b11;
    (32'd1 << size) <= data_bytes;
    (burst == AOU_AXI_WRAP) -> ((len inside {8'd1, 8'd3, 8'd7, 8'd15}) &&
                               ((addr & ((64'd1 << size) - 64'd1)) == 64'd0));
    (burst == AOU_AXI_FIXED) -> (len <= 8'd15);
    (burst == AOU_AXI_INCR) ->
        ((({52'd0, addr[11:0]} >> size) + {56'd0, len}) < (64'd4096 >> size));
  }

  // AXI4 A4.4, table A4-5: an allocate bit (AxCACHE[3:2]) needs Modifiable (AxCACHE[1]);
  // the six encodings that break this are reserved.
  constraint c_axi4_cache {
    (cache[3:2] != 2'b00) -> cache[1];
  }
  // The ten AxCACHE encodings c_axi4_cache allows, for sequences that set cache directly.
  static const bit [3:0] LEGAL_CACHE[10] = '{4'h0, 4'h1, 4'h2, 4'h3, 4'h6, 4'h7, 4'hA, 4'hB,
                                            4'hE, 4'hF};

  // AXI4 A7.2.4: exclusive accesses are a power of two bytes, aligned to their
  // total size, and at most 16 beats. AXI allows up to 128 bytes; this bench
  // models at most 64, the project's limit.
  constraint c_exclusive {
    lock -> ((burst != AOU_AXI_FIXED) && (len inside {8'd0, 8'd1, 8'd3, 8'd7, 8'd15}) &&
             ((({24'd0, len} + 32'd1) << size) <= 32'd64) &&
             ((addr & (((64'd1 + {56'd0, len}) << size) - 64'd1)) == 64'd0));
  }

  function new(string name = "aou_axi_txn");
    super.new(name);
  endfunction

  function void post_randomize();
    if (dir == AOU_AXI_WR) begin
      fill_wdata(AOU_AXI_STRB_FULL);
    end else begin
      data.delete();
      strb.delete();
    end
    rresp.delete();
  endfunction

  function int unsigned beats();
    return int'(len) + 1;
  endfunction

  function int unsigned beat_bytes();
    return 32'd1 << size;
  endfunction

  // Address of the first byte transferred in beat i (AXI4 A3.4.2). Only beat 0 of
  // an INCR or FIXED burst can be unaligned.
  function bit [63:0] beat_addr(int unsigned i);
    bit [63:0] nb      = 64'd1 << size;
    bit [63:0] aligned = addr & ~(nb - 64'd1);
    bit [63:0] a;
    bit [63:0] total;
    bit [63:0] lower;
    if (burst == AOU_AXI_FIXED || i == 0) return addr;
    a = aligned + 64'(i) * nb;
    if (burst == AOU_AXI_WRAP) begin
      total = nb * (64'(len) + 64'd1);
      lower = addr & ~(total - 64'd1);
      if (a >= lower + total) a -= total;
    end
    return a;
  endfunction

  // Address of byte lane 0 for beat i.
  function bit [63:0] beat_base(int unsigned i);
    return beat_addr(i) & ~(64'(data_bytes) - 64'd1);
  endfunction

  // Index of the beat whose transfer covers byte address a, counting from the
  // aligned start of an INCR burst; -1 when a lies outside the burst.
  function int beat_index_of(bit [63:0] a);
    bit [63:0] nb    = 64'd1 << size;
    bit [63:0] first = addr & ~(nb - 64'd1);
    bit [63:0] base  = a & ~(nb - 64'd1);
    if (base < first) return -1;
    if ((base - first) / nb >= 64'(beats())) return -1;
    return int'((base - first) / nb);
  endfunction

  // First and last active byte lane of beat i (AXI4 A3.4.2 Lower/Upper_Byte_Lane).
  function int unsigned lane_lo(int unsigned i);
    return int'(beat_addr(i) & (64'(data_bytes) - 64'd1));
  endfunction

  function int unsigned lane_hi(int unsigned i);
    bit [63:0] nb = 64'd1 << size;
    return int'((beat_addr(i) & ~(nb - 64'd1)) & (64'(data_bytes) - 64'd1)) + int'(nb) - 1;
  endfunction

  function bit [127:0] lane_mask(int unsigned i);
    bit [127:0] m = '0;
    for (int unsigned l = lane_lo(i); l <= lane_hi(i); l++) m[l] = 1'b1;
    return m;
  endfunction

  // INCR bursts must not cross a 4KB boundary (AXI4 A3.4.1).
  function bit crosses_4k();
    bit [63:0] nb = 64'd1 << size;
    bit [63:0] last;
    if (burst != AOU_AXI_INCR) return 1'b0;
    last = (addr & ~(nb - 64'd1)) + nb * (64'(len) + 64'd1) - 64'd1;
    return addr[63:12] != last[63:12];
  endfunction

  // The bytes this transaction carries, as address -> byte: for a write the
  // strobed bytes of the active lanes, for a read every active lane. A later beat
  // of a FIXED burst overwrites an earlier one, as in memory.
  function void to_bytes(output bit [7:0] b[bit [63:0]]);
    b.delete();
    for (int unsigned i = 0; i < beats() && i < data.size(); i++) begin
      for (int unsigned l = lane_lo(i); l <= lane_hi(i); l++) begin
        if (dir == AOU_AXI_RD || (i < strb.size() && strb[i][l]))
          b[beat_base(i) + 64'(l)] = data[i][8*l +: 8];
      end
    end
  endfunction

  function bit [1023:0] rand_word();
    bit [1023:0] w = '0;
    for (int unsigned k = 0; k < data_bytes / 4; k++) w[32*k +: 32] = $urandom();
    return w;
  endfunction

  // Fill data[] with random bytes and strb[] with the given pattern; strobes are
  // never set outside a beat's active lanes.
  function void fill_wdata(aou_axi_strb_e mode);
    bit [127:0] m;
    bit [127:0] r;
    data = new[beats()];
    strb = new[beats()];
    for (int unsigned i = 0; i < beats(); i++) begin
      data[i] = rand_word();
      m = lane_mask(i);
      r = {$urandom(), $urandom(), $urandom(), $urandom()};
      case (mode)
        AOU_AXI_STRB_FULL:   strb[i] = m;
        AOU_AXI_STRB_RANDOM: strb[i] = r & m;
        default: begin
          randcase
            6: strb[i] = m;
            3: strb[i] = r & m;
            1: strb[i] = '0;
          endcase
        end
      endcase
    end
  endfunction

  function string convert2string();
    string s;
    s = $sformatf("%s rp%0d %s id=%0h addr=%0h len=%0d size=%0d burst=%0d lock=%0b",
                  dir == AOU_AXI_WR ? "WR" : "RD", rp, local_side ? "local" : "remote",
                  id, addr, len, size, burst, lock);
    s = {s, $sformatf(" cache=%0h prot=%0h qos=%0h user=%04h", cache, prot, qos, user)};
    if (dir == AOU_AXI_WR) s = {s, $sformatf(" bresp=%0d buser=%04h", bresp, buser)};
    if (wuser.size() > 0) s = {s, " wuser=", user_list(wuser)};
    if (ruser.size() > 0) s = {s, " ruser=", user_list(ruser)};
    if (link_wuser.size() > 0)
      s = {s, $sformatf(" link: size=%0d len=%0d wuser=", link_size, link_len),
           user_list(link_wuser)};
    return s;
  endfunction

  // "0001,0002,..." with the tail elided past eight entries.
  static function string user_list(bit [15:0] u[]);
    string s = "";
    foreach (u[i]) begin
      if (i == 8) begin
        s = {s, $sformatf(",...(%0d)", u.size())};
        break;
      end
      s = {s, (i == 0) ? "" : ",", $sformatf("%04h", u[i])};
    end
    return s;
  endfunction

  function void do_copy(uvm_object rhs);
    aou_axi_txn t;
    super.do_copy(rhs);
    if (!$cast(t, rhs)) `uvm_fatal(get_type_name(), "do_copy: not an aou_axi_txn")
    dir        = t.dir;
    rp         = t.rp;
    local_side = t.local_side;
    id         = t.id;
    addr       = t.addr;
    len        = t.len;
    size       = t.size;
    burst      = t.burst;
    lock       = t.lock;
    cache      = t.cache;
    qos        = t.qos;
    prot       = t.prot;
    user       = t.user;
    user_fixed = t.user_fixed;
    wuser      = t.wuser;
    buser      = t.buser;
    ruser      = t.ruser;
    link_size  = t.link_size;
    link_len   = t.link_len;
    link_wuser = t.link_wuser;
    data_bytes = t.data_bytes;
    data       = t.data;
    strb       = t.strb;
    rresp      = t.rresp;
    bresp      = t.bresp;
    t_addr     = t.t_addr;
    t_done     = t.t_done;
    t_wlast    = t.t_wlast;
    t_w        = t.t_w;
    t_r        = t.t_r;
    aborted    = t.aborted;
    reset_outstanding = t.reset_outstanding;
  endfunction
endclass
