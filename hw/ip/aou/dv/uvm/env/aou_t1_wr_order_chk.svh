// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Order and forward progress of the writes the DUT sends, in every test, from
// the DUT's messages alone (the remote model's own TX may send either order).
//
// DP-R10 (one-way order): a WriteData the DUT sends for RP r follows a
// WriteReq on RP r whose data is still owed. AoU v0.8 5.7 does not order a
// WriteReq against its WriteData, but the owners require the DUT's TX to send
// the request first (PR #98); a receiver may rely on it. The L3 responder
// pairs them by count and would not notice.
//
// DP-R11 (write forward progress): no RP's committed write starves while the
// RP holds credit. The TX arbiters choose between RPs; nothing else should
// hold back an RP that has credit, so its data must eventually go. Per RP,
// while the DUT has sent a WriteReq whose data is still owed and the RP's
// write data is waiting inside the DUT (its S port has taken more W beats than
// the DUT has sent as WriteData), count the cycles in which the RP holds WDATA
// credit for a full-width WriteData (credit we granted and have not seen
// used). Other cycles (no such credit, or no data waiting) pause the count
// without clearing it, so a write fed by a trickle of credit is not blamed;
// any WriteData the DUT sends for the RP restarts it. The bound (progress_cycles) is generous: it catches a write
// that stops, not slow service. AoU v0.8 asks only for forward progress; the
// order in which RPs are served is the arbiters' choice (MAS 3.2.1).
//
// A reset, DISABLED and a new activation end every open write and every count.
class aou_t1_wr_order_chk extends uvm_component;
  `uvm_component_utils(aou_t1_wr_order_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_wr_order_chk) rx_msg_imp;

  aou_t1_env_cfg cfg;
  aou_l3_model   model;
  aou_core       rm;
  aou_axi_vif_t  s_vif[];
  bit            enable = 1'b1;
  // Cycles with credit and waiting data, without a WriteData for the RP,
  // before DP-R11 fires (+wr_progress_cycles=). The longest wait seen across
  // the stress and link lists on three RP-width mixes was about 300 cycles,
  // under FDI backpressure; the default leaves a wide margin over that.
  int unsigned   progress_cycles = 4000;

  // Beats still owed by each open write per wire RP, oldest first.
  protected int unsigned       owed_q[AOU_RP_MAX][$];
  protected int unsigned       epoch;
  // Per local RP: W beats the S port took and WriteData the DUT sent, since
  // the S port last had no write open (writes the DUT answers itself, or
  // answers early, then leave no beat counted as waiting), the S-port writes
  // open (AW taken, B not yet given), the credited wait and whether DP-R11
  // was reported for it.
  protected longint unsigned   w_took[AOU_RP_MAX];
  protected longint unsigned   wd_sent[AOU_RP_MAX];
  protected int unsigned       s_open[AOU_RP_MAX];
  protected int unsigned       wait_n[AOU_RP_MAX];
  protected bit                rep[AOU_RP_MAX];
  // Local RP of each wire RP (the inverse of DEST_RP), refreshed periodically.
  protected int unsigned       local_of[AOU_RP_MAX];
  protected int unsigned       wire_of_x[AOU_RP_MAX];

  int unsigned n_wreq;
  int unsigned n_wdata;
  int unsigned n_r10;
  int unsigned n_r11;
  // Longest credited wait seen (the margin to tune progress_cycles by).
  int unsigned max_wait;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_msg_imp = new("rx_msg_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("wr_progress_cycles=%d", progress_cycles));
    foreach (local_of[w]) begin
      local_of[w] = w;
      wire_of_x[w] = w;
    end
  endfunction

  // The wire RP local RP x's messages carry (DEST_RP, register mirror).
  protected function int unsigned wire_of(int unsigned x);
    uvm_reg_field f;
    if (rm == null) return x;
    f = rm.dest_rp.get_field_by_name($sformatf("rp%0d_dest", x));
    return (f == null) ? x : int'(f.get_mirrored_value());
  endfunction

  protected function void refresh_map();
    foreach (local_of[w]) local_of[w] = w;
    for (int unsigned x = 0; x < cfg.n_rp && x < AOU_RP_MAX; x++) begin
      wire_of_x[x] = wire_of(x);
      if (wire_of_x[x] < AOU_RP_MAX) local_of[wire_of_x[x]] = x;
    end
  endfunction

  // Granules of a full-width WriteData for local RP x (Tables 5-7).
  protected function int unsigned need(int unsigned x);
    return cfg.rp_bytes[x] <= 32 ? 8 : cfg.rp_bytes[x] <= 64 ? 15 : 30;
  endfunction

  protected function void forget();
    foreach (owed_q[w]) owed_q[w].delete();
    foreach (wait_n[x]) begin
      wait_n[x] = 0;
      rep[x] = 1'b0;
    end
  endfunction

  // A new activation or DISABLED ends every open write and every count. Called
  // from both the message path and the sampling loop, whichever sees it first.
  protected function void link_check();
    if (model.lnk.epoch == epoch && model.lnk.state != AOU_LS_DISABLED) return;
    forget();
    epoch = model.lnk.epoch;
  endfunction

  // Reset contract: nothing the DUT sent before is owed any more.
  function void reset_flush();
    forget();
    foreach (w_took[x]) begin
      w_took[x] = 0;
      wd_sent[x] = 0;
      s_open[x] = 0;
    end
  endfunction

  function void write(aou_msg m);
    aou_msg_req q;
    int unsigned w = int'(m.rp);
    if (!enable || model == null || w >= AOU_RP_MAX) return;
    link_check();
    if (m.msg_type == AOU_MT_WREQ && $cast(q, m)) begin
      n_wreq++;
      owed_q[w].push_back(int'(q.len) + 1);
      return;
    end
    if (m.cred_class() != AOU_CC_WDATA) return;
    n_wdata++;
    if (local_of[w] < AOU_RP_MAX) begin
      wd_sent[local_of[w]]++;
      wait_n[local_of[w]] = 0;
      rep[local_of[w]] = 1'b0;
    end
    aou_rule_log::check("DP-R10", get_type_name());
    if (owed_q[w].size() == 0) begin
      n_r10++;
      aou_rule_log::fire("DP-R10", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"DP-R10: the DUT sent a WriteData on RP%0d with no WriteReq on that RP owing data ",
           "(the DUT's TX sends each write's WriteReq before its WriteData)"}, w))
      return;
    end
    owed_q[w][0] = owed_q[w][0] - 1;
    if (owed_q[w][0] == 0) void'(owed_q[w].pop_front());
  endfunction

  // One sampled cycle of local RP x: count it if a committed write waits on
  // data inside the DUT while the RP holds credit for it. Any other cycle
  // pauses the count; only a WriteData for the RP (write()), a reset, DISABLED
  // or a new activation (forget()) restarts it.
  protected function void progress(int unsigned x);
    int unsigned w = wire_of_x[x];
    if (w >= AOU_RP_MAX || owed_q[w].size() == 0 || w_took[x] <= wd_sent[x] ||
        model.crd.rx_outstanding[w][AOU_CC_WDATA] < need(x))
      return;
    if (wait_n[x] == 0) aou_rule_log::check("DP-R11", get_type_name());
    wait_n[x]++;
    if (wait_n[x] > max_wait) max_wait = wait_n[x];
    if (wait_n[x] > progress_cycles && !rep[x]) begin
      rep[x] = 1'b1;
      n_r11++;
      aou_rule_log::fire("DP-R11", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"DP-R11: RP%0d's committed write still owes %0d beats and its data waits in the DUT, ",
           "but the DUT sent no WriteData on it for %0d cycles in which it held WDATA credit ",
           "(%0d granules granted and not yet used)"}, w, owed_q[w][0], wait_n[x],
          model.crd.rx_outstanding[w][AOU_CC_WDATA]))
    end
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned n = 0;
    if (!enable || s_vif.size() == 0 || model == null) return;
    forever begin
      @(s_vif[0].mon_cb);
      if ((n++ & 63) == 0) refresh_map();
      link_check();
      for (int unsigned x = 0; x < cfg.n_rp && x < AOU_RP_MAX; x++) begin
        if (s_vif[x].mon_cb.resetn !== 1'b1) begin
          s_open[x] = 0;
        end else begin
          if (s_vif[x].mon_cb.awvalid === 1'b1 && s_vif[x].mon_cb.awready === 1'b1) s_open[x]++;
          if (s_vif[x].mon_cb.bvalid === 1'b1 && s_vif[x].mon_cb.bready === 1'b1 &&
              s_open[x] > 0)
            s_open[x]--;
          if (s_vif[x].mon_cb.wvalid === 1'b1 && s_vif[x].mon_cb.wready === 1'b1) w_took[x]++;
        end
        if (s_open[x] == 0) w_took[x] = wd_sent[x];
        progress(x);
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf(
              {"%0d WriteReq, %0d WriteData from the DUT; DP-R10 %0d, DP-R11 %0d; longest ",
               "credited wait for WriteData %0d cycles (bound %0d)"}, n_wreq, n_wdata, n_r10,
              n_r11, max_wait, progress_cycles), UVM_LOW)
  endfunction
endclass
