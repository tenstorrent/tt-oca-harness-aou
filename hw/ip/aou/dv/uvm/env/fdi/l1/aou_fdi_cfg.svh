// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class aou_fdi_cfg extends uvm_object;
  `uvm_object_utils(aou_fdi_cfg)

  int unsigned   phy = 0;
  int unsigned   beat_bytes = 64;     // 32, 64 or 128 (FDI width of this PHY)
  bit            is_active = 1'b1;    // 0: monitor only

  // TX responder
  aou_fdi_trdy_e trdy_policy = AOU_TRDY_ALWAYS;
  int unsigned   trdy_pct = 70;       // RANDOM: chance trdy is high
  int unsigned   hole_pct = 20;       // HOLES: chance of a hole before a mid-flit beat
  int unsigned   burst_max = 8;       // BURSTY: longest high or low run
  int unsigned   stall_pct = 0;       // chance of a stand-alone stall at a flit boundary
  int unsigned   stall_hold_max = 8;  // cycles stallreq stays high after stallack
  // Stall corners (UCIe r1.1 8.3.2): the share of stand-alone stalls raised
  // mid-flit instead of at a boundary, and pl_trdy keeping its policy (lows
  // included; rule 7 does not require consecutive pl_trdy) between pl_stallreq
  // and lp_stallack instead of being held high.
  int unsigned   stall_mid_pct = 0;
  bit            stall_trdy_free = 1'b0;
  // FDI-R57: lp_stallack must answer pl_stallreq within this many cycles.
  int unsigned   stall_timeout = 2000;
  // Back-pressure hold: pl_trdy low from the next flit boundary while set.
  bit            tx_hold = 1'b0;

  // PL driver
  // Fill FH/CRC with random bytes; the Protocol Layer must ignore them.
  bit            random_adapter_bytes = 1'b0;
  bit            poison_cancelled = 1'b1; // cancelled copies carry random bytes

  // Monitor
  bit            checks_en = 1'b1;
  bit            cov_en = 1'b1;
  bit            check_tx_adapter_bytes = 1'b1;
  int unsigned   irdy_reset_grace = 4; // cycles lp_irdy may stay high after entering Reset

  aou_fdi_gate   gate;

  function new(string name = "aou_fdi_cfg");
    super.new(name);
    gate = aou_fdi_gate::type_id::create("gate");
  endfunction

  function int unsigned bpf();
    return beats_per_flit(beat_bytes);
  endfunction

  function int unsigned bph();
    return beats_per_half(beat_bytes);
  endfunction

  function string convert2string();
    return $sformatf({"phy=%0d beat_bytes=%0d active=%0b trdy=%s stall_pct=%0d mid=%0d ",
                      "trdy_free=%0b hold=%0b"}, phy, beat_bytes, is_active, trdy_policy.name(),
                     stall_pct, stall_mid_pct, stall_trdy_free, tx_hold);
  endfunction
endclass
