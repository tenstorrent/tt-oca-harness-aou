<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# axi/: L4 AXI agents, transaction, memory and remote model

Package `aou_axi_pkg` (`aou_axi_pkg.sv`, with `aou_axi_bus_if.sv`). Everything outside the agents sees only
`aou_axi_txn`.

## Why our own agents

The M0 spike evaluated pulp-platform/axi (see `docs/VIP_EVALUATION.md`). It isn't
UVM-shaped and lacks out-of-order B, timing policies, a transaction-rebuilding
monitor and an exclusive monitor. On Verilator it runs about 160x slower than VCS.
These agents are written from the AXI4 spec instead. The address and lane helpers
in `aou_axi_txn` follow AXI4 A3.4, and the monitor's handshake rules were
cross-checked against pulp's `AXI_BUS_DV` assertion list. No pulp code is copied.

## Pieces

| Class | Role |
|---|---|
| `aou_axi_bus_if #(DATA_W=1024)` | One AXI4 port. Clocking blocks `mgr_cb`, `sub_cb`, `mon_cb`. ID 10, ADDR 64, LEN 8 bits |
| `aou_axi_txn` | The contract transaction, plus `beats`, `beat_addr`, `beat_base`, `lane_lo/hi`, `lane_mask`, `crosses_4k`, `to_bytes` and `fill_wdata` |
| `aou_axi_cfg` | Per-agent config: `vif_key`/`vif`, `data_bytes`, `rp`, `local_side`, outstanding limits, `w_before_aw_en`, `reorder_en`, `r_interleave_en`, `exclusive_en`, `mem`, `checks_en`, `cov_en`, `timing` |
| `aou_axi_timing`, `aou_axi_delay` | Per-channel delays: zero, fixed, range or bursty. `apply(AOU_AXI_TIMING_*)` sets a profile |
| `aou_mem` | Sparse memory with seeded hashed initial contents, error regions (SLVERR/DECERR) and an exclusive monitor |
| `aou_axi_mgr_agent` | `sqr` (`aou_axi_sequencer`), `drv`, `mon`, `ap` |
| `aou_axi_sub_agent` | `drv` (answers from `cfg.mem`), `mon`, `ap` |
| `aou_axi_monitor` | Rebuilds transactions and publishes them on `ap` (writes after B, reads after RLAST). Checks rules AXI-R01..R18 (`checkers/rules.csv`). Coverage in `txn_cg` and `zero_cg` |
| `aou_remote_axi_model` | L4a remote subordinate: `execute(req, rsp)`. See ARCHITECTURE.md |
| `aou_axi_rand_seq` | Random legal traffic. Each in-flight transaction gets its own 4KB slot |
| `aou_axi_unaligned_wr_seq` | #56: single-beat writes and reads of every size at every offset |
| `aou_axi_b_zero_seq` | #64: back-to-back single-beat writes, then reads |

## Timing

- Manager: `*_valid` is the idle gap before each AW, W beat or AR. `b_ready` and
  `r_ready` are the cycles that ready stays low after each handshake.
- Subordinate: `*_ready` is the cycles ready stays low after each handshake.
  `b_lat` counts from the write's last AW/W handshake to BVALID, `r_lat` from the
  AR handshake to the first RVALID, and `r_beat` is the gap between R beats.
- A delay of 0 means ready is held high, or B/R valid is driven right after the
  handshake edge, so it is seen at the next edge (the #64 pattern).

## Driver boundary (for a VIP swap)

The drivers are the only VIP-replaceable part. The rest depends on them only as
follows:

- Sequences run on `aou_axi_sequencer` (`uvm_sequencer #(aou_axi_txn)` with a
  `cfg` handle) and send fully formed `aou_axi_txn`s.
- `item_done()` is called once a transaction is accepted. When it completes, the
  same object, with `bresp` or `data`/`rresp` filled in, is returned through
  `put_response()`.
- A subordinate answers from `cfg.mem` using `aou_mem::axi_write`,
  `axi_read_start` and `axi_read_resp`, so its responses match the scoreboard.
- The monitor depends only on `mon_cb`.

A VIP adapter has to keep these four points.

## Known limits

- No mid-test reset: the drivers and monitors drop state on reset, but sequences
  don't recover.
- The monitor checks a Verilator-safe subset of AXI4. `Axi4PC` (optional, see the
  top-level README) covers the rest.
- Verilator 5.052 builds the covergroups but `get_coverage()` returns 0. The
  monitor's counters (`n_b_zero`, `n_r_zero`) are what tests check.
