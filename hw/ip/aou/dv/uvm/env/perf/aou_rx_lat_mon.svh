// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// RX per-message latency (fdi-rx-plan 13), report only, from the DUT's ports:
// no internal probe, so the same monitor measures any RTL. For every AXI
// message the remote die sends, in DUT clock cycles:
//   T_first / T_last  the FDI beat carrying the message's first / last granule
//                     is delivered at the DUT's RX pins (the L1 monitor's
//                     flits after cancel rollback, aou_flit_item::t_beat,
//                     paired in order with the flits L3 built, whose messages
//                     and start granules are known)
//   T_out             the DUT presents the message on AXI: the M-port AW/AR
//                     handshake of a WriteReq/ReadReq (the burst at the
//                     message's address and ID), the M-port W handshake of a
//                     WriteData's beat, the S-port B handshake of a WriteResp,
//                     the S-port R handshake of a ReadData's beat. The windows
//                     run with READY high, so a handshake is the first VALID
//                     cycle; WriteData and ReadData beats pair one to one with
//                     AXI beats when the remote die's bus is the RP's width
//                     (aou_perf_test's default), otherwise only a write's or
//                     read's first beat is paired.
//   T_crd             the DUT's credit for the message's granules reaches the
//                     remote die (L3 credit manager tx_granted, polled per
//                     cycle; returned at pop in message order per RP and
//                     class, so credits retire the oldest presented messages)
//   latency           T_out - T_last; latency_first T_out - T_first; credit
//                     T_crd - T_out (negative when the AXI side is slower than
//                     the pop); rate messages presented per window cycle.
// Reported per window and message kind (aw, ar, b, w256/w512/w1024,
// wf256/wf512/wf1024, r256/r512/r1024) through aou_perf_mon::put:
//   rxlat.<window>.<kind>.{n,min,avg,max}  rxlat_first.<window>.<kind>.avg
//   rxcrd.<window>.<kind>.{avg,max}        rxrate.<window>.<kind>
//   rxsg.<window>.<kind>.avg               the start granule (0 = G0)
// A message whose T_out falls inside the open window counts for it.
// Messages the DUT splits (several M-port bursts) pair by their first burst
// only; a message that never pairs is counted (n_unpaired) and not measured.
class aou_rx_lat_mon extends uvm_component;
  `uvm_component_utils(aou_rx_lat_mon)

  `uvm_analysis_imp_decl(_l3_flit)
  `uvm_analysis_imp_decl(_rx_flit)
  `uvm_analysis_imp_decl(_m_txn)
  `uvm_analysis_imp_decl(_s_txn)
  uvm_analysis_imp_l3_flit #(aou_l3_flit_item, aou_rx_lat_mon) l3_flit_imp;  // l3.ap_tx_flit
  uvm_analysis_imp_rx_flit #(aou_flit_item, aou_rx_lat_mon)    rx_flit_imp;  // fdi mon ap_rx
  uvm_analysis_imp_m_txn #(aou_axi_txn, aou_rx_lat_mon)        m_txn_imp;    // M-port monitors
  uvm_analysis_imp_s_txn #(aou_axi_txn, aou_rx_lat_mon)        s_txn_imp;    // S-port monitors

  aou_perf_mon           perf;        // put() sink
  aou_l3_agent           l3;          // credit counters
  virtual aou_fdi_lsm_if vif;         // core clock
  int unsigned           beat_bytes = 64;
  real                   clk_ns = 1.0;
  int unsigned           n_rp = AOU_T1_RP_COUNT;

  int unsigned n_msgs;       // messages timed at the FDI
  int unsigned n_paired;
  int unsigned n_unpaired;   // messages the AXI side never matched (end of test)
  int unsigned n_dropped_flits;  // L3 flits L1 never delivered to the DUT

  // One remote message waiting for its AXI handshake.
  typedef struct {
    string     kind;
    int unsigned rp;
    aou_cred_class_e cc;
    int unsigned granules;
    int unsigned sg;         // start granule
    bit [9:0]  id;
    bit [63:0] addr;
    time       t_first;
    time       t_last;
  } msg_t;

  // Measured: presented messages waiting for their credit, per RP and class.
  typedef struct {
    string kind;
    int unsigned granules;
    time   t_last;
    time   t_out;
  } done_t;

  protected aou_l3_flit_item l3_q[$];      // flits built, not yet delivered
  protected aou_flit_item    rx_q[$];      // flits delivered, not yet paired
  protected msg_t            carry[$];     // messages whose last granule is in the next flit
  protected int unsigned     carry_g[$];   // ...and that granule's index there
  protected msg_t            req_q[AOU_RP_MAX][2][$];   // WriteReq (0) / ReadReq (1) per RP
  protected msg_t            wdata_q[AOU_RP_MAX][$];     // WriteData, in order per RP
  protected msg_t            wresp_q[AOU_RP_MAX][$];
  protected msg_t            rdata_q[AOU_RP_MAX][bit [9:0]][$];
  protected done_t           done_q[AOU_RP_MAX][AOU_CC_NUM][$];
  protected int unsigned     crd_seen[AOU_RP_MAX][AOU_CC_NUM];
  protected int unsigned     crd_acc[AOU_RP_MAX][AOU_CC_NUM];

  // Window samples, per kind.
  protected string  win;
  protected time    t_open;
  protected real    lat_sum[string];
  protected real    lat_first_sum[string];
  protected real    sg_sum[string];
  protected real    lat_min[string];
  protected real    lat_max[string];
  protected int unsigned lat_n[string];
  protected real    crd_sum[string];
  protected real    crd_max[string];
  protected int unsigned crd_n[string];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    l3_flit_imp = new("l3_flit_imp", this);
    rx_flit_imp = new("rx_flit_imp", this);
    m_txn_imp = new("m_txn_imp", this);
    s_txn_imp = new("s_txn_imp", this);
  endfunction

  function real cycles(time t);
    return real'(t) / (clk_ns * 1ns);
  endfunction

  // ---- FDI side -----------------------------------------------------------
  function void write_l3_flit(aou_l3_flit_item it);
    if (it.flit == null) return;
    l3_q.push_back(it);
    pair_flits();
  endfunction

  function void write_rx_flit(aou_flit_item it);
    rx_q.push_back(it);
    pair_flits();
  endfunction

  // The delivery time of granule g of a delivered flit.
  function time t_granule(aou_flit_item f, int unsigned g);
    int unsigned b = (aou_granule_byte(g) + 4) / beat_bytes;
    return (b < FLIT_BYTES/32) ? f.t_beat[b] : f.t_end;
  endfunction

  static function string kind_of(aou_msg m);
    aou_msg_wdata wd;
    aou_msg_rdata rd;
    case (m.msg_type)
      AOU_MT_WREQ:  return "aw";
      AOU_MT_RREQ:  return "ar";
      AOU_MT_WRESP: return "b";
      AOU_MT_WDATA, AOU_MT_WDATAF:
        if ($cast(wd, m)) return $sformatf("%s%0d", (m.msg_type == AOU_MT_WDATAF) ? "wf" : "w",
                                           aou_dl_bits(wd.dlength));
      AOU_MT_RDATA:
        if ($cast(rd, m)) return $sformatf("r%0d", aou_dl_bits(rd.dlength));
      default: ;
    endcase
    return "";
  endfunction

  static function bit same_bytes(aou_l3_flit_item lf, aou_flit_item rf);
    foreach (lf.bytes[i]) if (lf.bytes[i] != rf.data[i]) return 0;
    return 1;
  endfunction

  // Flits are delivered in the order L3 built them; one L1 did not deliver
  // (sent before the link was active) is skipped by its bytes.
  protected function void pair_flits();
    while (l3_q.size() > 0 && rx_q.size() > 0) begin
      aou_l3_flit_item lf;
      aou_flit_item rf = rx_q.pop_front();
      aou_flit f;
      while (l3_q.size() > 0 && !same_bytes(l3_q[0], rf)) begin
        void'(l3_q.pop_front());
        carry.delete();
        carry_g.delete();
        n_dropped_flits++;
      end
      if (l3_q.size() == 0) break;
      lf = l3_q.pop_front();
      f = lf.flit;
      // Messages that began in the previous flit end here.
      while (carry.size() > 0) begin
        msg_t m = carry.pop_front();
        int unsigned g = carry_g.pop_front();
        m.t_last = t_granule(rf, g);
        queue_msg(m);
      end
      foreach (f.msgs[i]) begin
        aou_msg am = f.msgs[i];
        msg_t m;
        int unsigned n = am.num_granules();
        int unsigned last;
        if (am.cred_class() == AOU_CC_NONE || am.start_granule < 0) continue;
        m.kind = kind_of(am);
        if (m.kind == "" || int'(am.rp) >= n_rp || int'(am.rp) >= AOU_RP_MAX) continue;
        m.rp = int'(am.rp);
        m.cc = am.cred_class();
        m.granules = n;
        m.sg = am.start_granule;
        m.t_first = t_granule(rf, am.start_granule);
        last = am.start_granule + n - 1;
        case (am.msg_type)
          AOU_MT_WREQ, AOU_MT_RREQ: begin
            aou_msg_req rq;
            if ($cast(rq, am)) begin
              m.id = rq.id;
              m.addr = rq.addr;
            end
          end
          AOU_MT_WRESP: begin
            aou_msg_wresp b;
            if ($cast(b, am)) m.id = b.id;
          end
          AOU_MT_RDATA: begin
            aou_msg_rdata d;
            if ($cast(d, am)) m.id = d.id;
          end
          default: ;
        endcase
        n_msgs++;
        if (last < AOU_GRANULES) begin
          m.t_last = t_granule(rf, last);
          queue_msg(m);
        end else begin
          carry.push_back(m);
          carry_g.push_back(last - AOU_GRANULES);
        end
      end
    end
  endfunction

  protected function void queue_msg(msg_t m);
    case (m.cc)
      AOU_CC_WREQ:  req_q[m.rp][0].push_back(m);
      AOU_CC_RREQ:  req_q[m.rp][1].push_back(m);
      AOU_CC_WDATA: wdata_q[m.rp].push_back(m);
      AOU_CC_WRESP: wresp_q[m.rp].push_back(m);
      AOU_CC_RDATA: rdata_q[m.rp][m.id].push_back(m);
      default: ;
    endcase
  endfunction

  // ---- AXI side -----------------------------------------------------------
  // A remote request at the M port: the burst at the message's address and ID
  // (a split request's later bursts match nothing). Its W beats pair with the
  // WriteData messages queued for the RP, in order.
  function void write_m_txn(aou_axi_txn t);
    int k = (t.dir == AOU_AXI_WR) ? 0 : 1;
    int unsigned r = t.rp;
    if (t.aborted || r >= AOU_RP_MAX) return;
    foreach (req_q[r][k][i]) begin
      if (req_q[r][k][i].id == t.id && req_q[r][k][i].addr == t.addr) begin
        msg_t m = req_q[r][k][i];
        req_q[r][k].delete(i);
        measure(m, t.t_addr);
        break;
      end
    end
    if (t.dir != AOU_AXI_WR || t.t_w.size() == 0) return;
    // WriteData: the oldest queued messages of this RP, one per W beat when
    // the counts agree (equal widths), else the first beat only.
    if (wdata_q[r].size() >= t.t_w.size() && t.t_w.size() == t.beats()) begin
      foreach (t.t_w[j]) begin
        msg_t m = wdata_q[r].pop_front();
        measure(m, t.t_w[j]);
      end
    end else if (wdata_q[r].size() > 0) begin
      int unsigned n = (wdata_q[r].size() < t.beats()) ? wdata_q[r].size() : t.beats();
      msg_t m = wdata_q[r].pop_front();
      measure(m, t.t_w[0]);
      for (int unsigned j = 1; j < n && wdata_q[r].size() > 0; j++) begin
        void'(wdata_q[r].pop_front());   // merged or split beats: not timed
        n_unpaired++;
      end
    end
  endfunction

  // A local request completing at the S port: its B is a WriteResp, its R
  // beats are ReadData messages of its ID, in order.
  function void write_s_txn(aou_axi_txn t);
    int unsigned r = t.rp;
    if (t.aborted || r >= AOU_RP_MAX) return;
    if (t.dir == AOU_AXI_WR) begin
      foreach (wresp_q[r][i]) begin
        if (wresp_q[r][i].id == t.id) begin
          msg_t m = wresp_q[r][i];
          wresp_q[r].delete(i);
          measure(m, t.t_done);
          break;
        end
      end
      return;
    end
    if (!rdata_q[r].exists(t.id) || rdata_q[r][t.id].size() == 0 || t.t_r.size() == 0) return;
    if (rdata_q[r][t.id].size() >= t.beats() && t.t_r.size() == t.beats() &&
        rdata_q[r][t.id][t.beats()-1].t_last <= t.t_r[t.beats()-1]) begin
      for (int unsigned j = 0; j < t.beats(); j++) begin
        msg_t m = rdata_q[r][t.id].pop_front();
        measure(m, t.t_r[j]);
      end
    end else begin
      // Width converted (beats and messages differ): the first beat only, and
      // the rest of this read's messages are dropped by their RLAST.
      msg_t m = rdata_q[r][t.id].pop_front();
      measure(m, t.t_r[0]);
      while (rdata_q[r][t.id].size() > 0 && rdata_q[r][t.id][0].t_last <= t.t_done) begin
        void'(rdata_q[r][t.id].pop_front());
        n_unpaired++;
      end
    end
  endfunction

  // ---- measurement --------------------------------------------------------
  protected function void measure(msg_t m, time t_out);
    done_t d;
    real lat = cycles(t_out - m.t_last);
    real lat_f = cycles(t_out - m.t_first);
    n_paired++;
    d.kind = m.kind;
    d.granules = m.granules;
    d.t_last = m.t_last;
    d.t_out = t_out;
    done_q[m.rp][m.cc].push_back(d);
    if (win == "" || t_out < t_open) return;
    if (!lat_n.exists(m.kind)) begin
      lat_n[m.kind] = 0;
      lat_sum[m.kind] = 0.0;
      lat_first_sum[m.kind] = 0.0;
      sg_sum[m.kind] = 0.0;
      lat_min[m.kind] = lat;
      lat_max[m.kind] = lat;
    end
    lat_n[m.kind]++;
    lat_sum[m.kind] += lat;
    lat_first_sum[m.kind] += lat_f;
    sg_sum[m.kind] += real'(m.sg);
    if (lat < lat_min[m.kind]) lat_min[m.kind] = lat;
    if (lat > lat_max[m.kind]) lat_max[m.kind] = lat;
  endfunction

  protected function void credit(int unsigned r, int c, time now);
    while (done_q[r][c].size() > 0 && crd_acc[r][c] >= done_q[r][c][0].granules) begin
      done_t d = done_q[r][c].pop_front();
      real v = cycles(now - d.t_out);
      crd_acc[r][c] -= d.granules;
      if (win == "" || d.t_out < t_open) continue;
      if (!crd_n.exists(d.kind)) begin
        crd_n[d.kind] = 0;
        crd_sum[d.kind] = 0.0;
        crd_max[d.kind] = v;
      end
      crd_n[d.kind]++;
      crd_sum[d.kind] += v;
      if (v > crd_max[d.kind]) crd_max[d.kind] = v;
    end
  endfunction

  // Credit the DUT returned since the last poll retires presented messages.
  protected function void poll_credits();
    if (l3 == null) return;
    for (int unsigned r = 0; r < n_rp && r < AOU_RP_MAX; r++) begin
      for (int c = 0; c < AOU_CC_NUM; c++) begin
        int unsigned g = l3.model.crd.tx_granted[r][c];
        if (g != crd_seen[r][c]) begin
          crd_acc[r][c] += g - crd_seen[r][c];
          crd_seen[r][c] = g;
          credit(r, c, $time);
        end
      end
    end
  endfunction

  task run_phase(uvm_phase phase);
    if (vif == null) return;
    forever begin
      @(vif.mon_cb);
      poll_credits();
    end
  endtask

  // ---- windows ------------------------------------------------------------
  function void open(string name);
    win = name;
    t_open = $time;
    lat_sum.delete();
    lat_first_sum.delete();
    sg_sum.delete();
    lat_min.delete();
    lat_max.delete();
    lat_n.delete();
    crd_sum.delete();
    crd_max.delete();
    crd_n.delete();
  endfunction

  function void close();
    real cyc = cycles($time - t_open);
    if (win == "" || perf == null) return;
    foreach (lat_n[k]) begin
      perf.put({"rxlat.", win, ".", k, ".n"}, real'(lat_n[k]));
      perf.put({"rxlat.", win, ".", k, ".min"}, lat_min[k]);
      perf.put({"rxlat.", win, ".", k, ".avg"}, lat_sum[k] / real'(lat_n[k]));
      perf.put({"rxlat.", win, ".", k, ".max"}, lat_max[k]);
      perf.put({"rxlat_first.", win, ".", k, ".avg"}, lat_first_sum[k] / real'(lat_n[k]));
      perf.put({"rxsg.", win, ".", k, ".avg"}, sg_sum[k] / real'(lat_n[k]));
      if (cyc > 0.0) perf.put({"rxrate.", win, ".", k}, real'(lat_n[k]) / cyc);
    end
    foreach (crd_n[k]) begin
      perf.put({"rxcrd.", win, ".", k, ".avg"}, crd_sum[k] / real'(crd_n[k]));
      perf.put({"rxcrd.", win, ".", k, ".max"}, crd_max[k]);
    end
    win = "";
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned left;
    foreach (req_q[r, k]) left += req_q[r][k].size();
    foreach (wdata_q[r]) left += wdata_q[r].size();
    foreach (wresp_q[r]) left += wresp_q[r].size();
    // Not foreach (rdata_q[r, i]): Verilator 5.052 emits first()/next() on the
    // outer unpacked array of an unpacked-of-associative and fails to compile.
    foreach (rdata_q[r]) begin
      bit [9:0] id;
      if (rdata_q[r].first(id) != 0)
        do left += rdata_q[r][id].size(); while (rdata_q[r].next(id) != 0);
    end
    `uvm_info(get_type_name(), $sformatf(
              {"%0d remote messages timed at the FDI, %0d paired with an AXI handshake, ",
               "%0d not timed, %0d never paired, %0d source flits not delivered"},
              n_msgs, n_paired, n_unpaired, left, n_dropped_flits), UVM_LOW)
  endfunction
endclass
