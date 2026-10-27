<!--
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2026 Tenstorrent USA Inc
-->

# AOU_FDI_CHECKER design

Why `AOU_FDI_CHECKER.sv` is built the way it is. Sections follow the module's
order, so a `See DESIGN.md "<name>"` pointer in the RTL resolves to a heading
here. The module carries only the constraints an editor of a line must not
violate; [`../README.md`](../README.md) carries the user-facing summary.

## Contents

- [Overview](#overview)
- [The checker's package](#the-checkers-package)
- [Interface](#interface)
- [Elaboration-time configuration guards](#elaboration-time-configuration-guards)
- [Selectable check groups](#selectable-check-groups)
- [Direction observation](#direction-observation)
- [Flit reconstruction](#flit-reconstruction)
- [Flit field extraction](#flit-field-extraction)
- [Structural well-formedness rules](#structural-well-formedness-rules)
- [Message lengths](#message-lengths)
- [Message-start consistency](#message-start-consistency)
- [Activation handshake model](#activation-handshake-model)
- [Credit accounting](#credit-accounting)
- [Spending](#spending)
- [Violation matrix and capture](#violation-matrix-and-capture)
- [Optional activation-status cross-check](#optional-activation-status-cross-check)
- [Cross-check reporting](#cross-check-reporting)
- [Simulation-only reporting](#simulation-only-reporting)
- [Decisions reversed](#decisions-reversed)

## Overview

A synthesizable AXI-over-UCIe protocol checker for one single-PHY UCIe FDI
link: the AoU v0.7 wire format the design implements, judged by the v0.8
activation and credit-ordering rules (v0.8 decides where the two differ).
Section numbers here are v0.8's unless marked v0.7; the wire-format package
cites v0.7's. It observes either or both directions -- the LP stream the die
under observation drives, the PL stream its peer drives -- reconstructs 256-byte
flits and reports protocol violations on hardware status ports: a sticky
per-class vector, a frozen first-violation capture record, a per-direction flit
count and a one-cycle trigger. It observes only: it never drives the link and
reads no internal signal of the design, so one instance serves the simulation
harness, an FPGA bench and an emulator.

**Independence from the design is deliberate.** The checker imports nothing from
the RTL it judges. The wire format is stated in its own `aou_fdi_wire_pkg` from
the specification ([The wire-format package](#the-wire-format-package)); the
activation and credit rules are written from the specification and are *not*
shared with `AOU_ACTIVATION_CTRL` or the `AOU_*_CRD_CTRL` modules. A checker that
took either from the modules it observes could only find them disagreeing with
themselves; the two agreeing proves nothing and the two disagreeing is the
finding. A change that "removes the duplication" leaves the checker passing and
unable to find anything. An earlier revision imported the wire format from
`packet_def_pkg` on the argument that a second copy is a maintenance hazard; it
is, but a wrong granule count or field position in the design package would have
been invisible to the checker, which is the worse hazard.

Rules covered: the structural encodings (MSGTYPE, MISCOP, ACTIVATIONOP, DLENGTH,
reserved-must-be-zero fields); message-start framing and the Activation
placement rule (4.4); the activation handshake (8.4); message and advertisement
ordering (8.4); credit accounting across four planes (6); the FDId (4.3.1),
plane-range (6.2, 6.4) and plane-map (3, 6.2) configuration rules; and the
optional activation-status cross-check, the one finding about the design's
opinion rather than the traffic.

**The shape of a rule.** Each rule reads the completed flit during the one
consume cycle, takes its fields from the extraction stage, and drives its own row
of the per-granule violation matrix. Adding a rule touches neither reconstruction
nor reporting. The cross-check is the exception: off by default, reading inputs
nothing else reads, reporting on a surface of its own.

## The checker's package

`aou_fdi_checker_pkg.sv` holds the checker's opinions and nothing else: the
protocol violation codes and class count, the cross-check codes and count, the
cross-check settling and convergence defaults, and the rule groups and named
profiles. It is ordered ahead of the module in both filelists and is shared with
nothing outside the checker.

The codes live in a package rather than the module because three consumers
decode reports -- the module, the standalone testbench and the loopback helper --
and each once wrote them out by hand. That was survivable while every check was
unconditional (drift cost a mislabelled failure message); once check groups were
selectable, a bench told a class is enabled when it is not would read silence as
a pass. `CHK_PROFILE_CLASSES_*` states what each profile must resolve to on
`O_CHECK_ENABLED` independently of the module's resolution, so a test comparing
the two is a comparison rather than a tautology.

`aou_fdi_checker_pkg.py` mirrors the package for the two Python consumers, and
`scripts/check_checker_code_space.py` fails if the two disagree on any value or
either holds a name the other lacks. Generating the Python was rejected as more
moving parts for the same guarantee; the script refuses to skip a declaration it
cannot read, and its `--self-test` proves a mismatch fails. The testbench's own
wire-format constants in `tests/aou_flit.py` are deliberately *not* mirrored:
written from the specification separately, they are what lets a layout test fail
rather than pass by construction.

### The wire-format package

`aou_fdi_wire_pkg.sv` is AoU v0.7 as the checker reads it, each value citing its
section: flit geometry and granule positions (4.2, Figure 4); the protocol
header (4.3, Figure 5); first-byte fields and the MSGTYPE, MISCOP, DLENGTH and
ACTIVATIONOP encodings (Tables 1, 15, 27, 5.4); message lengths (Tables 2-13,
19, 26); the credit encoding (Table 18); and the two Misc layouts (Figures 19,
20). The Misc layouts are derived, not stated: v0.7 5.7's (v0.8 5.8) convention -- bytes count
up, bits count down, fields MSB-first -- is `wire_bit(s)`, so ACTIVATIONOP is
"stream bits 7-10" and the grant's twenty credit fields are "three bits each in
class-then-plane order from stream bit 7, two for WriteResp". The fields that
straddle a byte boundary fall out of the convention rather than being
reassembled by hand. Loop bounds in the decode are constants, because a bound
that is a variable -- even one constant after unrolling -- stalls some synthesis
front ends. The package is not mirrored into Python.

## Interface

Every way in or out is a port or a parameter: no hierarchical reference, no file
I/O. That is what lets one source serve every platform.

### Parameters

| Parameter | Default | What it is |
|-----------|---------|------------|
| `FDI_IF_BYTES` | 32 | FDI bus width in bytes: 32, 64 or 128 (UCIe 3.0 10.2). Others are rejected at elaboration rather than mis-parsed. |
| `FLIT_SEQ_WD` | 32 | Per-direction flit sequence counter width; 32 bits lasts ~71.6 minutes at one million consumed flits per second. |
| `VIOL_CNT_WD` | 16 | Width of the aggregate violation counter. Each direction whose flit has a finding contributes one, so a cycle can add two. Distinguishes "a few" from "a flood". |
| `RP_COUNT` | 4 | Planes both dies drive (6.2 makes the count symmetric), in the observed die's numbering; 1..4. |
| `FDID` | 0 | The FDId (4.3.1) of the bridge pair this instance watches; 0 is the single-bridge case; 0..3. |
| `CRD_CAPACITY` | 2048 | Outstanding credit one shadow counter can hold: the checker's capacity, not a protocol quantity ([Credit accounting](#credit-accounting)). At least 1. |
| `CHK_PROFILE` | `CHK_PROFILE_FULL` | Named posture from the package ([Selectable check groups](#selectable-check-groups)). |
| `STRUCT_EN`, `FRAMING_EN`, `ACT_SEQ_EN`, `MSG_ORDER_EN`, `CREDIT_EN` | from profile | One enable per rule group, overridable to depart from a profile in one group. |
| `OBS_LP_EN`, `OBS_PL_EN` | 1 | Which streams this instance observes ([Direction observation](#direction-observation)). |
| `XCHK_LP_EN`, `XCHK_PL_EN` | 0 | Cross-check enables, one per die ([Optional activation-status cross-check](#optional-activation-status-cross-check)). |
| `XCHK_SETTLE_CYCLES` | 4096 | Cycles both views must hold still before a steady-state comparison is believed. Defaulted from the package so the testbench cannot wait out a tolerance the module no longer has. |
| `XCHK_CONVERGE_CYCLES` | 1024 | Cycles the design gets to follow once the checker's model has moved. Same source. |

Derived geometry (`FDI_IF_WD`, `BEATS_PER_FLIT` = 8/4/2) is `localparam`: a
latency-optimized flit is 256 bytes at every width. Both cross-check enables
default off: the comparison is across a configuration-dependent pipeline, and a
first user must not be handed a feature whose tolerances nobody has checked
against their bench. They are separate because benches are asymmetric -- a
third-party peer has no status wires to compare against. The intervals come from
[The budget behind the defaults](#the-budget-behind-the-defaults); **tighten
only with evidence**.

### Clock, reset and the two flit streams

| Port | Dir | Width | What it is |
|------|-----|-------|------------|
| `I_CLK`, `I_RESETN` | in | 1 | Observed clock; active-low asynchronous reset. |
| `I_LINK_RESET` | in | 1 | Starts a new observed-link epoch (below). |
| `I_LP_VALID`, `I_LP_IRDY`, `I_PL_TRDY` | in | 1 | Outbound handshake: a beat counts only when all three are set. |
| `I_LP_DATA` | in | `FDI_IF_WD` | Outbound beat. |
| `I_PL_VALID` | in | 1 | Inbound handshake: FDI gives a receiver no backpressure, so valid alone. |
| `I_PL_DATA` | in | `FDI_IF_WD` | Inbound beat. |
| `I_PL_FLIT_CANCEL` | in | 1 | Retracts the 128B half whose last beat transferred the previous cycle (UCIe 3.0 10.2). FDI has no `lp_flit_cancel`. |

The outbound stream is qualified on the full handshake because the simulation-only
decoder's valid-only sampling is correct solely because the harness ties TRDY
high; on a bench with backpressure it would shift every following beat and turn
compliant traffic into false violations. Unobserved streams keep their ports and
are tied off at the instance.

`I_LINK_RESET` clears the reconstruction's beat index and half-flit state (not
the buffer contents, which nothing reads before every beat is rewritten and
whose clear would cost a mux leg on four thousand flops), the message carry,
activation events, credit counters, pending grant state, and the cross-check's
timers and comparison-reached evidence. It preserves findings and sequence
numbers so the previous epoch stays diagnosable. An integration asserts it when
either endpoint resets the link.

### Configuration

| Port | Dir | Width | What it is |
|------|-----|-------|------------|
| `I_CFG_RP_DEST_RP` | in | 4x2 | Entry p: the wire plane a message from local plane p carries, i.e. the peer's name for it. Matches the `DEST_RP` SFR and the credit controllers' `I_RP_DEST_RP`. |

Configuration is supplied, never inferred: a checker that learned it from the
traffic it judges could not tell misconfiguration from compliance. One map
serves both dies because the protocol requires the two to be programmed as
inverses of each other; the active entries must be distinct ([The plane map is
one-to-one](#the-plane-map-is-one-to-one)). There is no credit-management-type
input: the v0.8 8.4 windows depend on the message or credit class, not on a
mode ([Credit accounting](#credit-accounting)).

### Cross-check inputs

| Port | Dir | What it is |
|------|-----|------------|
| `I_LP_ACT_ST_DISABLED`, `I_LP_ACT_ST_ENABLED` | in | The observed die's own view. |
| `I_PL_ACT_ST_DISABLED`, `I_PL_ACT_ST_ENABLED` | in | The peer's own view. |

**Comparison only.** Read by the comparator and nothing else -- no rule, no
counter, not the activation model even to break a tie. A checker that let the
design's status inform its model would agree with the design by construction.
They pair with `AOU_CORE_TOP`'s two `O_AOU_ACTIVATE_ST_*` outputs, the only
activation state the delivered core brings out, so the cross-check needs no RTL
change; it also means ACTIVATE and DEACTIVATE both read `2'b00` and are
indistinguishable, leaving the DISABLED and ENABLED boundaries -- where the
disagreements that matter are. Tying these low with the cross-check enabled is
reported as a steady mismatch: a checker asked to compare against nothing says
so.

### Violation reporting

| Port | Dir | Width | What it is |
|------|-----|-------|------------|
| `O_VIOLATION` | out | `VIOL_CLASS_CNT` | Sticky, one bit per class, until `I_ERR_CLEAR`. |
| `O_VIOLATION_TRIGGER` | out | 1 | One-cycle pulse when any finding occurs; what makes the module useful on an emulator. |
| `O_VIOLATION_CNT` | out | `VIOL_CNT_WD` | One aggregate saturating count of flits with a finding. Each direction contributes independently, so simultaneous LP and PL findings add two. Keeps counting after the capture freezes so the flood is visible. |
| `O_CAPTURE_VALID` | out | 1 | A capture record is held. |
| `O_CAPTURE_CODE` | out | `VIOL_CODE_WD` | Class of the captured finding. |
| `O_CAPTURE_DIR` | out | 1 | 0: outbound (LP). 1: inbound (PL). |
| `O_CAPTURE_FLIT_SEQ` | out | `FLIT_SEQ_WD` | Sequence of the offending flit. |
| `O_CAPTURE_GRANULE_IDX`, `O_CAPTURE_GRANULE` | out | 6, 40 | Offending granule and its contents; header findings name granule 0. |
| `O_CHECK_ENABLED` | out | `VIOL_CLASS_CNT` | Constant: which classes this instance checks, in `O_VIOLATION`'s bit space. |
| `O_LP_FLIT_SEQ`, `O_PL_FLIT_SEQ` | out | `FLIT_SEQ_WD` | Flits that completed on the wire; cancelled and partial flits do not count, nor do the adapter's NOP flits inbound. |

The capture freezes on the first finding because protocol errors cascade and the
tenth report describes a consequence. The count is of flits, not (granule,
class) hits: a flit breaking one rule in thirty granules is one event, and the
hit count would need to reduce 720 matrix bits per direction, 1440 across both,
for a number nobody read.

| Code | Name | Meaning |
|-----:|------|---------|
| 0 | `VIOL_MSGTYPE` | Reserved or undefined MSGTYPE (Table 1). |
| 1 | `VIOL_MISCOP` | Reserved or undefined MISCOP (Table 15). |
| 2 | `VIOL_ACTIVATIONOP` | Reserved or undefined ACTIVATIONOP (Table 27). |
| 3 | `VIOL_DLENGTH` | Reserved DLENGTH encoding (5.4). |
| 4 | `VIOL_RSVD_NONZERO` | Reserved field non-zero (Tables 2, 3, 10-13, 18; v0.7 Table 26). |
| 5 | `VIOL_MSGSTART` | MsgStart inconsistent with message lengths (4.4). |
| 6 | `VIOL_ACT_SEQ` | Illegal activation sequencing (8.4). |
| 7 | `VIOL_MSG_ORDER` | Credited message outside its window: before the sender's ActivateAck is received (9.2), a request after its own DeactivateReq, any after DISABLED (8.4). |
| 8 | `VIOL_CRD_UNDERFLOW` | Shadow credit would go negative (6). |
| 9 | `VIOL_MISC_PLACEMENT` | Activation message not at granule 0, including a second Activation message in the same flit (4.4). |
| 10 | `VIOL_ADV_ORDER` | Credits advertised before the advertiser's ActivateAck or in DISABLED (8.4). |
| 11 | `VIOL_RP_RANGE` | Plane field naming a plane the link lacks (5.2.2, 6.2, 6.4). |
| 12 | `VIOL_FDID` | Flit whose FDId is not the bridge this instance watches (4.3.1, 6.4). |
| 13 | `VIOL_CRD_OVERFLOW` | Advertisement took a shadow counter past `CRD_CAPACITY`. |
| 14 | `VIOL_RP_MAP` | `I_CFG_RP_DEST_RP` maps two planes onto one (3, 6.2); reported with every flit until fixed. |

The vectors are exactly `VIOL_CLASS_CNT` bits wide. Adding a rule to an existing
class changes no interface, but adding a new class changes the status-vector
width (and can change the code width at a power-of-two boundary). Cross-check
findings have their own space so a false positive there can never freeze or mask
a protocol finding. `O_CHECK_ENABLED` is the same space read as a question: a
clear bit in `O_VIOLATION` means "nothing found" only where the same bit is set
here. It is a port rather than a parameter read back because a bench can only
assert what the instance elaborated to.

### Cross-check reporting

| Port | Dir | Width | What it is |
|------|-----|-------|------------|
| `O_XCHK_VIOLATION`, `O_XCHK_TRIGGER`, `O_XCHK_CNT` | out | 2, 1, `VIOL_CNT_WD` | The same shape as the protocol surface, none of the same registers. |
| `O_XCHK_CAPTURE_VALID`, `O_XCHK_CAPTURE_CODE`, `O_XCHK_CAPTURE_DIE` | out | 1, 1, 1 | Own capture record; die 0 is the observed die, 1 its peer. |
| `O_XCHK_CAPTURE_CHK_ST`, `O_XCHK_CAPTURE_OBS_ST` | out | 2, 2 | Both views at the finding, `{enabled, disabled}`: "they disagree" is not actionable without knowing which way round. |
| `O_XCHK_CAPTURE_FLIT_SEQ` | out | `FLIT_SEQ_WD` | The die's stream position: when, not what, since no flit causes this. |
| `O_XCHK_COMPARED` | out | 2 | Bit d: a settled comparison has actually been made for die d. |

| Code | Name | Meaning |
|-----:|------|---------|
| 0 | `XVIOL_TIMEOUT` | The design never converged on the checker's state: look at the receiving die's decode path. |
| 1 | `XVIOL_MISMATCH` | Both views settled and still disagree: look at the state machine. |

Nothing here can set, count, trigger or freeze anything in the protocol domain,
and vice versa; that containment is what makes the feature safe to enable by
parameter -- the worst a false positive can do is fill this surface.
`O_XCHK_COMPARED` is sticky until reset, untouched by `I_ERR_CLEAR` and not part
of the status: it exists because a comparison that never happened -- the link
never settled, the inputs were never wired -- is otherwise indistinguishable from
one that agreed. It is the first thing a regression enabling the cross-check
should assert.

### Clearing

| Port | Dir | What it is |
|------|-----|------------|
| `I_ERR_CLEAR` | in | Clears error status in both domains, and nothing else. |

The rule is whether zeroing could change a later verdict; error status cannot,
model state can. Cleared: the sticky vectors, counts and capture valid bits, and
`r_xchk_reported` (which suppresses a repeat and so is status). Not cleared: the
shadow credit counters (a clear that resynchronised them would hide an ongoing
underflow), the message-start carry, the activation events, the cross-check
timers, and `O_XCHK_COMPARED`. The capture records' fields are left in place --
they mean nothing without the valid bit, and zeroing them is a mux on every flop
for a value no reader may use. A finding coincident with a clear wins. One clear
serves both domains because separate freezes are about one domain not displacing
the other's findings, not about who may clear them.

## Elaboration-time configuration guards

A checker that silently mis-parses a configuration it was not written for is
worse than none, so each of these is a compile error: `FDI_IF_BYTES` in
{32, 64, 128} and `TWO_PHY` undefined (the two-PHY split is not supported; the
three widths give 8, 4 and 2 beats, so a 128B half is always whole beats and
needs no guard of its own); `RP_COUNT` 1..4 and `FDID` 0..3 (both two-bit fields on
the wire); positive counter widths; `CRD_CAPACITY` at least 1; `CHK_PROFILE` a
posture the package names (an unknown one would otherwise fall through to the
full set and elaborate more than was asked); every enable 0 or 1 ("2" would
read as enabled and look deliberate); every violation class in exactly one
group; at least one rule group enabled; both cross-check intervals at least 1
(zero would be the naive equality comparison); at least one stream observed,
and the two-ended rules not asked for with one; and `MAX_MSG_G` no longer than a
flit, since one level of carry is only enough while no message spans two.

## Selectable check groups

Five groups -- structural encodings, message-start framing, activation
sequencing, message ordering, credit accounting -- each defaulting to enabled,
so an instantiation that says nothing gets everything. Groups rather than
per-class enables because the rules are not independent and per-class enables
would invite combinations with unclear prerequisites.

| Profile | Runs |
|---------|------|
| `CHK_PROFILE_FULL` | Every group. |
| `CHK_PROFILE_NO_CREDIT` | All but credit accounting, the largest group by far. |
| `CHK_PROFILE_WELL_FORMED` | Structural and framing: what a single flit can be judged by with no model of the link. Named for what it keeps; the posture a partner-chiplet or one-stream bench is left with. |
| `CHK_PROFILE_STRUCTURAL` | Structural alone; per direction it retains one pending flag and the 40-bit first granule needed to check a credit grant spanning G47 to the next flit's G0. |
| `CHK_PROFILE_LINK_MODEL` | The complement of well-formed: for a bench that trusts the peer's encoder and does not want forty-eight encoding reports between it and an activation bug. The only posture that suppresses a report whose logic something else still reads, so the one the tests lean on hardest. |

Profiles are named integers, not a bitmask, so a caller cannot ask for a
combination nobody has thought about; a wanted combination is reached by setting
one group's enable, which is a deliberate act. **Asking for nothing is the one
posture refused**: all five off would approve every flit, the one failure of
selectable groups that would not announce itself. A cross-check enable is no
escape, since it says nothing about the traffic.

### The prerequisites are derived, not asked for

The user says what to check; the module works out what that needs, because the
dependencies run against the obvious reading -- a rule's *output* qualifies rules
other than its own, so suppressing a report must not remove logic downstream
still consults. Stated in the module as a resolution because prose has already
proved able to hide it:

```
ACT_MODEL_EN     = ACT_SEQ_EN | MSG_ORDER_EN | CREDIT_EN | XCHK_LP_EN | XCHK_PL_EN
FRAMING_LOGIC_EN = FRAMING_EN | ACT_MODEL_EN | CREDIT_EN
```

- The activation model belongs to none of its four consumers (both
  activation-derived rules, credit accounting's consume window, each cross-check
  enable). The pairing that has to be tested is well-formed with a cross-check
  enabled, where only the cross-check asks for the model; a resolution missing
  the `XCHK_*` terms would compare a die's state against a model frozen at
  DISABLED.
- Message ordering is computed in the credit section from the credited-message
  decode and the consume window, without a counter; `CREDIT_EN=0` keeps those.
- The sequencing terms qualify what the model *believes*, so `ACT_SEQ_EN=0`
  gates the matrix row only; gating the terms would change the model, not the
  report.
- The encoding legality terms qualify which opcodes the model reads, so
  `STRUCT_EN=0` gates the five structural rows only; removing the terms would
  judge an undefined opcode against the state and report a sequencing violation
  for a message nobody could read.
- The framing claim is read by the activation and credit models, so one
  malformed flit yields one finding rather than three. `FRAMING_LOGIC_EN` is the
  term that can take state with it: with no consumer, the carry register, the
  claim network and the length tables go.

**Gated in two places.** At the violation matrix row, ANDed with the class's bit
of the same vector `O_CHECK_ENABLED` publishes, so a disabled class never sets a
bit, pulls the trigger, bumps the count or freezes the capture -- one place
decides all four. And at state with no remaining consumer, as the *load* enable:
the shadow counters and activation events are only ever reset when their derived
logic enable is off, which lets synthesis drop them and everything that fed only
them.
`w_teardown_done` is gated too, since it reads the events' next state and would
otherwise keep the event decode alive. The underflow term is gated at its source
as well as its row so the spend trees become unread. Message ordering owns no
state. Structural reporting retains the spanning-grant pending flag and first
granule while either structural or credit logic needs them; most of its other
decode remains when the activation model consumes it. The idiom is the
cross-check's -- an enable resolved to a constant and ANDed in, no generate
blocks, one way to disable a feature.

`O_CHECK_ENABLED` costs pins and buys two things: a bench can assert it got the
posture it asked for, and a reader of a record can tell "no violations" from
"not looking" -- the same principle as `O_XCHK_COMPARED`. A silently pruned
checker gets three independent defences: this output, the loopback regression's
insistence on the full set, and the testbench skipping rather than passing what
a posture excludes.

## Direction observation

Both directions run the same logic indexed by direction, so they cannot drift
apart as rules are added; the index is the value in `O_CAPTURE_DIR`. `OBS_LP_EN`
and `OBS_PL_EN` are for the board that brings out one stream, which previously
had to tie the other off and accept what the rules made of the silence.

The direction count is not parameterized: it is structural throughout the
module's per-direction arrays and the capture record, and would change the
interface for nothing. A disabled stream's beat qualifier is forced to zero
instead, so its buffer is only ever reset, the flit it would check is a constant,
and the extraction and rule cones reading it constant-propagate away,
`w_chk_go` and the flit count with them. Ports, code spaces and the capture
encoding are bit-for-bit unchanged:
**turning a direction off is not an interface change**, and a parameterized
count arriving should be pushed back on.

One declaration is load-bearing: `r_flit_data` is unpacked over direction and
packed within one, where every other per-direction array is packed throughout.
With direction packed, the variable beat write is arithmetic over one flat
vector and cannot be shown to stop at its own half, so both buffers survive
whatever the enables say; measured, the packed form removed 99 of the 2147 flops
an unobserved stream should remove. That is why an area claim here gets a number
rather than an argument.

### One stream cannot make a statement about two ends

Single-stream observation is legal with the structural and framing groups and
refused at elaboration for activation sequencing, message ordering, credit
accounting and either cross-check. Those are statements about both ends: an
acknowledge answers a request that crossed the other way, and advertisements
travel against the traffic they fund. A checker asked to make them from one
stream would be reporting on silence -- a confident-looking verdict that could
not have been reached. Observing neither stream is refused for the reason an
empty posture is. There is deliberately no output saying which streams are
watched, since nothing on the interface changes; an unobserved stream's flit
count stays at zero, and the loopback regression's demand for traffic in both
directions is written against exactly those counters.

## Flit reconstruction

A beat is accumulated only on a completed transfer: valid, IRDY and TRDY
outbound; valid alone inbound, where FDI gives no backpressure. The flit is
buffered and checked once complete. Figure 5 distributes MsgStart across bytes
62-65 and 190-193, so a quarter-streaming implementation could retain quarters
whose MsgStart follows their granules and process the others as they arrive.
This implementation instead uses one whole-flit window because framing and
Activation placement are flit-wide predicates, credit advertisements are summed
over the flit, and same-cycle credit netting combines both completed streams.
Beat zero is the low-order bits, so flit byte i is `[i*8 +: 8]`.

There is one buffer per direction. The check runs in the one cycle `w_chk_go` is
high -- second half done, no cancel this cycle, first half committed -- reading
the buffer combinationally, and every consumer samples at that cycle's edge. A
next-flit beat written at the same edge becomes visible one cycle later, and at
the widest bus the next flit cannot complete before the following edge, so a
second bank is unnecessary (an earlier claim to the contrary was corrected by
audit and a back-to-back test at every width). That one-cycle window is the
check pipeline's whole budget: it is why the framing rule is a parallel mask
rather than a walk, and why each direction has its own pipeline, since both can
complete a flit on the same cycle. The sequence counter advances at the consume
edge, so during the check `r_flit_seq` is the consumed flit's own number.

**The adapter's NOP flits are discarded, inbound.** UCIe 3.0 Table 3-4 gives
the Format 6 Streaming flit header's Protocol Identifier, bits [7:6] of flit
byte 0, and reserves 00b for a D2D Adapter NOP; Table 10-3 lets the adapter
forward one uncancelled and requires the protocol layer to discard it. A NOP is
all zeros below the header, so judged as a flit it reads as empty MsgStart, no
credit and FDId 0 -- benign to an instance watching bridge 0 and a `VIOL_FDID`
on every NOP to any other -- and it would count in `O_PL_FLIT_SEQ`. So a
completed inbound flit whose PID is 00b is consumed by the reconstruction
(`w_flit_done`) and not passed to the check stage or the counter (`w_chk_go`).
The outbound stream is not filtered: the protocol layer "must never set this to
00b", so an outbound flit saying NOP is the observed die's flit and is judged as
one. The delivered transmitter sends 11b.

**Cancellation is per 128B half, one cycle late** (UCIe 3.0 10.2, Figures 10-15
to 10-17). Each half is written provisionally into its slot; `r_half_done` marks
the one cycle in which a cancel may retract it; a cancel rewinds the beat index
to that half's start (a beat arriving that cycle is the first of whatever the
adapter sends next); `r_half0_ok` remembers a committed first half, and the flit
is consumed when the second half commits with the first already committed. That
pairs an original first half with a replayed second (10-16, 10-17) and discards
a re-sent first half that the adapter cancels (10-16): it lands in the second
slot, is cancelled, and is overwritten. A cancel naming no completed half is
ignored; UCIe fixes its timing. The earlier model treated a cancel as concurrent
with the beat and discarded the whole flit, wrong on all three counts and never
exercised, since the harness ties `pl_flit_cancel` off.

## Flit field extraction

A flit is four 64-byte quarters, each a two-byte header pair, twelve five-byte
granules and a second pair, so granule g is at byte `2 + 64*(g/12) + 5*(g%12)`
(Figure 4). MsgStart's 48 bits come from header bytes 62-65 and 190-193, a high
nibble then a byte per pair (Figure 5); MsgCredit is bytes 128-129; FDId is bits
[1:0] of byte 62. The header's `Rsvd` bits are not `RsvdZero` and are not read.

Within a granule, byte 0 is bits [7:0]: MSGTYPE is the high nibble; MISCOP bits
[3:1] on a Misc message, RP bits [3:2] on every credited message, DLENGTH bits
[1:0] on data messages -- the fields overlap, and which one a granule carries
follows from MSGTYPE. ACTIVATIONOP, PROPERTYREQ and the RsvdZero fields are
derived from their stream positions in `aou_fdi_wire_pkg`.

## Structural well-formedness rules

Everything decidable from one flit with no protocol state, as 48 parallel
comparisons. At the widest bus a new flit can arrive every two cycles, but a
completed flit still has one combinational `w_chk_go` cycle in which every rule
must settle. All are qualified on MsgStart -- a continuation granule carries
payload, and payload lands in the MSGTYPE nibble as readily as anywhere, so an
unqualified rule would report legal traffic on almost every flit -- and on each
other, because the fields overlap: MISCOP is a MISCOP only on a Misc message,
ACTIVATIONOP only on an Activation message, DLENGTH only on a data message, so
an illegal MSGTYPE breaks one rule rather than four. Legal values are
`aou_fdi_wire_pkg`'s from Tables 1, 15, 27 and 5.4, and deliberately not
`AOU_ACTIVATION_CTRL`'s.

**Reserved fields.** The activation message's RsvdZero (stream bits 12-39,
Figure 19) and PROPERTYREQ on any opcode but ActivateReq ("must be 0b0 for
other messages", v0.7 Table 26); the credit grant's 17-bit RsvdZero tail, which lies
in its second granule -- the granule the report names, since the first would
show none of the offending bits; and the RsvdZero in the first granule of the
credited messages that have one -- stream bit 6 on WriteReq and ReadReq, bits
6-7 and 36-39 on WriteResp, bits 37-39 on ReadData (Tables 2, 3, 10-13),
qualified on MSGTYPE because the same positions are AWLOCK, DLENGTH or RLAST on
another message. The padding at the tail of the data messages lies in a later
granule and is not checked. PROF and PROFEXTLEN are never read as reserved: the
v0.7 Base Profile ignores them (v0.7 5.8), and a profile is entitled to fill
them; v0.8 removes PROFEXTLEN and passes the 16-bit FLEX as AXI USER under the
Basic Profile (11.1).

### Activation message placement

v0.7 4.4: at most one MiscU message per flit, and it is the first message.
Read as Activation-only: v0.7 uses "MiscU" for the Activation messages alone
(8.3.4, Table 26) and v0.8 4.4 states the rule for the Activation MiscOp,
allowing two other Misc messages per half-flit. An Activation start anywhere but
granule 0 breaks one of the two clauses, so the rule is one term per granule,
`VIOL_MISC_PLACEMENT`; it also makes 9.2's "ActivateReq and ActivateAck in two
different flits" hold. The other reading -- every Misc message at granule 0 --
would report the delivered transmitter on its first flit and blind the credit
model to every grant not at granule 0; see [Decisions reversed](#decisions-reversed).
A misplaced activation message is still believed: its placement is wrong, its
meaning is not.

### Resource-plane range

A credited message names its destination plane in the receiver's numbering
(5.2.2); an advertisement names the advertiser's own plane (6.4.1), and a grant's
fields for an unsupported plane "must be set to zero" (6.4.2). Wire plane q is
the observed die's when `q < RP_COUNT` and the peer's when some local plane maps
onto it, so a stream's messages may name the receiver's set and its
advertisements the sender's. Anything else is `VIOL_RP_RANGE`, attributed to the
message's granule (granule 0 for a header or spanning grant), and neither spent
nor counted: a wrong counter would both invent an underflow on the plane it hit
and hide one on the plane it belonged to. A header advertising nothing names no
plane.

### The plane map is one-to-one

The specification never says "one-to-one" of the remap 5.2.2 allows, but planes
exist to be "independently flow controlled" (3, 6.2), and a folded map gives two
planes one credit pool; the checker's model would also double-count under it.
The active entries of `I_CFG_RP_DEST_RP` must be pairwise distinct. The map is a
live input, so this is `VIOL_RP_MAP` on granule 0 of every consumed flit while
the map is bad -- a sequence number, and ahead of any credit report the map
would produce -- rather than an elaboration guard.

### Flit destination

FDId (4.3.1) says which of up to four bridges a flit is for, and its credits
"must be assigned to the initiator indicated by the FDId field" (6.4). This
instance watches one pair, `FDID`; a flit for another is `VIOL_FDID` on granule
0 and is otherwise judged as if it were ours, because a single-bridge bench has
a misconfiguration to fix before any other report on that flit means anything.
A multi-bridge bench needs one instance per FDId.

## Message lengths

The counts are `aou_fdi_wire_pkg`'s, one per Table 2-13, 19 and 26; every
message has the fixed length of its type under the Base Profile (v0.7 5.8),
which ignores PROFEXTLEN; v0.8 has no PROFEXTLEN. `MAX_MSG_G` (30) sizes the overrun carry and must not exceed
the flit.

## Message-start consistency

MsgStart says which granules begin a message; type, MISCOP and DLENGTH say how
many granules each occupies; a granule claimed as a continuation must not begin
another (4.4). A message may legally run off the end of a flit -- the
transmitter packs a ring and emits sliding windows, so a thirty-granule message
starting at granule 40 puts twenty-two granules in the next flit -- so the
overrun is carried, not reported: the granules claimed past 47 are the leading
granules of the next flit, and a start landing in *those* is what is reported.
The carry is the rule's only state.

Computed as a parallel mask: each start of known length generates a mask of the
granules it claims, `GRANULE_CNT + MAX_MSG_G - 1` bits wide so the overrun is a
slice off the top; the masks are ORed and compared with MsgStart. Attributed to
the granule that wrongly begins a message -- its contents are the thing that is
not a message, and in the overrun case the message it collides with was in a flit
already reported on. A message of undeterminable length (undefined type, MISCOP
or DLENGTH) claims nothing: it is already reported structurally, and guessing a
length would turn one root cause into two reports.

## Activation handshake model

Each die's state is reconstructed from the wire; `AOU_ACTIVATION_CTRL`'s state
machine, legality table and one-hot encoding are neither imported nor mirrored
(see Overview). 8.4 in brief: each die sends ActivateReq and must answer the
other's with ActivateAck; once all four have crossed the link is ENABLED and
credited traffic is permitted; teardown has the same shape and returns the link
to DISABLED. Two rules follow, both asked of the die that *sent* the message
against that die's own state, sharing one class because they are two ways for
the same message to be out of order and the capture carries the opcode:

- **Phase.** Activation opcodes belong to a die not yet enabled, deactivation
  opcodes to one that is.
- **Answer.** A die may only acknowledge a request it received, and a received
  request travels the *other* way. An acknowledge nobody asked for is
  unsolicited.

**Four events per direction, one state for the link.** Events are one bit per
direction -- die d's own messages are on stream d, the ones it received on
stream 1-d -- so request sent, request received, acknowledge sent and
acknowledge received exist separately per die. The events are kept rather than
folded into the state because a die's state does not govern what it may send:
within ACTIVATE, advertising is armed by the acknowledge the die *sent* and
sending credited messages by the one it *received*. The state is combinational
off the events -- a register copy could only agree with them or be wrong -- and
says the specification's condition: ENABLED once both a request and an
acknowledge have been sent and received (the request terms are implied by the
answer rule and written anyway), ACTIVATE from the first activation message
until then, DEACTIVATE once any deactivation message of the exchange has been
seen, DISABLED before and after. There is one state, not one per die: 8.2's
conditions name the same four events from either side, so two per-die states
could only ever be equal, and an earlier revision that held two was carrying a
distinction the wire cannot make. A completed teardown clears the events,
computed from the events *after* the flit so the completing flit is judged
against the link it tore down; reset and teardown are the only ways back to
DISABLED.

A flit's activation messages are judged against the state before it and their
events applied together after; the messages a flit can legally carry together
read nothing the other could change, and gathering rather than sequencing fits
the window. Skew mostly works in both rules' favour: the checker usually sees a
message before the receiving die decodes it, and its model of a die is enabled
before the die says so. The exception is a narrow FDI, where a flit takes several
beats: the receiving die can decode a request from the flit's first beats and
its acknowledge can complete on the same edge as the request flit. So an
acknowledge is also solicited by a believed request completing on the same edge
in the other direction; one completing any later is still unsolicited.
The price is that a die acting on a state its peer has not reached -- a teardown
begun within a receive pipeline of activation completing -- is invisible; that
needs software to deactivate that fast, and an unsubstantiable report would be
worse than a missing one.

The model advances only on an Activation start that is not inside another
message, has a defined opcode and is legal for the current phase and request
history. Placement and reserved-field findings do not make an otherwise
unambiguous opcode unbelievable: they are reported, while the semantic event
still advances the model. Undefined or out-of-sequence events do not, avoiding
a stream of consequences from a state transition the wire did not establish.

## Credit accounting

`AOU_TX_CRD_CTRL` and `AOU_RX_CRD_CTRL` are neither imported nor mirrored (see
Overview). A credit is one granule of receive buffer for one class (6.1);
advertisements travel as the header MsgCredit field (one plane, five classes)
and CrdtGrant messages (four planes, five classes), both in one flit adding
(6.4); every AXI message consumes its granule count at its start, including one
that runs into the next flit; Misc is not credited.

Boundary messages on the same stream affect the remainder of their own flit:
an Activation message is first (4.4), so later messages in that flit are after
it. The advertising window therefore opens with the die's own ActivateAck
flit and closes after the flit that completes the teardown, and the request
part of the consume window closes with its own DeactivateReq flit. Its opening boundary is a received ActivateAck on the
opposite stream, so credited traffic is enabled once that ActivateAck is
received: when its flit is consumed, or earlier when it lies in a committed
first half (see "First halves fund early").

The windows are v0.8 8.4's, which made the consume window depend on the class
(v0.7 gated every class alike):

- **Advertising**: from the die's own ActivateAck ("after ActivateAck is sent,
  it is permitted ... to send credits" -- the header can share the flit, and a
  CrdtGrant may follow the Activation message at granule 0 under v0.7) until the
  link reaches DISABLED, where 8.4 forbids every credit. The window is the same
  for every class. After the die's own DeactivateAck, v0.8 8.4 permits request
  credits (WriteReq, ReadReq and, as an interim reading, WriteData; whether
  "Request" covers WriteData is an open spec question). v0.8 is silent on
  response credits (ReadData, WriteResp) there; MAS 7.3.1 sends them, since the
  die's own requests may still be open, and the checker follows it. A flit's
  credits -- header MsgCredit and grants alike -- are consumed with the flit or
  half flit that carries them, once it passes the cancel window (MAS 7.3.1), not
  ordered by byte position among its messages. So the flit carrying the
  DeactivateAck that completes the teardown is judged against the link it tore
  down, and its credits are legal (they are discarded with the rest at
  DISABLED). Outside the window: `VIOL_ADV_ORDER`. Before the advertiser's
  ActivateAck and in DISABLED the advertisement funds nothing; inside it, every
  credit funds the counters.
- **Sending credited messages**: from the die having sent an ActivateReq and
  received the ActivateAck answering it. Requests (WriteReq, ReadReq, WriteData)
  stop at its own DeactivateReq (8.4). Pending ReadData and WriteResp must still
  be sent after it, including answers to requests received after it (8.4), so
  they stay legal until DISABLED. The opening is 9.2's condition ("once the
  protocol layer has sent an ActivateReq and received an ActivateAck, it can
  proceed to send data messages"), which is the lenient of the two the
  specification offers: 8.4's ENABLED additionally waits for the die's own
  acknowledge. A die that has been acknowledged but is slow to acknowledge in
  turn is compliant by 9.2, and a checker holding it to 8.4 would report it; the
  two sections should agree and have been raised as feedback. Outside the
  window: `VIOL_MSG_ORDER`, with no underflow report, so one root cause yields
  one report.

**First halves fund early.** A latency-optimized flit's first half that is not
cancelled is consumed by the protocol layer before the second half arrives
(UCIe 3.0 10.2, Figures 10-16 and 10-17), so a die may spend a credit grant
carried in it as soon as that half commits, and an ActivateAck at granule 0 of
it is received then too: it opens the receiving die's consume window at the
commit (`r_act_ack_half`), not when the flit completes. Without that, a die that
acted on the first half -- an adapter pause between the halves, its next flit
ending in the same cycle as the Ack's -- was reported for a credited message
before the ActivateAck (seen on a 32-byte FDI build). An adapter that pauses
`pl_valid` between the halves makes the gap visible. At the first half's commit the
buffer's first half is current and the framing of G0-G23 depends only on earlier
granules and the carry, so grants lying wholly in G0-G23, and one continuing
from the previous flit's G47, are summed then and fund the peer's counter at
once (`w_early_for`); the flit's consume adds only the rest (`w_late_for`): the
header MsgCredit, which is in the second half, and grants reaching into it. The
Activation message that opens or closes the advertising window is at G0, so the
window is known at the commit. A clip at the early funding is reported with the
advertising flit's consume. Without this the checker funded credit one half late
and reported an underflow against a die that spent a first-half grant before the
second half arrived.

Both dies may advertise until DISABLED and the response counters keep being
spent until DISABLED, so the windows are all teardown needs and nothing is
suspended.

**Planes.** A counter is per die, per local plane, per class. The plane field
means two things: a credited message carries the **destination** plane, already
remapped by its sender; a credit message -- header or each grant slice --
carries the advertiser's own **source** plane, so the peer can return the credit
to the right counter. Both are therefore in the numbering of the die at the far
end of the flit. `I_CFG_RP_DEST_RP` is the *observed* die's map, so it applies
to one side only: the observed die's local plane p is spent by outbound messages
naming `DEST_RP[p]` and funded by inbound advertisements naming `DEST_RP[p]`;
the peer's counter for the observed die's plane p is spent by inbound messages
naming `p` and funded by outbound advertisements naming `p`, no map anywhere
(`w_plane_wire`). An earlier revision put the peer's side through the map too.
Under any permutation of `0..RP_COUNT-1` that is a relabelling and invisible;
under a map onto planes the observed die lacks -- which the range rule admits,
since the peer may number its planes as it likes -- the inbound counters were
never funded and never spent, and the inbound direction could not report an
overspend. There is a test at such a map, in both directions, and one for each
direction of the source/destination mistake. Advertisements are accumulated in
wire-plane numbering and mapped to local planes once.

**Capacity.** AoU has no sender-side ceiling: a receiver advertises exactly its
slots (6.4.3), and a sender's counter saturates on an over-grant (6.4, since
v0.7.1), which the wire cannot see. So
the per-plane, per-class ceilings the checker once carried described nothing it
could judge and were replaced by one `CRD_CAPACITY`: how much outstanding credit
a shadow counter can track, `$clog2(CRD_CAPACITY + 1)` bits. An advertisement
that would exceed it is clipped and reported as `VIOL_CRD_OVERFLOW` on granule 0
of the advertising flit, after the same cycle's spending has been netted --
untracked credit is credit whose later spending would be reported as underflow
against the wrong die. It means either a receiver advertising beyond any
plausible buffer (2048 granules is 10 KB per class per plane) or an instance
whose capacity is too small; either way, look at the advertiser. The running
sum within a flit is sized for a full counter plus one flit's maximum
advertisement (a header and twenty-four grants of 128), derived so a large
capacity cannot wrap it.

**Reassembling a credit grant.** A grant advertises all four planes at once, so
its plane is a field index. `decode_credit_grant` in the wire package reads the
twenty fields off Figure 20's MSB-first stream into one array; an earlier
revision read the design's packed struct and got the plane-1 ReadReq and
ReadData halves the wrong way round, as did the testbench's encoder of the time,
which is why neither caught it. The WriteResp field is two bits and is
zero-extended into the eight-entry `CREDIT_TABLE`. A grant may start at any
granule (4.4 constrains only Activation messages), so the pair at each of the
forty-seven positions is decoded and the believed grants summed by a six-level
tree per plane and class over forty-nine terms -- header, spanning grant,
forty-seven positions -- written out rather than left to a tool to
re-associate; the earlier one-position-at-a-time accumulation was a
forty-seven-deep adder chain per counter. A grant starting at granule 47
continues in G0 of the next flit; its first granule is held in `r_grant_g0` with
`r_grant_pend`, and its body -- reserved bits, plane range and credits alike --
is judged with the flit that carries it. The pair is loaded on every consumed
flit and held while either the structural rules or the credit model is present.
A grant is believed when its type is recognized and it begins where a message
may. Non-zero reserved padding is reported but does not make its unambiguous
credit fields disappear; one the framing rule rejected is neither counted nor
has its reserved bits read.

## Spending

Per counter, the flit's spend is a number, not a sequence: `w_crd_sel` says
which granules start a believed credited message for that plane and class,
`sum_spent` adds their lengths in a six-level tree, and one comparison against
what was available decides the underflow. Available is the counter plus any
advertisement crossing the other way in the same cycle; what is left is
`min(CRD_CAPACITY, available - spent)`, clipped after netting so that returned
credit is not discarded when same-cycle spending made room.

An earlier revision walked the forty-eight granules per counter, subtracting
and comparing as it went, to name the granule at which the count crossed zero:
forty-eight dependent compare-subtract stages per counter and linear
combinational depth, for one detail of the report. Naming that granule exactly
needs a prefix sum, which costs what the walk cost. So an underflowing counter
marks every granule that started one of its messages in the flit, the capture
-- which takes the lowest offending granule -- names the class's first message,
and a flit that overspends is one finding rather than one per message past the
line. Only believed messages are spent: a credited message of known length,
beginning where a message may and naming a supported plane. Undefined
type/length, framing and plane-range failures are therefore not also reported as
underflows; non-zero reserved padding is reported independently without
discarding an otherwise decodable message. The ordering rule asks nothing about
the plane; it is about when, not where.

## Violation matrix and capture

One bit per granule per class; the class index is the code, every rule drives
its own row, and a rule is added by adding a row. Reserved-field findings are
attributed to the granule holding the bits. Per direction, the capture candidate
is the lowest offending granule, then the lowest class on it; the sticky vector
ORs the whole matrix and the count adds one per direction with any bit set. When
both directions report in one cycle both are retained and the capture takes the
outbound direction. The count saturates -- a pegged counter still says "a flood",
which is all it is for -- and the trigger is registered in the observed clock
domain rather than emitted combinationally.

## Optional activation-status cross-check

Compares each die's reconstructed state against the die's own reported state.
Two independent implementations of one handshake disagreeing is the most direct
test of `AOU_ACTIVATION_CTRL` available, and the one thing here that can find a
die believing something the traffic does not support. Off unless asked, contained
so it cannot reach the protocol domain, tolerant by default -- because a naive
version would be actively harmful:

**Equality is the wrong comparison.** The two views are separated by a pipeline
whose delay has a different sign per event. On the stream a die drives,
`AOU_ACTIVATION_CTRL` records the event when the message enters its activation
FIFO, *before* the wire, so the design moves first -- by the TX queue, flit
assembly, the flit's time on the wire and any TX low-power deferral, a few
hundred cycles at worst. On the other stream the die records the event after its
receive path decodes it, so the checker moves first, by the decode depth. Which
side appears to enter ENABLED first depends on message order and differs per
die, so equality would report every correct activation.

**Comparison on quiescence instead.** Compare only when nothing is moving: no
well-formed activation message on either stream (link-wide, since a message is
an event for both dies; well-formed rather than believed, since a message this
module rejected may still move a die; undefined opcodes excluded, since neither
side acts on them) and neither view changed, for `XCHK_SETTLE_CYCLES`. Skew is
a transport delay; it cannot make the views disagree forever, so anything still
disagreeing once everything has stopped is a real difference. On top, a
one-sided convergence timeout: when the *checker* moves first the design has
`XCHK_CONVERGE_CYCLES` to follow, since that wait is short and bounded; in the
other direction the design legitimately leads by a large and unpredictable
margin and is left to the settled comparison. Details that are load-bearing:
the disturbance term in the settled condition (the counter still holds the full
interval on the cycle a view moves, and without it the comparison would be made
against the very change that should have restarted it); the comparison reads
the live views while only change detection reads the registered copies; arming
the window restarts it; the timeout wins where both could fire; one report per
disagreement, released when the two agree again, since a held disagreement
would otherwise peg the counter and pulse the trigger forever; counters
saturate; and the view registers reset to DISABLED rather than zero, because
zero reads as "moving" and would restart the timer for no reason.
`O_XCHK_COMPARED` is gated on the enable so it says a comparison was made, not
that one would have been.

### The budget behind the defaults

Design-moves-first sets `XCHK_SETTLE_CYCLES`: the TX low-power heartbeat (an
8-bit counter, 255 cycles at the widest threshold), the activation and misc
queues, the packing states, output mux and skid stages, eight beats on the
narrowest bus and this module's two-cycle stage -- under three hundred cycles.
The deactivate idle-drain timeout (up to 1024) is deliberately excluded: it
gates when the request is queued, so it elapses before the state changes.
Checker-moves-first sets `XCHK_CONVERGE_CYCLES`: the receive decode depth, single
digits. The defaults, 4096 and 1024, are roughly fifteen and a hundred times
those; the terms are read off today's RTL and the dominant one is a programmable
threshold, so a bench changing a register this module never sees must still be
quiet.

A finding means the two implementations disagree, not that the design is wrong
-- this module can be the wrong one, which is why both views are captured. A
known non-design cause is a tolerance too tight for the bench.

## Cross-check reporting

Deliberately a duplicate of the protocol reporting logic rather than a
parameterisation of it: sharing registers is the one thing this must not do, and
sharing code would leave a single edit able to reconnect the two domains. Its own
trigger lets an emulator arm on either kind of finding; its own capture and
freeze are the containment -- were it the protocol record, a cross-check finding
on an untuned bench would freeze it before the run reached the violation it was
looking for. The captured flit sequence is the die's stream position: when, not
what.

## Simulation-only reporting

Behind the same `ASSERTION_ON` guard the rest of the RTL uses, with no file
logging (the decoder's job; keeping the module free of file I/O is what keeps
the synthesizable-subset claim honest) and no `$finish`, since the checker's
purpose is to survive the violation and the soak reads the ports afterwards. The
cross-check has a separate assertion with its own message, because its finding
has a different first thing to look at and one of its known causes is the
tolerances; it is vacuous with the feature off.

## Decisions reversed

Each of these was tried, or claimed, and withdrawn; the reason is kept so it is
not tried again.

- **Two flit buffer banks per direction**, claimed necessary to overlap one
  flit's check with the next's accumulation. The check reads the buffer in the
  one cycle after the last beat and every consumer samples at that edge; a
  next-flit beat written at the same edge is visible a cycle later, and at the
  widest bus the next flit cannot complete before the following edge. Removed
  with a back-to-back regression at every width: 4096 flops.
- **"One Misc message per flit"**, reading 4.4's MiscU as every Misc message. It
  reported the delivered transmitter's first flit and blinded the credit model
  to every grant not at granule 0; v0.7 uses MiscU for Activation messages only
  and v0.8 says so outright. Withdrawn in the review that proposed it.
- **Wire format imported from `packet_def_pkg`**, with an elaboration check that
  compared the design package with itself. Replaced by the checker's own
  statement of the specification; see Overview.
- **Per-plane, per-class credit ceilings**, twenty scalars mirroring
  `AOU_TX_CRD_CTRL`'s. The protocol has no sender-side ceiling, so they described
  nothing the checker could judge and assumed both dies were built alike;
  replaced by one capacity and an overflow finding.
- **A teardown suspension window** and a credit-management-type input. 8.4
  defines the windows exactly; nothing to suspend. (v0.8 8.4 since made them
  class-dependent, which the windows follow without a mode input.)
- **One teardown window for every class**, v0.7 8.4's: no credited message
  after the sender's own DeactivateReq and no credit after its own
  DeactivateAck. v0.8 8.4 requires pending ReadData and WriteResp after the
  DeactivateReq and permits request credits after the DeactivateAck, so both
  windows now depend on the class (2026-10-20).
- **Response credits closing at the advertiser's own DeactivateAck**, v0.7's
  rule kept as the interim while v0.8 was silent, with a grant at G47 held to
  it. The MAS sends them until DISABLED (7.3.1, 2026-10-26), so the
  advertising window is one for every class again.
- **The consume window opening only when the ActivateAck's flit completes.**
  A committed first half is received (UCIe 3.0 10.2), as the early funding
  already assumed; see [Credit accounting](#credit-accounting).
- **Serial credit walks**, forty-seven adds and forty-eight compare-subtracts per
  counter, to name the granule at which credit ran out. Replaced by trees and
  per-flit attribution; three-quarters of the module's logic.
- **A cancel model** that treated `pl_flit_cancel` as concurrent with the beat
  and discarded the whole flit. UCIe cancels a 128B half, one cycle late, and
  replays it.
- **8.4's ENABLED as the condition for sending credited messages**, which
  reported a die that had been acknowledged but not yet acknowledged in turn.
  9.2 permits it, and the lenient reading was chosen (2026-09-07 review); see
  [Credit accounting](#credit-accounting).
- **An advertising window closing after the DeactivateAck's flit** while the
  consume window closed with the DeactivateReq's. Both boundary messages are
  first in their flit, so both windows now close with the flit.
- **One activation state per die**, two arrays always equal to each other; see
  [Activation handshake model](#activation-handshake-model).
- **Judging the adapter's NOP flits** on the inbound stream; see
  [Flit reconstruction](#flit-reconstruction).
- **Indexing the peer's credit counters through `I_CFG_RP_DEST_RP`**, which
  blinded the inbound direction under any map onto planes the observed die
  lacks; see [Credit accounting](#credit-accounting), "Planes".
