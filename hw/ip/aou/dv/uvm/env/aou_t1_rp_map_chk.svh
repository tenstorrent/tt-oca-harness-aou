// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Asymmetric RP mapping (MAS 3.10), in every T1 test, from the register mirror
// (ASYMMETRIC_RP_PROC_CON, DEST_RP), the S-port pins and the DUT's messages.
//
// Local subordinate port x sends its requests on TX lane lane(x):
// RPx_TX_RP_SEL while ASYMMETRIC_RP_EN is set, x otherwise; lane l's messages
// carry the wire RP DEST_RP.RPl_DEST (MAS 3.10.1). Ports on one lane form a
// merge group: their requests go out as {remapped ID, source port} (the port
// index in the low 1 bit with 2 RPs, 2 bits with 3 or 4), and a port's
// requests of one ID share one remapped ID while any of them is outstanding
// (3.10.5). A port alone on its lane keeps its ID (3.10.4). The mapping is on
// the subordinate ports only: the responses of the DUT's manager ports keep
// their own lane (taken from the RTL; 3.10.4 places AOU_ASYMMETRIC_RP_PROC
// between the subordinate ports and the TX core and says nothing of them).
// The remote die answers on the lane it received the request on, and the DUT
// returns the response to the port the source tag names.
//
// Other checkers translate through this one: req_wire()/rsp_wire() give the
// wire RP of a port's requests and of its manager port's responses,
// req_port()/rsp_port() the port a wire request or a returning response
// belongs to, orig_id() the port's own ID behind a wire ID.
//
// Checks, on every WriteReq and ReadReq the DUT sends:
//   FEAT-R29: it is on the wire RP of a lane some port selects; on a merged
//             lane its low ID bits name a port of that lane; and that port has
//             a request of the direction accepted at its pins and not yet sent
//             whose bytes hold the message's address (and, alone on its lane,
//             whose ID the message carries).
//   FEAT-R30: on a merged lane a port's requests of one ID outstanding share
//             one wire ID, and requests of different IDs do not: otherwise the
//             responses could not find their requester (3.10.5). A wire ID is
//             outstanding from its request until the remote die's WriteResp
//             or last ReadData for it (the remapper's own lifetime).
// Requests a port's pins accepted leave the pending list when their message
// is matched, when the port's response arrives first with no early write
// response possible (a request the DUT answered itself), or on a reset.
//
// Coverage: cg_rp_map_req per request, cg_rp_map_cfg per mapping that carried
// traffic (aou_t1_rp_map_fc_bins.svh).
`uvm_analysis_imp_decl(_rpm_dut)

class aou_t1_rp_map_chk extends uvm_component;
  `uvm_component_utils(aou_t1_rp_map_chk)

  uvm_analysis_imp_rpm_dut #(aou_msg, aou_t1_rp_map_chk) dut_msg_imp;   // L3 ap_rx_msg
  uvm_analysis_imp #(aou_msg, aou_t1_rp_map_chk)         rem_msg_imp;   // L3 ap_tx_msg

  aou_core       rm;
  aou_axi_vif_t  s_vif[];
  aou_l3_model   model;            // link epoch, for cg_rp_map_cfg
  int unsigned   n_rp = 1;
  int unsigned   peer_rp = 1;      // the remote die's RP count
  int unsigned   rp_bytes[4] = '{default: 64};

  typedef struct {
    bit [9:0]  id;
    bit [63:0] lo;      // size-aligned first byte
    bit [64:0] hi;      // one past the last byte (65 bits: the map's top)
  } req_t;
  protected req_t pend[AOU_RP_MAX][2][$];          // [port][rd] accepted, not yet sent
  // Wire ID -> the port's own ID, and the requests outstanding on it.
  protected bit [9:0]    w_orig[AOU_RP_MAX][2][int];
  protected int unsigned w_cnt[AOU_RP_MAX][2][int];
  // Requests sent and not yet answered at the port, per own ID.
  protected int unsigned sent[AOU_RP_MAX][2][int];

  // The mirror, decoded when it changes.
  protected uvm_reg_data_t map_raw = '1;
  protected uvm_reg_data_t dest_raw = '1;
  protected bit            en;
  protected int unsigned   lane_q[AOU_RP_MAX];
  protected int unsigned   dest_q[AOU_RP_MAX];
  protected int unsigned   on_lane[AOU_RP_MAX];   // ports on each lane

  // resolve() result of the last message, which two subscribers may ask for.
  protected aou_msg      last_m;
  protected int          last_x;
  protected bit [9:0]    last_orig;

  int unsigned n_req[2];
  int unsigned n_merged[2];
  int unsigned n_bad;

  protected int cv_dir;
  protected int cv_port;
  protected int cv_lane;
  protected int cv_route;
  protected int cv_shape;
  protected int cv_pair;
  protected int cv_merge;
  protected int cv_width;
  protected int cv_wide;
  protected uvm_reg_data_t cov_map = '1;
  protected uvm_reg_data_t cov_dest = '1;
  protected int unsigned   cov_epoch = '1;

  covergroup cg_rp_map_req;
    cp_dir: coverpoint cv_dir {
      `AOU_T1_RPMAP_FC_DIR(AOU_FC_CG)
    }
    cp_port: coverpoint cv_port {
      `AOU_T1_RPMAP_FC_PORT(AOU_FC_CG)
    }
    cp_lane: coverpoint cv_lane {
      `AOU_T1_RPMAP_FC_LANE(AOU_FC_CG)
    }
    cp_route: coverpoint cv_route {
      `AOU_T1_RPMAP_FC_ROUTE(AOU_FC_CG)
    }
    x_target: cross cp_port, cp_lane;
    x_route_dir: cross cp_route, cp_dir;
  endgroup
  aou_fc_group fc_req;

  covergroup cg_rp_map_cfg;
    cp_shape: coverpoint cv_shape {
      `AOU_T1_RPMAP_FC_SHAPE(AOU_FC_CG)
    }
    cp_pair: coverpoint cv_pair {
      `AOU_T1_RPMAP_FC_PAIR(AOU_FC_CG)
    }
    cp_merge: coverpoint cv_merge {
      `AOU_T1_RPMAP_FC_MERGE(AOU_FC_CG)
    }
    cp_width: coverpoint cv_width {
      `AOU_T1_RPMAP_FC_WIDTH(AOU_FC_CG)
    }
    cp_wide: coverpoint cv_wide {
      `AOU_T1_RPMAP_FC_WIDE(AOU_FC_CG)
    }
    x_pair_merge: cross cp_pair, cp_merge;
  endgroup
  aou_fc_group fc_cfg;

  function new(string name, uvm_component parent);
    aou_fc_db db;
    aou_fc_point p;
    bit fresh;
    super.new(name, parent);
    dut_msg_imp = new("dut_msg_imp", this);
    rem_msg_imp = new("rem_msg_imp", this);
    cg_rp_map_req = new();
    cg_rp_map_cfg = new();
    db = aou_fc_db::get();
    fc_req = db.group("env.cg_rp_map_req", fresh);
    if (fresh) begin
      p = fc_req.cp("cp_dir"); `AOU_T1_RPMAP_FC_DIR(AOU_FC_REG)
      p = fc_req.cp("cp_port"); `AOU_T1_RPMAP_FC_PORT(AOU_FC_REG)
      p = fc_req.cp("cp_lane"); `AOU_T1_RPMAP_FC_LANE(AOU_FC_REG)
      p = fc_req.cp("cp_route"); `AOU_T1_RPMAP_FC_ROUTE(AOU_FC_REG)
      void'(fc_req.add_cross("x_target", "cp_port cp_lane"));
      void'(fc_req.add_cross("x_route_dir", "cp_route cp_dir"));
    end
    fc_cfg = db.group("env.cg_rp_map_cfg", fresh);
    if (fresh) begin
      p = fc_cfg.cp("cp_shape"); `AOU_T1_RPMAP_FC_SHAPE(AOU_FC_REG)
      p = fc_cfg.cp("cp_pair"); `AOU_T1_RPMAP_FC_PAIR(AOU_FC_REG)
      p = fc_cfg.cp("cp_merge"); `AOU_T1_RPMAP_FC_MERGE(AOU_FC_REG)
      p = fc_cfg.cp("cp_width"); `AOU_T1_RPMAP_FC_WIDTH(AOU_FC_REG)
      p = fc_cfg.cp("cp_wide"); `AOU_T1_RPMAP_FC_WIDE(AOU_FC_REG)
      void'(fc_cfg.add_cross("x_pair_merge", "cp_pair cp_merge"));
    end
  endfunction

  // ---- The mapping, from the mirror -------------------------------------
  protected function void decode();
    uvm_reg_data_t m;
    uvm_reg_data_t d;
    if (rm == null) begin
      foreach (lane_q[x]) begin
        lane_q[x] = x;
        dest_q[x] = x;
        on_lane[x] = (x < n_rp) ? 1 : 0;
      end
      return;
    end
    m = rm.asymmetric_rp_proc_con.get_mirrored_value();
    d = rm.dest_rp.get_mirrored_value();
    if (m == map_raw && d == dest_raw) return;
    map_raw = m;
    dest_raw = d;
    en = m[0] && n_rp >= 2;
    foreach (lane_q[x]) begin
      lane_q[x] = en ? int'(m[1 + 2 * x +: 2]) : x;
      dest_q[x] = int'(d[4 * x +: 2]);
      on_lane[x] = 0;
    end
    for (int unsigned x = 0; x < n_rp; x++) on_lane[lane_q[x]]++;
  endfunction

  function bit enabled();
    decode();
    return en;
  endfunction

  function int unsigned lane(int unsigned x);
    decode();
    return lane_q[x];
  endfunction

  // Port x shares its lane with another port.
  function bit merged(int unsigned x);
    decode();
    return x < n_rp && on_lane[lane_q[x]] > 1;
  endfunction

  // Wire RP of port x's requests, and of its manager port's responses.
  function int unsigned req_wire(int unsigned x);
    decode();
    return dest_q[lane_q[x]];
  endfunction

  function int unsigned rsp_wire(int unsigned x);
    decode();
    return dest_q[x];
  endfunction

  // The port of lane l a message with wire ID wid belongs to; -1: no port
  // selects l, or the source tag names a port that is not on it.
  function int rsp_port(int unsigned l, bit [9:0] wid);
    int unsigned t;
    decode();
    if (l >= AOU_RP_MAX || on_lane[l] == 0) return -1;
    if (on_lane[l] == 1) begin
      for (int unsigned x = 0; x < n_rp; x++) if (lane_q[x] == l) return x;
      return -1;
    end
    t = (n_rp == 2) ? int'(wid[0]) : int'(wid[1:0]);
    return (t < n_rp && lane_q[t] == l) ? int'(t) : -1;
  endfunction

  // The lane in use whose DEST_RP is wire RP w; -1 when none is.
  function int lane_of_wire(int unsigned w);
    decode();
    for (int unsigned l = 0; l < AOU_RP_MAX; l++)
      if (on_lane[l] != 0 && dest_q[l] == w) return l;
    return -1;
  endfunction

  function int req_port(int unsigned w, bit [9:0] wid);
    int l = lane_of_wire(w);
    return (l < 0) ? -1 : rsp_port(l, wid);
  endfunction

  // Port x's own ID behind wire ID wid (the same ID unless x is merged).
  function bit [9:0] orig_id(int unsigned x, bit rd, bit [9:0] wid);
    if (!merged(x) || !w_orig[x][rd].exists(int'(wid))) return wid;
    return w_orig[x][rd][int'(wid)];
  endfunction

  // ---- Requests ---------------------------------------------------------
  // The port and own ID of DUT request m (x = -1: none found, reported once).
  function void resolve(aou_msg m, output int x, output bit [9:0] orig);
    if (m == last_m) begin
      x = last_x;
      orig = last_orig;
      return;
    end
    last_m = m;
    take_req(m, x, orig);
    last_x = x;
    last_orig = orig;
  endfunction

  function void write_rpm_dut(aou_msg m);
    int x;
    bit [9:0] orig;
    if (m.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ}) resolve(m, x, orig);
  endfunction

  protected function void bad(string rule, string msg);
    n_bad++;
    aou_rule_log::fire(rule, get_type_name());
    `uvm_error(get_type_name(), $sformatf("%s: %s (ASYMMETRIC_RP_PROC_CON %0h, DEST_RP %0h)", rule,
                                          msg, map_raw, dest_raw))
  endfunction

  protected function void take_req(aou_msg m, output int x, output bit [9:0] orig);
    aou_msg_req q;
    bit rd = m.msg_type == AOU_MT_RREQ;
    int l;
    int hit = -1;
    string what;
    x = -1;
    orig = '0;
    if (!$cast(q, m)) return;
    orig = q.id;
    what = $sformatf("%s on wire RP%0d ID %0h addr %0h", rd ? "ReadReq" : "WriteReq", m.rp, q.id,
                     q.addr);
    aou_rule_log::check("FEAT-R29", get_type_name());
    l = lane_of_wire(int'(m.rp));
    if (l < 0) begin
      bad("FEAT-R29", {what, ": no port's lane sends to that RP"});
      return;
    end
    x = rsp_port(l, q.id);
    if (x < 0) begin
      bad("FEAT-R29", $sformatf("%s: lane %0d is merged and the ID's source tag names %s", what,
                                l, "no port of it"));
      return;
    end
    foreach (pend[x][rd][i]) begin
      if (q.addr < pend[x][rd][i].lo || 65'(q.addr) >= pend[x][rd][i].hi) continue;
      if (on_lane[l] == 1 && pend[x][rd][i].id != q.id) continue;
      if (on_lane[l] > 1 && !id_free(x, rd, q.id, pend[x][rd][i].id)) continue;
      hit = i;
      break;
    end
    if (hit < 0) begin
      bad("FEAT-R29", $sformatf("%s: port %0d (lane %0d) has no such %s pending (%0d pending)",
                                what, x, l, rd ? "read" : "write", pend[x][rd].size()));
      x = -1;
      return;
    end
    orig = pend[x][rd][hit].id;
    pend[x][rd].delete(hit);
    if (!sent[x][rd].exists(int'(orig))) sent[x][rd][int'(orig)] = 0;
    sent[x][rd][int'(orig)]++;
    n_req[rd]++;
    if (on_lane[l] > 1) begin
      n_merged[rd]++;
      bind_wid(x, rd, q.id, orig, what);
    end
    sample_req(x, rd);
  endfunction

  // Wire ID wid may carry port x's ID o: wid is free or bound to o.
  protected function bit id_free(int unsigned x, bit rd, bit [9:0] wid, bit [9:0] o);
    return !w_cnt[x][rd].exists(int'(wid)) || w_cnt[x][rd][int'(wid)] == 0 ||
           w_orig[x][rd][int'(wid)] == o;
  endfunction

  // FEAT-R30: a port's ID o maps to one wire ID while outstanding.
  protected function void bind_wid(int unsigned x, bit rd, bit [9:0] wid, bit [9:0] o, string what);
    aou_rule_log::check("FEAT-R30", get_type_name());
    foreach (w_cnt[x][rd][k]) begin
      if (w_cnt[x][rd][k] != 0 && k != int'(wid) && w_orig[x][rd][k] == o)
        bad("FEAT-R30", $sformatf("%s: port %0d's ID %0h is outstanding as wire ID %0h too", what,
                                  x, o, k));
    end
    if (!w_cnt[x][rd].exists(int'(wid))) w_cnt[x][rd][int'(wid)] = 0;
    w_orig[x][rd][int'(wid)] = o;
    w_cnt[x][rd][int'(wid)]++;
  endfunction

  // The remote die's WriteResp or last ReadData ends one request of its wire ID.
  function void write(aou_msg m);
    aou_msg_wresp b;
    aou_msg_rdata d;
    int x;
    bit rd;
    bit [9:0] wid;
    if ($cast(b, m)) begin
      rd = 1'b0;
      wid = b.id;
    end else if ($cast(d, m) && d.last) begin
      rd = 1'b1;
      wid = d.id;
    end else begin
      return;
    end
    x = rsp_port(int'(m.rp), wid);
    if (x < 0 || !w_cnt[x][rd].exists(int'(wid))) return;
    if (w_cnt[x][rd][int'(wid)] > 0) w_cnt[x][rd][int'(wid)]--;
  endfunction

  protected function bit early_en(int unsigned x);
    uvm_reg rg;
    if (rm == null) return 1'b0;
    rg = rm.get_reg_by_name($sformatf("write_early_response_rp%0d", x));
    return rg != null && rg.get_field_by_name("early_bresp_en").get_mirrored_value() != 0;
  endfunction

  // The response to port x's oldest request of the ID: one already sent, or
  // else one the DUT answered itself, which will not be sent. An early write
  // response (EARLY_BRESP_EN) may come before the write is sent: then the
  // write stays pending.
  protected function void answered(int unsigned x, bit rd, bit [9:0] id);
    if (sent[x][rd].exists(int'(id)) && sent[x][rd][int'(id)] > 0) begin
      sent[x][rd][int'(id)]--;
      return;
    end
    if (!rd && early_en(x)) return;
    foreach (pend[x][rd][i]) begin
      if (pend[x][rd][i].id == id) begin
        pend[x][rd].delete(i);
        return;
      end
    end
  endfunction

  protected function req_t req_of(bit [9:0] id, bit [63:0] addr, bit [7:0] len, bit [2:0] size);
    req_t r;
    r.id = id;
    r.lo = addr & ~((64'd1 << size) - 64'd1);
    r.hi = 65'(r.lo) + ((65'(len) + 65'd1) << size);
    return r;
  endfunction

  task run_phase(uvm_phase phase);
    foreach (s_vif[x]) begin
      automatic int unsigned xx = x;
      fork
        watch(xx);
      join_none
    end
  endtask

  protected task watch(int unsigned x);
    forever begin
      @(s_vif[x].mon_cb);
      if (s_vif[x].mon_cb.resetn !== 1'b1) begin
        flush_port(x);
        continue;
      end
      if (s_vif[x].mon_cb.awvalid === 1'b1 && s_vif[x].mon_cb.awready === 1'b1)
        pend[x][0].push_back(req_of(s_vif[x].mon_cb.awid, s_vif[x].mon_cb.awaddr,
                                    s_vif[x].mon_cb.awlen, s_vif[x].mon_cb.awsize));
      if (s_vif[x].mon_cb.arvalid === 1'b1 && s_vif[x].mon_cb.arready === 1'b1)
        pend[x][1].push_back(req_of(s_vif[x].mon_cb.arid, s_vif[x].mon_cb.araddr,
                                    s_vif[x].mon_cb.arlen, s_vif[x].mon_cb.arsize));
      if (s_vif[x].mon_cb.bvalid === 1'b1 && s_vif[x].mon_cb.bready === 1'b1)
        answered(x, 1'b0, s_vif[x].mon_cb.bid);
      if (s_vif[x].mon_cb.rvalid === 1'b1 && s_vif[x].mon_cb.rready === 1'b1 &&
          s_vif[x].mon_cb.rlast === 1'b1)
        answered(x, 1'b1, s_vif[x].mon_cb.rid);
    end
  endtask

  protected function void flush_port(int unsigned x);
    foreach (pend[x][rd]) begin
      pend[x][rd].delete();
      w_cnt[x][rd].delete();
      w_orig[x][rd].delete();
      sent[x][rd].delete();
    end
  endfunction

  // Reset contract: every transaction is gone and the remap tables empty.
  function void reset_flush();
    for (int unsigned x = 0; x < AOU_RP_MAX; x++) flush_port(x);
    last_m = null;
  endfunction

  // ---- Coverage ---------------------------------------------------------
  protected function void sample_req(int unsigned x, bit rd);
    cv_dir = int'(rd);
    cv_port = x;
    cv_lane = lane_q[x];
    cv_route = !en ? 0 : merged(x) ? 3 : (lane_q[x] == x) ? 1 : 2;
    cg_rp_map_req.sample();
    fc_req.sample(cv_dir, cv_port, cv_lane, cv_route);
    if (map_raw == cov_map && dest_raw == cov_dest && (model == null ||
        model.lnk.epoch == cov_epoch)) return;
    cov_map = map_raw;
    cov_dest = dest_raw;
    if (model != null) cov_epoch = model.lnk.epoch;
    sample_cfg();
  endfunction

  protected function void sample_cfg();
    int unsigned groups = 0;
    int unsigned big = 0;
    bit moved = 1'b0;
    bit mixed = 1'b0;
    cv_wide = 0;
    for (int unsigned l = 0; l < AOU_RP_MAX; l++) begin
      if (on_lane[l] > 1) groups++;
      if (on_lane[l] > big) big = on_lane[l];
    end
    for (int unsigned x = 0; x < n_rp; x++) begin
      if (lane_q[x] != x) moved = 1'b1;
      if (en && lane_q[x] < n_rp && rp_bytes[x] > rp_bytes[lane_q[x]]) cv_wide = 1;
      for (int unsigned y = 0; y < n_rp; y++)
        if (y != x && lane_q[y] == lane_q[x] && rp_bytes[y] != rp_bytes[x]) mixed = 1'b1;
    end
    if (!en) cv_shape = (map_raw[8:1] == 8'he4) ? 0 : 1;
    else if (groups == 2) cv_shape = 7;
    else if (groups == 1) cv_shape = 2 + big;
    else cv_shape = moved ? 3 : 2;
    cv_pair = 10 * int'(n_rp) + int'(peer_rp);
    cv_merge = int'(groups != 0);
    cv_width = (groups == 0) ? 0 : mixed ? 2 : 1;
    cg_rp_map_cfg.sample();
    fc_cfg.sample(cv_shape, cv_pair, cv_merge, cv_width, cv_wide);
  endfunction

  function void report_phase(uvm_phase phase);
    decode();
    `uvm_info(get_type_name(), $sformatf(
              {"mapping %s (ASYMMETRIC_RP_PROC_CON %0h, DEST_RP %0h): %0d WriteReq (%0d merged), ",
               "%0d ReadReq (%0d merged) matched to their ports, %0d errors"},
              en ? "enabled" : "disabled", map_raw, dest_raw, n_req[0], n_merged[0], n_req[1],
              n_merged[1], n_bad), UVM_LOW)
  endfunction
endclass
