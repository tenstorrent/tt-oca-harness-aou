// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Rebuilds complete transactions from the pins and publishes them on ap: a
// write after its B handshake, a read after its last R beat. W bursts pair with
// AWs in order whichever comes first. With cfg.checks_en it also checks the
// protocol rules AXI-R01..R18 (checkers/rules.csv), all from mon_cb samples.
class aou_axi_monitor extends uvm_monitor;
  `uvm_component_utils(aou_axi_monitor)

  aou_axi_cfg cfg;
  uvm_analysis_port #(aou_axi_txn) ap;

  int unsigned n_wr;
  int unsigned n_rd;
  int unsigned n_b_zero;  // B valid in the cycle after the write's last AW/W handshake
  int unsigned n_r_zero;  // first R valid in the cycle after the AR handshake

  protected aou_axi_vif_t vif;
  protected longint unsigned cyc;
  protected bit [1023:0] data_mask;
  protected bit [127:0]  strb_mask;

  protected aou_axi_mon_item aw_q[$];   // AW seen, W burst not complete
  protected aou_axi_mon_item wb_q[$];   // complete W bursts with no AW yet
  protected bit [1023:0]     wd_q[$];   // W burst in progress
  protected bit [127:0]      ws_q[$];
  protected aou_axi_mon_item b_q[$];    // waiting for B
  protected aou_axi_mon_item r_q[$];    // waiting for R
  // Responses still owed for transactions a reset aborted (reset_flush):
  // within stale_window the next response on such an ID is the stale one.
  time                   stale_window = 10us;
  protected int unsigned stale_b[bit [9:0]];
  protected int unsigned stale_r[bit [9:0]];
  protected time         stale_until;
  int unsigned n_aborted;
  // sw_reset_window(): open while software requests AOU_SW_RESET.
  protected bit          rst_win;
  // W bursts begun before the request whose AW has not been seen yet.
  protected int unsigned rst_w_first;

  protected longint unsigned b_start;
  protected longint unsigned r_start;

  // Previous cycle, for the handshake stability rules.
  protected logic        p_awvalid, p_awready, p_wvalid, p_wready, p_bvalid, p_bready;
  protected logic        p_arvalid, p_arready, p_rvalid, p_rready;
  protected logic [98:0] p_aw, p_ar;
  protected logic [1152:0] p_w;
  protected logic [11:0] p_b;
  protected logic [1036:0] p_r;

  // Sampled values for the covergroups.
  protected bit       cv_is_rd;
  protected bit [2:0] cv_size;
  protected bit [1:0] cv_len_bkt;
  protected bit       cv_unaligned;
  protected bit       cv_zero;

  covergroup txn_cg;
    cp_dir: coverpoint cv_is_rd {
      `AOU_AXI_FC_DIR(AOU_FC_CG)
    }
    cp_size: coverpoint cv_size {
      `AOU_AXI_FC_SIZE(AOU_FC_CG)
    }
    cp_len: coverpoint cv_len_bkt {
      `AOU_AXI_FC_LEN(AOU_FC_CG)
    }
    cp_align: coverpoint cv_unaligned {
      `AOU_AXI_FC_ALIGN(AOU_FC_CG)
    }
    x_txn: cross cp_dir, cp_size, cp_len, cp_align;
  endgroup

  // #64: B presented zero cycles after the AW/W handshakes; R likewise after AR.
  covergroup zero_cg;
    cp_dir: coverpoint cv_is_rd {
      `AOU_AXI_FC_DIR(AOU_FC_CG)
    }
    cp_zero: coverpoint cv_zero {
      `AOU_AXI_FC_ZERO(AOU_FC_CG)
    }
    x_zero: cross cp_dir, cp_zero;
  endgroup

  // The service's copies of the covergroups above, shared by every monitor.
  protected aou_fc_group fc_txn;
  protected aou_fc_group fc_zero;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap      = new("ap", this);
    txn_cg  = new();
    zero_cg = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_txn = db.group("axi.txn_cg", fresh);
    if (fresh) begin
      p = fc_txn.cp("cp_dir"); `AOU_AXI_FC_DIR(AOU_FC_REG)
      p = fc_txn.cp("cp_size"); `AOU_AXI_FC_SIZE(AOU_FC_REG)
      p = fc_txn.cp("cp_len"); `AOU_AXI_FC_LEN(AOU_FC_REG)
      p = fc_txn.cp("cp_align"); `AOU_AXI_FC_ALIGN(AOU_FC_REG)
      p = fc_txn.add_cross("x_txn", "cp_dir cp_size cp_len cp_align");
      `AOU_AXI_FC_X_TXN(AOU_FC_REG)
    end
    fc_zero = db.group("axi.zero_cg", fresh);
    if (fresh) begin
      p = fc_zero.cp("cp_dir"); `AOU_AXI_FC_DIR(AOU_FC_REG)
      p = fc_zero.cp("cp_zero"); `AOU_AXI_FC_ZERO(AOU_FC_REG)
      void'(fc_zero.add_cross("x_zero", "cp_dir cp_zero"));
    end
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    vif       = cfg.vif;
    data_mask = {1024{1'b1}} >> (1024 - 8 * cfg.data_bytes);
    strb_mask = {128{1'b1}} >> (128 - cfg.data_bytes);
  endfunction

  function int unsigned outstanding();
    return aw_q.size() + wb_q.size() + b_q.size() + r_q.size() + (wd_q.size() > 0);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      cyc++;
      if (vif.mon_cb.resetn !== 1'b1) begin
        clear();
      end else begin
        if (cfg.checks_en) check_stable();
        sample_cycle();
        save_prev();
      end
    end
  endtask

  function void check_phase(uvm_phase phase);
    if (cfg.checks_en && live_outstanding() > 0)
      `uvm_error(get_type_name(), $sformatf({"AXI-R17: at end of test %0d AW without W, ",
          "%0d W without AW, %0d W beats, %0d writes without B, %0d reads without RLAST"},
          aw_q.size(), wb_q.size(), wd_q.size(), b_q.size(), r_q.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        "%0d writes, %0d reads, %0d zero-cycle B, %0d zero-cycle R", n_wr, n_rd, n_b_zero,
        n_r_zero), UVM_LOW)
  endfunction

  // Reset contract. bus_reset (the port's own reset): forget in-flight
  // transactions without publishing them, drop responses the DUT still sends
  // for them (stale_window), and don't judge the handshakes the reset cut
  // short. Otherwise (AOU_SW_RESET; the bus is not reset) they stay tracked
  // and are published if they complete, but may never complete, so the end
  // of test does not count them as missing.
  function void reset_flush(bit bus_reset = 1'b1);
    if (!bus_reset) begin
      foreach (aw_q[k]) aw_q[k].txn.aborted = 1'b1;
      foreach (b_q[k]) b_q[k].txn.aborted = 1'b1;
      foreach (r_q[k]) r_q[k].txn.aborted = 1'b1;
      n_aborted += aw_q.size() + b_q.size() + r_q.size();
      return;
    end
    foreach (b_q[k]) stale_b[b_q[k].txn.id] = stale_b.exists(b_q[k].txn.id) ?
                                              stale_b[b_q[k].txn.id] + 1 : 1;
    foreach (r_q[k]) stale_r[r_q[k].txn.id] = stale_r.exists(r_q[k].txn.id) ?
                                              stale_r[r_q[k].txn.id] + 1 : 1;
    n_aborted += outstanding();
    stale_until = $time + stale_window;
    clear();
  endfunction

  // Opened just before the APB write that requests AOU_SW_RESET and closed when
  // it completes: every transaction already on the bus, or whose first
  // handshake falls inside the window, is marked reset_outstanding.
  function void sw_reset_window(bit open);
    rst_win = open;
    if (!open) return;
    foreach (aw_q[k]) aw_q[k].txn.reset_outstanding = 1'b1;
    foreach (b_q[k]) b_q[k].txn.reset_outstanding = 1'b1;
    foreach (r_q[k]) r_q[k].txn.reset_outstanding = 1'b1;
    // W bursts pair with AWs in order, so aw_q and wb_q are never both
    // non-empty; with aw_q empty every burst begun belongs to a later AW.
    rst_w_first = aw_q.size() != 0 ? 0 : wb_q.size() + (wd_q.size() > 0);
  endfunction

  // In-flight transactions no reset has made optional.
  function int unsigned live_outstanding();
    int unsigned n = wb_q.size() + (wd_q.size() > 0);
    foreach (aw_q[k]) if (!aw_q[k].txn.aborted) n++;
    foreach (b_q[k]) if (!b_q[k].txn.aborted) n++;
    foreach (r_q[k]) if (!r_q[k].txn.aborted) n++;
    return n;
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

  protected function void clear();
    aw_q.delete();
    wb_q.delete();
    wd_q.delete();
    ws_q.delete();
    b_q.delete();
    r_q.delete();
    rst_w_first = 0;
    p_awvalid = 1'b0;
    p_wvalid  = 1'b0;
    p_bvalid  = 1'b0;
    p_arvalid = 1'b0;
    p_rvalid  = 1'b0;
  endfunction

  protected function logic [98:0] aw_payload();
    return {vif.mon_cb.awid, vif.mon_cb.awaddr, vif.mon_cb.awlen, vif.mon_cb.awsize,
            vif.mon_cb.awburst, vif.mon_cb.awlock, vif.mon_cb.awcache, vif.mon_cb.awprot,
            vif.mon_cb.awqos};
  endfunction

  protected function logic [98:0] ar_payload();
    return {vif.mon_cb.arid, vif.mon_cb.araddr, vif.mon_cb.arlen, vif.mon_cb.arsize,
            vif.mon_cb.arburst, vif.mon_cb.arlock, vif.mon_cb.arcache, vif.mon_cb.arprot,
            vif.mon_cb.arqos};
  endfunction

  protected function logic [1152:0] w_payload();
    return {vif.mon_cb.wdata, vif.mon_cb.wstrb, vif.mon_cb.wlast};
  endfunction

  protected function logic [11:0] b_payload();
    return {vif.mon_cb.bid, vif.mon_cb.bresp};
  endfunction

  protected function logic [1036:0] r_payload();
    return {vif.mon_cb.rid, vif.mon_cb.rdata, vif.mon_cb.rresp, vif.mon_cb.rlast};
  endfunction

  protected function void save_prev();
    p_awvalid = vif.mon_cb.awvalid;
    p_awready = vif.mon_cb.awready;
    p_wvalid  = vif.mon_cb.wvalid;
    p_wready  = vif.mon_cb.wready;
    p_bvalid  = vif.mon_cb.bvalid;
    p_bready  = vif.mon_cb.bready;
    p_arvalid = vif.mon_cb.arvalid;
    p_arready = vif.mon_cb.arready;
    p_rvalid  = vif.mon_cb.rvalid;
    p_rready  = vif.mon_cb.rready;
    p_aw      = aw_payload();
    p_ar      = ar_payload();
    p_w       = w_payload();
    p_b       = b_payload();
    p_r       = r_payload();
  endfunction

  // Once VALID is high it stays high, with a stable payload, until READY.
  protected function void check_stable();
    if ($isunknown({vif.mon_cb.awvalid, vif.mon_cb.wvalid, vif.mon_cb.bvalid,
                    vif.mon_cb.arvalid, vif.mon_cb.rvalid}))
      `uvm_error(get_type_name(), "AXI-R18: a VALID signal is X or Z out of reset")
    if (p_awvalid === 1'b1 && p_awready !== 1'b1 &&
        (vif.mon_cb.awvalid !== 1'b1 || aw_payload() !== p_aw))
      `uvm_error(get_type_name(), "AXI-R01: AWVALID dropped or AW payload changed before AWREADY")
    if (p_wvalid === 1'b1 && p_wready !== 1'b1 &&
        (vif.mon_cb.wvalid !== 1'b1 || w_payload() !== p_w))
      `uvm_error(get_type_name(), "AXI-R02: WVALID dropped or W payload changed before WREADY")
    if (p_bvalid === 1'b1 && p_bready !== 1'b1 &&
        (vif.mon_cb.bvalid !== 1'b1 || b_payload() !== p_b))
      `uvm_error(get_type_name(), "AXI-R03: BVALID dropped or B payload changed before BREADY")
    if (p_arvalid === 1'b1 && p_arready !== 1'b1 &&
        (vif.mon_cb.arvalid !== 1'b1 || ar_payload() !== p_ar))
      `uvm_error(get_type_name(), "AXI-R04: ARVALID dropped or AR payload changed before ARREADY")
    if (p_rvalid === 1'b1 && p_rready !== 1'b1 &&
        (vif.mon_cb.rvalid !== 1'b1 || r_payload() !== p_r))
      `uvm_error(get_type_name(), "AXI-R05: RVALID dropped or R payload changed before RREADY")
  endfunction

  protected function void sample_cycle();
    if (vif.mon_cb.bvalid === 1'b1 && !(p_bvalid === 1'b1 && p_bready !== 1'b1)) b_start = cyc;
    if (vif.mon_cb.rvalid === 1'b1 && !(p_rvalid === 1'b1 && p_rready !== 1'b1)) r_start = cyc;
    if (vif.mon_cb.awvalid === 1'b1 && vif.mon_cb.awready === 1'b1) on_aw();
    if (vif.mon_cb.wvalid === 1'b1 && vif.mon_cb.wready === 1'b1) on_w();
    pair_writes();
    if (vif.mon_cb.bvalid === 1'b1 && vif.mon_cb.bready === 1'b1) on_b();
    if (vif.mon_cb.arvalid === 1'b1 && vif.mon_cb.arready === 1'b1) on_ar();
    if (vif.mon_cb.rvalid === 1'b1 && vif.mon_cb.rready === 1'b1) on_r();
  endfunction

  protected function aou_axi_mon_item new_item(aou_axi_dir_e dir);
    aou_axi_mon_item it = aou_axi_mon_item::type_id::create("it");
    aou_axi_txn t = aou_axi_txn::type_id::create("txn");
    t.dir        = dir;
    t.rp         = cfg.rp;
    t.local_side = cfg.local_side;
    t.data_bytes = cfg.data_bytes;
    t.t_addr     = $time;
    t.reset_outstanding = rst_win;
    it.txn       = t;
    it.addr_cyc  = cyc;
    return it;
  endfunction

  protected function void on_aw();
    aou_axi_mon_item it = new_item(AOU_AXI_WR);
    it.txn.id    = vif.mon_cb.awid;
    it.txn.addr  = vif.mon_cb.awaddr;
    it.txn.len   = vif.mon_cb.awlen;
    it.txn.size  = vif.mon_cb.awsize;
    it.txn.burst = vif.mon_cb.awburst;
    it.txn.lock  = vif.mon_cb.awlock;
    it.txn.cache = vif.mon_cb.awcache;
    it.txn.prot  = vif.mon_cb.awprot;
    it.txn.qos   = vif.mon_cb.awqos;
    if (rst_w_first > 0) begin
      it.txn.reset_outstanding = 1'b1;
      rst_w_first--;
    end
    check_addr(it.txn, "AW");
    aw_q.push_back(it);
  endfunction

  protected function void on_ar();
    aou_axi_mon_item it = new_item(AOU_AXI_RD);
    it.txn.id    = vif.mon_cb.arid;
    it.txn.addr  = vif.mon_cb.araddr;
    it.txn.len   = vif.mon_cb.arlen;
    it.txn.size  = vif.mon_cb.arsize;
    it.txn.burst = vif.mon_cb.arburst;
    it.txn.lock  = vif.mon_cb.arlock;
    it.txn.cache = vif.mon_cb.arcache;
    it.txn.prot  = vif.mon_cb.arprot;
    it.txn.qos   = vif.mon_cb.arqos;
    it.txn.data  = new[it.txn.beats()];
    it.txn.rresp = new[it.txn.beats()];
    check_addr(it.txn, "AR");
    r_q.push_back(it);
  endfunction

  protected function void check_addr(aou_axi_txn t, string ch);
    int unsigned total;
    if (!cfg.checks_en) return;
    if (t.burst == 2'b11)
      `uvm_error(get_type_name(), $sformatf("AXI-R12: %s burst type is reserved: %s", ch,
                                            t.convert2string()))
    else if (cfg.incr_only && t.burst != AOU_AXI_INCR)
      `uvm_error(get_type_name(), $sformatf(
          "AXI-R19: %s burst type %0d on an INCR-only port (test stimulus error): %s", ch,
          t.burst, t.convert2string()))
    if ((32'd1 << t.size) > cfg.data_bytes)
      `uvm_error(get_type_name(), $sformatf("AXI-R13: %s size %0d is wider than the %0d-byte bus",
                                            ch, t.size, cfg.data_bytes))
    if (t.crosses_4k())
      `uvm_error(get_type_name(), $sformatf("AXI-R10: %s INCR burst crosses 4KB: %s", ch,
                                            t.convert2string()))
    if (t.burst == AOU_AXI_WRAP &&
        (!(t.len inside {8'd1, 8'd3, 8'd7, 8'd15}) || (t.addr & (64'(t.beat_bytes()) - 1)) != 0))
      `uvm_error(get_type_name(), $sformatf(
          "AXI-R11: %s WRAP needs len 2/4/8/16 and an aligned start: %s", ch, t.convert2string()))
    if (t.burst == AOU_AXI_FIXED && t.len > 15)
      `uvm_error(get_type_name(), $sformatf("AXI-R14: %s FIXED burst longer than 16 beats: %s", ch,
                                            t.convert2string()))
    if (t.lock) begin
      total = t.beats() * t.beat_bytes();
      if (total > 128 || (total & (total - 1)) != 0 || t.len > 15 ||
          (t.addr & (64'(total) - 1)) != 0)
        `uvm_error(get_type_name(), $sformatf(
            "AXI-R15: %s exclusive access must be 2^n bytes up to 128, aligned, 16 beats max: %s",
            ch, t.convert2string()))
    end
  endfunction

  protected function void on_w();
    aou_axi_mon_item it;
    if (rst_win && wd_q.size() == 0 && aw_q.size() == 0) rst_w_first++;
    wd_q.push_back(vif.mon_cb.wdata & data_mask);
    ws_q.push_back(vif.mon_cb.wstrb);
    // The burst in progress belongs to the first AW still without W data.
    if (cfg.checks_en && aw_q.size() > wb_q.size() && wb_q.size() == 0 &&
        wd_q.size() == aw_q[0].txn.beats() + 1)
      `uvm_error(get_type_name(), $sformatf("AXI-R06: W burst runs past AWLEN without WLAST: %s",
                                            aw_q[0].txn.convert2string()))
    if (vif.mon_cb.wlast === 1'b1) begin
      it = aou_axi_mon_item::type_id::create("it");
      it.txn = aou_axi_txn::type_id::create("txn");
      it.txn.data = new[wd_q.size()];
      it.txn.strb = new[ws_q.size()];
      foreach (wd_q[k]) begin
        it.txn.data[k] = wd_q[k];
        it.txn.strb[k] = ws_q[k];
      end
      it.w_cyc = cyc;
      wd_q.delete();
      ws_q.delete();
      wb_q.push_back(it);
    end
  endfunction

  protected function void pair_writes();
    aou_axi_mon_item it;
    aou_axi_mon_item w;
    while (aw_q.size() > 0 && wb_q.size() > 0) begin
      it = aw_q.pop_front();
      w  = wb_q.pop_front();
      it.txn.data = w.txn.data;
      it.txn.strb = w.txn.strb;
      it.w_cyc    = w.w_cyc;
      if (cfg.checks_en) begin
        if (it.txn.data.size() != it.txn.beats())
          `uvm_error(get_type_name(), $sformatf(
              "AXI-R06: WLAST after %0d beats, AWLEN says %0d: %s", it.txn.data.size(),
              it.txn.beats(), it.txn.convert2string()))
        foreach (it.txn.strb[i]) begin
          if ((it.txn.strb[i] & ~(it.txn.lane_mask(i) & strb_mask)) != '0)
            `uvm_error(get_type_name(), $sformatf(
                "AXI-R16: WSTRB %0h on inactive lanes in beat %0d (active %0d..%0d): %s",
                it.txn.strb[i], i, it.txn.lane_lo(i), it.txn.lane_hi(i), it.txn.convert2string()))
        end
      end
      b_q.push_back(it);
    end
  endfunction

  protected function void on_b();
    aou_axi_mon_item it;
    bit [9:0] id = vif.mon_cb.bid;
    longint unsigned last_hs;
    if (is_stale(1'b0, id)) begin
      stale_b[id]--;
      return;
    end
    foreach (b_q[k]) begin
      if (b_q[k].txn.id == id) begin
        it = b_q[k];
        b_q.delete(k);
        it.txn.bresp  = vif.mon_cb.bresp;
        it.txn.t_done = $time;
        last_hs = it.addr_cyc > it.w_cyc ? it.addr_cyc : it.w_cyc;
        if (b_start == last_hs + 1) n_b_zero++;
        if (cfg.cov_en) sample_zero(1'b0, b_start == last_hs + 1);
        publish(it.txn);
        n_wr++;
        return;
      end
    end
    if (owes(1'b0, id)) begin
      stale_b[id]--;
      return;
    end
    if (cfg.checks_en)
      `uvm_error(get_type_name(), $sformatf(
          "AXI-R07: B ID %0h matches no write whose AW and last W handshakes are done", id))
  endfunction

  protected function void on_r();
    aou_axi_mon_item it;
    bit [9:0] id = vif.mon_cb.rid;
    bit last;
    if (is_stale(1'b1, id)) begin
      if (vif.mon_cb.rlast === 1'b1) stale_r[id]--;
      return;
    end
    foreach (r_q[k]) begin
      if (r_q[k].txn.id == id) begin
        it = r_q[k];
        if (it.beats == 0) it.first_cyc = r_start;
        if (it.beats < it.txn.beats()) begin
          it.txn.data[it.beats]  = vif.mon_cb.rdata & data_mask;
          it.txn.rresp[it.beats] = vif.mon_cb.rresp;
        end
        it.beats++;
        last = (it.beats >= it.txn.beats());
        if (cfg.checks_en && (vif.mon_cb.rlast === 1'b1) != last)
          `uvm_error(get_type_name(), $sformatf("AXI-R09: RLAST=%0b on beat %0d of %0d: %s",
                                                vif.mon_cb.rlast, it.beats, it.txn.beats(),
                                                it.txn.convert2string()))
        if (last || vif.mon_cb.rlast === 1'b1) begin
          r_q.delete(k);
          it.txn.t_done = $time;
          if (it.first_cyc == it.addr_cyc + 1) n_r_zero++;
          if (cfg.cov_en) sample_zero(1'b1, it.first_cyc == it.addr_cyc + 1);
          publish(it.txn);
          n_rd++;
        end
        return;
      end
    end
    if (owes(1'b1, id)) begin
      if (vif.mon_cb.rlast === 1'b1) stale_r[id]--;
      return;
    end
    if (cfg.checks_en)
      `uvm_error(get_type_name(), $sformatf("AXI-R08: R ID %0h matches no outstanding read", id))
  endfunction

  protected function void sample_zero(bit is_rd, bit zero);
    cv_is_rd = is_rd;
    cv_zero  = zero;
    zero_cg.sample();
    fc_zero.sample(int'(cv_is_rd), int'(cv_zero));
  endfunction

  protected function void publish(aou_axi_txn t);
    if (cfg.cov_en) begin
      cv_is_rd     = (t.dir == AOU_AXI_RD);
      cv_size      = t.size;
      cv_len_bkt   = t.len == 0 ? 2'd0 : t.len < 4 ? 2'd1 : t.len < 16 ? 2'd2 : 2'd3;
      cv_unaligned = (t.addr & (64'(t.beat_bytes()) - 1)) != 0;
      txn_cg.sample();
      fc_txn.sample(int'(cv_is_rd), int'(cv_size), int'(cv_len_bkt), int'(cv_unaligned));
    end
    `uvm_info(get_type_name(), t.convert2string(), UVM_HIGH)
    ap.write(t);
  endfunction
endclass
