<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Open items from the tt-oca-dv layout migration

What the move of the bench into the tt-oca-dv layout and the harness runner
(DECISIONS.md D16) left for later, with the reason each was deferred and what
closing it takes. An item is removed here in the commit that closes it. The
standalone flow is complete without any of them; most describe what the harness
leg does not yet do, or where the bench keeps its own mechanism instead of the
harness pattern.

## Tests and scenarios

- **Scenario naming.** The harness pattern is one test class per scenario,
  named `aou_<area>_<behavior>_test`, with the scenario name equal to the class
  name and no plusargs. The bench's tests take plusargs, so the testlists name
  the plusarg variants as scenarios (`<class>.<slug>`, the slug derived from the
  plusargs) over the same class. Closing it means one thin class per variant
  (or an owner decision to accept `args` in the testlists), `MinDefaultLoops`
  and `create_scenario_seq` adoption per test, and renaming the classes whose
  names do not follow the pattern. The dot and the plusarg slug in today's
  scenario names are the visible cost.
- **`aou_fdi_t1_bringup_test` as the sanity test.** `aou_sanity_test` is a new
  class on `ocah_test` that runs the bring-up sequence; the bring-up test it
  duplicates was not rewritten over it, so both exist until the test classes
  move to the scenario pattern.
- **Seeding.** A virtual sequence that wants its draws replayable calls
  `seed_scenario_rng()` from the base sequence; the harness's per-scenario seed
  hook is not used. Each simulator takes the seed through its own switch
  (`+ntb_random_seed` on VCS, `+verilator+seed+N` on Verilator), set by the
  Makefile; the harness runner sets the VCS one.
- **`l3_unit` and `axi_selftest` testlists.** New in this migration: one
  scenario per test class, one seed each, no plan items. They had no run list
  before (the Makefile ran the classes by hand), so they carry no baseline.
- **Per-entry timeouts.** The harness testlist schema has `timeout_sec` per
  scenario; the lists do not set it, so the runner's default applies, and the
  standalone flow relies on the bench's own watchdogs. Set per scenario once
  the harness leg's timings are measured.

## Grading and expected failures

- **`expected_fail.yaml` versus `expect_fail`.** The bench's grader
  (`check_run.py` with `expected_fail.yaml`) is the verdict in both flows:
  `judge_run.py` applies it to the harness's leaf logs. The testlists also
  carry the harness's `expect_fail`/`expect_fail_match` keys for the entries
  whose expected failure is deterministic across seeds and configurations, so
  the harness's own grading agrees with the bench's on those; the entries that
  are per-config, per-encoding (`fdi_enc`), `seed_dependent` or `requires:`
  conditional have no `expect_fail` and show as FAIL to the harness until the
  schema can express them. XPASS has no harness equivalent.
- **Blocked scenarios.** The plan said `module = { uvm = false }` for
  scenarios that cannot run yet; the runner rejects that key, so blocked
  scenarios carry the `blocked` tag and their reason in
  `testlists/plan_ids.yaml`, and `run_list.py` and `sweep.py` skip them. A
  harness-side convention for blocked scenarios would replace the tag.

## Harness leg

Consumption through tt-oca-harness `run_dv.py` was taken out of the layout
move and is a follow-up once the standalone bench is accepted. What the move
left in place for it costs the standalone flow nothing: the runner's keys in
the sim configs (`[frameworks.uvm]`, `build_dir`, `[build.options]`,
`[build.vcs].uvm_lib`), `scripts/sweep.py` and `scripts/judge_run.py`, and the
`+aou_config` argument on the perf scenarios (the runner has no per-target
run-time arguments; the Makefile adds the same argument itself). None of it
has been accepted against the standalone baseline: a first harness sweep on
the runner's default `uvm-1.2` built and ran every target but flipped about a
tenth of the seed-dependent verdicts in both directions, which is what led to
the `uvm-ieee-2020-2.0` pin below; the sweep on that library was not completed.

- **Verilator through `run_dv.py`.** The harness lists Verilator for cocotb
  only. The standalone flow keeps Verilator (pinned uvm-core, `--timing`, z3
  for `randomize()`, the DPI shim); the harness leg runs VCS. Xcelium and
  Questa stay standalone-only and untested, as before.
- **Simulator UVM versus uvm-core.** Through the harness the bench compiles
  against the UVM VCS ships; standalone it compiles the pinned uvm-core 2020.3.1
  on every simulator. The sim configs pin `[build.vcs].uvm_lib` to
  `uvm-ieee-2020-2.0`, the shipped library nearest the pinned source: on the
  one seed tried (`aou_t1_slice_test` seed 6, 2xmix-sp64-rxf) it reproduced the
  standalone trace, where the runner's default `uvm-1.2` draws a different
  random stream and flips about a tenth of the seed-dependent verdicts either
  way. A full sweep on it is part of the deferred harness leg. The
  two libraries still differ in API (`uvm_path_e` in 1.2 and in uvm-core's alias,
  `uvm_door_e` in the IEEE libraries), so the bench keeps to constructs both
  accept or selects by the library's version macro. A vendored uvm-core on the
  harness side would remove the difference altogether.
- **Coverage.** Code coverage (`COV=1`, the passing-runs-only merge,
  `cov/config/vcs/cov_exclude.hier`, the `urg -map` of the register bench, the
  FSM reset filter), the functional coverage report (`make fc_report`) and
  X-propagation builds (`XPROP`) exist standalone through the Makefile only.
  The harness's `--cov` and `coverage_policy.toml` are not wired.
- **Arm Axi4PC.** The optional Axi4PC binding (`AXI4PC`, `.deps/BP063/`) is
  compiled in by the Makefile only: the sim configs carry the bench's own
  Axi4PC files (always compiled, inert without it) but not `tb/aou_axi4pc_arm.sv`
  (which includes Arm's `Axi4PC.sv`) or the `AOU_AXI4PC` defines, because Arm's licence
  keeps the file out of every tree and a source the runner cannot find would
  break its build. Closing it takes a harness way to add a user-supplied
  source and define to a target (an optional overlay or a target that names
  `AXI4PC_DIR`), and a harness sweep with it on.
- **Escape suite, `RTL_PATCH`, `FDI_ENC`.** `make escape` and the patched-RTL
  builds are standalone only. A harness equivalent needs targets that compile
  a patched copy of `RTL/` (`exclude_files` plus `sources`) and a replacement
  for `escape.py`'s CAUGHT/ESCAPED grading.
- **Regression steering and metrics.** The harness's LSF executor has no live
  control file (`run_ctl.py`), no per-job CPU and memory record
  (`build/metrics.jsonl`) and draws random seeds in regression mode; a
  seed-exact sweep is one `--run-only` leaf per scenario and seed
  (`scripts/sweep.py`). Standalone keeps all three.
- **Plan status, rule inventory, performance checks.** `make plan_status`,
  `make rule_inventory`, `make perf_check` and `make perf_report` read the
  standalone `out/` layout; they do not read harness run directories.
  `judge_run.py` writes `results.csv` files that `compare_results.py` reads, and
  no more.
- **Register model regeneration.** The RAL is committed
  (`uvm/env/gen/aou_core_csr_uvm_pkg.sv`, `make ral`, freshness in
  `make lint`); the harness's `regen-regs` flow is not hooked to it.
- **Lint on the harness side.** `make lint` (Verible, Verilator `-Wall`,
  `check_rules.py`, `check_testlists.py`, the sim-config and RAL and docs
  freshness checks) is standalone; the harness has no equivalent for a
  vendored bench. The harness's Python lint and format checks apply to its own
  files only. `check_public.py` and the harness's hygiene checker are two
  checkers with overlapping pattern sets.
- **Verilator version.** aou-rtl CI pins Verilator 5.052; the harness's floor
  is 5.036. Nothing reconciles them until the harness runs the bench on
  Verilator.
- **Vendored location.** The bench is at `hw/ip/aou/dv` here and names its
  paths from the repository root (DECISIONS.md D17), so the harness can place
  it at the same path and find it by convention. The harness side has not done
  that yet: its branch that vendored the bench put it under
  `vendor/tenstorrent/aou/upstream/VERIF` with four `duts.toml` entries, which
  no longer matches these sim configs. What it takes there: a second Bender
  `vendor_package` for this repository with `target_dir: hw/ip/aou`,
  `include_from_upstream: ["hw/ip/aou/dv"]` and
  `mapping: [{ from: "hw/ip/aou/dv", to: "dv" }]` (or a symlink, or whatever
  the harness maintainers prefer for a Bender-managed tree under `hw/`), the
  four `[duts.aou*]` entries and `"VERIF"` in the existing package's
  `include_from_upstream` removed. Whether that is acceptable under the
  harness's "never edit a vendored tree" rule is their call.

## OCAH library adoption

- **Scope of the bases.** Only `ocah_test` and `ocah_sequence` are used.
  `ocah_env`, `ocah_scoreboard` and `ocah_checker` (with their `CHK-*` evidence
  and `CHECKER_SUMMARY`) and `ocah_axi_vip` were out of scope; the bench's
  layered models and rule-based checkers remain. Adopting them is an owner
  decision per component, measured against the rule ledger and the escape
  suite.
- **Fetched versus vendored.** `ocah_lib` is fetched by `make setup` at the pin
  in `scripts/get_ocah_lib.sh`. Vendoring it into aou-rtl would remove the
  network dependency of `make setup` at the cost of a copy to keep current.

## Documents and hygiene

- **`DOC/` references.** The plans cite `DOC/integration_guide` and
  `csr/aou-core.rdl` by repository path; through the harness those are under
  the vendored root, and the harness's document index does not list them.
- **PR and issue numbers in existing comments.** Files inherited from before
  the migration (the escape patches' notes, `BUGS/` references, some class
  headers) cite GitHub PR and issue numbers; the harness convention keeps
  tracker references out of code comments. New files follow the convention;
  the old references are cleaned as the files are touched.
- **Hygiene checker findings in inherited text.** The OSS document hygiene
  checker (the `oss-doc-hygiene` term bindings) passes on the files this
  migration wrote. Its blocking findings over the whole bench are all in text
  that predates it: the decision record and the guidelines naming the
  commercial VIP vendors they rule out (D1, D13, AGENTS.md "Boundaries",
  CODING_GUIDELINES.md), a `synopsys translate_off` pragma pair in the vendored
  FDI checker, a vendor document cited in `aou_flit_item.svh`, and a
  dictionary key in `test_perf_model.py` that matches its licence-server
  pattern. Each needs a wording decision by the owner or an allowed-context
  entry in the binding; none is a leak of site or licensed material
  (`check_public.py` is clean).
- **`fc.json` plan items.** The functional coverage report's `plan_ids` field
  is empty: the covergroups are not yet tied to plan items. The VPLAN-to-FCOV
  table in `docs/AOU_FCOV.adoc` is the hand-maintained mapping meanwhile.
- **Baseline scope.** The pre-migration baseline the parity check compares
  against is every testlist on every VCS target, the register bench and the
  assertion targets on VCS, the escape suite on VCS, and the short lists
  (`g1a`, `g1b`, `t1_api`) and the register bench on Verilator. The long lists
  have no Verilator baseline, so a Verilator-only degradation in them would
  not be caught by the comparison; the standalone Verilator smoke is the gate
  there. The `1x512-sp64-p512` target fails most of its scenarios, the new
  `aou_sanity_test` included (scoreboard data mismatches, AXI-S02, and the AXI
  read-channel rules AXI-R08/R09 trip across tests), in the baseline and after
  the move alike; the comparison treats these as unchanged FAIL, not as
  degradations. They are not in `expected_fail.yaml` and need a bug draft or a
  bench fix by the owner before the target can be graded green.
