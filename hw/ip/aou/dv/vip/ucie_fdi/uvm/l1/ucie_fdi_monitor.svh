// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Mainband monitor of one PHY, both directions, with the FDI mainband rule
// checks (FDI-Rnn, listed in ../../README.md).
// Each completed flit is a new ucie_flit_item, which subscribers may keep.
// - ap_tx: flits the DUT sent; a beat transfers on lp_valid & lp_irdy &
//   pl_trdy (FDI-R01).
// - ap_rx: flits delivered to the DUT, after cancel rollback: a cancel in the
//   cycle after a 128B half drops that half (FDI-R05); on a 256 B FDI, where
//   the flit is one beat, a cancel after it drops the whole flit.
// Reset flushes both directions, and so does a LinkError the Adapter entered
// mid-flit (gate abort; UCIe r1.1 8.3.3.7): the partial flits are abandoned.
class ucie_fdi_monitor extends uvm_monitor;
  `uvm_component_utils(ucie_fdi_monitor)

  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  ucie_fdi_cfg cfg;
  ucie_fdi_cov cov;   // coverage collector, set by the bench; null: none

  uvm_analysis_port #(ucie_flit_item) ap_tx;
  uvm_analysis_port #(ucie_flit_item) ap_rx;

  int unsigned n_tx_flits;
  int unsigned n_rx_flits;
  int unsigned n_rx_cancels;
  int unsigned n_stalls;
  int unsigned n_stalls_mid;     // pl_stallreq rose inside a DUT TX flit
  int unsigned n_stalls_trdy0;   // ... in a cycle with pl_trdy low
  int unsigned n_cancels_stalled; // RX cancels while the TX side was stalled
  int unsigned n_rx_cancel_h1;   // RX flits with a second-half cancel (none at 256 B)
  int unsigned n_rx_cancel_rep;  // RX flits with one half cancelled more than once
  int unsigned n_tx_abandoned;   // partial flits abandoned on a mid-flit LinkError
  int unsigned n_rx_abandoned;
  int unsigned n_rx_beats_reset; // RX beats in Reset with the Receiver Active (+fdi_rx_early)
  // Cycles in Active in which the Adapter would take a DUT TX beat: pl_trdy
  // high and no stall handshake under way. A test judging how much the DUT
  // sends compares against this, not wall-clock cycles, so the pl_trdy policy
  // the seed drew doesn't decide the result.
  int unsigned n_tx_ready;

  local ucie_flit_item tx_cur;
  local int unsigned  tx_beat;
  local int unsigned  tx_gap;
  local int unsigned  tx_stall;

  local ucie_flit_item rx_cur;
  local int unsigned  rx_beat;
  local int unsigned  rx_gap;
  local int unsigned  rx_bubbles;
  local bit           rx_half_done;

  local bit           prev_rst_n;
  local bit           prev_sr;
  local bit           prev_sa;
  local logic [3:0]   prev_sts;
  local int unsigned  since_reset_sts;
  local int unsigned  sr_cycles;
  local int unsigned  sa_cycles;
  local bit           sr_mid;
  local bit           sr_trdy0;
  local bit           abandoned;  // left Active mid-flit; until the next Active
  local bit           abandon_h_done;  // ... right after a whole 128B half: its cancel may follow
  // Rule evaluations for the ledger, by index; flushed in check_phase.
  typedef enum int {
    R01, R02, R05, R07, R08, R09, R10, R12, R13, R35, R42, R43, R44, R45, R57, N_RULES
  } rule_e;
  local static const string RULE[N_RULES] = '{
      "FDI-R01", "FDI-R02", "FDI-R05", "FDI-R07", "FDI-R08", "FDI-R09", "FDI-R10", "FDI-R12",
      "FDI-R13", "FDI-R35", "FDI-R42", "FDI-R43", "FDI-R44", "FDI-R45", "FDI-R57"};
  local int unsigned  n_chk[N_RULES];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_tx = new("ap_tx", this);
    ap_rx = new("ap_rx", this);
  endfunction

  task run_phase(uvm_phase phase);
    if (!cfg.cov_en) cov = null;
    forever begin
      @(vif.mon_cb);
      sample();
    end
  endtask

  local function void err(rule_e r, string msg);
    if (!cfg.checks_en) return;
    ucie_rule_log::fire(RULE[r], get_type_name());
    `uvm_error(get_type_name(), $sformatf("%s: phy%0d %s", RULE[r], cfg.phy, msg))
  endfunction

  local function void chk(rule_e r);
    n_chk[r]++;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (cfg.checks_en)
      foreach (n_chk[r]) ucie_rule_log::check(RULE[r], get_type_name(), n_chk[r]);
    n_chk = '{default: 0};
  endfunction

  local function void flush_partial(string why);
    if (tx_beat != 0 || rx_beat != 0)
      `uvm_info(get_type_name(), $sformatf("%s: dropping partial flits (tx beat %0d, rx beat %0d)",
                                           why, tx_beat, rx_beat), UVM_MEDIUM)
    tx_cur = null; tx_beat = 0; tx_gap = 0; tx_stall = 0;
    rx_cur = null; rx_beat = 0; rx_gap = 0; rx_bubbles = 0; rx_half_done = 1'b0;
    prev_sr = 1'b0; prev_sa = 1'b0; sr_cycles = 0; sa_cycles = 0;
  endfunction

  local function void sample();
    logic [3:0] sts = vif.mon_cb.pl_state_sts;
    if (vif.mon_cb.rst_n !== 1'b1) begin
      if (prev_rst_n) flush_partial("reset");
      prev_rst_n = 1'b0;
      return;
    end
    if (!prev_rst_n) begin
      chk(R07);
      if (vif.mon_cb.pl_stallreq !== 1'b0 || vif.mon_cb.lp_stallack !== 1'b0)
        err(R07, "pl_stallreq and lp_stallack must both be low at reset exit");
      prev_sts = sts;
      since_reset_sts = 0;
    end
    if (sts != prev_sts && sts == FDI_STS_RESET) since_reset_sts = 0;
    else if (since_reset_sts < 1000) since_reset_sts++;
    if (prev_sts == FDI_STS_ACTIVE && sts != FDI_STS_ACTIVE && cfg.gate.abort) abandon();
    if (sts == FDI_STS_ACTIVE) abandoned = 1'b0;
    sample_tx(sts);
    sample_stall();
    sample_rx(sts);
    prev_sts = sts;
    prev_rst_n = 1'b1;
  endfunction

  // The Adapter left Active mid-flit: the DUT must drop its partial TX flit and
  // the partial RX flit it got. A DUT TX flit still presented afterwards is that
  // abandoned flit, not a new one (FDI-R43 waits for the next Active; FDI-R44
  // still requires lp_irdy low in Reset).
  local function void abandon();
    if (tx_beat != 0) begin
      n_tx_abandoned++;
      if (cov != null) cov.sample_abandon(1'b0);
    end
    if (rx_cur != null) begin
      n_rx_abandoned++;
      if (cov != null) cov.sample_abandon(1'b1);
    end
    if (tx_beat != 0 || rx_cur != null)
      `uvm_info(get_type_name(), $sformatf(
                "left Active mid-flit: TX beat %0d, RX beat %0d abandoned", tx_beat, rx_beat),
                UVM_MEDIUM)
    abandon_h_done = rx_cur != null && rx_half_done;
    tx_cur = null; tx_beat = 0; tx_stall = 0;
    rx_cur = null; rx_beat = 0; rx_bubbles = 0; rx_half_done = 1'b0;
    abandoned = 1'b1;
  endfunction

  local function void sample_tx(logic [3:0] sts);
    bit v = vif.mon_cb.lp_valid === 1'b1;
    bit i = vif.mon_cb.lp_irdy === 1'b1;
    bit t = vif.mon_cb.pl_trdy === 1'b1;
    if (v) chk(R42);
    if (v && !i) err(R42, "lp_valid without lp_irdy");
    if (sts == FDI_STS_RESET && since_reset_sts >= cfg.irdy_reset_grace) chk(R44);
    if (i && sts == FDI_STS_RESET && since_reset_sts >= cfg.irdy_reset_grace)
      err(R44, "lp_irdy high while pl_state_sts is Reset");
    if (vif.mon_cb.lp_stallack === 1'b1) chk(R10);
    if (vif.mon_cb.lp_stallack === 1'b1 && (v || i))
      err(R10, $sformatf("lp_valid=%0b lp_irdy=%0b while lp_stallack is high", v, i));
    if (tx_beat != 0) chk(R02);
    if (tx_beat != 0 && !(v && i)) begin
      err(R02, $sformatf("bubble inside a TX flit at beat %0d", tx_beat));
      // The partial flit is lost; resynchronise on the next lp_valid so one
      // truncation is one report, not one per idle cycle that follows.
      tx_cur = null;
      tx_beat = 0;
      tx_stall = 0;
    end
    if (tx_beat == 0 && v && !abandoned) chk(R43);
    if (tx_beat == 0 && v && sts != FDI_STS_ACTIVE && !abandoned)
      err(R43, $sformatf("TX flit starts while pl_state_sts=0x%0h", sts));

    if (t && sts == FDI_STS_ACTIVE && vif.mon_cb.pl_stallreq !== 1'b1 &&
        vif.mon_cb.lp_stallack !== 1'b1)
      n_tx_ready++;
    if (tx_beat != 0 && !t) tx_stall++;
    if (!(v && i && t)) begin
      if (tx_beat == 0 && tx_gap < 1000) tx_gap++;
      return;
    end
    if (tx_beat == 0) begin
      tx_cur = new("tx_cur");
      tx_cur.dir = UCIE_FDI_TX;
      tx_cur.phy = cfg.phy;
      tx_cur.t_start = $time;
      tx_cur.gap_before = tx_gap;
      tx_gap = 0;
      tx_stall = 0;
    end
    chk(R01);
    tx_cur.put_beat(cfg.beat_bytes, tx_beat, vif.mon_cb.lp_data);
    tx_beat++;
    if (tx_beat == cfg.bpf()) begin
      publish_tx(tx_cur);
      tx_cur = null;
      tx_beat = 0;
    end
  endfunction

  // A complete DUT TX flit: its Adapter-owned bytes checked, then published.
  local function void publish_tx(ucie_flit_item f);
    f.t_end = $time;
    f.n_stall_cycles = tx_stall;
    if (cfg.check_tx_adapter_bytes) chk(R45);
    if (cfg.check_tx_adapter_bytes && !f.tx_adapter_bytes_legal())
      err(R45, $sformatf("Adapter-owned bytes: FH=%02h%02h CRC0=%02h%02h CRC1=%02h%02h",
                         f.data[0], f.data[1], f.data[126], f.data[127], f.data[254],
                         f.data[255]));
    if (cov != null) cov.sample_xfer(UCIE_FDI_TX, cfg.beat_bytes, tx_stall, f.gap_before);
    n_tx_flits++;
    `uvm_info(get_type_name(), {"DUT TX ", f.convert2string()}, UVM_HIGH)
    ap_tx.write(f);
  endfunction

  local function void sample_stall();
    bit sr = vif.mon_cb.pl_stallreq === 1'b1;
    bit sa = vif.mon_cb.lp_stallack === 1'b1;
    if (sr != prev_sr) chk(R08);
    if (sa != prev_sa) chk(R09);
    if (sa && !prev_sa) begin
      chk(R12);
      chk(R13);
    end
    if (sr && !prev_sr && prev_sa) err(R08, "pl_stallreq rose while lp_stallack was high");
    if (!sr && prev_sr && !prev_sa) err(R08, "pl_stallreq fell before lp_stallack rose");
    if (sa && !prev_sa && !prev_sr) begin
      if (sr) err(R12, "lp_stallack rose in the same cycle as pl_stallreq");
      else err(R09, "lp_stallack rose without pl_stallreq");
    end
    if (!sa && prev_sa && prev_sr) err(R09, "lp_stallack fell while pl_stallreq was high");
    if (sa && !prev_sa && tx_beat != 0)
      err(R13, $sformatf("lp_stallack rose inside a TX flit (beat %0d)", tx_beat));

    if (sr && !prev_sr) begin
      sr_cycles = 0;
      sr_mid = tx_beat != 0;
      if (sr_mid) n_stalls_mid++;
      sr_trdy0 = sr_mid && vif.mon_cb.pl_trdy !== 1'b1;
      if (sr_trdy0) n_stalls_trdy0++;
    end
    if (sr && !sa) sr_cycles++;
    if (sa && !prev_sa) chk(R57);
    if (sr && !sa && sr_cycles == cfg.stall_timeout) begin
      chk(R57);
      err(R57, $sformatf("no lp_stallack %0d cycles after pl_stallreq (TX beat %0d)",
                               sr_cycles, tx_beat));
    end
    if (sa && !prev_sa) sa_cycles = 0;
    if (sa) sa_cycles++;
    if (!sa && prev_sa) begin
      n_stalls++;
      if (cov != null) cov.sample_stall(sr_cycles, sa_cycles, sr_mid, sr_trdy0);
    end
    prev_sr = sr;
    prev_sa = sa;
  endfunction

  local function void sample_rx(logic [3:0] sts);
    bit v = vif.mon_cb.pl_valid === 1'b1;
    bit c = vif.mon_cb.pl_flit_cancel === 1'b1;
    if (c) chk(R05);
    if (c && abandon_h_done) begin
      n_rx_cancels++;
    end else if (c) begin
      if (!rx_half_done || rx_cur == null) begin
        err(R05, "pl_flit_cancel not in the cycle after a 128B half (a 256B flit)");
      end else begin
        // The cancelled unit: half 0 or 1, or 2, the whole flit, on a 256 B FDI.
        int unsigned half = (cfg.bpf() == 1) ? 2 : (rx_beat == cfg.bpf()) ? 1 : 0;
        int unsigned count;
        bit stalled;
        rx_beat -= cfg.bph();
        if (half != 1) rx_cur.n_cancel_h0++;
        else rx_cur.n_cancel_h1++;
        if (v) rx_cur.n_cancel_valid++;
        stalled = vif.mon_cb.pl_stallreq === 1'b1 || vif.mon_cb.lp_stallack === 1'b1;
        if (stalled) n_cancels_stalled++;
        count = rx_cur.n_cancel_h0 + rx_cur.n_cancel_h1;
        n_rx_cancels++;
        if (cov != null) cov.sample_cancel(half, v, count, stalled);
      end
    end else if (rx_half_done && rx_beat == cfg.bpf()) begin
      publish_rx();
    end
    rx_half_done = 1'b0;
    abandon_h_done = 1'b0;

    // UCIe r1.1 8.2.7 rule 3: with rx_active req and sts both 1 the Receiver
    // is Active even while pl_state_sts is still Reset (+fdi_rx_early). Retrain
    // carries no mainband flits, so the rule stays strict there.
    if (v) chk(R35);
    if (v && sts == FDI_STS_RESET) n_rx_beats_reset++;
    if (v && sts != FDI_STS_ACTIVE && !(sts == FDI_STS_RESET && vif.mon_cb.rx_active === 1'b1))
      err(R35, $sformatf("pl_valid while pl_state_sts=0x%0h (rx_active %0b)", sts,
                               vif.mon_cb.rx_active === 1'b1));
    if (!v) begin
      if (rx_cur == null) begin
        if (rx_gap < 1000) rx_gap++;
      end else if (!c) begin
        rx_bubbles++;
      end
      return;
    end
    if (rx_cur == null) begin
      rx_cur = new("rx_cur");
      rx_cur.dir = UCIE_FDI_RX;
      rx_cur.phy = cfg.phy;
      rx_cur.t_start = $time;
      rx_cur.gap_before = rx_gap;
      rx_gap = 0;
      rx_bubbles = 0;
    end
    rx_cur.put_beat(cfg.beat_bytes, rx_beat, vif.mon_cb.pl_data);
    rx_beat++;
    rx_half_done = (rx_beat % cfg.bph()) == 0;
  endfunction

  local function void publish_rx();
    rx_cur.t_end = $time;
    if (rx_cur.n_cancel_h1 != 0) n_rx_cancel_h1++;
    if (rx_cur.n_cancel_h0 > 1 || rx_cur.n_cancel_h1 > 1) n_rx_cancel_rep++;
    rx_cur.n_stall_cycles = rx_bubbles;
    if (cov != null) cov.sample_xfer(UCIE_FDI_RX, cfg.beat_bytes, rx_bubbles, rx_cur.gap_before);
    n_rx_flits++;
    `uvm_info(get_type_name(), {"DUT RX ", rx_cur.convert2string()}, UVM_HIGH)
    ap_rx.write(rx_cur);
    rx_cur = null;
    rx_beat = 0;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({"phy%0d: %0d TX, %0d RX flits, %0d RX cancels ",
                                          "(%0d while stalled; %0d flits with a second-half ",
                                          "cancel, %0d with a repeated one), %0d stalls (%0d ",
                                          "mid-flit, %0d of them with pl_trdy low); %0d TX ",
                                          "and %0d RX flits abandoned mid-flit; %0d RX beats ",
                                          "in Reset"}, cfg.phy,
                                         n_tx_flits, n_rx_flits, n_rx_cancels, n_cancels_stalled,
                                         n_rx_cancel_h1, n_rx_cancel_rep, n_stalls, n_stalls_mid,
                                         n_stalls_trdy0, n_tx_abandoned, n_rx_abandoned,
                                         n_rx_beats_reset), UVM_LOW)
  endfunction
endclass
