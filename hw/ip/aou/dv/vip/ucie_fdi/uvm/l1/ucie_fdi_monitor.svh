// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Mainband monitor of one PHY, both directions, with the FDI mainband rule
// checks (FDI-Rnn, listed in ../../README.md).
// Each completed flit is a new ucie_flit_item, which subscribers may keep.
// - ap_tx: flits the Protocol Layer sent; a beat transfers on lp_valid & lp_irdy &
//   pl_trdy (FDI-R01).
// - ap_rx: flits delivered to the Protocol Layer, after cancel rollback: a cancel in the
//   cycle after a 128B half drops that half (FDI-R05); from 256 B up, where
//   the flit is one beat, a cancel after it drops every flit of that beat.
//   NOP flits (Protocol ID 00b, r3.0 Table 3-5; the Flit Header 0000h of an
//   empty lane, §10.3.1, is one) are not delivered: the Protocol Layer
//   discards them (UCIe r3.0 Table 10-3 pl_flit_cancel).
// On a 512 or 1024 B FDI a beat carries 2 or 4 flits, one per 256 B lane
// (UCIe r3.0 §10.3.1): a TX beat is that many flits, each checked (FDI-R45, so
// a lane the Protocol Layer leaves empty is an error), and an RX beat is that many
// flits, of which the zero-padded lanes are NOPs.
// Reset flushes both directions, and so does a LinkError entered mid-flit
// (UCIe r3.0 §10.3.3.7): the partial flits are abandoned. That is seen on
// the interface alone (pl_state_sts Active -> LinkError with a flit part-way
// in either direction), so a passive monitor on a real Adapter judges it the
// same way as the model's own.
// The checks on the stall handshake follow r3.0 §10.3.2 (rules 1 to 8).
// The Protocol Layer may present a flit (lp_valid, lp_irdy) in any state but
// Reset and wait for pl_trdy (r3.0 §10.2.4, Table 10-3 lp_irdy); pl_trdy, and
// with it every transfer, needs Active or a stall handshake in LinkError
// (FDI-R43), and lp_valid alone
// transfers nothing.
// Errors (UCIe r3.0 Table 10-3, §10.3.1): a cancel unit that carried pl_error
// must be cancelled and no RX data may follow until the link has left Active
// (FDI-R06), and pl_error needs the Receiver active (FDI-R58); lp_corrupt_crc
// comes with lp_valid on the last transfer of a 128B half (FDI-R59), on both
// halves if on the first (FDI-R60). At 512 B and up they, like
// pl_flit_cancel, apply to every flit of the transfer.
class ucie_fdi_monitor extends uvm_monitor;
  `uvm_component_utils(ucie_fdi_monitor)

  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  ucie_fdi_cfg cfg;
  ucie_fdi_cov cov;   // coverage collector, set by the bench; null: none
  ucie_fdi_fcov fcov; // the model's own covergroups, set by the agent; null: none

  uvm_analysis_port #(ucie_flit_item) ap_tx;
  uvm_analysis_port #(ucie_flit_item) ap_rx;

  int unsigned n_tx_flits;
  int unsigned n_rx_flits;
  int unsigned n_rx_cancels;
  int unsigned n_stalls;
  int unsigned n_stalls_mid;     // pl_stallreq rose inside a TX flit
  int unsigned n_stalls_trdy0;   // ... in a cycle with pl_trdy low
  int unsigned n_cancels_stalled; // RX cancels while the TX side was stalled
  int unsigned n_rx_cancel_h1;   // RX flits with a second-half cancel (none at 256 B)
  int unsigned n_rx_cancel_rep;  // RX flits with one half cancelled more than once
  int unsigned n_tx_abandoned;   // partial flits abandoned on a mid-flit LinkError
  int unsigned n_rx_abandoned;
  int unsigned n_rx_beats_reset; // RX beats in Reset with the Receiver Active (+ucie_rx_early)
  // Cycles in Active in which the Adapter would take a TX beat: pl_trdy
  // high and no stall handshake under way. A test judging how much the
  // Protocol Layer sends compares against this, not wall-clock cycles, so the pl_trdy policy
  // the seed drew doesn't decide the result.
  int unsigned n_tx_ready;
  int unsigned n_rx_nops;        // uncancelled RX NOP flits, discarded
  int unsigned n_rx_nop_cancels; // cancels of a first half (or transfer) of NOPs only
  int unsigned n_tx_nops;        // TX NOP flits (Protocol ID 00b) where the stream allows them
  int unsigned n_rx_part;        // 512/1024 B: RX beats with fewer flits than lanes
  int unsigned n_rx_errors;      // RX cancel units flagged on pl_error
  int unsigned n_tx_corrupt;     // TX transfers of flits with lp_corrupt_crc

  local ucie_flit_item tx_cur[$];  // the flits of the current beat(s), one per lane
  local int unsigned  tx_beat;
  local int unsigned  tx_gap;
  local int unsigned  tx_stall;

  local ucie_flit_item rx_cur[$];
  local int unsigned  rx_beat;
  local int unsigned  rx_gap;
  local int unsigned  rx_bubbles;
  local bit           rx_half_done;
  local bit           rx_err_unit;  // pl_error in the current cancel unit
  local bit           rx_err_wait;  // ... cancelled; no RX data until the link leaves Active
  local bit           tx_cc_h0;     // lp_corrupt_crc on the first half of the current TX flit
  local bit           tx_cc_any;    // ... on any transfer of it

  local bit           prev_rst_n;
  local bit           prev_sr;
  local bit           prev_sa;
  local logic [3:0]   prev_sts;
  // Cycles left in which lp_irdy may still be high in Reset: only after
  // LinkError -> Reset (FDI-R44).
  local int unsigned  irdy_grace;
  local int unsigned  sr_cycles;
  local int unsigned  sa_cycles;
  local bit           sr_mid;
  local bit           sr_trdy0;
  local int unsigned  trdy_low;     // cycles of the current pl_trdy-low run
  local bit           trdy_low_in;  // ... which started inside a TX flit
  local bit           trdy_low_ok;  // ... all in Active, with no stall handshake or hold
  local bit           abandon_h_done;  // ... right after a whole 128B half: its cancel may follow
  // Rule evaluations for the ledger, by index; flushed in check_phase.
  typedef enum int {
    R01, R02, R05, R06, R07, R08, R09, R10, R12, R13, R35, R43, R44, R45, R57, R58, R59, R60,
    R64, N_RULES
  } rule_e;
  local static const string RULE[N_RULES] = '{
      "FDI-R01", "FDI-R02", "FDI-R05", "FDI-R06", "FDI-R07", "FDI-R08", "FDI-R09", "FDI-R10",
      "FDI-R12", "FDI-R13", "FDI-R35", "FDI-R43", "FDI-R44", "FDI-R45", "FDI-R57", "FDI-R58",
      "FDI-R59", "FDI-R60", "FDI-R64"};
  local int unsigned  n_chk[N_RULES];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_tx = new("ap_tx", this);
    ap_rx = new("ap_rx", this);
  endfunction

  task run_phase(uvm_phase phase);
    if (!cfg.cov_en) cov = null;
    if (!cfg.fcov_en) fcov = null;
    forever begin
      @(vif.mon_cb);
      sample();
    end
  endtask

  local function void err(rule_e r, string msg);
    if (!cfg.checks_en) return;
    ucie_rule_log::fire(RULE[r], this);
    `uvm_error(get_type_name(), $sformatf("%s: phy%0d %s", RULE[r], cfg.phy, msg))
  endfunction

  local function void chk(rule_e r);
    n_chk[r]++;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (cfg.checks_en)
      foreach (n_chk[r]) ucie_rule_log::check(RULE[r], this, n_chk[r]);
    n_chk = '{default: 0};
  endfunction

  local function void flush_partial(string why);
    if (tx_beat != 0 || rx_beat != 0)
      `uvm_info(get_type_name(), $sformatf("%s: dropping partial flits (tx beat %0d, rx beat %0d)",
                                           why, tx_beat, rx_beat), UVM_MEDIUM)
    tx_cur.delete(); tx_beat = 0; tx_gap = 0; tx_stall = 0; tx_cc_h0 = 1'b0; tx_cc_any = 1'b0;
    rx_cur.delete(); rx_beat = 0; rx_gap = 0; rx_bubbles = 0; rx_half_done = 1'b0;
    rx_err_unit = 1'b0; rx_err_wait = 1'b0;
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
      irdy_grace = 0;
    end
    // UCIe r3.0 Table 10-3 lp_irdy: "On a LinkError to Reset transition, it is
    // permitted for lp_irdy to be asserted for a few clocks but it must be
    // de-asserted eventually"; on any other entry to Reset it must be low.
    if (sts == FDI_STS_RESET && prev_sts != FDI_STS_RESET)
      irdy_grace = prev_sts == FDI_STS_LINKERROR ? cfg.irdy_reset_grace : 0;
    else if (irdy_grace != 0)
      irdy_grace--;
    if (prev_sts == FDI_STS_ACTIVE && sts == FDI_STS_LINKERROR)
      abandon(vif.mon_cb.pl_flit_cancel === 1'b1);
    sample_tx(sts);
    sample_stall();
    sample_rx(sts);
    prev_sts = sts;
    prev_rst_n = 1'b1;
  endfunction

  // The link left Active for LinkError: the Protocol Layer must drop its partial TX flit
  // and the partial RX flit it got (UCIe r3.0 §10.3.3.7: "It is required for
  // the upper layer to internally clean up the data path, even if pl_trdy is
  // not asserted"). A whole RX flit whose cancel cycle is this first clock of
  // LinkError is not partial: with no cancel (c 0) it is delivered as usual.
  // The Protocol Layer may keep presenting a flit in LinkError (pl_trdy stays low, so
  // nothing transfers, unless the Adapter drains it under a stall handshake,
  // FDI-R43); FDI-R44 still requires lp_irdy low in Reset once the grace
  // after LinkError has run out.
  local function void abandon(bit c);
    bit rx = rx_cur.size() != 0 && !(rx_half_done && rx_beat == cfg.bpf() && !c);
    if (tx_beat != 0) begin
      n_tx_abandoned++;
      if (cov != null) cov.sample_abandon(1'b0);
      if (fcov != null) fcov.sample_abandon(1'b0);
    end
    if (rx) begin
      n_rx_abandoned++;
      if (cov != null) cov.sample_abandon(1'b1);
      if (fcov != null) fcov.sample_abandon(1'b1);
    end
    if (tx_beat != 0 || rx)
      `uvm_info(get_type_name(), $sformatf(
                "left Active for LinkError mid-flit:%s%s",
                tx_beat != 0 ? $sformatf(" TX flit abandoned after %0d of its %0d transfers;",
                                         tx_beat, cfg.bpf()) : "",
                rx ? $sformatf(" RX flit abandoned with %0d of its %0d transfers kept",
                               rx_beat, cfg.bpf()) : ""), UVM_MEDIUM)
    tx_cur.delete(); tx_beat = 0; tx_stall = 0; tx_cc_h0 = 1'b0; tx_cc_any = 1'b0;
    if (!rx) return;
    abandon_h_done = rx_half_done;
    rx_cur.delete(); rx_beat = 0; rx_bubbles = 0; rx_half_done = 1'b0;
    rx_err_unit = 1'b0;
  endfunction

  local function void sample_tx(logic [3:0] sts);
    bit v = vif.mon_cb.lp_valid === 1'b1;
    bit i = vif.mon_cb.lp_irdy === 1'b1;
    bit t = vif.mon_cb.pl_trdy === 1'b1;
    // lp_stream is relevant with lp_valid (UCIe r3.0 Table 10-3); checked on
    // a flit's first beat, so a wrong value is one report per flit.
    if (v && tx_beat == 0) chk(R64);
    if (v && tx_beat == 0 && vif.mon_cb.lp_stream !== cfg.stream)
      err(R64, $sformatf("lp_stream %02h with lp_valid; the link carries stream %02h",
                         vif.mon_cb.lp_stream, cfg.stream));
    if (sts == FDI_STS_RESET && irdy_grace == 0) chk(R44);
    if (i && sts == FDI_STS_RESET && irdy_grace == 0)
      err(R44, prev_sts == FDI_STS_RESET ? "lp_irdy high while pl_state_sts is Reset" :
                                          $sformatf("lp_irdy high on entry to Reset from 0x%0h",
                                                    prev_sts));
    if (vif.mon_cb.lp_stallack === 1'b1) chk(R10);
    if (vif.mon_cb.lp_stallack === 1'b1 && (v || i))
      err(R10, $sformatf("lp_valid=%0b lp_irdy=%0b while lp_stallack is high", v, i));
    if (tx_beat != 0) chk(R02);
    if (tx_beat != 0 && !(v && i)) begin
      err(R02, $sformatf("bubble inside a TX flit at beat %0d", tx_beat));
      // The partial flit is lost; resynchronise on the next lp_valid so one
      // truncation is one report, not one per idle cycle that follows.
      tx_cur.delete();
      tx_beat = 0;
      tx_stall = 0;
      tx_cc_h0 = 1'b0;
      tx_cc_any = 1'b0;
    end
    // FDI-R43: pl_trdy "must be asserted only if pl_state_sts is Active or
    // when performing the pl_stallreq/lp_stallack handshake when the
    // pl_state_sts is LinkError" (UCIe r3.0 Table 10-3; §10.3.3.7: an Adapter
    // that runs the handshake in LinkError provides pl_trdy to drain the
    // Protocol Layer). The handshake lasts until lp_stallack falls (§10.3.2
    // rule 9), and rule 6 keeps lp_valid and lp_irdy low while lp_stallack is
    // high. Every transfer needs pl_trdy, so none happens outside those
    // either. Presenting a flit and waiting through Retrain, LinkReset or
    // Disabled is legal: the Adapter keeps pl_trdy low.
    if (t) chk(R43);
    if (t && sts != FDI_STS_ACTIVE &&
        !(sts == FDI_STS_LINKERROR &&
          (vif.mon_cb.pl_stallreq === 1'b1 || vif.mon_cb.lp_stallack === 1'b1)))
      err(R43, $sformatf("pl_trdy high while pl_state_sts=0x%0h%s", sts,
                         v && i ? $sformatf(" (a TX transfer, beat %0d)", tx_beat) : ""));

    if (t && sts == FDI_STS_ACTIVE && vif.mon_cb.pl_stallreq !== 1'b1 &&
        vif.mon_cb.lp_stallack !== 1'b1)
      n_tx_ready++;
    if (fcov != null) sample_trdy_run(sts, t);
    if (tx_beat != 0 && !t) tx_stall++;
    check_corrupt(v, v && i && t);
    if (!(v && i && t)) begin
      if (tx_beat == 0 && tx_gap < 1000) tx_gap++;
      return;
    end
    if (tx_beat == 0) begin
      for (int unsigned l = 0; l < cfg.fpb(); l++) begin
        ucie_flit_item f = new("tx_cur");
        f.dir = UCIE_FDI_TX;
        f.phy = cfg.phy;
        f.t_start = $time;
        f.gap_before = l == 0 ? tx_gap : 0;
        tx_cur.push_back(f);
      end
      tx_gap = 0;
      tx_stall = 0;
    end
    chk(R01);
    foreach (tx_cur[l]) tx_cur[l].put_beat(cfg.beat_bytes, tx_beat, vif.mon_cb.lp_data, l);
    tx_beat++;
    if (tx_beat == cfg.bpf()) begin
      foreach (tx_cur[l]) publish_tx(tx_cur[l], l);
      if (tx_cc_any) begin
        n_tx_corrupt++;
        if (fcov != null) fcov.sample_corrupt(tx_cc_h0);
      end
      tx_cur.delete();
      tx_beat = 0;
      tx_cc_h0 = 1'b0;
      tx_cc_any = 1'b0;
    end
  endfunction

  // lp_corrupt_crc (UCIe r3.0 Table 10-3): asserted with lp_valid for the last
  // transfer of a 128B half (from 256 B up every transfer ends both halves),
  // and on the second half whenever on the first. xfer: this cycle transfers
  // a beat (tx_beat is still its index). Whether the protocol allows it at all
  // is the link-state monitor's check (FDI-R61).
  local function void check_corrupt(bit v, bit xfer);
    bit cc = vif.mon_cb.lp_corrupt_crc === 1'b1;
    bit last_of_half = ((tx_beat + 1) % cfg.bph()) == 0;
    bit second_half = cfg.bph() < cfg.bpf() && tx_beat + 1 == cfg.bpf();
    if (cc) chk(R59);
    if (cc && !v) err(R59, "lp_corrupt_crc without lp_valid");
    if (!xfer) return;
    if (cc && !last_of_half)
      err(R59, $sformatf("lp_corrupt_crc on transfer %0d of a TX flit, not the last of a 128B half",
                         tx_beat));
    if (second_half && tx_cc_h0) begin
      chk(R60);
      if (!cc) err(R60, "lp_corrupt_crc on the first 128B half of a TX flit but not the second");
    end
    if (cc && last_of_half) begin
      tx_cc_any = 1'b1;
      if (!second_half && cfg.bph() < cfg.bpf()) tx_cc_h0 = 1'b1;
    end
  endfunction

  // A complete TX flit (in lane `lane` of a wide beat): its Adapter-owned
  // bytes checked, then published. A NOP (Protocol ID 00b) is an error on a
  // Streaming stream (r3.0 Table 3-5), and so is a lane left empty, since the
  // Protocol Layer sends valid data on the full width (§10.3.1); on a
  // CXL.cachemem stream it is a NOP flit, accepted and still published.
  local function void publish_tx(ucie_flit_item f, int unsigned lane);
    bit nop_ok = stream_tx_nop_legal(cfg.stream);
    f.t_end = $time;
    f.n_stall_cycles = tx_stall;
    if (cfg.check_tx_adapter_bytes) chk(R45);
    if (cfg.check_tx_adapter_bytes && !f.tx_adapter_bytes_legal(nop_ok))
      err(R45, $sformatf("%sAdapter-owned bytes: FH=%02h%02h CRC0=%02h%02h CRC1=%02h%02h%s",
                         cfg.fpb() > 1 ? $sformatf("lane %0d: ", lane) : "", f.data[0],
                         f.data[1], f.data[126], f.data[127], f.data[254], f.data[255],
                         !nop_ok && f.is_nop() ?
                         " (Protocol ID 00b, a NOP, which a Streaming Protocol Layer never sends)"
                         : ""));
    if (nop_ok && f.is_nop()) n_tx_nops++;
    if (cov != null)
      cov.sample_xfer(UCIE_FDI_TX, cfg.beat_bytes, tx_stall, f.gap_before, f, lane);
    if (fcov != null)
      fcov.sample_xfer(UCIE_FDI_TX, cfg.beat_bytes, tx_stall, f.gap_before, f, lane);
    n_tx_flits++;
    `uvm_info(get_type_name(), {"TX ", f.convert2string()}, UVM_HIGH)
    ap_tx.write(f);
  endfunction

  // A run of pl_trdy low that the policy made: every cycle of it in Active,
  // with no stall handshake and no tx_hold. Sampled when pl_trdy rises again.
  local function void sample_trdy_run(logic [3:0] sts, bit t);
    bit quiet = sts == FDI_STS_ACTIVE && vif.mon_cb.pl_stallreq !== 1'b1 &&
                vif.mon_cb.lp_stallack !== 1'b1 && !cfg.tx_hold;
    if (!t) begin
      if (trdy_low == 0) begin
        trdy_low_in = tx_beat != 0;
        trdy_low_ok = 1'b1;
      end
      trdy_low++;
      trdy_low_ok &= quiet;
    end else if (trdy_low != 0) begin
      if (trdy_low_ok && quiet) fcov.sample_trdy(cfg.trdy_policy, trdy_low_in, trdy_low);
      trdy_low = 0;
    end
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
      if (fcov != null) fcov.sample_stall(sr_cycles, sa_cycles, sr_mid, sr_trdy0);
    end
    prev_sr = sr;
    prev_sa = sa;
  endfunction

  local function void sample_rx(logic [3:0] sts);
    bit v = vif.mon_cb.pl_valid === 1'b1;
    bit c = vif.mon_cb.pl_flit_cancel === 1'b1;
    bit e = vif.mon_cb.pl_error === 1'b1;
    if (e) chk(R58);
    if (e && vif.mon_cb.rx_active !== 1'b1) err(R58, "pl_error while the Receiver is not active");
    // FDI-R06: the unit that carried pl_error is cancelled in its cancel cycle,
    // and then nothing comes until the link leaves Active (to retrain).
    if (rx_half_done && rx_err_unit) begin
      chk(R06);
      if (!c) err(R06, "a 128B half (from 256 B up, a transfer) with pl_error was not cancelled");
      rx_err_unit = 1'b0;
      rx_err_wait = c;
    end
    if (sts != FDI_STS_ACTIVE) rx_err_wait = 1'b0;
    if (rx_err_wait && v) begin
      chk(R06);
      err(R06, "RX data after a pl_error before the link left Active to retrain");
      rx_err_wait = 1'b0;
    end
    if (c) chk(R05);
    if (c && abandon_h_done) begin
      n_rx_cancels++;
    end else if (c) begin
      if (!rx_half_done || rx_cur.size() == 0) begin
        err(R05, "pl_flit_cancel not in the cycle after a 128B half (from 256 B up, a beat)");
      end else begin
        // The cancelled unit: half 0 or 1, or 2, every flit of the beat, from
        // 256 B up.
        int unsigned half = (cfg.bpf() == 1) ? 2 : (rx_beat == cfg.bpf()) ? 1 : 0;
        int unsigned count;
        bit stalled;
        rx_beat -= cfg.bph();
        foreach (rx_cur[l]) begin
          if (half != 1) rx_cur[l].n_cancel_h0++;
          else rx_cur[l].n_cancel_h1++;
          if (v) rx_cur[l].n_cancel_valid++;
        end
        stalled = vif.mon_cb.pl_stallreq === 1'b1 || vif.mon_cb.lp_stallack === 1'b1;
        if (stalled) n_cancels_stalled++;
        count = rx_cur[0].n_cancel_h0 + rx_cur[0].n_cancel_h1;
        n_rx_cancels++;
        if (cov != null) cov.sample_cancel(half, v, count, stalled);
        if (fcov != null) fcov.sample_cancel(half, v, count, stalled);
        // A first half (or transfer) of NOPs cancelled: the Adapter may cancel
        // NOPs to keep them from the Protocol Layer and never replay them
        // (r3.0 Table 10-3 pl_flit_cancel). What follows is a new flit, so
        // the partial one is dropped rather than carrying its cancel counts
        // over. A replay that follows instead starts afresh, which only
        // resets the counts.
        if (rx_beat == 0 && all_nop()) begin
          n_rx_nop_cancels++;
          rx_cur.delete();
        end
      end
    end else if (rx_half_done && rx_beat == cfg.bpf()) begin
      publish_rx();
    end
    rx_half_done = 1'b0;
    abandon_h_done = 1'b0;

    // FDI-R35, UCIe r3.0 10.2.7: flits only while the Receiver is Active,
    // pl_rx_active_req and lp_rx_active_sts both 1 with pl_state_sts Reset,
    // Retrain or Active (rule 3; Reset with +ucie_rx_early). In Active with the
    // request low no flit may be sent either (rule 6).
    if (v) chk(R35);
    if (v && sts == FDI_STS_RESET) n_rx_beats_reset++;
    if (v && !(vif.mon_cb.rx_active === 1'b1 &&
               sts inside {FDI_STS_RESET, FDI_STS_RETRAIN, FDI_STS_ACTIVE}))
      err(R35, $sformatf("pl_valid while pl_state_sts=0x%0h with the Receiver %s", sts,
                         vif.mon_cb.rx_active === 1'b1 ? "active" : "not active"));
    if (!v) begin
      if (rx_cur.size() == 0) begin
        if (rx_gap < 1000) rx_gap++;
      end else if (!c) begin
        rx_bubbles++;
      end
      return;
    end
    if (rx_cur.size() == 0) begin
      for (int unsigned l = 0; l < cfg.fpb(); l++) begin
        ucie_flit_item f = new("rx_cur");
        f.dir = UCIE_FDI_RX;
        f.phy = cfg.phy;
        f.t_start = $time;
        f.gap_before = l == 0 ? rx_gap : 0;
        rx_cur.push_back(f);
      end
      rx_gap = 0;
      rx_bubbles = 0;
    end
    if (e && !rx_err_unit) begin
      int unsigned bph = cfg.bph();
      int unsigned unit = cfg.bpf() == 1 ? (cfg.fpb() > 1 ? 3 : 2) : rx_beat / bph;
      int unsigned in_unit = rx_beat % bph;
      int unsigned pos = bph == 1 ? 3 : in_unit == 0 ? 0 : in_unit == bph - 1 ? 2 : 1;
      rx_err_unit = 1'b1;
      n_rx_errors++;
      if (fcov != null) fcov.sample_error(unit, pos);
    end
    // A replay after a cancel rewrites every lane (fewer flits leave NOPs).
    foreach (rx_cur[l]) rx_cur[l].put_beat(cfg.beat_bytes, rx_beat, vif.mon_cb.pl_data, l);
    rx_beat++;
    rx_half_done = (rx_beat % cfg.bph()) == 0;
  endfunction

  local function bit all_nop();
    foreach (rx_cur[l]) if (!rx_cur[l].is_nop()) return 1'b0;
    return 1'b1;
  endfunction

  // The flits of the finished beat(s), less the NOPs the Protocol Layer
  // discards.
  local function void publish_rx();
    int unsigned n_nop;
    foreach (rx_cur[l]) begin
      ucie_flit_item f = rx_cur[l];
      if (f.is_nop()) begin
        n_nop++;
        continue;
      end
      f.t_end = $time;
      if (f.n_cancel_h1 != 0) n_rx_cancel_h1++;
      if (f.n_cancel_h0 > 1 || f.n_cancel_h1 > 1) n_rx_cancel_rep++;
      f.n_stall_cycles = rx_bubbles;
      if (cov != null)
        cov.sample_xfer(UCIE_FDI_RX, cfg.beat_bytes, rx_bubbles, f.gap_before, f, l);
      if (fcov != null)
        fcov.sample_xfer(UCIE_FDI_RX, cfg.beat_bytes, rx_bubbles, f.gap_before, f, l);
      n_rx_flits++;
      `uvm_info(get_type_name(), {"RX ", f.convert2string()}, UVM_HIGH)
      ap_rx.write(f);
    end
    n_rx_nops += n_nop;
    if (cfg.fpb() > 1 && n_nop != 0) n_rx_part++;
    if (fcov != null && cfg.fpb() > 1) fcov.sample_lanes(cfg.fpb() - n_nop);
    rx_cur.delete();
    rx_beat = 0;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({"phy%0d: %0d TX, %0d RX flits, %0d RX cancels ",
                                          "(%0d while stalled; %0d flits with a second-half ",
                                          "cancel, %0d with a repeated one), %0d stalls (%0d ",
                                          "mid-flit, %0d of them with pl_trdy low); %0d TX ",
                                          "and %0d RX flits abandoned mid-flit; %0d RX beats ",
                                          "in Reset; %0d RX NOP flits discarded, %0d RX ",
                                          "cancels of NOPs, %0d RX beats not full; %0d RX ",
                                          "errors (pl_error), %0d TX transfers with ",
                                          "lp_corrupt_crc, %0d TX NOP flits"}, cfg.phy,
                                         n_tx_flits, n_rx_flits, n_rx_cancels, n_cancels_stalled,
                                         n_rx_cancel_h1, n_rx_cancel_rep, n_stalls, n_stalls_mid,
                                         n_stalls_trdy0, n_tx_abandoned, n_rx_abandoned,
                                         n_rx_beats_reset, n_rx_nops, n_rx_nop_cancels,
                                         n_rx_part, n_rx_errors, n_tx_corrupt, n_tx_nops),
              UVM_LOW)
  endfunction
endclass
