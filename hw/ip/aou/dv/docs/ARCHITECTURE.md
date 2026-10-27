<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Testbench architecture and stream contracts

Living document. It fixes the names and connections that independent work streams
build against, so their pieces integrate without rework. Change it only through
the integrator.

## Topology

One DUT (`AOU_TOP`) against layered models. Top module: `tb_top`.

```
 local side                         DUT                        remote die (models)
 L4b AXI manager  --S port-->  +-----------+  --FDI TX-->  L1 monitor --> L3 unpacker --> L4a (remote AXI)
 L4b AXI subordinate <-M port- |  AOU_TOP  |  <--FDI RX--  L1 driver  <-- L3 packer   <-- L4a (remote AXI)
 APB agent ------------------> |           |  <-bringup->  L2 PL link-state agent
                               +-----------+
```

The remote die is entirely models: L1/L2 present a UCIe adapter at FDI, and
L3/L4a play the remote AoU protocol layer and its AXI side. T1 replaced PR 80's
`aou_tb_top` bench, which has been retired (DECISIONS.md D0).

## Directory ownership

| Directory | Stream | Contents |
|---|---|---|
| `uvm/env/axi/` | A | `aou_axi_bus_if.sv`; `aou_axi_pkg.sv` and its class files: transaction (`aou_axi_txn`), config, manager and subordinate agents, monitor, memory (`aou_mem`), timing policies, sequences |
| `uvm/env/` | A (scoreboard), integrator (env) | `aou_env_pkg.sv`: `aou_scoreboard`, `aou_env_cfg`, `aou_env`; `aou_t1_env_pkg.sv`: the T1 env, its cfgs, checkers (`chk/`, `perf/`) and `aou_base_test_seq` |
| `uvm/env/fdi/` | B | `aou_fdi_mb_if.sv`, `aou_fdi_lsm_if.sv`; `aou_fdi_pkg.sv` (L1: flit item, Format 6 codec, PL driver and TX responder, monitor); `aou_lsm_pkg.sv` (L2: PL link-state agent, bringup reference model) |
| `uvm/env/l3/` | C | `aou_l3_pkg.sv`: message classes, flit objects, packer with policies, unpacker, credit manager, link controller, remote-die agent glue; `AOU_FDI_CHECKER` integration |
| `uvm/env/apb/` | D | `aou_apb_if.sv`, `aou_apb_pkg.sv` (agent, reg adapter, predictor), register sequences |
| `uvm/seq_lib/` | integrator | `aou_seq_lib_pkg.sv`: every virtual sequence, by area |
| `uvm/tests/` | integrator | `aou_tests.sv` (base test, tests, by area; compiled in `tb_top.sv` under `UVM`); `reg/`, `fdi/`, `l3_unit/`, `axi_selftest/` the other benches' tests |
| `tb/` | integrator | `tb_top.sv` and the other tops, the status/irq/reset interfaces |
| `testlists/` | integrator | the testlists (scenarios and groups) and `plan_ids.yaml` |

Each bench's sim config (`aou_sim_cfg.toml` for T1, `aou_reg_sim_cfg.toml`,
`aou_l3_unit_sim_cfg.toml`, `aou_axi_selftest_sim_cfg.toml`) lists its include
directories and sources in dependency order; T1's is ocah_lib, ral, rules, fc,
axi, fdi, checker, l3, apb, the top's interfaces, env, t1_env, seq_lib, the FDI
tests, `tb/tb_top.sv`. A stream that adds a source file adds it there. The
standalone Makefile reads the configs through `scripts/sim_cfg.py` and puts the
RTL (`RTL/filelist.f`) and uvm-core in front; the tt-oca-harness runner reads
them directly when this repository is vendored.

Layers depend only downward: L4a uses L3's message API; L3 uses L1's flit API;
L1/L2 know nothing above them.

## Build configuration

Compile-time parameters come from `CONFIG` (default `1x512-sp64`). The table of
all configurations and the naming legend are in README "Build configurations"
(`make configs` prints them):

| CONFIG | RP_COUNT | RP0..RP3 data width | FDI_CONFIG | Covers |
|---|---|---|---|---|
| 1x512-sp64 | 1 | 512 | SP_64B | the default single-RP build |
| 4x512-sp64 | 4 | 512 | SP_64B | multi-RP (2.12) at one width |
| 3x512-sp64 | 3 | 512 | SP_64B | an RP count that is not a power of two |
| 4xmix4211-sp128 | 4 | 1024, 512, 256, 256 | SP_128B | mixed widths, every local width (2.14), 1024-bit FDI |
| 4xmix2144-sp64 | 4 | 512, 256, 1024, 1024 | SP_64B | mixed widths, RP2/RP3 at 1024; with 4xmix4211, every RP at every local width |
| 1x256-sp32 | 1 | 256 | SP_32B | narrowest RP and FDI (the RTL defaults' FDI) |
| 2xmix-tp64_128 | 2 | 512, 1024 | TP_64B_128B (TWO_PHY) | two-PHY FDI, 2 RPs, mixed widths |
| 2x512-tp32_64 | 2 | 512 | TP_32B_64B (TWO_PHY) | two-PHY FDI with a 256-bit PHY0, 2 RPs at one width |
| 1x512-sp64-nxt | 1 | 512 | SP_64B | TX_NXT_PACKING_EN 1 (registered TX packer output stage) |
| 2xmix-sp64-rxf | 2 | 1024, 256 | SP_64B | non-default RX FIFO depths, RX FIFO register slices off |

The configurations are a pairwise set rather than a cross product: every pair
of RP count (1, 2, 3, 4), local width (256, 512, 1024, mixed) and FDI width
(256, 512, 1024, both two-PHY pairs) that matters appears in some build, and
every RP is built at every local width. The remote die's width is a
run-time choice (`+remote_bytes=N` or `N0,N1,..` per RP), so one build covers
every upsize, downsize and bypass pairing. The remote model converts like a
real die of that width (`aou_t1_l4a_adapter`). A writer may raise the WriteReq
size above AWSIZE, and WriteData may use any DLENGTH of at least max(the
WriteReq size, 256 bits), so DLENGTH is self-describing. By default the model
packs at AWSIZE, the minimal legal choice; `+remote_wreq=upsize` sends WriteReqs
of its bus size, and `dut_like` keeps AWSIZE with WriteData at its bus width,
as this DUT does. It maps a
received request that fits its bus onto one AXI transaction, downsizes a wider
one, splits bursts past `+remote_max_burst` (default 256 beats) like the DUT's
splitter (MAS 3.6), and packs ReadData at the requester's ARSIZE (AoU 5.7).
Unused RPs repeat RP0's width,
because the DUT sizes the AXI data ports to the widest of all four parameters;
a narrower RP uses the low bits of its slot. In two-PHY builds the remote die
uses one PHY (`+active_phy=P`, random per seed by default) and AOU_FDI_CHECKER is
not instantiated.

## Interfaces and config_db names

`tb_top` registers every interface in `uvm_config_db` under scope `"*"`:

| Key | Type | Used by |
|---|---|---|
| `s_axi<r>` | `aou_axi_bus_if #(.DATA_W(1024))` | L4b manager agent (DUT's AXI S port) |
| `m_axi<r>` | `aou_axi_bus_if #(.DATA_W(1024))` | L4b subordinate agent (DUT's AXI M port) |
| `fdi_mb<p>` | `aou_fdi_mb_if #(.DATA_W(1024))` | L1 agent, PHY *p* |
| `fdi_lsm` | `aou_fdi_lsm_if` | L2 agent |
| `apb` | `aou_apb_if` | APB agent |
| `status` | `aou_status_if` | interrupts, FSM state, SW pins |
| `irq` | `aou_irq_if` | the same interrupts and activation status, clocked (T1 status watcher) |
| `rst` | `aou_rst_if` | T1 reset agent: mid-test I_RESETN/I_PRESETN (ANDed with the top's power-on reset) |
| `wdt` | `aou_wdt_if` | write-watchdog checker: per-RP AW/B handshakes at the early-response controller, the SFR's watchdog fields and its APB port (white-box taps) |
| `fdi_chk` | `aou_fdi_checker_if` | AOU_FDI_CHECKER status ports (`aou_fdi_chk_adapter`) |

One parameterization per interface type (widest width, with the real width in
the agent config) means one Verilator vif type. Drivers use only their own
clocking block; monitors use only `mon_cb`.

### T1 env: where the implementation departs from the test layer API

The names below differ from the "Test layer API" section because the API names
are SystemVerilog keywords or because a PR 80 interface has no clock. Everything
else keeps the API's names.

| API name | Implemented as | Why |
|---|---|---|
| `env.expect` | `env.expects` | `expect` is a keyword |
| `program(feature_cfg)` | `program_cfg(aou_t1_feature_cfg)` | `program` is a keyword |
| `deactivate(who, force)` | `deactivate(who, forced)` | `force` is a keyword |
| reset agent on `aou_reset_if` | `aou_t1_reset_agent` on `aou_rst_if` (key `rst`) | PR 80's `aou_reset_if` (since retired) had no clock, so no clocking block |
| `regs.model` | `aou_t1_reg_env` (extends `aou_reg_env`) adds `model` | `aou_reg_env` calls it `regmodel` |

Per-RP remote widths: `cfg.rp_remote_bytes[r]` (0: `cfg.remote_bytes`), read
through `cfg.remote_bytes_of(r)`. Traffic profiles carry `rp_mask` (default all
RPs): `traffic()` runs only on the RPs it selects.

Additions: `env.rmgr` (remote managers: one `aou_axi_sequencer` per RP whose
transactions go out through L3, `vseqr.r_mgr_sqr[r]`), `env.sw_isr` (the local
software of MAS 7.3.5: answers INT_ACTIVATE_START/INT_DEACTIVATE_START through the
registers; `cfg.sw_isr_en`), `env.l4a` (the `aou_l4a_if_c` adapter over `remote`),
`env.attr_chk` (`aou_t1_attr_chk`: attributes, exclusive responses and FLEX across the
link; `cfg.attr_chk_en`), `env.xfer_cov` (`aou_t1_xfer_cov`: their functional coverage),
`env.rx_fifo_chk` (`aou_t1_rx_fifo_chk`, passive: credit and activation against what
the DUT's RX FIFOs still hold, and the DEACTIVATE_TIME_OUT_VALUE quiet window;
`cfg.rx_fifo_chk_en`, `cfg.rx_fifo_slack`), `cfg.remote_rp_count` (the remote die's RP
count, `+remote_rp_count`), `env.outstanding(why)`, and in the base vseq `inject_mem_error()`, `wait_link()`,
`wait_l3()`, `write_field()`. Traffic profiles are `aou_t1_traffic_cfg` objects
(`aou_t1_traffic_cfg::named("rand"|"unaligned"|"b_zero"|"long"|"short"|"narrow"|"stall")`).
`scoreboard.remote_imp` gets the remote managers' completed transactions (L4a
originated, as this document defines it), not the remote model's responses.

Reset contract as implemented: `env.reset_flush(which, bus_reset)`. I_PRESETN alone
only cancels the software ISR (the core and link keep running). I_RESETN and
AOU_SW_RESET (`sw_reset()`; both bus_reset = 1): the local AXI agents are on the
DUT's AXI-port reset (`tb_top.axi_port_rst_n`, the core reset read from the DUT), as
the SoC's AXI peers must be (MAS 7.3.6, integration guide 3.1.1: either reset loses
every AXI transaction in flight or queued in AOU_CORE, and the attached managers and
subordinates are reset with it or recover on their own). AXI managers drop queued
and in-flight items and restart idle once the reset is over, subordinates drop
requests, monitors forget in-flight transactions. `abort_traffic()` (bus_reset = 0,
no reset) only stops waiting: a burst already on the bus is still completed. The
managers' outstanding transactions end with `aou_axi_txn.aborted = 1` (sequences
continue) and `sb.abort()` counts them and marks the bytes an aborted write strobes
unknown: each may hold its old value or the write's until a checked write defines
it again. `sw_reset()` also brackets the request with `env.sw_reset_window()`, from
the APB write that requests AOU_SW_RESET to the core reset: the S-port monitors
mark every transaction on the bus in the window `reset_outstanding`; a write that
completes in it is lost or landed whatever its response (the reset loses writes
queued in the core, early-acknowledged ones included, 7.2.5), so the scoreboard
treats it like an aborted write, and a read that ends with SLVERR counts as aborted
too (MAS 7.3.6 loses the read and defines no response, so the SLVERR is taken from the RTL; any other response is checked as usual, and SLVERR on any
later transaction is still an error). The DUT sends no response for a
transaction the reset lost (its RX FIFOs reset with the core), but the managers
tolerate one: for `stale_window` (10 us) a response on an ID with an aborted
request is taken as the stale one and new requests on that ID wait; later, a stale
count only absorbs a response nothing else matches. The subordinate agents'
monitors use no window (the responder is the bench's own driver, reset with the
port). The remote die (L3
`reset_flush()`: queues, credits, responder; L1 pump and
PL driver: flits built before the reset) always drops everything. `traffic()` and
`wait_traffic()` are bounded by `cfg.drain_timeout` (T1-V08, then `stop_traffic()`).

Reset rule (integration guide 3.1.1): I_RESETN or I_PRESETN is asserted only with the
APB master idle (PSEL low, nothing waiting on PREADY) and the asynchronous APB bridge's
request/done handshake drained in both clock domains (`aou_rst_if.apb_quiet`, read from
the bridge's state), both clocks running; at power-on both resets are held while both
clocks run, and the APB and AXI drivers wait for their reset to release. The reset
agent's `do_reset()` calls `quiesce_apb()` first: `aou_apb_cfg.hold` stops the APB driver
starting new transfers, and the agent waits for PSEL low and the bridge idle for four
PCLK cycles. Master-visible completion of a write is not enough. A checker in the agent
reports any reset asserted otherwise. A test that resets mid-access on purpose passes
`quiesce = 0`, says so in its header and does not claim the rule.

## Inter-layer APIs

- **L1 ↔ L3:** `aou_flit_item` holds 256 bytes, the PHY, cancel and stall plans
  for driving, and timestamps. The L1 driver takes flits from a sequencer. The L1
  monitor publishes `ap_tx` (flits the DUT sent, after cancel rollback) and `ap_rx`
  (flits delivered to the DUT).
- **L2:** `aou_lsm_cfg` holds the latency ranges; states are encoded as in UCIe
  r1.1 Table 8-2. The agent publishes state changes, and L1 only drives while L2
  reports Active.
- **L3 ↔ L4a:** L3 publishes decoded messages from the DUT (`aou_msg` subclasses)
  and accepts messages to send through `aou_l3_agent.send(aou_msg)`. Credits,
  packing and activation are L3's job. L4a's remote AXI model turns the DUT's
  WriteReq/WriteData/ReadReq into memory operations on the remote `aou_mem` and
  returns WriteResp/ReadData through L3, with configurable latency.
- **L4a ↔ scoreboard:** only `aou_axi_txn`.

### L3 ↔ L4a: remote AXI model API (stream A)

`aou_remote_axi_model` (`aou_axi_pkg`, a `uvm_component`) is the remote die's AXI
subordinate. L3 must not import L4, so the glue that turns decoded
WriteReq/WriteData/ReadReq messages into calls belongs to a class above L3 (the
remote-die agent glue in env).

- **Config:** `cfg` is an `aou_axi_cfg`, set directly or from `uvm_config_db` key
  `"cfg"`. It uses `mem` (the remote `aou_mem`, created if null), `timing.b_lat`
  and `timing.r_lat` (latency in cycles), `exclusive_en`, and `vif`/`vif_key`. Any
  `aou_axi_bus_if` on the same clock will do, because only `mon_cb` is used, to
  count cycles; a vif is needed only for nonzero latency.
- **Call:** `task execute(aou_axi_txn req, output aou_axi_txn rsp)`.
  - `req` holds the request fields (`dir`, `id`, `addr`, `len`, `size`, `burst`,
    `lock`, `cache`, `prot`, `qos`) and `data_bytes`, the width the data is laid
    out in. A write also carries `data[]` and `strb[]`, one entry per beat in
    bus-aligned lanes.
  - `rsp` is a copy with `local_side = 0` and `t_done` set. A write gets `bresp`;
    a read gets `data[]` and `rresp[]` for every beat. Both follow `aou_mem`'s
    error-region and exclusive rules.
  - Fork one call per request. Responses come back out of order across IDs and
    in call order within an ID, with reads and writes ordered independently. A
    write lands on the memory, and is judged by the exclusive monitor, when the
    call is made (arrival order, as at a subordinate that has accepted AW and
    W); only its B waits. A read's data is taken when the call returns.
- **Publishing:** the model writes every response to its `ap`.

`aou_scoreboard` (`aou_env_pkg`) has three analysis imps:

- `local_mgr_imp`: local manager monitors at the DUT's S ports.
- `remote_imp`: transactions **L4a originated** towards the DUT, published once
  they complete, with responses and `local_side = 0`. Not the model's
  `execute()` responses.
- `local_sub_imp`: local subordinate monitors at the M ports. Only counted.

Set `sb.remote_mem` to the model's `cfg.mem`, and `sb.local_mem` to the one
`aou_mem` that all local subordinate agents share.

### L1 ↔ L3 boundary and the L3 API (stream C)

L3 (`l3/aou_l3_pkg`) does not import `aou_fdi_pkg`. Its only flit type is
`aou_l3_flit_item`: `bit [7:0] bytes[256]` in wire byte order (byte *i* is the
*i*-th byte of the 256-byte Format 6 flit, beat *k* of a 64-byte FDI carries bytes
64k..64k+63), plus `phy` and `t_start`. L3 fills every byte; bytes 0-1 (flit
header, default PID 11b from `cfg.fh_byte0`) and 126-127/254-255 (CRC) are the
adapter's and L1 may overwrite them.

What L1 must provide, and how the integrator connects it (env glue, a byte copy
each way: `l3_item.bytes = l1_item.data` and back; L1's `aou_flit_item.data[256]`
uses the same byte order):

- **DUT → L3:** every flit the DUT sent, after cancel rollback, exactly once and
  in order: L1 `ap_tx` → converter → `aou_l3_agent.rx_flit_imp`
  (`uvm_analysis_imp #(aou_l3_flit_item)`, a function, zero time).
- **L3 → DUT:** L1's driver side pulls: a sequence on the L1 sequencer loops
  `l3.tx_flit_export.get(it)` (`uvm_blocking_get_imp`, blocks until L3 has a flit),
  copies `it.bytes` into an `aou_flit_item` and drives it. L3 builds a flit only
  when asked, so the credits it returns are current; it never needs idle flits.
  L1 drives only while L2 reports Active.

L3 API (`aou_l3_agent`, `aou_l3_cfg` set directly or via `uvm_config_db` key `"cfg"`):

| Item | Meaning |
|---|---|
| `send(aou_msg)` | Queue a message (`aou_msg_wreq/rreq/wdata/rdata/wresp/act/crdtgrant/raw`). `msg.rp` is the wire RP (the DUT's plane). Credits, packing and activation are L3's. |
| `activate()`, `deactivate()`, `wait_state(s)` | Link control tasks; states `AOU_LS_DISABLED/ACTIVATE/ENABLED/DEACTIVATE/ERROR`. By default L3 answers the DUT's ActivateReq/DeactivateReq itself. |
| `ap_rx_msg`, `ap_tx_msg` | Decoded DUT messages (every type) / messages L3 put into a flit. |
| `ap_tx_flit` | Flits handed to L1. |
| `sqr` (`aou_l3_sequencer`) | Message sequencer; `p_sequencer.model` reaches the model for non-message injections. |
| `cfg.l4a` (`aou_l4a_if_c`) | Responder callback: `task handle_write(aou_msg_wreq, aou_msg_wdata[$], output bresp)`, `task handle_read(aou_msg_rreq, output bit[1023:0] data[$], output bit[1:0] resp[$])`. L3 groups AWLEN+1 WriteData per WriteReq (per RP, in order), sets RP/RID/RLAST/DLENGTH (from ARSIZE) on ReadData, and sends WriteResp/ReadData through the packer. Dequeue to L4a frees the RX credits. `cfg.resp_fork` runs requests concurrently (ordered within an ID). With no `l4a`, DUT requests are consumed without a response. An env adapter implements this over `aou_remote_axi_model.execute()`. |
| `cfg.spec_rev`, `rp_count`, `fdid`, `dest_rp[]` | v0.7 (default) or v0.8; RP count; FDId; DEST_RP map for responses. |
| `cfg.rx_depth[]`, `ret_policy[]`, `ret_delay`, `tx_cred_max` | Modelled RX buffer per class (= credits advertised), return policy (immediate, on consume, delayed, withheld), TX saturation. |
| `cfg.pol` (`aou_packer_policy`) | Layout: `set_dut_like/sparse/min_density/max_density/random`, `start_granule`, `split_at`, `hole_pct`, `max_msgs_per_flit`, `allow_span`, `random_order`, `cred_method`, `misc_per_half_max` (v0.8 4.4: at most 2; an Activation always travels alone), `hold_credited`, `prof_pct` (random PROF in AXI messages), `zero_grants` (extra zero-credit CrdtGrants). |
| `cfg.chk` (`aou_l3_rule_chk`) | Rule reporting: findings are `uvm_error` "AOU-R*n*: ..." unless `expect_rule()` declared them; `count(rule, src)`. |

Error injection: `aou_msg.ignore_credits / ignore_state / flip_mask / len_adj / raw_g`,
and the sequences in `l3/seq/` (`aou_l3_bad_type_seq`, `aou_l3_rsvd_seq`,
`aou_l3_no_credit_seq`, `aou_l3_act_inject_seq`, `aou_l3_flit_inject_seq`,
`aou_l3_overgrant_seq`).

AOU_FDI_CHECKER (`checker/`, copied from bdf498c) is instantiated by the top on
the DUT's FDI (LP = DUT TX qualified by valid&irdy&trdy, PL = flits to the DUT,
`FDI_IF_BYTES` = FDI width, `RP_COUNT`, `I_CFG_RP_DEST_RP` = DEST_RP); its
reporting ports go to an `aou_fdi_checker_if` registered as `"fdi_chk"`, which
`aou_fdi_chk_adapter` turns into AOU-R* reports.

## The transaction contract

`aou_axi_txn` (in `axi/`, VIP-neutral) is the only AXI type the scoreboard,
sequences and tests see.

```
typedef enum bit {AOU_AXI_WR, AOU_AXI_RD} aou_axi_dir_e;
class aou_axi_txn extends uvm_sequence_item;
  aou_axi_dir_e dir;
  int unsigned  rp;
  bit           local_side;          // 1: DUT's AXI ports; 0: remote die (L4a)
  bit [9:0]     id;
  bit [63:0]    addr;
  bit [7:0]     len;                 // beats - 1
  bit [2:0]     size;                // log2(bytes per beat)
  bit [1:0]     burst;
  bit           lock;
  bit [3:0]     cache, qos;
  bit [2:0]     prot;
  int unsigned  data_bytes;          // bus width in bytes
  bit [1023:0]  data[];              // one entry per beat, bus-aligned lanes
  bit [127:0]   strb[];              // per W beat
  bit [1:0]     rresp[];             // per R beat
  bit [1:0]     bresp;
  time          t_addr, t_done;
  // helpers: beat_addr(i), active lanes for beat i, bytes() as address -> byte
endclass
```

Monitors and L4a publish a transaction on `analysis_port #(aou_axi_txn)` when it
completes: a write after B, a read after its last data beat.

## Scoreboard rule

Checks bytes, as AXI4 defines them, so it is unaffected by splitting,
aggregation and width conversion inside the DUT:

- **Memories.** The local subordinate agents and the remote L4a model each answer
  from an `aou_mem` (sparse, random initial contents, seeded). The scoreboard keeps
  a golden copy of each.
- **Local to remote.** A write entering the DUT's S port must change the remote
  memory at exactly the bytes AXI4 addressing and WSTRB select; when its B returns
  OKAY, those bytes must match golden. Read data returned at the S port must equal
  golden remote memory, beat by beat and lane by lane.
- **Remote to local.** The same, for traffic L4a originates through L3 towards
  the DUT's M port and local memory.
- **Responses and order.** Every request gets exactly one response with its own ID,
  in order within an ID. Error responses injected by a memory propagate unchanged.
  The one exception is the reset rule in the reset contract above.
- **Attributes.** prot, qos, cache, lock and id are checked end to end when no
  feature splits or merges the transaction.
- **Isolation.** Stimulus keeps in-flight transactions to disjoint addresses unless
  a test asks otherwise, so the golden model is unambiguous.
- **Drain.** Nothing outstanding at end of test.

## Test layer API

Tests never reach into agents. A test picks a configuration and a virtual
sequence; virtual sequences use only the handles and helper tasks below. Changing
this API goes through the integrator, because every ported test depends on it.

### Environment (`aou_t1_env`, in `env/`)

| Handle | Type |
|---|---|
| `cfg` | `aou_t1_env_cfg`: RP count and per-RP data bytes, `spec_rev`, L1/L2/L3/AXI agent configs, timing profiles, check enables |
| `s_mgr[r]`, `m_sub[r]` | `aou_axi_mgr_agent` on the DUT's S port, `aou_axi_sub_agent` on its M port, per RP |
| `fdi[p]`, `lsm` | L1 agent per PHY, L2 link-state agent |
| `l3`, `remote` | `aou_l3_agent` (remote die protocol layer), `aou_remote_axi_model` (remote AXI side, behind the L4a adapter) |
| `apb`, `regs` | APB agent, `aou_reg_env` (`regs.model` is the register block) |
| `rst` | reset agent driving `I_RESETN`/`I_PRESETN` through `aou_rst_if` (config_db key `rst`) |
| `sb`, `status`, `fdi_chk`, `expect` | scoreboard, interrupt/status watcher, FDI checker adapter, expectation registry |
| `dbg_chk` | `aou_t1_dbg_fifo_chk`: predicts each RP's response error debug FIFO and checks every debug-window read and pop |
| `crd_rr`, `early_tbl` | `aou_t1_crd_rr_chk`: round-robin MsgCredit order in a window a test opens (T1-C03); `aou_t1_early_tbl_chk`: early-table backpressure on RPs with EARLY_BRESP_EN (FEAT-R15/R16) |
| `wdt_chk` | `aou_t1_wdt_chk`: the write-transaction watchdog of every RP, from a model of its count (FEAT-R23 to R28) |
| `crd_chk` | `aou_t1_crd_flow_chk`: an RP with credit and queued work is not held back by another RP without credit (T1-C01), the DUT uses the credit it holds (T1-C02), and no RP with credit that is next in a class's order waits too long for its message (T1-C43) |
| `vseqr` | `aou_t1_vseqr`: sequencer handles for all of the above, plus `env` |

### Base virtual sequence (`aou_base_test_seq`)

Every test's virtual sequence extends this and composes these tasks:

| Task | Meaning |
|---|---|
| `link_up()` | L2 bringup to Active |
| `activate(who, order)` | AoU activation: DUT-, remote- or both-initiated (APB `activate_start`, SW pin, or L3), with ordering and timing randomization |
| `deactivate(who, force)` | orderly or forced deactivation from either side; waits for DISABLED |
| `program(feature_cfg)` | DUT configuration through the register sequences (split, aggregator, early response, QoS, DEST_RP, LP mode, interrupt masks, error info, time-outs) |
| `traffic(dir, n, profile)` / `traffic_nb(...)` + `wait_traffic()` | local→remote, remote→local or both; a profile names AXI sequence knobs and timing policies |
| `pause_traffic()` / `resume_traffic()` | quiesce or resume all traffic sources |
| `drain(timeout)` | wait until nothing is outstanding anywhere |
| `link_event(kind)` | PL-initiated Retrain, LinkError, L1 entry/exit, Reset, inband_pres drop, clk_req wake |
| `lp_mode(en, threshold)` | TX low-power mode; static configuration, only while the DUT is DISABLED (T1-LP03) |
| `hold_tx()` / `release_tx()` | back-pressure on the DUT's TX: L1 holds pl_trdy low from the next flit boundary (`aou_fdi_cfg.tx_hold`), so requests back up behind the DUT's ring buffer and arbiters |
| `hold_remote_tx()` / `release_remote_tx()` | the remote die's counterpart: L3 holds back credited messages (`pol.hold_credited`), then packs the backlog densely |
| `inject(kind, args)` | L3 error injection (bad type, reserved bits, credit violations, out-of-state Activate/Deactivate, MsgStart, placement, over-grant, ...) and AXI error responses from memories |
| `sw_reset()` | `AOU_SW_RESET` (every SFR, the activation state and the RX FIFOs reset, MAS 7.3.6), then reprogram and re-activate |
| `hard_reset(which)` | assert `I_RESETN` and/or `I_PRESETN` mid-test, flush the environment, bring up again |
| `expect_event(id, min, max)` | declare an error, interrupt or rule hit the scenario is supposed to cause |

### Reset contract

Every agent, model, monitor and checker implements `reset_flush()`: drop
in-flight state, clear queues and credits, and re-arm. The env calls it on
every reset the `rst` agent drives. On reset the scoreboard moves outstanding
transactions to an "aborted" count instead of reporting them, and checks
again from the next activation.

### Expectations

The expectation registry (`expect`) is how negative tests stay strict.
`expect_event(id, min, max)` registers a rule ID (`AOU-R16`, `FDI-R12`,
`AXI-R05`, ...), an interrupt (`INT_REQ_LINKRESET`, ...) or a scoreboard
check. A report catcher demotes matching errors to info and counts them. At
end of test, each expectation's count must be within `[min, max]`, and any
error that was not expected fails the test as usual. Checkers never need to
know which test is running.

### Tests

A test (`uvm/tests/`) is thin. It sets `aou_t1_env_cfg` (or factory overrides),
names its virtual sequence, and has its plan items listed in `testlists/plan_ids.yaml`. The
base test (`aou_base_test`, on the OCAH library's `ocah_test`) builds the env,
runs the virtual sequence through `start_seq()`, and performs the end-of-test
checks: scoreboard drained, expectations met, no unexpected interrupts, FDI
checker clean. `aou_sanity_test` is the bring-up gate: one pass of
`aou_sanity_test_seq` through `run_single_scenario()`; it is also the default
`make run` test.
