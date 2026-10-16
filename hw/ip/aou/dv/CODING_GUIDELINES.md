<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# hw/ip/aou/dv coding guidelines

Rules for the UVM testbench. They draw on the lowRISC SystemVerilog and DV
style guides, restricted to what Verilator 5.052 handles, since every file must
build on Verilator and VCS. `make lint` checks what a tool can check; review
checks the rest.

## Structure

- One class per file, named after the class (`aou_flit.svh` holds `aou_flit`).
- One package per layer: `aou_fdi_pkg` (L1), `aou_lsm_pkg` (L2), `aou_l3_pkg`,
  `aou_axi_pkg` (L4a/L4b), `aou_env_pkg`, `aou_test_pkg`. A layer imports only
  layers below it.
- Classes never use hierarchical references. Interfaces reach classes only
  through `uvm_config_db`, with the full parameterized type spelled out on every
  `set` and `get`.
- The scoreboard, predictors, sequences and tests use only the VIP-neutral
  `aou_axi_txn`. An AXI agent's own item type stays inside its adapter.

## Naming

- lower_snake_case for everything except parameters and macros (ALL_CAPS).
- Suffixes: `_if` interface, `_pkg` package, `_e` enum, `_t` typedef,
  `_cfg` config object, `_item` sequence item, `_seq` sequence, `_test` test,
  `_vseq` virtual sequence.

## UVM

- Register every class with the factory. One config object per agent.
- Report through `` `uvm_info/warning/error/fatal `` only, never `$display`.
  The report ID is the class name. A checker's report starts with its rule ID
  (`AOU-R16:`, `FDI-R12:`, `AXI-R03:`), and the rule appears in
  `checkers/rules.csv`.
- No `#delay` in classes. Time passes through clocking blocks, with one
  clocking block per clock domain. Reset belongs to the clock/reset agent.
- Each scenario declares the test-plan IDs it covers under its name in
  `testlists/plan_ids.yaml`.

## Verilator-safe subset

- Drive and sample a signal only through a clocking block, never also raw.
- Randomization (Verilator solves with z3 at run time; `make setup` installs it):
  - Check every `randomize()` through `` `AOU_RANDOMIZE(obj) `` or
    `` `AOU_RANDOMIZE_WITH(obj, {...}) ``, which fail fatally. Without a solver,
    Verilator returns 0 and leaves every field zero.
  - Constraints may use ranges, `inside`, enums, implication, solve-before,
    `soft`, `unique`, `randc` and `.sum() with`.
  - Don't combine `dist` with rand dynamic arrays or with an inline `with`
    on the same variable; Verilator gets both wrong. Pick the bucket in
    `pre_randomize` with `randcase` and apply it through `soft` implications.
  - Dynamic arrays (beats, payload) aren't `rand`. Size and fill them in
    `post_randomize` with `$urandom`. That's also about 100× faster on Verilator.
- Don't start a comment with the word "Verilator": Verilator parses it as a
  pragma and fails the build.
- No `return` (or other jump) inside a `randcase` arm: Verilator 5.052 fails
  on it nondeterministically (internal fault in V3Width/V3Active, or an
  undefined `__Vrandcase` symbol depending on `--output-groups`). Assign in
  the arms, or pick with `$urandom_range` and `case`.
- Covergroups: coverpoints and crosses only; FSM transitions as explicit
  (previous, current) bins; no `get_coverage()` on a coverpoint.
- Our own SVA: `|->`, `|=>`, `##N` only. Richer checks go in monitor code.
- The first use of any other construct gets a small probe on both simulators
  before it spreads.

## Oracles

- Expected behaviour comes from the AXI4, UCIe and AoU specifications and the
  MAS, never from reading the RTL.
- Where the RTL and the documentation disagree, the test follows the
  documentation and the disagreement is filed.
- A test that fails because of a known DUT bug goes in `expected_fail.yaml`
  with the bug ID and the exact failing check. It is never silenced any other
  way.

## Licensing

- New files carry the SPDX header above.
- Nothing from Avery, Synopsys SVT or Arm is committed. Arm's `Axi4PC` is
  optional and lives in the git-ignored `tools/BP063/` (see README).

## Commits

- Short subject lines. Testbench changes stay separate from RTL and from `dv/`.
- Every model change arrives with a test that exercises it.
- Changes to shared packages keep `make test` (T1 bring-up) and `make lint`
  passing on both simulators.
