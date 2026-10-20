// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die's AXI manager on one plane, its bus cfg.data_bytes wide:
// takes aou_axi_txn from an aou_axi_sequencer (so the L4b sequences run
// unchanged), sends WriteReq +
// WriteData/WriteDataFull or ReadReq through L3, and completes each
// transaction from the DUT's WriteResp/ReadData (rsp_write(), fed by
// aou_t1_remote_mgr). item_done() returns once the messages are queued; the
// completed transaction goes back through put_response() and out on ap.
class aou_t1_remote_mgr_driver extends uvm_driver #(aou_axi_txn);
  `uvm_component_utils(aou_t1_remote_mgr_driver)

  aou_axi_cfg  cfg;
  aou_l3_agent l3;
  bit [1:0]    wire_rp = 2'd0; // RP field of our requests: the DUT's plane
  int unsigned full_pct = 30;  // WriteDataFull when every lane is strobed
  // How our writes go on the link. A writer may raise the WriteReq size above
  // AWSIZE, and WriteData may use any DLENGTH of at least max(the WriteReq
  // size, 256 bits): DLENGTH is self-describing. All three modes are legal.
  // AOU_RWREQ_AWSIZE (default): the WriteReq keeps AWSIZE and WriteData is
  //   packed at it, the minimal legal choice.
  // AOU_RWREQ_UPSIZE: a narrow write that is modifiable (AxCACHE[1]) and not
  //   exclusive goes as a WriteReq of our bus size, its length recomputed and
  //   its strobes sparse. A non-modifiable one keeps its size (AXI4 A4.4).
  // AOU_RWREQ_DUT_LIKE: the WriteReq keeps AWSIZE and WriteData is at our bus
  //   width, as this DUT sends; legal, and it exercises a receiver's downsizers.
  aou_t1_rwreq_e wreq_mode = AOU_RWREQ_AWSIZE;
  uvm_analysis_port #(aou_axi_txn) ap;

  int unsigned n_wr;
  int unsigned n_rd;
  int unsigned n_aborted;

  protected aou_axi_txn  wr_q[bit [9:0]][$];
  protected aou_axi_txn  rd_q[bit [9:0]][$];
  protected int unsigned rd_beat[bit [9:0]][$];
  // Responses still owed for transactions a reset aborted (see
  // aou_axi_mgr_driver: within stale_window the next response on such an ID
  // is the stale one, and new requests on that ID wait for it).
  time                   stale_window = 10us;
  aou_axi_vif_t          clk_vif;   // any interface on the core clock, for waiting
  protected int unsigned stale_b[bit [9:0]];
  protected int unsigned stale_r[bit [9:0]];
  protected time         stale_until;
  protected int unsigned n_wr_os;
  protected int unsigned n_rd_os;
  protected uvm_event    done_ev;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
    done_ev = new("done_ev");
  endfunction

  function int unsigned outstanding();
    return n_wr_os + n_rd_os;
  endfunction

  static function bit [1:0] dl_of(int unsigned bytes);
    if (bytes <= 32) return AOU_DL_256;
    if (bytes == 64) return AOU_DL_512;
    return AOU_DL_1024;
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      accept(req);
      seq_item_port.item_done();
    end
  endtask

  protected task accept(aou_axi_txn t);
    if (t.data_bytes != cfg.data_bytes)
      `uvm_fatal(get_type_name(), $sformatf("txn data_bytes %0d != cfg data_bytes %0d",
                                            t.data_bytes, cfg.data_bytes))
    t.rp = cfg.rp;
    t.local_side = 1'b0;
    while (is_stale(t.dir == AOU_AXI_RD, t.id)) @(clk_vif.mon_cb);
    t.t_addr = $time;
    if (t.dir == AOU_AXI_WR) begin
      while (n_wr_os >= cfg.max_wr_outstanding) done_ev.wait_trigger();
      send_write(t);
      wr_q[t.id].push_back(t);
      n_wr_os++;
    end else begin
      while (n_rd_os >= cfg.max_rd_outstanding) done_ev.wait_trigger();
      t.data = new[t.beats()];
      t.rresp = new[t.beats()];
      send_read(t);
      rd_q[t.id].push_back(t);
      rd_beat[t.id].push_back(0);
      n_rd_os++;
    end
  endtask

  protected function void fill_req(aou_msg_req m, aou_axi_txn t);
    m.rp = wire_rp;
    m.id = t.id;
    m.addr = t.addr;
    m.len = t.len;
    m.size = t.size;
    m.lock = t.lock;
    m.cache = t.cache;
    m.prot = t.prot;
    m.qos = t.qos;
  endfunction

  protected function void send_write(aou_axi_txn t);
    aou_msg_wreq wq = aou_msg_wreq::type_id::create("wreq");
    int unsigned mb = (t.beat_bytes() < 32) ? 32 : t.beat_bytes();
    bit [127:0] all;
    if (wreq_mode == AOU_RWREQ_DUT_LIKE) mb = cfg.data_bytes;
    if (wreq_mode == AOU_RWREQ_UPSIZE && !t.lock && t.cache[1] &&
        t.beat_bytes() < cfg.data_bytes) begin
      send_write_upsized(t);
      return;
    end
    all = {128{1'b1}} >> (128 - mb);
    fill_req(wq, t);
    l3.send(wq);
    for (int unsigned i = 0; i < t.beats(); i++) begin
      aou_msg_wdata wd = aou_msg_wdata::type_id::create("wdata");
      wd.rp = wire_rp;
      wd.dlength = dl_of(mb);
      if (mb == cfg.data_bytes) begin
        wd.data = t.data[i];
        wd.strb = t.strb[i] & all;
      end else begin
        // Move the active lanes from our bus to the narrower message's lanes.
        wd.data = '0;
        wd.strb = '0;
        for (int unsigned l = t.lane_lo(i); l <= t.lane_hi(i); l++) begin
          int unsigned m = int'((t.beat_base(i) + 64'(l)) % 64'(mb));
          wd.data[8*m +: 8] = t.data[i][8*l +: 8];
          wd.strb[m] = t.strb[i][l];
        end
      end
      if (wd.strb == all && $urandom_range(99) < full_pct) wd.set_full(1'b1);
      l3.send(wd);
    end
  endfunction

  // t as a WriteReq of our bus size: the same bytes, in beats of the bus from
  // t's (possibly unaligned) start to its end, strobes on t's bytes only.
  protected function void send_write_upsized(aou_axi_txn t);
    aou_msg_wreq wq = aou_msg_wreq::type_id::create("wreq");
    bit [7:0] b[bit [63:0]];
    int unsigned bb = cfg.data_bytes;
    bit [63:0] base = t.addr & ~(64'(bb) - 64'd1);
    bit [63:0] stop = (t.addr & ~(64'(t.beat_bytes()) - 64'd1)) +
                      64'(t.beat_bytes()) * (64'(t.len) + 64'd1);
    int unsigned nbeats = int'((stop - base + 64'(bb) - 64'd1) / 64'(bb));
    bit [127:0] all = {128{1'b1}} >> (128 - bb);
    t.to_bytes(b);
    fill_req(wq, t);
    wq.size = 3'($clog2(bb));
    wq.len = 8'(nbeats - 1);
    l3.send(wq);
    for (int unsigned i = 0; i < nbeats; i++) begin
      aou_msg_wdata wd = aou_msg_wdata::type_id::create("wdata");
      wd.rp = wire_rp;
      wd.dlength = dl_of(bb);
      wd.data = '0;
      wd.strb = '0;
      for (int unsigned l = 0; l < bb; l++) begin
        bit [63:0] a = base + 64'(i * bb + l);
        if (b.exists(a)) begin
          wd.data[8*l +: 8] = b[a];
          wd.strb[l] = 1'b1;
        end
      end
      if (wd.strb == all && $urandom_range(99) < full_pct) wd.set_full(1'b1);
      l3.send(wd);
    end
  endfunction

  protected function void send_read(aou_axi_txn t);
    aou_msg_rreq rq = aou_msg_rreq::type_id::create("rreq");
    fill_req(rq, t);
    l3.send(rq);
  endfunction

  protected function void complete(aou_axi_txn t);
    t.t_done = $time;
    done_ev.trigger();
    ap.write(t);
    seq_item_port.put_response(t);
  endfunction

  // A DUT response on this plane.
  function void rsp_write(aou_msg m);
    aou_msg_wresp b;
    aou_msg_rdata d;
    if ($cast(b, m)) begin
      aou_axi_txn t;
      if (is_stale(1'b0, b.id)) begin
        stale_b[b.id]--;
        return;
      end
      if (!wr_q.exists(b.id) || wr_q[b.id].size() == 0) begin
        if (owes(1'b0, b.id)) begin
          stale_b[b.id]--;
          return;
        end
        `uvm_error(get_type_name(), $sformatf("T1-RM01: WriteResp with no write outstanding: %s",
                                              m.convert2string()))
        return;
      end
      t = wr_q[b.id].pop_front();
      t.bresp = b.resp;
      n_wr_os--;
      n_wr++;
      complete(t);
    end else if ($cast(d, m)) begin
      aou_axi_txn t;
      int unsigned i;
      int unsigned bus = aou_dl_bits(d.dlength) / 8;
      if (is_stale(1'b1, d.id)) begin
        if (d.last) stale_r[d.id]--;
        return;
      end
      if (!rd_q.exists(d.id) || rd_q[d.id].size() == 0) begin
        if (owes(1'b1, d.id)) begin
          if (d.last) stale_r[d.id]--;
          return;
        end
        `uvm_error(get_type_name(), $sformatf("T1-RM02: ReadData with no read outstanding: %s",
                                              m.convert2string()))
        return;
      end
      t = rd_q[d.id][0];
      i = rd_beat[d.id][0];
      if (i >= t.beats()) begin
        `uvm_error(get_type_name(), $sformatf("T1-RM03: ReadData beat %0d of a %0d-beat read: %s",
                                              i, t.beats(), t.convert2string()))
        return;
      end
      // Move each active lane from the DLENGTH-wide message to our bus lanes.
      t.data[i] = '0;
      for (int unsigned l = t.lane_lo(i); l <= t.lane_hi(i); l++) begin
        bit [63:0] a = t.beat_base(i) + 64'(l);
        t.data[i][8*l +: 8] = d.data[8*int'(a % 64'(bus)) +: 8];
      end
      t.rresp[i] = d.resp;
      rd_beat[d.id][0] = i + 1;
      if (d.last != (i + 1 == t.beats()))
        `uvm_error(get_type_name(), $sformatf("T1-RM04: RLAST=%0d on beat %0d of %0d: %s", d.last,
                                              i, t.beats(), t.convert2string()))
      if (d.last || i + 1 == t.beats()) begin
        void'(rd_q[d.id].pop_front());
        void'(rd_beat[d.id].pop_front());
        n_rd_os--;
        n_rd++;
        complete(t);
      end
    end
  endfunction

  // Reset contract: in-flight transactions end with aborted = 1 (returned to
  // their sequences and appended to `aborted` for the scoreboard); responses
  // the DUT still sends for them are dropped.
  function void reset_flush(ref aou_axi_txn aborted[$]);
    foreach (wr_q[id]) begin
      foreach (wr_q[id][k]) begin
        stale_b[id] = stale_b.exists(id) ? stale_b[id] + 1 : 1;
        abort(wr_q[id][k], aborted);
      end
    end
    foreach (rd_q[id]) begin
      foreach (rd_q[id][k]) begin
        stale_r[id] = stale_r.exists(id) ? stale_r[id] + 1 : 1;
        abort(rd_q[id][k], aborted);
      end
    end
    wr_q.delete();
    rd_q.delete();
    rd_beat.delete();
    n_wr_os = 0;
    n_rd_os = 0;
    stale_until = $time + stale_window;
    done_ev.trigger();
  endfunction

  // Within stale_window a response on an ID with a stale count is taken as
  // the stale one; after it, a stale count only absorbs a response nothing
  // else matches (a late answer to an aborted request).
  protected function bit is_stale(bit rd, bit [9:0] id);
    return $time <= stale_until && owes(rd, id);
  endfunction

  protected function bit owes(bit rd, bit [9:0] id);
    if (rd) return stale_r.exists(id) && stale_r[id] > 0;
    return stale_b.exists(id) && stale_b[id] > 0;
  endfunction

  protected function void abort(aou_axi_txn t, ref aou_axi_txn aborted[$]);
    t.aborted = 1'b1;
    t.t_done = $time;
    n_aborted++;
    aborted.push_back(t);
    seq_item_port.put_response(t);
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (outstanding() != 0)
      `uvm_error(get_type_name(), $sformatf("T1-RM05: %0d writes and %0d reads outstanding at end",
                                            n_wr_os, n_rd_os))
  endfunction
endclass
