<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# UCIe FDI model

A SystemVerilog UVM model of the **Adapter side of the UCIe Flit-Aware Die-to-Die
Interface (FDI)**, for verifying a Protocol Layer. It drives and checks the FDI
mainband in Latency-Optimized 256B Flit Format 6 and the FDI link state
(pl_state_sts, the clock, wake and rx_active handshakes, stall, Adapter-initiated
link events), with an always-on rule check on both sides of the interface. It
depends on UVM and nothing else: no protocol above the FDI, no design, no
bench library.

## Summary and road-map

**What this is.** The FDI half of the AoU bench (`hw/ip/aou/dv`), pulled into a
directory of its own inside it, `vip/ucie_fdi` ("Moving it out of the AoU bench"
says why there). The AoU bench now uses it through the API below, the same way
any other protocol layer would: its AoU-specific parts (the DUT's bringup pins, the
reference model of the DUT's bringup controller, the bench's coverage collectors and
rule ledger) are a layer on top, `hw/ip/aou/dv/uvm/env/fdi/aou_fdi_layer_pkg.sv`.

**Where it stands.** Self-contained and self-tested: `dv/` runs the model
against a loopback Protocol Layer stub on VCS and Verilator. The AoU bench's
regressions run on it unchanged.

**How a layer plugs in.** A layer does not subclass the model or override its types.
It takes three kinds of handle:
- the flits, on the mainband monitor's analysis ports;
- the link state, as an observer: a class that `implements ucie_lsm_observer` and
  registers with the link-state monitor, which calls it every clock;
- coverage, as a collector that `implements ucie_fdi_cov`, set on each mainband
  monitor.

Nothing the model does every clock allocates an object.

| | Item | Depends on |
|---|---|---|
| Done | Mainband agent (Format 6 codec, RX driver with cancels and bubbles, TX responder with `pl_trdy` policies and stalls, monitor with checks) | - |
| Done | Link-state agent (Adapter state machine, handshakes, events: Retrain, L1 entry and exit, LinkError incl. mid-flit, LinkReset, Disabled, aborted bringups) | - |
| Done | Extension API: link-state observers and a mainband coverage collector (interface classes), flit analysis ports; own rule ledger, self-test | - |
| Done | FDI widths of 32, 64, 128 and 256 bytes; at 256 B a flit is one transfer and its cancel covers the whole flit | - |
| Next | Covergroups of the model's own as a `ucie_fdi_cov` collector and a link-state observer (the AoU bench's are an example) | - |
| Next | Protocol-Layer-initiated PM entry (`lp_state_req` = L1/L2), today not modelled | - |
| Deferred | Other flit formats (68B, Standard 256B), RDI, the sideband, `pl_error` | a user who needs them |
| Deferred | A home outside the AoU bench: tt-oca-harness's shared VIP or a repository of its own (see "Moving it out of the AoU bench") | a second consumer |

## Contents

- [What it models](#what-it-models)
- [Layout](#layout)
- [Use model](#use-model)
- [Extension API](#extension-api)
- [API reference](#api-reference)
- [Checks](#checks)
- [Coverage](#coverage)
- [Self-test](#self-test)
- [Known limits](#known-limits)
- [The AoU bench as a consumer](#the-aou-bench-as-a-consumer)
- [Moving it out of the AoU bench](#moving-it-out-of-the-aou-bench)

## What it models

*The Adapter, seen from the Protocol Layer, on one or two FDIs.* The model plays the
UCIe Die-to-Die Adapter; the design under test is the Protocol Layer. Section numbers
are UCIe r1.1's, which the code cites; the same sections are §10.2 and §10.3 in UCIe
r3.0 (r1.1 §8.2.x is r3.0 §10.2.x, §8.3.x is §10.3.x).

| Area | UCIe r1.1 | What the model does |
|---|---|---|
| Flit format | §2.4.4, §3.3.4 (r3.0 §3.3.4) | Latency-Optimized 256B with optional bytes (Format 6): two 128B halves, Flit Header bytes 0-1 and CRC bytes 126-127, 254-255 owned by the Adapter |
| Byte mapping | §8.3.1 | Flit byte k on FDI byte k mod N of transfer floor(k/N), N = 32, 64, 128 or 256 bytes; at 256 the flit is one transfer |
| Data transfer | §8.2.4, Table 8-2 | RX: `pl_valid` with bubbles, `pl_flit_cancel` of either half (idle or with the replay's first beat, repeated), of the whole flit at 256 B (see "Flit width 256 B"); TX: `pl_trdy` by policy |
| Stall | §8.3.2 | `pl_stallreq` / `lp_stallack`, at a flit boundary or mid-flit |
| Clock gating | §8.2.3.1, §8.2.3.2 | `lp_wake_req` / `pl_wake_ack` responder, `pl_clk_req` / `lp_clk_ack` handshakes |
| rx_active | §8.2.7 | `pl_rx_active_req` / `lp_rx_active_sts` on every Active entry and exit; optionally RX flits in Reset once the Receiver is active |
| Bring-up | §8.2.8, §8.3.3.1 | clock handshake, `pl_inband_pres`, the Protocol Layer's NOP->Active request, Active |
| State machine | §8.3.3 | Retrain (§8.3.3.4), L1 entry and remote exit (§8.2.9), LinkReset (§8.3.3.5), Disabled (§8.3.3.6), LinkError incl. mid-flit and on `lp_linkerror` (§8.3.3.7), the restart after a link-down (§8.3.3.8) |

## Layout

The layout is tt-oca-harness's for shared verification IP
(`hw/common/dv/vip/<name>/`, `ocah_axi_vip` for example): the interfaces, the UVM
packages with their compile list, and the self-test each in a directory of its own.
The model has no assertion modules and no coverage of its own yet, so it has no
`sva/` or `cov/`.

| Path | Contents |
|---|---|
| `interface/ucie_fdi_mb_if.sv` | Mainband interface of one FDI (`ucie_fdi_mb_if #(DATA_W)`) |
| `interface/ucie_fdi_lsm_if.sv` | Link-state handshakes shared by the FDIs (`ucie_fdi_lsm_if`) |
| `uvm/ucie_fdi_pkg.sv`, `uvm/l1/` | L1, the mainband: flit item and codec, agent, PL driver, TX responder, monitor, coverage collector API (`ucie_fdi_cov`), flit sequence, rule ledger |
| `uvm/ucie_lsm_pkg.sv`, `uvm/l2/` | L2, the link state: encodings, agent, driver, monitor, sample (`ucie_lsm_obs_t`), observer API (`ucie_lsm_observer`), event item and sequences |
| `uvm/ucie_fdi_macros.svh` | `UCIE_RANDOMIZE_WITH` |
| `uvm/sources.toml`, `uvm/ucie_fdi.f` | Compile list: a tt-oca-harness source list (repository-root paths) and a `-f` file (`${UCIE_FDI_HOME}`, this directory) |
| `dv/` | Self-test: Protocol Layer stub, scoreboard, tests, top, Makefile |

## Use model

*Compile the model after UVM, instantiate its interfaces in the top, build one
mainband agent per FDI and one link-state agent that takes them, and put a protocol
layer on top (Extension API).* `dv/` is a complete, small example of every step.

### Compile

Compile UVM, then `uvm/ucie_fdi.f` (with `UCIE_FDI_HOME` set to this directory) or the
sources of `uvm/sources.toml` in order, then the bench. Packages: `ucie_fdi_pkg` (L1) and
`ucie_lsm_pkg` (L2, imports L1).

### Top

```systemverilog
ucie_fdi_mb_if #(.DATA_W(BUS_W)) fdi_mb0 (.clk(clk), .rst_n(rst_n));   // one per FDI
ucie_fdi_lsm_if                   fdi_lsm (.clk(clk), .rst_n(rst_n));
// The Receiver is Active when both rx_active signals are 1 (§8.2.7).
assign fdi_mb0.rx_active = fdi_lsm.pl_rx_active_req && fdi_lsm.lp_rx_active_sts;
initial begin
  uvm_config_db #(virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)))::set(null, "*", "fdi_mb0", fdi_mb0);
  uvm_config_db #(virtual ucie_fdi_lsm_if)::set(null, "*", "fdi_lsm", fdi_lsm);
end
```

The mainband interface is always `BUS_W` (2048) bits wide, so every FDI has the same
virtual-interface type; connect the low `8 * beat_bytes` bits to the design. Take the
width from `ucie_fdi_pkg::BUS_W`, never a literal: it grows with the widest FDI the
model supports (it was 1024 before 256 B FDIs).
The Adapter drives the `pl_*` signals; the design drives the `lp_*` ones
(`lp_linkerror` tied 0 if it has none). Config-db keys: `fdi_mb<p>` per FDI,
`fdi_lsm` once.

### Environment

```systemverilog
// build_phase
fdi_cfg = ucie_fdi_cfg::type_id::create("fdi_cfg");
fdi_cfg.phy = 0;
fdi_cfg.beat_bytes = 64;                       // the FDI width: 32, 64, 128 or 256 bytes
fdi = ucie_fdi_agent::type_id::create("fdi0", this);
fdi.cfg = fdi_cfg;
lsm = ucie_lsm_agent::type_id::create("lsm", this);
lsm.cfg = lsm_cfg;
lsm.phy.push_back(fdi);                        // one per FDI: L2 opens, closes and stalls them
```

The link-state agent brings the link up after every reset by itself
(`cfg.auto_bringup`); traffic waits for Active.

### A protocol layer on top

The model carries flits; what is in them is the protocol layer's.

- **Into the design (RX):** start a `ucie_flit_seq` (or your own sequence of
  `ucie_flit_item`) on `fdi.sqr`. Fill `payloads` with the flits to send; the
  sequence adds a cancel plan and gaps per flit. Bytes 0-1, 126-127 and 254-255 are
  the Adapter's: only Byte 0 bits [7:6] (the Protocol ID) are yours, the rest the
  driver clears or randomises (`random_adapter_bytes`).
- **Out of the design (TX):** subscribe to `fdi.mon.ap_tx`; every completed TX flit
  arrives as a new `ucie_flit_item`, which you may keep.
- **What the design received:** `fdi.mon.ap_rx` carries each RX flit as the
  Protocol Layer saw it once cancels were applied, which is what a reference model of
  the design consumes.
- **Link state:** implement `ucie_lsm_observer` and call `lsm.mon.add_observer()`;
  `observe(cur, prev)` runs every clock (Extension API). `lsm.drv.state` and
  `lsm.drv.link_active` are the Adapter's view.
- **Link events:** start `ucie_lsm_event_seq::of(LSM_EV_RETRAIN)` (any `LSM_EV_*`; set
  `ev_to`, `ev_cycles` and the abort fields on it before `start`) or `ucie_lsm_l1_seq`
  (L1 entry, a dwell, the exit) on `lsm.sqr`. An event returns when it is over,
  including the bringup that follows a link-down.
- **Resetting the layers above:** a flit a sequence handed the PL driver before a
  reset of your protocol layer is dropped, not sent, when you bump `fdi_cfg.gate.epoch`.

## Extension API

*A layer implements what the model calls and registers a handle; it never subclasses
the model or overrides its types.* There are three roles, each with the simplest
mechanism that fits it.

| Role | Mechanism | Register | Called |
|---|---|---|---|---|
| Read flits | `uvm_analysis_port #(ucie_flit_item)` `ap_tx`, `ap_rx` on `ucie_fdi_monitor` | `fdi.mon.ap_tx.connect(...)` | at every completed flit |
| Follow the link state | `interface class ucie_lsm_observer`: `observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev)` | `lsm.mon.add_observer(obj)` (any number) | every clock, reset included, after the monitor's own rules |
| Collect mainband coverage | `interface class ucie_fdi_cov`: `sample_xfer`, `sample_cancel`, `sample_stall`, `sample_abandon` | `fdi.mon.cov = obj` (one per monitor; PHYs may share one) | at every flit, RX cancel, stall handshake, abandoned flit; never when null or `cov_en` is 0 |

**Why interface classes for two of them.** An observer or a collector in a UVM bench
already has a base class of its own, a `uvm_component` or a `uvm_object`. An interface
class adds the model's API to it without taking that place. Flits keep UVM's analysis
ports because many unrelated subscribers read them and may keep them.

**What an observer gets.** `ucie_lsm_obs_t` is a struct passed by value: this clock's
link-state signals as the Protocol Layer sees them (`pl_state_sts` of `active_phy`'s
FDI), decoded into `sts` and `req`, and the previous clock's. Nothing is allocated. Signals
of your own design (pins that are not FDI) are yours to sample in the same `observe()`;
the AoU layer does that with its bringup pins.

**Rules for implementers.**
- Declare the implementing methods `virtual`: VCS requires it of an implementation of
  an interface-class method (IEEE 1800-2017 8.26); Verilator accepts either.
- `observe()` is a function: no time passes in it. A layer that drives pins does so
  from its own `run_phase`.
- Register in `connect_phase`, once the agents are built.

**Example: a protocol layer on top.** A minimal layer that decodes the design's TX
flits, drops its partial state when the link leaves Active, and counts mainband
coverage:

```systemverilog
class my_layer extends uvm_component implements ucie_lsm_observer;
  `uvm_component_utils(my_layer)
  uvm_analysis_imp #(ucie_flit_item, my_layer) tx_imp;  // flits the design sent

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_imp = new("tx_imp", this);
  endfunction

  function void write(ucie_flit_item f);
    // decode f.data[2:125], f.data[128:253]: the payload is the protocol layer's
  endfunction

  virtual function void observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev);
    if (prev.sts == LSM_ACTIVE && cur.sts != LSM_ACTIVE) begin
      // the link went down: flush what was in flight
    end
  endfunction
endclass

class my_fdi_cov extends uvm_object implements ucie_fdi_cov;
  `uvm_object_utils(my_fdi_cov)
  function new(string name = "my_fdi_cov");
    super.new(name);
  endfunction
  virtual function void sample_xfer(ucie_fdi_dir_e dir, int unsigned beat_bytes,
                                    int unsigned stall, int unsigned gap); endfunction
  virtual function void sample_cancel(int unsigned half, bit with_valid, int unsigned count,
                                      bit stalled); endfunction
  virtual function void sample_stall(int unsigned lat, int unsigned hold, bit mid,
                                     bit trdy0); endfunction
  virtual function void sample_abandon(bit rx); endfunction
endclass

// In the env's connect_phase:
fdi.mon.ap_tx.connect(layer.tx_imp);
lsm.mon.add_observer(layer);
fdi.mon.cov = cov;   // a my_fdi_cov, created in build_phase
```

The self-test's scoreboard (`dv/ucie_fdi_selftest_env.svh`) and the AoU bench's
`aou_fdi_layer` are complete examples.

## API reference

### Packages and interfaces

| Name | Contents |
|---|---|
| `ucie_fdi_pkg` | `FLIT_BYTES` (256), `HALF_BYTES` (128), `MIN_BEAT_BYTES` (32), `MAX_BEAT_BYTES` (256), `MAX_BEATS_PER_FLIT` (8), `BUS_W` (2048), `FDI_STS_ACTIVE`, `FDI_STS_RESET`; `ucie_fdi_dir_e` (`UCIE_FDI_TX`, `UCIE_FDI_RX`), `ucie_fdi_cancel_e` (`UCIE_CANCEL_NONE/IDLE/VALID`), `ucie_fdi_trdy_e` (`UCIE_TRDY_ALWAYS/RANDOM/BURSTY/HOLES`), `ucie_fdi_beat_t`; codec helpers `valid_beat_bytes`, `beats_per_flit` (1 once a transfer holds a flit), `flits_per_beat` (1 up to 256 B), `flit_chunk_bytes` (a flit's bytes per transfer), `beats_per_half` (the beats of one cancel unit: a half, or the one beat at 256 B), `halves_per_flit` (cancel units per flit: 2, or 1 at 256 B), `is_adapter_byte`, `is_crc_byte` |
| `ucie_lsm_pkg` | `ucie_lsm_state_e` (`LSM_RESET`, `LSM_ACTIVE`, `LSM_L1`, `LSM_RETRAIN`, `LSM_LINKRESET`, `LSM_LINKERROR`, `LSM_DISABLED`, ...), `ucie_lsm_req_e` (`LSM_REQ_*`), `ucie_lsm_ev_e` (`LSM_EV_*`), `ucie_lsm_abort_e` (`LSM_AB_*`); `sts_code`, `sts_decode`, `req_code`, `req_decode` (UCIe r1.1 Table 8-2 encodings) |
| `ucie_fdi_mb_if #(DATA_W)` | `pl_valid`, `pl_data`, `pl_flit_cancel`, `pl_trdy`, `pl_stallreq`, `pl_state_sts`; `lp_valid`, `lp_irdy`, `lp_data`, `lp_stallack`; `rx_active` (driven by the top); clocking blocks `drv_cb`, `lsm_cb`, `mon_cb` |
| `ucie_fdi_lsm_if` | `pl_inband_pres`, `pl_clk_req`, `pl_wake_ack`, `pl_rx_active_req`; `lp_state_req`, `lp_wake_req`, `lp_clk_ack`, `lp_rx_active_sts`, `lp_linkerror`; `drv_cb`, `mon_cb` |

### L1: `ucie_fdi_cfg` (one per FDI)

| Field | Default | Meaning |
|---|---|---|
| `phy` | 0 | FDI index (config-db key `fdi_mb<phy>`) |
| `beat_bytes` | 64 | FDI width: 32, 64, 128 or 256 bytes |
| `is_active` | 1 | 0: monitor only |
| `trdy_policy` | `ALWAYS` | `pl_trdy`: always, `RANDOM` (`trdy_pct`), `BURSTY` (runs of 1..`burst_max`), `HOLES` (only inside a flit, `hole_pct` per beat) |
| `stall_pct`, `stall_mid_pct` | 0, 0 | chance of a stand-alone stall per flit boundary, and the share raised mid-flit (none at 256 B, where every cycle is a flit boundary) |
| `stall_hold_min`, `stall_hold_max` | 1, 8 | cycles `pl_stallreq` stays high after `lp_stallack` |
| `stall_trdy_free` | 0 | keep the `pl_trdy` policy between `pl_stallreq` and `lp_stallack` instead of holding it high |
| `stall_timeout` | 2000 | FDI-R57 bound |
| `tx_hold` | 0 | `pl_trdy` low from the next flit boundary (back-pressure) |
| `random_adapter_bytes` | 0 | random Flit Header and CRC bytes on RX (the Protocol Layer must ignore them) |
| `poison_cancelled` | 1 | cancelled halves carry random bytes |
| `checks_en`, `cov_en` | 1, 1 | monitor checks; coverage calls to `mon.cov` |
| `check_tx_adapter_bytes` | 1 | FDI-R45 |
| `irdy_reset_grace` | 4 | cycles `lp_irdy` may stay high after entering Reset (FDI-R44) |
| `gate` | | `ucie_fdi_gate`, shared with L2: `open`, `rx_early`, `abort`, `epoch`, `quiet()` |

### L1: classes

| Class | Role | Public |
|---|---|---|
| `ucie_fdi_agent` | one FDI | `cfg`, `vif`, `sqr`, `drv`, `rsp`, `mon` |
| `ucie_flit_item` | one 256B flit | `data[256]`, `phy`, `dir`; drive plan `cancel_h0`, `cancel_h1`, `h1_replay_resend_h0`, `cancel_repeat`, `pre_gap`, `beat_gap_pct`, `max_beat_gap`; observed `n_cancel_h0/h1` (a whole-flit cancel at 256 B counts in `n_cancel_h0`), `n_cancel_valid`, `n_stall_cycles`, `gap_before`, `t_start`, `t_end`, `t_beat[]` (when each beat was collected); `get_beat`, `put_beat` (with a `lane` argument for a transfer wider than a flit, 0 today), `randomize_payload`, `clear_adapter_bytes`, `same_payload`, `copy_data`, `mix_cancel_plan` |
| `ucie_flit_seq` | RX traffic | `n_flits`, `payloads[$]`, `cancel_pct`, `cancel_mix`, `gap_pct`, `bubble_pct`, `random_payload`, `pid` |
| `ucie_fdi_pl_driver` | drives RX flits with their cancel plan | |
| `ucie_fdi_tx_responder` | `pl_trdy`, `pl_stallreq` | `stall_begin()`, `stall_end()`, `stalled()` |
| `ucie_fdi_monitor` | both directions, checks | `ap_tx`, `ap_rx`, `cov`, counters `n_tx_flits`, `n_rx_flits`, `n_rx_cancels`, `n_stalls`, ... |
| `ucie_fdi_cov` | interface class: a mainband coverage collector | `sample_xfer`, `sample_cancel`, `sample_stall`, `sample_abandon` (Extension API) |
| `ucie_rule_log` | rule ledger | `check()`, `fire()`, `lines()`, `clear()` (static) |

### L2: `ucie_lsm_cfg`

| Field | Default | Meaning |
|---|---|---|
| `n_phy`, `active_phy` | 1, 0 | FDIs, and the one the Protocol Layer follows |
| `park_idle_phy` | 0 | two FDIs: the other one stays in Reset with its mainband closed |
| `is_active` | 1 | 0: monitor only |
| `lat_min`, `lat_max` | 1, 6 | Adapter response latency |
| `dwell_min`, `dwell_max` | 8, 40 | time in Retrain, L1, LinkError, ... |
| `auto_bringup` | 1 | bring the link up after every reset |
| `clk_req_hold_bringup` | 1 | hold `pl_clk_req` until the state leaves Reset |
| `rebringup_after_down` | 1 | link-down events end with a bringup |
| `req_timeout` | 20000 | cycles to wait for a Protocol Layer request (0: forever) |
| `react_en`, `react_linkerror_en` | 1, 1 | answer `lp_linkerror` and the Protocol Layer's PM exit |
| `sw_restart_delay` | random 50..1500 | cycles in Reset after a link-down before training again |
| `le_mid_flit_pct` | 0 | chance an Adapter LinkError is entered mid-flit |
| `rx_early` | 0 | cycles RX flits flow in Reset once the Receiver is active (§8.2.7) |
| `checks_en` | 1 | monitor checks |
| `cov_en` | 1 | for observers that collect link-state coverage (the model collects none itself) |
| `ref_slack` | 3 | cycles a Protocol Layer output may lag its cause |

### L2: classes

| Class | Role | Public |
|---|---|---|
| `ucie_lsm_agent` | the link | `cfg`, `phy[$]` (the mainband agents, set before build), `sqr`, `drv`, `mon` |
| `ucie_lsm_item` | one event | `kind`, `cycles`; `to` (how it ends), `at`, `in_l1`, `gap`, `hold_wake_ack` (aborts) |
| `ucie_lsm_event_seq` | one event | `of(kind)`; `ev_kind`, `ev_cycles`, `ev_to`, `ev_at`, `ev_in_l1`, `ev_gap`, `ev_hold_wake_ack` |
| `ucie_lsm_l1_seq` | L1 entry, `ev_cycles` in L1, remote exit | as `ucie_lsm_event_seq` |
| `ucie_lsm_driver` | Adapter state machine | `state`, `link_active`, `execute(item)`, `set_state()`, `wait_cycles()`, `parked()`; counters `n_le`, `n_le_react`, `n_le_mid_tx`, `n_le_mid_rx` |
| `ucie_lsm_monitor` | checks | `add_observer()`, `cur`, `prev` |
| `ucie_lsm_obs_t` | struct: one clock | `rst_n`, `pl_state_sts`, `sts`, `inband_pres`, `clk_req`, `wake_ack`, `rx_active_req`, `lp_state_req`, `req`, `wake_req`, `clk_ack`, `rx_active_sts`, `linkerror`; `obs_reset()`, `obs2string()` |
| `ucie_lsm_observer` | interface class: follows the link state | `observe(cur, prev)` (Extension API) |

### Plusargs

| Plusarg | Sets |
|---|---|
| `+react_linkerror=0\|1` | `ucie_lsm_cfg.react_linkerror_en` |
| `+sw_restart_delay=N` | `ucie_lsm_cfg.sw_restart_delay` (else random 50..1500) |
| `+le_mid_flit_pct=N` | `ucie_lsm_cfg.le_mid_flit_pct` |
| `+fdi_rx_early=N` | `ucie_lsm_cfg.rx_early` |
| `+park_idle_phy=0\|1` | `ucie_lsm_cfg.park_idle_phy` |

The link-state agent reads them in its `build_phase`. Everything else is set in the
config objects.

## Checks

*Always on in the monitors (`checks_en`), each a rule ID; every evaluation and every
violation is counted in `ucie_rule_log`.* A violation is a `uvm_error` with the
checker's class name as the ID and the message starting `FDI-Rnn:`. "Design" rules
check the Protocol Layer, "model" rules check the Adapter model itself.

| Rule | Checks | Checker | UCIe r1.1 | At 256 B |
|---|---|---|---|---|
| FDI-R01 | a TX beat transfers only on `lp_irdy & lp_valid & pl_trdy` | `ucie_fdi_monitor` | §8.2.4 | unchanged: one beat is the flit |
| FDI-R02 | design: no bubbles inside a TX flit | `ucie_fdi_monitor` | §8.2.4 | nothing to check: a TX flit is one beat, so it has no inside |
| FDI-R05 | model: `pl_flit_cancel` only in the cycle after the last beat of a 128B half | `ucie_fdi_monitor` | Table 8-2 | in the cycle after the flit's one beat; it cancels the whole flit, since both halves end in that transfer |
| FDI-R07 | `pl_stallreq` and `lp_stallack` low at reset exit | `ucie_fdi_monitor` | §8.3.2 | unchanged |
| FDI-R08 | model: `pl_stallreq` rises with `lp_stallack` low, falls with it high | `ucie_fdi_monitor` | §8.3.2 | unchanged |
| FDI-R09 | design: `lp_stallack` rises with `pl_stallreq` high, falls with it low | `ucie_fdi_monitor` | §8.3.2 | unchanged |
| FDI-R10 | design: `lp_valid`, `lp_irdy` low while `lp_stallack` is high | `ucie_fdi_monitor` | §8.3.2 | unchanged |
| FDI-R12 | design: at least one flop between `pl_stallreq` and `lp_stallack` | `ucie_fdi_monitor` | §8.3.2 | unchanged |
| FDI-R13 | design: `lp_stallack` rises only at a flit boundary | `ucie_fdi_monitor` | §8.3.2 | always met: every cycle between TX beats is a flit boundary |
| FDI-R14, R15 | model: `pl_wake_ack` follows `lp_wake_req` | `ucie_lsm_monitor` | §8.2.3.1 | unchanged (no mainband) |
| FDI-R16 | design: `lp_wake_req` high when `lp_state_req` changes leaving Reset, PM, LinkReset or Disabled | `ucie_lsm_monitor` | §8.2.3, §8.2.3.1 | unchanged (no mainband) |
| FDI-R18, R19 | design: `lp_clk_ack` answers `pl_clk_req` a clock later at the earliest, and falls after it | `ucie_lsm_monitor`, `ucie_lsm_driver` | §8.2.3.2 | unchanged (no mainband) |
| FDI-R25, R29 | model: `pl_rx_active_req` rules; both rx_active signals low before leaving Active | `ucie_lsm_monitor` | §8.2.7 | unchanged (no mainband) |
| FDI-R26, R28 | design: `lp_rx_active_sts` answers `pl_rx_active_req` | `ucie_lsm_monitor`, `ucie_lsm_driver` | §8.2.7 | unchanged (no mainband) |
| FDI-R33 | design: NOP for at least a clock before Active from Reset | `ucie_lsm_monitor`, `ucie_lsm_driver` | §8.2.8, §8.3.3.1 | unchanged (no mainband) |
| FDI-R35 | model: flits to the Protocol Layer only in Active (or Reset with the Receiver active) | `ucie_fdi_monitor` | §8.2.7, §8.2.8 | unchanged |
| FDI-R41 | design: Active requested after a PM exit | `ucie_lsm_driver` | §8.2.9 | unchanged (no mainband) |
| FDI-R42 | design: `lp_valid` only with `lp_irdy` | `ucie_fdi_monitor` | Table 8-2 | unchanged |
| FDI-R43 | design: a TX flit starts only in Active | `ucie_fdi_monitor` | §8.2.4, §8.3.3 | unchanged |
| FDI-R44 | design: `lp_irdy` low in Reset | `ucie_fdi_monitor` | Table 8-2 | unchanged |
| FDI-R45 | design: TX Protocol ID non-zero, other Flit Header and CRC bytes zero | `ucie_fdi_monitor` | §2.4.4, §3.3.4 | unchanged: the same bytes, collected from one beat |
| FDI-R46 | design: no reserved `lp_state_req` value | `ucie_lsm_monitor` | Table 8-2 | unchanged (no mainband) |
| FDI-R47 | design: no Retrain request outside Raw Format | `ucie_lsm_monitor` | §8.3.3.4 | unchanged (no mainband) |
| FDI-R48 | design: a Retrain from Active ends with NOP->Active | `ucie_lsm_driver` | §8.3.3.4 | unchanged (no mainband) |
| FDI-R49 | design: `lp_linkerror` released once the Adapter reports LinkError | `ucie_lsm_driver` | §8.3.3.7 | unchanged (no mainband) |
| FDI-R57 | design: `lp_stallack` within `stall_timeout` cycles of `pl_stallreq` (liveness bound) | `ucie_fdi_monitor` | §8.3.2 | unchanged |

**Flit width 256 B.** UCIe r1.1 times `pl_flit_cancel` from the end of each 128B half
(Table 8-2) and maps flit byte k to transfer floor(k/N) (§8.3.1). With N = 256 the
whole flit is one transfer and both halves end in it, so there is one cancel cycle per
flit, and a cancel in it applies to the whole flit; UCIe r3.0 §10.3.1 says the same of
FDIs wider than a flit (a cancel applies to every flit in that clock). The model
therefore cancels whole flits at 256 B: a cancel plan on either half becomes
`cancel_repeat` cancels of the flit, then the flit. Because a flit has no inside, a
stall request is always at a flit boundary, the design's TX never has a partial flit to
abandon, and a mid-flit LinkError can only catch an RX flit in its cancel cycle or
between a cancel and its replay. The rules whose wording names a half or the inside of
a flit are traced in the "At 256 B" column above.

The model's own obligations that hold by construction (the clock-request ordering
around link-state exits, Active only after the rx_active handshake, PM entry only after
a stall, no flits with the Receiver inactive) are in the driver's comments.

## Coverage

*The model samples, the bench counts.* A mainband monitor with a collector set
(`mon.cov`, a `ucie_fdi_cov`) and `cov_en` calls it at every flit, cancel, stall and
abandoned flit. Link-state coverage is an observer's: it sees every clock and samples
what it needs. `sample_xfer` gets the FDI width, so a collector bins per width (32,
64, 128, 256 bytes); `sample_cancel`'s `half` is 0 or 1 for a 128B half and 2 for a
whole-flit cancel at 256 B. At 256 B a collector can never see a TX stall between
beats, a stall raised mid-flit, a half cancel or an abandoned TX flit, so bins for
those belong only to the narrower widths. The AoU bench's collectors are `aou_fdi_cov`
and `aou_lsm_cov`. Stimulus quality figures (cancels, stalls, abandoned flits, RX beats in Reset) are also in
the mainband monitor's end-of-test summary.

## Self-test

*The model against a Protocol Layer stub that loops every delivered flit back, on one
FDI.* `ucie_pl_stub` answers the handshakes and the state requests as a simple Protocol
Layer would; `ucie_fdi_selftest_sb` checks that every flit sent arrives intact after
its cancels and comes back in order; the model's monitors check the rules on the way.

```sh
cd dv
make test UVM_HOME=<uvm-core checkout> SIM=vcs TEST=ucie_fdi_smoke_test SEED=1
make test UVM_HOME=<uvm-core checkout> SIM=verilator TEST=ucie_fdi_events_test PLUSARGS="+beat_bytes=128 +trdy=bursty"
```

| Test | Covers |
|---|---|
| `ucie_fdi_smoke_test` | traffic both ways: cancels of every shape (whole-flit cancels at 256 B), bubbles, gaps, `pl_trdy` policy, stand-alone and mid-flit stalls, random Adapter bytes; fails if no RX flit was cancelled |
| `ucie_fdi_events_test` | the same under Retrain, L1 entry and exit, a clock wake, LinkError entered mid-flit, LinkReset, Disabled and a Retrain ending in LinkError |

Knobs: `+beat_bytes=32|64|128|256`, `+trdy=always|random|bursty|holes`, `+n_flits=N`, plus
the model's plusargs. A run passes with no `UVM_ERROR` and no `UVM_FATAL`. Verilator
needs `--vpi` and uses `dv/uvm_dpi_verilator.cc`, as the AoU bench does, and
solves `randomize()` with z3 (on `PATH`, or `VERILATOR_SOLVER="<z3> --in"`).

## Known limits

- One flit format: Latency-Optimized 256B with optional bytes (Format 6). No 68B or
  Standard 256B formats, no Raw Format.
- FDI widths up to 256 bytes, one flit per clock at most. Wider FDIs (several flits
  per clock, UCIe r3.0 §10.3.1) are not modelled.
- At 256 B a half cannot be cancelled on its own: the interface has one cancel cycle
  per flit. Cancel plans that name a half become whole-flit cancels.
- No sideband, no `pl_error`, no `pl_cfg`/`lp_cfg`, no `pl_phyinrecenter`, no
  `pl_speedmode`/`pl_lnk_cfg`.
- PM entry is the Adapter's (remote-initiated) only; a Protocol Layer request for L1
  or L2 is not answered. The Protocol Layer may start a PM exit with `lp_wake_req`.
- With two FDIs both report the same state, or the one not followed stays in Reset
  (`park_idle_phy`); they do not train independently.
- The model does not check what is in a flit beyond the Adapter-owned bytes; that is
  the protocol layer's.

## The AoU bench as a consumer

The AoU bench (`hw/ip/aou/dv`) compiles the model from `uvm/sources.toml` (its sim
config's `source_lists`) and adds `aou_fdi_layer_pkg`:

- `aou_bringup_if`: the DUT's bringup pins that are not FDI (PHY select, software
  pins, status outputs, internal triggers).
- `aou_fdi_layer`: one component and a `ucie_lsm_observer`. It drives those pins
  (idle on reset, `pulse_sw()`), steps the reference model of the DUT's bringup
  controller (`aou_bringup_model`) every clock, checks that the DUT never requests L2,
  and holds the coverage collectors. The bench's envs create it and call
  `attach(lsm)` in `connect_phase`.
- `aou_fdi_cov` (a `ucie_fdi_cov`, set on every mainband monitor) and `aou_lsm_cov`
  (sampled by the layer and the reference model): feeding the bench's coverage
  service.
- `aou_t1_axi4pc_ctl`, the Axi4PC control, is a second observer.

Its tests print `ucie_rule_log` after the bench's own rule ledger.

## Moving it out of the AoU bench

*Recommendation only; nothing here depends on it.* The model sits inside the AoU
bench, at `hw/ip/aou/dv/vip/ucie_fdi`, because tt-oca-harness takes only
`hw/ip/aou/dv` from the AoU repository: anywhere else, the harness's copy of the
bench would build without it. The directory has no path into the rest of the bench
or the repository: it builds from `UVM_HOME` and itself. `uvm/ucie_fdi.f` names its
files from this directory (`UCIE_FDI_HOME`) and `uvm/sources.toml` from the
repository root under one common prefix, so a move is a copy of this directory plus
a new prefix in `uvm/sources.toml` and in the consumer's `source_lists` entry.

Two homes fit, once a second consumer wants the model:

1. **tt-oca-harness's shared VIP**, `hw/common/dv/vip/`, beside `ocah_axi_vip`. The
   directory already has that layout: `interface/`, `uvm/` with its `sources.toml`,
   `dv/` for the self-test, and this README. A harness bench lists `uvm/sources.toml`
   under `source_lists`, as the AoU bench lists the OCAH library's. The harness's
   VIPs also have a `MANUAL.md`, a cocotb layer and a self-test run from a sim config
   and testlist under `dv/`; the model would gain those there, and the harness's
   `ocah_` prefix on its names if the maintainers ask for it.
2. **A repository of its own** with this directory as its root (the `sources.toml`
   paths lose the `hw/ip/aou/dv/vip/ucie_fdi/` prefix), a licence and a CI job that
   runs the self-test on Verilator.

Either way:

- **Version it** with semantic version tags. The API is the classes, fields,
  interface classes and plusargs above: a new interface-class method is a major
  version (every implementer must add it), a new field or class a minor one, and a
  renamed or removed one a major one.
- **Consume it from AoU as a pinned dependency**, the way the bench already takes
  the OCAH library: a fetch script with a pinned commit (`scripts/get_ocah_lib.sh` is
  the pattern) into the git-ignored `.deps/`, and `sim_cfg.py` mapping the
  source-list prefix there. In the harness, the sparse checkout that script already
  makes takes one more path, and `sim_cfg.py` already maps `hw/common/dv/vip/` to it.
  That keeps one copy, makes upgrades a one-line pin change, and leaves the public
  AoU repository free of submodules. A git submodule works too but makes every clone
  and CI job carry it; a vendored copy drifts.
- **Keep the AoU layer in AoU.** `aou_fdi_layer_pkg` is the bench's, not the model's.
