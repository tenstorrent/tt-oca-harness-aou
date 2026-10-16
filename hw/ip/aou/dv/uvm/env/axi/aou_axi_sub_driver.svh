// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI4 subordinate: answers from cfg.mem. One cycle loop samples every channel at
// a clock edge and then drives the next cycle's outputs, so a response that
// becomes due at an edge (latency 0) is driven straight after that edge.
// Responses leave out of order across IDs (reorder_en) and in order within an ID.
class aou_axi_sub_driver extends uvm_component;
  `uvm_component_utils(aou_axi_sub_driver)

  aou_axi_cfg cfg;

  // Fault injection for checker self-tests: percentage of R beats with one data
  // bit flipped, of writes that never reach memory, and of cycles in which a
  // pending R beat's RVALID is withdrawn before RREADY (breaks AXI-R05).
  int unsigned fault_rdata_pct  = 0;
  int unsigned fault_wdrop_pct  = 0;
  int unsigned fault_rvalid_pct = 0;

  // Error injection: inject_orphan() queues a B, or a one-beat R with RLAST,
  // that answers no request (an AXI4 violation the DUT's ID-mismatch logic
  // must catch). It goes out when the channel is idle and is withdrawn if the
  // manager does not take it within orphan_hold cycles.
  int unsigned orphan_hold = 1000;
  int unsigned n_orphan_taken;
  int unsigned n_orphan_withdrawn;

  protected aou_axi_vif_t vif;
  protected longint unsigned cyc;

  protected bit aw_rdy, w_rdy, ar_rdy;
  protected int unsigned aw_cnt, w_cnt, ar_cnt;

  protected aou_axi_txn aw_q[$];   // AW accepted, W data not yet complete
  protected aou_axi_txn wb_q[$];   // complete W bursts whose AW has not arrived
  protected bit [1023:0] wd_q[$];  // beats of the W burst in progress
  protected bit [127:0]  ws_q[$];

  protected aou_axi_txn b_q[$];
  protected longint unsigned b_due[$];
  protected bit b_busy;
  protected int b_idx;

  protected aou_axi_txn r_q[$];
  protected longint unsigned r_due[$];
  protected int unsigned r_sent[$];
  protected bit r_busy;
  protected int r_idx;
  protected int r_burst = -1;      // burst in progress when R is not interleaved
  protected longint unsigned r_next;
  protected bit r_hidden;

  protected bit [9:0] orph_id[2][$];   // [0] B, [1] R
  protected bit [1:0] orph_resp[2][$];
  protected bit       orph_busy[2];
  protected int unsigned orph_age[2];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    vif = cfg.vif;
    if (cfg.mem == null) `uvm_fatal(get_type_name(), "cfg.mem is null")
  endfunction

  function int unsigned outstanding();
    return aw_q.size() + wb_q.size() + b_q.size() + r_q.size();
  endfunction

  function void inject_orphan(bit rd, bit [9:0] id, bit [1:0] resp);
    orph_id[rd].push_back(id);
    orph_resp[rd].push_back(resp);
  endfunction

  function int unsigned orphans_pending();
    return orph_id[0].size() + orph_id[1].size();
  endfunction

  task run_phase(uvm_phase phase);
    drive_idle();
    forever begin
      @(vif.sub_cb);
      cyc++;
      if (vif.sub_cb.resetn !== 1'b1) begin
        reset_state();
        drive_idle();
      end else begin
        sample();
        pair_writes();
        drive();
      end
    end
  endtask

  int unsigned n_aborted;

  // Reset contract: drop every request in progress (writes already in
  // memory stay there) and present idle outputs.
  function void reset_flush();
    n_aborted += outstanding();
    reset_state();
    drive_idle();
  endfunction

  protected function void reset_state();
    aw_q.delete();
    wb_q.delete();
    wd_q.delete();
    ws_q.delete();
    b_q.delete();
    b_due.delete();
    r_q.delete();
    r_due.delete();
    r_sent.delete();
    b_busy  = 1'b0;
    r_busy  = 1'b0;
    r_burst = -1;
    r_hidden = 1'b0;
    foreach (orph_busy[c]) begin
      orph_busy[c] = 1'b0;
      orph_id[c].delete();
      orph_resp[c].delete();
    end
    aw_cnt  = 0;
    w_cnt   = 0;
    ar_cnt  = 0;
    aw_rdy  = 1'b0;
    w_rdy   = 1'b0;
    ar_rdy  = 1'b0;
  endfunction

  protected function void drive_idle();
    vif.sub_cb.awready <= 1'b0;
    vif.sub_cb.wready  <= 1'b0;
    vif.sub_cb.arready <= 1'b0;
    vif.sub_cb.bvalid  <= 1'b0;
    vif.sub_cb.bid     <= '0;
    vif.sub_cb.bresp   <= '0;
    vif.sub_cb.rvalid  <= 1'b0;
    vif.sub_cb.rid     <= '0;
    vif.sub_cb.rdata   <= '0;
    vif.sub_cb.rresp   <= '0;
    vif.sub_cb.rlast   <= 1'b0;
  endfunction

  protected function aou_axi_txn new_req(aou_axi_dir_e dir);
    aou_axi_txn t = aou_axi_txn::type_id::create("req");
    t.dir        = dir;
    t.rp         = cfg.rp;
    t.local_side = cfg.local_side;
    t.data_bytes = cfg.data_bytes;
    t.t_addr     = $time;
    if (dir == AOU_AXI_WR) begin
      t.id    = vif.sub_cb.awid;
      t.addr  = vif.sub_cb.awaddr;
      t.len   = vif.sub_cb.awlen;
      t.size  = vif.sub_cb.awsize;
      t.burst = vif.sub_cb.awburst;
      t.lock  = vif.sub_cb.awlock;
      t.cache = vif.sub_cb.awcache;
      t.prot  = vif.sub_cb.awprot;
      t.qos   = vif.sub_cb.awqos;
    end else begin
      t.id    = vif.sub_cb.arid;
      t.addr  = vif.sub_cb.araddr;
      t.len   = vif.sub_cb.arlen;
      t.size  = vif.sub_cb.arsize;
      t.burst = vif.sub_cb.arburst;
      t.lock  = vif.sub_cb.arlock;
      t.cache = vif.sub_cb.arcache;
      t.prot  = vif.sub_cb.arprot;
      t.qos   = vif.sub_cb.arqos;
    end
    return t;
  endfunction

  protected function void sample();
    aou_axi_txn t;
    if (aw_rdy && vif.sub_cb.awvalid === 1'b1) begin
      aw_q.push_back(new_req(AOU_AXI_WR));
      aw_cnt = cfg.timing.aw_ready.next();
    end
    if (w_rdy && vif.sub_cb.wvalid === 1'b1) begin
      wd_q.push_back(vif.sub_cb.wdata);
      ws_q.push_back(vif.sub_cb.wstrb);
      if (vif.sub_cb.wlast === 1'b1) begin
        t = aou_axi_txn::type_id::create("t");
        t.data = new[wd_q.size()];
        t.strb = new[ws_q.size()];
        foreach (wd_q[k]) begin
          t.data[k] = wd_q[k];
          t.strb[k] = ws_q[k];
        end
        wd_q.delete();
        ws_q.delete();
        wb_q.push_back(t);
      end
      w_cnt = cfg.timing.w_ready.next();
    end
    for (int c = 0; c < 2; c++) begin
      if (orph_busy[c] && (c == 0 ? vif.sub_cb.bready : vif.sub_cb.rready) === 1'b1) begin
        orph_busy[c] = 1'b0;
        void'(orph_id[c].pop_front());
        void'(orph_resp[c].pop_front());
        n_orphan_taken++;
      end
    end
    if (b_busy && vif.sub_cb.bready === 1'b1) begin
      b_q.delete(b_idx);
      b_due.delete(b_idx);
      b_busy = 1'b0;
    end
    if (ar_rdy && vif.sub_cb.arvalid === 1'b1) begin
      t = new_req(AOU_AXI_RD);
      cfg.mem.axi_read_start(t, cfg.exclusive_en);
      r_q.push_back(t);
      r_due.push_back(cyc + 64'(cfg.timing.r_lat.next()));
      r_sent.push_back(0);
      ar_cnt = cfg.timing.ar_ready.next();
    end
    if (r_busy && !r_hidden && vif.sub_cb.rready === 1'b1) begin
      r_busy = 1'b0;
      r_sent[r_idx]++;
      r_burst = r_idx;
      if (r_sent[r_idx] == r_q[r_idx].beats()) begin
        r_q.delete(r_idx);
        r_due.delete(r_idx);
        r_sent.delete(r_idx);
        r_burst = -1;
      end
      if (cfg.r_interleave_en) r_burst = -1;
      r_next = cyc + 64'(cfg.timing.r_beat.next());
    end
  endfunction

  // W bursts pair with AWs in order; either may arrive first.
  protected function void pair_writes();
    aou_axi_txn t;
    aou_axi_txn w;
    while (aw_q.size() > 0 && wb_q.size() > 0) begin
      t = aw_q.pop_front();
      w = wb_q.pop_front();
      t.data = w.data;
      t.strb = w.strb;
      t.bresp = execute_write(t);
      b_q.push_back(t);
      b_due.push_back(cyc + 64'(cfg.timing.b_lat.next()));
    end
  endfunction

  protected function bit [1:0] execute_write(aou_axi_txn t);
    if (t.data.size() != t.beats())
      `uvm_error(get_type_name(), $sformatf("write has %0d W beats, AWLEN says %0d: %s",
                                            t.data.size(), t.beats(), t.convert2string()))
    if (fault_wdrop_pct > 0 && $urandom_range(99) < fault_wdrop_pct) return cfg.mem.txn_resp(t);
    return cfg.mem.axi_write(t, cfg.exclusive_en);
  endfunction

  // Index of the next response to send from q, or -1. Only the oldest entry of
  // each ID is eligible; reorder_en picks randomly among eligible entries.
  protected function int pick(ref aou_axi_txn q[$], ref longint unsigned due[$]);
    int cand[$];
    bit head;
    foreach (q[k]) begin
      head = 1'b1;
      for (int j = 0; j < k; j++) if (q[j].id == q[k].id) head = 1'b0;
      if (head && due[k] <= cyc) cand.push_back(k);
      if (!cfg.reorder_en) break;
    end
    if (cand.size() == 0) return -1;
    return cand[$urandom_range(cand.size() - 1)];
  endfunction

  protected function void drive();
    int k;
    aou_axi_txn t;
    bit [1023:0] d;
    bit [1:0] resp;
    int unsigned beat;

    aw_rdy = (aw_cnt == 0);
    if (!aw_rdy) aw_cnt--;
    w_rdy = (w_cnt == 0);
    if (!w_rdy) w_cnt--;
    ar_rdy = (ar_cnt == 0);
    if (!ar_rdy) ar_cnt--;
    if (cfg.hold_req) {aw_rdy, w_rdy, ar_rdy} = 3'b000;
    vif.sub_cb.awready <= aw_rdy;
    vif.sub_cb.wready  <= w_rdy;
    vif.sub_cb.arready <= ar_rdy;

    drive_orphan(0);
    if (!b_busy && !orph_busy[0]) begin
      k = pick(b_q, b_due);
      if (k >= 0) begin
        b_busy = 1'b1;
        b_idx  = k;
        vif.sub_cb.bid   <= b_q[k].id;
        vif.sub_cb.bresp <= b_q[k].bresp;
      end
      vif.sub_cb.bvalid <= b_busy;
    end

    if (!r_busy && r_burst < 0) drive_orphan(1);
    if (!r_busy && !orph_busy[1] && cyc >= r_next) begin
      k = (r_burst >= 0) ? r_burst : pick(r_q, r_due);
      if (k >= 0) begin
        t      = r_q[k];
        beat   = r_sent[k];
        r_busy = 1'b1;
        r_idx  = k;
        d      = cfg.mem.read_beat(t, beat);
        resp   = cfg.mem.axi_read_resp(t, beat, cfg.exclusive_en);
        if (fault_rdata_pct > 0 && $urandom_range(99) < fault_rdata_pct)
          d[8 * t.lane_lo(beat)] = ~d[8 * t.lane_lo(beat)];
        vif.sub_cb.rid   <= t.id;
        vif.sub_cb.rdata <= d;
        vif.sub_cb.rresp <= resp;
        vif.sub_cb.rlast <= (beat == t.beats() - 1);
      end
    end
    r_hidden = r_busy && fault_rvalid_pct > 0 && $urandom_range(99) < fault_rvalid_pct;
    if (!orph_busy[1]) vif.sub_cb.rvalid <= r_busy && !r_hidden;
  endfunction

  // Presents, holds or withdraws the head orphan of channel c (0 B, 1 R).
  protected function void drive_orphan(int c);
    if (orph_busy[c]) begin
      if (++orph_age[c] < orphan_hold) return;
      orph_busy[c] = 1'b0;
      void'(orph_id[c].pop_front());
      void'(orph_resp[c].pop_front());
      n_orphan_withdrawn++;
      if (c == 0) vif.sub_cb.bvalid <= 1'b0;
      else vif.sub_cb.rvalid <= 1'b0;
      return;
    end
    if (orph_id[c].size() == 0 || (c == 0 ? b_busy : r_busy)) return;
    orph_busy[c] = 1'b1;
    orph_age[c] = 0;
    if (c == 0) begin
      vif.sub_cb.bid    <= orph_id[0][0];
      vif.sub_cb.bresp  <= orph_resp[0][0];
      vif.sub_cb.bvalid <= 1'b1;
    end else begin
      vif.sub_cb.rid    <= orph_id[1][0];
      vif.sub_cb.rdata  <= '0;
      vif.sub_cb.rresp  <= orph_resp[1][0];
      vif.sub_cb.rlast  <= 1'b1;
      vif.sub_cb.rvalid <= 1'b1;
    end
  endfunction
endclass
