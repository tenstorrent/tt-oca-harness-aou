// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class ucie_fdi_cfg extends uvm_object;
  `uvm_object_utils(ucie_fdi_cfg)

  int unsigned   phy = 0;
  // FDI width of this PHY: 32, 64, 128, 256, 512 or 1024 B (any other is a
  // fatal error)
  int unsigned   beat_bytes = 64;
  bit            is_active = 1'b1;    // 0: monitor only

  // TX responder
  ucie_fdi_trdy_e trdy_policy = UCIE_TRDY_ALWAYS;
  int unsigned   trdy_pct = 70;       // RANDOM: chance trdy is high
  int unsigned   hole_pct = 20;       // HOLES: chance of a hole before a mid-flit beat
  int unsigned   burst_max = 8;       // BURSTY: longest high or low run
  // Stand-alone stalls: the chance of a pl_stallreq/lp_stallack handshake with
  // no state change, per flit boundary in Active. Out-of-spec stress: in Flit
  // mode UCIe r3.0 §10.3.2 uses the handshake only when exiting Active to PM
  // ("must only be used when exiting Active State to a PM state"), so a
  // Protocol Layer may take pl_stallreq as the start of a PM entry. 0 (the
  // default): none, only the stall of a PM entry. A stall under way when the
  // link leaves Active is finished first, except on the way to LinkError,
  // where it runs on (ucie_fdi_tx_responder).
  int unsigned   stall_pct = 0;
  // Cycles a stand-alone stall holds pl_stallreq high after lp_stallack, from
  // stall_hold_min to stall_hold_max. 0 drops it as soon as the ack is seen
  // (r3.0 §10.3.2 sets no minimum), the shortest stall the Protocol Layer
  // can see.
  int unsigned   stall_hold_min = 1;
  int unsigned   stall_hold_max = 8;
  // Stall corners (r3.0 §10.3.2): the share of stand-alone stalls raised
  // mid-flit instead of at a boundary (none on a 256 B FDI, where a flit is
  // one beat and every cycle is a flit boundary; out-of-spec with stall_pct),
  // and pl_trdy following its policy (lows included; rule 7: "pl_trdy is not
  // required to be asserted consecutively") between pl_stallreq and
  // lp_stallack instead of being held high, for every stall, a PM entry's
  // included. Either way pl_trdy keeps coming during the stall, whether the
  // gate is open or closed, so data presented before lp_stallack is accepted
  // (rule 7); every policy raises it again (RANDOM needs trdy_pct > 0).
  int unsigned   stall_mid_pct = 0;
  bit            stall_trdy_free = 1'b0;
  // A stall handshake open when the link enters LinkError (r3.0 §10.3.3.7:
  // "It is not required to complete the stallreq/ack handshake before
  // entering this state"). 0: the Adapter does not perform it there:
  // pl_stallreq stays high in the first clock that shows LinkError and falls
  // on the next (a clock after the status changes), and pl_trdy stays low.
  // 1: it does ("If the lower layer decides to perform a pl_stallreq/
  // lp_stallack handshake, it must provide pl_trdy to the upper layer to
  // drain the packets"): pl_trdy drains the Protocol Layer until lp_stallack,
  // and a handshake still open when the link leaves LinkError is abandoned
  // with the move to Reset. Either way the Adapter never waits for
  // lp_stallack in LinkError: the upper layer must clean up its data path
  // there "even if pl_trdy is not asserted", and need not acknowledge.
  bit            le_stall_drain = 1'b0;
  // FDI-R57: lp_stallack must answer pl_stallreq within this many cycles.
  int unsigned   stall_timeout = 2000;
  // Back-pressure hold: pl_trdy low from the next flit boundary while set.
  bit            tx_hold = 1'b0;

  // PL driver
  // Fill FH/CRC with random bytes; the Protocol Layer must ignore them. The
  // Protocol ID and the Flit Type (Byte 0 and Byte 1 [7:6]) stay as the flit
  // has them (ucie_flit_item::randomize_adapter_bytes).
  bit            random_adapter_bytes = 1'b0;
  bit            poison_cancelled = 1'b1; // cancelled copies carry random bytes
  // 512 B and up: chance a transfer is sent with fewer flits than it could
  // carry, the empty lanes zero (NOP), as an Adapter does after a gap on the
  // Link (UCIe r3.0 10.3.1). Without it a transfer is short only when the
  // sequence has no more flits ready.
  int unsigned   partial_beat_pct = 0;
  // The chance the PL driver forwards a NOP flit (ucie_flit_item::make_nop:
  // Protocol ID 00b, random sequence number and Ack/Nak bits, r3.0 Table 3-5;
  // an all-zero body, §3.1) before a flit of the sequence, at every width, and from 512 B
  // up also in each further lane of a transfer. A third of the stand-alone
  // NOPs go through uncancelled, which the Protocol Layer must discard; a
  // third are cancelled with an ordinary cancel plan and replayed; a third are
  // cancelled and never replayed (their first 128B half, from 256 B up the
  // transfer, with pl_valid low in the cancel cycle), as Table 10-3
  // pl_flit_cancel lets an Adapter do to keep NOPs from the Protocol Layer.
  // 0 (the default): none. +ucie_nop_pct=N sets it.
  int unsigned   nop_pct = 0;
  // pl_stream, the stream ID of the data on this FDI (UCIe r3.0 Table
  // 10-3): tied to this value, as an integration may do (r3.0 10.2.1), and
  // the one lp_stream must carry with lp_valid (FDI-R64). Its protocol sets
  // the flit rules: Streaming (x4h) or CXL.cachemem (x3h), whose Format 6
  // layouts the model carries; PCIe, CXL.io and Management Transport streams
  // are refused (stream_layout_modelled). Protocol ID 00b on TX (a NOP) is an
  // FDI-R45 error on a Streaming stream only (stream_tx_nop_legal). The
  // default is Stack 0 Streaming, matching ucie_lsm_cfg::protocol.
  bit [7:0]      stream = UCIE_STREAM_S0_STREAMING;
  // pl_error (UCIe r3.0 Table 10-3): the chance an RX flit meets a framing
  // error the Adapter detects. pl_error pulses with pl_valid on one transfer
  // of a 128B half (from 256 B up, of the transfer); the Adapter finishes that
  // half, cancels it, retrains the link (the link-state agent runs a Retrain)
  // and only then replays it. Only in Active. 0 (default): never.
  int unsigned   error_pct = 0;
  // Cycles the PL driver waits for that Retrain before it reports an error and
  // replays anyway (no active link-state agent).
  int unsigned   error_retrain_timeout = 100000;

  // Monitor
  bit            checks_en = 1'b1;
  bit            cov_en = 1'b1;
  // The model's own covergroups (ucie_fdi_fcov), apart from a bench's
  // collector; +ucie_fcov=0|1 overrides it.
  bit            fcov_en = 1'b1;
  bit            check_tx_adapter_bytes = 1'b1;
  // FDI-R44: cycles lp_irdy may stay high after LinkError -> Reset. UCIe r3.0
  // Table 10-3 allows "a few clocks" there and gives no number, so this is a
  // liveness bound; on any other entry to Reset lp_irdy must already be low.
  int unsigned   irdy_reset_grace = 4;

  ucie_fdi_gate   gate;

  function new(string name = "ucie_fdi_cfg");
    super.new(name);
    gate = ucie_fdi_gate::type_id::create("gate");
  endfunction

  function int unsigned bpf();
    return beats_per_flit(beat_bytes);
  endfunction

  function int unsigned fpb();
    return flits_per_beat(beat_bytes);
  endfunction

  function int unsigned bph();
    return beats_per_half(beat_bytes);
  endfunction

  function string convert2string();
    return $sformatf({"phy=%0d beat_bytes=%0d active=%0b trdy=%s stall_pct=%0d mid=%0d ",
                      "stall_hold=%0d..%0d trdy_free=%0b le_drain=%0b hold=%0b stream=%02h ",
                      "nop=%0d"}, phy, beat_bytes, is_active, trdy_policy.name(), stall_pct,
                     stall_mid_pct, stall_hold_min, stall_hold_max, stall_trdy_free,
                     le_stall_drain, tx_hold, stream, nop_pct);
  endfunction
endclass
