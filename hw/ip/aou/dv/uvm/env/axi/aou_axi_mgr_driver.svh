// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI4 manager driver. Each channel runs in its own thread, so AW, W and AR
// proceed independently up to the outstanding limits. item_done() returns once
// a transaction is queued; the completed transaction (B or R filled in) comes
// back through put_response().
class aou_axi_mgr_driver extends uvm_driver #(aou_axi_txn);
  `uvm_component_utils(aou_axi_mgr_driver)

  aou_axi_cfg cfg;

  protected aou_axi_vif_t vif;
  protected mailbox #(aou_axi_mgr_item) aw_mb;
  protected mailbox #(aou_axi_mgr_item) w_mb;
  protected mailbox #(aou_axi_mgr_item) ar_mb;
  protected aou_axi_mgr_item wr_os[$];
  protected aou_axi_mgr_item rd_os[$];
  protected semaphore wr_tok;
  protected semaphore rd_tok;
  protected bit [1023:0] data_mask;
  protected bit [127:0]  strb_mask;
  // Responses still owed for transactions a reset aborted, per ID. Whether
  // the DUT still answers them after a software reset is unspecified, so for
  // stale_window after the flush a response on such an ID is taken to be the
  // stale one (AXI keeps responses in order per ID) and dropped, and new
  // transactions on that ID wait until it has come or the window has passed.
  // An entry is null once its transaction has gone back to the sequence. A
  // software reset's flush cannot take back a request that is presented but
  // not yet handed over: it reaches the DUT after the reset and really
  // executes. Such a transaction goes back only when its stale response is
  // dropped (or the window passes), so its sequence keeps the addresses
  // reserved meanwhile and cannot issue an overlapping transaction.
  time                   stale_window = 10us;
  protected aou_axi_mgr_item stale_b[bit [9:0]][$];
  protected aou_axi_mgr_item stale_r[bit [9:0]][$];
  protected int unsigned stale_held;
  protected time         stale_until;
  protected uvm_event    flush_ev;
  int unsigned           n_aborted;
  // 1: no new transaction reaches the bus (the local software has stopped
  // issuing, MAS software-operation 7.3.5). A write whose AW or W has started
  // still finishes, and responses are still taken.
  bit                    hold_new = 1'b0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aw_mb = new();
    w_mb  = new();
    ar_mb = new();
    flush_ev = new("flush_ev");
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    vif       = cfg.vif;
    wr_tok    = new(cfg.max_wr_outstanding);
    rd_tok    = new(cfg.max_rd_outstanding);
    data_mask = {1024{1'b1}} >> (1024 - 8 * cfg.data_bytes);
    strb_mask = {128{1'b1}} >> (128 - cfg.data_bytes);
  endfunction

  task run_phase(uvm_phase phase);
    idle_outputs();
    @(vif.mgr_cb);
    while (vif.mgr_cb.resetn !== 1'b1) @(vif.mgr_cb);
    fork
      forever begin
        fork
          begin
            fork
              aw_loop();
              w_loop();
              ar_loop();
              b_loop();
              r_loop();
            join_none
            flush_ev.wait_trigger();
            disable fork;
          end
        join
        idle_outputs();
        // A flush on I_RESETN comes at its assertion: restart once it is over.
        @(vif.mgr_cb);
        while (vif.mgr_cb.resetn !== 1'b1) @(vif.mgr_cb);
      end
    join_none
    forever begin
      seq_item_port.get_next_item(req);
      accept(req);
      seq_item_port.item_done();
    end
  endtask

  function int unsigned outstanding();
    return wr_os.size() + rd_os.size();
  endfunction

  // Transactions whose request has reached the bus and that await a response.
  function int unsigned issued();
    int unsigned n = 0;
    foreach (wr_os[k]) if (wr_os[k].addr_started || wr_os[k].w_started) n++;
    foreach (rd_os[k]) if (rd_os[k].addr_started) n++;
    return n;
  endfunction

  // Transactions on the bus whose request (AW and every W beat, or AR) has
  // not been fully handed over yet.
  function int unsigned issuing();
    int unsigned n = 0;
    foreach (wr_os[k])
      if ((wr_os[k].addr_started || wr_os[k].w_started) && !(wr_os[k].addr_done && wr_os[k].w_done))
        n++;
    foreach (rd_os[k]) if (rd_os[k].addr_started && !rd_os[k].addr_done) n++;
    return n;
  endfunction

  // Reset contract: every queued or in-flight transaction ends now with
  // aborted = 1 (returned through put_response so sequences continue and
  // appended to `aborted` for the scoreboard). Items that never reached the
  // bus are dropped; responses the DUT still sends for the others are dropped
  // too (stale_window). bus_reset (the port's own reset, I_RESETN): the
  // channel threads also restart with idle outputs once the reset is over.
  // Otherwise (AOU_SW_RESET: the bus itself is not reset) a burst whose AW or
  // W has started is still driven to completion, as AXI requires.
  function void reset_flush(ref aou_axi_txn aborted[$], input bit bus_reset = 1'b1);
    aou_axi_mgr_item it;
    aou_axi_mgr_item aw_l[$];
    aou_axi_mgr_item w_l[$];
    while (aw_mb.try_get(it) != 0) aw_l.push_back(it);
    while (w_mb.try_get(it) != 0) w_l.push_back(it);
    while (ar_mb.try_get(it) != 0) it.untouched = 1'b1;
    foreach (aw_l[i]) foreach (w_l[j]) if (aw_l[i] == w_l[j]) aw_l[i].untouched = 1'b1;
    if (!bus_reset) begin
      // A burst with its AW or its W already on the bus must finish.
      foreach (aw_l[i]) if (!aw_l[i].untouched) void'(aw_mb.try_put(aw_l[i]));
      foreach (w_l[j]) if (!w_l[j].untouched) void'(w_mb.try_put(w_l[j]));
    end
    foreach (wr_os[k]) begin
      it = wr_os[k];
      if (!it.untouched && (!bus_reset || (it.addr_done && it.w_done))) begin
        if (!bus_reset && !(it.addr_done && it.w_done)) begin
          hold(it, aborted);
          stale_b[it.txn.id].push_back(it);
          continue;
        end
        stale_b[it.txn.id].push_back(null);
      end
      abort(it.txn, aborted);
      wr_tok.put(1);
    end
    foreach (rd_os[k]) begin
      it = rd_os[k];
      if (!it.untouched && (!bus_reset || it.addr_done)) begin
        if (!bus_reset && !it.addr_done) begin
          hold(it, aborted);
          stale_r[it.txn.id].push_back(it);
          continue;
        end
        stale_r[it.txn.id].push_back(null);
      end
      abort(it.txn, aborted);
      rd_tok.put(1);
    end
    wr_os.delete();
    rd_os.delete();
    stale_until = $time + stale_window;
    if (bus_reset) flush_ev.trigger();
  endfunction

  // Within stale_window a response on an ID with a stale count is taken as
  // the stale one; after it, a stale count only absorbs a response nothing
  // else matches (a late answer to an aborted request).
  protected function bit is_stale(bit rd, bit [9:0] id);
    return $time <= stale_until && owes(rd, id);
  endfunction

  protected function bit owes(bit rd, bit [9:0] id);
    if (rd) return stale_r.exists(id) && stale_r[id].size() > 0;
    return stale_b.exists(id) && stale_b[id].size() > 0;
  endfunction

  // The stale response for the oldest aborted transaction on id has come.
  protected function void drop_stale(bit rd, bit [9:0] id);
    aou_axi_mgr_item it = rd ? stale_r[id].pop_front() : stale_b[id].pop_front();
    if (it != null) release_held(it, rd);
  endfunction

  protected function void abort(aou_axi_txn t, ref aou_axi_txn aborted[$]);
    t.aborted = 1'b1;
    t.t_done = $time;
    n_aborted++;
    aborted.push_back(t);
    seq_item_port.put_response(t);
  endfunction

  // Aborted for the scoreboard now, returned to the sequence by release_held().
  protected function void hold(aou_axi_mgr_item it, ref aou_axi_txn aborted[$]);
    it.txn.aborted = 1'b1;
    n_aborted++;
    aborted.push_back(it.txn);
    stale_held++;
  endfunction

  protected function void release_held(aou_axi_mgr_item it, bit rd);
    it.txn.t_done = $time;
    stale_held--;
    seq_item_port.put_response(it.txn);
    if (rd) rd_tok.put(1);
    else wr_tok.put(1);
  endfunction

  // The window has passed: held transactions go back without their response.
  protected function void release_expired();
    foreach (stale_b[id]) foreach (stale_b[id][k]) if (stale_b[id][k] != null) begin
      release_held(stale_b[id][k], 1'b0);
      stale_b[id][k] = null;
    end
    foreach (stale_r[id]) foreach (stale_r[id][k]) if (stale_r[id][k] != null) begin
      release_held(stale_r[id][k], 1'b1);
      stale_r[id][k] = null;
    end
  endfunction

  protected task accept(aou_axi_txn t);
    aou_axi_mgr_item it = aou_axi_mgr_item::type_id::create("it");
    if (t.data_bytes != cfg.data_bytes)
      `uvm_fatal(get_type_name(), $sformatf("txn data_bytes %0d != cfg data_bytes %0d",
                                            t.data_bytes, cfg.data_bytes))
    t.rp         = cfg.rp;
    t.local_side = cfg.local_side;
    it.txn       = t;
    while (is_stale(t.dir == AOU_AXI_RD, t.id)) @(vif.mgr_cb);
    if (t.dir == AOU_AXI_WR) begin
      if (t.data.size() != t.beats() || t.strb.size() != t.beats())
        `uvm_fatal(get_type_name(), $sformatf("write needs %0d data/strb beats: %s",
                                              t.beats(), t.convert2string()))
      wr_tok.get(1);
      wr_os.push_back(it);
      aw_mb.put(it);
      w_mb.put(it);
    end else begin
      t.data  = new[t.beats()];
      t.rresp = new[t.beats()];
      rd_tok.get(1);
      rd_os.push_back(it);
      ar_mb.put(it);
    end
  endtask

  protected task wait_cycles(int unsigned n);
    repeat (n) @(vif.mgr_cb);
  endtask

  protected function void idle_outputs();
    vif.mgr_cb.awvalid <= 1'b0;
    vif.mgr_cb.wvalid  <= 1'b0;
    vif.mgr_cb.arvalid <= 1'b0;
    vif.mgr_cb.bready  <= 1'b0;
    vif.mgr_cb.rready  <= 1'b0;
    vif.mgr_cb.awid    <= '0;
    vif.mgr_cb.awaddr  <= '0;
    vif.mgr_cb.awlen   <= '0;
    vif.mgr_cb.awsize  <= '0;
    vif.mgr_cb.awburst <= '0;
    vif.mgr_cb.awlock  <= '0;
    vif.mgr_cb.awcache <= '0;
    vif.mgr_cb.awprot  <= '0;
    vif.mgr_cb.awqos   <= '0;
    vif.mgr_cb.wdata   <= '0;
    vif.mgr_cb.wstrb   <= '0;
    vif.mgr_cb.wlast   <= '0;
    vif.mgr_cb.arid    <= '0;
    vif.mgr_cb.araddr  <= '0;
    vif.mgr_cb.arlen   <= '0;
    vif.mgr_cb.arsize  <= '0;
    vif.mgr_cb.arburst <= '0;
    vif.mgr_cb.arlock  <= '0;
    vif.mgr_cb.arcache <= '0;
    vif.mgr_cb.arprot  <= '0;
    vif.mgr_cb.arqos   <= '0;
  endfunction

  // Every loop polls its mailbox at a clock edge, so a drive always lands right
  // after an edge and the next edge samples the handshake.
  protected task aw_loop();
    aou_axi_mgr_item it;
    int unsigned d;
    forever begin
      while (aw_mb.try_peek(it) == 0 || (hold_new && !it.w_started)) @(vif.mgr_cb);
      void'(aw_mb.try_get(it));
      it.addr_started = 1'b1;
      d = cfg.timing.aw_valid.next();
      if (d > 0) begin
        vif.mgr_cb.awvalid <= 1'b0;
        wait_cycles(d);
      end
      vif.mgr_cb.awid    <= it.txn.id;
      vif.mgr_cb.awaddr  <= it.txn.addr;
      vif.mgr_cb.awlen   <= it.txn.len;
      vif.mgr_cb.awsize  <= it.txn.size;
      vif.mgr_cb.awburst <= it.txn.burst;
      vif.mgr_cb.awlock  <= it.txn.lock;
      vif.mgr_cb.awcache <= it.txn.cache;
      vif.mgr_cb.awprot  <= it.txn.prot;
      vif.mgr_cb.awqos   <= it.txn.qos;
      vif.mgr_cb.awvalid <= 1'b1;
      do @(vif.mgr_cb); while (vif.mgr_cb.awready !== 1'b1);
      it.txn.t_addr = $time;
      it.addr_done  = 1'b1;
      vif.mgr_cb.awvalid <= 1'b0;
    end
  endtask

  protected task ar_loop();
    aou_axi_mgr_item it;
    int unsigned d;
    forever begin
      while (hold_new || ar_mb.try_get(it) == 0) @(vif.mgr_cb);
      it.addr_started = 1'b1;
      d = cfg.timing.ar_valid.next();
      if (d > 0) begin
        vif.mgr_cb.arvalid <= 1'b0;
        wait_cycles(d);
      end
      vif.mgr_cb.arid    <= it.txn.id;
      vif.mgr_cb.araddr  <= it.txn.addr;
      vif.mgr_cb.arlen   <= it.txn.len;
      vif.mgr_cb.arsize  <= it.txn.size;
      vif.mgr_cb.arburst <= it.txn.burst;
      vif.mgr_cb.arlock  <= it.txn.lock;
      vif.mgr_cb.arcache <= it.txn.cache;
      vif.mgr_cb.arprot  <= it.txn.prot;
      vif.mgr_cb.arqos   <= it.txn.qos;
      vif.mgr_cb.arvalid <= 1'b1;
      do @(vif.mgr_cb); while (vif.mgr_cb.arready !== 1'b1);
      it.txn.t_addr = $time;
      it.addr_done  = 1'b1;
      vif.mgr_cb.arvalid <= 1'b0;
    end
  endtask

  protected task w_loop();
    aou_axi_mgr_item it;
    int unsigned d;
    forever begin
      while (w_mb.try_peek(it) == 0 || (hold_new && !it.addr_started)) @(vif.mgr_cb);
      void'(w_mb.try_get(it));
      it.w_started = 1'b1;
      if (!cfg.w_before_aw_en) while (!it.addr_done) @(vif.mgr_cb);
      for (int unsigned i = 0; i < it.txn.beats(); i++) begin
        d = cfg.timing.w_valid.next();
        if (d > 0) begin
          vif.mgr_cb.wvalid <= 1'b0;
          wait_cycles(d);
        end
        vif.mgr_cb.wdata  <= it.txn.data[i] & data_mask;
        vif.mgr_cb.wstrb  <= it.txn.strb[i] & strb_mask;
        vif.mgr_cb.wlast  <= (i == it.txn.beats() - 1);
        vif.mgr_cb.wvalid <= 1'b1;
        do @(vif.mgr_cb); while (vif.mgr_cb.wready !== 1'b1);
      end
      it.w_done = 1'b1;
      vif.mgr_cb.wvalid <= 1'b0;
    end
  endtask

  protected task b_loop();
    bit rdy;
    int unsigned cnt = 0;
    forever begin
      rdy = (cnt == 0);
      vif.mgr_cb.bready <= rdy;
      @(vif.mgr_cb);
      if (stale_held != 0 && $time > stale_until) release_expired();
      if (rdy && vif.mgr_cb.bvalid === 1'b1) begin
        complete_b(vif.mgr_cb.bid, vif.mgr_cb.bresp);
        cnt = cfg.timing.b_ready.next();
      end else if (cnt > 0) begin
        cnt--;
      end
    end
  endtask

  protected task r_loop();
    bit rdy;
    int unsigned cnt = 0;
    forever begin
      rdy = (cnt == 0);
      vif.mgr_cb.rready <= rdy;
      @(vif.mgr_cb);
      if (rdy && vif.mgr_cb.rvalid === 1'b1) begin
        complete_r(vif.mgr_cb.rid, vif.mgr_cb.rdata, vif.mgr_cb.rresp, vif.mgr_cb.rlast);
        cnt = cfg.timing.r_ready.next();
      end else if (cnt > 0) begin
        cnt--;
      end
    end
  endtask

  // Responses go to the oldest outstanding request with the same ID; protocol
  // violations are the monitor's to report.
  protected function void complete_b(bit [9:0] id, bit [1:0] resp);
    aou_axi_txn t;
    if (is_stale(1'b0, id)) begin
      drop_stale(1'b0, id);
      `uvm_info(get_type_name(), $sformatf("B ID %0h for a write a reset aborted; dropped", id),
                UVM_MEDIUM)
      return;
    end
    foreach (wr_os[k]) begin
      if (wr_os[k].txn.id == id && wr_os[k].addr_done && wr_os[k].w_done) begin
        t        = wr_os[k].txn;
        t.bresp  = resp;
        t.t_done = $time;
        wr_os.delete(k);
        wr_tok.put(1);
        seq_item_port.put_response(t);
        return;
      end
    end
    if (owes(1'b0, id)) begin
      drop_stale(1'b0, id);
      return;
    end
    `uvm_error(get_type_name(), $sformatf("B ID %0h matches no outstanding write", id))
  endfunction

  protected function void complete_r(bit [9:0] id, bit [1023:0] d, bit [1:0] resp, bit last);
    aou_axi_txn t;
    if (is_stale(1'b1, id)) begin
      if (last) drop_stale(1'b1, id);
      `uvm_info(get_type_name(), $sformatf("R ID %0h for a read a reset aborted; dropped", id),
                UVM_MEDIUM)
      return;
    end
    foreach (rd_os[k]) begin
      if (rd_os[k].txn.id == id && rd_os[k].addr_done) begin
        t = rd_os[k].txn;
        t.data[rd_os[k].beats_rcvd]  = d & data_mask;
        t.rresp[rd_os[k].beats_rcvd] = resp;
        rd_os[k].beats_rcvd++;
        if (last || rd_os[k].beats_rcvd == t.beats()) begin
          t.t_done = $time;
          rd_os.delete(k);
          rd_tok.put(1);
          seq_item_port.put_response(t);
        end
        return;
      end
    end
    if (owes(1'b1, id)) begin
      if (last) drop_stale(1'b1, id);
      return;
    end
    `uvm_error(get_type_name(), $sformatf("R ID %0h matches no outstanding read", id))
  endfunction
endclass
