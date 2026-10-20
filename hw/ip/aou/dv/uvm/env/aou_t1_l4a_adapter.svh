// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3's responder callback over the remote AXI model: a DUT WriteReq/WriteData
// or ReadReq becomes AXI transactions on remote.execute(). On the link, data
// travels in the lanes of a bus as wide as the message's DLENGTH. The remote
// die's own bus on that RP is cfg.remote_bytes_of(rp) wide, and the adapter is
// that die's width converter and splitter, working from the request message as
// received (its size, address and length):
// - A request whose size fits the native bus maps onto one AXI transaction
//   with the same size, length and strobes (narrow when it is below the bus).
// - A wider request is downsized to the native size.
// - Like the DUT's splitter (MAS 3.6), a burst longer than the maximum burst
//   length (cfg.remote_max_burst, 2^n beats, default 256, the AXI4 limit) is
//   split into sub-bursts, each with its own address, size and strobes, and
//   the request gets one response: the worst BRESP of its sub-bursts, or
//   ReadData packed from them. The spec leaves splitting to the
//   implementation. A legal burst never crosses 4KB; the split guards that too.
//   An exclusive request is never split (its reservation covers the whole),
//   so it may exceed the maximum burst length: legal AXI, since nothing makes
//   a subordinate split. Exclusives are at most 64 bytes here, so at most two
//   beats on a 256-bit bus. split_cg counts such a request as "whole" at the
//   current maximum (b1, whole for a 2-beat exclusive at a maximum of 1).
// - ReadData is packed at the requester's ARSIZE (spec §5.7: the responder
//   converts), each beat with the worst response of the native beats under it.
// - +remote_max_burst_rand=1 (off by default) picks a new maximum from the
//   legal set when the remote is idle, so one run sees several.
// WriteData DLENGTH is self-describing: a writer may send any DLENGTH of at
// least max(its WriteReq's size, 256 bits), and the receiver takes the lanes
// at that DLENGTH. Packing at the WriteReq's size is the minimal legal choice;
// this DUT packs at its RP width, which is also legal.
// T1-L4A02: WriteData DLENGTH is at least max(its WriteReq's size, 256 bits).
// T1-L4A04: the maximum burst length never changes while the remote has a
//   request in hand.
typedef class aou_t1_xfer_cov;

class aou_t1_l4a_adapter extends aou_l4a_if_c;
  `uvm_object_utils(aou_t1_l4a_adapter)

  aou_remote_axi_model remote;
  aou_t1_env_cfg       cfg;            // remote native width per RP (null: message width)
  aou_t1_xfer_cov      cov;            // remote max burst length seen (null: none)
  int unsigned         n_wr;
  int unsigned         n_rd;
  int unsigned         n_conv[2][2];   // [wr, rd][downsized, exact]
  int unsigned         n_split;        // requests that took more than one transaction
  int unsigned         n_max_changes;  // runtime changes of the maximum burst length
  protected int unsigned n_busy;       // requests inside the converter

  function new(string name = "aou_t1_l4a_adapter");
    super.new(name);
  endfunction

  function aou_axi_txn mk(aou_msg_req req, aou_axi_dir_e dir, int unsigned bus);
    aou_axi_txn t = aou_axi_txn::type_id::create("l4a");
    t.dir = dir;
    t.rp = int'(req.rp);
    t.local_side = 1'b0;
    t.id = req.id;
    t.addr = req.addr;
    t.len = req.len;
    t.size = req.size;
    t.burst = AOU_AXI_INCR;
    t.lock = req.lock;
    t.cache = req.cache;
    t.prot = req.prot;
    t.qos = req.qos;
    t.data_bytes = bus;
    return t;
  endfunction

  // The remote die's AXI data bytes on wire RP rp.
  function int unsigned native_bytes(int rp, int unsigned bus);
    if (cfg == null) return bus;
    return cfg.remote_bytes_of(rp);
  endfunction

  function int unsigned max_burst();
    return (cfg == null) ? 256 : cfg.remote_max_burst;
  endfunction

  // Changes the maximum burst length, legal only while the remote is idle.
  function void set_max_burst(int unsigned v);
    if (n_busy != 0)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-L4A04: maximum burst length changed to %0d with %0d requests in hand", v,
                 n_busy))
    if (cfg != null && cfg.remote_max_burst != v) begin
      cfg.remote_max_burst = v;
      n_max_changes++;
    end
  endfunction

  // A request enters the converter: at an idle point, maybe pick a new maximum.
  protected function int unsigned enter();
    int unsigned legal[9] = '{1, 2, 4, 8, 16, 32, 64, 128, 256};
    if (n_busy == 0 && cfg != null && cfg.remote_max_burst_rand && $urandom_range(3) == 0)
      set_max_burst(legal[$urandom_range(8)]);
    n_busy++;
    return max_burst();
  endfunction

  protected function void leave(int unsigned mb);
    if (max_burst() != mb)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-L4A04: maximum burst length went from %0d to %0d during a request", mb,
                 max_burst()))
    n_busy--;
  endfunction

  // t as the native bus of nb bytes carries it: AxSIZE capped at the bus, in
  // INCR transactions of at most mb beats (unless exclusive) that don't cross
  // 4KB. A write's strobed bytes move to their native lanes.
  function void to_native(aou_axi_txn t, int unsigned nb, int unsigned mb, ref aou_axi_txn q[$]);
    bit [7:0] b[bit [63:0]];
    bit [2:0] sz = (t.beat_bytes() > nb) ? 3'($clog2(nb)) : t.size;
    bit [63:0] w = 64'd1 << sz;
    bit [63:0] start = t.addr & ~(w - 64'd1);
    bit [63:0] stop = (t.addr & ~(64'(t.beat_bytes()) - 64'd1)) +
                      64'(t.beat_bytes()) * (64'(t.len) + 64'd1);
    int unsigned total = int'((stop - start) / w);
    int unsigned j = 0;
    q.delete();
    if (t.dir == AOU_AXI_WR) t.to_bytes(b);
    while (j < total) begin
      aou_axi_txn n;
      bit [63:0] a0 = (j == 0) ? t.addr : start + 64'(j) * w;
      int unsigned k = 1;
      while (j + k < total && (k < mb || t.lock) &&
             ((start + 64'(j + k) * w) >> 12) == (a0 >> 12))
        k++;
      if (!$cast(n, t.clone())) `uvm_fatal(get_type_name(), "clone failed")
      n.addr = a0;
      n.size = sz;
      n.len = 8'(k - 1);
      n.data_bytes = nb;
      n.data.delete();
      n.strb.delete();
      if (t.dir == AOU_AXI_WR) begin
        n.data = new[k];
        n.strb = new[k];
        for (int unsigned i = 0; i < k; i++) begin
          n.data[i] = '0;
          n.strb[i] = '0;
          for (int unsigned l = n.lane_lo(i); l <= n.lane_hi(i); l++) begin
            bit [63:0] a = n.beat_base(i) + 64'(l);
            if (b.exists(a)) begin
              n.data[i][8*l +: 8] = b[a];
              n.strb[i][l] = 1'b1;
            end
          end
        end
      end
      q.push_back(n);
      j += k;
    end
    if (q.size() > 1) n_split++;
    if (cov != null) cov.sample_split(mb, q.size() > 1);
  endfunction

  virtual task handle_write(input aou_msg_wreq req, input aou_msg_wdata data[$],
                            output bit [1:0] bresp);
    aou_axi_txn t;
    aou_axi_txn rsp;
    aou_axi_txn q[$];
    int unsigned bus = (data.size() > 0) ? aou_dl_bits(data[0].dlength) / 8 : 32;
    int unsigned nb;
    int unsigned k;
    int unsigned mb = enter();
    t = mk(req, AOU_AXI_WR, bus);
    t.data = new[data.size()];
    t.strb = new[data.size()];
    foreach (data[i]) begin
      if (aou_dl_bits(data[i].dlength) / 8 != bus)
        `uvm_error(get_type_name(), $sformatf(
                   "T1-L4A01: WriteData DLENGTH changes within a burst (beat %0d: %0d bits)", i,
                   aou_dl_bits(data[i].dlength)))
      t.data[i] = data[i].data;
      t.strb[i] = data[i].strb & ({128{1'b1}} >> (128 - bus));
    end
    if (t.beat_bytes() > bus) begin
      `uvm_error(get_type_name(), $sformatf(
                 "T1-L4A02: WriteData of %0d bits for a WriteReq of size %0d (%0d bits): %s",
                 8 * bus, t.size, 8 * t.beat_bytes(), t.convert2string()))
      t.size = 3'($clog2(bus));
    end
    nb = native_bytes(int'(req.rp), bus);
    k = (t.beat_bytes() > nb) ? 0 : 1;
    n_conv[0][k]++;
    to_native(t, nb, mb, q);
    bresp = 2'b00;
    foreach (q[i]) begin
      remote.execute(q[i], rsp);
      if (rsp.bresp > bresp) bresp = rsp.bresp;
    end
    leave(mb);
    n_wr++;
  endtask

  virtual task handle_read(input aou_msg_rreq req, output bit [1023:0] data[$],
                           output bit [1:0] resp[$]);
    aou_axi_txn t;
    aou_axi_txn q[$];
    bit [7:0] b[bit [63:0]];
    bit [1:0] r_of[bit [63:0]];
    int unsigned nb;
    int unsigned k;
    int unsigned mb = enter();
    t = mk(req, AOU_AXI_RD, aou_dl_bits(aou_dl_for_size(req.size)) / 8);
    nb = native_bytes(int'(req.rp), t.data_bytes);
    k = (t.beat_bytes() > nb) ? 0 : 1;
    n_conv[1][k]++;
    to_native(t, nb, mb, q);
    foreach (q[i]) begin
      aou_axi_txn rsp;
      remote.execute(q[i], rsp);
      for (int unsigned j = 0; j < rsp.beats(); j++)
        for (int unsigned l = rsp.lane_lo(j); l <= rsp.lane_hi(j); l++) begin
          bit [63:0] a = rsp.beat_base(j) + 64'(l);
          b[a] = rsp.data[j][8*l +: 8];
          r_of[a] = rsp.rresp[j];
        end
    end
    // Pack into ReadData beats of the requester's ARSIZE.
    data.delete();
    resp.delete();
    for (int unsigned i = 0; i < t.beats(); i++) begin
      bit [1023:0] d = '0;
      bit [1:0] r = 2'b00;
      for (int unsigned l = t.lane_lo(i); l <= t.lane_hi(i); l++) begin
        bit [63:0] a = t.beat_base(i) + 64'(l);
        d[8*l +: 8] = b[a];
        if (r_of[a] > r) r = r_of[a];
      end
      data.push_back(d);
      resp.push_back(r);
    end
    leave(mb);
    n_rd++;
  endtask
endclass
