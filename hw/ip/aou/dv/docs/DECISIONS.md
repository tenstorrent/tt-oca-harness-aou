<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Design decisions for the VIP-free UVM testbench

Why the bench at `hw/ip/aou/dv` is built the way it is: the constraints that shaped it, the
choices made under them, the alternatives that were turned down, and the
policies the bench enforces. What the code does is in the code, the
[README](../README.md) and [ARCHITECTURE.md](ARCHITECTURE.md); this document
records only the reasons.

## How to use this document

- Read it before changing the bench's structure or one of its policies:
  verdicts, coverage rules, the bug process, configurations, the public tree.
  If a change contradicts a decision here, change the decision first, in this
  file, with its reason, and in the same commit as the code.
- Each decision has the same parts. **Decision** is what holds today. **Why**
  gives the constraint or goal behind it. **Rejected** lists the alternatives
  that were considered and why they lost. **Where** names the files, directories
  and make knobs that implement it. **Consequences** covers what follows from
  it, including known costs and follow-ups.
- Paths are relative to `hw/ip/aou/dv` unless they start with a top-level
  directory of the repository (`RTL/`, `csr/`, `DOC/`, `hw/`).
- Spec citations give section numbers only. AoU means the AXI-over-UCIe
  specification (v0.7 unless v0.8 is named). UCIe means the UCIe base
  specification (r1.1 unless named). MAS means the IP's micro-architecture
  specification, and the integration guide is `DOC/integration_guide`.
- Unresolved items are collected in [Open items](#open-items) at the end.

## Overview

The bench verifies one `AOU_TOP` (the AoU bridge with its FDI bringup
controller) against models of everything around it: AXI managers and
subordinates on its local ports, an APB host, and a remote die made of layered
models that present a UCIe Adapter at FDI and play the remote AoU protocol layer
and its AXI side. It uses no commercial verification IP, so it can be published
with the RTL and run on an open simulator; VCS is the day-to-day simulator and
Verilator the open one it must also pass on. Every check reports under a rule
ID traced to a specification section. Every run gets a verdict (PASS, XFAIL,
FAIL, XPASS) against a list of known DUT bugs, so regressions stay green on
known bugs while anything new fails. Coverage, code and functional, counts only
passing runs, and the test plan is tied to the testlists by scripts, so that
coverage of the plan is measured rather than asserted.

## D0. Starting point: the PR 80 smoke flow

**Decision.** The bench grows out of the Verilator UVM smoke flow contributed
upstream as GitHub PR 80 by VNCHIPLabs (Vinh Trieu and Quang Le): commits
`2bcdbf1`, `f257806` and `b09a47b`. Those three commits are kept with their
authorship; the overhaul is layered on top of them. Once T1 covered everything
the smoke did, the smoke bench itself was retired and its reusable parts kept.

**Why.** PR 80 established the parts everything else needs: a pinned Accellera
uvm-core fetched into `.deps/` and compiled from source, the RTL file list taken
from the repository, a Verilator-first build, AXI and FDI interfaces, a minimal
FDI peer and a four-RP write/read smoke. Its documentation also set the
principle that the UVM flow complements the cocotb flow in the verification directory rather than
replacing it, and that registers use the RAL generated from the RDL rather than
a second hand-written model. The second still holds. The first ended when the
cocotb flow was retired (D16): it had two tests, both covered by T1 and the
register bench, and keeping two environments meant two sets of harness code,
CI jobs and documents for one DUT.

The smoke bench (`aou_tb_top`, `aou_multi_rp_smoke_test`, its environment, FDI
peer, AXI driver and FDI monitor, `aou_uvm_pkg` and its file list, and the AXI,
FDI, APB and reset interfaces only it used) was retired because T1 does all of it
with the layered models: multi-RP write/read round trips with exact data checks
(`aou_mrp_test` on `4x512-sp64`), activation through APB and the link-state agent,
and clean DUT status. Keeping it meant a second set of AXI/FDI components, lint
waivers for code no longer developed, and a default build nobody used.

**Kept.** `uvm_dpi_verilator.cc` (the uvm-core DPI shim every Verilator build
links), `scripts/get_uvm_core.sh` (`make setup`), `pkg/core/aou_pkg.sv` (an
independent AoU message and flit encoder, now the cross-check in
`aou_l3_codec_test`, TB=l3_unit), `tb/aou_status_if.sv` (T1's `status`
interface, moved from `intf/`) and the Makefile header. PR 80's interfaces also
seeded `aou_axi_bus_if` and `aou_apb_if`, and its top the T1 and register-bench
clock, reset and tie-off code; those files say so in their headers. README
"Acknowledgements" lists all of it.

**Where.** `make setup`, `uvm_dpi_verilator.cc`, `l3/unit/aou_l3_codec_test.svh`,
`tb/aou_status_if.sv`, the Makefile header. **Consequences.** `TB` defaults to
`t1`; `make test` runs the T1 bring-up test. Files kept from PR 80 keep their
VNCHIPLabs copyright and SPDX headers, with ours added where we changed them.
`aou_pkg.sv` is the only PR 80 file left with a lint waiver.

## D1. No commercial verification IP

**Decision.** The bench contains no commercial VIP: no Synopsys SVT AXI/APB, no
Avery (or other) UCIe VIP, and no vendor-confidential protocol checkers. It has
its own AXI, APB, FDI and AoU agents, models and checkers. The scoreboard,
sequences and tests see only the VIP-neutral `aou_axi_txn`, so a commercial or
third-party AXI agent could be plugged in later behind one adapter.

**Why.**

- The bench is meant to be published with the RTL under Apache-2.0. Commercial
  VIP is licensed per site, can't be redistributed, and its source and
  documentation are confidential, so a bench that needs it can't be published or
  even run by most readers.
- It must run on an open simulator (D2). Commercial VIP is typically supported
  only on the commercial simulators.
- An earlier bench on a non-public branch (`dv/`, built on SVT and a UCIe VIP)
  showed the cost of the dependency: it ran only where the licences were, and its
  results couldn't be shared with the RTL's open-source users.

**Rejected.**

- *Keep the commercial VIP and publish only the tests.* The tests don't run
  without it, so nothing would be reproducible outside the site.
- *Adopt open-source AXI and APB VIP.* Evaluated in detail in
  [VIP_EVALUATION.md](VIP_EVALUATION.md). Every AXI candidate missed
  requirements the DUT needs exercised (W before AW, out-of-order responses
  across IDs, sparse and zero strobes, exclusives, a transaction-level monitor)
  or was unusably slow on Verilator; closing the gaps was estimated to cost as
  much as writing our own agents or more. For APB, the best candidate cost as
  much to adapt as to rewrite; its interface assertions were adapted with
  attribution.
- *Use a UCIe VIP for the FDI side.* No open one exists, and the DUT's FDI needs
  only the Adapter's side of the FDI handshakes, which a model covers (D3).

**Where.** `axi/`, `apb/`, `fdi/`, `l3/`, `env/`; the VIP-neutral transaction in
`axi/` (`aou_axi_txn`) and the swap note in `axi/README.md`. CODING_GUIDELINES.md,
"Licensing", and AGENTS.md, "Boundaries", forbid committing Avery, Synopsys SVT
or Arm material.

**Consequences.** We own the agents and their bugs. Every checker therefore
needs evidence that it can fire (D4), because no vendor stands behind it.
Arm's free `Axi4PC` assertions can be enabled as an optional extra (D13).

**Measured effect on simulation speed.** Dropping the VIP also made the bench
much faster. The comparison below uses essentially the same RTL: only `AOU_CORE_SFR.v`
differs between the two branches. One side is a reference
regression of the earlier VIP-based bench, run one test after another on a
single CI agent on 2026-10-08. The other is this bench's `1x512-sp64` lists. Both
used VCS with code coverage enabled.

| | Earlier VIP bench | This bench (`1x512-sp64`) |
|---|---|---|
| Tests (runs with timing) | 72 in the list (61 with a simulated time) | 312 |
| Simulated time, total | 0.92 ms | 6.0 ms |
| Simulated ns per wall-clock second, aggregate | 486 | 2,250 (4.6×) |
| Simulated ns per CPU second | 850 | 7,065 (8.3×) |
| Median test | 25 s wall, 9.7 s CPU | 6 s wall |
| Long runs, steady state | ~650–770 ns/s (76–83 µs in 105–116 s) | ~14,000–15,600 ns/s (0.4–1 ms in 27–72 s) |
| Compile | 315 s | ~85–90 s |
| Whole regression, elapsed | 2.4 h, one configuration | ~14 min, all 7 configurations (1,657 T1 + 84 register runs, in parallel through the batch system) |

The hosts differ, and the tests do different work, so read the ratios as
throughput rather than a per-test speed-up. Without coverage, this bench reaches
about 25,000–28,000 simulated ns per second on long VCS runs. Verilator runs at
between a half and a third of VCS's speed on the same lists.

## D2. Simulators: VCS for development, Verilator as the open reference

**Decision.** Two simulators are first-class. Verilator (pinned to 5.052) is the
open-source simulator the published bench must pass on. VCS is the default when
it is on `PATH` and is used for day-to-day development, debug and code coverage.
Work is cross-checked on Verilator before every merge and at every gate.
Xcelium has a basic build and run only; Questa builds, but its runs and coverage
are untested. Every simulator compiles the same pinned uvm-core source, never
its bundled UVM.

**Why.**

- Verilator is what a reader of the public repository can run, so it decides
  what "the bench passes" means outside the site.
- VCS turns builds around faster on this bench, gives richer code coverage
  (condition, FSM, branch) and Verdi's source and struct debug, which is why
  development happens there.
- Compiling one UVM source everywhere removes vendor UVM differences as a cause
  of disagreement between simulators.

**Rejected.** *Verilator only*: slower iteration, and no condition or FSM
coverage. *VCS only*: the bench would
drift into constructs Verilator rejects and stop being runnable for readers.
*Each simulator's bundled UVM*: version skew between simulators. Through the
harness runner VCS compiles its shipped UVM; the sim configs pin it to
`uvm-ieee-2020-2.0`, the shipped library nearest the pinned source (on the one
seed tried it reproduced the standalone trace; the runner's default 1.2 does
not; the harness leg itself is a deferred follow-up, OPEN_ITEMS.md), and `aou_reg_burstlen_cb` selects the
register path type by the library's version macro.

**Where.** `SIM=vcs|verilator|xcelium|questa` in the Makefile; `make setup`
(uvm-core, and z3 for Verilator's `randomize()`); AGENTS.md, "Running things";
the Verilator-safe subset in CODING_GUIDELINES.md (D15).

**Consequences.** New constructs need a probe on both simulators before they
spread. Verilator 5.052 code-generation problems are worked around in the build
(for example `-fno-dfg-peephole`, see VIP_EVALUATION.md) rather than in the
code. Xcelium coverage and full-regression matching are an open item.

The bench compiles against two UVM libraries: the pinned uvm-core, and the OCAH
library (`ocah_lib`, fetched by `make setup` into `.deps/ocah_lib` at the pin in
`scripts/get_ocah_lib.sh`), whose `ocah_test` and `ocah_sequence` are the bases
of `aou_base_test` and `aou_base_test_seq`. The library is the harness's shared
framework; building on it is what lets the harness runner start the bench
unchanged, and the pin keeps the standalone build reproducible. Only the bases
are used (D16): the AXI VIP, scoreboard and checker frameworks of the library
stay out until an owner decision takes them in, because the bench's own models
and rule-based checkers (D3, D4) already cover their ground.

## D3. Layered models of the remote die

**Decision.** The remote die is entirely models, in layers that depend only
downward:

| Layer | Package | Role |
|---|---|---|
| L1 | `aou_fdi_pkg` | FDI mainband: beats and 256-byte flits, Format 6 codec, PL driver and TX responder, monitor |
| L2 | `aou_lsm_pkg` | FDI link state: the Adapter's side of bringup, PL-initiated events, and a reference model of the DUT's bringup controller |
| L3 | `aou_l3_pkg` | AoU protocol layer: messages, packing and unpacking, credits, activation and deactivation |
| L4a / L4b | `aou_axi_pkg` | The remote die's AXI side behind L3 (L4a), and the local AXI agents on the DUT's ports (L4b) |

The DUT side has its own models: AXI managers and subordinates on the S and M
ports, an APB agent with the generated register model, a software model that
answers activation and deactivation interrupts as the MAS describes, and a
reset agent. The scoreboard checks bytes as AXI4 defines them, end to end, so
it is unaffected by splitting, aggregation and width conversion inside the DUT.

**Why.**

- Each layer can be built and tested alone. `TB=l3_unit` runs L3 and the FDI
  checker with no DUT; `TB=axi_selftest` runs the AXI agents and the scoreboard
  in loopback. A DUT failure then can't be blamed on an untested layer below.
- Injection belongs at the layer that owns the concept: bad message types and
  credit violations at L3, flit corruption and stalls at L1, link events at L2.
  A single monolithic FDI peer, as in the PR 80 smoke, can't inject at the
  protocol level.
- A model rather than a second DUT instance lets the remote side behave in
  ways the DUT never does: other packing densities, withheld or delayed credit,
  out-of-sequence activation messages, other data widths, v0.8 encodings.
- The remote die's width is a run-time choice (`+remote_bytes`), so one build
  covers every upsize, downsize and bypass pairing.

**Rejected.** *Two DUTs back to back*: a bug common to both sides cancels out,
and the remote side can't be driven into illegal or unusual traffic.
*Extending PR 80's minimal FDI peer*: no layering, so no reuse and no
protocol-level injection.

**Where.** [ARCHITECTURE.md](ARCHITECTURE.md) (topology, inter-layer APIs, the
transaction contract, scoreboard rule, reset contract, test layer API);
`fdi/`, `l3/`, `axi/`, `env/`, `tb/tb_top.sv`.

**Consequences.** The models implement the spec independently of the RTL, so a
disagreement can come from either side; that is handled by D5 and D7. Every
component implements `reset_flush()` (the reset contract), because mid-test
resets are part of the plan. Changes to the test layer API go through the
integrator, because every test depends on it. The bench was built by parallel
work streams against the contracts in ARCHITECTURE.md; keep them current when a
boundary moves.

## D4. Rule-based checking with spec-traced IDs

**Decision.** Every check reports under a rule ID listed in `checkers/rules.csv`,
with exactly one primary checker, any secondary cross-checks, a scope and a
spec reference. Rule families: `AOU-Rn` (the AoU specification's checkable
rules), `FDI-Rn` (UCIe r1.1 chapter 8 FDI handshakes), `FDI-Mn` (the bringup
reference model), `AXI-Rn` (AXI4 handshake rules on the DUT's ports), `AXI-Sn`
(scoreboard: responses and data), `APB-Rn`, `REG-Rn` (registers), `DP-Rn`,
`FEAT-Rn` (data-path and feature checks) and `T1-*` (bench-level scenario checks:
`T1-E` errors, `T1-L`/`T1-LP`/`T1-RA` lifecycle, `T1-M` multi-RP, `T1-P`
performance, `T1-T` end of test, `T1-V` base-sequence steps, `T1-RM`/`T1-L4A`
the remote AXI side). Messages start with the ID (`AOU-R16: ...`).

Scope says whom a rule binds: **DUT** (checked on the DUT's outputs), **MODEL**
(binds the partner our models play; self-checked or held by construction) or
**N/A** (this DUT's interface can't exercise it). Each checker counts its
evaluations and violations in a rule ledger printed at the end of every run,
and `make rule_inventory` turns the ledgers into
[checker_inventory.md](checker_inventory.md).

Negative tests stay strict through an expectation registry: a test declares
which rule IDs or interrupts it expects and how many times, a report catcher
demotes exactly those, and any other error still fails.

**Why.**

- A stable ID at the start of each message is what makes the verdict model
  (D6) work: an expected failure is tied to a rule and a message, not to a test
  name.
- One primary checker per rule prevents both gaps and double reporting.
  `rule_inventory` shows rules with no checker, two primaries, a checker that
  never runs, or one that never fired.
- Evidence matters more than the existence of a checker. The inventory says, per
  rule, whether it fired in a negative test or was only ever evaluated in
  passing runs. (Escape and mutation runs also counted while the suite of D14
  existed.)

**Rejected.**

- *Free-form error messages.* They can't be matched reliably to known bugs and
  can't be counted per rule.
- *Turning checkers off in negative tests.* That would hide every other failure
  in the same run.
- *Checks derived from reading the RTL.* They would confirm the RTL rather than
  verify it (D5).

**Where.** `checkers/rules.csv`, `checkers/aou_rule_pkg.sv`,
`checkers/aou_rule_log.svh`, `scripts/rule_inventory.py`, `scripts/check_rules.py`
(in `make lint`), the expectation registry in `env/` (`expect_event`), the reused
`AOU_FDI_CHECKER` in `checker/` (with its own `DESIGN.md`) behind
`l3/aou_fdi_chk_adapter.svh`.

**Consequences.** Adding a check means adding its row to `rules.csv` first.
Rules that have never fired are listed as such until a negative test or a
mutation proves them. A known gap (an FDI rule with no checker) is visible in
the inventory rather than forgotten.

## D5. Specification baselines and unspecified behaviour

**Decision.**

- **AoU.** The bench targets AoU v0.7 by default, which is what the RTL
  implements, and can switch to v0.8, where the RTL is heading. The switch is the
  `spec_rev` field of the env and L3 configs; v0.8-only rules (message layout,
  the Activation message's profile fields, the ERROR state) are checked only
  under v0.8 and appear as such in the inventory.
- **UCIe.** FDI behaviour follows UCIe r1.1 (chapter 8), written with knowledge
  of r2.0's changes but not modelling them. System management (sideband and
  management transport) is out of scope; the DUT has none.
- **AXI scope: INCR bursts only.** The DUT supports INCR bursts and nothing
  else. AoU's WriteReq and ReadReq carry no AxBURST field (AoU 2.5; the Basic
  Profile lists BURST as INCR only), so the remote die can only rebuild an INCR
  burst, and the width converters compute INCR addresses. FIXED and WRAP on the
  DUT's S port are therefore out of scope, not a coverage hole: the AXI agents
  on the S ports are configured INCR-only (`aou_axi_cfg.incr_only`), their
  sequences never generate another burst type, and AXI-R19 flags any other
  burst there as a test-stimulus error. `axi.txn_cg` has no burst coverpoint,
  and plan items 4.16/4.17 are dropped (owner decision, coverage-closure plan
  D1).
- **Oracle.** Expected behaviour comes from the AXI4, UCIe and AoU
  specifications and the MAS, never from the RTL. Where the RTL and the
  documents disagree, the test follows the documents.
- **Unspecified or conflicting behaviour.** When the AoU specification and the
  MAS conflict, or behaviour is undefined, the bench does not stop to ask. It
  takes an explicit interim expectation, implements it, files a bug draft that
  records the choice (D7), and ties any failure it causes to that draft
  (D6).
- **FDI state encodings.** RTL from before the UCIe encoding fix uses private FDI
  state encodings on `pl_state_sts` and `lp_state_req` instead of UCIe's. L2
  can model either through `fdi_enc` (`RTL` or `SPEC`). `SPEC` is the default,
  and no test forces `RTL`; the `*_spec_test` tests (testlist `g1b`) select
  `SPEC` themselves because they check UCIe-only behaviour. A run-wide override
  (make `FDI_ENC`, plusarg `+FDI_ENC`) runs a whole regression with `RTL`
  against RTL from before the fix. (Retired; see the amendment below.)

**Amendment (2026-10-26): one FDI encoding.** The DUT on `main` uses UCIe's
encodings since its encoding fix, and the owner has ruled (2026-10-24) that the
bench does not stay compatible with RTL that lacks a fix that is on `main`. So
the `RTL` map is gone: L2 encodes and decodes UCIe r1.1 Table 8-2 only, with no
selector (`fdi_enc`, `aou_fdi_enc_e`, make `FDI_ENC`, `+FDI_ENC`,
`run_list.py --fdi-enc` and the informational coverpoint `cp_fdi_enc` were
removed), and every check that ran only under `SPEC` (FDI-R47, R48, R49, the
Retrain NOP/Active rule of FDI-M01, the Adapter's LinkReset and Disabled) now
always runs. A DUT whose state codes disagree with UCIe is a DUT bug, not a
bench mode. The `*_spec_test` names stay: they name the UCIe-only scenarios.

**Why.** v0.7 is what the DUT claims, so checking it against v0.8 would report
intended behaviour as bugs, while v0.8 support keeps the bench useful when the
RTL moves (and the work goes back to the public repository). A bench that
follows the RTL where documents are silent would encode the RTL's choices as
truth; one that blocks on every question would never finish. The interim
expectation makes the choice explicit and reviewable, and the draft carries the
question to the people who can answer it.

**Rejected.** *Hard-coding the RTL's FDI encodings*: bakes a known bug into the
bench. *Hard-coding UCIe encodings*: every FDI test fails until the DUT is fixed,
hiding all other findings. *Waiting for clarification before writing the
check*: stalls the work and leaves the behaviour unchecked meanwhile.

**Where.** `env/aou_t1_env_cfg.svh` and `l3/aou_l3_cfg.svh` (`spec_rev`),
`fdi/aou_lsm_pkg.sv` (UCIe encodings), `l3/aou_link_ctrl.svh`
(v0.8 ERROR state), CODING_GUIDELINES.md "Oracles", AGENTS.md "Boundaries".

**Consequences.** Some checks encode an interim expectation, not a settled
fact; their comments and expected-fail notes name the draft. When an answer
arrives, the check changes to match it and cites the source. Concrete UCIe
r1.1 to r2.0 FDI rule changes are still to be listed (see Open items).

## D6. Verdict model: PASS, XFAIL, FAIL, XPASS

**Decision.** `scripts/check_run.py` judges every run from its `sim.log` against
`expected_fail.yaml`:

- **PASS**: no `UVM_ERROR` or `UVM_FATAL`, and the log reached the UVM report
  summary.
- **XFAIL**: every error matches an expected-fail entry for that test, each
  entry naming a bug draft.
- **FAIL**: any unexplained error, or no report summary (crash, hang, kill).
- **XPASS**: an entry matched nothing in a run of its test. It is reported for
  review, because the bug may be fixed.

An entry names the test, the bug (its GitHub issue on
`tenstorrent/tt-oca-harness-aou`, or `BUGS/NNN` while the draft is staged and not
yet filed), and the exact failing check: a
substring of the error message (`check:`) or, when the signature spans several
fields of one message, a regular expression (`check_re:`). Two refinements keep
the list from hiding new failures:

- **Bug-specific entries vs generic symptoms.** A generic symptom that a bug
  causes but that anything else could also cause (traffic did not complete, not
  drained, a scoreboard mismatch, a failed handshake) carries `requires: <bug>`.
  It explains an error only when a bug-specific entry (one without `requires:`)
  for the same bug matched another error in the same run. A generic symptom can
  therefore never excuse a run on its own.
- **Seed dependence.** An entry marked `seed_dependent: true` is a bug that only
  some seeds hit; its absence in a run is not reported as XPASS.

`make run` writes each verdict to `<run>/verdict.txt`, which coverage (D10) and
plan status (D8) read.

**Why.** The DUT has known bugs, and their owners fix them on their own
schedule. Regressions must stay green on those bugs, so that a red result
always means something new, while still running every test and every check. A
fix must be visible without anyone remembering to look: it shows as XPASS
(the entry stops matching) or as an XFAIL run becoming PASS.

**Rejected.**

- *Disabling or skipping the affected tests.* Their other checks stop running,
  and a fix goes unnoticed.
- *Letting them fail.* New failures drown in known ones.
- *Matching by test name or by bug alone.* Any new error in an affected test
  would be excused.
- *Standalone entries for generic symptoms.* They were in early versions and
  could explain a new hang just because the test had a known bug; `requires:`
  replaced them.

**Where.** `expected_fail.yaml` (its header defines the fields),
`scripts/check_run.py`, `verdict.txt` in each run directory,
`scripts/passing_runs.py`.

**Consequences.** Every XPASS must be reviewed: either the bug is fixed (drop the
entry, or the whole test now passes), or the entry's signature drifted (fix the
entry). When a fix lands, its entries are removed in the same change that
updates the bug draft's status. Entries stay tied to drafts, so a merged draft
keeps its number.

## D7. Bug process and RTL ownership

**Decision.**

- **Drafts, tracker-neutral, outside the bench.** A DUT issue is written up as a
  numbered Markdown draft in a bug-draft directory outside the bench (its
  location is a site setting), indexed in that directory's README. Drafts are
  classified as DUT bug, RTL/doc mismatch, spec/doc conflict or documentation,
  and cite the RTL, RDL, MAS and spec sections involved. Nothing in the draft or
  its index depends on a particular issue tracker; filing is a separate step.
  A draft merged into another keeps its number and file, because expected-fail
  entries cite it.
- **Candidate fixes on separate branches.** `RTL/`, `csr/` and `DOC/` belong to
  their maintainers. The bench never edits them. A candidate RTL fix lives on its
  own branch (one per draft, based on `main`, RTL change only) and is tested by
  applying it to a build-time copy of `RTL/` with `RTL_PATCH=<abs path>`; the
  build is named `-fix-<name>` and the source tree is never modified.
- **Triage method.**
  1. Reproduce the exact original signature (same checker, same message, same
     mechanism) with waves. A different failure is a different issue.
  2. Find the likely cause from waves and the RTL.
  3. Write the fix in a fresh agent or by a different person, given only the
     description of the cause (signals, times, suspect logic) and the RTL style
     guide, not the investigation's context.
  4. Rerun with the fix applied through `RTL_PATCH`.
  5. A separate judge decides whether it worked: the test passes, and the run is
     materially the same up to the original point of failure, so the triggering
     condition still happened and the fix prevented the bug. For arbitration or
     timing changes this has to be argued from waves.
  6. Capture cause, patch and before/after evidence in the draft.
  7. If it didn't work, repeat with new agents, passing on the record of
     earlier attempts.
- **Never weaken a check to pass.** When a check turns out to be wrong, the fix
  to the check cites the specification section that proves it wrong (for
  example the FDI Retrain exit rule, UCIe r1.1 8.3.3.4, corrected in the
  bringup model and driver). A failure that is the DUT's goes into
  `expected_fail.yaml`, never anywhere else.

**Why.** RTL ownership is enforced upstream (code owners), and a bench that
patched the RTL to pass would verify a design nobody ships. Tracker-neutral
drafts keep the bench publishable and portable; filing is policy that differs
per organisation. Separate fixer and judge roles counter confirmation bias: the
agent that found a cause is the worst placed to judge its own fix. Requiring the
same signature stops a triage from "fixing" a different, easier failure.

**Rejected.** *Fixing RTL in place on the bench branch*: breaks ownership and
mixes verification and design changes in one history. *Filing into a tracker
from the bench*: ties the public bench to one organisation's tools. *One agent
investigating, fixing and judging*: prone to accepting its own hypothesis.

**Where.** `RTL_PATCH` in the Makefile (copy-and-patch of `RTL/` into the
build directory), `run_list.py --rtl-patch`, `expected_fail.yaml`, AGENTS.md
"Boundaries", CODING_GUIDELINES.md "Oracles"; the bug-draft location in the
git-ignored `site/SITE.md`.

**Consequences.** A verified fix appears as XPASS on its expected-fail entries in
an `RTL_PATCH` regression, which is the evidence attached to the draft. Fix
branches are renamed after the tracker entry once filed. Some findings turn out
to be bench bugs; the draft review step checks that before anything is filed.

## D8. Test plan traceability

**Decision.**

- The test plan starts from the verification branch's
  `dv/doc/AOU_RTL_TEST_PLAN.md` (sections 2.1 to 2.22), turned into
  `docs/test_plan_items.yaml` by `scripts/gen_plan_items.py` with corrections
  from `docs/test_plan_corrections.yaml` (rewordings, duplicates merged into a
  surviving ID, items dropped as untestable on this RTL, each with a note).
- Each testlist scenario names the plan items it covers. The testlists
  themselves (`testlists/*.toml`) follow the harness schema, which has no plan
  key, so the item lists live in the sidecar `testlists/plan_ids.yaml`, keyed by
  scenario name, together with the reason of every blocked scenario.
- `make plan_status` matches every judged run under `out/` to its scenario
  (test class, plusargs, TB and CONFIG) and reports each item as covered (a PASS
  run), xfail-only, failing, blocked or not covered.

**Why.** The existing plan carries the intent of the features to verify and an
ID scheme people already use; starting over would lose both. Corrections go in a
separate file so that regeneration never loses them and each change has a
reason. Plan status only counts PASS, for the same reason coverage does (D10):
an XFAIL run went somewhere wrong.

**Rejected.** *Hand-editing the generated items*: lost on regeneration. *A
fresh plan*: loses the existing IDs and intent. *Test names as the link between
plan and runs*: one test covers different items with different plusargs and
configs, so the testlist scenario is the unit. *A test-by-test mapping to the
VIP-based testbench*: kept for a while, then removed; this bench stands on the
plan, its coverage and its checkers, not on resemblance to another bench.

**Where.** `docs/test_plan_items.yaml`, `docs/test_plan_corrections.yaml`,
`testlists/*.toml`, `testlists/plan_ids.yaml`, `scripts/plan_status.py`,
AGENTS.md "Testlists carry the plan".

**Consequences.** A new scenario is not done until `plan_ids.yaml` lists its
items; `scripts/check_testlists.py` (in `make lint`) fails on a scenario the
sidecar does not know or a sidecar entry no list has. A scenario that can't run
yet carries the `blocked` tag and its reason in the sidecar; `run_list.py` and
`sweep.py` skip it. Plan IDs are strings (`4.10` is not `4.1`).

## D9. Build configurations

**Decision.** `CONFIG` selects the T1 (and register bench) build parameters: RP
count, data width per RP, `FDI_CONFIG`, `TX_NXT_PACKING_EN` (and, in `-rxf`, the RX FIFO
parameters). Ten configurations exist (three more, `1x512-sp64-p512`,
`4xmix4211-sp128-p512` and `4xmix4211-sp128-p256`, built
`AXI_PEER_DIE_MAX_DATA_WD` below 1024 until that parameter became a localparam
fixed at the AoU maximum; see the amendment below):

| CONFIG | RPs | RP widths | FDI_CONFIG | Purpose |
|---|---|---|---|---|
| 1x512-sp64 | 1 | 512 | 1 (SP_64B) | The default: one RP, the usual data path |
| 4x512-sp64 | 4 | 512 each | 1 (SP_64B) | Multi-RP behaviour at one width |
| 3x512-sp64 | 3 | 512 each | 1 (SP_64B) | An RP count that is not a power of two |
| 4xmix4211-sp128 | 4 | 1024, 512, 256, 256 | 2 (SP_128B) | Mixed widths, every local width, 1024-bit FDI |
| 4xmix2144-sp64 | 4 | 512, 256, 1024, 1024 | 1 (SP_64B) | Mixed widths, RP2/RP3 at 1024 bits; two 1024-bit RPs on a 512-bit FDI |
| 1x256-sp32 | 1 | 256 | 0 (SP_32B) | Narrowest RP and FDI |
| 2xmix-tp64_128 | 2 | 512, 1024 | 4 (TP_64B_128B) | Two-PHY FDI, two RPs, mixed widths |
| 2x512-tp32_64 | 2 | 512 each | 3 (TP_32B_64B) | Two-PHY FDI with a 256-bit PHY0, two RPs at one width |
| 1x512-sp64-nxt | 1 | 512 | 1 (SP_64B) | `TX_NXT_PACKING_EN` 1: the registered TX packer output stage |
| 2xmix-sp64-rxf | 2 | 1024, 256 | 1 (SP_64B) | Non-default RX FIFO depths, RX FIFO register slices off |

Names describe the configuration and refer to nothing else:

- `NxW`: N remote ports (RPs) × W-bit RP AXI data width.
- `mix`: mixed RP widths (listed in the table). `mix<digits>` has one digit per
  RP, RP0 first: its width in 256-bit units (1 = 256, 2 = 512, 4 = 1024).
- `sp<B>`: single PHY with a B-byte FDI data path (`FDI_CFG_SP_<B>B`).
- `tp<B1>_<B2>`: two PHYs with B1- and B2-byte FDI (`FDI_CFG_TP_<B1>B_<B2>B`,
  built with `TWO_PHY`).
- `-nxt`: `TX_NXT_PACKING_EN` 1 (`AOU_TX_NXT_PACKING=1`): the other value of the
  AOU_TX_CORE output-stage parameter, a registered flit chunk computed from the
  packer's look-ahead state. Every other build takes the RTL default, 0.
- `-rxf`: the integrator's RX FIFO parameters changed: a different depth per RP and
  class (multiples the MAS 3.9 credit formulas divide by) and every `RX_*_FIFO_RS_EN`
  0. The other builds keep the RTL defaults, so the advertised credit is checked
  against the integration guide's defaults there and against these depths here.

The set is pairwise, not a cross product: every pair of RP count, local width and
FDI width that matters appears in some build, and every `FDI_CONFIG` value is
built. The remote die's width per RP is chosen at run time, so the up- and
down-converters (all six are instantiated across the set) are reached without
more builds. The converters and the per-RP credit and granule logic are generated
per RP, though, so the local width is a per-RP axis: the two 4-RP mixed builds
together give every RP every local width (256, 512 and 1024), and with per-RP
remote widths every (RP, local, remote) pairing. Until the coverage closure
(WP10) there was one 4-RP mixed build, with RP widths 1024, 256, 512, 256
(`4xmix4121-sp128` by the digit rule, which it predates). It never built RP2 at
256 or 1024, or RP3 at 1024, so it was retuned to `4xmix4211-sp128` and
`4xmix2144-sp64` was added. The register bench takes the same `CONFIG`, so its
coverage merges into T1's.

**Why.** Width conversion, multi-RP arbitration and FDI configurations are where
the DUT's parameterization lives, and a single build covers only one point of
each. A full cross product would multiply build and regression cost for little
gain. The integration guide puts no constraint on RP widths per `FDI_CONFIG`, so
`2x512-tp32_64` keeps 512-bit RPs and differs from `2xmix-tp64_128` in the FDI
pair alone. Every pairing of a local RP width and a remote RP width (256, 512,
1024) is legal, and the remote's width is not known when the DUT is built, so
the remote width is a run-time knob (`+remote_bytes`, per RP) and the mixed
builds cover all nine pairings. `AXI_PEER_DIE_MAX_DATA_WD` was the integrator's
promise that the remote die sends no WriteData wider than it; the default 1024
allows every pairing. It got three restricted builds (the bench limited the
remote die to the parameter): `1x512-sp64-p512`; `4xmix4211-sp128-p512`, where
a 1024-bit RP was wider than the parameter and its own reads still got
ReadData1024 (AoU 5.7: ReadData follows ARSIZE); and `4xmix4211-sp128-p256`,
the largest ratio (a 1024-bit ReadData path over a 256-bit WriteData path).

**Amendment (2026-10-20).** `AXI_PEER_DIE_MAX_DATA_WD` is a localparam fixed at
1024, the widest AoU data message: a receiver cannot know the remote die's AXI
width, so the RX data path is sized for the maximum and there is no promise for
an integrator to make. The three restricted builds, their matrix scenarios and
plan item 14.17 are retired; the remote die model stays bounded at 128 bytes
(`AOU_T1_PEER_MAX_BYTES`), and the nine width pairings remain covered by the
mixed builds through `+remote_bytes`.

**Rejected.** *One configuration* (misses the converters and the other FDI
widths). *A full cross product* (cost). *Names after a purpose or another bench*
(an earlier set did; a purpose name can read as something else, and a reference
to another bench means nothing to a reader of this one). *Telling the 4-RP mixed
builds apart by FDI or an ordinal* (`4xmix-sp64`, `4xmix2-sp64`): neither shows
the per-RP widths, and the FDI scheme breaks when two share an FDI.

**Where.** `[targets.<CONFIG>]` in `aou_sim_cfg.toml` and `aou_reg_sim_cfg.toml`
(`make configs`); README
"Build configurations"; ARCHITECTURE.md "Build configuration"; `target` in
testlist entries.

A configuration is a sim-config *target*: its defines (`RP_COUNT`,
`AXI_DATA_WD_RP*`, `FDI_CONFIG`, `TWO_PHY`, `AXI_PEER_DIE_MAX_DATA_WD`,
`AOU_RX_FIFO_ALT`) are the target's `defines`, merged over `target_defaults`,
and the Makefile and the harness runner read the same table, so a build means
the same thing in both flows. The `-assert` targets (`<CONFIG>-assert`) are the
same defines plus `ASSERTION_ON`, generated by `sim_cfg.py` rather than listed
twice.

**Consequences and follow-ups.**

- Build and output directory names key on `CONFIG`, so a rename is one change
  across sim configs, testlists, expected-fail entries, scripts and docs; don't
  rename during a regression. `scripts/plan_status.py` matches the config in a
  build directory name as a whole name, because names contain `-`.
- A new configuration goes in the sim config, the README table and this table
  together; testlist scenarios without `target` pick it up.
- A converter whose tests are XFAIL on a known bug stays weakly covered,
  because coverage counts only PASS (D10). That is intended.

## D10. Coverage policy

**Decision.**

- **Passing runs only.** Code and functional coverage merge only PASS runs. FAIL,
  XFAIL (even on a known bug) and unjudged runs never count, and every report
  states how many runs were merged and excluded.
- **Code coverage scope.** The DUT and its hierarchy only: `AOU_TOP` under T1
  (`cov/config/vcs/cov_t1.hier`), `AOU_CORE_TOP` under the register bench
  (`cov/config/vcs/cov_reg.hier`), never the testbench. On VCS the register bench's passing
  runs are merged into T1's report with `urg -map` onto `AOU_CORE_TOP`; Verilator
  and Questa merge the files directly.
- **Exclusions at database build time.** Cells an integrator replaces, and
  generic memory macros, are cut out of the coverage database at compile time
  through `cov/config/vcs/cov_exclude.hier`, each entry with its reason and a citation: the
  CDC synchroniser, the glitch-free DFT reset mux and the scan-reset buffer
  (integration guide 8.7 and 3.13.1), and the behavioural two-port SRAM model
  (`AOU_TPSRAM`, a stand-in for a compiled macro; the controllers around it stay
  in). IP-specific logic, including the asynchronous APB bridge, stays in.
- **Dead code is excluded item by item at report time.** Line and branch items
  that no stimulus can reach, because a higher-priority arm always takes the
  case, go in `cov/config/vcs/cov_exclude.el`, which `make cov_report` passes to
  `urg -elfile` (`COV_EL=` reports without it). Each item carries its reason;
  URG's checksums drop an item whose RTL has changed, so it is reviewed again.
  Code reachable only by illegal stimulus stays a hole: illegal stimulus is out
  of scope, not dead code. First entries: the six time-out arms of
  `AOU_ACTIVATION_CTRL` that #108's abort pre-empts.
- **Reset-only FSM transitions are excluded (user decision).** VCS FSM coverage
  filters out transitions that only an asynchronous reset in the middle of a
  state makes (`-cm_fsmresetfilter`, `cov/config/vcs/cov_fsm_reset.filter`;
  `COV_FSM_RESET=1` keeps them). Hitting them needs resets at cycle-exact
  moments and shows only that the reset branch runs. Reset correctness is
  checked instead by running the reset tests on an X-propagation build
  (`XPROP=tmerge|xmerge`) and checking that no DUT output or state register is
  X after reset is released.
- **Functional coverage is counted by the bench.** Every testbench covergroup
  feeds a coverage service that counts bins itself and writes `fc.json` per run;
  covergroup and service take their bins from one table macro, so they can't
  drift. `make fc_report` union-merges passing runs. The closure target is 100%.
  Any waiver needs explicit review; an unreachable bin stays a hole until then.
  v0.8 bins are included (tagged `v0.8`, reported apart, not waived), and
  white-box bins on DUT internal state are allowed. A bin that can't mean what
  it says (an AXI-illegal cross cell, a field the wire doesn't carry) is a
  covergroup bug: it is ignored or made illegal in the service, not waived.
- **Closure.** Closure is measured on the union of every configuration. The
  plan, the gap analysis and the owner's decisions on it are in
  [COVERAGE_CLOSURE.md](COVERAGE_CLOSURE.md).

**Why.**

- A failed or expected-failure run stopped early or went somewhere wrong;
  counting it would credit the bench with behaviour it didn't check.
- Excluded cells are replaced by the integrator or signed off formally, so their
  simulation coverage measures nothing about the IP. The aim is to measure the
  right scope, not to raise the numbers. Cutting them at database generation
  (rather than filtering reports) keeps one source list and makes every report
  agree.
- Verilator 5.052 compiles covergroups but scores them as 0%, and VCS weights
  coverpoints and crosses its own way; bins counted by the bench compare bin for
  bin across simulators.
- v0.8 bins are there because the RTL and the bench are heading to v0.8; white-box
  bins are allowed because some protocol states are visible only inside the DUT.

**Rejected.** *Merging every run*: inflates coverage with unchecked behaviour.
*Report-time exclusion only* (`urg -hier`): kept only as a preview,
`COV_EXCLUDE_PREVIEW=1`, for databases built before an entry was added. *The
simulator's covergroup scores as the number*: not comparable across simulators,
zero on Verilator. *Waiving holes to reach a target*: waivers are reviewed case
by case.

**Where.** `COV=1`, `make cov_report`, `make fc_report`, `COV_WITH`,
`COV_EXCLUDE_PREVIEW` in the Makefile; `cov/`; `scripts/passing_runs.py`,
`scripts/fc_report.py`, `scripts/cov_summary.py`; README "Coverage".

**Consequences.** Coverage numbers are always quoted with their merged and
excluded run counts. A new exclusion needs a citation and review. Verilator and
the commercial tools count code coverage differently; compare uncovered items
per module, not headline percentages. Later stages of the functional coverage
plan are open items.

## D11. Waves and debug

**Decision.**

- `WAVES=1` is a run-time knob: the same build dumps waves into the run
  directory without a rebuild. On VCS a generated UCLI script dumps FSDB; on
  other simulators the bound module `tb/aou_waves.sv` dumps FST (Verilator), SHM
  or VCD on `+waves`.
- Builds are wave-capable by default (Verilator compiled with FST tracing, VCS
  with the Verdi design database). `WAVES_BUILD=0` gives a lean build in its own
  `-nowaves` directory, and `WAVES=1` refuses to run against it.
- Debug method: group failures by signature (checker or rule ID and message with
  times, IDs and addresses stripped), rerun only the shortest failing run of each
  signature with `WAVES=1` (same test and seed, new `RID`), and debug from the
  waves together with every log in the run directory.
- Waves are read as text with open-source readers (`scripts/waveq.py`,
  `scripts/axi_outstanding.py`, through pywellen; FSDB through Verdi's
  converter). The procedure, commands and signal map are in `docs/WAVE_DEBUG.md`
  and `docs/AXI_OUTSTANDING.md`, tool-neutral so any agent or person can follow
  them.

**Why.** Verilator can only trace code built with tracing, so a lean default
would turn every debug into a rebuild of several minutes; the build cost of
wave support is small by comparison. Dumping on every run would waste time and
disk. One wave rerun per signature, not per failure, keeps debug proportional
to the number of distinct problems. Logs leave room for guessing; waves answer
what the wires did. Text readers let a script or an agent query waves
directly, and open readers keep the public tree free of internal tools.

**Rejected.** *Lean builds by default* (debug needs a rebuild). *Always dumping*
(cost). *Internal wave-query tools in the tree* (not public; an optional hook,
`WAVEIO_WQ`, can point to one outside it).

**Where.** `WAVES`, `WAVES_BUILD` in the Makefile; `tb/aou_waves.sv`;
`scripts/waveq.py`, `scripts/waveio.py`, `scripts/axi_outstanding.py`;
`docs/WAVE_DEBUG.md` and `docs/AXI_OUTSTANDING.md` (with thin `.claude/skills/`
wrappers at the repository root); AGENTS.md "Debug failures from waves".

**Consequences.** Regressions may use `WAVES_BUILD=0` builds, but a failure's
wave rerun then needs the default build.

## D12. Compute, run artefacts and site settings

**Decision.**

- **Batch only.** All builds, simulations and regressions go through the site
  batch system (LSF where `bsub` exists; `LSF=0` runs locally). The login host
  does editing, git, grep and lint only. Job I/O stays on a shared filesystem.
  Requests are sized from measured usage recorded per job in
  `build/metrics.jsonl`.
- **One directory per run, outside `build/`.** Each `make run` creates
  `out/<build>/<test>.rid.<RID>.seed.<SEED>.time.<timestamp>.uid.<uid>/`
  atomically, holding `sim.log`, `run.sh`, the job output, the verdict and the
  coverage data. Merged reports go to `out/<build>/merged/`. `make clean` leaves
  `out/` alone.
- **Regressions through `run_list.py`.** Several testlists share one pool of
  `-j` runs, and a running regression is steered through a control file with
  `scripts/run_ctl.py`: jobs in flight, pause, drain, scheduler priority and
  queue, and launch order (`fifo`, `shortest`, `failed-first`). Where the site
  provides job-modify hooks, a priority or queue change also reaches this
  regression's own pending jobs, and no others.
- **`run_list.py` does not build.** `make build` for the same SIM, TB and CONFIG
  comes first, and again after any testbench or RTL change.
- **Two executors, one grader.** The harness runner (`run_dv.py`, with
  `--executor lsf`) is a second way to start the same builds and scenarios. Its
  regression mode draws its own seeds, so a seed-exact repeat of a standalone
  regression runs one `--run-only` leaf per scenario and seed
  (`scripts/sweep.py`). Whatever started a run, the verdict is the bench's:
  `scripts/judge_run.py` applies `check_run.py` and `expected_fail.yaml` to the
  harness's leaf logs and reports where the harness's own PASS/FAIL (from the
  testlist's `expect_fail` keys) disagrees, and `scripts/compare_results.py`
  compares two regressions' `results*.csv` and fails on any verdict that got
  worse.
- **Site specifics in `site/`.** Scheduler options, licence reservations,
  simulator module names, the bug-draft location and internal tool notes live in
  the git-ignored `site/` (`site.mk`, included by the Makefile; `SITE.md`;
  `public_patterns.txt`).

**Why.** Shared compute needs good citizenship, and measured requests let more
jobs run at once. Run artefacts inside build directories get clobbered by
rebuilds and cleans, and timestamps alone collide; the enumerated name lets a
test and seed run any number of times. Long regressions need their parallelism
and priority adjusted as the farm's load changes, without losing finished
work by restarting. Separating build from run lets one build serve several run
lists and avoids concurrent regressions racing to rebuild a `simv` in use.
Keeping site details out of tracked files is what keeps the tree publishable
(D13).

**Rejected.** Each alternative named in Why: running on the login host, run
directories inside `build/`, restarting to change `-j`, building on demand, and
site options in the committed Makefile.

**Where.** Makefile (`LSF`, `BUILD_MEM`, `RUN_MEM`, `RUN_CPUS`, `JOB_PRIORITY`,
`JOB_QUEUE`, `RID`), `scripts/new_run_dir.sh`, `scripts/run_list.py`,
`scripts/run_ctl.py`, `scripts/test_run_list.py`, `scripts/job_metrics.py`,
`scripts/sweep.py`, `scripts/judge_run.py`, `scripts/compare_results.py`,
`site/` (ignored), README "Compute", "Regressions" and "Through
tt-oca-harness".

**Consequences.** A regression after a source change without a rebuild runs a
stale `simv`; nothing warns about it yet (Open items).

## D13. Public repository hygiene and licensed material

**Decision.**

- Tracked files and commit messages contain no internal references: no site
  paths, private hostnames, home directories, queue or module names, licence
  details, internal tool names or issue-tracker keys.
  `scripts/check_public.py` (`make check-public`) scans the tree and, with
  `--range`, the lines added and the messages of a commit range, using built-in
  patterns plus the site's own list in `site/public_patterns.txt`. A line can
  opt out explicitly with the marker `public-ok`, for a pattern documented on
  purpose.
- Licensed or member-only material is never committed: no Avery or Synopsys
  SVT code, no Arm `Axi4PC` (BP063; each user downloads it and `make setup`
  unpacks it into the bench's git-ignored `.deps/BP063/`), no UCIe
  specification text. Specs are cited by section number.
- New files carry the SPDX header.

**Why.** The bench and its history go back to the public repository. History
is published too, so scanning only the tree is not enough. Arm's licence allows
use but not redistribution, and the UCIe specification is member-only.

**Rejected.** *Scrubbing at push time only* (history would already carry the
references). *Site options and patterns in tracked files* (the pattern list would
itself leak the names).

**Where.** `scripts/check_public.py`, `make check-public` (`PUBLIC_BASE`),
`.gitignore` (`site/`, `.deps/`), README "Public repository" and "Optional: Arm
AXI4 protocol assertions", CODING_GUIDELINES.md "Licensing".

**Consequences.** Run `make check-public` before anything leaves the site.
Earlier history on the integration branch carried internal references, which
the planned squash removes (Open items).

## D14. Bug-escape suite (retired)

**Amendment, 2026-10-21: retired.** The escape patches, `testlists/escape.toml`,
`scripts/escape.py`, `ESCAPE=` and `make escape` were removed. The suite did its
job: it proved that every checker could fire and that the bench caught the bugs
fixed on `main` so far. Keeping thirteen RTL patches applying against moving RTL
had come to cost more than that evidence was still worth. `RTL_PATCH` (D7),
which shared its copy-and-patch mechanism, stays. Rule fire evidence now comes
from negative tests only (D4). The text below is the decision as it stood.

**Decision.** Every real bug fixed on `main` must make the bench fail when it
comes back. `escape/<id>.patch` reverses one fix; `make build ESCAPE=<id>`
applies it to a build-time copy of `RTL/` (the same mechanism as `RTL_PATCH`),
and `make escape` runs each entry of `testlists/escape.toml` on the clean
and escape builds. A bug is CAUGHT when the clean run passes and the escape run
fails with the entry's signature (a regex over the error lines); otherwise it is
ESCAPED, or CLEAN-FAILS when the clean run itself fails. `mut_*` patches are RTL
mutations, not fixes, that break one rule, to prove a new checker fires.

**Why.** Coverage shows what was exercised, not what would have been detected.
Re-introducing historic bugs is direct evidence that the bench catches the kind
of bug the design actually had. Matching a signature rather than "any failure"
proves the right checker caught it. Mutations give fire evidence for rules no
real bug has triggered (D4).

**Rejected.** *Trusting coverage or test count as evidence of detection.*
*Patching the source tree* (ownership, D7).

**Where.** `escape/`, `testlists/escape.toml`, `scripts/escape.py`,
`ESCAPE` and `make escape` in the Makefile; README "Bug-escape suite" (the
table of escapes and what catches them).

**Consequences.** Each new fix on `main` gets an escape patch and entry. Escape
runs go to `out/<build>-esc-<id>/` and are ignored by plan status. A fix that
only a particular simulator's compile catches is marked with `build: <sim>`. When
an escape can't be a literal reversal (the surrounding RTL changed), the patch is
the closest faithful mutation and the README says why.

## D15. Coding guidelines and guardrails

**Decision.** [CODING_GUIDELINES.md](../CODING_GUIDELINES.md) is binding, `make
lint` (Verible and Verilator `-Wall`) must stay clean, and new code gets no lint
waivers. [AGENTS.md](../AGENTS.md) states the working rules for people and agents.
The reasons behind the main rules:

- **One layer per package, imports only downward; no hierarchical references
  from classes; interfaces only through `uvm_config_db`.** Each layer can be
  tested alone and swapped (D3), and no class depends on one top's hierarchy,
  so the same classes serve the T1, register, unit and self-test benches.
- **VIP-neutral `aou_axi_txn` everywhere above the agents.** Keeps the AXI agents
  replaceable (D1).
- **A Verilator-safe subset.** Every file must build on both simulators (D2).
  Checked randomization macros exist because Verilator without a solver returns
  0 and leaves every field zero, which looks like a valid but useless stimulus.
  The rules on `dist`, dynamic arrays, `randcase` and comments record Verilator
  5.052 faults found the hard way; dynamic arrays filled in `post_randomize` are
  also far faster there. New constructs get a probe on both simulators first.
- **Report IDs and rule IDs.** Message prefixes are what verdicts and the rule
  ledger match on (D4, D6); `$display` bypasses both.
- **Clocking blocks only, no `#delay` in classes.** Race-free sampling that
  behaves the same on both simulators.
- **Oracles from the documents, never the RTL; known bugs only through
  `expected_fail.yaml`.** D5, D6, D7.
- **Commits: one concern each, bench changes separate from RTL, tests with the
  model change they exercise.** Lets a change be reverted or moved between
  branches on its own, and keeps bench work separable from design work.

**Rejected.** *Adopting a full external style guide unmodified.* The lowRISC
SystemVerilog and DV guides are the base, restricted to what Verilator 5.052
handles. *Lint waivers for new code.* Waivers accumulate and hide new findings.

**Where.** CODING_GUIDELINES.md, AGENTS.md, `lint/`, `.verible_waivers`,
`make lint`. **Consequences.** The waiver files list only findings in files inherited from
PR 80 and the old bench. A construct that fails on one simulator is a guideline
change, not a local workaround.

## D16. One bench, standalone first, the harness as a consumer

**Decision.**

- `hw/ip/aou/dv` holds one verification environment, the SystemVerilog UVM bench, in
  the tt-oca-dv layout (`tb/`, `uvm/{env,seq_lib,tests}`, `cov/`, `testlists/`,
  `docs/`, `scripts/`, one `*_sim_cfg.toml` per top). The cocotb flow is
  retired; CI runs the UVM smoke on Verilator instead.
- The bench's home is this repository. It builds, runs, grades and documents
  itself from here with nothing but `make setup`; the standalone Makefile flow
  is the flow of record for regressions and gates.
- tt-oca-harness consumes it: the repository is vendored under
  `vendor/tenstorrent/aou/upstream/` and the harness runner reads the same sim
  configs and testlists (where the bench sits in the harness, and how the sim
  configs name their paths, is D17). Nothing of the bench moves to the harness,
  and nothing in the harness is needed to run the bench.
- Where the two disagree, the harness schema is followed where it costs
  nothing (directory names, sim-config and testlist keys, `expect_fail`,
  `tags`, SPDX headers), and the bench's own mechanism is kept where the
  harness has none or a weaker one: the grader and `expected_fail.yaml` (D6),
  the plan sidecar (D8), the enumerated run directories
  and the control file (D12). Each such choice is a line in `OPEN_ITEMS.md`
  until it is either adopted by the harness or revisited here.

**Why.** Two environments for one DUT cost two of everything and prove nothing
the other does not. The harness layout is what the other OCAH DUTs use, so a
reader moving between them finds the same places, and the same sim config
serves both runners. Keeping the bench self-sufficient is a requirement of this
repository: it is public and standalone, is vendored into the harness at tags,
and must keep passing for a reader with no harness checkout.

**Rejected.** *Moving the bench into the harness*: the repository would lose its
own verification and every aou-rtl change would need a harness change. *A
harness-specific copy of the testlists or sim configs*: two sources of truth
that drift. *Dropping Verilator because the harness runs VCS*: Verilator is
what a public reader has (D2); the harness side is an open item for it. *The
harness's `expect_fail` alone as the verdict*: it keys on a log string per
scenario and cannot express per-check, per-config or per-encoding expectations,
nor XPASS (D6). *Scenario-named tests without plusargs* (the harness pattern):
left as they are, with the plusarg scenarios named in the testlists, because
renaming eighty test classes was out of this migration's scope; it is the first
open item.

**Where.** The layout itself; `aou_*_sim_cfg.toml`; `testlists/`;
`scripts/sim_cfg.py`, `testlist.py`, `check_testlists.py`, `sweep.py`,
`judge_run.py`, `compare_results.py`; `.github/workflows/uvm-smoke.yml`; README
"Getting Started" and "Through tt-oca-harness"; `OPEN_ITEMS.md`.

**Consequences.** A harness schema change is a change to `sim_cfg.py`'s key
sets and `check_testlists.py`, caught by `make lint`. The harness pin of the
OCAH library (`scripts/get_ocah_lib.sh`) and the harness's pin of this
repository move independently; a bump of either is tested by the smoke on both
sides. `OPEN_ITEMS.md` is the list of what the migration deferred, and a change
that closes an item removes it there in the same commit.

## D17. The bench lives at hw/ip/aou/dv, one path space for both consumers

**Decision.**

- The bench's directory in this repository is `hw/ip/aou/dv`, the path at
  which tt-oca-harness finds a DUT's bench by convention
  (`hw/<group>/<dut>/dv`, `tools/dv/runlib/duts.py`) and lays out its own IPs
  (`hw/ip/<name>/{rtl,dv,regs,doc}`). `VERIF/` is gone.
- The sim configs name every bench path from the repository root as
  `hw/ip/aou/dv/...`, with no vendored prefix. `scripts/sim_cfg.py` resolves
  that prefix against this repository and `hw/common/dv/vip/` against
  `.deps/ocah_lib`, and its `check` rejects a path under `vendor/`. A harness
  checkout that places this directory at `hw/ip/aou/dv` reads the files
  unchanged and needs no `duts.toml` entry for `aou`, `aou_reg`, `aou_l3_unit`
  or `aou_axi_selftest`.
- `RTL/`, `csr/`, `DOC/` and `INTEG/` stay where they are; whether they follow
  into `hw/ip/aou/{rtl,regs,doc}` is the RTL maintainers' decision.

**Why.** The sim configs had two readers and one of them, the standalone
Makefile, had to translate the harness's vendored root
(`vendor/tenstorrent/aou/upstream/VERIF/`) back onto the repository on every
read, while the harness's own layout rule expects a bench under `hw/`, not
under a vendored tree, and found this one only through four registry entries.
Putting the bench at the conventional path in both repositories makes the path
in the file the path on disk for both, removes the mapping and the registry
entries, and gives a reader moving between OCAH DUTs the same place to look.

**Rejected.** *Keeping `VERIF/` and the vendored prefix*: the mapping and the
registry entries are a standing cost, and the harness's layout rule stays
unmet. *`hw/aou/dv` (the flat form)*: also discovered by convention, but the
harness groups its IPs under `hw/ip/`, and AoU is one. *Moving `RTL/` and
`csr/` in the same change*: those trees have their own consumers (the Bender
`aou` target, the collateral flow, the integration guide) and owners; the bench
move does not depend on them.

**Where.** The directory; `aou_*_sim_cfg.toml`; `scripts/sim_cfg.py`
(`DV_PREFIX`, `ROOT`, `check`); `Makefile` and `scripts/regen_ral.sh`,
`scripts/get_peakrdl.sh` (`ROOT` four levels up); `lint/verilator_lint.vlt`;
the repository's `.gitignore`, `.github/CODEOWNERS` and
`.github/workflows/uvm-smoke.yml`.

**Consequences.** On the harness side the bench must land at `hw/ip/aou/dv`
rather than under `vendor/`: a second Bender `vendor_package` with
`target_dir: hw/ip/aou` and a `mapping` from `hw/ip/aou/dv` to `dv`, or an
equivalent the harness maintainers prefer, and the removal of the four
`duts.toml` entries and of `"VERIF"` from the existing package's
`include_from_upstream`. Whether a Bender-managed tree under `hw/` is
acceptable under the harness's "never edit a vendored tree" rule is their
call; until then the harness branch that vendored `VERIF` is stale
(`OPEN_ITEMS.md`, "Vendored location"). Anything that computes the repository
root from the bench's position (the Makefile, the two shell scripts,
`sim_cfg.py`) is four levels deep now; a script that assumed one level would
have reached `hw/ip/aou`.

## D18. The system resets both dies after an FDI link-down

**Decision.**

- When the FDI link goes down (LinkReset, LinkError or Disabled, started by
  the Adapter or the remote die, or the LinkError the DUT raises on
  `lp_linkerror`; a deactivation never takes the link down, and the DUT
  never restarts it), the bench's software and system model resets both
  dies while the link is down: AOU_SW_RESET on the DUT (the bring-up
  controller, outside AOU_CORE, keeps its state) and the remote die's reset
  of its AoU state (`reset_flush()`). Software then restarts the link on the
  UCIe controller (the Adapter model's `sw_restart_delay` in Reset before it
  trains again), reprograms the last `program_cfg()`, and the dies activate
  again from DISABLED.
- It applies unless both dies are cleanly DISABLED with no activation message
  pending or in flight in either direction (`aou_quiet()`: the DUT and the
  remote DISABLED, the remote's activation queue empty). A received
  ActivateReq or a queued ActivateAck keeps the DUT out of DISABLED, so those
  cases reset. The DUT's own last DeactivateAck leaves it DISABLED once
  handed to TX; that case is covered by the remote, which cannot be DISABLED
  until it receives that Ack. Non-activation messages still in a TX path
  when both are DISABLED (a CrdtGrant permitted after DeactivateAck) are not
  seen; one would surface as a checker failure, not be hidden.
  Ordinary deactivate-then-relink flows are quiet and unchanged.
- `relink()` applies it, and so does `link_event()` for a link-down the
  Adapter brings back up by itself; that hook re-activates the dies itself,
  so a test that wants to drive re-activation after such an event sets
  `+sysrst_on_linkdown=0`. `recover()` and `sw_reset()` already reset the DUT
  for the error LinkReset (MAS 7.3.6). `cfg.sysrst_on_linkdown`
  (`+sysrst_on_linkdown=0`) turns it off.
- AOU_FDI_CHECKER resets all of its state on every FDI Reset.

**Why.**

- The owners' documents assign AOU_SW_RESET only to the LinkReset that
  AOU_CORE requests itself (MAS 7.3.6, integration guide 6.5.3). They are
  silent on the other link-downs, and the RTL never clears its activation
  state on one.
- AoU v0.8 reads as the interface state not surviving an FDI reset (9.1/9.2,
  8.3.3, 8.2/8.4). UCIe flushes the Adapters' pipelines on LinkReset and
  Disabled, so a message in flight across the reset may be lost.
- The project's principle is to keep the hardware simple and let software or a
  system reset controller own clearing state.
- Without the reset, an exchange split across the reset (the DUT's queued
  ActivateAck going out after the relink) is out of sequence under a checker
  that starts afresh at the reset.

**Rejected.**

- *A checker activation epoch that survives an FDI reset* (gated on the
  DUT's own DISABLED). The state before the reset may be what caused it, and
  the checker would trust the device under check about when to forget its
  model.
- *Resetting on every link-down.* That would churn every deactivate-and-relink
  test for no gain, because a quiet interface has nothing to clear.
- *An RTL change that clears the activation FSM on link-down.* It is neither
  sufficient (the queued TX flit survives) nor documented.

The owner has since decided (2026-10-22) that a routine deactivation
leaves the FDI link up, that only an error takes it down from the IP, and that
restarting the link after a reset or error is software's job on the UCIe
controller, never the IP's. This decision's "software resets both dies,
restarts the link, reprograms and re-activates" is therefore the documented
flow. Still open (011): who resets AOU_CORE after a link-down it did not
request, and must a flit already in its TX path be dropped?

## D19. The local AXI agents are reset with AOU_CORE

**Decision.**

- The bench's local AXI managers and subordinates on the DUT's S and M ports,
  and the Axi4PC checkers on them, are on the DUT's AXI-port reset
  (`tb_top.axi_port_rst_n`: the core reset read from the DUT, I_RESETN and
  AOU_SW_RESET together). `sw_reset_core()` flushes the environment with
  `bus_reset = 1` once the core reset is sampled, so the software reset is a
  bus reset to the agents: queued and in-flight transactions end as aborted,
  the drivers idle their outputs and restart once the reset is over.
- The scoreboard treats a write on the bus at the AOU_SW_RESET request
  (`reset_outstanding`) as lost or landed whatever its response; a read in the
  same window may end with SLVERR (MAS 7.3.6 defines no response for it).
- No check judges the AXI protocol across the software reset on the DUT's
  ports: T1-L28 (S-port handshakes inside the reset pulse) and T1-L26 (an M-port
  response presented before the reset and not accepted after it) are retired,
  with every expected-fail entry that rested on them, and so is the bench's
  support for an RTL-side guard that would have kept the ports AXI-clean.

**Why.** The owner's decision (2026-10-25): an error that needs AOU_SW_RESET or
I_RESETN loses every AXI transaction in flight or queued in the block, and the
rest of the AXI logic attached to it is reset as well or has its own recovery
mechanism. That is now what the MAS (7.3.6) and the integration guide (3.1.1,
6.5.3) say. A bench whose agents kept driving the ports across the reset, and
checkers that expected the DUT to keep the AXI protocol through it, were testing
a contract the IP does not offer; the stalls, shifted W-to-AW pairing and
orphan responses they reported were the bench's own doing. Modelling the reset
peers the integration guide requires makes those scenarios pass and leaves
T1-L29 (the RX FIFOs are empty at the release of AOU_SW_RESET, and no beat held
across it reaches an M port) as the one DUT-side check of the software reset.

**Where.** `tb/tb_top.sv`, `tb/aou_axi4pc_gate.sv`, `uvm/env/aou_t1_env.svh`
(`reset_flush`, `sw_reset_window`), `uvm/env/aou_base_test_seq.svh`
(`sw_reset_core`), `uvm/env/axi/aou_axi_monitor.svh`, `uvm/env/aou_scoreboard.svh`,
`uvm/env/aou_t1_sw_reset_chk.svh`, `expected_fail.yaml`, `checkers/rules.csv`;
[ARCHITECTURE.md](ARCHITECTURE.md) "Reset contract as implemented".

**Consequences.** A test that wants the DUT's ports to stay protocol-clean across
AOU_SW_RESET has no such expectation to lean on. The RX FIFOs (AOU_FIFO_RP) are
on the core reset together with AOU_CORE, so nothing the reset lost is presented
on a port afterwards; the managers' stale window and the Axi4PC gate stay as
defensive measures only, and `aou_sw_reset` is write-only and self-clearing in
the RDL (a write of 1 resets the bit with every other SFR).

## Open items

- **Functional coverage stages FC2 and FC3.** FC1 (the counting service, every
  existing covergroup, `make fc_report`) is done, and so are FC2's bin
  corrections (COVERAGE_CLOSURE.md 3.1). The later stages add the AoU
  protocol, FDI behaviour and cross-layer groups of the functional coverage plan.
  FC3 includes listing the concrete FDI rule changes from UCIe r1.1 to r2.0 for
  the signals this DUT has, so that the owner can decide which to cover (D5).
- **History squash.** The integration branch is to become the three PR 80
  commits, kept with their authorship, plus one squashed commit holding the
  overhaul and this document. `make check-public` then runs over the new range;
  the squash also drops internal references that earlier commits carried
  (D13). The old branch is kept for reference.
- **Stale `simv` warning.** `run_list.py` should warn when the build is older
  than the testbench or RTL sources it was built from (D12).
- **Xcelium coverage.** Xcelium builds and runs but has no coverage flow and no
  full-regression matching (D2). Questa's run and coverage are also untested.
