// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Performance data (plan 2.10), report only: no thresholds. A window
// (open()/close()) collects the transactions completed in it (local S-port
// managers: l2r; remote-die managers: r2l), their bytes and latencies, the
// flits each way, and for single-outstanding windows the round-trip
// breakdown at FDI. Credit return delay (remote request put in a flit to the
// DUT granting that credit back, paired in order per RP and class from the
// window's start, when every earlier credit has come back) and TX drain time
// are measured per window. Every metric goes to perf.txt in the run directory
// ("metric value" per line) and to the log; T1-P01 fails a run whose
// windows produced no data.
//
// Per link (l2r: DUT TX, r2l: DUT RX) a window also measures the payload the
// link carried, its flits and its messages by type, over the whole window and
// over a steady-state sub-window that drops the first and last ss_drop_pct
// percent of the data messages crossing that link. The sub-window is cut on
// data messages, not completions: a write completes when its B returns, which
// can bunch long after its data crossed. Those go to perf.json with the build
// and the issued-traffic histogram; docs/PERF_JSON.md is the schema. Each
// bandwidth window's per-link figures also go to res_ap (aou_perf_result) for
// aou_perf_chk, the gate.
class aou_perf_mon extends uvm_component;
  `uvm_component_utils(aou_perf_mon)

  uvm_tlm_analysis_fifo #(aou_axi_txn) loc_fifo;
  uvm_tlm_analysis_fifo #(aou_axi_txn) rem_fifo;
  uvm_tlm_analysis_fifo #(aou_msg)     dut_fifo;   // DUT -> remote die
  uvm_tlm_analysis_fifo #(aou_msg)     tb_fifo;    // remote die -> DUT
  uvm_analysis_port #(aou_perf_result) res_ap;

  aou_l3_agent  l3;
  virtual aou_fdi_lsm_if vif;      // clock for credit polling
  aou_t1_env_cfg cfg;
  uvm_reg_block regs;              // the DUT's RAL model: split lengths
  int unsigned  beat_bytes = 64;   // FDI bytes per cycle on the active PHY
  real          clk_ns = 1.0;
  string        file_name = "perf.txt";
  string        json_name = "perf.json";
  int unsigned  ss_drop_pct = 10;
  int unsigned  min_ss_flits = 2000;
  bit           writefull = 1'b1;  // the windows' writes use full strobes
  int unsigned  remote_full_pct = 100;  // remote full-strobe beats sent as WriteDataFull
  string        perf_mode = "bw";

  protected string       win;
  protected time         t_open;
  protected longint      bytes[2];      // [0] l2r, [1] r2l
  protected int unsigned n_txn[2];
  protected real         lat_sum[2];
  protected time         lat_min[2];
  protected time         lat_max[2];
  protected time         t_last[2];     // last completion per issuing side
  protected int unsigned flits_tx0;      // DUT -> model, at open
  protected int unsigned flits_rx0;      // model -> DUT, at open
  protected bit          single;         // one transaction in flight: round trips are its own
  protected longint      granules;       // granules of the messages the DUT sent
  // Round-trip breakdown: last request seen at FDI and last response put in a flit.
  protected time         t_dut_req;
  protected time         t_tb_rsp;
  protected time         t_tb_req;
  protected time         t_dut_rsp;
  protected real         rt_sum[2][3];
  protected int unsigned rt_n[2];
  // Credit return: remote requests per (RP, class), waiting for their grant.
  protected time         crd_q[4][2][$];
  protected int unsigned crd_seen[4][2];  // l3.model.crd.tx_granted at the last poll
  protected real         crd_sum;
  protected time         crd_max;
  protected int unsigned crd_n;
  // Lowest credit the DUT held from us per class in the window (over the RPs).
  protected int unsigned crd_low[AOU_CC_NUM];
  // TX drain: DUT requests after a grant
  protected time         t_grant;
  protected time         t_drain_first;
  protected time         t_drain_last;
  protected int unsigned n_drain;

  // Window records for the per-link figures: completed transactions (time,
  // issuing side, write, bytes), messages per link, flit counter changes per link.
  protected time         tx_t[$];
  protected bit          tx_side[$];
  protected bit          tx_wr[$];
  protected longint      tx_bytes[$];
  protected time         msg_t[2][$];
  protected string       msg_kind[2][$];
  protected int unsigned msg_g[2][$];
  protected int unsigned msg_db[2][$];   // DLENGTH bytes of a data message, else 0
  protected time         fl_t[2][$];
  protected int unsigned fl_n[2][$];
  protected int unsigned hist[string];
  protected string       win_scenario;
  protected string       win_dir;
  protected int          win_wr_pct;

  protected string       lines[$];
  protected string       json_win[$];
  int unsigned           n_windows;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    loc_fifo = new("loc_fifo", this);
    rem_fifo = new("rem_fifo", this);
    dut_fifo = new("dut_fifo", this);
    tb_fifo  = new("tb_fifo", this);
    res_ap   = new("res_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    int v;
    super.build_phase(phase);
    if ($value$plusargs("perf_ss_drop_pct=%d", v)) ss_drop_pct = v;
    if ($value$plusargs("perf_min_ss_flits=%d", v)) min_ss_flits = v;
  endfunction

  function void put(string metric, real v);
    string l = $sformatf("%s %0.3f", metric, v);
    lines.push_back(l);
    `uvm_info(get_type_name(), {"PERF ", l}, UVM_LOW)
  endfunction

  function void take_msgs();
    aou_msg m;
    while (dut_fifo.try_get(m)) take_dut(m);
    while (tb_fifo.try_get(m)) take_tb(m);
  endfunction

  function bit full_strb(aou_axi_txn t);
    if (t.dir != AOU_AXI_WR) return 1'b1;
    foreach (t.strb[i]) if ((t.strb[i] & t.lane_mask(i)) != t.lane_mask(i)) return 1'b0;
    return 1'b1;
  endfunction

  function void take_txn(aou_axi_txn t, int d);
    time    lat;
    longint nb;
    string  key;
    // A remote transaction completes in the same step as the message that
    // completes it, possibly before that message is taken.
    take_msgs();
    if (win == "" || t.aborted || t.t_addr < t_open) return;
    lat = t.t_done - t.t_addr;
    nb = (longint'(t.len) + 1) << t.size;
    bytes[d] += nb;
    if (n_txn[d] == 0 || lat < lat_min[d]) lat_min[d] = lat;
    if (lat > lat_max[d]) lat_max[d] = lat;
    lat_sum[d] += real'(lat);
    n_txn[d]++;
    if (t.t_done > t_last[d]) t_last[d] = t.t_done;
    tx_t.push_back(t.t_done);
    tx_side.push_back(d[0]);
    tx_wr.push_back(t.dir == AOU_AXI_WR);
    tx_bytes.push_back(nb);
    key = $sformatf("%s|%s|%0d|%0d|%0d|%0d|%0d", d == 0 ? "l2r" : "r2l",
                    t.dir == AOU_AXI_WR ? "W" : "R", t.rp, nb, 1 << t.size,
                    t.addr % 4096, full_strb(t));
    if (hist.exists(key)) hist[key]++;
    else hist[key] = 1;
    // With one transaction in flight the FDI times in between are its own.
    if (single && d == 0 && t_dut_req >= t.t_addr && t_tb_rsp >= t_dut_req) begin
      rt_sum[0][0] += real'(t_dut_req - t.t_addr);
      rt_sum[0][1] += real'(t_tb_rsp - t_dut_req);
      rt_sum[0][2] += real'(t.t_done - t_tb_rsp);
      rt_n[0]++;
    end
    if (single && d == 1 && t_tb_req >= t.t_addr && t_dut_rsp >= t_tb_req) begin
      rt_sum[1][0] += real'(t_tb_req - t.t_addr);
      rt_sum[1][1] += real'(t_dut_rsp - t_tb_req);
      rt_sum[1][2] += real'(t.t_done - t_dut_rsp);
      rt_n[1]++;
    end
  endfunction

  function bit is_last_rsp(aou_msg m);
    aou_msg_rdata d;
    if (m.msg_type == AOU_MT_WRESP) return 1'b1;
    return $cast(d, m) && d.last;
  endfunction

  function void note_msg(int l, aou_msg m);
    if (win == "") return;
    msg_t[l].push_back($time);
    msg_kind[l].push_back(m.kind());
    msg_g[l].push_back(m.num_granules());
    msg_db[l].push_back(data_bytes(m));
  endfunction

  function int unsigned data_bytes(aou_msg m);
    aou_msg_wdata w;
    aou_msg_rdata r;
    if ($cast(w, m)) return aou_dl_bits(w.dlength) / 8;
    if ($cast(r, m)) return aou_dl_bits(r.dlength) / 8;
    return 0;
  endfunction

  function void take_dut(aou_msg m);
    if (m.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ}) begin
      t_dut_req = $time;
      if (t_grant != 0 && $time >= t_grant) begin
        if (n_drain == 0) t_drain_first = $time;
        t_drain_last = $time;
        n_drain++;
      end
    end else if (is_last_rsp(m)) begin
      t_dut_rsp = $time;
    end
    if (win != "") granules += longint'(m.num_granules());
    note_msg(0, m);
  endfunction

  function void take_tb(aou_msg m);
    if (m.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ}) begin
      t_tb_req = $time;
      if (win != "") crd_q[m.rp][m.msg_type == AOU_MT_RREQ ? 1 : 0].push_back($time);
    end else if (is_last_rsp(m)) begin
      t_tb_rsp = $time;
    end
    note_msg(1, m);
  endfunction

  function void flush();
    aou_axi_txn t;
    aou_msg m;
    while (loc_fifo.try_get(t)) take_txn(t, 0);
    while (rem_fifo.try_get(t)) take_txn(t, 1);
    while (dut_fifo.try_get(m)) take_dut(m);
    while (tb_fifo.try_get(m)) take_tb(m);
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_txn t;
    aou_axi_txn u;
    aou_msg m;
    aou_msg q;
    fork
      forever begin loc_fifo.get(t); take_txn(t, 0); end
      forever begin rem_fifo.get(u); take_txn(u, 1); end
      forever begin dut_fifo.get(m); take_dut(m); end
      forever begin tb_fifo.get(q); take_tb(q); end
      forever begin @(vif.mon_cb); poll_credits(); poll_flits(); end
    join
  endtask

  // Flits on link l so far: l2r the DUT sent, r2l the remote die sent.
  function int unsigned link_flits(int l);
    return (l == 0) ? l3.model.rx_flits : l3.model.tx_flits;
  endfunction

  function void poll_flits();
    if (win == "") return;
    for (int l = 0; l < 2; l++) begin
      int unsigned n = link_flits(l);
      if (fl_n[l][$] != n) begin
        fl_t[l].push_back($time);
        fl_n[l].push_back(n);
      end
    end
  endfunction

  // Credits the DUT returned since the last poll (in flit headers or CrdtGrant).
  function void poll_credits();
    take_msgs();
    for (int r = 0; r < 4; r++) begin
      for (int c = 0; c < 2; c++) begin
        int unsigned g = l3.model.crd.tx_granted[r][c];
        int unsigned n = g - crd_seen[r][c];
        crd_seen[r][c] = g;
        while (win != "" && n > 0 && crd_q[r][c].size() > 0) begin
          time d = $time - crd_q[r][c].pop_front();
          crd_sum += real'(d);
          if (d > crd_max) crd_max = d;
          crd_n++;
          n--;
        end
      end
    end
    if (win == "") return;
    for (int c = 0; c < AOU_CC_NUM; c++) begin
      for (int unsigned r = 0; r < cfg.n_rp; r++) begin
        int unsigned o = l3.model.crd.rx_outstanding[r][c];
        if (o < crd_low[c]) crd_low[c] = o;
      end
    end
  endfunction

  // Opens a window; scenario, dir and wr_pct describe its traffic in perf.json.
  function void open(string name, bit one = 1'b0, string scenario = "", string dir = "",
                     int wr_pct = -1);
    poll_credits();
    win = name;
    win_scenario = scenario;
    win_dir = dir;
    win_wr_pct = wr_pct;
    single = one;
    t_open = $time;
    granules = 0;
    crd_sum = 0.0;
    crd_max = 0;
    crd_n = 0;
    foreach (crd_low[c]) crd_low[c] = '1;
    foreach (crd_q[r, c]) crd_q[r][c].delete();
    foreach (bytes[d]) begin
      bytes[d] = 0;
      n_txn[d] = 0;
      lat_sum[d] = 0.0;
      lat_min[d] = 0;
      lat_max[d] = 0;
      t_last[d] = 0;
      rt_n[d] = 0;
      foreach (rt_sum[d][k]) rt_sum[d][k] = 0.0;
    end
    tx_t.delete();
    tx_side.delete();
    tx_wr.delete();
    tx_bytes.delete();
    hist.delete();
    for (int l = 0; l < 2; l++) begin
      msg_t[l].delete();
      msg_kind[l].delete();
      msg_g[l].delete();
      msg_db[l].delete();
      fl_t[l].delete();
      fl_n[l].delete();
      fl_t[l].push_back($time);
      fl_n[l].push_back(link_flits(l));
    end
    flits_tx0 = l3.model.rx_flits;
    flits_rx0 = l3.model.tx_flits;
  endfunction

  // Flit counter of link l at time t (the last change at or before t).
  function int unsigned flits_at(int l, time t);
    int unsigned n = fl_n[l][0];
    foreach (fl_t[l][i]) begin
      if (fl_t[l][i] > t) break;
      n = fl_n[l][i];
    end
    return n;
  endfunction

  function real cycles(time t);
    return real'(t) / (clk_ns * 1ns);
  endfunction

  function string jnum(real v);
    return $sformatf("%0.3f", v);
  endfunction

  // AXI bytes of the window's transactions whose data cross link l.
  function longint link_txn_bytes(int l);
    longint b = 0;
    foreach (tx_t[i]) if ((tx_side[i] == l[0]) == tx_wr[i]) b += tx_bytes[i];
    return b;
  endfunction

  // Link l over (ta, tb]: payload, flits and messages by type, as the body of
  // a JSON object (no closing brace) and as perf.txt metrics
  // <win>.link_<l2r|r2l>.<pre><metric>. The payload is the transactions
  // completed in (ta, tb] when scale < 0, else scale times the DLENGTH bytes of
  // the data messages that crossed in (ta, tb].
  function string link_obj(int l, time ta, time tb, string pre, real scale,
                           output int unsigned nfl, output longint o_app, output longint o_g,
                           output real o_cyc);
    longint      app = 0;
    longint      db = 0;
    longint      g = 0;
    int unsigned gk[string];
    int unsigned nk[string];
    string       s;
    string       sep;
    real         cyc = cycles(tb - ta);
    real         duty;
    string       dn = (l == 0) ? "l2r" : "r2l";
    if (scale < 0.0) begin
      foreach (tx_t[i])
        if (tx_t[i] > ta && tx_t[i] <= tb && ((tx_side[i] == l[0]) == tx_wr[i])) app += tx_bytes[i];
    end
    foreach (msg_t[l][i]) begin
      string k = msg_kind[l][i];
      if (msg_t[l][i] <= ta || msg_t[l][i] > tb) continue;
      g += longint'(msg_g[l][i]);
      db += longint'(msg_db[l][i]);
      if (!gk.exists(k)) begin
        gk[k] = 0;
        nk[k] = 0;
      end
      gk[k] += msg_g[l][i];
      nk[k]++;
    end
    if (scale >= 0.0) app = longint'(scale * real'(db));
    nfl = flits_at(l, tb) - flits_at(l, ta);
    o_app = app;
    o_g = g;
    o_cyc = cyc;
    duty = (cyc > 0) ? real'(nfl) / (cyc * real'(beat_bytes) / 256.0) : 0.0;
    put({win, ".link_", dn, ".", pre, "bytes_per_cycle"}, (cyc > 0) ? real'(app) / cyc : 0.0);
    put({win, ".link_", dn, ".", pre, "cycles"}, cyc);
    put({win, ".link_", dn, ".", pre, "flits"}, real'(nfl));
    put({win, ".link_", dn, ".", pre, "duty"}, duty);
    if (nfl > 0) put({win, ".link_", dn, ".", pre, "granules_per_flit"}, real'(g) / real'(nfl));
    s = $sformatf({"{\"app_bytes\": %0d, \"cycles\": %s, \"flits\": %0d, \"granules\": %0d, ",
                   "\"duty\": %s"}, app, jnum(cyc), nfl, g, jnum(duty));
    s = {s, ", \"granules_by_msg\": {"};
    sep = "";
    foreach (gk[k]) begin
      s = {s, sep, $sformatf("\"%s\": %0d", k, gk[k])};
      sep = ", ";
    end
    s = {s, "}, \"msgs_by_msg\": {"};
    sep = "";
    foreach (nk[k]) begin
      s = {s, sep, $sformatf("\"%s\": %0d", k, nk[k])};
      sep = ", ";
    end
    return {s, "}"};
  endfunction

  // Bytes per cycle a saturated link carries with app bytes in g granules of
  // messages: AoU packs 48 five-byte granules in each 256-byte flit, messages
  // straddling flits (d2d_model's packing), at beat_bytes per cycle.
  function real mix_cap(longint app, longint g);
    return (g > 0) ? real'(beat_bytes) * 48.0 / 256.0 * real'(app) / real'(g) : 0.0;
  endfunction

  // Link l: the whole window and the steady-state sub-window, as a JSON
  // object whose top-level figures repeat the steady-state ones. The
  // sub-window runs between data messages; its payload is their DLENGTH bytes
  // scaled by the window's AXI bytes per DLENGTH byte on this link (1.0 for
  // full-width, full-strobe traffic).
  function string link_json(int l, aou_perf_result res);
    time         t[$];
    time         d[$];
    time         ta;
    time         tb;
    int unsigned n;
    int unsigned k;
    int unsigned nfl;
    longint      db = 0;
    longint      f_app;
    longint      f_g;
    longint      s_app;
    longint      s_g;
    real         f_cyc;
    real         s_cyc;
    string       full;
    string       ss;
    string       dn = (l == 0) ? "l2r" : "r2l";
    foreach (tx_t[i]) if ((tx_side[i] == l[0]) == tx_wr[i]) t.push_back(tx_t[i]);
    foreach (msg_t[l][i]) begin
      if (msg_db[l][i] == 0) continue;
      d.push_back(msg_t[l][i]);
      db += longint'(msg_db[l][i]);
    end
    if (t.size() == 0 || d.size() == 0)
      return {"{\"full\": null, \"ss\": null, \"app_bytes\": 0, \"cycles\": 0, \"flits\": 0, ",
              "\"granules_by_msg\": {}, \"duty\": 0}"};
    t.sort();
    full = link_obj(l, t_open, t[$], "", -1.0, nfl, f_app, f_g, f_cyc);
    res.data[l] = (f_app > 0);
    res.bpc[l] = (f_cyc > 0.0) ? real'(f_app) / f_cyc : 0.0;
    res.cycles[l] = f_cyc;
    res.flits[l] = nfl;
    res.mix_cap[l] = mix_cap(f_app, f_g);
    n = d.size();
    k = n * ss_drop_pct / 100;
    if (n < 2 * k + 2)
      return {"{\"full\": ", full, "}, \"ss\": null, ", full.substr(1, full.len() - 1), "}"};
    ta = (k > 0) ? d[k - 1] : t_open;
    tb = d[n - k - 1];
    ss = link_obj(l, ta, tb, "ss_", real'(link_txn_bytes(l)) / real'(db), nfl, s_app, s_g, s_cyc);
    res.bpc[l] = (s_cyc > 0.0) ? real'(s_app) / s_cyc : 0.0;
    res.cycles[l] = s_cyc;
    res.flits[l] = nfl;
    res.ss_ok[l] = (nfl >= min_ss_flits);
    res.mix_cap[l] = mix_cap(s_app, s_g);
    ss = {ss, $sformatf(", \"mix_cap\": %s", jnum(res.mix_cap[l]))};
    put({win, ".link_", dn, ".ss_ok"}, real'(nfl >= min_ss_flits));
    ss = {ss, $sformatf(", \"t_start\": %s, \"t_end\": %s, \"ss_ok\": %s", jnum(cycles(ta)),
                        jnum(cycles(tb)), (nfl >= min_ss_flits) ? "true" : "false")};
    return {"{\"full\": ", full, "}, \"ss\": ", ss, "}, ", ss.substr(1, ss.len() - 1), "}"};
  endfunction

  // Every message that crossed link l while the window was open, by type.
  function string msgs_json(aou_perf_result res, int l);
    string s = "{";
    string sep = "";
    if (l == 0) begin
      foreach (res.msgs_l2r[k]) begin
        s = {s, sep, $sformatf("\"%s\": %0d", k, res.msgs_l2r[k])};
        sep = ", ";
      end
    end else begin
      foreach (res.msgs_r2l[k]) begin
        s = {s, sep, $sformatf("\"%s\": %0d", k, res.msgs_r2l[k])};
        sep = ", ";
      end
    end
    return {s, "}"};
  endfunction

  function string hist_json();
    string s = "[";
    string sep = "";
    foreach (hist[key]) begin
      string f[$];
      int    p = 0;
      for (int i = 0; i <= key.len(); i++) begin
        if (i == key.len() || key[i] == "|") begin
          f.push_back(key.substr(p, i - 1));
          p = i + 1;
        end
      end
      s = {s, sep, $sformatf({"{\"init\": \"%s\", \"kind\": \"%s\", \"rp\": %s, \"bytes\": %s, ",
                              "\"beat_bytes\": %s, \"offset_mod_4k\": %s, \"full_strb\": %s, ",
                              "\"count\": %0d}"},
                             f[0], f[1], f[2], f[3], f[4], f[5], (f[6] == "1") ? "true" : "false",
                             hist[key])};
      sep = ", ";
    end
    return {s, "]"};
  endfunction

  // Closes the window; cycles from open to the last completion.
  function void close();
    real   cyc = real'($time - t_open) / (clk_ns * 1ns);
    string dn[2] = '{"l2r", "r2l"};
    real   peak = real'(beat_bytes) / 256.0;
    string j;
    string ccn[AOU_CC_NUM] = '{"wreq", "rreq", "wdata", "rdata", "wresp"};
    aou_perf_result res;
    if (win == "") return;
    flush();
    n_windows++;
    res = aou_perf_result::type_id::create(win);
    res.win_name = win;
    res.scenario = win_scenario;
    res.traffic_dir = win_dir;
    for (int l = 0; l < 2; l++) foreach (msg_kind[l][i]) res.count(l, msg_kind[l][i]);
    put({win, ".cycles"}, cyc);
    for (int d = 0; d < 2; d++) begin
      if (n_txn[d] == 0) continue;
      put({win, ".", dn[d], ".txns"}, real'(n_txn[d]));
      put({win, ".", dn[d], ".bytes_per_cycle"}, real'(bytes[d]) / cyc);
      // The same over this side's own span: open to its last completion.
      put({win, ".", dn[d], ".own_cycles"}, cycles(t_last[d] - t_open));
      put({win, ".", dn[d], ".own_bytes_per_cycle"}, real'(bytes[d]) / cycles(t_last[d] - t_open));
      put({win, ".", dn[d], ".lat_avg"}, lat_sum[d] / real'(n_txn[d]) / (clk_ns * 1ns));
      put({win, ".", dn[d], ".lat_min"}, real'(lat_min[d]) / (clk_ns * 1ns));
      put({win, ".", dn[d], ".lat_max"}, real'(lat_max[d]) / (clk_ns * 1ns));
      if (rt_n[d] > 0) begin
        put({win, ".", dn[d], ".rt_to_fdi"}, rt_sum[d][0] / real'(rt_n[d]) / (clk_ns * 1ns));
        put({win, ".", dn[d], ".rt_far_side"}, rt_sum[d][1] / real'(rt_n[d]) / (clk_ns * 1ns));
        put({win, ".", dn[d], ".rt_from_fdi"}, rt_sum[d][2] / real'(rt_n[d]) / (clk_ns * 1ns));
      end
    end
    put({win, ".dut_tx_flits_per_cycle"}, real'(l3.model.rx_flits - flits_tx0) / cyc);
    put({win, ".dut_rx_flits_per_cycle"}, real'(l3.model.tx_flits - flits_rx0) / cyc);
    put({win, ".fdi_peak_flits_per_cycle"}, peak);
    if (l3.model.rx_flits != flits_tx0)
      put({win, ".dut_tx_granules_per_flit"},
          real'(granules) / real'(l3.model.rx_flits - flits_tx0));
    if (crd_n > 0) begin
      put({win, ".credit_return.samples"}, real'(crd_n));
      put({win, ".credit_return.avg"}, crd_sum / real'(crd_n) / (clk_ns * 1ns));
      put({win, ".credit_return.max"}, real'(crd_max) / (clk_ns * 1ns));
    end
    foreach (crd_low[c]) put({win, ".dut_credit_low.", ccn[c]}, real'(crd_low[c]));
    j = $sformatf({"{\"name\": \"%s\", \"scenario\": \"%s\", \"traffic_dir\": \"%s\", ",
                   "\"wr_pct\": %0d, \"t_open\": %s, \"t_close\": %s, \"dir\": {"},
                  win, win_scenario, win_dir, win_wr_pct, jnum(cycles(t_open)),
                  jnum(cycles($time)));
    j = {j, "\"l2r\": ", link_json(0, res), ", \"r2l\": ", link_json(1, res), "}, ",
         "\"window_msgs\": {\"l2r\": ", msgs_json(res, 0), ", \"r2l\": ", msgs_json(res, 1),
         "}, \"init\": {"};
    for (int d = 0; d < 2; d++) begin
      real own = (n_txn[d] > 0) ? cycles(t_last[d] - t_open) : 0.0;
      j = {j, (d > 0) ? ", " : "",
           $sformatf("\"%s\": {\"txns\": %0d, \"bytes\": %0d, \"cycles\": %s}", dn[d], n_txn[d],
                     bytes[d], jnum(own))};
    end
    j = {j, "}, \"dut_credit_low\": {"};
    foreach (crd_low[c]) j = {j, (c > 0) ? ", " : "", $sformatf("\"%s\": %0d", ccn[c], crd_low[c])};
    j = {j, "}, \"txn_hist\": ", hist_json(), "}"};
    json_win.push_back(j);
    if (n_txn[0] + n_txn[1] == 0)
      `uvm_error(get_type_name(), {"T1-P01: no transaction completed in window ", win})
    else if (!(win_scenario inside {"lat", "drain"}))
      res_ap.write(res);
    win = "";
  endfunction

  function void grant_at(time t);
    t_grant = t;
    n_drain = 0;
  endfunction

  function void drain_report();
    flush();
    if (n_drain == 0) begin
      `uvm_error(get_type_name(), "T1-P01: no DUT request after the credit grant")
      return;
    end
    put("drain.requests", real'(n_drain));
    put("drain.grant_to_first", real'(t_drain_first - t_grant) / (clk_ns * 1ns));
    put("drain.grant_to_last", real'(t_drain_last - t_grant) / (clk_ns * 1ns));
  endfunction

  function string sim_name();
`ifdef VCS
    return "vcs";
`elsif VERILATOR
    return "verilator";
`elsif XCELIUM
    return "xcelium";
`elsif QUESTA
    return "questa";
`else
    return "unknown";
`endif
  endfunction

  // Split-transaction maximum AxLEN of RP r from the RAL mirror (reset 15).
  function int unsigned split_len(int unsigned r, string field);
    uvm_reg rg;
    if (regs == null) return 15;
    rg = regs.get_reg_by_name($sformatf("axi_split_tr_rp%0d", r));
    if (rg == null) return 15;
    return int'(rg.get_field_by_name(field).get_mirrored_value());
  endfunction

  function string int_list(int unsigned v[$]);
    string s = "[";
    foreach (v[i]) s = {s, (i > 0) ? ", " : "", $sformatf("%0d", v[i])};
    return {s, "]"};
  endfunction

  // The build and run as perf.json's "build" object; the widths and PHY also
  // go to perf.txt as config.* metrics.
  function string build_json();
    string       config_name = "";
    string       test = "";
    int unsigned seed = 0;
    int unsigned rb[$];
    int unsigned rr[$];
    int unsigned aw[$];
    int unsigned ar[$];
    string       ccn[AOU_CC_NUM] = '{"WREQ", "RREQ", "WDATA", "RDATA", "WRESP"};
    string       s;
    void'($value$plusargs("aou_config=%s", config_name));
    void'($value$plusargs("UVM_TESTNAME=%s", test));
    if (!$value$plusargs("ntb_random_seed=%d", seed))
      void'($value$plusargs("verilator+seed+%d", seed));
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      rb.push_back(cfg.rp_bytes[r]);
      rr.push_back(cfg.remote_bytes_of(r));
      aw.push_back(split_len(r, "max_awburstlen"));
      ar.push_back(split_len(r, "max_arburstlen"));
    end
    put("config.active_phy", real'(cfg.lsm_cfg.active_phy));
    put("config.n_phy", real'(cfg.lsm_cfg.n_phy));
    put("config.beat_bytes", real'(beat_bytes));
    foreach (rb[r]) put($sformatf("config.rp%0d_bytes", r), real'(rb[r]));
    foreach (rr[r]) put($sformatf("config.rp%0d_remote_bytes", r), real'(rr[r]));
    s = $sformatf({"{\"config\": \"%s\", \"sim\": \"%s\", \"test\": \"%s\", \"seed\": %0d, ",
                   "\"perf_mode\": \"%s\", \"active_phy\": %0d, \"n_phy\": %0d, ",
                   "\"beat_bytes\": %0d, \"rp_count\": %0d, \"rp_bytes\": %s, ",
                   "\"remote_bytes\": %s, \"max_awlen\": %s, \"max_arlen\": %s, ",
                   "\"writefull\": %s, \"remote_full_pct\": %0d, \"l3_rx_depth\": {"},
                  config_name, sim_name(), test, seed, perf_mode, cfg.lsm_cfg.active_phy,
                  cfg.lsm_cfg.n_phy, beat_bytes, cfg.n_rp, int_list(rb), int_list(rr),
                  int_list(aw), int_list(ar),
                  writefull ? "true" : "false", remote_full_pct);
    foreach (ccn[c])
      s = {s, (c > 0) ? ", " : "", $sformatf("\"%s\": %0d", ccn[c], cfg.l3_cfg.rx_depth[c])};
    return {s, $sformatf("}, \"ss_drop_pct\": %0d, \"min_ss_flits\": %0d}", ss_drop_pct,
                         min_ss_flits)};
  endfunction

  function void report_phase(uvm_phase phase);
    int    fd;
    string b = build_json();
    fd = $fopen(file_name, "w");
    if (fd == 0) begin
      `uvm_error(get_type_name(), {"T1-P01: cannot write ", file_name})
      return;
    end
    foreach (lines[i]) $fdisplay(fd, "%s", lines[i]);
    $fclose(fd);
    fd = $fopen(json_name, "w");
    if (fd == 0) begin
      `uvm_error(get_type_name(), {"T1-P01: cannot write ", json_name})
      return;
    end
    $fdisplay(fd, "{\"schema\": 2,\n \"build\": %s,\n \"windows\": [", b);
    foreach (json_win[i])
      $fdisplay(fd, "  %s%s", json_win[i], (i + 1 < json_win.size()) ? "," : "");
    $fdisplay(fd, " ]}");
    $fclose(fd);
  endfunction

  function void check_phase(uvm_phase phase);
    if (n_windows == 0) `uvm_error(get_type_name(), "T1-P01: no performance window was measured")
  endfunction
endclass
