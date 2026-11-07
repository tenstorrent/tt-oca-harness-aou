// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Adapter side of the Protocol Layer's TX: pl_trdy by policy, and pl_stallreq (UCIe r3.0
// §10.3.2).
// - pl_trdy is low at flit boundaries while the gate is closed or
//   cfg.tx_hold is set; a started flit is always allowed to finish (Flit
//   mode exits from Active other than to PM "simply de-assert pl_trdy at a
//   Flit boundary before state transition", §10.3.2).
// - While pl_stallreq is high and lp_stallack low, the Adapter accepts the
//   data the Protocol Layer presents (§10.3.2 rule 7: "any data presented on
//   the interface must be accepted by the physical layer until the rising
//   edge of lp_stallack"), gate closed or open and tx_hold or not: trdy is
//   held high, or with cfg.stall_trdy_free follows its policy, lows included
//   ("pl_trdy is not required to be asserted consecutively"; every policy
//   raises it again). A Protocol Layer that presented a flit may keep it up
//   until it transfers (§10.2.4) and may not acknowledge before (rule 6), so
//   without this the handshake might never end (FDI-R11).
// - LinkError does not wait for the handshake (§10.3.3.7; gate.stall_cut, or
//   gate.abort mid-flit): trdy then only finishes a started flit (none after
//   an abort, where the partial flit is abandoned), and the Protocol Layer
//   cleans up its data path without pl_trdy (§10.3.3.7). The handshake runs
//   on in LinkError: pl_stallreq falls only after lp_stallack (rule 3).
// - Stand-alone stalls (cfg.stall_pct) start only while the gate is open, at
//   a flit boundary, or mid-flit for cfg.stall_mid_pct of them (on a 256 B
//   FDI a flit is one beat, so always at a boundary). In Flit mode r3.0 uses
//   the handshake only on the way to PM (§10.3.2), so they are stress beyond
//   the spec. One under way when L2 closes the gate for Retrain, LinkReset or
//   Disabled runs to its end, all four phases, before L2 changes the status
//   (gate.stall_busy, quiet()), so pl_trdy is never high outside Active
//   (Table 10-3 pl_trdy). A PM entry's stall ends with lp_stallack before L2
//   leaves Active.
// - pl_stallreq rises only with lp_stallack low and falls only with it high
//   (rules 2 and 3, FDI-R08). Reset drops it (rule 3 allows that) and ends
//   any handshake in progress, so neither a stand-alone stall nor the stall
//   of a PM entry that a reset stopped is resumed afterwards.
class ucie_fdi_tx_responder extends uvm_component;
  `uvm_component_utils(ucie_fdi_tx_responder)

  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  ucie_fdi_cfg cfg;

  local bit          trdy_q;
  local bit          stallreq_q;
  local bit          stall_want;
  local int unsigned n_resets;  // resets that ended a handshake under way
  local int unsigned tx_beat;
  local bit          run_val;
  local int unsigned run_left;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.pl_trdy <= 1'b0;
    vif.drv_cb.pl_stallreq <= 1'b0;
    fork
      random_stalls();
    join_none
    forever begin
      @(vif.drv_cb);
      step();
      vif.drv_cb.pl_trdy <= trdy_q;
      vif.drv_cb.pl_stallreq <= stallreq_q;
    end
  endtask

  local function void step();
    bit ack = vif.drv_cb.lp_stallack === 1'b1;
    bit rise = 1'b0;
    if (vif.drv_cb.rst_n !== 1'b1) begin
      trdy_q = 1'b0;
      stallreq_q = 1'b0;
      if (stall_want || cfg.gate.stall_busy) n_resets++;
      stall_want = 1'b0;
      cfg.gate.stall_busy = 1'b0;
      tx_beat = 0;
      cfg.gate.set_tx_busy(1'b0);
      return;
    end
    if (trdy_q && vif.drv_cb.lp_valid === 1'b1 && vif.drv_cb.lp_irdy === 1'b1)
      tx_beat = (tx_beat + 1) % cfg.bpf();
    // LinkError mid-flit: the partial TX flit is abandoned, never accepted.
    if (cfg.gate.abort) tx_beat = 0;
    cfg.gate.set_tx_busy(tx_beat != 0);

    if (stall_want && !stallreq_q && !ack) begin
      stallreq_q = 1'b1;
      rise = 1'b1;
    end else if (!stall_want && stallreq_q && ack) begin
      stallreq_q = 1'b0;
    end

    if (cfg.gate.abort) trdy_q = 1'b0;
    else if (stallreq_q && !ack && !cfg.gate.stall_cut)
      trdy_q = cfg.stall_trdy_free ? policy() : 1'b1;
    else if (!cfg.gate.open || cfg.tx_hold) trdy_q = tx_beat != 0;
    else trdy_q = policy();
    // Rule 7 corner: half of the mid-flit stalls start with pl_trdy low.
    if (rise && cfg.stall_trdy_free && tx_beat != 0 && $urandom_range(1) != 0) trdy_q = 1'b0;
  endfunction

  local function bit policy();
    case (cfg.trdy_policy)
      UCIE_TRDY_RANDOM: return $urandom_range(99) < cfg.trdy_pct;
      UCIE_TRDY_BURSTY: begin
        if (run_left == 0) begin
          run_val = !run_val;
          run_left = $urandom_range(cfg.burst_max, 1);
        end
        run_left--;
        return run_val;
      end
      UCIE_TRDY_HOLES:  return tx_beat == 0 || $urandom_range(99) >= cfg.hole_pct;
      default:         return 1'b1;
    endcase
  endfunction

  // Raise pl_stallreq and return once lp_stallack is high. Used by L2 before
  // a PM entry and by the random stalls; callers take turns. Returns early if
  // a reset ends the handshake (the caller then skips stall_end).
  task stall_begin();
    int unsigned r;
    while (cfg.gate.stall_busy) @(vif.drv_cb);
    cfg.gate.stall_busy = 1'b1;
    stall_want = 1'b1;
    r = n_resets;
    do @(vif.drv_cb);
    while (!(stallreq_q && vif.drv_cb.lp_stallack === 1'b1) && r == n_resets);
  endtask

  // Drop pl_stallreq and return once lp_stallack is low again: the
  // handshake's four phases are done (r3.0 §10.3.2 rule 9).
  task stall_end();
    int unsigned r = n_resets;
    stall_want = 1'b0;
    do @(vif.drv_cb); while ((stallreq_q || vif.drv_cb.lp_stallack !== 1'b0) && r == n_resets);
    if (r == n_resets) cfg.gate.stall_busy = 1'b0;
  endtask

  function bit stalled();
    return stall_want;
  endfunction

  // Stand-alone stalls (cfg.stall_pct; see the header). Only while the gate
  // is open: L2 closes it before it leaves Active and then waits for one
  // already under way (gate.quiet()). A reset ends one where it stands.
  local task random_stalls();
    if (cfg.stall_pct == 0) return;
    forever begin
      bit mid;
      int unsigned r;
      @(vif.drv_cb);
      mid = cfg.bpf() > 1 && $urandom_range(99) < cfg.stall_mid_pct;
      // None while the TX is held (tx_hold): the handshake raises pl_trdy
      // (rule 7) and would let flits through the hold.
      if (cfg.gate.open && !cfg.tx_hold && (mid ? tx_beat != 0 : tx_beat == 0) &&
          !cfg.gate.stall_busy && $urandom_range(99) < cfg.stall_pct) begin
        r = n_resets;
        stall_begin();
        if (r == n_resets) repeat ($urandom_range(cfg.stall_hold_max, cfg.stall_hold_min))
          @(vif.drv_cb);
        if (r == n_resets) stall_end();
        repeat (cfg.bpf()) @(vif.drv_cb);
      end
    end
  endtask
endclass
