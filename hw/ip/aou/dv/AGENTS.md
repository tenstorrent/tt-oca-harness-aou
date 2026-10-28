<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# AGENTS.md: hw/ip/aou/dv

Rules for anyone working on the VIP-free UVM testbench, people and coding agents
alike. This file is the single source; `CLAUDE.md` next to it only imports it.
Read [CODING_GUIDELINES.md](CODING_GUIDELINES.md) before writing code; it is binding.
Read [docs/DECISIONS.md](docs/DECISIONS.md) before changing structure or policy.
[README.md](README.md) documents the make targets and knobs named below.
[docs/AOU_TB_ARCH.adoc](docs/AOU_TB_ARCH.adoc) "Adding a Scenario" is the
checklist for a new test; [OPEN_ITEMS.md](OPEN_ITEMS.md) lists what the
tt-oca-dv layout migration deferred, and a change that closes an item removes
it there in the same commit. The bench is complete standalone; the harness
runner is meant to become a second consumer of the same sim configs and
testlists (DECISIONS.md D16; not yet validated, OPEN_ITEMS.md "Harness leg"),
so nothing may be added that works only through it.

## Running things

- Work from `hw/ip/aou/dv`. `make setup` once (uvm-core, the OCAH library, z3, PeakRDL,
  pywellen into `.deps/`).
- **Arm Axi4PC is optional but worth having.** If `.deps/BP063/` is empty or
  missing, ask the user once whether they want Arm's AXI4 protocol checker.
  It's free from https://developer.arm.com/downloads/view/BP063, but the
  download needs an Arm account and acceptance of Arm's licence, so the user
  downloads it, or points you at a BP063 tarball they already have.
  `make setup AXI4PC_TGZ=<tarball>` unpacks it into the git-ignored
  `.deps/BP063/`; never commit or redistribute it. T1 builds then bind it to
  every DUT AXI port (README "Optional: Arm AXI4 protocol assertions"). Without
  it the bench runs, but only its own subset of AXI4 rules.
- **Site specifics** (simulator modules to load, LSF options, where bug drafts
  go, internal tools) are in `site/SITE.md` and `site/site.mk` when present.
  `site/` is git-ignored and never committed; read `site/SITE.md` first if it
  exists. Load the simulators before running; LSF jobs inherit the environment.
- **Develop on VCS** (the default when `vcs` is on PATH). Cross-check on
  Verilator before every merge and at gates. Without VCS, `SIM=verilator` is the
  flow.
- **Compute goes through LSF where there is one.** When `bsub` is on PATH,
  `make build/run/test` submit with `bsub -K`, sized from `build/metrics.jsonl`;
  only editing, git, grep and `make lint` run on the login host, and job I/O must
  be on a shared filesystem, never `/tmp`. Never start a regression on a shared
  login host. Without `bsub` (or with `LSF=0`) builds and runs execute on the
  current host (README "Compute").
- **The full regression is `scripts/regress.py`** (README "Run everything";
  `python3 scripts/regress.py --help` lists every option, and `make regress` is a
  shorthand for it): every bench, configuration and testlist, built and run, then one
  summary that exits non-zero on any FAIL or XPASS. `--configs`, `--items`, `--steps`
  and `--rerun-failed` narrow, resume or repeat it.
- **Regressions run through `scripts/run_list.py`, which can be steered live.** It
  prints a control file (`out/<build>/<rid>.ctl`). Change `jobs`, `pause`, `drain`,
  `priority`, `queue` or `order` with `scripts/run_ctl.py <ctl> key=value` instead of
  restarting it (README "Regressions"). `run_list.py` does not build: run `make build`
  first, and again after any testbench or RTL change, or the runs use a stale binary
  (`make run` and `run_list.py` print a `WARNING: STALE BUILD` banner when that happens).
- **Run artifacts never go in `build/`.** Every `make run` creates its own
  directory `out/<build>/<test>.rid.<RID>.seed.<SEED>.time.<ts>.uid.<uid>/` (the
  ttem layout) holding `sim.log`, `run.sh`, `job.out` and coverage data. Repeat a
  run with a different `RID`. Merged reports go to `out/<build>/merged/`.
- **Build configurations** (`CONFIG`, e.g. `1x512-sp64`, `2x512-tp32_64`): the table
  and the naming legend are in README "Build configurations"; `make configs` prints
  them. A new configuration goes in `aou_sim_cfg.toml` and
  `aou_reg_sim_cfg.toml` (`[targets.<CONFIG>]`, plus `<CONFIG>-assert` when the
  assertion regression covers it), the README table and DECISIONS.md D9 together.
- `make lint` must stay clean. New files get no waivers. Its tool-free part is
  `make check-config` (sim configs, testlists, rules, bug citations, RAL and docs
  freshness), which the GitHub smoke workflow runs before building.
- **Testlists carry the plan.** A scenario is a `[[tests]]` entry of
  `testlists/<area>.toml` (harness schema: `name`, `module = { uvm = "<class>" }`,
  `args`, `seed`/`reseed`, `target`, `tags`, `run_modes`, `expect_fail`); the
  bench's aggregate `all.toml` includes every area and defines the groups. The
  test-plan items a scenario covers are listed under its name in
  `testlists/plan_ids.yaml` (IDs from `docs/test_plan_items.yaml`; prefer the
  surviving ID of a merged item; IDs are text, so write `4.10`, never `4.1`).
  A scenario without `target` runs on every target; `reseed = N` means seeds
  `seed`..`seed+N-1`. A scenario that can't run yet gets the `blocked` tag, stays
  out of every group and has its reason under `blocked:` in `plan_ids.yaml`.
  `python3 scripts/check_testlists.py` (in `make lint`) validates the lists;
  `make plan_status` reports the plan status from the runs under `out/`.
- `scripts/check_run.py` judges every run: PASS (no errors), XFAIL (every error
  matches an `expected_fail.yaml` entry for that test, each naming a bug), FAIL
  (anything else, including no UVM report summary). An entry that stops matching
  is reported as XPASS and must be reviewed: the bug may be fixed. A generic
  symptom a bug causes (a stall, a scoreboard mismatch, a failed handshake) gets
  `requires: <bug>`: it explains an error only when a bug-specific entry for that
  bug matched in the same run, so it cannot hide a new failure.
- **Coverage counts passing runs only.** `make run` writes each verdict to
  `<run>/verdict.txt`, and `make cov_report` merges only PASS runs (code and
  functional coverage, every simulator). FAIL, XFAIL and unjudged runs never
  count, even when their failure is a known DUT bug. Report coverage numbers
  with the merged/excluded counts `cov_report` prints.
- **Functional coverage is counted by our service, not the simulator.** A new
  covergroup takes its bins from a `*_fc_bins.svh` table and feeds its
  `aou_fc_group` next to `sample()`; `make fc_report` (README) is the number.
- **Debug failures from waves.** Group failures by error signature, rerun the
  shortest run of each signature with `WAVES=1` (same test and seed, new `RID`),
  and debug from the waves together with every log in the run directory. Read
  waves as text with `scripts/waveq.py` (FST, VCD and FSDB). The procedure,
  commands and T1 signal map are in [docs/WAVE_DEBUG.md](docs/WAVE_DEBUG.md).
- **Outstanding AXI transactions** (queue depth, concurrency, whether a test
  reached deep outstanding traffic) come from the waves through
  `scripts/axi_outstanding.py`; see [docs/AXI_OUTSTANDING.md](docs/AXI_OUTSTANDING.md).
- Optional, Claude Code only: the skills under `.claude/skills/` at the repository
  root are thin wrappers that point at these two documents.

## Where checks live

- **DUT checks live in passive, always-on checkers and monitors; tests provide
  stimulus.** A checker is built by the env (`env/`, `l3/`, `fdi/`, `checker/`),
  observes pins, messages and the register mirror, predicts what the DUT must do
  from that observation, and checks it in every test that reaches the
  behaviour. A check in a test, virtual sequence or test-built component that
  decides pass/fail from what the test knows it sent is blind in every other
  test.
- **Prefer generic invariants over scenario checks.** "An RP with credit and a
  queued request is not held back while another RP has none" fires wherever the
  bug occurs; "in this test every RP sends exactly k requests" only where the
  test was written. When a new invariant then fires in other tests, it has
  found real failures: tie each to its bug in `expected_fail.yaml`, don't
  narrow the check to the test it came from.
- Three carve-outs:
  1. Test intent. When the expectation depends on what the test means to do
     (a limit it set, a window it quiesced), the test states it in the config
     object or through the checker's API, and the checker checks it.
  2. End-of-sequence register read-backs (a status, counter or capture register
     the sequence just provoked) may stay in the test.
  3. Stimulus quality ("every RP reached 32 pending", "the sweep reached
     offset X", "at least one stall ended") is functional coverage: a bin of a
     covergroup that feeds its `aou_fc_group`, never an error.
- Example: the debug-window check T1-E19 used to sit in the error test's
  sequence, which compared the beats of the reads it issued. Now
  `aou_t1_dbg_fifo_chk` predicts each RP's error FIFO from the M-port error
  responses and remote completions it observes, and checks every debug-window
  read and pop in any test; the sequence only issues them.

## Reporting bugs

- **GitHub issues are the record.** A DUT finding (bug, RTL/doc mismatch,
  spec/doc conflict, unspecified behaviour) is reported as an issue on
  `tenstorrent/tt-oca-harness-aou`, the public repository, and the bench cites it
  as `tenstorrent/tt-oca-harness-aou#<n>` (`bug:` and `requires:` in
  `expected_fail.yaml`, the reference column of `uvm/env/checkers/rules.csv`,
  testlists, plan files, documents, code comments). Issue numbers are the only
  bug identifiers that get committed.
- **`BUGS/` at the repository root is the staging area, never committed** (it is
  git-ignored; `site/SITE.md` may name another place). A finding is drafted there
  first as `NNN-<slug>.md` from
  [scripts/bugs/TEMPLATE.md](scripts/bugs/TEMPLATE.md): front matter (kind,
  severity, area from `scripts/bugs/github.yaml`, needs, blocked_by, related), a
  title of at most 72 characters, Impact/Affects/Found by, Observed, Expected,
  Root cause, Reproduce (test, `CONFIG`, seed, the failing check's rule ID, wave
  evidence per [docs/WAVE_DEBUG.md](docs/WAVE_DEBUG.md)). Drafts are triaged
  there (merged, downgraded to `testbench`, dropped) before anything public
  happens. `python3 -I scripts/bugs/gen_readme.py` validates the front matter and
  regenerates the staging area's `index.csv` and README table (`--check` only
  validates).
- **Until the issue exists, the bench cites the draft** as `BUGS/NNN`, so a
  failure is tied to its bug the moment it is understood. `make check-config`
  (`scripts/check_bug_refs.py`) accepts exactly those two forms, rejects anything
  else, and lists the staged citations so they do not linger. Nothing else in
  the repository may reference a draft: the issue carries the full report, and
  code or documents that need the detail link the issue.
- **Filing is the user's decision.** Filing is a public action: ask, with the
  draft numbers, and file only on the user's explicit go-ahead; never on your own
  initiative. File with `scripts/bugs/gh_import.py`, not by hand, so labels
  (`kind:`, `severity:`, `area:`, `needs:`), issue types, blocked-by links,
  duplicate closure of merged drafts and the `issue_github:` write-back stay
  consistent. It needs `gh` logged in with write access (`gh auth status`).
  Dry-run first and read `plan.md`; the `--sha` must be a commit that exists on
  the public repository's `main`, or the permalinks in the bodies are dead:

  ```sh
  python3 -I scripts/bugs/gh_import.py --dry-run --out /tmp/bugs-gh --sha <public-main-sha>
  python3 -I scripts/bugs/gh_import.py --apply --repo tenstorrent/tt-oca-harness-aou --sha <public-main-sha>
  python3 -I scripts/bugs/rewrite_refs.py        # BUGS/NNN -> tenstorrent/tt-oca-harness-aou#n in the bench
  make check-config
  ```

  A rerun of `--apply` is safe: issues already created are found by their
  `<!-- bugs-id: NNN -->` marker and updated, not duplicated. `rewrite_refs.py`
  reads the `issue_github:` lines the import wrote back and replaces every
  `BUGS/NNN` the bench cites; commit that rewrite as one `verif:` commit. Then
  the draft has done its job; keep or delete it locally.
- **An issue body is public.** Before filing, make sure the draft holds no site
  paths, hostnames, internal tool names or tracker keys; `make check-public`
  covers the tree, so read the dry-run JSON for what it cannot see. Reproduce
  steps cite repository paths and bench commands only.
- **Afterwards the issue is where the discussion lives.** Owner decisions, fix
  status and questions go on the issue; an interim expectation the bench chose
  is stated there. A fix branch (`bugfix/<issue>-<slug>`, RTL change only, off
  `main`) links the issue. An `expected_fail.yaml` entry that stops matching is
  reported as XPASS: check the issue, and remove the entry when the fix is on
  `main`.
- **Resolved, not yet closed.** When a merged PR or commit fixes the problem
  (in the DUT, a document or the spec) but testbench, test-plan or other
  follow-ups remain, set the draft to `state: resolved` with `resolved_by` (the
  PR such as `"#89"`, or the commit SHA). Its issue stays open with the
  `status:resolved` label and names what resolved it; close it, like any open
  issue, once the follow-ups are done.

## Boundaries

- Never edit `RTL/`, `csr/`, `DOC/` or anything outside `hw/ip/aou/dv`. A DUT bug
  goes in `expected_fail.yaml` with its bug ID and gets a draft in the git-ignored
  staging area; filing it on GitHub is the user's decision ("Reporting bugs").
- Expected behaviour comes from the AXI4/UCIe/AoU specs and the MAS, never from
  reading the RTL.
- When behaviour is unspecified or the documents disagree, don't stop to ask:
  draft a report in the staging area (`BUGS/` at the repository root unless
  `site/SITE.md` says otherwise), choose a sensible interim expectation, implement
  it, note the choice in the draft, and tie any resulting failure to it in
  `expected_fail.yaml`.
- Nothing from Avery, Synopsys SVT or Arm is committed (Arm's `Axi4PC` lives in
  the git-ignored `.deps/BP063/`).
- Commits: short subject, `verif:` prefix, one concern per commit, tests with the
  code they exercise. Never push; the integrator merges, and runs
  `make check-public` before anything goes to the public repository.
