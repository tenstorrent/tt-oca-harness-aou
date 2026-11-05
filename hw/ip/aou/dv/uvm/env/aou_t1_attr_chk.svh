// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI request attributes and exclusive responses across the link, and FLEX,
// in every T1 test (cfg.attr_chk_en). WriteReq and ReadReq carry AxLOCK,
// AxCACHE, AxPROT and AxQOS (AoU 5.3; Basic Profile Table 31), responses carry
// EXOKAY, and FLEX is USER[15:0] (5.2 / 11.1): the DUT takes AWUSER, ARUSER
// and WUSER on its S port and BUSER and RUSER on its M port (16 bits each)
// and sends them as the FLEX of WriteReq, ReadReq, WriteData, WriteResp and
// ReadData (DP-R08); it presents the FLEX of each message it receives as the
// USER of the AXI transfer it makes of it: AWUSER, ARUSER and WUSER on its M
// port, BUSER and RUSER on its S port (DP-R12).
//
// A request seen at the far side (the remote model for local requests, the M
// port for remote ones) is matched to the requester's transaction by RP,
// direction, ID and address: its start lies inside that transaction's bytes,
// and same-ID pieces are taken in far-side order until they cover it.
// RPs are compared as the DUT's local RPs: a request on the wire carries the
// receiver's RP, so the remote model's view (its plane, the wire RP of DUT
// requests) maps back through the remote die's DEST_RP map
// (l3_cfg.dest_rp, the inverse of the DUT's).
// Whichever side completes first waits for the other: normally the far side,
// but a write answered early completes at the S port first. A requester
// transaction that never matches (reset, a response the DUT made up) or a far
// request that never matches is only counted; other checkers own those.
// DP-R05: the remote die decodes the AxLOCK/AxCACHE/AxPROT/AxQOS the S port got.
// DP-R06: the M port presents the AxLOCK/AxCACHE/AxPROT/AxQOS the remote die sent.
// DP-R07: an exclusive transaction's BRESP/RRESP at the requester is the far
//   subordinate's (EXOKAY or OKAY; AXI4 A7.2: only the subordinate's monitor
//   can decide), when the DUT neither split nor merged it.
// DP-R08: FLEX in each AXI message the DUT sends equals the AXI USER value
//   the DUT's AXI port received: WriteReq = AWUSER, ReadReq = ARUSER,
//   WriteData(Full) = the WUSER of its W beat, WriteResp = BUSER (of the
//   first sub-burst's B when the DUT's burst splitter merged several),
//   ReadData = RUSER of the R beat (of the transaction's first R beat when
//   the DUT's downsizer merged several local beats into one). Checked on the
//   matched pair: the far side of a local request carries the FLEX of the
//   DUT's WriteReq/ReadReq (user) and WriteData beats (wuser[], message
//   order; aou_t1_l4a_adapter); a remote request's near side carries the FLEX
//   of the DUT's WriteResp (buser) and ReadData beats (ruser[];
//   aou_t1_remote_mgr_driver), its far pieces the BUSER/RUSER the M port
//   returned. Responses the DUT makes up match nothing and are not checked.
// DP-R09: the size of each WriteReq the DUT sends is at least the AWSIZE of
//   the S-port write it came from (a writer may raise the size, never lower it),
//   matched by RP, ID and address as above.
// DP-R12: the USER the DUT's AXI port presents for a received message is that
//   message's FLEX: every M-port sub-burst of a remote WriteReq/ReadReq carries
//   its FLEX as AWUSER/ARUSER; each M-port W beat carries as WUSER the FLEX of
//   the first WriteData beat whose bytes it holds (one to one at equal width,
//   repeated on every narrow beat the DUT's downsizer makes of a wide
//   WriteData beat, the first merged beat's when its upsizer joins several;
//   AOU_AXI_DOWN/AOU_AGGREGATOR); the S-port B of a local write carries the
//   remote WriteResp's FLEX as BUSER, unless the DUT answered it early (then 0,
//   AOU_EARLY_BRESP_CTRL_AWCACHE: EARLY_BRESP_EN set on the RP, bufferable or
//   EARLY_ALWAYS_EN, not exclusive); each S-port R beat carries its ReadData
//   beat's FLEX as RUSER. The remote die's values come from the remote
//   manager's AXI USER (aou_t1_remote_mgr_driver, which keeps the link view of
//   a write it repacked in link_size/link_len/link_wuser) and the remote
//   subordinate's BUSER/RUSER (aou_remote_axi_model, merged by
//   aou_t1_l4a_adapter: the first sub-burst's BUSER, the RUSER of the native
//   beat holding each ReadData beat's first byte). An early B whose BUSER is 0
//   is not compared (it may or may not have been the DUT's own).
class aou_t1_attr_chk extends uvm_component;
  `uvm_component_utils(aou_t1_attr_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) loc_fifo;   // S-port managers (near, L2R)
  uvm_tlm_analysis_fifo #(aou_axi_txn) far_fifo;   // remote model executions (far, L2R)
  uvm_tlm_analysis_fifo #(aou_axi_txn) rmt_fifo;   // remote managers (near, R2L)
  uvm_tlm_analysis_fifo #(aou_axi_txn) sub_fifo;   // M-port subordinates (far, R2L)
  uvm_tlm_analysis_fifo #(aou_msg)     dut_fifo;   // DUT -> remote die

  aou_t1_xfer_cov      cov;
  aou_l3_cfg           l3_cfg;   // dest_rp: the remote die's plane -> the DUT's RP
  aou_t1_early_tbl_chk early;    // EARLY_BRESP_EN/EARLY_ALWAYS_EN mirror; null: never early

  protected aou_axi_txn far_q[2][string][$];    // [path 0 L2R, 1 R2L][rp/dir/id]
  protected aou_axi_txn near_q[2][string][$];   // completed, nothing matched yet
  int unsigned n_match[2];
  int unsigned n_excl_cmp[2];
  int unsigned n_flex_chk;      // DP-R08: FLEX values of DUT messages
  int unsigned n_rx_flex_chk;   // DP-R12: USER values the DUT presented
  int unsigned n_wsize_chk;
  protected aou_axi_txn wire_w;  // scratch: a repacked write's link geometry

  protected aou_msg_wreq wreq_q[string][$];   // DUT WriteReqs not yet matched
  protected aou_axi_txn  aw_q[string][$];     // S-port writes not yet matched

  function new(string name, uvm_component parent);
    super.new(name, parent);
    loc_fifo = new("loc_fifo", this);
    far_fifo = new("far_fifo", this);
    rmt_fifo = new("rmt_fifo", this);
    sub_fifo = new("sub_fifo", this);
    dut_fifo = new("dut_fifo", this);
  endfunction

  // The DUT's local RP for remote plane / wire RP x.
  function int local_rp(int x);
    if (l3_cfg == null || x < 0 || x > 3) return x;
    return int'(l3_cfg.dest_rp[x]);
  endfunction

  // t's key; remote-side txns (L2R far: wire RP; R2L near: remote plane) map
  // back to the DUT's RP.
  function string key(aou_axi_txn t, bit remote_side);
    return $sformatf("%0d/%0d/%0h", remote_side ? local_rp(t.rp) : t.rp, t.dir, t.id);
  endfunction

  static function string path_name(int p);
    return (p == 0) ? "local->remote" : "remote->local";
  endfunction

  // With wide set, the window starts at n's 128-byte container: a remote die
  // may send a narrow write as a WriteReq of its bus size (up to 128 bytes),
  // which starts there, and the M-port bursts the DUT makes of it may too.
  static function bit inside_of(aou_axi_txn n, bit [63:0] a, bit wide = 1'b0);
    bit [63:0] base = n.addr & ~(64'(n.beat_bytes()) - 64'd1);
    bit [63:0] lo = wide ? (n.addr & ~64'd127) : base;
    // Offsets, so a burst ending at 2^64 - 1 does not wrap.
    return a >= lo && (a - lo) < (base - lo) + 64'(n.beats() * n.beat_bytes());
  endfunction

  // A reset dropped every transaction in flight.
  function void reset_flush();
    flush();
    foreach (far_q[p]) far_q[p].delete();
    foreach (near_q[p]) near_q[p].delete();
    wreq_q.delete();
    aw_q.delete();
  endfunction

  static function string wkey(int rp, bit [9:0] id);
    return $sformatf("%0d/%0h", rp, id);
  endfunction

  function void cmp_wsize(aou_axi_txn n, aou_msg_wreq w);
    n_wsize_chk++;
    aou_rule_log::check("DP-R09", get_type_name());
    if (w.size < n.size) begin
      aou_rule_log::fire("DP-R09", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
                 "DP-R09: DUT WriteReq of size %0d for an S-port write of AWSIZE %0d: %s", w.size,
                 n.size, n.convert2string()))
    end
  endfunction

  // An S-port write against the DUT WriteReqs of its RP and ID.
  function void take_aw(aou_axi_txn n);
    string k = wkey(n.rp, n.id);
    aou_msg_wreq rest[$];
    bit hit = 1'b0;
    if (wreq_q.exists(k)) begin
      foreach (wreq_q[k][i]) begin
        if (inside_of(n, wreq_q[k][i].addr)) begin
          cmp_wsize(n, wreq_q[k][i]);
          hit = 1'b1;
        end else rest.push_back(wreq_q[k][i]);
      end
      wreq_q[k] = rest;
    end
    if (!hit) aw_q[k].push_back(n);
  endfunction

  function void take_wreq(aou_msg_wreq w);
    string k = wkey(local_rp(int'(w.rp)), w.id);
    if (aw_q.exists(k)) begin
      foreach (aw_q[k][i]) begin
        if (inside_of(aw_q[k][i], w.addr)) begin
          cmp_wsize(aw_q[k][i], w);
          aw_q[k].delete(i);
          return;
        end
      end
    end
    wreq_q[k].push_back(w);
  endfunction

  function void take_far(int p, aou_axi_txn f);
    string k = key(f, p == 0);
    if (f.aborted) return;
    if (near_q[p].exists(k)) begin
      foreach (near_q[p][k][i]) begin
        if (inside_of(near_q[p][k][i], f.addr, p == 1)) begin
          aou_axi_txn one[$] = '{f};
          matched(p, near_q[p][k][i], f, 1'b1);
          check_flex(p, near_q[p][k][i], one);
          near_q[p][k].delete(i);
          return;
        end
      end
    end
    far_q[p][k].push_back(f);
  endfunction

  // Bytes from the start address to the end of the last beat; split or resized
  // pieces of one transaction add up to it.
  static function longint unsigned span(aou_axi_txn t);
    return longint'(t.beats()) * t.beat_bytes() -
           longint'(t.addr & (64'(t.beat_bytes()) - 64'd1));
  endfunction

  // One past the last byte of an INCR burst's last beat.
  static function bit [63:0] end_of(aou_axi_txn t);
    return (t.addr & ~(64'(t.beat_bytes()) - 64'd1)) + 64'(t.beats()) * t.beat_bytes();
  endfunction

  // Do the pieces, taken together, cover every byte of the INCR request n from
  // its address to its end? Walks the pieces in address order; a piece that
  // starts at or below the point reached so far extends it (sub-bursts may
  // overlap in the first beat, see take_near).
  static function bit covers(aou_axi_txn n, aou_axi_txn got[$]);
    bit [63:0] reached = n.addr;
    aou_axi_txn s[$] = got;
    s.sort() with (item.addr);
    foreach (s[i]) begin
      if (s[i].addr > reached) return 1'b0;
      if (end_of(s[i]) > reached) reached = end_of(s[i]);
    end
    return reached >= end_of(n);
  endfunction

  // A later same-ID request can start inside an earlier one's bytes and reach
  // the far side before the earlier response gets back, so pieces (queued in
  // far-side order) are taken oldest first only until they cover n.
  //
  // The pieces of an unaligned INCR request can overlap: when the splitter cuts
  // it, each sub-burst starts at the next unserved narrow beat, which lies
  // inside the previous sub-burst's last wide beat (AXI4 A3.4.1: only a burst's
  // first beat is partial). The spans then add up to more than n's, and the
  // address a piece reaches overstates what it served. So an INCR request
  // counts as covered when the pieces taken so far cover every byte from its
  // address to its end (the remote die may complete the pieces in any order,
  // so this is the union of their ranges, not the furthest end reached), and
  // a further same-ID piece that starts inside the last taken piece's final
  // beat is still its continuation and is taken too. Other bursts go by the
  // span sum.
  function void take_near(int p, aou_axi_txn n);
    string k = key(n, p == 1);
    aou_axi_txn got[$];
    aou_axi_txn rest[$];
    aou_axi_txn last;
    longint unsigned have = 0;
    bit covered = 1'b0;
    bit incr = (n.burst == AOU_AXI_INCR);
    if (n.aborted || n.reset_outstanding) return;
    if (p == 0 && n.dir == AOU_AXI_WR) take_aw(n);
    if (far_q[p].exists(k)) begin
      foreach (far_q[p][k][i]) begin
        aou_axi_txn f = far_q[p][k][i];
        bit continues = incr && covered && last != null && f.addr > last.addr &&
                        f.addr >= end_of(last) - 64'(last.beat_bytes()) && f.addr < end_of(last);
        if ((!covered || continues) && inside_of(n, f.addr, p == 1)) begin
          got.push_back(f);
          have += span(f);
          last = f;
          covered = incr ? covers(n, got) : (have >= span(n));
        end else rest.push_back(f);
      end
      far_q[p][k] = rest;
    end
    if (got.size() == 0) begin
      near_q[p][k].push_back(n);
      return;
    end
    foreach (got[i]) matched(p, n, got[i], got.size() == 1);
    check_flex(p, n, got);
  endfunction

  // Reports one DP-R08 mismatch.
  protected function void flex_err(int p, aou_axi_txn n, string msg, string beat, bit [15:0] got,
                                   string sig, bit [15:0] exp);
    aou_rule_log::fire("DP-R08", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
               "DP-R08: %s: DUT %s%s on RP%0d carries FLEX %04h, the %s port got %s %04h: %s",
               path_name(p), msg, beat, n.rp, got, (p == 0) ? "S" : "M", sig, exp,
               n.convert2string()))
  endfunction

  // FLEX of the DUT's messages for n against the USER its AXI port got (the
  // header's DP-R08). got holds n's far pieces; on p == 1 they are the M-port
  // bursts the DUT made of the remote request, in the order their responses
  // completed (same ID, so the order the DUT issued them).
  function void check_flex(int p, aou_axi_txn n, aou_axi_txn got[$]);
    aou_axi_txn f;
    int bad;
    if (got.size() == 0) return;
    f = got[0];
    aou_rule_log::check("DP-R08", get_type_name());
    aou_rule_log::check("DP-R12", get_type_name());
    if (p == 0) begin
      // What the DUT received for this request: the remote WriteResp or
      // ReadData FLEX on the S port's B or R (DP-R12).
      if (n.dir == AOU_AXI_WR) rx_wresp(n, got);
      else rx_rdata(n, got);
      // The DUT's request: every far piece carries the one WriteReq/ReadReq FLEX.
      n_flex_chk++;
      foreach (got[i]) begin
        if (got[i].user != n.user) begin
          flex_err(p, n, (n.dir == AOU_AXI_WR) ? "WriteReq" : "ReadReq", "", got[i].user,
                   (n.dir == AOU_AXI_WR) ? "AWUSER" : "ARUSER", n.user);
          break;
        end
      end
      // One WriteData per W beat (AoU 5.2: USER passes through beat by beat).
      if (n.dir == AOU_AXI_WR) begin
        n_flex_chk += f.wuser.size();
        if (f.wuser.size() != n.wuser.size())
          `uvm_info(get_type_name(), $sformatf(
                    "DP-R08: %s: %0d WriteData beats for %0d W beats, comparing the first %0d: %s",
                    path_name(p), f.wuser.size(), n.wuser.size(),
                    (f.wuser.size() < n.wuser.size()) ? f.wuser.size() : n.wuser.size(),
                    n.convert2string()), UVM_MEDIUM)
        bad = -1;
        foreach (f.wuser[i]) begin
          if (i < n.wuser.size() && f.wuser[i] != n.wuser[i] && bad < 0) bad = i;
        end
        if (bad >= 0)
          flex_err(p, n, "WriteData", $sformatf(" beat %0d", bad), f.wuser[bad], "WUSER",
                   n.wuser[bad]);
      end
      return;
    end
    // The remote request as the M port presented it (DP-R12).
    rx_req(n, got);
    if (n.dir == AOU_AXI_WR) begin
      // WriteResp: the B of the first sub-burst (the only one when unsplit).
      n_flex_chk++;
      if (n.buser != first_piece(got).buser)
        flex_err(p, n, "WriteResp", "", n.buser,
                 (got.size() > 1) ? "BUSER of the first sub-burst" : "BUSER",
                 first_piece(got).buser);
      return;
    end
    // ReadData: merged by the downsizer (the M port narrower than the remote
    // request's size) every beat carries the transaction's first RUSER;
    // otherwise each beat carries the RUSER of the M-port beat holding its bytes.
    if (n.ruser.size() != n.beats()) return;
    n_flex_chk += n.beats();
    bad = -1;
    if (f.beat_bytes() < n.beat_bytes()) begin
      aou_axi_txn first = first_piece(got);
      if (first.ruser.size() == 0) return;
      foreach (n.ruser[i]) if (n.ruser[i] != first.ruser[0] && bad < 0) bad = i;
      if (bad >= 0)
        flex_err(p, n, "ReadData", $sformatf(" beat %0d", bad), n.ruser[bad],
                 "RUSER of the transaction's first R beat", first.ruser[0]);
      return;
    end
    foreach (n.ruser[i]) begin
      bit [63:0] a = n.beat_addr(i);
      int j;
      int sel = -1;
      // The piece that supplied the bytes at a. When the splitter cuts an
      // unaligned request into sub-bursts, each starts at the next unserved
      // narrow beat and its last wide beat covers the start of the next piece
      // (AXI4 A3.4.1: a burst's first beat may be unaligned, the rest are
      // full width), so the pieces' byte ranges overlap. The piece issued for
      // the highest address at or below a is the one whose beat was read.
      foreach (got[g]) begin
        j = got[g].beat_index_of(a);
        if (j >= 0 && j < got[g].ruser.size() && got[g].addr <= a &&
            (sel < 0 || got[g].addr > got[sel].addr)) sel = g;
      end
      if (sel < 0) continue;
      j = got[sel].beat_index_of(a);
      if (n.ruser[i] != got[sel].ruser[j]) begin
        bad = i;
        flex_err(p, n, "ReadData", $sformatf(" beat %0d", i), n.ruser[i],
                 $sformatf("RUSER on beat %0d of its burst at %0h", j, got[sel].addr),
                 got[sel].ruser[j]);
        break;
      end
    end
  endfunction

  // Reports one DP-R12 mismatch: the DUT presented got as sig for the remote
  // die's message msg, whose FLEX is exp.
  protected function void rx_flex_err(int p, aou_axi_txn n, string msg, string sig,
                                      bit [15:0] got, bit [15:0] exp);
    aou_rule_log::fire("DP-R12", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
               {"DP-R12: %s: the remote die's %s on RP%0d carries FLEX %04h, ",
                "the DUT's %s port presents %s %04h: %s"},
               path_name(p), msg, n.rp, exp, (p == 0) ? "S" : "M", sig, got,
               n.convert2string()))
  endfunction

  // Last byte of the AxSIZE container of beat i of t.
  static function bit [63:0] beat_hi(aou_axi_txn t, int unsigned i);
    bit [63:0] bb = 64'(t.beat_bytes());
    return (t.beat_addr(i) & ~(bb - 64'd1)) + bb - 64'd1;
  endfunction

  // A remote request at the M port: every sub-burst carries the request's
  // FLEX as AWUSER/ARUSER, and each W beat the FLEX of the first WriteData
  // beat whose bytes it holds (the header's DP-R12).
  protected function void rx_req(aou_axi_txn n, aou_axi_txn got[$]);
    aou_axi_txn w;
    n_rx_flex_chk++;
    foreach (got[i]) begin
      if (got[i].user != n.user) begin
        rx_flex_err(1, n, (n.dir == AOU_AXI_WR) ? "WriteReq" : "ReadReq",
                    (n.dir == AOU_AXI_WR) ? $sformatf("AWUSER on its burst at %0h", got[i].addr) :
                                            $sformatf("ARUSER on its burst at %0h", got[i].addr),
                    got[i].user, n.user);
        break;
      end
    end
    if (n.dir != AOU_AXI_WR || n.burst != AOU_AXI_INCR) return;
    // The link view: the WriteReq's geometry and one FLEX per WriteData beat.
    if (wire_w == null) wire_w = aou_axi_txn::type_id::create("wire_w");
    w = wire_w;
    w.addr = n.addr;
    w.burst = AOU_AXI_INCR;
    if (n.link_wuser.size() > 0) begin
      w.size = n.link_size;
      w.len = n.link_len;
      w.wuser = n.link_wuser;
    end else begin
      w.size = n.size;
      w.len = n.len;
      w.wuser = n.wuser;
    end
    w.data_bytes = w.beat_bytes();
    if (w.wuser.size() != w.beats()) return;
    foreach (got[g]) begin
      aou_axi_txn f = got[g];
      if (f.wuser.size() != f.beats()) continue;   // W beats not captured
      for (int unsigned j = 0; j < f.beats(); j++) begin
        bit [63:0] lo = f.beat_addr(j);
        bit [63:0] hi = beat_hi(f, j);
        int k = w.beat_index_of(lo);
        // A burst the DUT started below the WriteReq's address still holds
        // its first beat.
        if (k < 0 && lo < w.addr && hi >= w.addr) k = 0;
        if (k < 0) continue;
        n_rx_flex_chk++;
        if (f.wuser[j] != w.wuser[k]) begin
          rx_flex_err(1, n, $sformatf("WriteData beat %0d", k),
                      $sformatf("WUSER on beat %0d of its burst at %0h", j, f.addr), f.wuser[j],
                      w.wuser[k]);
          return;
        end
      end
    end
  endfunction

  // A write the DUT answered early carries BUSER 0 (the header's DP-R12).
  protected function bit may_be_early(aou_axi_txn n);
    if (early == null || n.lock || !early.early_en(n.rp)) return 1'b0;
    return n.cache[0] || early.always_en(n.rp);
  endfunction

  // The remote WriteResp's FLEX on the S port's B: the lowest-addressed
  // piece's BUSER, as aou_t1_l4a_adapter merged it (the pieces reach this
  // checker in the remote die's completion order, which take_near's coverage
  // test tolerates).
  protected function void rx_wresp(aou_axi_txn n, aou_axi_txn got[$]);
    bit [15:0] exp = first_piece(got).buser;
    string cands = "";
    if (n.buser == 16'h0 && may_be_early(n)) return;
    n_rx_flex_chk++;
    if (n.buser == exp) return;
    foreach (got[i]) cands = {cands, (i == 0) ? "" : ",", $sformatf("%04h@%0h", got[i].buser,
                                                                     got[i].addr)};
    rx_flex_err(0, n, "WriteResp",
                (got.size() > 1) ? $sformatf("BUSER (first of the sub-bursts' %s)", cands) :
                                   "BUSER", n.buser, exp);
  endfunction

  // Each ReadData beat's FLEX on the S port's R beat: the RUSER of the remote
  // beat that held the beat's first byte (aou_t1_l4a_adapter).
  protected function void rx_rdata(aou_axi_txn n, aou_axi_txn got[$]);
    if (n.ruser.size() != n.beats()) return;
    foreach (n.ruser[i]) begin
      bit [63:0] a = n.beat_addr(i);
      int j;
      int sel = -1;
      foreach (got[g]) begin
        j = got[g].beat_index_of(a);
        if (j >= 0 && j < got[g].ruser.size() && (sel < 0 || got[g].addr > got[sel].addr)) sel = g;
      end
      if (sel < 0) continue;
      j = got[sel].beat_index_of(a);
      n_rx_flex_chk++;
      if (n.ruser[i] != got[sel].ruser[j]) begin
        rx_flex_err(0, n, $sformatf("ReadData beat %0d", i),
                    $sformatf("RUSER on beat %0d (remote beat %0d of its burst at %0h)", i, j,
                              got[sel].addr), n.ruser[i], got[sel].ruser[j]);
        return;
      end
    end
  endfunction

  // The piece whose request the DUT issued first (same ID: the lowest address).
  static function aou_axi_txn first_piece(aou_axi_txn got[$]);
    aou_axi_txn f = got[0];
    foreach (got[i]) if (got[i].addr < f.addr) f = got[i];
    return f;
  endfunction

  function void matched(int p, aou_axi_txn n, aou_axi_txn f, bit one);
    string rule = (p == 0) ? "DP-R05" : "DP-R06";
    n_match[p]++;
    aou_rule_log::check(rule, get_type_name());
    if (f.lock != n.lock || f.cache != n.cache || f.prot != n.prot || f.qos != n.qos) begin
      aou_rule_log::fire(rule, get_type_name());
      `uvm_error(get_type_name(), $sformatf(
                 {"%s: %s: far side got lock=%0b cache=%0h prot=%0h qos=%0h, the requester ",
                  "sent lock=%0b cache=%0h prot=%0h qos=%0h: %s"}, rule, path_name(p), f.lock,
                 f.cache, f.prot, f.qos, n.lock, n.cache, n.prot, n.qos, n.convert2string()))
    end
    if (cov != null) cov.sample_attr(p, f);
    if (one && n.lock) check_excl(p, n, f);
  endfunction

  function void check_excl(int p, aou_axi_txn n, aou_axi_txn f);
    bit bad = 1'b0;
    string what;
    n_excl_cmp[p]++;
    aou_rule_log::check("DP-R07", get_type_name());
    if (n.dir == AOU_AXI_WR) begin
      bad = (n.bresp != f.bresp);
      what = $sformatf("BRESP %0d", n.bresp);
      if (cov != null) cov.sample_excl(p, 0, f.bresp);
    end else begin
      if (n.rresp.size() != f.rresp.size()) return;
      foreach (n.rresp[i]) if (n.rresp[i] != f.rresp[i]) bad = 1'b1;
      what = $sformatf("RRESP %p", n.rresp);
      if (cov != null && f.rresp.size() > 0) cov.sample_excl(p, 1, f.rresp[0]);
    end
    if (bad) begin
      aou_rule_log::fire("DP-R07", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
                 "DP-R07: %s: exclusive %s at the requester, the subordinate answered %s: %s",
                 path_name(p), what, (n.dir == AOU_AXI_WR) ? $sformatf("BRESP %0d", f.bresp) :
                 $sformatf("RRESP %p", f.rresp), n.convert2string()))
    end
  endfunction

  // DUT WriteReqs feed the size check; FLEX is checked on the matched pair.
  function void take_dut(aou_msg m);
    aou_msg_wreq w;
    if (m.msg_type == AOU_MT_WREQ && $cast(w, m)) take_wreq(w);
  endfunction

  function void flush();
    aou_axi_txn t;
    aou_msg m;
    while (far_fifo.try_get(t)) take_far(0, t);
    while (sub_fifo.try_get(t)) take_far(1, t);
    while (loc_fifo.try_get(t)) take_near(0, t);
    while (rmt_fifo.try_get(t)) take_near(1, t);
    while (dut_fifo.try_get(m)) take_dut(m);
  endfunction

  // Far pieces are taken before each requester completion, so a piece that
  // arrived first is always queued when its requester looks for it.
  task run_phase(uvm_phase phase);
    aou_msg m;
    aou_axi_txn t;
    aou_axi_txn u;
    aou_axi_txn v;
    aou_axi_txn w;
    fork
      forever begin dut_fifo.get(m); take_dut(m); end
      forever begin far_fifo.get(u); take_far(0, u); end
      forever begin sub_fifo.get(w); take_far(1, w); end
      forever begin
        loc_fifo.get(t);
        while (far_fifo.try_get(u)) take_far(0, u);
        take_near(0, t);
      end
      forever begin
        rmt_fifo.get(v);
        while (sub_fifo.try_get(w)) take_far(1, w);
        take_near(1, v);
      end
    join
  endtask

  function void check_phase(uvm_phase phase);
    flush();
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned left[2][2];
    int unsigned w_left[2];
    foreach (far_q[p]) foreach (far_q[p][k]) left[p][0] += far_q[p][k].size();
    foreach (near_q[p]) foreach (near_q[p][k]) left[p][1] += near_q[p][k].size();
    foreach (wreq_q[k]) w_left[0] += wreq_q[k].size();
    foreach (aw_q[k]) w_left[1] += aw_q[k].size();
    `uvm_info(get_type_name(), $sformatf(
              {"matched L2R/R2L %0d/%0d, exclusive responses compared %0d/%0d, unmatched far ",
               "%0d/%0d requester %0d/%0d; FLEX values checked: DUT messages %0d, USER the DUT ",
               "presented %0d; WriteReq sizes checked %0d, unmatched WriteReq %0d ",
               "S-port write %0d"},
              n_match[0], n_match[1], n_excl_cmp[0], n_excl_cmp[1], left[0][0], left[1][0],
              left[0][1], left[1][1], n_flex_chk, n_rx_flex_chk, n_wsize_chk, w_left[0],
              w_left[1]), UVM_LOW)
  endfunction
endclass
