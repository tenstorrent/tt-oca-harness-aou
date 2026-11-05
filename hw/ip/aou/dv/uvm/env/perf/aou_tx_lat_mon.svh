// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX per-message latency, the mirror of aou_rx_lat_mon, report only, from the
// DUT's ports. For every AXI message the DUT sends, in DUT clock cycles:
//   T_axi    the AXI handshake (VALID and READY) that carried the message's
//            payload into the DUT: the S-port AW/AR handshake of a
//            WriteReq/ReadReq, the S-port W handshake of a WriteData's beat,
//            the M-port B handshake of a WriteResp, the M-port R handshake of
//            a ReadData's beat
//   T_g      the FDI beat carrying the message's first granule transfers at
//            the DUT's TX pins (lp_valid & lp_irdy & pl_trdy; the L1 monitor's
//            aou_flit_item::t_beat[b] for the beat holding the granule)
//   T_flit   the first beat of the flit the message starts in (T_g when the
//            message starts in the first beat)
//   latency  T_g - T_axi, the figure reported; latency_flit T_flit - T_axi
// Messages are the L3 unpacker's decode of the DUT's flits (l3.ap_rx_msg, with
// start_flit and start_granule); the flit's beat times come from the L1
// monitor (fdi mon ap_tx), both in flit order, so start_flit indexes the n-th
// TX flit. The S-port monitors publish a local request when it completes,
// after its flit, so WriteReq/ReadReq/WriteData messages wait for their
// transaction; the M-port monitors publish a remote request at its B / RLAST
// handshake, before the DUT's WriteResp / ReadData flit, so those
// transactions wait for their messages. WriteData and
// ReadData beats pair one to one with messages when the remote die's bus is
// the RP's width (aou_perf_test's default); otherwise only the first beat.
// Reported per window and message kind (aw, ar, b, w256/w512/w1024,
// wf256/wf512/wf1024, r256/r512/r1024) through aou_perf_mon::put:
//   txlat.<window>.<kind>.{n,min,avg,max}  txlat_flit.<window>.<kind>.avg
//   txsg.<window>.<kind>.avg               the start granule (0 = G0)
// A message whose T_g falls inside the open window counts for it.
class aou_tx_lat_mon extends uvm_component;
  `uvm_component_utils(aou_tx_lat_mon)

  `uvm_analysis_imp_decl(_tx_flit)
  `uvm_analysis_imp_decl(_dut_msg)
  `uvm_analysis_imp_decl(_m_txn)
  `uvm_analysis_imp_decl(_s_txn)
  uvm_analysis_imp_tx_flit #(aou_flit_item, aou_tx_lat_mon) tx_flit_imp;  // fdi mon ap_tx
  uvm_analysis_imp_dut_msg #(aou_msg, aou_tx_lat_mon)       dut_msg_imp;  // l3.ap_rx_msg
  uvm_analysis_imp_m_txn #(aou_axi_txn, aou_tx_lat_mon)     m_txn_imp;    // M-port monitors
  uvm_analysis_imp_s_txn #(aou_axi_txn, aou_tx_lat_mon)     s_txn_imp;    // S-port monitors

  aou_perf_mon           perf;        // put() sink
  int unsigned           beat_bytes = 64;
  real                   clk_ns = 1.0;
  int unsigned           n_rp = AOU_T1_RP_COUNT;

  int unsigned n_msgs;       // DUT messages timed at the FDI
  int unsigned n_paired;
  int unsigned n_unpaired;   // messages no AXI handshake matched (end of test)
  int unsigned n_no_flit;    // messages whose flit the L1 monitor did not report

  // One DUT message waiting for the AXI handshake that produced it.
  typedef struct {
    string       kind;
    int unsigned rp;
    bit [9:0]    id;
    bit [63:0]   addr;
    int unsigned sg;         // start granule
    time         t_flit;
    time         t_g;
  } msg_t;

  protected aou_flit_item flits[int unsigned];          // by TX flit index
  protected int unsigned  n_flits;
  protected msg_t         req_q[AOU_RP_MAX][2][$];      // WriteReq (0) / ReadReq (1) per RP
  protected msg_t         wdata_q[AOU_RP_MAX][$];        // WriteData, in order per RP
  protected msg_t         wresp_q[AOU_RP_MAX][$];
  protected msg_t         rdata_q[AOU_RP_MAX][bit [9:0]][$];

  // M-port transactions waiting for their WriteResp / ReadData messages.
  typedef struct {
    aou_axi_txn  t;
    int unsigned beat;       // next R beat to pair
  } pend_t;
  protected pend_t        m_pend[AOU_RP_MAX][$];

  // Window samples, per kind.
  protected string  win;
  protected time    t_open;
  protected real    lat_sum[string];
  protected real    lat_flit_sum[string];
  protected real    sg_sum[string];
  protected real    lat_min[string];
  protected real    lat_max[string];
  protected int unsigned lat_n[string];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_flit_imp = new("tx_flit_imp", this);
    dut_msg_imp = new("dut_msg_imp", this);
    m_txn_imp = new("m_txn_imp", this);
    s_txn_imp = new("s_txn_imp", this);
  endfunction

  function real cycles(time t);
    return real'(t) / (clk_ns * 1ns);
  endfunction

  // The transfer time of granule g of a sent flit.
  function time t_granule(aou_flit_item f, int unsigned g);
    int unsigned b = (aou_granule_byte(g) + 4) / beat_bytes;
    return (b < FLIT_BYTES/32) ? f.t_beat[b] : f.t_end;
  endfunction

  // ---- FDI side -----------------------------------------------------------
  function void write_tx_flit(aou_flit_item it);
    flits[n_flits] = it;
    n_flits++;
  endfunction

  function void write_dut_msg(aou_msg am);
    msg_t m;
    aou_flit_item f;
    if (am.cred_class() == AOU_CC_NONE || am.start_flit < 0 || am.start_granule < 0) return;
    m.kind = aou_rx_lat_mon::kind_of(am);
    if (m.kind == "" || int'(am.rp) >= n_rp || int'(am.rp) >= AOU_RP_MAX) return;
    if (!flits.exists(am.start_flit)) begin
      n_no_flit++;
      return;
    end
    f = flits[am.start_flit];
    m.rp = int'(am.rp);
    m.sg = am.start_granule;
    m.t_flit = f.t_beat[0];
    m.t_g = t_granule(f, am.start_granule);
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
    case (am.cred_class())
      AOU_CC_WREQ:  req_q[m.rp][0].push_back(m);
      AOU_CC_RREQ:  req_q[m.rp][1].push_back(m);
      AOU_CC_WDATA: wdata_q[m.rp].push_back(m);
      AOU_CC_WRESP: if (!pair_pending(m)) wresp_q[m.rp].push_back(m);
      AOU_CC_RDATA: if (!pair_pending(m)) rdata_q[m.rp][m.id].push_back(m);
      default: ;
    endcase
    // Flits older than this one are no longer needed.
    foreach (flits[i]) if (i + 64 < am.start_flit) flits.delete(i);
  endfunction

  // ---- AXI side -----------------------------------------------------------
  // A local request at the S port: its AW/AR handshake made the WriteReq /
  // ReadReq at the message's address and ID; its W beats made the WriteData
  // messages queued for the RP, in order.
  function void write_s_txn(aou_axi_txn t);
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

  // A WriteResp / ReadData message against the M-port transactions already
  // published for its RP and ID: the oldest whose handshake precedes the flit.
  protected function bit pair_pending(msg_t m);
    foreach (m_pend[m.rp][i]) begin
      aou_axi_txn t = m_pend[m.rp][i].t;
      if (t.id != m.id) continue;
      if (m.kind == "b") begin
        if (t.dir != AOU_AXI_WR || t.t_done > m.t_flit) continue;
        m_pend[m.rp].delete(i);
        measure(m, t.t_done);
        return 1;
      end
      if (t.dir != AOU_AXI_RD) continue;
      begin
        int unsigned j = m_pend[m.rp][i].beat;
        if (j >= t.t_r.size() || t.t_r[j] > m.t_flit) continue;
        measure(m, t.t_r[j]);
        if (j + 1 >= t.t_r.size()) m_pend[m.rp].delete(i);
        else m_pend[m.rp][i].beat = j + 1;
        return 1;
      end
    end
    return 0;
  endfunction

  // A remote request served at the M port: its B handshake made the WriteResp
  // of its ID, its R beats the ReadData messages of its ID, in order. Usually
  // it arrives before its messages and waits for them.
  function void write_m_txn(aou_axi_txn t);
    int unsigned r = t.rp;
    pend_t p;
    if (t.aborted || r >= AOU_RP_MAX) return;
    p.t = t;
    p.beat = 0;
    if (t.dir == AOU_AXI_WR) begin
      foreach (wresp_q[r][i]) begin
        if (wresp_q[r][i].id == t.id && wresp_q[r][i].t_flit >= t.t_done) begin
          msg_t m = wresp_q[r][i];
          wresp_q[r].delete(i);
          measure(m, t.t_done);
          return;
        end
      end
      m_pend[r].push_back(p);
      return;
    end
    if (rdata_q[r].exists(t.id)) begin
      while (p.beat < t.t_r.size() && rdata_q[r][t.id].size() > 0 &&
             rdata_q[r][t.id][0].t_flit >= t.t_r[p.beat]) begin
        msg_t m = rdata_q[r][t.id].pop_front();
        measure(m, t.t_r[p.beat]);
        p.beat++;
      end
    end
    if (p.beat < t.t_r.size()) m_pend[r].push_back(p);
    // Pending transactions older than 4096 are stale (their messages were lost).
    while (m_pend[r].size() > 4096) begin
      void'(m_pend[r].pop_front());
      n_unpaired++;
    end
  endfunction

  // ---- measurement --------------------------------------------------------
  protected function void measure(msg_t m, time t_axi);
    real lat = cycles(m.t_g - t_axi);
    real lat_f = cycles(m.t_flit - t_axi);
    n_paired++;
    `uvm_info(get_type_name(), $sformatf("%s rp%0d g%0d: axi->granule %0.0f, axi->flit %0.0f",
                                         m.kind, m.rp, m.sg, lat, lat_f), UVM_HIGH)
    if (win == "" || m.t_g < t_open) return;
    if (!lat_n.exists(m.kind)) begin
      lat_n[m.kind] = 0;
      lat_sum[m.kind] = 0.0;
      lat_flit_sum[m.kind] = 0.0;
      sg_sum[m.kind] = 0.0;
      lat_min[m.kind] = lat;
      lat_max[m.kind] = lat;
    end
    lat_n[m.kind]++;
    lat_sum[m.kind] += lat;
    lat_flit_sum[m.kind] += lat_f;
    sg_sum[m.kind] += real'(m.sg);
    if (lat < lat_min[m.kind]) lat_min[m.kind] = lat;
    if (lat > lat_max[m.kind]) lat_max[m.kind] = lat;
  endfunction

  // ---- windows ------------------------------------------------------------
  function void open(string name);
    win = name;
    t_open = $time;
    lat_sum.delete();
    lat_flit_sum.delete();
    sg_sum.delete();
    lat_min.delete();
    lat_max.delete();
    lat_n.delete();
  endfunction

  function void close();
    if (win == "" || perf == null) return;
    foreach (lat_n[k]) begin
      perf.put({"txlat.", win, ".", k, ".n"}, real'(lat_n[k]));
      perf.put({"txlat.", win, ".", k, ".min"}, lat_min[k]);
      perf.put({"txlat.", win, ".", k, ".avg"}, lat_sum[k] / real'(lat_n[k]));
      perf.put({"txlat.", win, ".", k, ".max"}, lat_max[k]);
      perf.put({"txlat_flit.", win, ".", k, ".avg"}, lat_flit_sum[k] / real'(lat_n[k]));
      perf.put({"txsg.", win, ".", k, ".avg"}, sg_sum[k] / real'(lat_n[k]));
    end
    win = "";
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned left;
    foreach (req_q[r, k]) left += req_q[r][k].size();
    foreach (wdata_q[r]) left += wdata_q[r].size();
    foreach (wresp_q[r]) left += wresp_q[r].size();
    foreach (rdata_q[r, i]) left += rdata_q[r][i].size();
    foreach (m_pend[r]) left += m_pend[r].size();
    `uvm_info(get_type_name(), $sformatf(
              {"%0d DUT messages timed at the FDI, %0d paired with an AXI handshake, ",
               "%0d not timed, %0d never paired, %0d without a reported flit"},
              n_msgs, n_paired, n_unpaired, left, n_no_flit), UVM_LOW)
  endfunction
endclass
