// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Functional coverage of what crosses the link (plan 4.25-4.28, 4.31, 5.23-5.26,
// 8.14), in every T1 test:
// - attr_cg: AxQOS, AxPROT and the legal AxCACHE values the far side received,
//   per path and direction (sampled by aou_t1_attr_chk on each matched request).
// - excl_cg: exclusive transactions by the subordinate's answer (EXOKAY: the
//   exclusive pair held; OKAY: it failed), per path and direction.
// - chan_cg: channel orderings AXI4 allows: an S-port W burst presented before
//   its AW (A3.3.1; the DUT takes it only once the AW is accepted, so
//   w_taken_before_aw is ignored); R beats of different IDs
//   interleaved on an M port, in the ReadData the remote die sent, and on an
//   S port (A5; ReadData carries RID and RLAST, AoU 5.5).
// - width_cg: every completed request by path, direction, the DUT RP's width,
//   the remote die's native width on that RP and the requester's AxSIZE (full
//   bus width or narrower), so the report shows which of the nine width
//   pairings ran, each way (plan 2.14). Fed by the S-port managers (l2r) and
//   the remote managers (r2l). The widths are the configured ones. On l2r
//   the DUT's part does not depend on the remote width: those cells cover the
//   remote model's converter (the DUT's part is DUT width x ARSIZE). On r2l
//   they cover the DUT's upsizers and downsizers, per direction.
// - split_cg: the remote model's splitter, by its maximum burst length and
//   whether the request was split (sampled by aou_t1_l4a_adapter).
// - small_cg: requests below 32 bytes (AxSIZE 0..4) by path and direction,
//   from the same requester samples as width_cg; 1-, 2- and 16-byte bins are
//   tagged "rare".
class aou_t1_xfer_cov extends uvm_component;
  `uvm_component_utils(aou_t1_xfer_cov)

  typedef enum int {EV_W_LEAD = 0, EV_W_EARLY = 1, EV_M_ILV = 2, EV_MSG_ILV = 3,
                    EV_S_ILV = 4} ev_e;

  uvm_tlm_analysis_fifo #(aou_msg) tb_fifo;   // remote die -> DUT
  uvm_tlm_analysis_fifo #(aou_axi_txn) req_fifo;  // completed requests, both paths
  int unsigned dut_bytes[4] = '{default: 64};     // DUT RP widths
  int unsigned rem_bytes[4] = '{default: 64};     // remote die's native width per RP
  aou_axi_vif_t s_vif[];
  aou_axi_vif_t m_vif[];

  protected int       cv_path;
  protected int       cv_dir;
  protected bit [3:0] cv_qos;
  protected bit [2:0] cv_prot;
  protected bit [3:0] cv_cache;
  protected bit [1:0] cv_resp;
  protected int       cv_ev;
  protected int       cv_dut;
  protected int       cv_rem;
  protected int       cv_size;
  protected int       cv_req;
  protected int       cv_max;
  protected int       cv_split;

  protected bit [9:0] msg_id[4];
  protected bit       msg_open[4];

  covergroup attr_cg;
    cp_path: coverpoint cv_path {
      `AOU_XFER_FC_PATH(AOU_FC_CG)
    }
    cp_dir: coverpoint cv_dir {
      `AOU_XFER_FC_DIR(AOU_FC_CG)
    }
    cp_qos: coverpoint cv_qos {
      `AOU_XFER_FC_QOS(AOU_FC_CG)
    }
    cp_prot: coverpoint cv_prot {
      `AOU_XFER_FC_PROT(AOU_FC_CG)
    }
    cp_cache: coverpoint cv_cache {
      `AOU_XFER_FC_CACHE(AOU_FC_CG)
    }
    x_qos: cross cp_path, cp_dir, cp_qos;
    x_prot: cross cp_path, cp_dir, cp_prot;
    x_cache: cross cp_path, cp_dir, cp_cache;
  endgroup

  covergroup excl_cg;
    cp_path: coverpoint cv_path {
      `AOU_XFER_FC_PATH(AOU_FC_CG)
    }
    cp_dir: coverpoint cv_dir {
      `AOU_XFER_FC_DIR(AOU_FC_CG)
    }
    cp_resp: coverpoint cv_resp {
      `AOU_XFER_FC_EXRESP(AOU_FC_CG)
    }
    x_excl: cross cp_path, cp_dir, cp_resp;
  endgroup

  covergroup chan_cg;
    cp_event: coverpoint cv_ev {
      `AOU_XFER_FC_EVENT(AOU_FC_CG)
    }
  endgroup

  covergroup width_cg;
    cp_path: coverpoint cv_path {
      `AOU_XFER_FC_PATH(AOU_FC_CG)
    }
    cp_dir: coverpoint cv_dir {
      `AOU_XFER_FC_DIR(AOU_FC_CG)
    }
    cp_dut: coverpoint cv_dut {
      `AOU_XFER_FC_WIDTH(AOU_FC_CG)
    }
    cp_rem: coverpoint cv_rem {
      `AOU_XFER_FC_WIDTH(AOU_FC_CG)
    }
    cp_size: coverpoint cv_size {
      `AOU_XFER_FC_SIZE(AOU_FC_CG)
    }
    cp_req: coverpoint cv_req {
      `AOU_XFER_FC_REQ(AOU_FC_CG)
    }
    x_pair: cross cp_dut, cp_rem;
    x_pair_dir: cross cp_path, cp_dir, cp_dut, cp_rem;
    x_pair_req: cross cp_path, cp_dut, cp_rem, cp_req;
    x_pair_size: cross cp_path, cp_dir, cp_dut, cp_rem, cp_size;
  endgroup

  covergroup small_cg;
    cp_path: coverpoint cv_path {
      `AOU_XFER_FC_PATH(AOU_FC_CG)
    }
    cp_dir: coverpoint cv_dir {
      `AOU_XFER_FC_DIR(AOU_FC_CG)
    }
    cp_small: coverpoint cv_size {
      `AOU_XFER_FC_SMALL(AOU_FC_CG)
    }
    x_small: cross cp_path, cp_dir, cp_small;
  endgroup

  covergroup split_cg;
    cp_max: coverpoint cv_max {
      `AOU_XFER_FC_MAX_BURST(AOU_FC_CG)
    }
    cp_split: coverpoint cv_split {
      `AOU_XFER_FC_SPLIT(AOU_FC_CG)
    }
    x_max_split: cross cp_max, cp_split;
  endgroup

  protected aou_fc_group fc_attr;
  protected aou_fc_group fc_excl;
  protected aou_fc_group fc_chan;
  protected aou_fc_group fc_width;
  protected aou_fc_group fc_split;
  protected aou_fc_group fc_small;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tb_fifo = new("tb_fifo", this);
    req_fifo = new("req_fifo", this);
    attr_cg = new();
    excl_cg = new();
    chan_cg = new();
    width_cg = new();
    split_cg = new();
    small_cg = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_attr = db.group("xfer.attr_cg", fresh);
    if (fresh) begin
      p = fc_attr.cp("cp_path"); `AOU_XFER_FC_PATH(AOU_FC_REG)
      p = fc_attr.cp("cp_dir"); `AOU_XFER_FC_DIR(AOU_FC_REG)
      p = fc_attr.cp("cp_qos"); `AOU_XFER_FC_QOS(AOU_FC_REG)
      p = fc_attr.cp("cp_prot"); `AOU_XFER_FC_PROT(AOU_FC_REG)
      p = fc_attr.cp("cp_cache"); `AOU_XFER_FC_CACHE(AOU_FC_REG)
      void'(fc_attr.add_cross("x_qos", "cp_path cp_dir cp_qos"));
      void'(fc_attr.add_cross("x_prot", "cp_path cp_dir cp_prot"));
      void'(fc_attr.add_cross("x_cache", "cp_path cp_dir cp_cache"));
    end
    fc_excl = db.group("xfer.excl_cg", fresh);
    if (fresh) begin
      p = fc_excl.cp("cp_path"); `AOU_XFER_FC_PATH(AOU_FC_REG)
      p = fc_excl.cp("cp_dir"); `AOU_XFER_FC_DIR(AOU_FC_REG)
      p = fc_excl.cp("cp_resp"); `AOU_XFER_FC_EXRESP(AOU_FC_REG)
      void'(fc_excl.add_cross("x_excl", "cp_path cp_dir cp_resp"));
    end
    fc_chan = db.group("xfer.chan_cg", fresh);
    if (fresh) begin
      p = fc_chan.cp("cp_event"); `AOU_XFER_FC_EVENT(AOU_FC_REG)
    end
    fc_width = db.group("xfer.width_cg", fresh);
    if (fresh) begin
      p = fc_width.cp("cp_path"); `AOU_XFER_FC_PATH(AOU_FC_REG)
      p = fc_width.cp("cp_dir"); `AOU_XFER_FC_DIR(AOU_FC_REG)
      p = fc_width.cp("cp_dut"); `AOU_XFER_FC_WIDTH(AOU_FC_REG)
      p = fc_width.cp("cp_rem"); `AOU_XFER_FC_WIDTH(AOU_FC_REG)
      p = fc_width.cp("cp_size"); `AOU_XFER_FC_SIZE(AOU_FC_REG)
      p = fc_width.cp("cp_req"); `AOU_XFER_FC_REQ(AOU_FC_REG)
      void'(fc_width.add_cross("x_pair", "cp_dut cp_rem"));
      void'(fc_width.add_cross("x_pair_dir", "cp_path cp_dir cp_dut cp_rem"));
      void'(fc_width.add_cross("x_pair_req", "cp_path cp_dut cp_rem cp_req"));
      p = fc_width.add_cross("x_pair_size", "cp_path cp_dir cp_dut cp_rem cp_size");
      `AOU_XFER_FC_X_SIZE(AOU_FC_REG)
    end
    fc_small = db.group("xfer.small_cg", fresh);
    if (fresh) begin
      p = fc_small.cp("cp_path"); `AOU_XFER_FC_PATH(AOU_FC_REG)
      p = fc_small.cp("cp_dir"); `AOU_XFER_FC_DIR(AOU_FC_REG)
      p = fc_small.cp("cp_small"); `AOU_XFER_FC_SMALL(AOU_FC_REG)
      `AOU_XFER_FC_SMALL_RARE(AOU_FC_REG)
      p = fc_small.add_cross("x_small", "cp_path cp_dir cp_small");
      `AOU_XFER_FC_X_SMALL_RARE(AOU_FC_REG)
    end
    fc_split = db.group("xfer.split_cg", fresh);
    if (fresh) begin
      p = fc_split.cp("cp_max"); `AOU_XFER_FC_MAX_BURST(AOU_FC_REG)
      p = fc_split.cp("cp_split"); `AOU_XFER_FC_SPLIT(AOU_FC_REG)
      p = fc_split.add_cross("x_max_split", "cp_max cp_split");
      `AOU_XFER_FC_X_SPLIT(AOU_FC_REG)
    end
  endfunction

  // p: 0 local->remote, 1 remote->local; f: the request as the far side got it.
  function void sample_attr(int p, aou_axi_txn f);
    cv_path = p;
    cv_dir = (f.dir == AOU_AXI_WR) ? 0 : 1;
    cv_qos = f.qos;
    cv_prot = f.prot;
    cv_cache = f.cache;
    attr_cg.sample();
    fc_attr.sample(cv_path, cv_dir, int'(cv_qos), int'(cv_prot), int'(cv_cache));
  endfunction

  function void sample_excl(int p, int d, bit [1:0] resp);
    cv_path = p;
    cv_dir = d;
    cv_resp = resp;
    excl_cg.sample();
    fc_excl.sample(cv_path, cv_dir, int'(cv_resp));
  endfunction

  function void sample_ev(ev_e e);
    cv_ev = int'(e);
    chan_cg.sample();
    fc_chan.sample(cv_ev);
  endfunction

  // One request through the remote model's splitter.
  function void sample_split(int unsigned max_burst, bit split);
    cv_max = int'(max_burst);
    cv_split = split ? 1 : 0;
    split_cg.sample();
    fc_split.sample(cv_max, cv_split);
  endfunction

  // A completed request: local_side marks an S-port request (l2r), otherwise
  // a remote manager's (r2l). Aborted requests prove nothing.
  function void take_req(aou_axi_txn t);
    int unsigned own;
    if (t.aborted || t.rp > 3) return;
    cv_path = t.local_side ? 0 : 1;
    cv_dir = (t.dir == AOU_AXI_WR) ? 0 : 1;
    cv_dut = int'(dut_bytes[t.rp]);
    cv_rem = int'(rem_bytes[t.rp]);
    cv_size = int'(t.size);
    own = t.local_side ? dut_bytes[t.rp] : rem_bytes[t.rp];
    cv_req = (t.beat_bytes() < own) ? 1 : 0;
    width_cg.sample();
    fc_width.sample(cv_path, cv_dir, cv_dut, cv_rem, cv_size, cv_req);
    if (t.size < 3'd5) begin
      small_cg.sample();
      fc_small.sample(cv_path, cv_dir, cv_size);
    end
  endfunction

  function void take_tb(aou_msg m);
    aou_msg_rdata d;
    if (m.msg_type != AOU_MT_RDATA || !$cast(d, m)) return;
    if (msg_open[d.rp] && d.id != msg_id[d.rp]) sample_ev(EV_MSG_ILV);
    msg_id[d.rp] = d.id;
    msg_open[d.rp] = !d.last;
  endfunction

  // W bursts are counted from their first beat; burst k belongs to the k-th AW.
  protected task watch_s(int r);
    int unsigned n_aw = 0;
    int unsigned n_wb = 0;
    bit in_burst = 1'b0;
    bit led = 1'b0;
    bit early = 1'b0;
    bit r_open = 1'b0;
    bit [9:0] r_id = '0;
    forever begin
      @(s_vif[r].mon_cb);
      if (s_vif[r].mon_cb.resetn !== 1'b1) begin
        n_aw = 0;
        n_wb = 0;
        in_burst = 1'b0;
        led = 1'b0;
        r_open = 1'b0;
        continue;
      end
      if (s_vif[r].mon_cb.wvalid === 1'b1 && !in_burst && !led && n_wb >= n_aw &&
          s_vif[r].mon_cb.awvalid !== 1'b1) begin
        sample_ev(EV_W_LEAD);
        led = 1'b1;
      end
      if (s_vif[r].mon_cb.wvalid === 1'b1 && s_vif[r].mon_cb.wready === 1'b1) begin
        if (!in_burst) begin
          n_wb++;
          early = 1'b0;
        end
        if (!early && n_wb > n_aw + ((s_vif[r].mon_cb.awvalid === 1'b1 &&
                                      s_vif[r].mon_cb.awready === 1'b1) ? 1 : 0)) begin
          sample_ev(EV_W_EARLY);
          early = 1'b1;
        end
        in_burst = (s_vif[r].mon_cb.wlast !== 1'b1);
        led = 1'b0;
      end
      if (s_vif[r].mon_cb.awvalid === 1'b1 && s_vif[r].mon_cb.awready === 1'b1) n_aw++;
      if (s_vif[r].mon_cb.rvalid === 1'b1 && s_vif[r].mon_cb.rready === 1'b1) begin
        if (r_open && s_vif[r].mon_cb.rid != r_id) sample_ev(EV_S_ILV);
        r_id = s_vif[r].mon_cb.rid;
        r_open = (s_vif[r].mon_cb.rlast !== 1'b1);
      end
    end
  endtask

  protected task watch_m(int r);
    bit r_open = 1'b0;
    bit [9:0] r_id = '0;
    forever begin
      @(m_vif[r].mon_cb);
      if (m_vif[r].mon_cb.resetn !== 1'b1) begin
        r_open = 1'b0;
        continue;
      end
      if (m_vif[r].mon_cb.rvalid === 1'b1 && m_vif[r].mon_cb.rready === 1'b1) begin
        if (r_open && m_vif[r].mon_cb.rid != r_id) sample_ev(EV_M_ILV);
        r_id = m_vif[r].mon_cb.rid;
        r_open = (m_vif[r].mon_cb.rlast !== 1'b1);
      end
    end
  endtask

  task run_phase(uvm_phase phase);
    aou_msg m;
    foreach (s_vif[r]) begin
      automatic int rr = r;
      fork watch_s(rr); join_none
    end
    foreach (m_vif[r]) begin
      automatic int rr = r;
      fork watch_m(rr); join_none
    end
    fork
      forever begin
        aou_axi_txn t;
        req_fifo.get(t);
        take_req(t);
      end
    join_none
    forever begin
      tb_fifo.get(m);
      take_tb(m);
    end
  endtask
endclass
