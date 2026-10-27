// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// R/B response error debug FIFO and its debug window (MAS software-operation
// 7.2.4), checked in every test from what the env observes.
//
// Model: per RP a FIFO of `depth` entries, fed by the RP's M port. Every
// non-OKAY R beat pushes one entry {ID, address of that beat aligned down to
// ARSIZE, RRESP}; every non-OKAY B pushes one entry {ID, AWADDR, BRESP}, where
// AWADDR is the address of the write as the remote die issued it (aligned down
// to AWSIZE when the write is wider than the RP, as the width converter
// does), so the sub-bursts the splitter made of one write all record the same
// address. The beat is the beat the RP's splitter sees, after width conversion
// and before the aggregator: one remote beat wider than the RP pushes once per
// RP beat, a long burst of errors once per beat, and a failing M-port beat the
// read aggregator built from narrow remote beats once per narrow beat of the
// splitter's sub-burst within it (the remote read is known from the rmgr's
// request, same ID, in flight over the beat; the sub-burst starts at the
// M-port ARADDR and holds MAX_ARBURSTLEN+1 remote beats, register mirror). A
// push into a full FIFO is dropped: the first `depth`
// errors are kept and later ones lost. Errors the DUT makes up itself never
// reach the M port and push nothing. Errors whose M-port responses are within
// order_cycles of each other may enter in either order: the MAS orders nothing
// between B and R errors close together, and the DUT's B and R capture paths
// differ in latency. The beats of one burst are in beat order.
//
// Entries are ordered by the handshake that pushed them: each R beat's own
// handshake (aou_axi_txn::t_r, from the monitor) and the B handshake. The
// monitor publishes a read when it completes, after any B that landed between
// its beats, so the model inserts by time and, when that overfills it, drops
// the latest entry, as the hardware did when that entry arrived. A pop that
// lands between the beats of a read whose beats overfill the FIFO is applied
// before them, not among them; the sequences pop only once their errors have
// completed. The narrow beats re-expanded from one aggregated M-port beat are
// pushed as the aggregator presents them to the splitter, one per cycle at
// the earliest and later under backpressure on the read-data path, which the
// env does not see: such an entry is timed at the earliest it can have been
// pushed and marked `late`, and until the remote read has completed (an upper
// bound on every beat's push) any entry of another transaction behind it may
// have entered before it.
//
// A B entry's address is resolved from the remote write with the same ID that
// was in flight over the sub-burst's address when the B returned (rmgr
// transactions carry t_addr and t_done; the manager-side ID is the remote
// ID). Until then, or when no remote write is found, the entry matches any
// address at or below the sub-burst's address in the same 4 KB. Two
// same-ID writes over the same bytes in flight together are told apart by
// issue order, which is exact unless the earlier one's remote B lags the
// later one's first manager-port B.
//
// A remote access is a debug-window access when its address equals RP r's
// {DEBUG_UPPER_ADDR, DEBUG_LOWER_ADDR} and RPr_ERROR_INFO_ACCESS_EN is set
// (register mirror). Software issues them as single beats of any size; the
// window also answers longer bursts (MAS 7.2.4). Reads and pops of any length
// within 4 KB:
//   T1-E03  every RRESP of a read and the BRESP of a pop is OKAY;
//   T1-E19  every RP-wide lane of every read beat equals the head entry:
//           remote beats at least as wide as the RP hold whole RP beats, so
//           every lane equals lane 0 of beat 0; narrower remote beats are
//           slices of RP beats, so beat k equals beat k mod (RP / remote);
//   T1-E02  the head, {ID, ADDR, RESP} in the low 76 bits of beat 0, is the
//           predicted head (any entry of a group pushed together). Not judged
//           after a drop the model could not order, or after pops whose
//           entries it could not tell, until the pops have drained the FIFO.
// A pop removes the head (MAS 7.2.4). Entries pushed close together may have
// entered in either order, so the model knows the head only when a single
// entry can be it, or when a read that no pop overlapped has returned it (the
// model then moves that entry to the front). A pop of a head the model does
// not know is pending: it took one of the entries that may lead, and they all
// stay acceptable heads until the pending pops cover every such entry, or a
// read that no pop overlapped shows which one the hardware still holds; the
// entries that may have been ahead of it are the ones the pops took. The
// window samples the head when a read becomes active, so a read in flight
// together with a pop (rmgr requests, as issued) returns the head before or
// after the pop. Each read remembers how many pops had completed when it was
// issued and whether one was in flight then; it overlaps a pop when one was
// in flight at its issue, completed after it or is in flight at its end. An
// entry a pop removed is an acceptable head only for the reads issued before
// that pop completed, and is forgotten once none of them is in flight; a pop
// still in flight when the read completes may have taken the leading entry. A
// read that overlapped a pop teaches the model nothing about the order; one
// issued after a pop completed does, even while an earlier read that the pop
// overlapped is still in flight.
class aou_t1_dbg_fifo_chk extends uvm_component;
  `uvm_component_utils(aou_t1_dbg_fifo_chk)

  uvm_analysis_imp_dbg_mport #(aou_axi_txn, aou_t1_dbg_fifo_chk)  mport_imp;
  uvm_analysis_imp_dbg_remote #(aou_axi_txn, aou_t1_dbg_fifo_chk) remote_imp;
  uvm_analysis_imp_dbg_remote_req #(aou_axi_txn, aou_t1_dbg_fifo_chk) remote_req_imp;

  aou_t1_env_cfg cfg;
  aou_core       rm;
  aou_axi_vif_t  clk_vif;
  int unsigned   depth = 4;
  int unsigned   order_cycles = 32;

  typedef struct packed {
    bit [9:0]  id;
    bit [63:0] addr;
    bit [1:0]  resp;
    bit [63:0] tm;    // handshake that pushed it, ps
    bit [31:0] src;   // M-port transaction the entry came from
    bit        b_sub; // B entry still holding the sub-burst's address
    bit        late;  // re-expanded beat: pushed at tm or later, by the remote read's end
  } ent_t;

  typedef struct {
    ent_t        e;
    int unsigned seq;   // the pop that removed it, counted per RP (or a later one)
  } taken_t;

  typedef struct {
    aou_axi_txn  t;
    int unsigned seq;     // pops completed when the read was issued
    bit          busy;    // a pop was in flight when the read was issued
    bit          behind;  // issued after a pop that an earlier read in flight overlapped
  } rd_rec_t;

  int unsigned n_push;
  int unsigned n_drop;
  int unsigned n_read;
  int unsigned n_pop;
  int unsigned n_unresolved;   // heads matched by a B entry whose write was not found
  int unsigned max_hist = 256;

  protected ent_t            q[AOU_RP_MAX][$];
  protected bit              unsure[AOU_RP_MAX];
  protected longint unsigned period_ps;   // M-port clock period; order_cycles in time
  protected bit [31:0]       n_src;
  protected aou_axi_txn      wr_hist[AOU_RP_MAX][$];   // completed remote writes
  protected aou_axi_txn      rd_req[AOU_RP_MAX][$];    // remote reads in flight, issue order
  protected aou_axi_txn      late_rd[bit [31:0]];      // src of re-expanded entries -> remote read
  protected rd_rec_t         rd_open[AOU_RP_MAX][$];   // debug reads issued, not completed
  protected int unsigned     pop_open[AOU_RP_MAX];     // debug pops issued, not completed
  protected int unsigned     pop_seq[AOU_RP_MAX];      // debug pops completed
  protected taken_t          taken[AOU_RP_MAX][$];     // popped while a debug read was outstanding
  protected bit              head_known[AOU_RP_MAX];   // q[r][0] is the hardware's head
  protected int unsigned     pend[AOU_RP_MAX];         // pops whose entries are still in q[r]
  int unsigned n_overlap;      // debug reads judged with a pop in flight
  int unsigned n_behind;       // reads issued after a pop an earlier read overlapped, judged clean

  function new(string name, uvm_component parent);
    super.new(name, parent);
    mport_imp = new("mport_imp", this);
    remote_imp = new("remote_imp", this);
    remote_req_imp = new("remote_req_imp", this);
  endfunction

  task run_phase(uvm_phase phase);
    time t0;
    if (clk_vif == null) return;
    @(clk_vif.mon_cb);
    t0 = $time;
    @(clk_vif.mon_cb);
    period_ps = 64'($time - t0);
  endtask

  // The ordering window in time; a cycle until the clock has been measured.
  function bit [63:0] order_ps();
    return 64'(order_cycles) * (period_ps == 0 ? 64'd1 : 64'(period_ps));
  endfunction

  // Reset contract: a core or software reset empties every FIFO.
  function void reset_flush();
    foreach (q[r]) begin
      q[r].delete();
      wr_hist[r].delete();
      rd_req[r].delete();
      taken[r].delete();
      head_known[r] = 1'b0;
      pend[r] = 0;
      unsure[r] = 1'b0;
      rd_open[r].delete();
      pop_open[r] = 0;
      pop_seq[r] = 0;
    end
    late_rd.delete();
  endfunction

  static function bit is_err(bit [1:0] resp);
    return resp inside {AOU_AXI_SLVERR, AOU_AXI_DECERR};
  endfunction

  static function bit [63:0] lo_of(aou_axi_txn t);
    return t.addr & ~((64'd1 << t.size) - 64'd1);
  endfunction

  function bit [63:0] window_of(int unsigned r, output bit en);
    uvm_reg_field f;
    uvm_reg       up;
    uvm_reg       lo;
    en = 1'b0;
    if (rm == null) return '0;
    f = rm.aou_con0.get_field_by_name($sformatf("rp%0d_error_info_access_en", r));
    up = rm.get_reg_by_name($sformatf("axi_error_info0_rp%0d", r));
    lo = rm.get_reg_by_name($sformatf("axi_error_info1_rp%0d", r));
    if (f == null || up == null || lo == null) return '0;
    en = f.get_mirrored_value() != 0;
    return {32'(up.get_field_by_name("debug_upper_addr").get_mirrored_value()),
            32'(lo.get_field_by_name("debug_lower_addr").get_mirrored_value()) << 7};
  endfunction

  // MAX_ARBURSTLEN of RP r (register mirror): the splitter cuts a read into
  // sub-bursts of that many + 1 beats as it sees them.
  function int unsigned split_arlen(int unsigned r);
    uvm_reg g;
    if (rm == null) return 255;
    g = rm.get_reg_by_name($sformatf("axi_split_tr_rp%0d", r));
    if (g == null) return 255;
    return int'(g.get_field_by_name("max_arburstlen").get_mirrored_value());
  endfunction

  // The latest an entry can have been pushed: its handshake, or for a
  // re-expanded beat the end of the remote read (unknown until then).
  protected function bit [63:0] hi_of(ent_t e);
    if (!e.late) return e.tm;
    if (late_rd.exists(e.src) && late_rd[e.src].t_done != 0) return 64'(late_rd[e.src].t_done);
    return '1;
  endfunction

  // Entry b, behind a in the model, may have entered the FIFO before a.
  protected function bit may_precede(ent_t a, ent_t b);
    bit [63:0] h = hi_of(a);
    return h == '1 || b.tm <= h + order_ps();
  endfunction

  // Entry i may be the hardware's head when the first `skip` entries may be
  // gone: it may have entered before every entry ahead of it from skip on, and
  // no earlier beat of its own burst is among them.
  protected function bit may_lead(int unsigned r, int unsigned i, int unsigned skip);
    for (int unsigned j = skip; j < i; j++)
      if (q[r][j].src == q[r][i].src || !may_precede(q[r][j], q[r][i])) return 1'b0;
    return 1'b1;
  endfunction

  // The DUT RP a remote plane's requests land on (MAS 3.10.2).
  function int unsigned dut_rp(int unsigned plane);
    return (plane < AOU_RP_MAX) ? int'(cfg.l3_cfg.dest_rp[plane]) : plane;
  endfunction

  // An M-port transaction completed: push one entry per error response.
  function void write_dbg_mport(aou_axi_txn t);
    bit [31:0] src;
    bit [63:0] cyc = period_ps == 0 ? 64'd1 : 64'(period_ps);
    bit [63:0] nxt = 0;  // earliest the next re-expanded beat of t can be presented
    if (t.aborted || t.rp >= AOU_RP_MAX) return;
    src = n_src++;
    if (t.dir == AOU_AXI_WR) begin
      if (is_err(t.bresp)) push(t.rp, t.id, t.addr, t.bresp, src, 1'b1, 1'b0, 64'(t.t_done));
    end else begin
      foreach (t.rresp[k]) begin
        bit [63:0] a = lo_of(t) + (64'(k) << t.size);
        bit [63:0] tm = k < t.t_r.size() ? 64'(t.t_r[k]) : 64'(t.t_done);
        aou_axi_txn w;
        if (!is_err(t.rresp[k])) continue;
        // A beat the read aggregator built from narrow remote beats pushes once
        // per narrow beat of the sub-burst within it (the splitter sees the
        // re-expanded beats): t is the sub-burst, its ARADDR the sub-burst's
        // start, MAX_ARBURSTLEN+1 remote beats long, bounded by the read's end.
        // The aggregator presents the narrow beats of the whole burst one per
        // cycle at the earliest, so a beat is not earlier than the one before
        // it, even when the M port accepted the wide beats back to back.
        w = agg_source(t.rp, t, a, tm);
        if (w == null) push(t.rp, t.id, a, t.rresp[k], src, 1'b0, 1'b0, tm);
        else begin
          bit [63:0] nb = 64'd1 << w.size;
          bit [63:0] lo = t.addr & ~(nb - 64'd1);
          bit [63:0] hi = lo_of(w) + ((64'(w.len) + 64'd1) << w.size);
          bit [63:0] sub_hi = lo + (64'(split_arlen(t.rp)) + 64'd1) * nb;
          if (sub_hi < hi) hi = sub_hi;
          late_rd[src] = w;
          if (late_rd.size() > max_hist) begin
            bit [31:0] oldest;
            void'(late_rd.first(oldest));
            late_rd.delete(oldest);
          end
          for (bit [63:0] n = lo; n < hi; n += nb)
            if (n >= a && n < a + (64'd1 << t.size)) begin
              if (nxt < tm) nxt = tm;
              push(t.rp, t.id, n, t.rresp[k], src, 1'b0, 1'b1, nxt);
              nxt += cyc;
            end
        end
      end
    end
  endfunction

  // The remote read, narrower than M-port read t, that t's beat at a was
  // aggregated from: same ID, issued before the beat, covering it. Null when
  // t is at the remote read's own size (or no request is known).
  protected function aou_axi_txn agg_source(int unsigned r, aou_axi_txn t, bit [63:0] a,
                                            bit [63:0] tm);
    foreach (rd_req[r][j]) begin
      aou_axi_txn w = rd_req[r][j];
      if (w.id == t.id && 64'(w.t_addr) <= tm && covers(w, a, r)) return w.size < t.size ? w : null;
    end
    return null;
  endfunction

  // A remote request was sent: remember reads until they complete, and
  // the debug-window accesses in flight. A debug read records the pops
  // completed and in flight at its issue (the driver publishes the same
  // transaction object when it completes).
  function void write_dbg_remote_req(aou_axi_txn t);
    int unsigned r = dut_rp(t.rp);
    bit en;
    if (r >= cfg.n_rp) return;
    if (t.addr == window_of(r, en) && en) begin
      if (t.dir == AOU_AXI_RD) begin
        rd_rec_t c;
        c.t = t;
        c.seq = pop_seq[r];
        c.busy = pop_open[r] != 0;
        c.behind = 1'b0;
        foreach (rd_open[r][j]) if (rd_open[r][j].seq != c.seq) c.behind = !c.busy;
        rd_open[r].push_back(c);
        if (rd_open[r].size() > max_hist) void'(rd_open[r].pop_front());
      end else pop_open[r]++;
    end
    if (t.dir != AOU_AXI_RD) return;
    rd_req[r].push_back(t);
    if (rd_req[r].size() > max_hist) void'(rd_req[r].pop_front());
  endfunction

  function void write_dbg_remote(aou_axi_txn t);
    int unsigned r;
    bit en;
    bit [63:0] w;
    rd_rec_t   rec;
    bit        found = 1'b0;
    r = dut_rp(t.rp);
    if (r >= cfg.n_rp) return;
    if (t.dir == AOU_AXI_RD) begin
      foreach (rd_req[r][j]) if (rd_req[r][j] == t) begin
        rd_req[r].delete(j);
        break;
      end
      foreach (rd_open[r][j]) if (rd_open[r][j].t == t) begin
        rec = rd_open[r][j];
        found = 1'b1;
        rd_open[r].delete(j);
        break;
      end
    end
    w = window_of(r, en);
    if (en && t.addr == w && t.dir != AOU_AXI_RD && pop_open[r] != 0) pop_open[r]--;
    if (t.aborted) return;
    if (!en || t.addr != w) begin
      if (t.dir == AOU_AXI_WR) begin
        wr_hist[r].push_back(t);
        if (wr_hist[r].size() > max_hist) void'(wr_hist[r].pop_front());
      end
      return;
    end
    if (t.dir == AOU_AXI_RD) dbg_read(r, t, rec, found);
    else dbg_pop(r, t);
  endfunction

  // The remote transaction t covers the M-port address a: a is within t's
  // bytes, or at most one RP-width beat below their start, since the width
  // converter and the aggregator base a beat or sub-burst on the RP-width
  // boundary at or below the transaction's start.
  function bit covers(aou_axi_txn t, bit [63:0] a, int unsigned r);
    bit [63:0] lo = lo_of(t) & ~(64'(cfg.rp_bytes[r]) - 64'd1);
    return a >= lo && a < lo_of(t) + ((64'(t.len) + 64'd1) << t.size);
  endfunction

  // Give B entries the address of the remote write they belong to: the write
  // with the same ID in flight over the sub-burst's address when the B
  // returned, the earliest issued when several are (same-ID writes are served
  // in order; wr_hist is in completion order, which for one ID is issue order).
  protected function void resolve(int unsigned r);
    foreach (q[r][i]) begin
      if (!q[r][i].b_sub) continue;
      foreach (wr_hist[r][j]) begin
        aou_axi_txn w = wr_hist[r][j];
        if (w.id == q[r][i].id && 64'(w.t_addr) <= q[r][i].tm && q[r][i].tm <= 64'(w.t_done) &&
            covers(w, q[r][i].addr, r))
        begin
          // The width converter aligns a write wider than the RP down to its AWSIZE.
          q[r][i].addr = (int'(w.size) > $clog2(cfg.rp_bytes[r])) ? lo_of(w) : w.addr;
          q[r][i].b_sub = 1'b0;
          break;
        end
      end
    end
  endfunction

  // Entry e's address matches the observed a.
  static function bit addr_match(ent_t e, bit [63:0] a);
    if (!e.b_sub) return e.addr == a;
    return a <= e.addr && a[63:12] == e.addr[63:12];
  endfunction

  protected function void push(int unsigned r, bit [9:0] id, bit [63:0] addr, bit [1:0] resp,
                               bit [31:0] src, bit b_sub, bit late, bit [63:0] tm);
    ent_t e;
    ent_t gone;
    int   pos;
    e.id = id;
    e.addr = addr;
    e.resp = resp;
    e.tm = tm;
    e.src = src;
    e.b_sub = b_sub;
    e.late = late;
    n_push++;
    // In handshake order; a beat published late goes where its handshake was.
    pos = q[r].size();
    while (pos > (head_known[r] ? 1 : 0) && q[r][pos - 1].tm > e.tm) pos--;
    q[r].insert(pos, e);
    if (q[r].size() > depth + pend[r]) begin
      // Full: the latest arrival is the one the hardware dropped. A drop leaves
      // which entry was kept unknown when the dropped entry may have entered
      // before any retained entry of another transaction (within the ordering
      // window of the last one, or behind a re-expanded beat whose read has not
      // ended); the beats of one burst are in order.
      gone = q[r][depth + pend[r]];
      q[r].delete(depth + pend[r]);
      n_drop++;
      foreach (q[r][i])
        if (q[r][i].src != gone.src && may_precede(q[r][i], gone)) unsure[r] = 1'b1;
      `uvm_info(get_type_name(), $sformatf("RP%0d FIFO full: id=%0h addr=%0h resp=%0d dropped", r,
                                           gone.id, gone.addr, gone.resp), UVM_MEDIUM)
      if (gone.tm == e.tm && gone.src == e.src && gone.addr == e.addr) return;
    end
    `uvm_info(get_type_name(), $sformatf("RP%0d FIFO push: id=%0h addr=%0h resp=%0d (%0d held)", r,
                                         e.id, e.addr, e.resp, q[r].size()), UVM_MEDIUM)
  endfunction

  // A debug read t of RP r completed; rec is its issue record (found = 0 when
  // it was issued before the window was enabled: judged as overlapping).
  protected function void dbg_read(int unsigned r, aou_axi_txn t, rd_rec_t rec, bit found);
    bit overlap = !found || rec.busy || rec.seq != pop_seq[r] || pop_open[r] != 0;
    n_read++;
    aou_rule_log::check("T1-E03", get_type_name());
    foreach (t.rresp[k]) begin
      if (t.rresp[k] != AOU_AXI_OKAY) begin
        aou_rule_log::fire("T1-E03", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            "T1-E03: RP%0d debug FIFO read RRESP %0d (beat %0d of %0d)", r, t.rresp[k], k,
            t.rresp.size()))
        break;
      end
    end
    check_lanes(r, t);
    if (found && !overlap && rec.behind) n_behind++;
    check_head(r, t, overlap, found ? rec.seq : 0, !found);
    prune_taken(r);
  endfunction

  // Forget the entries removed by pops that every debug read in flight was
  // issued after: no read can return them.
  protected function void prune_taken(int unsigned r);
    int unsigned oldest;
    if (rd_open[r].size() == 0) begin
      taken[r].delete();
      return;
    end
    oldest = rd_open[r][0].seq;
    foreach (rd_open[r][j]) if (rd_open[r][j].seq < oldest) oldest = rd_open[r][j].seq;
    for (int i = taken[r].size() - 1; i >= 0; i--)
      if (taken[r][i].seq <= oldest) taken[r].delete(i);
    while (taken[r].size() > max_hist) void'(taken[r].pop_front());
  endfunction

  protected function void dbg_pop(int unsigned r, aou_axi_txn t);
    n_pop++;
    aou_rule_log::check("T1-E03", get_type_name());
    if (t.bresp != AOU_AXI_OKAY) begin
      aou_rule_log::fire("T1-E03", get_type_name());
      `uvm_error(get_type_name(), $sformatf("T1-E03: RP%0d debug FIFO pop BRESP %0d", r, t.bresp))
    end
    pop_seq[r]++;
    if (head_known[r]) begin
      take_front(r, 1);
      head_known[r] = 1'b0;
    end else if (q[r].size() != 0) begin
      pend[r]++;
      settle(r);
    end
    // A drop the model could not order left the entry kept unknown, not the
    // count: once the pops have drained the model, the FIFO is empty too.
    if (q[r].size() == 0) unsure[r] = 1'b0;
  endfunction

  // Remove the first n entries. A debug read in flight may have sampled them
  // before the pop: they are tagged with the latest pop, at or after the one
  // that took them.
  protected function void take_front(int unsigned r, int unsigned n);
    repeat (n) begin
      if (q[r].size() == 0) return;
      if (rd_open[r].size() != 0) begin
        taken_t k;
        k.e = q[r][0];
        k.seq = pop_seq[r];
        taken[r].push_back(k);
      end
      void'(q[r].pop_front());
    end
  endfunction

  // The pending pops took the hardware's first pend[r] entries: when no entry
  // beyond those may be among them, they took exactly those.
  protected function void settle(int unsigned r);
    int unsigned n = 0;
    foreach (q[r][i]) if (may_lead(r, i, pend[r] - 1)) n++;
    if (n > pend[r]) return;
    take_front(r, n);
    pend[r] = 0;
  endfunction

  // A read that no pop overlapped returned entry i: it is the head. The
  // pending pops took the entries that may have been ahead of it, when there
  // are exactly as many as pops; otherwise the model cannot tell which.
  protected function void learn_head(int unsigned r, int unsigned i);
    ent_t h = q[r][i];
    ent_t rest[$];
    int unsigned n = 0;
    foreach (q[r][j]) begin
      if (j == i) continue;
      if (pend[r] != 0 && may_lead(r, j, pend[r] - 1)) n++;
      else rest.push_back(q[r][j]);
    end
    if (n != pend[r]) begin
      unsure[r] = 1'b1;
      return;
    end
    q[r] = rest;
    q[r].push_front(h);
    pend[r] = 0;
    head_known[r] = 1'b1;
  endfunction

  // T1-E19 on a debug read t of RP r.
  protected function void check_lanes(int unsigned r, aou_axi_txn t);
    int unsigned rw = t.data_bytes;
    int unsigned pw = cfg.rp_bytes[r];
    int unsigned bad = 0;
    int unsigned total = 0;
    int unsigned bk = 0;
    int unsigned bl = 0;
    if (t.data.size() == 0) return;
    for (int unsigned k = 0; k < t.data.size(); k++) begin
      if (rw >= pw) begin
        for (int unsigned l = 0; l < rw / pw; l++) begin
          bit diff = 1'b0;
          total++;
          for (int unsigned b = 0; b < pw; b++)
            if (t.data[k][8*(l*pw+b) +: 8] != t.data[0][8*b +: 8]) diff = 1'b1;
          if (diff && bad++ == 0) begin
            bk = k;
            bl = l;
          end
        end
      end else if (k >= pw / rw) begin
        bit diff = 1'b0;
        total++;
        for (int unsigned b = 0; b < rw; b++)
          if (t.data[k][8*b +: 8] != t.data[k % (pw / rw)][8*b +: 8]) diff = 1'b1;
        if (diff && bad++ == 0) bk = k;
      end
    end
    aou_rule_log::check("T1-E19", get_type_name());
    if (bad != 0) begin
      aou_rule_log::fire("T1-E19", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"T1-E19: RP%0d debug FIFO read: %0d of %0d RP-wide lanes differ from the head entry ",
           "(first: beat %0d lane %0d; %0d beats of %0d bytes, %0d-byte RP)"},
          r, bad, total, bk, bl, t.data.size(), rw, pw))
    end
  endfunction

  // T1-E02: beat 0 holds the predicted head (or an entry pushed with it). A
  // read issued after seq pops had completed may also return an entry a later
  // pop removed (any removed entry when its issue is unknown).
  protected function void check_head(int unsigned r, aou_axi_txn t, bit overlap,
                                     int unsigned seq, bit any_taken);
    bit [1023:0] d;
    bit [9:0]    id;
    bit [63:0]   addr;
    bit [1:0]    resp;
    string       exp = "";
    int unsigned gone = pop_open[r] + pend[r];  // leading entries the pops may have taken
    if (t.data.size() == 0 || unsure[r]) return;
    // A read overlapping a pop returns the head sampled when the read became
    // active, before or after the pop: an entry the pop removed while the read
    // was in flight, or the entry behind the one a pop still in flight takes;
    // the FIFO may have been empty by then, and nothing is predicted for that.
    if (overlap) n_overlap++;
    if (q[r].size() <= gone) return;
    resolve(r);
    d = t.data[0];
    resp = d[1:0];
    addr = d[65:2];
    id = d[75:66];
    aou_rule_log::check("T1-E02", get_type_name());
    foreach (taken[r][i]) begin
      ent_t k = taken[r][i].e;
      if ((any_taken || taken[r][i].seq > seq) && k.id == id && addr_match(k, addr) &&
          k.resp == resp)
        return;
    end
    // Candidates for the head: the entries that may have entered before every
    // entry ahead of them (pushed within order_cycles of each, or behind a
    // re-expanded beat before its read ended); a beat whose burst has an
    // earlier beat ahead of it is not one.
    foreach (q[r][i]) begin
      if (!may_lead(r, i, gone)) continue;
      if (q[r][i].id == id && addr_match(q[r][i], addr) && q[r][i].resp == resp) begin
        if (q[r][i].b_sub) n_unresolved++;
        if (!overlap) learn_head(r, i);
        return;
      end
      exp = {exp, exp == "" ? "" : " or ",
             $sformatf("id=%0h addr=%0h%s resp=%0d", q[r][i].id, q[r][i].addr,
                       q[r][i].b_sub ? " (sub-burst)" : "", q[r][i].resp)};
    end
    foreach (taken[r][i])
      if (any_taken || taken[r][i].seq > seq)
        exp = {exp, exp == "" ? "" : " or ",
               $sformatf("id=%0h addr=%0h resp=%0d (popped)", taken[r][i].e.id, taken[r][i].e.addr,
                         taken[r][i].e.resp)};
    aou_rule_log::fire("T1-E02", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
        "T1-E02: RP%0d FIFO head id=%0h addr=%0h resp=%0d, expected %s (%0d entries held)", r, id,
        addr, resp, exp, q[r].size()))
  endfunction

  function void report_phase(uvm_phase phase);
    if (n_push + n_read + n_pop != 0)
      `uvm_info(get_type_name(), $sformatf(
          {"debug FIFO: %0d pushes (%0d dropped), %0d reads (%0d overlapping a pop, %0d issued ",
           "after a pop an earlier read overlapped), %0d pops, %0d B heads unresolved"},
          n_push, n_drop, n_read, n_overlap, n_behind, n_pop, n_unresolved), UVM_LOW)
  endfunction
endclass
