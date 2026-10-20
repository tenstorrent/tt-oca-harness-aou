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
class aou_t1_xfer_cov extends uvm_component;
  `uvm_component_utils(aou_t1_xfer_cov)

  typedef enum int {EV_W_LEAD = 0, EV_W_EARLY = 1, EV_M_ILV = 2, EV_MSG_ILV = 3,
                    EV_S_ILV = 4} ev_e;

  uvm_tlm_analysis_fifo #(aou_msg) tb_fifo;   // remote die -> DUT
  aou_axi_vif_t s_vif[];
  aou_axi_vif_t m_vif[];

  protected int       cv_path;
  protected int       cv_dir;
  protected bit [3:0] cv_qos;
  protected bit [2:0] cv_prot;
  protected bit [3:0] cv_cache;
  protected bit [1:0] cv_resp;
  protected int       cv_ev;

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

  protected aou_fc_group fc_attr;
  protected aou_fc_group fc_excl;
  protected aou_fc_group fc_chan;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tb_fifo = new("tb_fifo", this);
    attr_cg = new();
    excl_cg = new();
    chan_cg = new();
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
    forever begin
      tb_fifo.get(m);
      take_tb(m);
    end
  endtask
endclass
