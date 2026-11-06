// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// L1: FDI mainband with UCIe Flit Format 6 (Latency-Optimized 256B with
// optional bytes), on FDIs of 32 to 1024 bytes. Flit item, Format 6 codec,
// PL driver (to the DUT RX), TX responder (pl_trdy and stallreq towards the
// DUT TX), monitor with protocol checks and a coverage hook. Rule IDs are listed in ../README.md.

package ucie_fdi_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "ucie_fdi_macros.svh"

  localparam int FLIT_BYTES     = 256;
  localparam int HALF_BYTES     = 128;
  localparam int MIN_BEAT_BYTES = 32;
  localparam int MAX_BEAT_BYTES = 1024;
  localparam int BUS_W          = MAX_BEAT_BYTES * 8;
  // The most transfers one flit can take (at the narrowest FDI).
  localparam int MAX_BEATS_PER_FLIT = FLIT_BYTES / MIN_BEAT_BYTES;

  // UCIe pl_state_sts Active; the same value in the UCIe and RTL encodings.
  localparam logic [3:0] FDI_STS_ACTIVE = 4'h1;
  localparam logic [3:0] FDI_STS_RESET  = 4'h0;

  // What the Adapter reports as negotiated (UCIe r3.0 Table 10-3). pl_protocol: bit 3 is "with Management Transport" (1001b is
  // Management Transport alone); the low bits 000b PCIe, 011b CXL.1 (CXL.io),
  // 100b..110b CXL.2..CXL.4 (CXL.io and CXL.cachemem), 111b Streaming.
  localparam logic [3:0] UCIE_PROTO_PCIE      = 4'b0000;
  localparam logic [3:0] UCIE_PROTO_CXL1      = 4'b0011;
  localparam logic [3:0] UCIE_PROTO_CXL2      = 4'b0100;
  localparam logic [3:0] UCIE_PROTO_CXL3      = 4'b0101;
  localparam logic [3:0] UCIE_PROTO_CXL4      = 4'b0110;
  localparam logic [3:0] UCIE_PROTO_STREAMING = 4'b0111;
  localparam logic [3:0] UCIE_PROTO_MGMT      = 4'b1001;
  // pl_protocol_flitfmt: the model carries Format 6 only.
  localparam logic [3:0] UCIE_FLITFMT_6       = 4'b0110;
  // pl_stream/lp_stream: [7:4] the stack (0 or 1), [3:0] the protocol: 1 PCIe,
  // 2 CXL.io, 3 CXL.cachemem, 4 Streaming, 5 Management Transport.
  localparam logic [7:0] UCIE_STREAM_S0_STREAMING = 8'h04;

  function automatic bit protocol_defined(logic [3:0] p);
    return p inside {4'b0000, [4'b0011:4'b1001], [4'b1011:4'b1111]};
  endfunction

  // CXL.cachemem is part of the protocol: the only case lp_corrupt_crc applies.
  function automatic bit protocol_has_cachemem(logic [3:0] p);
    return p[2:0] inside {3'b100, 3'b101, 3'b110};
  endfunction

  function automatic bit protocol_is_streaming(logic [3:0] p);
    return p[2:0] == 3'b111;
  endfunction

  // A stream ID that is defined and names a protocol the link negotiated.
  function automatic bit stream_fits(logic [3:0] p, logic [7:0] s);
    if (!(s[7:4] inside {4'h0, 4'h1})) return 1'b0;
    case (s[3:0])
      4'h1:    return p == UCIE_PROTO_PCIE || p == 4'b1000;
      4'h2:    return p[2:0] inside {3'b011, 3'b100, 3'b101, 3'b110};
      4'h3:    return protocol_has_cachemem(p);
      4'h4:    return protocol_is_streaming(p);
      4'h5:    return p[3];
      default: return 1'b0;
    endcase
  endfunction

  // TX: Protocol Layer (DUT) to Adapter. RX: Adapter to Protocol Layer (DUT).
  typedef enum bit {UCIE_FDI_TX, UCIE_FDI_RX} ucie_fdi_dir_e;

  // How the PL driver cancels a 128B half (from 256 B up, every flit of the
  // transfer): not at all, with pl_valid low in the cancel cycle, or with the
  // replay's first beat in the cancel cycle.
  typedef enum bit [1:0] {
    UCIE_CANCEL_NONE,
    UCIE_CANCEL_IDLE,
    UCIE_CANCEL_VALID
  } ucie_fdi_cancel_e;

  typedef enum bit [1:0] {
    UCIE_TRDY_ALWAYS,  // pl_trdy high whenever the link is Active
    UCIE_TRDY_RANDOM,  // each cycle high with trdy_pct
    UCIE_TRDY_BURSTY,  // alternating high/low runs of 1..burst_max cycles
    UCIE_TRDY_HOLES    // high, with holes only inside a flit (hole_pct per beat)
  } ucie_fdi_trdy_e;

  typedef logic [BUS_W-1:0] ucie_fdi_beat_t;

  // ---------------------------------------------------------------------------
  // Format 6 codec. Flit byte k travels on FDI byte (k mod N) of transfer
  // floor(k/N), N = beat bytes (UCIe r1.1 §8.3.1). Bytes 0-1 (Flit Header)
  // and 126-127, 254-255 (CRC0/CRC1) belong to the Adapter.
  //
  // The cancel unit. pl_flit_cancel comes in the cycle after the last chunk
  // of a 128B half (UCIe r1.1 Table 8-2). Up to 128 B a half ends on its own
  // transfer, so each half has its own cancel. On a 256 B FDI the flit is one
  // transfer and both halves end in it, so the one cancel after it applies to
  // the whole flit (as UCIe r3.0 10.3.1 says of wider FDIs: a cancel applies
  // to every flit in that clock).
  //
  // Wider FDIs (UCIe r3.0 10.3.1, Implementation Note "NBYTES"): a 512 or
  // 1024 B transfer carries 2 or 4 flits, flit j on bytes 256j to 256j+255
  // (lane j; the byte mapping above, continued). The Adapter forwards whole
  // flits on the low lanes and zeros on the rest, and a Flit Header of 0000h
  // is a NOP the Protocol Layer discards; the Protocol Layer sends valid flits
  // on every lane. pl_flit_cancel applies to every flit of the transfer
  // before it. The helpers below are the only place the width arithmetic
  // lives.
  // ---------------------------------------------------------------------------
  function automatic bit valid_beat_bytes(int unsigned n);
    return n inside {32, 64, 128, 256, 512, 1024};
  endfunction

  // Transfers per flit: 1 once a transfer holds a whole flit.
  function automatic int unsigned beats_per_flit(int unsigned beat_bytes);
    return (beat_bytes >= FLIT_BYTES) ? 1 : FLIT_BYTES / beat_bytes;
  endfunction

  // Flits per transfer (lanes): 1 up to 256 B, beat_bytes / 256 above.
  function automatic int unsigned flits_per_beat(int unsigned beat_bytes);
    return (beat_bytes > FLIT_BYTES) ? beat_bytes / FLIT_BYTES : 1;
  endfunction

  // Bytes of one flit in one transfer: the beat, or the flit's 256 B lane.
  function automatic int unsigned flit_chunk_bytes(int unsigned beat_bytes);
    return (beat_bytes > FLIT_BYTES) ? FLIT_BYTES : beat_bytes;
  endfunction

  // Beats of one cancel unit: a 128B half, or one beat from 256 B up.
  function automatic int unsigned beats_per_half(int unsigned beat_bytes);
    return (beat_bytes >= FLIT_BYTES) ? 1 : HALF_BYTES / beat_bytes;
  endfunction

  // Cancel units per flit: 2 halves up to 128 B; 1 from 256 B up, where the
  // unit is the transfer (one flit at 256 B, every flit in it above).
  function automatic int unsigned halves_per_flit(int unsigned beat_bytes);
    return beats_per_flit(beat_bytes) / beats_per_half(beat_bytes);
  endfunction

  function automatic bit is_adapter_byte(int unsigned i);
    return i inside {0, 1, 126, 127, 254, 255};
  endfunction

  function automatic bit is_crc_byte(int unsigned i);
    return i inside {126, 127, 254, 255};
  endfunction

  `include "ucie_rule_log.svh"
  `include "l1/ucie_fdi_gate.svh"
  `include "l1/ucie_fdi_cfg.svh"
  `include "l1/ucie_flit_item.svh"
  `include "l1/ucie_fdi_cov.svh"
  `include "l1/ucie_fdi_fcov.svh"
  `include "l1/ucie_fdi_pl_driver.svh"
  `include "l1/ucie_fdi_tx_responder.svh"
  `include "l1/ucie_fdi_monitor.svh"
  `include "l1/ucie_fdi_agent.svh"
  `include "l1/ucie_flit_seq.svh"

endpackage
