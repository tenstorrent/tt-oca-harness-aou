// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Adapter side of the DUT TX: pl_trdy by policy, and pl_stallreq.
// - pl_trdy is low at flit boundaries while the gate is closed or
//   cfg.tx_hold is set; a started flit is always allowed to finish (Active
//   exits drop trdy at a flit boundary, UCIe r1.1 §8.3.2).
// - While pl_stallreq is high and lp_stallack low, trdy stays high so the
//   DUT can reach a flit boundary (FDI-R11), or with cfg.stall_trdy_free
//   keeps its policy, lows included (r1.1 8.3.2 rule 7).
// - Stand-alone stalls start at a flit boundary, or mid-flit for
//   cfg.stall_mid_pct of them.
// - pl_stallreq rises only with lp_stallack low and falls only with it high
//   (FDI-R08).
class aou_fdi_tx_responder extends uvm_component;
  `uvm_component_utils(aou_fdi_tx_responder)

  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  aou_fdi_cfg cfg;

  local bit          trdy_q;
  local bit          stallreq_q;
  local bit          stall_want;
  local bit          stall_busy;
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
      tx_beat = 0;
      cfg.gate.tx_busy = 1'b0;
      return;
    end
    if (trdy_q && vif.drv_cb.lp_valid === 1'b1 && vif.drv_cb.lp_irdy === 1'b1)
      tx_beat = (tx_beat + 1) % cfg.bpf();
    // LinkError mid-flit: the partial DUT flit is abandoned, never accepted.
    if (cfg.gate.abort) tx_beat = 0;
    cfg.gate.tx_busy = tx_beat != 0;

    if (stall_want && !stallreq_q && !ack) begin
      stallreq_q = 1'b1;
      rise = 1'b1;
    end else if (!stall_want && stallreq_q && ack) begin
      stallreq_q = 1'b0;
    end

    if (cfg.gate.abort) trdy_q = 1'b0;
    else if (stallreq_q && !ack && !cfg.stall_trdy_free) trdy_q = 1'b1;
    else if (!cfg.gate.open || cfg.tx_hold) trdy_q = tx_beat != 0;
    else trdy_q = policy();
    // Rule 7 corner: half of the mid-flit stalls start with pl_trdy low.
    if (rise && cfg.stall_trdy_free && tx_beat != 0 && $urandom_range(1) != 0) trdy_q = 1'b0;
  endfunction

  local function bit policy();
    case (cfg.trdy_policy)
      AOU_TRDY_RANDOM: return $urandom_range(99) < cfg.trdy_pct;
      AOU_TRDY_BURSTY: begin
        if (run_left == 0) begin
          run_val = !run_val;
          run_left = $urandom_range(cfg.burst_max, 1);
        end
        run_left--;
        return run_val;
      end
      AOU_TRDY_HOLES:  return tx_beat == 0 || $urandom_range(99) >= cfg.hole_pct;
      default:         return 1'b1;
    endcase
  endfunction

  // Raise pl_stallreq and return once lp_stallack is high. Used by L2 before
  // a PM entry and by the random stalls; callers take turns.
  task stall_begin();
    while (stall_busy) @(vif.drv_cb);
    stall_busy = 1'b1;
    stall_want = 1'b1;
    do @(vif.drv_cb); while (!(stallreq_q && vif.drv_cb.lp_stallack === 1'b1));
  endtask

  // Drop pl_stallreq and return once lp_stallack is low again.
  task stall_end();
    stall_want = 1'b0;
    do @(vif.drv_cb); while (stallreq_q || vif.drv_cb.lp_stallack !== 1'b0);
    stall_busy = 1'b0;
  endtask

  function bit stalled();
    return stall_want;
  endfunction

  local task random_stalls();
    if (cfg.stall_pct == 0) return;
    forever begin
      bit mid;
      @(vif.drv_cb);
      mid = $urandom_range(99) < cfg.stall_mid_pct;
      if (cfg.gate.open && (mid ? tx_beat != 0 : tx_beat == 0) && !stall_busy &&
          $urandom_range(99) < cfg.stall_pct) begin
        stall_begin();
        repeat ($urandom_range(cfg.stall_hold_max, 1)) @(vif.drv_cb);
        stall_end();
        repeat (cfg.bpf()) @(vif.drv_cb);
      end
    end
  endtask
endclass
