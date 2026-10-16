// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// L1: FDI mainband with UCIe Flit Format 6 (Latency-Optimized 256B with
// optional bytes). Flit item, Format 6 codec, PL driver (to the DUT RX), TX
// responder (pl_trdy and stallreq towards the DUT TX), monitor with protocol
// checks and coverage. Rule IDs refer to checkers/rules.csv.

package aou_fdi_pkg;
  import uvm_pkg::*;
  import aou_rule_pkg::*;
  import aou_fc_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  `include "aou_fc_macros.svh"

  localparam int FLIT_BYTES     = 256;
  localparam int HALF_BYTES     = 128;
  localparam int MAX_BEAT_BYTES = 128;
  localparam int BUS_W          = 1024;

  // UCIe pl_state_sts Active; the same value in the UCIe and RTL encodings.
  localparam logic [3:0] FDI_STS_ACTIVE = 4'h1;
  localparam logic [3:0] FDI_STS_RESET  = 4'h0;

  // TX: Protocol Layer (DUT) to Adapter. RX: Adapter to Protocol Layer (DUT).
  typedef enum bit {AOU_FDI_TX, AOU_FDI_RX} aou_fdi_dir_e;

  // How the PL driver cancels a 128B half: not at all, with pl_valid low in
  // the cancel cycle, or with the replay's first beat in the cancel cycle.
  typedef enum bit [1:0] {
    AOU_CANCEL_NONE,
    AOU_CANCEL_IDLE,
    AOU_CANCEL_VALID
  } aou_fdi_cancel_e;

  typedef enum bit [1:0] {
    AOU_TRDY_ALWAYS,  // pl_trdy high whenever the link is Active
    AOU_TRDY_RANDOM,  // each cycle high with trdy_pct
    AOU_TRDY_BURSTY,  // alternating high/low runs of 1..burst_max cycles
    AOU_TRDY_HOLES    // high, with holes only inside a flit (hole_pct per beat)
  } aou_fdi_trdy_e;

  typedef logic [BUS_W-1:0] aou_fdi_beat_t;

  // ---------------------------------------------------------------------------
  // Format 6 codec. Flit byte k travels on FDI byte (k mod N) of transfer
  // floor(k/N), N = beat bytes (UCIe r1.1 §8.3.1). Bytes 0-1 (Flit Header)
  // and 126-127, 254-255 (CRC0/CRC1) belong to the Adapter.
  // ---------------------------------------------------------------------------
  function automatic bit valid_beat_bytes(int unsigned n);
    return n inside {32, 64, 128};
  endfunction

  function automatic int unsigned beats_per_flit(int unsigned beat_bytes);
    return FLIT_BYTES / beat_bytes;
  endfunction

  function automatic int unsigned beats_per_half(int unsigned beat_bytes);
    return HALF_BYTES / beat_bytes;
  endfunction

  function automatic bit is_adapter_byte(int unsigned i);
    return i inside {0, 1, 126, 127, 254, 255};
  endfunction

  function automatic bit is_crc_byte(int unsigned i);
    return i inside {126, 127, 254, 255};
  endfunction

  `include "l1/aou_fdi_gate.svh"
  `include "l1/aou_fdi_cfg.svh"
  `include "l1/aou_flit_item.svh"
  `include "l1/aou_fdi_fc_bins.svh"
  `include "l1/aou_fdi_cov.svh"
  `include "l1/aou_fdi_pl_driver.svh"
  `include "l1/aou_fdi_tx_responder.svh"
  `include "l1/aou_fdi_monitor.svh"
  `include "l1/aou_fdi_agent.svh"
  `include "l1/aou_flit_seq.svh"

endpackage
