// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX arbitration order (MAS 3.2.1) from the requests the DUT sends (L3
// ap_rx_msg). The vseq builds a backlog behind hold_tx(), lower tiers first,
// then calls check_round() with each RP's tier and the addresses the S ports
// accepted before release_tx(). Per message class (ReadReq, WriteReq,
// WriteData), with a = first and b = last backlogged message of a tier:
// - FEAT-R11: no lower-tier message between a and b (no promotion expected).
//   For WriteData, a and b count only writes whose W data the S port had
//   also accepted before release: QoS orders requests (MAS 3.2.1), and the
//   DUT may send a lower tier's WriteData while a higher tier's open burst
//   has no beat to send yet (other RPs' bursts may go on meanwhile);
// - FEAT-R12: with a short starvation timer the lowest tier is promoted and
//   gets in between the highest tier's a and b;
// - FEAT-R14: equal tiers (round-robin) never grant one RP twice in a row
//   while the other still has a backlogged request;
// - FEAT-R13: the round really had both tiers waiting at the arbiter (a
//   backlogged lower-tier message after a), else it proves nothing.
// Requests carry the address, so the local RP is (addr - base) / stride.
// WriteData carries no address: the k-th WriteData on a wire RP belongs to the k-th
// WriteReq on it (single-beat writes). It can precede its WriteReq, in the
// same flit, so it is matched when the round is checked, not on arrival.
class aou_qos_order_chk extends uvm_component;
  `uvm_component_utils(aou_qos_order_chk)

  typedef struct {
    time       t;
    bit [3:0]  mt;
    int        rp;      // local RP, -1 if unknown
    bit [63:0] addr;
    int        wrp;     // WriteData: wire RP and index among its WriteData
    int        widx;
  } ent_t;

  typedef enum int {QOS_ORDER, QOS_PROMOTE, QOS_RR} expect_e;

  uvm_tlm_analysis_fifo #(aou_msg) fifo;
  bit [63:0]   base = 64'h0000_0010_0000_0000;
  bit [63:0]   stride = 64'h0000_0001_0000_0000;
  ent_t        ents[$];
  int unsigned n_rounds;
  int unsigned n_checked[3];
  protected bit [63:0] wreq_addr[4][$];
  protected int unsigned n_wdata[4];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    fifo = new("fifo", this);
  endfunction

  function int local_rp(bit [63:0] a);
    if (a < base) return -1;
    return int'((a - base) / stride);
  endfunction

  function void take(aou_msg m);
    aou_msg_req  rq;
    ent_t e;
    e.t = $time;
    e.mt = m.msg_type;
    e.rp = -1;
    if ($cast(rq, m) && m.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ}) begin
      e.addr = rq.addr;
      e.rp = local_rp(rq.addr);
      if (m.msg_type == AOU_MT_WREQ) wreq_addr[m.rp].push_back(rq.addr);
    end else if (m.msg_type inside {AOU_MT_WDATA, AOU_MT_WDATAF}) begin
      e.wrp = int'(m.rp);
      e.widx = int'(n_wdata[m.rp]++);
    end else return;
    `uvm_info(get_type_name(), $sformatf("%s wire RP%0d addr %0h (WriteData #%0d)", cname(e.mt),
                                         m.rp, e.addr, e.widx), UVM_HIGH)
    ents.push_back(e);
  endfunction

  task run_phase(uvm_phase phase);
    aou_msg m;
    forever begin
      fifo.get(m);
      take(m);
    end
  endtask

  function void flush();
    aou_msg m;
    while (fifo.try_get(m)) take(m);
  endfunction

  // tier[r]: 0 = RP r not in the round, else higher is served first. inq:
  // addresses the S ports accepted before release (the backlog).
  // inq_w: the writes among them whose W data was accepted before release too.
  function void check_round(time t_from, int tier[4], bit inq[bit [63:0]],
                            bit inq_w[bit [63:0]], expect_e exp, string tag);
    bit [3:0] classes[3] = '{AOU_MT_RREQ, AOU_MT_WREQ, AOU_MT_WDATA};
    flush();
    foreach (ents[i]) begin
      if (ents[i].mt inside {AOU_MT_WDATA, AOU_MT_WDATAF} && ents[i].rp < 0 &&
          ents[i].widx < wreq_addr[ents[i].wrp].size()) begin
        ents[i].addr = wreq_addr[ents[i].wrp][ents[i].widx];
        ents[i].rp = local_rp(ents[i].addr);
      end
    end
    n_rounds++;
    foreach (classes[c]) begin
      ent_t s[$];
      bit   q[$];
      bit   qd[$];
      int   hi = 0;
      int   lo = 99;
      int   hrp = -1;
      int   lrp = -1;
      foreach (ents[i]) begin
        if (ents[i].t < t_from || ents[i].rp < 0 || ents[i].rp > 3) continue;
        if (ents[i].mt != classes[c] &&
            !(classes[c] == AOU_MT_WDATA && ents[i].mt == AOU_MT_WDATAF)) continue;
        if (tier[ents[i].rp] == 0) continue;
        s.push_back(ents[i]);
        q.push_back(inq.exists(ents[i].addr));
        qd.push_back(classes[c] == AOU_MT_WDATA ? inq.exists(ents[i].addr) &&
                     inq_w.exists(ents[i].addr) : inq.exists(ents[i].addr));
      end
      if (s.size() == 0) continue;
      foreach (tier[r]) begin
        if (tier[r] == 0) continue;
        if (tier[r] > hi || (tier[r] == hi && exp == QOS_RR)) begin hi = tier[r]; hrp = r; end
      end
      foreach (tier[r]) begin
        if (tier[r] == 0 || r == hrp) continue;
        if (tier[r] < lo || lrp < 0) begin lo = tier[r]; lrp = r; end
      end
      if (lrp < 0) continue;
      n_checked[c]++;
      if (exp == QOS_RR) check_rr(s, q, hrp, lrp, tag, classes[c]);
      else check_tiers(s, q, qd, tier, exp, hi, lo, tag, classes[c]);
    end
  endfunction

  protected function string cname(bit [3:0] mt);
    case (mt)
      AOU_MT_RREQ: return "ReadReq";
      AOU_MT_WREQ: return "WriteReq";
      default:     return "WriteData";
    endcase
  endfunction

  protected function string seq2string(ent_t s[$], bit q[$], int tier[4]);
    string r = "";
    foreach (s[i]) r = {r, $sformatf(" %0d%s", tier[s[i].rp], q[i] ? "" : "'")};
    return r;
  endfunction

  protected function void bounds(ent_t s[$], bit q[$], int tier[4], int t, output int a,
                                 output int b);
    a = -1;
    b = -1;
    foreach (s[i]) begin
      if (q[i] && tier[s[i].rp] == t) begin
        if (a < 0) a = i;
        b = i;
      end
    end
  endfunction

  // qd: q narrowed for FEAT-R11 (see the header; equal to q except for WriteData).
  protected function void check_tiers(ent_t s[$], bit q[$], bit qd[$], int tier[4],
                                      expect_e exp, int hi, int lo, string tag, bit [3:0] mt);
    string seq = seq2string(s, q, tier);
    int a, b, n_between;
    bit backlog = 1'b0;
    bounds(s, q, tier, hi, a, b);
    if (a < 0) return;
    for (int i = a + 1; i < s.size(); i++) if (q[i] && tier[s[i].rp] == lo) backlog = 1'b1;
    if (!backlog) begin
      `uvm_error(get_type_name(), $sformatf(
          {"FEAT-R13: %s %s: no tier-%0d request still waiting after the first tier-%0d one; ",
           "tiers in send order (' = after release):%s"},
          tag, cname(mt), lo, hi, seq))
      return;
    end
    n_between = 0;
    for (int i = a + 1; i < b; i++) if (tier[s[i].rp] == lo) n_between++;
    if (exp == QOS_PROMOTE) begin
      if (n_between == 0)
        `uvm_error(get_type_name(), $sformatf(
            {"FEAT-R12: %s %s: tier-%0d requests not promoted past the starvation timer; ",
             "tiers in send order (' = after release):%s"},
            tag, cname(mt), lo, seq))
      return;
    end
    // Every pair of tiers, not just the extremes.
    for (int t1 = hi; t1 > 0; t1--) begin
      int a1, b1;
      bounds(s, qd, tier, t1, a1, b1);
      if (a1 < 0) continue;
      for (int i = a1 + 1; i < b1; i++) begin
        if (tier[s[i].rp] < t1) begin
          `uvm_error(get_type_name(), $sformatf(
              {"FEAT-R11: %s %s: tier-%0d request sent while tier-%0d requests were queued; ",
               "tiers in send order (' = after release):%s"},
              tag, cname(mt), tier[s[i].rp], t1, seq))
          return;
        end
      end
    end
    `uvm_info(get_type_name(), $sformatf("%s %s: order ok:%s", tag, cname(mt), seq), UVM_LOW)
  endfunction

  protected function void check_rr(ent_t s[$], bit q[$], int hrp, int lrp, string tag,
                                   bit [3:0] mt);
    int tier[4] = '{0, 0, 0, 0};
    string seq;
    int a, b;
    int prev = -1;
    bit backlog = 1'b0;
    tier[hrp] = 2;
    tier[lrp] = 1;
    seq = seq2string(s, q, tier);
    bounds(s, q, tier, 2, a, b);
    if (a < 0) return;
    for (int i = a + 1; i < s.size(); i++) if (q[i] && s[i].rp == lrp) backlog = 1'b1;
    if (!backlog) begin
      `uvm_error(get_type_name(), $sformatf(
          {"FEAT-R13: %s %s: RP%0d had nothing waiting after RP%0d's first request; ",
           "RPs in send order:%s"},
          tag, cname(mt), lrp, hrp, seq))
      return;
    end
    for (int i = a; i <= b; i++) begin
      if (s[i].rp != hrp) begin
        prev = -1;
        continue;
      end
      if (prev >= 0) begin
        bit l_waiting = 1'b0;
        for (int j = i + 1; j < s.size(); j++) if (q[j] && s[j].rp == lrp) l_waiting = 1'b1;
        if (l_waiting) begin
          `uvm_error(get_type_name(), $sformatf(
              {"FEAT-R14: %s %s: RP%0d granted twice in a row while RP%0d was waiting ",
               "(round-robin); RPs (2 = RP%0d) in send order:%s"},
              tag, cname(mt), hrp, lrp, hrp, seq))
          return;
        end
      end
      prev = i;
    end
    `uvm_info(get_type_name(), $sformatf("%s %s: round-robin ok:%s", tag, cname(mt), seq), UVM_LOW)
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        "%0d rounds; checked ReadReq %0d, WriteReq %0d, WriteData %0d",
                                         n_rounds, n_checked[0], n_checked[1], n_checked[2]),
              UVM_LOW)
  endfunction
endclass
