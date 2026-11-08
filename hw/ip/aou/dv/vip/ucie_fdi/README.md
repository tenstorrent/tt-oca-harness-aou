<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# UCIe FDI model

A SystemVerilog UVM model of the **Adapter side of the UCIe Flit-Aware Die-to-Die
Interface (FDI)**, for verifying a Protocol Layer. It drives and checks the FDI
mainband in Latency-Optimized 256B Flit Format 6 for the Streaming protocol and the FDI link state
(pl_state_sts, the clock, wake and rx_active handshakes, stall, Adapter-initiated
link events), with an always-on rule check on both sides of the interface. Its
interfaces carry every FDI signal but the sideband configuration channel. It
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
against a loopback Protocol Layer stub on VCS and Verilator. It follows UCIe r3.0
(Revision 3.0, Version 1.0), which every section, table and figure number here and in
the code refers to. Power management is the exception: the Adapter enters L1 on its
own and does not answer L1 or L2 requests yet (see "Known limits").

**How a layer plugs in.** A layer does not subclass the model or override its types.
It takes four kinds of handle:
- the flits, on the mainband monitor's analysis ports;
- the link state, as an observer: a class that `implements ucie_lsm_observer` and
  registers with the link-state monitor, which calls it every clock;
- coverage, as a collector that `implements ucie_fdi_cov` (or extends
  `ucie_fdi_cov_base`), set on each mainband monitor;
- link events, on the link-state driver's analysis port `ap_event`.

Nothing the model does every clock allocates an object, except the flits it
publishes: each completed flit is a new `ucie_flit_item` on `ap_tx` or `ap_rx`
(by design, so subscribers may keep it), up to four per clock on the widest FDI.
With `nop_pct` the PL driver also creates each NOP flit it forwards.

| | Item | Depends on |
|---|---|---|
| Done | Mainband agent (Format 6 codec, RX driver with cancels and bubbles, TX responder with `pl_trdy` policies and stalls, monitor with checks) | - |
| Done | Link-state agent (Adapter state machine, handshakes, events: Retrain, L1 entry and exit, LinkError incl. mid-flit, LinkReset, Disabled, aborted bringups) | - |
| Done | Extension API: link-state observers and a mainband coverage collector (interface classes, the collector with a do-nothing base class), flit and link-event analysis ports; own rule ledger keyed by checker instance, self-test | - |
| Done | A second consumer: one link-state agent per FDI (several links side by side, each with its own plusargs through `+<name>@<instance>`), passive monitors that need nothing from the active driver, the two-FDI mirrored mode kept as an option (see "One FDI per protocol stack") | - |
| Done | FDI widths of 32, 64, 128 and 256 bytes; at 256 B a flit is one transfer and its cancel covers the whole flit | - |
| Done | FDI widths of 512, 768 and 1024 bytes: 2 to 4 flits per transfer, NOP lanes on RX, a cancel covers every flit of the transfer (see "Flit widths 512 B and up") | - |
| Done | NOP flits by their Protocol ID: the monitor drops every uncancelled RX NOP, the PL driver can forward NOPs (uncancelled, cancelled and replayed, cancelled and dropped; `nop_pct`), and the TX rule on Protocol ID 00b follows the stream's protocol (see "Flit format and protocol") | - |
| Done | `pl_error` (framing errors the Adapter flags, cancels and retrains after) and checks of `lp_corrupt_crc`, both applying to every flit of a transfer at 512 B and up | - |
| Done | Covergroups of the model's own: a mainband collector per FDI (`ucie_fdi_fcov`) and a link-state observer (`ucie_lsm_fcov`), plain SystemVerilog, on by default (`fcov_en`); see "Coverage" | - |
| Done | Every FDI signal but `pl_cfg`/`lp_cfg` on the interfaces: the negotiated protocol, format, speed and width from the config objects, the Physical Layer's training and L1 indications, stream IDs; DLLP, Retimer credit and error outputs tied idle; the Protocol Layer's DLLP, Retimer credit and stream outputs checked (see "Signals") | - |
| Done | The Protocol Layer's requests answered as UCIe r3.0 Table 10-4 lists them: LinkReset and Disabled on `lp_state_req` (in Active, Retrain, L1, Reset after a NOP, and Disabled in LinkReset), `lp_linkerror` in every state, and optionally the Active request that ends LinkReset, Disabled and LinkError (`down_exit_on`); a request answered during an Adapter event abandons the event | - |
| Next (follow-up) | Power management as UCIe r3.0 has it (§10.2.9, §10.3.3.2): L1 and L2 entered on the Protocol Layer's request, Active.PMNAK, the PM exit started by the Active request; today's behaviour (see "Known limits") kept only as an option, off by default | - |
| Deferred | Other flit formats (68B, Standard 256B), the Format 6 layouts of PCIe, CXL.io and Management Transport, RDI, the sideband (`pl_cfg`/`lp_cfg`, not on the interfaces), DLLPs, `pl_cerror`/`pl_nferror`/`pl_trainerror` | a user who needs them |
| Deferred | A home outside the AoU bench: tt-oca-harness's shared VIP or a repository of its own (see "Moving it out of the AoU bench") | a second consumer |

## Contents

- [What it models](#what-it-models)
- [Signals](#signals)
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

*The Adapter, seen from the Protocol Layer, on one FDI per link-state agent.* The model plays the
UCIe Die-to-Die Adapter; the design under test is the Protocol Layer. Section, table
and figure numbers are UCIe r3.0's, as in the code.

| Area | UCIe r3.0 | What the model does |
|---|---|---|
| Flit format | §3.3.4, Figure 3-25, Table 3-5 | Latency-Optimized 256B with optional bytes (Format 6) as the Streaming protocol lays it out (and CXL.cachemem, Figure 3-24, with the same Adapter-owned bytes): two 128B halves, Flit Header bytes 0-1 (but for the Protocol ID, Byte 0 [7:6]) and CRC bytes 126-127, 254-255 owned by the Adapter. See "Flit format and protocol" |
| Byte mapping | §10.3.1 | Flit byte k on FDI byte k mod N of transfer floor(k/N), N = 32, 64, 128 or 256 bytes; at 256 the flit is one transfer; at 512 B and up (a multiple of 256) flit j of a transfer on bytes 256j to 256j+255 |
| Data transfer | §10.2.4, §10.2.5, Table 10-3 | RX: `pl_valid` with bubbles, `pl_flit_cancel` of either half (idle or with the replay's first beat, repeated), of the whole flit at 256 B (see "Flit width 256 B"), of every flit of the transfer at 512 B and up, where RX transfers may carry NOP lanes; optionally NOP flits (Table 3-5, Table 10-3 `pl_flit_cancel`: `nop_pct`); TX: `pl_trdy` by policy |
| Stall | §10.3.2 | `pl_stallreq` / `lp_stallack` before every PM entry; optionally stand-alone stalls with no state change, at a flit boundary or mid-flit (`stall_pct`: out-of-spec stress in Flit mode, see Known limits), each finished before the link leaves Active for Retrain, LinkReset or Disabled; one carried into LinkError is abandoned there (`pl_stallreq` falls unacknowledged), or with `le_stall_drain` drains the Protocol Layer (`pl_trdy` until `lp_stallack`, the drained transfers dropped; §10.3.3.7) and is abandoned if still open when the link leaves LinkError |
| Clock gating | §10.2.3.1, §10.2.3.2 | `lp_wake_req` / `pl_wake_ack` responder, `pl_clk_req` / `lp_clk_ack` handshakes: before every status change out of Reset, LinkReset, Disabled or L1 and around every move of a level signal there (§10.2.3.2 rules 5 to 7); a `pl_inband_pres` drop a test runs beside the running job (`lsm.drv.do_inband_drop(n)`, say while the bringup waits in Reset) holds `pl_clk_req` on its own, so neither releases a request the other still needs |
| rx_active | §10.2.7 | `pl_rx_active_req` / `lp_rx_active_sts` on every Active entry and exit, optionally before the Protocol Layer's Active request in Reset and Retrain, as when the remote die asks first (`remote_active_first_pct`); optionally RX flits in Reset once the Receiver is active |
| Bring-up | §10.2.8, §10.3.3.1 | clock handshake, `pl_inband_pres`, the Protocol Layer's request to leave Reset (§10.3.3.1 rule 1: `lp_state_req` NOP for at least one clock in Reset, then Active; an Active held into Reset is no request), Active |
| State machine | §10.2.6, Figure 10-19, §10.3.3 | Retrain (§10.3.3.4), L1 entry by the Adapter and its exit, by the remote die or on `lp_wake_req` (§10.2.9; not as r3.0 has it, see "Known limits"), LinkReset (§10.3.3.5), Disabled (§10.3.3.6), LinkError incl. mid-flit (§10.3.3.7), the restart after a link-down (§10.3.3.8: the Adapter's own, the Protocol Layer's NOP->Active even before `pl_inband_pres`, or either; `restart_on`) |
| Protocol Layer requests | Table 10-4, §10.3.3 | see "Requests the Adapter answers" below |
| Negotiated link | Table 10-3 | `pl_protocol`, `pl_protocol_flitfmt` (Format 6) and `pl_protocol_vld` with the bringup; `pl_speedmode`, `pl_max_speedmode` (the PHY's rate as an encoding), `pl_lnk_cfg` and the stream ID from the config objects; `pl_phyinl1` in L1, `pl_phyinrecenter` while training (optional) |
| Errors | Table 10-3, §10.3.1 | RX: `pl_error` with `pl_valid` on one transfer of a 128B half (from 256 B up, of the transfer), the half finished and cancelled, a Retrain, then the replay (`error_pct`); TX: `lp_corrupt_crc` checked for placement and protocol |

### One FDI per protocol stack

UCIe r3.0 §10.2: "A single instance is used for a Protocol Layer to Adapter
connection. However, a single Adapter can host multiple protocol stacks using multiple
instances of FDI." Each FDI has its own link state: §10.2.8 runs the bring-up
"independently for each Protocol Layer stack", and §10.3.3.8 lets each stack "independently
enter these states [LinkReset, Disabled] without affecting the other protocol stack".
The model follows that: one `ucie_lsm_agent` drives and checks the link state of one FDI
(its `ucie_fdi_lsm_if` and the `pl_state_sts` of its `ucie_fdi_mb_if`). Several stacks
are several link-state agents side by side, each with its own interfaces and mainband
agent (the self-test's `ucie_fdi_reuse_test` runs two).

The **mirrored mode** (`ucie_lsm_cfg.n_phy` 2, `active_phy`, `park_idle_phy`) is an
option beyond UCIe, kept for a Protocol Layer that follows one of two FDIs through one
set of handshakes: one `lp_state_req`, wake, clock
and rx_active handshake serve both FDIs, both report the same `pl_state_sts` (or the one
not followed stays in Reset with `park_idle_phy`), and the monitor samples the followed
one. It is not UCIe's multi-stack FDI.

### Requests the Adapter answers

With `react_en` (default 1) the link-state driver answers the Protocol Layer as UCIe r3.0
Table 10-4 lists ("Yes"), alongside its own events; a request it ignores changes nothing.
L1 and L2 requests are not answered yet (see "Known limits"), and Retrain is a request
only in Raw Format (§10.3.3.4; FDI-R47 checks the Protocol Layer never makes it). L2 and
Active.PMNAK are never reported, so their columns do not arise.

| Request | Reset | Active | L1 | LinkReset | Retrain | Disabled | LinkError |
|---|---|---|---|---|---|---|---|
| NOP then Active (`lp_state_req`) | Active entry (§10.3.3.1 rule 1) | - | PM exit on `lp_wake_req` (Known limits) | -> Reset with `down_exit_on` PL or EITHER (§10.3.3.5 rule 1) | Active entry (§10.3.3.4 rule 1) | -> Reset with `down_exit_on` PL or EITHER (§10.3.3.6) | -> Reset with `down_exit_on` PL or EITHER, `lp_linkerror` 0 and `linkerror_min_res` clocks there (§10.3.3.7) |
| LinkReset | -> LinkReset after a NOP of at least a clock (note a; §10.3.3.1 rule 2) | -> LinkReset (§10.3.3.8) | -> LinkReset | ignored | -> LinkReset, optionally through Active (§10.3.3.4 rule 2) | ignored | ignored |
| Disabled | -> Disabled after a NOP (note a; §10.3.3.1 rule 3) | -> Disabled | -> Disabled | -> Disabled (§10.3.3.5 rule 2) | -> Disabled, optionally through Active | ignored | ignored |
| `lp_linkerror` (with `react_linkerror_en`) | -> LinkError (§10.3.3.1 rule 4) | -> LinkError | -> LinkError | -> LinkError (§10.3.3.5 rule 4) | -> LinkError | -> LinkError (§10.3.3.6) | held while 1 (Table 10-3) |

- Out of Active the gates close at a flit boundary with no stall (Flit mode, r3.0
  §10.3.2; a stand-alone stall already under way is finished first, so `pl_trdy` is low
  before the status changes, Table 10-3, except on the way to LinkError, which does not
  wait for it, §10.3.3.7, and in which the Adapter abandons the handshake, or with
  `le_stall_drain` drains the Protocol Layer until `lp_stallack` and abandons it on the exit
  to Reset) and rx_active falls
  before the status changes
  (§10.2.7 rule 5); out of Reset,
  LinkReset, Disabled or L1 `pl_clk_req` comes first (§10.2.3.2 rules 6 and 7). The
  responder does not wait for `pl_wake_ack` (§10.2.3.1 rule 5).
- LinkReset and Disabled come `lat_min`..`lat_max` clocks after the request, plus up to
  `remote_rsp_max` for the remote die's sideband answer while the link is up or
  training; down and not training (Reset before `pl_inband_pres`, LinkReset) the Adapter
  completes them locally (§10.3.3.8 Implementation Note). `lp_linkerror` is answered at
  once. In Reset a request held from the state before, or reached from another request,
  is no request (Table 10-4 note a). The Active entry from Reset starts only with
  `pl_inband_pres` 1: the Protocol Layer waits for it before it requests Active
  (§10.2.3.2, last paragraph), so a NOP->Active given with `pl_inband_pres` 0 and
  withdrawn to NOP is a training trigger (§10.3.3.8), and the request is the next
  NOP->Active; one held until `pl_inband_pres` rises is the request.
- A request answered while an Adapter event runs abandons the event, as a reset does,
  except an Adapter LinkError already on its way (an error the Adapter has decided on,
  which §10.3.3.7 lets it enter without completing a stall handshake) and the stall of a
  PM entry, which finish first. A later request may stop an answer in turn
  (`lp_linkerror` while a LinkReset is answered), but nothing stops the answer to
  `lp_linkerror`: a Protocol Layer that drops it before LinkError is reported and
  requests LinkReset or Disabled still gets LinkError. The Adapter has seen the
  assertion: Table 10-3 `lp_linkerror` has it "propagate this request to RDI" and asks
  for "immediate action", and the move to LinkError rests on "observing ... lp_linkerror
  assertion" (§10.3.3.8), not on the signal still being high. A handshake the stopped
  job left half done is completed before its request moves again: `pl_rx_active_req`
  falls only once `lp_rx_active_sts` has answered it (§10.2.7 rule 4), and `pl_clk_req`
  falls only once `lp_clk_ack` has answered it and rises again only once `lp_clk_ack` has
  fallen (§10.2.3.2 rules 2, 3 and 5), however slowly the Protocol Layer acknowledges.
- Afterwards: LinkReset and Disabled answered end as the Adapter's own events do (Reset,
  then with `rebringup_after_down` the bringup, which waits for `restart_on`). A
  LinkError on `lp_linkerror` that abandoned an event ends the same way; one answered
  between events leaves the link in Reset, and a later `LSM_EV_LINKERROR` (the test's own
  answer to the same request) only runs the bringup.
- The Adapter leaves LinkReset, Disabled and LinkError on its internal request after the
  dwell (`down_exit_on` INTERNAL, the default), on the Protocol Layer's Active request
  only (PL), or on whichever comes first (EITHER). The request is taken from the second
  clock of the state on; out of LinkError never while `lp_linkerror` is 1, and only after
  `linkerror_min_res` clocks there, a scaled stand-in for r3.0 §10.3.3.7's 16 ms.

## Signals

*Every FDI signal of UCIe r3.0 Table 10-3 except the sideband
configuration channel.* The mainband ones are on `ucie_fdi_mb_if`, one per FDI; the
link-wide ones on `ucie_fdi_lsm_if`. A Protocol Layer without some of them leaves the
`pl_*` ones open and ties its `lp_*` ones to the idle values below.

| Signal | Interface | What the model does | Section |
|---|---|---|---|
| `pl_valid`, `pl_data`, `pl_flit_cancel`, `pl_trdy`, `pl_stallreq`, `pl_state_sts` | mainband | drives (see "What it models") | r3.0 §10.2.4, §10.3.2 |
| `lp_valid`, `lp_irdy`, `lp_data`, `lp_stallack` | mainband | checks | r3.0 §10.2.4, §10.3.2 |
| `pl_stream[7:0]` | mainband | holds `ucie_fdi_cfg.stream` (an integration may tie it, §10.2.1) | r3.0 Table 10-3 |
| `lp_stream[7:0]` | mainband | checks it names the link's stream with `lp_valid` (FDI-R64); idle: `stream` | r3.0 Table 10-3 |
| `pl_error` | mainband | pulses with `pl_valid` on a framing error (`error_pct`, default 0); see "Errors" (FDI-R06, R58 check the model) | r3.0 Table 10-3, §10.3.1 |
| `lp_corrupt_crc` | mainband | checks its placement (FDI-R59, R60) and that the protocol includes CXL.cachemem (FDI-R61); idle: 0 | r3.0 Table 10-3, §10.3.1 |
| `pl_dllp[31:0]`, `pl_dllp_valid`, `pl_dllp_ofc` | mainband | hold 0: DLLPs are not modelled (they serve PCIe and CXL.io; 32 bits is §10.3.1's NDLLP for wide FDIs) | r3.0 Table 10-3, §10.2.4.1 |
| `lp_dllp[31:0]`, `lp_dllp_valid`, `lp_dllp_ofc` | mainband | checks no DLLP while the protocol is Streaming (FDI-R62); idle: 0 | r3.0 Table 10-3 |
| `pl_retimer_crd` | mainband | holds 0: no Retimer | r3.0 Table 10-3 |
| `lp_retimer_crd` | mainband | checks it never asserts (FDI-R63); idle: 0 | r3.0 Table 10-3 |
| `pl_inband_pres`, `pl_clk_req`, `pl_wake_ack`, `pl_rx_active_req` | link | drives | r3.0 §10.2.3, §10.2.7, §10.2.8 |
| `lp_state_req`, `lp_wake_req`, `lp_clk_ack`, `lp_rx_active_sts`, `lp_linkerror` | link | checks and answers | r3.0 §10.2.3, §10.2.7, §10.3.3 |
| `pl_protocol[3:0]` | link | holds `ucie_lsm_cfg.protocol` | r3.0 Table 10-3 |
| `pl_protocol_flitfmt[3:0]` | link | holds 0110b, Format 6 | r3.0 Table 10-3 |
| `pl_protocol_vld` | link | rises with `pl_inband_pres`, falls on entry to LinkError or Reset (FDI-R65 checks the model) | r3.0 Table 10-3 |
| `pl_speedmode[2:0]`, `pl_lnk_cfg[2:0]` | link | hold `speedmode` (the PHY's rate as an encoding; FDI has no rate of its own), `lnk_cfg` | r3.0 Table 10-3 |
| `pl_max_speedmode` | link | holds `max_speedmode` (whether the PHY's rate may exceed 32 GT/s, an encoding too) | r3.0 Table 10-3 |
| `pl_phyinl1` | link | 1 in L1 | r3.0 Table 10-3 |
| `pl_phyinl2` | link | holds 0: the model never enters L2 | r3.0 Table 10-3 |
| `pl_phyinrecenter` | link | 0, or with `recenter_en` 1 from the bringup's `pl_clk_req` handshake to Active and in Retrain | r3.0 Table 10-3, §10.2.3.2 |
| `pl_cerror`, `pl_nferror` | link | hold 0: no error reporting | r3.0 Table 10-3 |
| `pl_trainerror` | link | holds 0: the model never fails training (its LinkErrors are internal or requested, and the signal belongs with a training failure that stays until LinkError -> Reset) | r3.0 Table 10-3 |

Not on the interfaces, with what a Protocol Layer that has them connects instead:

| Signal | Tie-off | Section |
|---|---|---|
| `pl_cfg`, `pl_cfg_vld`, `pl_cfg_crd` | 0: no sideband packets and no credit returns from the Adapter | r3.0 Table 10-3, §10.2.1 |
| `lp_cfg`, `lp_cfg_vld`, `lp_cfg_crd` | left open (nothing reads them) | r3.0 Table 10-3 |
| `pl_vendor_defined` | 0 ("these signals should not assert" when unused) | r3.0 Table 10-3 |
| `lp_vendor_defined` | left open | r3.0 Table 10-3 |
| `dm_param_exchange_done`, `dm_param_stack_count` | 0: no Management Transport parameter exchange (right for a protocol without Management Transport; with `pl_protocol` 1xxxb a Protocol Layer that waits for it needs it driven by the bench) | r3.0 Table 10-3 |

The defaults describe one consistent link: Streaming (`pl_protocol` 0111b) in Format 6
on stream 04h (Stack 0 Streaming), `pl_speedmode` 101b (the encoding for 32 GT/s, the PHY
rate the Adapter reports) with `pl_max_speedmode` 0 (a PHY rate of at most 32 GT/s), a
x16 module (`pl_lnk_cfg` 010b), no recentering reported (r3.0 has `pl_phyinrecenter`
high while the link trains; `recenter_en` reports it), no errors. The link-state agent
stops the test (`uvm_fatal`) on a reserved protocol or width, a `speedmode` encoding
above 32 GT/s with `max_speedmode` 0, or a stream that does not name the protocol.

## Layout

The layout is tt-oca-harness's for shared verification IP
(`hw/common/dv/vip/<name>/`, `ocah_axi_vip` for example): the interfaces, the UVM
packages with their compile list, and the self-test each in a directory of its own.
The model has no assertion modules, and its covergroups are classes in its packages
(`uvm/l1/ucie_fdi_fcov.svh`, `uvm/l2/ucie_lsm_fcov.svh`), so it has no `sva/` or `cov/`.

| Path | Contents |
|---|---|
| `interface/ucie_fdi_mb_if.sv` | Mainband interface of one FDI (`ucie_fdi_mb_if #(DATA_W)`) |
| `interface/ucie_fdi_lsm_if.sv` | Link state of one FDI: handshakes, negotiated values, indications (`ucie_fdi_lsm_if`; shared by two FDIs in the mirrored mode) |
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
`ucie_lsm_pkg` (L2, imports L1). `ucie_fdi_pkg` comes before the interfaces:
`ucie_fdi_mb_if` takes its default width from it.

### Top

```systemverilog
ucie_fdi_mb_if #(.DATA_W(BUS_W)) fdi_mb0 (.clk(clk), .rst_n(rst_n));   // one per FDI
ucie_fdi_lsm_if                   fdi_lsm (.clk(clk), .rst_n(rst_n));
// The Receiver is Active when both rx_active signals are 1 (UCIe r3.0 §10.2.7 rule 3).
assign fdi_mb0.rx_active = fdi_lsm.pl_rx_active_req && fdi_lsm.lp_rx_active_sts;
initial begin
  uvm_config_db #(virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)))::set(null, "*", "fdi_mb0", fdi_mb0);
  uvm_config_db #(virtual ucie_fdi_lsm_if)::set(null, "*", "fdi_lsm", fdi_lsm);
end
```

The mainband interface is always `BUS_W` (8192) bits wide, so every FDI has the same
virtual-interface type; connect the low `8 * beat_bytes` bits to the design. `DATA_W`
defaults to `ucie_fdi_pkg::BUS_W`; take the width from there, never a literal: it grows
with the widest FDI the model supports (it was 1024 before 256 B FDIs and 2048 before 512
and 1024 B ones).
The Adapter drives the `pl_*` signals; the design drives the `lp_*` ones. A design
without some of them ties them to their idle values ("Signals"): `lp_linkerror`,
`lp_corrupt_crc`, `lp_dllp*` and `lp_retimer_crd` to 0, and `lp_stream` to the link's
stream (`ucie_fdi_cfg.stream`). Config-db keys: `fdi_mb<p>` per FDI (`p` is
`ucie_fdi_cfg.phy`, unique across links), `fdi_lsm` for the link-state interface unless
the parent sets `lsm.lsm_vif` itself, as a second link must (`ucie_fdi_selftest_env`
does it with its `lsm_key`). The link-state agent takes the mainband interfaces from the
agents in its `phy`.

### Environment

```systemverilog
// build_phase
fdi_cfg = ucie_fdi_cfg::type_id::create("fdi_cfg");
fdi_cfg.phy = 0;
fdi_cfg.beat_bytes = 64;                       // the FDI width: 32 to 256, or 512 to 1024 in steps of 256
fdi = ucie_fdi_agent::type_id::create("fdi0", this);
fdi.cfg = fdi_cfg;
lsm_cfg = ucie_lsm_cfg::type_id::create("lsm_cfg");   // defaults: one FDI, Streaming
lsm = ucie_lsm_agent::type_id::create("lsm", this);
lsm.cfg = lsm_cfg;
lsm.phy.push_back(fdi);                        // the FDI of this link: L2 opens, closes and stalls it
```

A second protocol stack is a second FDI and a second link-state agent: a mainband agent
with `phy` 1, a link-state agent with its own `ucie_fdi_lsm_if` in `lsm_vif`, and that
mainband agent in its `phy`. In passive mode (`is_active` 0 in both configs) the agents
only monitor, so they can sit beside the active model or on a real Adapter; the
link-state agent still takes the (passive) mainband agent in `phy`.

The link-state agent brings the link up after every reset by itself
(`cfg.auto_bringup`); traffic waits for Active.

### A protocol layer on top

The model carries flits; what is in them is the protocol layer's.

- **Into the design (RX):** start a `ucie_flit_seq` (or your own sequence of
  `ucie_flit_item`) on `fdi.sqr`. Fill `payloads` with the flits to send; the
  sequence adds a cancel plan and gaps per flit. Bytes 0-1, 126-127 and 254-255 are
  the Adapter's: only Byte 0 bits [7:6] (the Protocol ID, never 00b, which makes the
  flit a NOP the monitor drops) are yours; the rest the driver clears or randomises
  (`random_adapter_bytes`), leaving Byte 1 [7:6] (the Flit Type) at 00b. A payload
  that leaves the Protocol ID at 00b gets the sequence's `pid`: any non-zero value is
  the Protocol Layer's to choose for Streaming (Table 3-5), and 11b is only a default,
  so set your own.
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
|---|---|---|---|
| Read flits | `uvm_analysis_port #(ucie_flit_item)` `ap_tx`, `ap_rx` on `ucie_fdi_monitor` | `fdi.mon.ap_tx.connect(...)` | at every completed flit |
| Follow the link state | `interface class ucie_lsm_observer`: `observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev)` | `lsm.mon.add_observer(obj)` (any number) | every clock, reset included, after the monitor's own rules |
| Collect mainband coverage | `interface class ucie_fdi_cov`: `sample_xfer` (with the flit and its lane), `sample_cancel`, `sample_stall`, `sample_abandon`; or extend `ucie_fdi_cov_base`, which implements them all as no-ops | `fdi.mon.cov = obj` (one per monitor; PHYs may share one) | at every flit, RX cancel, stall handshake, abandoned flit; never when null or `cov_en` is 0 |
| Read link events | `uvm_analysis_port #(ucie_lsm_item)` `ap_event` on `ucie_lsm_driver` | `lsm.drv.ap_event.connect(...)` (active only) | when an event from the sequencer has run, its bringup included |

**Why interface classes for two of them.** An observer or a collector in a UVM bench
already has a base class of its own, a `uvm_component` or a `uvm_object`. An interface
class adds the model's API to it without taking that place. A collector that can be a
`uvm_object` extends `ucie_fdi_cov_base` instead and overrides only what it samples, so a
method a later version adds does not break it; one that implements the interface class
directly must add every new method. Flits and link events keep UVM's analysis ports
because many unrelated subscribers read them and may keep them.

**What an observer gets.** `ucie_lsm_obs_t` is a struct passed by value: this clock's
link-state signals as the Protocol Layer sees them (`pl_state_sts` of `active_phy`'s
FDI), decoded into `sts` and `req`, and the previous clock's. Nothing is allocated. Signals
of your own design (pins that are not FDI) are yours to sample in the same `observe()`.

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
                                    int unsigned stall, int unsigned gap, ucie_flit_item f,
                                    int unsigned lane); endfunction
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

The self-test's scoreboard (`dv/ucie_fdi_selftest_env.svh`) is a complete example.

## API reference

### Packages and interfaces

| Name | Contents |
|---|---|
| `ucie_fdi_pkg` | `FLIT_BYTES` (256), `HALF_BYTES` (128), `MIN_BEAT_BYTES` (32), `MAX_BEAT_BYTES` (1024), `MAX_BEATS_PER_FLIT` (8), `BUS_W` (8192), `FDI_STS_ACTIVE`, `FDI_STS_RESET`; `UCIE_PROTO_*` (`pl_protocol` codes), `UCIE_FLITFMT_6`, `UCIE_STREAM_S0_STREAMING`; `ucie_fdi_dir_e` (`UCIE_FDI_TX`, `UCIE_FDI_RX`), `ucie_fdi_cancel_e` (`UCIE_CANCEL_NONE/IDLE/VALID`), `ucie_fdi_trdy_e` (`UCIE_TRDY_ALWAYS/RANDOM/BURSTY/HOLES`), `ucie_fdi_beat_t`; codec helpers `valid_beat_bytes`, `beats_per_flit` (1 once a transfer holds a flit), `flits_per_beat` (1 up to 256 B, 2 or 4 above), `flit_chunk_bytes` (a flit's bytes per transfer), `beats_per_half` (the beats of one cancel unit: a half, or the one beat from 256 B up), `halves_per_flit` (cancel units per flit: 2, or 1 from 256 B up), `is_adapter_byte`, `is_crc_byte`; protocol helpers `protocol_defined`, `protocol_has_cachemem`, `protocol_is_streaming`, `stream_fits` |
| `ucie_lsm_pkg` | `ucie_lsm_state_e` (`LSM_RESET`, `LSM_ACTIVE`, `LSM_L1`, `LSM_RETRAIN`, `LSM_LINKRESET`, `LSM_LINKERROR`, `LSM_DISABLED`, ...), `ucie_lsm_req_e` (`LSM_REQ_*`), `ucie_lsm_ev_e` (`LSM_EV_*`), `ucie_lsm_abort_e` (`LSM_AB_*`); `sts_code`, `sts_decode`, `req_code`, `req_decode` (the encodings of UCIe r3.0 Table 10-3) |
| `ucie_fdi_mb_if #(DATA_W)` | `pl_valid`, `pl_data`, `pl_flit_cancel`, `pl_error`, `pl_stream`, `pl_dllp`, `pl_dllp_valid`, `pl_dllp_ofc`, `pl_retimer_crd`, `pl_trdy`, `pl_stallreq`, `pl_state_sts`; `lp_valid`, `lp_irdy`, `lp_data`, `lp_corrupt_crc`, `lp_stream`, `lp_dllp`, `lp_dllp_valid`, `lp_dllp_ofc`, `lp_retimer_crd`, `lp_stallack`; `rx_active` (driven by the top); clocking blocks `drv_cb`, `lsm_cb`, `mon_cb` |
| `ucie_fdi_lsm_if` | `pl_inband_pres`, `pl_clk_req`, `pl_wake_ack`, `pl_rx_active_req`, `pl_protocol`, `pl_protocol_flitfmt`, `pl_protocol_vld`, `pl_speedmode`, `pl_max_speedmode`, `pl_lnk_cfg`, `pl_phyinrecenter`, `pl_phyinl1`, `pl_phyinl2`, `pl_cerror`, `pl_nferror`, `pl_trainerror`; `lp_state_req`, `lp_wake_req`, `lp_clk_ack`, `lp_rx_active_sts`, `lp_linkerror`; `drv_cb`, `mon_cb` |

### L1: `ucie_fdi_cfg` (one per FDI)

| Field | Default | Meaning |
|---|---|---|
| `phy` | 0 | FDI index (config-db key `fdi_mb<phy>`) |
| `beat_bytes` | 64 | FDI width: 32, 64, 128, 256, or a multiple of 256 from 512 to 1024 bytes (r3.0 §10.3.1, Implementation Note NBYTES: 64 to 512, and multiples of 256 from 512 up, are recommended; 32 is accepted but not recommended) |
| `is_active` | 1 | 0: monitor only |
| `trdy_policy` | `ALWAYS` | `pl_trdy`: always, `RANDOM` (`trdy_pct`), `BURSTY` (runs of 1..`burst_max`), `HOLES` (only inside a flit, `hole_pct` per beat) |
| `stall_pct`, `stall_mid_pct` | 0, 0 | out-of-spec stress for Flit mode (see below and "Known limits"): chance of a stand-alone stall (a stall handshake with no state change) per flit boundary in Active, and the share raised mid-flit (none from 256 B up, where every cycle is a flit boundary). Out-of-spec stress: in Flit mode r3.0 §10.3.2 uses the handshake only on the way to PM, so a Protocol Layer may read `pl_stallreq` as a PM entry. One under way when the link leaves Active for Retrain, LinkReset or Disabled is finished, all four phases, before the status changes; LinkError does not wait for it (Known limits) |
| `stall_hold_min`, `stall_hold_max` | 1, 8 | cycles a stand-alone stall (out-of-spec stress, `stall_pct`) holds `pl_stallreq` high after `lp_stallack` |
| `stall_trdy_free` | 0 | `pl_trdy` follows its policy between `pl_stallreq` and `lp_stallack` instead of being held high, on every stall: within r3.0 on a PM entry's stall, out-of-spec stress on a stand-alone one (`stall_pct`) (r3.0 §10.3.2 rule 7: `pl_trdy` "is not required to be asserted consecutively"). Either way `pl_trdy` keeps coming during the stall with the gate open or closed, so a flit the Protocol Layer presented before `lp_stallack` is accepted (rule 7: "any data presented on the interface must be accepted by the physical layer until the rising edge of lp_stallack"); every policy raises it again (`RANDOM` needs `trdy_pct` > 0) |
| `le_stall_drain` | 0 | a stall handshake open when the link enters LinkError (r3.0 §10.3.3.7): 0 abandoned a clock after the status changes (`pl_stallreq`, still high in the first clock that shows LinkError, falls unacknowledged on the next, and `pl_trdy` stays low); 1 performed there, `pl_trdy` draining the Protocol Layer until `lp_stallack` (the transfers dropped), and abandoned with the move to Reset if still open. Either way the Adapter never waits for `lp_stallack` in LinkError (Known limits) |
| `stall_timeout` | 2000 | cycles the Protocol Layer has to answer `pl_stallreq` with `lp_stallack` (FDI-R57), a liveness bound: r3.0 §10.3.2 rule 4 gives no time |
| `tx_hold` | 0 | `pl_trdy` low from the next flit boundary (back-pressure) |
| `random_adapter_bytes` | 0 | random Flit Header and CRC bytes on RX (the Protocol Layer must ignore them); the Protocol ID is kept, since 00b would make the flit a NOP, and so is the Flit Type (Byte 1 [7:6], 00b: a protocol flit, r3.0 Table 3-5) |
| `poison_cancelled` | 1 | cancelled halves carry random bytes |
| `partial_beat_pct` | 0 | 512 B and up: chance an RX transfer carries fewer flits than it could, the empty lanes zero (NOPs) |
| `nop_pct` | 0 | chance the PL driver forwards a NOP flit of its own (Protocol ID 00b, a random sequence number and Ack/Nak field, the field never 11b, which is reserved; an all-zero body: r3.0 Table 3-5, §3.1) before a flit, at every width, and from 512 B up in each further lane of a transfer; a third of the stand-alone ones go through uncancelled, a third are cancelled and replayed, a third are cancelled and never replayed (r3.0 Table 10-3 `pl_flit_cancel`). `+ucie_nop_pct=N` sets it |
| `stream` | 04h | `pl_stream`, and what `lp_stream` must carry (FDI-R64); must name `ucie_lsm_cfg.protocol`. Its protocol picks the flit rules: Streaming (x4h) or CXL.cachemem (x3h); other streams are refused (see "Flit format and protocol") |
| `error_pct` | 0 | chance an RX flit meets a framing error: `pl_error`, the half cancelled, a Retrain, the replay (only in Active) |
| `error_retrain_timeout` | 100000 | cycles the PL driver waits for that Retrain before it reports an error and replays anyway |
| `checks_en`, `cov_en` | 1, 1 | monitor checks; coverage calls to `mon.cov` |
| `fcov_en` | 1 | the model's own covergroups (`ucie_fdi_fcov`); `+ucie_fcov` overrides it |
| `check_tx_adapter_bytes` | 1 | check the Adapter-owned bytes and the Protocol ID of every TX flit (FDI-R45, see "Flit format and protocol") |
| `irdy_reset_grace` | 4 | cycles `lp_irdy` may stay high after LinkError -> Reset (FDI-R44); r3.0 Table 10-3 allows "a few clocks" there and gives no number, so this is a liveness bound. On any other entry to Reset `lp_irdy` must already be low |
| `gate` | | `ucie_fdi_gate`, shared with L2: `open`, `rx_early`, `abort`, `epoch`, `retrain_req` (a framing error asks L2 to retrain), `quiet()` (true from the edge after a TX flit's last transfer, so the state never changes on that edge) |

### L1: classes

| Class | Role | Public |
|---|---|---|
| `ucie_fdi_agent` | one FDI | `cfg`, `vif`, `sqr`, `drv`, `rsp`, `mon`, `fcov` (null with `fcov_en` 0) |
| `ucie_flit_item` | one 256B flit (several share a transfer at 512 and 1024 B) | `data[256]`, `phy`, `dir`; drive plan `cancel_h0`, `cancel_h1`, `h1_replay_resend_h0`, `cancel_repeat`, `pre_gap`, `beat_gap_pct`, `max_beat_gap`; observed `n_cancel_h0/h1` (a whole-flit cancel at 256 B counts in `n_cancel_h0`), `n_cancel_valid`, `n_stall_cycles`, `gap_before`, `t_start`, `t_end`, `t_beat[]` (when each beat was collected); `get_beat`, `put_beat` (with a `lane` argument: the flit's 256 B lane of a wide transfer), `is_nop` (Protocol ID 00b), `make_nop` (a NOP with random sequence number and Ack/Nak bits and an all-zero body), `randomize_payload`, `clear_adapter_bytes`, `randomize_adapter_bytes`, `tx_adapter_bytes_legal(nop_legal)`, `same_payload`, `copy_data`, `mix_cancel_plan` |
| `ucie_flit_seq` | RX traffic | `n_flits`, `payloads[$]`, `cancel_pct`, `cancel_mix`, `gap_pct`, `bubble_pct`, `random_payload`, `pid` |
| `ucie_fdi_pl_driver` | drives RX flits with their cancel plan; from 512 B up packs the flits the sequence has ready into one transfer, the first one's plan applying to all; NOPs of its own with `nop_pct` | `n_nops`, `n_nops_dropped` |
| `ucie_fdi_tx_responder` | `pl_trdy`, `pl_stallreq` | `stall_begin()`, `stall_end()`, `stalled()` |
| `ucie_fdi_monitor` | both directions, checks | `ap_tx`, `ap_rx`, `cov`, counters `n_tx_flits`, `n_rx_flits`, `n_rx_cancels`, `n_stalls`, `n_rx_nops` (uncancelled RX NOP flits discarded), `n_rx_nop_cancels` (cancels of a first half or transfer of NOPs), `n_tx_nops` (TX NOPs where the stream allows them), ... |
| `ucie_fdi_cov` | interface class: a mainband coverage collector | `sample_xfer`, `sample_cancel`, `sample_stall`, `sample_abandon` (Extension API) |
| `ucie_fdi_cov_base` | a `uvm_object` implementing `ucie_fdi_cov` with no-ops, to extend | as `ucie_fdi_cov` |
| `ucie_fdi_fcov` | the model's mainband covergroups, a `ucie_fdi_cov` | `fdi_bytes` (the FDI width); `sample_lanes()`, `sample_trdy()` besides the interface's; `convert2string()` (each group's score) |
| `ucie_rule_log` | rule ledger, keyed by rule and checker instance | `check(rule, who)`, `fire(rule, who)` (`who`: the checker component), `lines()` ("RULE-LEDGER <rule> <checker class> checks=<n> fires=<n> at=<instance>"), `clear()` (static) |

### L2: `ucie_lsm_cfg`

| Field | Default | Meaning |
|---|---|---|
| `n_phy`, `active_phy` | 1, 0 | FDIs under this link state, and the one the Protocol Layer follows; 2 is the mirrored mode, beyond UCIe (see "One FDI per protocol stack") |
| `park_idle_phy` | 0 | mirrored mode: the FDI not followed stays in Reset with its mainband closed |
| `is_active` | 1 | 0: monitor only |
| `lat_min`, `lat_max` | 1, 6 | Adapter response latency |
| `dwell_min`, `dwell_max` | 8, 40 | time in Retrain, L1, LinkError, ... |
| `auto_bringup` | 1 | bring the link up after every reset |
| `clk_req_hold_bringup` | 1 | 1: the bringup holds `pl_clk_req` from before `pl_inband_pres` until the state has left Reset (r3.0 §10.2.3.2 rule 5's recommendation); 0: it releases it as `pl_inband_pres` rises, so the Protocol Layer may gate in Reset and must wake by itself, and raises it again before `pl_rx_active_req` and Active (rules 5 and 7) |
| `rebringup_after_down` | 1 | link-down events end with a bringup |
| `req_timeout` | 20000 | cycles to wait for a Protocol Layer request or acknowledge (0: forever); a liveness bound, among others on the request to leave Reset and on the NOP->Active that restarts the training with `restart_on` PL (FDI-R33) |
| `react_en`, `react_linkerror_en` | 1, 1 | answer the Protocol Layer's requests ("Requests the Adapter answers"): LinkReset, Disabled, `lp_linkerror` (with `react_linkerror_en` too), the Active request that ends a link-down state (with `down_exit_on` PL or EITHER), the PM exit on `lp_wake_req` in L1, and with `restart_on` PL or EITHER the NOP->Active restart trigger of a link left in Reset between events; 0: only the Adapter's own events |
| `down_exit_on` | `LSM_EXIT_INTERNAL` | what ends LinkReset, Disabled and LinkError (r3.0 §10.3.3.5 rule 1, §10.3.3.6, §10.3.3.7): `LSM_EXIT_INTERNAL` the Adapter's internal request after the dwell; `LSM_EXIT_PL` only the Protocol Layer's Active request (no bound: a Protocol Layer may keep the link down); `LSM_EXIT_EITHER` whichever comes first |
| `linkerror_min_res` | 200 | clocks in LinkError before the Protocol Layer's Active request may end it; a scaled stand-in for r3.0 §10.3.3.7's 16 ms minimum residency |
| `remote_rsp_max` | 0 | extra clocks, drawn in [0:N], for the remote die's sideband answer to a LinkReset or Disabled request while the link is up or training (r3.0 §10.3.3.8 Implementation Note); 0 answers at once |
| `linkdown_via_active_pct` | 0 | chance a LinkReset or Disabled answered in Retrain, or in Reset after `pl_inband_pres`, first goes through Active (r3.0 §10.3.3.4 rule 2, §10.3.3.1 rules 2 and 3) |
| `restart_on` | `LSM_RESTART_SW` | what restarts the training after a link-down (LinkError, LinkReset or Disabled -> Reset; r3.0 §10.3.3.8): `LSM_RESTART_SW` the Adapter's own decision (software restarting the training, say), `sw_restart_delay` cycles later; `LSM_RESTART_PL` the Protocol Layer's NOP->Active on `lp_state_req` in that Reset, which may come before `pl_inband_pres` and return to NOP; `LSM_RESTART_EITHER` whichever comes first. With PL or EITHER the Adapter also answers the trigger between events, so a link left down (`rebringup_after_down` 0) comes up on it |
| `sw_restart_delay` | 300 | cycles in Reset after a link-down before the Adapter restarts the training on its own (`restart_on` SW or EITHER); the agent keeps the value set here (a bench that wants many delays draws one per run, as the self-test does in [50:1500]) |
| `remote_active_first_pct` | 0 | chance an Active entry from Reset (after `pl_inband_pres`, under `pl_clk_req`) or from a Retrain entered from Active starts the rx_active handshake before the Protocol Layer's Active request, as when the remote die's Active request arrives first (r3.0 §10.2.7 rule 1, §10.2.8 step 4) |
| `le_mid_flit_pct` | 0 | chance an Adapter LinkError is entered mid-flit |
| `rx_early` | 0 | cycles RX flits flow in Reset once the Receiver is active (r3.0 §10.2.7 rule 3) |
| `protocol` | 0111b (Streaming) | `pl_protocol` |
| `speedmode`, `max_speedmode` | 101b, 0 | `pl_speedmode`, `pl_max_speedmode`: the PHY's rate as the Adapter reports it, an encoding (101b is the one for 32 GT/s; FDI has no rate of its own) |
| `lnk_cfg` | 010b (x16) | `pl_lnk_cfg` |
| `recenter_en` | 0 | raise `pl_phyinrecenter` while the link trains (bringup and Retrain) |
| `checks_en` | 1 | monitor checks |
| `cov_en` | 1 | for observers that collect link-state coverage |
| `fcov_en` | 1 | the model's own link-state covergroups (`ucie_lsm_fcov`); `+ucie_fcov` overrides it |
| `hs_fall_timeout` | 1000 | cycles `lp_clk_ack` and `lp_rx_active_sts` may stay high after their request fell (FDI-R19, R28); r3.0 orders the falls but gives no time, so a liveness bound; 0: off |
| `wake_req_window` | 16 | cycles after a request that leaves a clock-gated state within which `lp_wake_req` may still rise, when it was not already high in the request's cycle (FDI-R16); r3.0 §10.2.3.1 rule 5 lets the request go first but gives no time, so a liveness bound; 0: the same cycle |
| `clk_req_window` | 16 | cycles after a level signal (`pl_inband_pres`, `pl_rx_active_req`, `pl_phyinl1`, `pl_phyinl2`, `pl_phyinrecenter`) moved in Reset, LinkReset, Disabled or PM within which `pl_clk_req` must rise, unless `lp_clk_ack` was already high (FDI-R20, a self-check of the Adapter); r3.0 §10.2.3.2 rule 5 lets the signal move first but gives no time, so a liveness bound; 0 asks for `pl_clk_req` by the cycle after the move, as 1 does |
| `linkerror_hold_report` | 0 | report once (an info) when `lp_linkerror` holds the Adapter in LinkError this many cycles past the dwell (0: never); the Adapter waits either way |

### L2: classes

| Class | Role | Public |
|---|---|---|
| `ucie_lsm_agent` | the link state of one FDI | `cfg`, `lsm_vif` (set before build, or config-db `fdi_lsm`), `phy[$]` (the mainband agent, two in the mirrored mode, set before build), `sqr`, `drv`, `mon`, `fcov` (null with `fcov_en` 0) |
| `ucie_lsm_item` | one event | `kind`, `cycles`; `to` (how it ends), `at`, `in_l1`, `gap`, `hold_wake_ack` (aborts) |
| `ucie_lsm_event_seq` | one event | `of(kind)`; `ev_kind`, `ev_cycles`, `ev_to`, `ev_at`, `ev_in_l1`, `ev_gap`, `ev_hold_wake_ack` |
| `ucie_lsm_l1_seq` | L1 entry, `ev_cycles` in L1, remote exit | as `ucie_lsm_event_seq` |
| `ucie_lsm_driver` | Adapter state machine | `ap_event` (each event once run), `state`, `link_active`, `execute(item)`, `set_state()`, `wait_cycles()`, `parked()`, `idle()` (no event and no answer under way); counters `n_le`, `n_le_react` (LinkErrors on `lp_linkerror`), `n_down_req` (LinkReset and Disabled on `lp_state_req`), `n_via_active`, `n_exit_req` (link-down states left on the Active request), `n_le_mid_tx`, `n_le_mid_rx` |
| `ucie_lsm_monitor` | checks | `add_observer()`, `cur`, `prev` |
| `ucie_lsm_obs_t` | struct: one clock | `rst_n`, `pl_state_sts`, `sts`, `inband_pres`, `clk_req`, `wake_ack`, `rx_active_req`, `lp_state_req`, `req`, `wake_req`, `clk_ack`, `rx_active_sts`, `linkerror`; `obs_reset()`, `obs2string()` |
| `ucie_lsm_observer` | interface class: follows the link state | `observe(cur, prev)` (Extension API) |
| `ucie_lsm_fcov` | the model's link-state covergroups, a `ucie_lsm_observer` | `sample_event()` (the driver's events), `sample_own()`; `convert2string()` |

### Plusargs

| Plusarg | Old name (alias) | Sets |
|---|---|---|
| `+ucie_react_linkerror=0\|1` | `+react_linkerror` | `ucie_lsm_cfg.react_linkerror_en` |
| `+ucie_sw_restart_delay=N` | `+sw_restart_delay` | `ucie_lsm_cfg.sw_restart_delay` |
| `+ucie_restart_on=sw\|pl\|either` | | `ucie_lsm_cfg.restart_on` |
| `+ucie_down_exit=internal\|pl\|either` | | `ucie_lsm_cfg.down_exit_on` |
| `+ucie_remote_active_first_pct=N` | | `ucie_lsm_cfg.remote_active_first_pct` |
| `+ucie_le_mid_flit_pct=N` | `+le_mid_flit_pct` | `ucie_lsm_cfg.le_mid_flit_pct` |
| `+ucie_rx_early=N` | `+fdi_rx_early` | `ucie_lsm_cfg.rx_early` |
| `+ucie_park_idle_phy=0\|1` | `+park_idle_phy` | `ucie_lsm_cfg.park_idle_phy` |
| `+ucie_fcov=0\|1` | | `fcov_en` of `ucie_lsm_cfg` and of every `ucie_fdi_cfg` |
| `+ucie_nop_pct=N` | | `nop_pct` of every `ucie_fdi_cfg` |

The link-state agent reads them in its `build_phase` (the mainband agents read
`+ucie_fcov` and `+ucie_nop_pct` in theirs), overriding the config object. Each
applies to every agent; `+<name>@<instance>=<value>`, with an agent's full name,
applies to that agent only and wins (`+ucie_le_mid_flit_pct@uvm_test_top.env1.lsm=0`),
so two links can differ. The old names still work, for every agent, when the new
name is not given. Everything else is set in the config objects.

## Checks

*Always on in the monitors (`checks_en`), each a rule ID; every evaluation and every
violation is counted in `ucie_rule_log`.* A violation is a `uvm_error` with the
checker's class name as the ID and the message starting `FDI-Rnn:`. "Design" rules
check the Protocol Layer, "model" rules check the Adapter model itself.

The monitors decide everything from the interfaces, nothing from the active driver,
so a passive agent (`is_active` 0) checks the same rules: on a real Adapter the
"model" rules check that Adapter. That includes a LinkError entered mid-flit (r3.0
§10.3.3.7): the mainband monitor drops the partial flits whenever `pl_state_sts`
goes from Active to LinkError with a flit part-way in either direction, and takes
every TX transfer in LinkError as a drain under a stall handshake: dropped, never
published, with only the Protocol Layer's place in its flit kept. What a
passive agent lacks are the checks that live in the link-state driver, the
Protocol Layer's liveness bounds on its answers and requests (FDI-R18 and R26
within `req_timeout`, R33, R41, R48).

| Rule | Checks | Checker | UCIe r3.0 | At 256 B | At 512/1024 B |
|---|---|---|---|---|---|
| FDI-R01 | a TX beat transfers only on `lp_irdy & lp_valid & pl_trdy` | `ucie_fdi_monitor` | §10.2.4 | unchanged: one beat is the flit | unchanged: one beat is 2 or 4 flits |
| FDI-R02 | design: no bubbles inside a TX flit; in LinkError a Protocol Layer that stops presenting part-way has cleaned up its data path, which is no bubble | `ucie_fdi_monitor` | §10.2.4, §10.3.3.7 | nothing to check: a TX flit is one beat, so it has no inside | nothing to check: a TX flit is one beat, so it has no inside |
| FDI-R05 | model: `pl_flit_cancel` only in the cycle after the last beat of a 128B half | `ucie_fdi_monitor` | Table 10-3 `pl_flit_cancel` | in the cycle after the flit's one beat; it cancels the whole flit, since both halves end in that transfer | in the cycle after the beat; it cancels every flit of the beat (§10.3.1) |
| FDI-R06 | model: a 128B half (from 256 B up, the transfer) that carried `pl_error` is cancelled, and no RX data follows until the link has left Active to retrain | `ucie_fdi_monitor` | Table 10-3 `pl_error` | the flit's one transfer | every flit of the transfer (§10.3.1) |
| FDI-R07 | `pl_stallreq` and `lp_stallack` low at reset exit | `ucie_fdi_monitor` | §10.3.2 rule 1 | unchanged | unchanged |
| FDI-R08 | model: `pl_stallreq` rises with `lp_stallack` low, falls with it high, but in LinkError or on its exit to Reset, which abandon an open handshake | `ucie_fdi_monitor` | §10.3.2 rules 2 and 3, §10.3.3.7 | unchanged | unchanged |
| FDI-R09 | design: `lp_stallack` rises with `pl_stallreq` high, falls with it low | `ucie_fdi_monitor` | §10.3.2 rules 4 and 5 | unchanged | unchanged |
| FDI-R10 | design: `lp_valid`, `lp_irdy` low while `lp_stallack` is high | `ucie_fdi_monitor` | §10.3.2 rule 6 | unchanged | unchanged |
| FDI-R12 | design: at least one flop between `pl_stallreq` and `lp_stallack` | `ucie_fdi_monitor` | §10.3.2 rule 8 | unchanged | unchanged |
| FDI-R13 | design: `lp_stallack` rises only at a flit boundary; after a mid-flit LinkError with a stall handshake open, the boundary of the flit the abort cut, which the Protocol Layer may finish in the drain, or the point where it stopped presenting (it cleaned up its data path, §10.3.3.7) | `ucie_fdi_monitor` | §10.3.2 rule 4 | always met: every cycle between TX beats is a flit boundary | always met, as at 256 B |
| FDI-R14, R15 | model: `pl_wake_ack` rises a clock after `lp_wake_req` at the earliest, and falls only after it | `ucie_lsm_monitor` | §10.2.3.1 rules 2 and 3 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R16 | design: a request leaving a clock-gated state (`lp_state_req` to Active, LinkReset or Disabled, or `lp_linkerror` rising, in Reset, PM, LinkReset or Disabled) uses the wake handshake: `lp_wake_req` high in the request's cycle, or rising within `wake_req_window` cycles after it and before the status leaves the gated state (one that fell before the request does not count) | `ucie_lsm_monitor` | §10.2.3, §10.2.3.1 rule 5 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R18, R19 | design: `lp_clk_ack` answers `pl_clk_req` a clock later at the earliest, and falls after it, within `hs_fall_timeout` | `ucie_lsm_monitor`, `ucie_lsm_driver` | Table 10-3 `lp_clk_ack`, §10.2.3.2 rules 2 and 3 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R20 | model: a level signal (`pl_inband_pres`, `pl_rx_active_req`, `pl_phyinl1`, `pl_phyinl2`, `pl_phyinrecenter`) that moves in Reset, LinkReset, Disabled or PM is covered by a `pl_clk_req` handshake: seen with `lp_clk_ack` high, or `pl_clk_req` rises within `clk_req_window` cycles and stays high until `lp_clk_ack` | `ucie_lsm_monitor` | §10.2.3, §10.2.3.2 rule 5 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R21 | model: a LinkError entered from Reset, LinkReset, Disabled or PM has `pl_clk_req` high before the change, or raised after it and acknowledged before the next status change | `ucie_lsm_monitor` | §10.2.3.2 rule 6 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R22 | model: any other status change out of Reset, LinkReset, Disabled or PM has `pl_clk_req` asserted before it and held until the status has changed | `ucie_lsm_monitor` | §10.2.3.2 rule 7 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R25, R29 | model: `pl_rx_active_req` rises only with `lp_rx_active_sts` low in Reset, Retrain or Active; both rx_active signals low before leaving Active for anything but LinkError | `ucie_lsm_monitor` | §10.2.7 rules 1 and 5 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R26, R28 | design: `lp_rx_active_sts` answers `pl_rx_active_req`, and falls after it, within `hs_fall_timeout` | `ucie_lsm_monitor`, `ucie_lsm_driver` | §10.2.7 rules 2 and 4 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R33 | design: the Protocol Layer asks to leave Reset (NOP for at least a clock in Reset, then Active) within `req_timeout` cycles of `pl_inband_pres`, and with `restart_on` PL gives the NOP->Active that restarts the training within `req_timeout` cycles of a link-down (liveness bounds). An Active held into Reset, or reached from another request, is no request; the driver does not take it and nothing reports it (`cg_reset_req` covers it) | `ucie_lsm_driver` | §10.3.3.1 rule 1, Table 10-4, §10.3.3.8 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R35 | model: flits to the Protocol Layer only while its Receiver is Active: `pl_rx_active_req` and `lp_rx_active_sts` both 1 with `pl_state_sts` Reset, Retrain or Active | `ucie_fdi_monitor` | §10.2.7 rules 3 and 6 | unchanged | unchanged; NOP lanes count as flits on the wire |
| FDI-R41 | design: Active requested after a PM exit, within `req_timeout` (a liveness bound) | `ucie_lsm_driver` | §10.2.9, §10.3.3.4 rule 1 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R43 | model: `pl_trdy` high only in Active, or in LinkError while `pl_stallreq` or `lp_stallack` is high (the Adapter drains the Protocol Layer under a stall handshake, which lasts until `lp_stallack` falls, rule 9), so no TX transfer (`lp_valid`, `lp_irdy`, `pl_trdy`) outside them either. Presenting a flit and waiting outside Active is legal, and `lp_valid` without `lp_irdy` transfers nothing | `ucie_fdi_monitor` | Table 10-3 `pl_trdy`, §10.2.4, §10.3.2 rules 6 and 9, §10.3.3.7 | unchanged | unchanged |
| FDI-R44 | design: `lp_irdy` low in Reset, but for `irdy_reset_grace` cycles after LinkError -> Reset | `ucie_fdi_monitor` | Table 10-3 `lp_irdy` | unchanged | unchanged |
| FDI-R45 | design: in every TX flit the Flit Header bits but the Protocol ID, and the CRC bytes, are zero (Byte 1 [7:6], the Flit Type, is 00b for a protocol flit), and on a Streaming stream the Protocol ID is not 00b (a NOP, which a Streaming Protocol Layer never sends); on a CXL.cachemem stream 00b is a NOP flit and passes | `ucie_fdi_monitor` | §3.3.4, Table 3-5, Figures 3-24, 3-25 | unchanged: the same bytes, collected from one beat | checked in every lane: the Protocol Layer sends valid data on the full width (§10.3.1), so on a Streaming stream an empty lane (Protocol ID 00b) fails; on CXL.cachemem it is a NOP flit |
| FDI-R46 | design: no reserved `lp_state_req` value | `ucie_lsm_monitor` | Table 10-3 `lp_state_req` | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R47 | design: no Retrain request outside Raw Format | `ucie_lsm_monitor` | §10.3.3.4 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R48 | design: a Retrain from Active ends with NOP->Active | `ucie_lsm_driver` | §10.3.3.4 rule 1 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R49 | model: the Adapter stays in LinkError while `lp_linkerror` is 1, however long the Protocol Layer holds it (the driver waits with no bound), whatever ends it: its internal request or the Protocol Layer's Active request | `ucie_lsm_monitor` | Table 10-3 `lp_linkerror`, §10.3.3.7 | unchanged (no mainband) | unchanged (no mainband) |
| FDI-R57 | design: `lp_stallack` within `stall_timeout` cycles of `pl_stallreq` (liveness bound), not in LinkError, where the Protocol Layer need not acknowledge | `ucie_fdi_monitor` | §10.3.2 rule 4, §10.3.3.7 | unchanged | unchanged |
| FDI-R58 | model: `pl_error` only while the Receiver is active | `ucie_fdi_monitor` | Table 10-3 `pl_error` | unchanged | unchanged |
| FDI-R59 | design: `lp_corrupt_crc` only with `lp_valid`, on the last transfer of a 128B half | `ucie_fdi_monitor` | Table 10-3 `lp_corrupt_crc`, §10.3.1 | any transfer: each ends both halves | any transfer; it applies to every flit of it (§10.3.1) |
| FDI-R60 | design: `lp_corrupt_crc` on a flit's first half is repeated on its second | `ucie_fdi_monitor` | Table 10-3 `lp_corrupt_crc` | nothing to check: both halves end in one transfer | as at 256 B |
| FDI-R61 | design: `lp_corrupt_crc` only when the protocol includes CXL.cachemem | `ucie_lsm_monitor` | Table 10-3 `lp_corrupt_crc` | unchanged | unchanged |
| FDI-R62 | design: no `lp_dllp_valid` while the protocol is Streaming | `ucie_lsm_monitor` | Table 10-3 `lp_dllp` | unchanged | unchanged |
| FDI-R63 | design: `lp_retimer_crd` never asserts (no Retimer; FDI exposes it for Raw Format only) | `ucie_lsm_monitor` | Table 10-3 `lp_retimer_crd` | unchanged | unchanged |
| FDI-R64 | design: `lp_stream` names the link's stream on the first beat of every TX flit | `ucie_fdi_monitor` | Table 10-3 `lp_stream` | unchanged | unchanged |
| FDI-R65 | model: `pl_protocol_vld` is 1 whenever `pl_inband_pres` is 1 in Reset, and falls only on entry to LinkError or Reset | `ucie_lsm_monitor` | Table 10-3 `pl_protocol_vld` | unchanged (no mainband) | unchanged (no mainband) |

**Flit width 256 B.** UCIe r3.0 times `pl_flit_cancel` from the end of each 128B half
(Table 10-3 `pl_flit_cancel`) and maps flit byte k to transfer floor(k/N) (§10.3.1). With
N = 256 the whole flit is one transfer and both halves end in it, so there is one cancel
cycle per flit, and a cancel in it applies to the whole flit; §10.3.1 says the same of
FDIs wider than a flit (a cancel applies to every flit in that clock). The model
therefore cancels whole flits at 256 B: a cancel plan on either half becomes
`cancel_repeat` cancels of the flit, then the flit. Because a flit has no inside, a
stall request is always at a flit boundary, the design's TX never has a partial flit to
abandon, and a mid-flit LinkError can only catch an RX flit in its cancel cycle or
between a cancel and its replay. The rules whose wording names a half or the inside of
a flit are traced in the "At 256 B" column above.

**Flit widths 512 B and up.** UCIe r3.0 §10.3.1 (Implementation Note "NBYTES")
covers FDIs wider than a flit, recommending multiples of 256 B; the model takes 512, 768
and 1024 B. A transfer then carries 2 to 4 flits, flit j on bytes 256j to 256j+255. The
Adapter forwards whole flits on the low lanes and zeros on the rest; a Flit Header of
0000h is a NOP that the Protocol Layer discards (and Table 10-3, `pl_flit_cancel`, has it
discard any uncancelled NOP). The Protocol Layer sends valid data on the full width,
packing a Protocol Flit with empty slots if it has nothing else, so on a Streaming stream
an empty TX lane fails the TX flit-format check (FDI-R45; on CXL.cachemem an all-zero lane
is a NOP flit, see "Flit format and protocol"). `pl_flit_cancel`
applies to every flit of the transfer before it. The PL driver packs the flits the
sequence has ready (fewer with `partial_beat_pct`) and uses the first flit's cancel plan
for the transfer; the monitor publishes each lane as its own flit and drops NOPs on RX
(at every width). As at 256 B every cycle between transfers is a flit boundary, so a
stall request or a state change always lands on one. The spec leaves open whether a
replay after a cancel re-sends the same flits in the same lanes; the monitor makes no
assumption and takes the replay transfer as it comes. The width bins of `cg_xfer` and
`cg_lanes` name 32 to 1024 B but not 768 B, which the model takes but the self-test does
not run: flits on a 768 B FDI fall in no width bin.

**Flit format and protocol.** The model lays flits out as Format 6 for the Streaming
protocol (r3.0 §3.3.4, Figure 3-25): the Adapter owns the Flit Header, Bytes 0-1, but
for the Protocol ID (Byte 0 [7:6]), and the CRC, Bytes 126-127 and 254-255. CXL.cachemem's
Format 6 (Figure 3-24) owns the same bytes. The flit rules follow the protocol of the FDI's
stream (`ucie_fdi_cfg.stream`; r3.0 Table 10-3: "Each stream ID maps to a unique protocol
and stack"), and the agent refuses any other stream:

| Stream | Layout | Protocol ID 00b on TX (FDI-R45) | Status |
|---|---|---|---|
| Streaming (04h, 14h) | Figure 3-25 | an error: "Protocol Layer must never set this to 00b for Flits sent across FDI" (Table 3-5; §3.3.4) | modelled, the default |
| CXL.cachemem (03h, 13h) | Figure 3-24, the same Adapter-owned bytes | accepted, a permissive reading: Table 3-5 names 00b the "D2D Adapter/CXL.io NOP Flit", which does not name CXL.cachemem, but it does not forbid 00b to the Protocol Layer as it does for Streaming | modelled |
| PCIe, CXL.io (x1h, x2h) | Figure 3-23: DLP bytes 122-125 and Flit_Marker bytes 250-253, shared by the Adapter and the Protocol Layer, Byte 0 [4] from the Protocol Layer | a NOP flit, which a PCIe Protocol Layer must send when it has no TLPs (§10.2.4.1) | not modelled: refused |
| Management Transport (x5h) | Figure 3-26: credit return on Bytes 250-253 from the Protocol Layer | | not modelled: refused |

A NOP is any flit with Protocol ID 00b, whatever its sequence number and Ack/Nak field
(Table 3-5); its body is all zeros (§3.1: "the body of the Flit is filled with all 0
data"), and the all-zero lane of a wide transfer is one. The monitor drops every RX NOP
that arrives uncancelled from `ap_rx` (Table 10-3 `pl_flit_cancel`: the Protocol Layer
"must discard these Flits"). With `nop_pct` the PL driver forwards NOPs of its own, at every
width: through uncancelled, cancelled and replayed by an ordinary cancel plan, or cancelled
and never replayed, as Table 10-3 lets an Adapter cancel valid NOP flits to keep them from
the Protocol Layer. A dropped NOP has its first 128B half (from 256 B up, its transfer)
forwarded and cancelled with `pl_valid` low in the cancel cycle, and nothing more of it is
sent. RX flits keep the Flit Type at 00b (Byte 1 [7:6], a protocol flit), with
`random_adapter_bytes` too: an Adapter does not hand a Protocol Layer Test flits (01b), and
Management flits (10b) travel on the Management Transport stream. With Management Transport
negotiated beside Streaming (`pl_protocol` 1111b), the mainband still carries only the
Streaming stream's protocol flits.

The model's own obligations that hold by construction are in the driver's and the TX
responder's comments: Active only after the rx_active handshake, on every entry (FDI-R34,
§10.2.8 steps 4 and 5); PM entry only after a stall handshake (FDI-R38, §10.3.2); data
the Protocol Layer presented accepted until `lp_stallack` (FDI-R11, §10.3.2 rule 7; in
LinkError as a drain, §10.3.3.7); a
stand-alone stall finished before any exit from Active but to LinkError, and never cut
short outside reset.

## Coverage

*The model has covergroups of its own, and a bench may add its collectors beside them.*
Both are plain SystemVerilog covergroups and need nothing from a bench; `fcov_en` (on by
default) or `+ucie_fcov=0` turns them off. VCS scores them (each agent prints its groups'
scores at the end of the test, and URG merges runs); Verilator 5.052 compiles and samples
them but scores them as 0, so the number comes from VCS. Bins that only some FDI widths
can reach count over the widths the self-test runs: the merged score is the one that
means anything.

| Group | Class | Sampled | Bins |
|---|---|---|---|
| `cg_xfer` | `ucie_fdi_fcov` | every completed flit | direction × FDI width (32 to 1024 B); direction × stall cycles inside the flit (`pl_trdy` low on TX, bubbles on RX: 0, 1, 2-7, 8+); direction × idle cycles before it |
| `cg_cancel` | `ucie_fdi_fcov` | every RX cancel | the unit (half 0, half 1, the flit at 256 B, every flit of a 512 or 1024 B transfer) × kind (idle, or with the replay's first beat); the cancels so far on the flit (1, 2, 3+); whether the TX side was stalled |
| `cg_stall` | `ucie_fdi_fcov` | every stall handshake | where `pl_stallreq` rose (a flit boundary, inside a flit with `pl_trdy` high, inside one with `pl_trdy` low); cycles to `lp_stallack`; cycles `lp_stallack` held |
| `cg_abandon` | `ucie_fdi_fcov` | a partial flit dropped on a mid-flit LinkError | TX, RX |
| `cg_lanes` | `ucie_fdi_fcov` | every RX transfer at 512 and 1024 B | flits carried, the rest NOP lanes: 1 or 2 at 512 B, 1 to 4 at 1024 B |
| `cg_trdy` | `ucie_fdi_fcov` | the end of a run of `pl_trdy` low the policy made (all in Active, no stall handshake, no `tx_hold`) | policy × where the run started (random and bursty: at a flit boundary or inside a flit; holes: inside only); its length |
| `cg_state` | `ucie_lsm_fcov` | every `pl_state_sts` change | each (previous, current) transition the model makes: 23 bins, from Reset to Active through every exit and abort, and LinkReset to Disabled on the request |
| `cg_clk` | `ucie_lsm_fcov` | `lp_clk_ack` rising | the state: Reset, Active, L1, LinkReset, LinkError, Disabled |
| `cg_wake` | `ucie_lsm_fcov` | `pl_wake_ack` rising | the state: Reset, L1 (an exit the Protocol Layer starts), Retrain |
| `cg_rx_active` | `ucie_lsm_fcov` | `pl_rx_active_req` changing | entry in Reset or Retrain, exit in Active or LinkError |
| `cg_event` | `ucie_lsm_fcov` | every link event the driver runs, and what it does on its own | the bringup, Retrain (ending in Active, LinkError, LinkReset or Disabled), LinkError (at a boundary, mid-flit, on `lp_linkerror`), a Retrain after `pl_error`, L1 entry and exit (by the Adapter or on `lp_wake_req`), LinkReset and Disabled (each also escalated to LinkError), the clock wake, an abort (`LSM_EV_INBAND_DROP` has none: it is for a link a test keeps in Reset) |
| `cg_reset_req` | `ucie_lsm_fcov` | an Active request in Reset; `pl_rx_active_req` rising before it | NOP then Active with `pl_inband_pres` 1 (the request) or 0 (the early training trigger), Active held into Reset, Active straight from another request, the rx_active handshake before the request in Reset and in Retrain ("before" judged by the NOP->Active progress since the entry to that state, so an Active held into it does not count as the request) |
| `cg_request` | `ucie_lsm_fcov` | every Protocol Layer request the driver answers (r3.0 Table 10-4) | LinkReset in Active, Retrain, L1 and Reset; Disabled in those and in LinkReset; `lp_linkerror` in Reset, Active, Retrain, L1, LinkReset and Disabled, and abandoning an event; an answer through Active; LinkReset, Disabled and LinkError left on the Active request |
| `cg_abort` | `ucie_lsm_fcov` | every abort | where (Reset, after the wake, after the Active request, in L1) and what it ends in (LinkError, LinkReset, Disabled, Reset) |
| `cg_error` | `ucie_fdi_fcov` | every `pl_error` | the unit (half 0 or 1, the flit at 256 B, every flit of a wider transfer) × the transfer it rode on (first, inside, last of a half; the only one from 256 B up) |
| `cg_corrupt` | `ucie_fdi_fcov` | every TX transfer with `lp_corrupt_crc` | the second half only, both halves, the flit (256 B), every flit of a wider transfer |

The mainband collector is an `ucie_fdi_cov` like a bench's and takes the rest through
methods of its own (`sample_lanes`, `sample_trdy`); the link-state one is an observer
like any other, and the driver also reports its events to it.

*A bench's collectors.* A mainband monitor with a collector set
(`mon.cov`, a `ucie_fdi_cov`) and `cov_en` calls it at every flit, cancel, stall and
abandoned flit. Link-state coverage is an observer's: it sees every clock and samples
what it needs. `sample_xfer` gets the FDI width, so a collector bins per width (32,
64, 128, 256, 512, 1024 bytes); at 512 and 1024 B it is called once per flit of a
transfer, NOPs not included. `sample_cancel`'s `half` is 0 or 1 for a 128B half and 2
for a cancel of the whole transfer from 256 B up (one call per cancel, however many
flits it drops). From 256 B up a collector can never see a TX stall between beats, a
stall raised mid-flit, a half cancel or an abandoned TX flit, so bins for those belong
only to the narrower widths. Stimulus quality figures (cancels, stalls, abandoned flits, RX beats in Reset, RX NOPs and short wide transfers) are also in
the mainband monitor's end-of-test summary.

## Self-test

*The model against a Protocol Layer stub that loops every delivered flit back, on one
FDI (two in `ucie_fdi_reuse_test`).* `ucie_pl_stub` answers the handshakes and the state requests as a simple Protocol
Layer would; `ucie_fdi_selftest_sb` checks that every flit sent arrives intact after
its cancels and comes back in order; the model's monitors check the rules on the way.

```sh
cd dv
make test UVM_HOME=<uvm-core checkout> SIM=vcs TEST=ucie_fdi_smoke_test SEED=1
make test UVM_HOME=<uvm-core checkout> SIM=verilator TEST=ucie_fdi_events_test PLUSARGS="+beat_bytes=128 +trdy=bursty"
```

| Test | Covers |
|---|---|
| `ucie_fdi_smoke_test` | traffic both ways: cancels of every shape (whole-transfer cancels from 256 B up), short RX transfers with NOP lanes at 512 and 1024 B, bubbles, gaps, `pl_trdy` policy, stand-alone and mid-flit stalls, random Adapter bytes; fails if no RX flit was cancelled |
| `ucie_fdi_events_test` | the same under Retrain, L1 entry and exit, a clock wake, LinkError entered mid-flit, LinkReset, Disabled and a Retrain ending in LinkError, with `pl_phyinrecenter` reporting the training |
| `ucie_fdi_cov_test` | the events test's traffic under every link event and ending the model has, for its coverage: Retrains ending in each state, LinkReset and Disabled escalated to LinkError, L1 exits by both sides, a LinkError the stub requests, and aborts at every point into every state; stalls keep their `pl_trdy` policy, and some are as short as the model makes them |
| `ucie_fdi_nop_test` | NOP flits on the smoke test's traffic: the PL driver forwards NOPs (`nop_pct` 15) with a random sequence number and Ack/Nak field and an all-zero body, uncancelled, cancelled and replayed, cancelled and dropped, and from 512 B up in lanes among other flits, which the scoreboard must never see delivered. `+nop_tx=1` runs the link as CXL.2 (stream 03h), where the stub starts a tenth of its TX transfers with a NOP flit that FDI-R45 must accept. Fails if no NOP of each kind was seen |
| `ucie_fdi_error_test` | the smoke test's traffic on a CXL.2 link (stream 03h) with framing errors (`error_pct` 10: `pl_error`, cancel, Retrain, replay) and the stub asking for corrupted CRCs (`lp_corrupt_crc` on the second half or both); fails if neither happened |
| `ucie_fdi_legal_test` | the cov test with a Protocol Layer doing what UCIe r3.0 allows (`+legal=all`, or a comma-separated list): `early` presents flits without waiting for `pl_trdy` and through Retrain, LinkError, the start of LinkReset and Disabled, and a few clocks into Reset after LinkError; `valid` drives `lp_valid` without `lp_irdy` between flits; `hs_lag` drops `lp_clk_ack` and `lp_rx_active_sts` 30 clocks after their requests; `le_hold` holds `lp_linkerror` 25000 clocks into LinkError; `wake_late` raises `lp_wake_req` a clock after its Active request. Any error fails it |
| `ucie_fdi_clk_req_test` | the `pl_clk_req` handshake on every exit from a state where the Protocol Layer may be clock gated, with a stub that gates its clock whenever r3.0 §10.2.3 lets it and acknowledges late (`+clk_ack_delay=N`, default 3): LinkReset, Disabled and LinkError from Active, Reset and L1, ending in Reset and in a bringup; LinkReset and Disabled escalated to LinkError; both L1 exits; `pl_inband_pres` drops in Reset; aborts that send a drop with its request, LinkReset or Disabled as the Protocol Layer requests Active, and LinkErrors reported before their request; then the cov test's events. `+clk_hold=0\|1` sets `clk_req_hold_bringup`. The stub reports a status change it would miss while gated (as FDI-R22 or R21); any error fails it |
| `ucie_fdi_reset_req_test` | the exit from Reset and the restart after a link-down (r3.0 §10.3.3.1 rule 1, §10.3.3.8) on the cov test's events and traffic, `+reset_req=`: `held` the stub requests Active in LinkError, LinkReset and Disabled and holds it into Reset for 40 clocks of `pl_inband_pres`, with a clock of LinkReset halfway (neither is a request with no NOP first), and reports an Adapter that starts the Active entry meanwhile; `early` the stub gives NOP->Active before `pl_inband_pres` and returns to NOP or holds Active, and reports an Adapter that starts the Active entry on a trigger withdrawn to NOP before the next NOP->Active; `restart` the same with `restart_on` PL and the Adapter's own restart decision delayed to 20000 clocks (`sw_restart_delay`), where `pl_inband_pres` must follow every trigger after a link-down within 300 clocks and a link left down must come up on it; `either` `restart_on` EITHER with the trigger in half the Resets; `rx_first` `remote_active_first_pct` 100 (the rx_active handshake before the request; both Reset and Retrain must see it); `drop` the stub waits 100 clocks of `pl_inband_pres` before its request, and the test drops `pl_inband_pres` (`do_inband_drop`) beside the bringup while it waits for that request, once in the first bringup and once in a LinkReset event's (after the link has been in LinkReset), with the Adapter's latencies at one clock, and fails unless both drops land there (it logs the link state and the bringup at each); the stub answers the drop with a one-clock NOP->Active, which the Adapter must not take, and the Active entry after the next request must keep `pl_clk_req` up until Active (FDI-R22); it cannot run with `+clk_hold=1`, since the drop waits for `pl_clk_req` to be released in Reset; `drop_overlap` the same stub, and one drop beside a LinkReset event's bringup as it waits to restart the training (`sw_restart_delay` 4), with `lp_clk_ack` 20 clocks late, so that the bringup raises its own `pl_clk_req` while the drop's waits for `lp_clk_ack`, then raises `pl_inband_pres` and releases its request inside the drop: `pl_clk_req` must stay up from that `lp_clk_ack` until `pl_inband_pres` rises, although the drop releases its own request in between: the watcher checks the model's own bringup sequence (`pl_clk_req` held from the drop's acknowledge until presence rises), while FDI-R20 (§10.2.3.2 rule 5) is the spec-level check that catches the defect (rule 7 does not apply: the status does not change in that window); `clk_req_hold_bringup` defaults to 0 in both. `+clk_hold=0\|1` sets `clk_req_hold_bringup`. Any error fails it |
| `ucie_fdi_state_req_test` | the Protocol Layer's requests (r3.0 Table 10-4), before the cov test's events and with its traffic: LinkReset and Disabled requested in Active, Retrain (abandoning an Adapter Retrain), L1 and Reset (after a NOP; link left down, and during a bringup), Disabled in LinkReset; requests the table ignores (LinkReset in Disabled, LinkReset and Disabled in LinkError); `lp_linkerror` in Reset (before and after `pl_inband_pres`), Active (between events and abandoning an idle event), Retrain (held 2000 clocks), L1, LinkReset, Disabled and as an L1 entry starts; requests that stop a job while its `pl_clk_req` waits for a slow `lp_clk_ack` (`+slow_ack=N`, default 50): LinkReset and Disabled as the Adapter's L1 exit raises it, `lp_linkerror` as a bringup raises it and as the answer to a LinkReset request in Reset raises it. The stub reports a request not answered within `req_bound`, an ignored one answered, a LinkReset or Disabled request that leads to a LinkError it did not request, and a `pl_clk_req` that falls before `lp_clk_ack` answered it. `+state_req=`: `basic`; `gated` with the clock-gating stub, which wakes itself with `lp_wake_req` for its own requests in Reset, LinkReset, Disabled and L1, and `remote_rsp_max` 30; `exit_pl` (`down_exit_on` PL, the stub reports an exit it did not ask for or one before `linkerror_min_res`), `exit_either`, `via_active` (`linkdown_via_active_pct` 100). `+clk_hold=0\|1` sets `clk_req_hold_bringup`. Any error fails it |
| `ucie_fdi_stall_exit_test` | stand-alone stalls around the Adapter's exits from Active, with dense stalls (`+stall_pct=N`, default 25), `pl_trdy` held high during them (`+stall_trdy_free=1` has it follow the policy) and a stub that acknowledges `+stall_ack=N` clocks after the flit boundary (default 40); with `+hold_present=1` the stub presents flits without waiting for `pl_trdy` and keeps a presented flit up through `pl_stallreq` until it transfers (legal: r3.0 §10.2.4, §10.3.2 rules 6 and 7), and the run must see such a flit accepted: `+stall_exit=directed` issues Retrain, LinkReset, Disabled, a mid-flit LinkError and a LinkError at a flit boundary while a stall waits for `lp_stallack`, then a PM entry and exit after one; `req` has the stub request LinkReset while an Adapter Retrain waits for one, raise `lp_linkerror` while an Adapter LinkReset waits, and request Disabled during one; `le_drop` has the stub raise `lp_linkerror` during a stall and drop it a clock later, before LinkError is reported, with a LinkReset or Disabled request in its place, with no event running and while an Adapter Retrain waits for the stall, and the link must still leave Active for LinkError and come back up (the Adapter has seen the assertion; LinkError has priority, r3.0 §10.3.3.8); `le_mid` (below 256 B) enters Adapter LinkErrors mid-flit while a stall waits for `lp_stallack` with a TX flit part-way (`stall_mid_pct` 90, `pl_trdy` random at 25 % meanwhile), up to 40 tries until 3 cut the stub inside a flit with `pl_stallreq` up, and fails unless one does; `+le_stall_drain=1` (any mode) sets the model's `le_stall_drain`, so the Adapter drains the Protocol Layer in LinkError and abandons the handshake on the exit to Reset (by default it abandons it on entry); `+keep_partial=1` (any mode) has the stub keep such a flit presented in LinkError instead of withdrawing it, as a Protocol Layer that cleans up its data path later may (§10.3.3.7 sets no time), and with the drain finish it and acknowledge at its boundary (rule 4), and `le_mid` then fails unless a flit was drained to its end; `+le_ignore=1` (any mode) has the stub keep the flit presented but take no `pl_trdy` outside Active and never acknowledge in LinkError, which r3.0 allows (§10.3.3.7 requires the upper layer to clean up "even if pl_trdy is not asserted", not to acknowledge); with it, or without the drain, `le_mid` fails unless a handshake was abandoned; `random` adds nothing but a random acknowledge delay (0..N); each then runs the cov test's events. Fails if the status leaves Active for Retrain, LinkReset or Disabled with the handshake under way, or `pl_stallreq` is still high once LinkError has gone to Reset, or the model drives `pl_trdy` in LinkError but to drain (with `pl_stallreq` high and `lp_stallack` low a clock before), and, with `+stall_ack` 20 or more, if a LinkError (at a flit boundary, or answering `lp_linkerror` in `req`) waits for `lp_stallack` (§10.3.3.7); FDI-R43 checks `pl_trdy` outside Active. `+trdy_le_stall=1` has the top force `pl_trdy` high for a clock in LinkError during a stall handshake, which r3.0 allows (Table 10-3) and FDI-R43 must accept (it implies `+le_stall_drain=1`) |
| `ucie_fdi_reuse_test` | the model as a second consumer uses it, on the events test plus three LinkErrors, `+reuse=`: `passive` passive mainband and link-state agents beside the active model, whose flits must match the active monitor's one by one, with the same cancels, stalls and abandoned flits and no error; `two_link` a second link (FDI 1, its own link-state interface) whose state must move by itself, and the instance plusarg `+ucie_le_mid_flit_pct@uvm_test_top.env1.lsm=0` reaching link 1 only; `mirror` and `park` the mirrored mode (`n_phy` 2), FDI 1 reporting FDI 0's status (and stalled before the L1 entry, the top acknowledging for it), or Reset, every clock; `restart` a `sw_restart_delay` of 777 set in the cfg (or `+expect_restart=N` with the plusarg) standing, every restart on the Adapter's own decision (`restart_on` SW) taking at least that long. In every mode the stub samples `pl_protocol` and `pl_protocol_flitfmt` in Reset before requesting Active and checks `pl_stream` |
| `ucie_fdi_neg_test` | the model's checks against one deliberate violation (`+neg=dllp\|retimer\|stream\|nop_tx\|corrupt_mid\|corrupt_h0\|corrupt_proto\|clk_ack\|irdy_reset\|wake\|wake_held\|xfer\|trdy_down\|trdy_le\|le_exit\|rx_inactive\|clk_exit\|le_after\|level\|inband_active\|held_forever\|no_restart\|wake_down\|wake_le\|unanswered`): the rule that must catch it (FDI-R62, R63, R64, R45, R59, R60, R61, R18, R44, R16, R16, R43, R43, R43, R49, R35, R22, R21, R20, the driver's refusal, R33, R33, R16, R16, the stub's answer checks) has to fire, as often as the violation is made, and its errors are expected; `corrupt_mid` and `corrupt_h0` need an FDI of 128 B or less. `nop_tx` is a NOP flit (Protocol ID 00b) on the default Streaming stream. `clk_ack` is an `lp_clk_ack` pulse without `pl_clk_req`, `irdy_reset` a flit presented through LinkReset and Disabled into Reset, `wake` an Active request in Reset with `lp_wake_req` never raised, `wake_held` the same with `lp_wake_req` held through LinkError and dropped on entry to Reset, over a bringup and three LinkErrors (four reports). Adapter faults the top forces: with `xfer` `pl_trdy` high for a clock while a flit waits in Retrain (256 B or more), with `trdy_down` the same with no flit presented, with `trdy_le` `pl_trdy` high for a clock in LinkError with no stall handshake, with `le_exit` Reset for a clock while the stub holds `lp_linkerror` in LinkError (the LinkError re-entered from that Reset without `pl_clk_req` also draws FDI-R21, expected too), with `rx_inactive` `pl_rx_active_req` low in Active while flits go on, with `clk_exit` `pl_clk_req` low through LinkReset -> Reset, with `le_after` Reset for a clock after a LinkError from Reset reported before its `pl_clk_req` was acknowledged, with `level` `pl_phyinrecenter` high for 40 clocks in Reset with no `pl_clk_req`. `inband_active` asks for `LSM_EV_INBAND_DROP` in Active, which the driver refuses with an error (`pl_inband_pres` falls only in Reset). `held_forever` holds an Active request from a LinkReset into Reset for good, so the stub never asks to leave Reset; `no_restart` waits, with `restart_on` PL, for a NOP->Active the stub never gives; both with `req_timeout` 3000. `wake_down` requests LinkReset after a NOP in Reset (link left down) with no `lp_wake_req`, `wake_le` raises `lp_linkerror` there with none (r3.0 §10.2.3.1); `unanswered` sets `react_en` 0, so the stub's own checks must report its LinkReset request in Active and its `lp_linkerror` as unanswered (two reports, `req_bound` 300) |

Knobs: `+beat_bytes=32|64|128|256|512|768|1024`, `+trdy=always|random|bursty|holes`, `+n_flits=N`, plus
the model's plusargs. A run passes when the simulator exits 0 and the log reports no `UVM_ERROR`
and no `UVM_FATAL`; otherwise `make run` prints `FAIL:` with the log path (and the simulator's
exit status when it is not 0) and exits non-zero. Verilator
needs `--vpi` and uses `dv/uvm_dpi_verilator.cc`, and
solves `randomize()` with z3 (on `PATH`, or `VERILATOR_SOLVER="<z3> --in"`).

## Known limits

- One flit format: Latency-Optimized 256B with optional bytes (Format 6), as laid out
  for Streaming and CXL.cachemem. Streams of PCIe, CXL.io and Management Transport, whose
  Format 6 layouts differ (r3.0 Figures 3-23, 3-26), are refused, and Management flits are
  not modelled. No 68B or Standard 256B formats, no Raw Format.
- FDI widths up to 1024 bytes (four flits per clock). UCIe r3.0 §10.3.1 also allows
  wider multiples of 256 B; `MAX_BEAT_BYTES` would grow with them. 32 B is accepted, though
  the NBYTES note does not recommend it.
- `pl_error` is a framing error the Adapter detects in Flit mode with Retry: it
  cancels the half and retrains. Raw Format's forwarding of the Physical Layer's
  `pl_error`, and its escalation without Retry, are not modelled.
- `lp_corrupt_crc` is checked, not acted on: corrupting the CRC and overwriting the
  Retry buffer are the Adapter's internals, and what the next flit carries is the
  protocol layer's.
- From 256 B up a half cannot be cancelled on its own: the interface has one cancel
  cycle per transfer. Cancel plans that name a half become whole-transfer cancels.
- No sideband: the configuration channel (`pl_cfg`/`lp_cfg` and their valid and
  credit signals) is not on the interfaces. Nor are the optional vendor-defined
  signals or the Management Transport ones.
- No DLLPs and no Retimer: `pl_dllp*` and `pl_retimer_crd` hold 0. No error
  reporting: `pl_cerror`, `pl_nferror` and `pl_trainerror` hold 0. No L2: `pl_phyinl2`
  holds 0.
- The negotiated protocol, speed and width are static for the test; one stream ID per
  FDI, so two protocol stacks multiplexed on one FDI are not modelled.
- Power management does not yet follow UCIe r3.0; a follow-up will make it
  spec-faithful, keeping today's behaviour only as an option, off by default. Today:
  - The Adapter enters L1 on its own (`LSM_EV_L1_ENTRY`, `ucie_lsm_l1_seq`), after the
    stall handshake, without `lp_state_req` = L1. r3.0 has the Protocol Layer request PM
    entry "by transitioning lp_state_req to L1 or L2 encoding" (§10.2.9) and the
    Adapter move to L1 "based on observing lp_state_req == L1" (§10.3.3.2 rule 2).
  - L1 and L2 requests from the Protocol Layer are not answered: no PM entry on them,
    no PM Response or Active.PMNAK (§10.2.9), so Table 10-4's L1 and L2 rows, and its L2
    column, never apply. `pl_phyinl2` holds 0.
  - The Protocol Layer's PM exit is triggered by `lp_wake_req` in L1 (one that comes with
    `lp_linkerror` or a LinkReset or Disabled request is that request's wake handshake
    instead): the Adapter answers the wake, raises `pl_clk_req`, moves to Retrain and
    waits for the Active request. In r3.0 "PM exit is initiated by the Protocol Layer
    requesting Active on FDI" (§10.2.9); `lp_wake_req` only ungates the Adapter's clocks
    (§10.2.3.1). The exit the remote die starts follows §10.2.9 (`pl_clk_req`, Retrain,
    then the Protocol Layer's Active request).
- The Active request that ends LinkError, LinkReset or Disabled is answered only with
  `down_exit_on` PL or EITHER; by default the Adapter leaves those states for Reset on
  its own after the dwell. In the Reset that follows, a request held on from there is no
  request to leave Reset (§10.3.3.1 rule 1); the model waits for NOP, then Active. The
  16 ms minimum LinkError residency is scaled down (`linkerror_min_res`).
- One Protocol Layer per Adapter: the LinkReset and Disabled handshakes of several
  Protocol Layers sharing an Adapter, and the RDI state they resolve to (§10.3.3.8), are
  not modelled.
- In the mirrored mode (`n_phy` 2) both FDIs report the same state, or the one not
  followed stays in Reset (`park_idle_phy`); they do not train independently (use one
  link-state agent per FDI for that). One link-state agent takes at most two FDIs.
- The model does not check what is in a flit beyond the Adapter-owned bytes; that is
  the protocol layer's.
- The mainband monitor, judging from the interface alone, drops partial flits only when
  `pl_state_sts` goes from Active to LinkError. A LinkError entered from Retrain, or from
  Reset with the Receiver active, while an RX flit is part-way is not seen as abandoning
  it (the model's own driver never does this, but a real Adapter watched by a passive
  agent may). A whole RX flit whose cancel cycle is the first clock of LinkError, and
  which that cycle does not cancel, is published on `ap_rx` as delivered, though the
  Protocol Layer may drop it as it cleans up its data path (§10.3.3.7).
- Stand-alone stalls (`stall_pct`, off by default) are stress beyond UCIe r3.0: in Flit
  mode the stall handshake "must only be used when exiting Active State to a PM state"
  (§10.3.2), so a Protocol Layer may treat `pl_stallreq` as the start of a PM entry. The
  model finishes one under way (the Protocol Layer acknowledges, then both signals fall)
  before it leaves Active for Retrain, LinkReset or Disabled. LinkError does not wait for
  it (§10.3.3.7: "It is not required to complete the stallreq/ack handshake before
  entering this state"; Table 10-3 `lp_linkerror`: "immediate action"): the model enters
  LinkError at the next flit boundary, or at once mid-flit. From the decision to enter
  LinkError to the status change (two clocks plus the end of a started flit) the link is
  still Active with `pl_stallreq` up, and a flit presented then gets no `pl_trdy`: the model
  reads §10.3.3.7 as ending rule 7's "must be accepted ... until the rising edge of
  lp_stallack" once it has decided on LinkError, as a mid-flit LinkError abandons a flit.
  In LinkError the Adapter never waits for `lp_stallack`: §10.3.3.7 requires the upper layer
  there "to internally clean up the data path, even if pl_trdy is not asserted", not to
  acknowledge, so a Protocol Layer that never takes `pl_trdy` or acknowledges there is
  legal. By default (`le_stall_drain` 0) the model does not perform the handshake in
  LinkError: `pl_stallreq` stays high in the first clock that shows LinkError and falls,
  unacknowledged, on the next (the model reads `pl_state_sts` as sampled, so it acts a
  clock after the status change), and `pl_trdy` stays low. With `le_stall_drain` it does
  ("If the lower layer decides to perform a pl_stallreq/lp_stallack handshake, it must
  provide pl_trdy to the upper layer to drain the packets"):
  from the clock after the status change until `lp_stallack` it
  drains the Protocol Layer, `pl_trdy` as during any stall (held high, or by policy with
  `stall_trdy_free`), the transfers dropped, never delivered ("these packets could be
  dropped and not transmitted on the Link"; Table 10-3 `pl_trdy`; FDI-R43); a Protocol
  Layer that holds a flit a mid-flit LinkError cut can so finish it and acknowledge at its
  boundary (rule 4), and a handshake still open when the link leaves LinkError is abandoned
  with the move to Reset, `pl_stallreq` falling and `pl_trdy` low on the clock the status
  changes. r3.0 does not say how a handshake left incomplete in LinkError ends; rule 3
  lets `pl_stallreq` fall before `lp_stallack` only "when domain is in reset", and the
  model reads §10.3.3.7's "not required to complete the stallreq/ack handshake" as
  allowing that fall in LinkError or on its exit to Reset. FDI-R08 accepts it there, and
  FDI-R57 does not run in LinkError. The default keeps `pl_trdy` low outside Active:
  draining gains nothing from a Protocol Layer that cleans up in LinkError, and a
  checker that frames every `lp_valid & lp_irdy & pl_trdy` as a flit, whatever the state,
  would take drained transfers for flits.

## The AoU bench as a consumer

The AoU bench (`hw/ip/aou/dv`) compiles the model from `uvm/sources.toml` (its sim
config's `source_lists`), and its regressions run on it unchanged. It adds
`aou_fdi_layer_pkg`, which is also a complete example of a protocol layer on top:

- `aou_bringup_if`: the DUT's bringup pins that are not FDI (PHY select, software
  pins, status outputs, internal triggers).
- `aou_fdi_layer`: one component and a `ucie_lsm_observer`. It drives those pins
  (idle on reset, `pulse_sw()`) and samples them in the same `observe()`, steps the reference model of the DUT's bringup
  controller (`aou_bringup_model`, with its own comparison slack `ref_slack`, apart
  from the model's liveness bounds) every clock, checks that the DUT never requests L2,
  and holds the coverage collectors. Its env configs draw `sw_restart_delay` in
  [50:1500] per run, so a DUT that asks anything of the link meanwhile is caught at many
  delays; `+ucie_sw_restart_delay=N` fixes it. The bench's envs create it and call
  `attach(lsm)` in `connect_phase`.
- `aou_fdi_cov` (a `ucie_fdi_cov`, set on every mainband monitor) and `aou_lsm_cov`
  (sampled by the layer and the reference model): feeding the bench's coverage
  service.
- `aou_t1_axi4pc_ctl`, the Axi4PC control, is a second observer.

Its top ties the Protocol Layer outputs the DUT has no pins for: `lp_stream` to the
link's stream, 04h (Stack 0 Streaming; r3.0 §10.2.1 allows the tie-off), so FDI-R64
holds, and the rest to 0. The model's Adapter outputs the DUT has no pins for stay
open.

The model's own covergroups stay on in the AoU bench (their run-time cost is within noise
on both simulators). They go into the simulator's coverage database beside the bench's,
not into the bench's coverage service, so `make fc_report` does not count them; URG
shows them. `+ucie_fcov=0` turns them off.

Its two-PHY builds use the mirrored mode (`n_phy` 2, `active_phy`, `park_idle_phy`), as
the DUT follows one of two FDIs through one set of handshakes. Its RX flits from
`ucie_flit_seq` keep the default Protocol ID 11b. No build of it uses a 768 B FDI. Its
tests print `ucie_rule_log` after the bench's own rule ledger.

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
