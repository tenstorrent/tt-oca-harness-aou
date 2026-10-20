<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Verification IP evaluation for the AoU UVM testbench

Decision record, October 2026. It covers the open-source AXI4 and APB
verification IP we evaluated for the VIP-free AoU testbench (`hw/ip/aou/dv`), why we
chose our own agents, and the third-party checker we use alongside them.

## Decision

| Interface | Decision | Third-party code used |
|---|---|---|
| AXI4 (manager, subordinate, monitor) | Our own agents (`uvm/env/axi/`) | Address and lane arithmetic follows AXI4 §A3.4; monitor rules were cross-checked against pulp-platform's `AXI_BUS_DV` assertion list. No code copied. |
| AXI4 protocol checking | Arm `Axi4PC` (BP063), optional | Downloaded by each user from Arm; never committed (licence) |
| APB3 | Our own agent (`uvm/env/apb/`) | Interface assertions adapted from amiq_apb (Apache-2.0, attributed) |

Because the scoreboard, sequences and tests only see the VIP-neutral
`aou_axi_txn`, the AXI pin-level agents can still be swapped for another
implementation later by writing one adapter (`uvm/env/axi/README.md`).

## What we needed

The testbench must run on VCS (primary) and Verilator 5.052 (cross-check),
using Accellera uvm-core 2020.3.1 compiled from source. The AXI agents had to
provide:

- independent AW/W/B/AR/R channels, up to 32 outstanding transactions per
  direction, and W before AW;
- out-of-order responses across IDs, in order within an ID, and read
  interleaving;
- per-channel valid/ready timing policies, including B and R zero cycles after
  the last W or AR handshake;
- every size and alignment, including unaligned starts, narrow transfers and
  sparse or zero WSTRB;
- INCR, WRAP and FIXED bursts, exclusive access (AxLOCK), and 4 KB legality;
- 256, 512 and 1024-bit data, 64-bit address, 10-bit ID;
- a monitor that rebuilds complete transactions for a scoreboard;
- UVM sequence items and sequences, protocol checks and functional coverage;
- a licence compatible with an Apache-2.0 repository, and active maintenance.

## AXI4 candidates

Each candidate except verilaxi was cloned, read against these requirements, and built in a
manager-to-subordinate test at 512-bit data, 64-bit address and 10-bit ID on
both simulators through LSF. verilaxi was assessed by reading the code. GitHub issues and pull requests were reviewed for
maintenance and recurring bug types.

### Summary

| Requirement | Our agents | tvip-axi | pulp-platform/axi | verilaxi | axi4_avip |
|---|---|---|---|---|---|
| Independent channels, outstanding traffic | ✓ | ✓ | ✓ | ✗ one transaction at a time | ✓ but outstanding sequences hang (fixed locally) |
| W before AW | ✓ | ✓ | ✓ | ✗ | ✗ W tied to its AW |
| Out-of-order and interleaved responses | ✓ | ✓ | R only; B always in AW order | ✗ in order | random shuffle at ≥3 pending; reads serialised |
| Zero-cycle B/R responses | ✓ | ✓ | ✓ | ✗ | ✗ ready only after valid |
| Timing policies per channel | ✓ | ✓ | uniform waits only | random ready only | 0–3 waits after valid |
| Unaligned, narrow, sparse/zero strobes | ✓ | ✗ strobes not tied to byte lanes | ✓ | ✗ full width, all strobes | ✗ strobes never sparse or zero |
| WRAP and FIXED | ✓ | ✗ (open issue #10 since 2019) | ✓ (WRAP start not size-aligned) | ✗ INCR only | ✓ |
| Exclusive access | ✓ | ✗ no AxLOCK | ✓ (length off by one) | ✗ | ✗ |
| Outstanding limit and back-pressure | ✓ | ✗ | ✓ | n/a | ✗ |
| Transaction-rebuilding monitor | ✓ | ✓ | ✗ beat mailboxes | ✗ | ✗ beats only |
| UVM sequence items | ✓ | ✓ (own tue framework) | ✗ not UVM | ✗ not UVM | ✓ but subordinate not reactive |
| Protocol checks | ✓ 18 rules + `Axi4PC` | ✗ one warning | ✓ but compiled out on Verilator | ~16 basic assertions | 15 basic per side |
| Functional coverage | ✓ | ✗ | ✗ | ✗ | basic; 0% on Verilator |
| VCS | ✓ | ✓ unmodified | ✓ unmodified | not built | ✓ after 3 patches |
| Verilator 5.052, per run | 3–4 s | 650–720 s after 3 library patches | 285–1486 s | not built | under 6 s after about 6 more patches; B count mismatch in INCR tests |
| Licence | Apache-2.0 | Apache-2.0 | Solderpad 0.51 | MIT | MIT |
| Maintenance | ours | one maintainer; last code change June 2024; Verilator not supported | active | one author, 2026 | 2–3 engineers in bursts; low response; Verilator (#30) open since 2023 |

### tvip-axi (taichi-ishitani/tvip-axi)

A clean UVM AXI VIP on the author's `tue` framework. It ran unmodified on VCS
at our widths, reached 32 outstanding each way, and completed responses out of
order with one-cycle minimum latency. Its gaps are real ones for us:

- no exclusive access;
- INCR only;
- strobes not tied to the active byte lanes, which matters for narrow and
  unaligned writes;
- no outstanding limit;
- no protocol checks and no coverage.

Verilator needs three patches to the library, and each run takes 650–720 s
because z3 solves every item. We estimated 3–5 engineer-weeks to close the
gaps, plus taking ownership of `tue`.

The issue history is mostly reset-cleanup bugs, all fixed, and the maintainer
responds within days. The maintainer declines Verilator support, and declines to
treat X on valid/ready as invalid ("use SVA").

### pulp-platform/axi (v0.39.11)

Widely used SystemVerilog, but not shaped for UVM: there are no sequence items,
all configuration is compile-time, and the monitor publishes beats rather than
transactions. Correctness issues:

- the subordinate always returns B in AW order;
- WRAP start addresses aren't size-aligned;
- exclusive length is off by one;
- the AR 4 KB assertion checks `aw_burst` (`axi_intf.sv:258`).

Its scoreboard only warns. On Verilator it needs z3, treats X as "don't care"
(false mismatches in two-state simulation), compiles its assertions out, and
runs about 160 times slower than VCS. Useful as a reference: the address
helpers, the assertion list and `axi_sim_mem`.

### verilaxi (nelsoncsc/verilaxi)

An RTL library (AXI DMA and video blocks) with small testbench helpers, not
verification IP. The master runs one transaction at a time with fixed
attributes. It also drives with blocking assignments, and doesn't wait for
`bvalid` before releasing `bready`. The slave is in order with no response
latency control.

### mirafra axi4_avip (mbits-mirafra/axi4_avip)

UVM with a nominal HDL/HVL split, MIT licence, Questa-only flow upstream.
Evaluated at commit `86b46171` (2026-07-08). The split isn't real: the BFMs
import UVM, so they can't run on an emulator. Each transaction carries 257 data
beats and is copied for each channel. A `config_db` wildcard allows one agent of
each kind per testbench.

Gaps against our requirements:

- ID is fixed at 4 bits, and address and data widths are package globals, so
  one build can't mix 256- and 1024-bit ports;
- the master ties W to its own AW and matches B and R in issue order, not by ID;
- the slave needs a sequence item for every transaction (issue #115), so it
  isn't reactive;
- the slave's out-of-order mode is a random shuffle once three or more are
  pending, and it serialises reads;
- RVALID drops between beats, and ready is never raised before valid, so there
  are no zero-cycle responses and no long stalls;
- no exclusive access, and the AW capture drops lock, cache and prot;
- stimulus has no 4 KB rule and WSTRB is never sparse or zero;
- the monitor publishes beats, not transactions, and samples B a cycle late;
- the scoreboard passed a run with about 208k bytes read from unwritten
  addresses;
- 15 basic assertions per side and basic coverage.

Its outstanding sequences hang on both simulators because the base sequence
reads the transaction ID inside the forked block, too late. That bug also
affects the upstream outstanding tests.

It needed 3 patches for VCS with uvm-core 2020, and about 6 more for Verilator
5.052 (`defparam` on arrays, `process::await()`, port types). Our widths touched
13 files. After that, simple 512-bit INCR and WRAP tests passed on VCS in
2–6 s. On Verilator they ran in under 6 s, but the INCR tests ended with a B
count mismatch, and coverage was 0% because Verilator ignores the covergroups.
Verilator support (issue #30) has been open since 2023. Of 102 issues, 43 are
open, and maintainer response is low.

Bringing it up to our needs means rewriting the drivers, monitors and items,
which we estimated at 6–8 engineer-weeks, against 4–6 for our own agents.
Worth keeping as reference only: the strobe calculation and the assertion list.

### amiq_axi_lite_uvc (amiq-consulting/amiq_axi_lite_uvc)

Not evaluated in depth: it covers AXI4-Lite and AXI5-Lite only (no bursts,
AxLEN/AxSIZE or exclusive access), and the AoU DUT has no AXI-Lite port. It is
Apache-2.0 and maintained (last change March 2026). Its design is a useful
reference for our agents: separate ready drivers, out-of-order and
outstanding-limit settings, AW/W ordering settings, and its checks and coverage
lists.

## APB

| Candidate | Result |
|---|---|
| amiq_apb (Apache-2.0, last update 2021) | Worked on both simulators after 3 small patches: uvm-core 2020 removed `uvm_test_done`, the driver never returned PRDATA to the item, and Verilator rejects parts of its covergroups. Its style conflicts with our rules (`#delay` driving, no clocking blocks, a monitor that publishes each transfer twice), and adopting it cost as much as writing our own. We wrote a minimal APB3 agent and adapted its 30 interface assertions with attribution. |
| UVM-1.2 `integrated/apb` example | APB2 only (no PREADY or PSLVERR), so unusable here. |

## Arm AXI4 protocol assertions (`Axi4PC`, BP063)

Free from Arm (https://developer.arm.com/downloads/view/BP063), licensed for
checking compatibility of one's own products. It may not be sublicensed or
redistributed, so it is never committed: users unpack it into the git-ignored
`.deps/BP063/` (`make setup AXI4PC_TGZ=<tarball>`). It works on VCS.

On Verilator 5.052 it crashed at AoU widths until we found a Verilator
code-generation bug. The DFG peephole pass turns a guarded array read into an
unconditional out-of-bounds read. Building with `-fno-dfg-peephole` (now the
default in our Makefile) fixes it, and we have a 20-line reproducer, with no
Arm code, ready for an upstream report.
