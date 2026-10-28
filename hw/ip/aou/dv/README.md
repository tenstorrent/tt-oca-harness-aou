<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc -->
# AoU DV

## Overview

DV environment for AoU (AXI-over-UCIe), the adapter in `RTL/` that carries AXI4
traffic from up to four resource planes over the UCIe Flit-Die Interface. It is
one SystemVerilog UVM bench with four tops: `tb/tb_top.sv` puts `AOU_TOP`
against layered models of the remote die (L1 FDI, L2 link state, L3 AoU
protocol, L4 AXI), and three smaller tops cover the register file alone, the L3
model against the FDI checker, and the AXI agents in loopback. No commercial VIP
is used; every model is the bench's own, and the base classes come from the OCAH
library of [tt-oca-harness](https://github.com/tenstorrent/tt-oca-harness).

The bench runs in two ways from the same sources, sim configs and testlists:
standalone from this directory's `Makefile` (VCS or Verilator), which is the
flow of record, and through the tt-oca-harness runner `run_dv.py` once this
repository is vendored into the harness. [docs/DECISIONS.md](docs/DECISIONS.md)
records why the bench is built the way it is, [AGENTS.md](AGENTS.md) holds the
working rules for people and coding agents, and [OPEN_ITEMS.md](OPEN_ITEMS.md)
the running list of what the layout migration left open.

It started from the Verilator UVM flow contributed in GitHub PR 80 by Vinh
Trieu and Quang Le (VNCHIPLabs); see [Acknowledgements](#acknowledgements).

## Prerequisites

| Need | Why | Notes |
| --- | --- | --- |
| Python 3.9 or later | every script | `tomllib` (3.11) is used when present; a subset TOML reader covers older interpreters; `scripts/bugs/*` also need PyYAML (`pip install -r requirements.txt` at the repository root) |
| GNU Make, Git, a C++ compiler | the standalone flow | |
| Verilator 5.052 | `SIM=verilator` | What CI builds (`.github/workflows/uvm-smoke.yml`); `--timing` and `randomize()` through z3 |
| Verible (`verible-verilog-lint`) | `make lint` | The version CI pins in `.github/tool-versions.env` (`VERIBLE_VERSION`) |
| VCS | `SIM=vcs` | The default when `vcs` is on `PATH`; the full regressions and coverage run here |
| LSF (`bsub`) | builds and runs at scale | Optional: `LSF=0` runs on the current host; site options in the git-ignored `site/site.mk` |
| `make setup` | fetches the pinned uvm-core, the OCAH library, z3, PeakRDL and pywellen into the git-ignored `.deps/` | No network after it; the pins are in `scripts/get_*.sh` |
| tt-oca-harness checkout with `uv` | "Through tt-oca-harness" below | Only for the harness leg |

## Getting Started

```sh
cd hw/ip/aou/dv
make setup                                   # one-time: uvm-core, ocah_lib, z3, PeakRDL, pywellen
make test                                    # build TB=t1 CONFIG=1x512-sp64, run aou_sanity_test
make build SIM=verilator                     # or SIM=vcs; TB=reg|l3_unit|axi_selftest for the other tops
make run TEST=aou_dp_random_test SEED=3 PLUSARGS='+dp_dir=both'
python3 scripts/run_list.py --items smoke    # the bring-up gate (4 scenarios)
python3 scripts/run_list.py --items functional -j 16 --rid nightly
python3 scripts/run_list.py --target 4x512-sp64 -j 16   # every scenario on one target
make check-config                            # sim configs, testlists, rules, RAL, plan items and docs freshness (what CI runs before building)
make lint                                    # check-config, Verible and Verilator lint, FDI checker guards
```

`--items` takes a scenario name or a testlist group (`smoke`, `ci`, the areas `g1a`,
`g1b`, `t1_api`, `fdi`, `datapath`, `features`, `stress`, `link`, `errors`,
`err_int`, `lifecycle`, `matrix`, `perf`, `assertions`, and `functional`,
`all`); `--tb reg` selects the register bench and its testlist. `make help`
lists every make target and variable.

### Run everything

`scripts/regress.py` is the full regression: it builds every bench the testlists need
and runs every scenario on it, then prints one summary. `python3 scripts/regress.py --help`
lists every option and what each step does; `make regress` is a shorthand that passes
make variables to it (table below). It needs the
[prerequisites](#prerequisites) for the simulator you pick, `make setup`, and
preferably LSF. Without `bsub` (or with `LSF=0`) the builds go one after another on
the current host and each list runs as many runs at once as it has CPUs, so use a
machine of your own, never a shared login host.

```sh
python3 scripts/regress.py --help                       # every option, every step
python3 scripts/regress.py --sim vcs --rid full1        # every CONFIG, every bench, every testlist
python3 scripts/regress.py --sim verilator --rid full1v # the same on Verilator, without the RTL assertions
python3 scripts/regress.py --sim vcs --rid pr1 --configs "1x512-sp64 2x512-tp32_64" --items "smoke ci assertions"
python3 scripts/regress.py --sim vcs --rid full1 --dry-run   # the plan and the run counts only
make regress SIM=vcs RID=full1                          # the same as the second line
```

What it does, in steps (`STEPS=build,run,summary`, plus `cov` with `COV=1`):

1. **build**: `make build` of the T1 bench (`TB=t1`) and the register bench (`TB=reg`)
   for every configuration (`make configs`), the `RTL_ASSERT=1` build of every
   configuration with a `<CONFIG>-assert` target, and the two model unit benches
   (`TB=l3_unit`, `TB=axi_selftest`): 27 builds on VCS. The RTL assertions are VCS-only
   ([RTL assertions](#rtl-assertions)), so on Verilator they are skipped with a note: 22 builds.
2. **run**: one `scripts/run_list.py` per build, with `--per-list`: T1 runs every
   testlist `all.toml` includes except `assertions.toml`, which runs on the `-assert`
   builds; the register bench runs `registers.toml` and the unit benches their own
   lists. That is about 5,300 runs on VCS (5,040 T1, 210 register, 37 assertion, 13 unit).
3. **cov** (`COV=1` only): `make cov_report` per configuration for this RID's
   passing runs, the register bench's folded in, then the union over the
   configurations in `out/regress/<RID>/union/`: code coverage (`urg -map AOU_CORE_TOP`
   on VCS, `verilator_coverage` on Verilator) and functional coverage (`fc_report.py`).
   The unit benches have no DUT and the `-assert` builds are left out of coverage.
   The configurations differ in DUT parameters, so on VCS a module merges across them
   only where its shape matches (urg warns `UCAPI-MAP-SHAPEMISMATCH` for the rest);
   read the union's instance rows, not its module-definition table, which holds the
   first configuration's modules only.
4. **summary**: a table per bench (T1, reg, assert, l3_unit, axi_selftest) of runs, PASS,
   XFAIL, FAIL and XPASS from the results CSVs, every FAIL and XPASS run with its run
   directory and the `make run ... WAVES=1` line that repeats it, and an overall
   result. The exit status is 1 when any run is FAIL or XPASS, or a build has no results.

Under LSF every build starts at once, then every `run_list.py`, each with `RUN_JOBS`
runs in flight (default 8; the CPU count with `LSF=0`), steerable live through its
control file `out/<build>/<RID>.ctl` ([Regressions](#regressions)). On VCS the whole
regression is about 14 CPU hours: each build takes about a minute, and the runs take
well under an hour of wall time when LSF grants the slots (up to about 200 at once). A
Verilator run costs about twice the CPU of a VCS run, and a Verilator T1 build takes
several minutes (four or more); `COV=1` costs about three and a half times the CPU of
a plain VCS run. `build/metrics.jsonl` records every job, so your own numbers are there.

Logs (one per build and per `run_list.py`), the exact commands (`commands.sh`) and
`summary.md` go to `out/regress/<RID>/`; the run directories and the results CSVs
(`results_<list>.rid.<RID>.csv`) are where `make run` and `run_list.py` always put
them, in `out/<build>/`.

`make regress` takes these variables; each is the script option of the same name in lower case
(`RUN_JOBS` is `-j`, `RERUN_FAILED` is `--rerun-failed`, `DRY_RUN=1` is `--dry-run`).

| Variable | Default | Meaning |
|---|---|---|
| `SIM` | `vcs` if on `PATH`, else `verilator` | Simulator |
| `RID` | `r<yymmdd>-<hhmm>` | Regression ID; repeat it to resume |
| `CONFIGS` | every configuration | Configurations, space separated |
| `BENCHES` | `t1 reg assert l3_unit axi_selftest` | Benches to build and run |
| `ITEMS` | everything | Groups or scenarios, run on every bench whose testlist defines them (`ITEMS="smoke ci assertions"` is the quick check) |
| `COV` | 0 | 1: coverage builds and runs, then the `cov` step |
| `RTL_PATCH` | none | Absolute path of a candidate RTL fix ([below](#building-against-a-candidate-rtl-fix)) |
| `RUN_JOBS` | 8 (LSF), CPU count | Runs in flight per `run_list.py` |
| `STEPS` | `build,run,summary` (`,cov`) | The steps to do, in their fixed order |
| `RERUN_FAILED` | none | An earlier RID: run only its scenarios with a FAIL or XPASS run |
| `COV_MEM` | `16GB` | LSF memory of each coverage job, always with a unit |
| `DRY_RUN` | 0 | 1: print the plan, build and run nothing |

Anything else on the `make regress` command line (`LSF=0`, `LSF_EXTRA_OPTS`, `AXI4PC=0`,
...) reaches the `make build` and `make run` calls the regression makes; with the script,
set them in the environment (`LSF_EXTRA_OPTS=... python3 scripts/regress.py ...`).

To **resume** an interrupted regression, repeat it with the same `RID`, leaving out the
steps already done: `make regress RID=full1 STEPS=run,summary`. A build that already has
results for that RID is skipped, so only the unfinished lists run again (from their
start). `STEPS=summary` reprints the summary. To **rerun the failures**, give a new RID:
`make regress RID=full1b RERUN_FAILED=full1` rebuilds only the builds that had a FAIL or
XPASS and runs every seed of each failing scenario; a single run is repeated with the
`make run` line the summary prints for it. `python3 scripts/test_regress.py` tests the
script with a fake `make`.

### Through tt-oca-harness (not yet validated)

Running the bench through the harness runner is a follow-up to the layout
move, not part of it: the sim configs and testlists carry what the runner
needs, and the scripts below exist, but no harness-side regression has been
accepted against the standalone baseline yet (`OPEN_ITEMS.md`, "Harness
leg"). The standalone flow above is the one that is verified.

The bench sits at `hw/ip/aou/dv`, the path the harness's
`hw/<group>/<dut>/dv` convention expects, and its sim configs name every path
from the repository root, so a tt-oca-harness checkout that places this
directory at the same path (the RTL stays vendored under
`vendor/tenstorrent/aou/upstream/`) needs no `duts.toml` entry for `aou`,
`aou_reg`, `aou_l3_unit` or `aou_axi_selftest`; the runner finds them and reads
the same `aou_sim_cfg.toml` and testlists:

```sh
python3 tools/dv/run_dv.py --doctor --dut aou --framework uvm
python3 tools/dv/run_dv.py --dut aou --framework uvm --build-only              # default target 1x512-sp64
python3 tools/dv/run_dv.py --dut aou --framework uvm --items smoke
python3 tools/dv/run_dv.py --dut aou --framework uvm --items all --target 4x512-sp64 --executor lsf
```

The runner's regression mode draws random seeds; a seed-exact sweep for
comparison with a standalone regression goes through `scripts/sweep.py`, and
`scripts/judge_run.py` grades the harness run directories with the bench's
grader so `scripts/compare_results.py` can compare the two. The harness side
is a consumer: nothing of the bench moves there, and a later aou-rtl tag is
re-vendored without harness-side work beyond the pin.

## Documents

| Document | What it covers |
| --- | --- |
| [docs/AOU_TB_ARCH.adoc](docs/AOU_TB_ARCH.adoc) | Testbench hierarchy, model ownership, environment components, clock and reset, stimulus, checking and coverage strategies, the SV-UVM realization and its differences from the harness pattern, adding a scenario |
| [docs/AOU_VPLAN.adoc](docs/AOU_VPLAN.adoc) | Verification strategy, naming rules, scope, the requirement-to-test matrix, the scenario summary and test procedures (generated from the testlists and class headers), regression groups, known limitations |
| [docs/AOU_FCOV.adoc](docs/AOU_FCOV.adoc) | Functional coverage goals, the covergroup inventory, closure policy, VPLAN-to-FCOV traceability |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The stream contracts and API names the layers were built against |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Decision records |
| [docs/COVERAGE_CLOSURE.md](docs/COVERAGE_CLOSURE.md) | Coverage closure plan, hole analysis, owner decisions |
| [docs/WAVE_DEBUG.md](docs/WAVE_DEBUG.md), [docs/AXI_OUTSTANDING.md](docs/AXI_OUTSTANDING.md) | Debugging a failure from waves; the outstanding-transaction histogram |
| [docs/PERF_JSON.md](docs/PERF_JSON.md) | The performance record each `aou_perf_test` run writes |
| [docs/checker_inventory.md](docs/checker_inventory.md) | Generated: every rule, its checker and the evidence from the runs |
| [OPEN_ITEMS.md](OPEN_ITEMS.md) | What the tt-oca-dv layout migration left for later |
| [AGENTS.md](AGENTS.md), [CODING_GUIDELINES.md](CODING_GUIDELINES.md) | Working rules; SystemVerilog and Python style |

`make docs` regenerates the tables under `docs/gen/` that the plans include;
`make lint` fails when they are stale. `docs/index.adoc` builds the three plans
into one book with Asciidoctor.

## Layout

| Path | Contents |
| --- | --- |
| `tb/` | `tb_top.sv` (T1), `aou_reg_top.sv`, `aou_l3_unit_top.sv`, `aou_axi_selftest_top.sv`; the status, interrupt and reset interfaces; `aou_waves.sv` |
| `uvm/env/` | The environment: `axi/`, `fdi/` (`l1/`, `l2/`), `l3/`, `apb/`, `checker/` (`AOU_FDI_CHECKER`), `checkers/` (`rules.csv`, the rule ledger), `chk/` and `perf/` (checkers), `gen/` (the committed register model), `pkg/`; the T1 env and its checkers at the top level |
| `uvm/seq_lib/` | Every virtual sequence, by area |
| `uvm/tests/` | `aou_tests.sv` (included by `tb_top.sv` under `UVM`), the test classes by area; `reg/`, `l3_unit/`, `axi_selftest/` for the other tops |
| `cov/` | `sv/`: the coverage service, the AXI4 coverage monitors and binds; `config/vcs/`: coverage scope, exclusion and FSM reset filter files |
| `testlists/` | TOML testlists (`all.toml` and the per-area lists, `registers.toml`, `l3_unit.toml`, `axi_selftest.toml`), `plan_ids.yaml` |
| `docs/` | The documents above; `gen/` is generated |
| `scripts/` | `regress.py` (`make regress`), `run_list.py`, `check_run.py`, `sim_cfg.py`, `testlist.py`, the lint and report scripts, the harness-leg scripts; `bugs/`: the bug-report template and the tools that validate staged drafts, file them as GitHub issues and rewrite the bench's citations |
| `aou_sim_cfg.toml`, `aou_reg_sim_cfg.toml`, `aou_l3_unit_sim_cfg.toml`, `aou_axi_selftest_sim_cfg.toml` | One sim config per top: sources, include directories, `[targets.<CONFIG>]` defines, run modes, testlist |
| `expected_fail.yaml` | Known DUT-bug failures the grader accepts as XFAIL, each tied to its GitHub issue (`tenstorrent/tt-oca-harness-aou#<n>`; `BUGS/<NNN>` for a draft staged but not yet filed) |
| `site/` | Git-ignored site settings (`site.mk`, `env.sh`, `public_patterns.txt`) |

## Build configurations

`CONFIG` selects the build parameters of the T1 bench (`TB=t1`) and the register
bench (`TB=reg`): RP count, AXI data width per RP, `FDI_CONFIG` and, in `-nxt`
configurations, `TX_NXT_PACKING_EN`. Build and
output directories are named after it (`build/vcs-t1-1x512-sp64`,
`out/vcs-t1-1x512-sp64`). `make configs` prints this table.

| CONFIG | RPs | RP widths (bits) | FDI_CONFIG | PHYs | For |
|---|---|---|---|---|---|
| `1x512-sp64` (default) | 1 | 512 | FDI_CFG_SP_64B | 1 | The default: one RP, the usual data path |
| `4x512-sp64` | 4 | 512 each | FDI_CFG_SP_64B | 1 | Multi-RP behaviour (plan 2.12) at one width |
| `3x512-sp64` | 3 | 512 each | FDI_CFG_SP_64B | 1 | An RP count that is not a power of two |
| `4xmix4211-sp128` | 4 | 1024, 512, 256, 256 | FDI_CFG_SP_128B | 1 | Mixed widths, every local width (2.14), 128-byte FDI |
| `4xmix2144-sp64` | 4 | 512, 256, 1024, 1024 | FDI_CFG_SP_64B | 1 | Mixed widths with RP2 and RP3 at 1024 bits; with `4xmix4211-sp128`, every RP at every local width |
| `1x256-sp32` | 1 | 256 | FDI_CFG_SP_32B | 1 | Narrowest RP and FDI (the RTL's default FDI_CONFIG) |
| `2xmix-tp64_128` | 2 | 512, 1024 | FDI_CFG_TP_64B_128B | 2 | Two-PHY FDI, two RPs, mixed widths |
| `2x512-tp32_64` | 2 | 512 each | FDI_CFG_TP_32B_64B | 2 | Two-PHY FDI with a 32-byte PHY0, two RPs at one width |
| `1x512-sp64-nxt` | 1 | 512 | FDI_CFG_SP_64B | 1 | `TX_NXT_PACKING_EN` 1: the registered TX packer output stage |
| `2xmix-sp64-rxf` | 2 | 1024, 256 | FDI_CFG_SP_64B | 1 | Non-default RX FIFO depth per RP and class, RX FIFO register slices off (plan 3.25) |

Reading a name:

- `NxW`: N remote ports (RPs), each with a W-bit RP AXI data width.
- `mix`: mixed RP widths, as listed in the table. `mix<digits>` gives one digit
  per RP, RP0 first: that RP's AXI data width in 256-bit units (1 = 256,
  2 = 512, 4 = 1024), so `4xmix4211` is RP0 1024, RP1 512, RP2 and RP3 256.
- `sp<B>`: a single PHY with a B-byte FDI data path (`FDI_CFG_SP_<B>B`).
- `tp<B1>_<B2>`: two PHYs with B1- and B2-byte FDI data paths
  (`FDI_CFG_TP_<B1>B_<B2>B`, built with `TWO_PHY`).
- `-nxt`: `TX_NXT_PACKING_EN` 1 (`AOU_TX_NXT_PACKING=1`): the TX flit packer
  computes each chunk from its look-ahead state and registers it before the FDI
  output; the default (0) drives the chunk combinationally from the granule ring.
- `-rxf`: non-default RX FIFO depths (`AOU_T1_RX_DEPTH` in `uvm/env/aou_t1_env_pkg.sv`) and
  `RX_*_FIFO_RS_EN=0`, passed to `AOU_TOP` under the `AOU_RX_FIFO_ALT` define.

The set is pairwise rather than a cross product (DECISIONS.md D9). Testlist
scenarios without `target` run on every configuration; scenarios that need
several RPs or a particular width name theirs.

## Setup and run

`make setup` fetches Accellera UVM-core 2020.3.1 at commit
`78c06547a2a0a29b3dc9dcafae62b75b2ff61544` and the OCAH library at the pin in
`scripts/get_ocah_lib.sh` into the ignored `.deps/` directory. Every simulator
compiles that same UVM source rather than its bundled UVM.

On macOS, the system `make` (3.81) is too old: the flow needs GNU Make 4, Verilator
(the version in `.github/tool-versions.env`), and lz4 for FST waves, found through
`pkg-config`. Homebrew is a quick way to get them
(`brew install make verilator lz4 pkgconf`); its GNU Make is `gmake`, so run
`gmake` wherever this file says `make`. Any other installation works too. On
Darwin the Makefile adds the SDK's `malloc/` directory for uvm-core's
`<malloc.h>`; without `pkg-config`, or to use other paths, set `VL_HOST_CFLAGS`
and `VL_HOST_LDFLAGS`.

`SIM=verilator`, `SIM=vcs`, `SIM=xcelium` or `SIM=questa` selects the simulator.
The default is VCS when `vcs` is on PATH, otherwise Verilator. Verilator and VCS
are the supported flows; Xcelium has a basic build and run without coverage, and
Questa builds but its run and coverage are untested.

Each bench's sim config lists its sources, include directories and the
`[targets.<CONFIG>]` defines; `scripts/sim_cfg.py` reads it for the Makefile
(`make build` puts `RTL/filelist.f` and uvm-core in front) and `sim_cfg.py check`
validates it against the harness key set (part of `make lint`).

`make build` and `make run` split the two steps, so further tests and seeds
reuse one build. A run passes when its log reaches the UVM report summary with
no `UVM_ERROR` or `UVM_FATAL`.

Run-time plusargs go in `PLUSARGS` (for example
`make run TEST=aou_fdi_t1_linkdown_spec_test PLUSARGS=+sw_restart_delay=0`).
After LinkError, LinkReset or Disabled -> Reset the link is restarted by
software on the UCIe controller, never by the DUT (integration guide §6.6.2):
the L2 Adapter model stays in Reset for `sw_restart_delay` cycles
(`+sw_restart_delay=N`, 0 trains at once; random in [50:1500] by default) and
then trains again by itself, and the bringup model checks that the DUT requests
nothing meanwhile (FDI-M01/M02). An AoU deactivation leaves the link Active
(FDI-M06).

After a LinkError the DUT holds the link down until software has written
`AOU_CON0.AOU_SW_RESET` (integration guide §6.6.3). In the FDI T1 tests that
write comes from the test itself, a random number of cycles after
`O_FDI_FSM_STATE` reports LinkError; `+sw_reset_delay_max=N` bounds the delay
(default 300). The lifecycle tests reset through `recover()` as before.

`+pclk_ps=<period in ps>` sets the APB clock of the T1 and register benches
(default 10000, 100 MHz; the core clock stays 1 GHz). The APB bridge is
asynchronous (integration guide 8.5.3), so the testlists try slow (40000),
fast (600) and near-equal (1013) PCLK:CLK ratios (plan 11.17).

`+v0p9draft` holds the DUT to expectations that AoU adds after v0.7.1, as the v0.9
draft words them (a placeholder until v0.9 is accepted); the DUT implements v0.7.1.
Today that is the 4.4 Misc placement on the DUT's flits: AOU-R6 (an Activation message
shares its flit only with one CrdtGrant after an ActivateReq/Ack or with responses after
a DeactivateReq; nothing follows a DeactivateAck) and AOU-R7 (at most 2 other Misc per
half-flit). Without it the DUT is held to v0.7.1's rule (at most one Activation message
per flit, at G0). The remote die's own flits follow the draft either way; the share of
its Activation flits that carry the permitted company is `act_share_pct` (default 50).
Further post-v0.7.1 DUT checks belong behind the same switch.

Traffic and remote-die knobs (run time, any T1 test):
- `+small_size_pct=N`: N% of requests are small, register-like accesses
  (AxSIZE below 5), both from the S ports and from the remote die. The default
  is 0: ordinary random requests are 32 bytes up to the bus (AxSIZE 5 or more),
  so small ones come only from this knob, a test's own size list or the
  directed tests (`aou_dp_size_test`, `aou_small_size_test`, `aou_dw_test`). `+small_size_wt=w0,w1,w2,w3,w4` weights AxSIZE 0..4 (default
  2,4,45,45,4), and `+small_burst_pct=N` (default 10) makes N% of them 2-4 beats
  instead of one. They live in `aou_axi_rand_seq`, which `aou_dp_seq` extends.
- `+remote_bytes=N` or `N0,N1,..`: the remote die's AXI data bytes.
- `+remote_wreq=awsize|upsize|dut_like`: how the remote die sizes its
  WriteReqs and WriteData; all three are legal.
- `+remote_max_burst=2^n`: the remote splitter's longest burst (default 256).
  `+remote_max_burst_rand=1` re-picks it whenever the remote is idle.

FDI corner knobs (run time, `testlists/fdi.toml`): `+fdi_trdy=always|random|holes|bursty`,
`+fdi_stall_pct=N` stand-alone stalls, `+fdi_stall_mid_pct=N` the share raised
inside a DUT TX flit, `+fdi_stall_trdy_free=1` lets `pl_trdy` drop between
`pl_stallreq` and `lp_stallack` (UCIe r1.1 8.3.2 rule 7), `+l1_cancel_pct=N` and
`+l1_cancel_mix=1` (second-half, both-halves and repeated flit cancels),
`+le_mid_flit_pct=N` (Adapter LinkErrors entered mid-flit, 8.3.3.7),
`+fdi_rx_early=N` (on every Active entry from Reset the Adapter forwards RX flits for N
cycles after the rx_active handshake while `pl_state_sts` is still Reset, as UCIe r1.1
8.2.7 allows when the remote die went Active first; off by default) and, in
two-PHY builds, `+active_phy=1 +park_idle_phy=1` (the unselected PHY stays in Reset,
so state and stalls must come from the selected one). The `l1.cg_fdi_stall`,
`cg_fdi_cancel` and `cg_fdi_abandon` bins show the corners were reached.

Build output is kept under the ignored `build/<sim>-<tb>[-<config>]/` directory. Each run gets
its own directory, `out/<build>/<test>.rid.<RID>.seed.<SEED>.time.<timestamp>.uid.<uid>/`
(the ttem layout), holding `sim.log`, the job script and output, and the run's
coverage data. Run the same test and seed again with another `RID`; directories
never collide. `make cov_report` writes merged reports to `out/<build>/merged/`,
and `make clean` leaves `out/` alone (`make clean-out` removes it).

## Waves

`WAVES=1` on `make run` or `make test` dumps the whole design into the run
directory. It's a run-time option, so it never needs a rebuild:

| Simulator | File | How |
|---|---|---|
| VCS | `waves.fsdb` | A UCLI script (`waves.tcl` in the run directory) calls `fsdbDumpvars ... +all`; open with `verdi -ssf waves.fsdb -dbdir <build>/simv.daidir` |
| Verilator | `waves.fst` | `+waves` starts the trace from `tb/aou_waves.sv`; open with GTKWave or Surfer |
| Xcelium | `waves.shm` | `+waves`, as for Verilator; untested |
| Questa | `waves.vcd` | `+waves`, as for Verilator; untested |

On simulators other than VCS, `PLUSARGS=+waves=<stem>` names the file.

Every build can dump waves, so rerunning a failure with `WAVES=1` never needs a
rebuild. Verilator compiles FST tracing in, because it can only start a trace
from code built with it, and VCS builds the Verdi design database (`-kdb`) for
source and struct debug. `WAVES_BUILD=0` leaves both out, for a lean regression
build in its own `-nowaves` build directory; `WAVES=1` refuses to run against
it.

To read waves as text, `scripts/waveq.py` searches signals and prints value
changes, values at a time, several signals per clock edge, and time ranges where
a signal holds a value. `scripts/axi_outstanding.py` prints a histogram of
outstanding AXI transactions per interface. Both read FST and VCD with pywellen
(installed by `make setup`) and FSDB through Verdi's `fsdb2vcd`, cached next to
the FSDB. Setting `WAVEIO_WQ` to a directory holding a compatible `wq` query tool
sends FSDB there instead. [docs/WAVE_DEBUG.md](docs/WAVE_DEBUG.md) is the
procedure for debugging a failure from waves, and
[docs/AXI_OUTSTANDING.md](docs/AXI_OUTSTANDING.md) explains the histogram.

## Public repository

`make check-public` lists internal references (site paths, private hostnames,
home directories, and the site patterns in `site/public_patterns.txt` when
present) in the tracked files and in the commits since `PUBLIC_BASE` (default
`main`). Site-specific settings live in the git-ignored `site/` directory:
`site.mk` (LSF options, included by the Makefile) and `SITE.md` (notes).

## Compute

Builds and runs are submitted to LSF when `bsub` is available (`LSF=0` runs
them on the current host). Load the simulator modules first; the job inherits
the environment. Requests default to what the jobs actually use: `BUILD_MEM` 4 GB
for Verilator (`JOBS=8` build threads) and 2 GB for VCS, and `RUN_MEM=1` GB with
`RUN_CPUS=1` per simulation. Both are numbers of GB, and the LSF request always
carries the unit (`rusage[mem=<N>GB]`), since a bare number means GB on some clusters
and MB on others. VCS compiles also reserve a VCS licence through LSF. Every build and run appends its CPU time,
peak memory and run time to `build/metrics.jsonl`, which is what the defaults
are tuned from.

## Regressions

`make regress` ([Run everything](#run-everything)) builds and runs the whole
regression through the script described here. `scripts/run_list.py` runs every scenario and seed of a testlist
(`testlists/*.toml`; default: the bench's aggregate, `testlists/all.toml` for
T1) through `make run`, at most `-j` at a time, and writes
`out/<build>/results_rid.<rid>.csv` (one `results_<list>.rid.<rid>.csv` per
included list with `--per-list`); the RID in the name means a later regression
of the same lists never overwrites an earlier one's results. `--items <group|scenario>...` picks groups (`smoke`, `ci`, `g1a`,
`functional`, ...) or scenario names; `--target <CONFIG>` picks the build and
skips scenarios pinned to another target; `--reseed N` caps the seeds per
scenario. `python3 scripts/check_testlists.py` validates the lists against the
sim configs and the test classes (part of `make lint`).
Several lists in one call share a single pool of `-j` runs. It does not build:
run `make build` for the same SIM/TB/CONFIG first, and again after any testbench
or RTL change, or the runs use a stale `simv`. A stale build is reported, not
rebuilt: `make build` records its compile defines and start time in
`<build>/build.stamp`, and `make run` prints a `WARNING: STALE BUILD` banner when
an RTL or testbench source is newer or the defines differ (`make stale-check`
runs only the check; `STALE_CHECK=0` skips it). `run_list.py` prints the banner
once at the start instead of once per run.

```sh
python3 scripts/run_list.py --sim vcs --target 1x512-sp64 --rid nightly -j 8 \
  --per-list --items g1a link
```

`--rtl-patch` and `--cov` pick the build as the make variables of the same
names do.

Your own bsub options go in `LSF_EXTRA_OPTS`. Every build and run appends it
after the site's options (`LSF_SITE_OPTS` in `site/site.mk`), for example to keep
jobs off a host:

```sh
export LSF_EXTRA_OPTS='-R "select[hname!=hostA]"'
make build SIM=verilator                # or LSF_EXTRA_OPTS=... on the command line
python3 scripts/run_list.py ...         # --lsf-extra-opts; default $LSF_EXTRA_OPTS
```

`run_list.py` hands it to each `make` it starts as a command-line variable. A site can
also set `LSF_VERILATOR_BUILD_OPTS` for Verilator compiles only (hosts that can't
build them), next to `LSF_VCS_BUILD_OPTS` for VCS compiles.

A running regression can be changed without restarting it. At startup
`run_list.py` writes a control file, `out/<build>/<rid>.ctl` (or `--ctl PATH`),
and prints its path; it re-reads it every second. Each change it applies is
logged with a timestamp and the old and new values, on stdout and in the run log
`out/<build>/<rid>.log`. The file is removed when `run_list.py` exits (normally,
on error or on SIGTERM), so an existing control file means a live run, and
`run_ctl.py` refuses a missing one. `scripts/run_ctl.py` edits the file atomically:

```sh
python3 scripts/run_ctl.py out/vcs-t1-1x512-sp64/nightly.ctl jobs=20   # more runs in flight
python3 scripts/run_ctl.py out/vcs-t1-1x512-sp64/nightly.ctl pause=1   # stop launching
python3 scripts/run_ctl.py out/vcs-t1-1x512-sp64/nightly.ctl drain=1   # finish running jobs, then exit
python3 scripts/run_ctl.py out/vcs-t1-1x512-sp64/nightly.ctl           # show the settings
```

| Key | Effect |
|---|---|
| `jobs=N` | Runs in flight at most. Lowering it never kills a running job. |
| `pause=0\|1` | 1 stops launching; running jobs finish. 0 resumes. |
| `drain=0\|1` | 1 lets the running jobs finish, then exits; the runs not launched are listed as `notrun` and the exit status is 1. |
| `priority=P` | Scheduler priority of runs launched from now on (make `JOB_PRIORITY`, `bsub -sp`). Empty means the default. |
| `queue=Q` | Scheduler queue of runs launched from now on (make `JOB_QUEUE`, `bsub -q`). Empty means `LSF_QUEUE`. |
| `order=O` | Launch order of the remaining runs: `fifo` (testlist order), `shortest` (by past run time in `build/metrics.jsonl`) or `failed-first` (tests with a failure in an earlier `results*.csv` or in this run). |

If the site defines `JOB_MODIFY_PRIORITY` and `JOB_MODIFY_QUEUE` (in
`site/site.mk`, for example `bmod -sp {priority} {job}`), a priority or queue
change also goes to the runs this `run_list.py` submitted that are still waiting
to be dispatched. It knows them from the job IDs `bsub` printed for its own
runs; other jobs are never touched. A job that started in the meantime is
refused by the scheduler and logged, unchanged. `kill -USR1 <pid>` raises `jobs` by one and
`kill -USR2 <pid>` lowers it by one, as a fallback. `run_list.py --help` lists
the options, and `python3 scripts/test_run_list.py` tests the control with a
fake `make run`.

## Lint and coding rules

`make lint` runs Verible and Verilator `-Wall` on the testbench (RTL and
uvm-core are excluded; the T1 top is linted with the DUT's parameter defaults
and again with `AOU_TX_NXT_PACKING=1`, the `-nxt` build), after `scripts/check_rules.py`, which fails when a rule
ID the testbench emits has no row in `uvm/env/checkers/rules.csv` or a row's ID is never
emitted (rows checked `via`, by construction, not checked or N/A excepted; any
other exception goes in its `EXEMPT` list with the reason). New code follows [CODING_GUIDELINES.md](CODING_GUIDELINES.md)
and gets no lint waivers; `.verible_waivers` and `lint/verilator_lint.vlt` only
list findings in files inherited from PR 80 and the vendored FDI checker.

## Optional: Arm AXI4 protocol assertions

Arm's AXI4 protocol checker (`Axi4PC`, BP063) is free from Arm but can't be
redistributed, so it isn't part of this repository and nothing requires it.
To enable it, download BP063 from
https://developer.arm.com/downloads/view/BP063 and unpack it into the
git-ignored `.deps/BP063/` with `make setup AXI4PC_TGZ=<path to the tarball>`
(`scripts/get_axi4pc.sh`), or point `AXI4PC_DIR` at its `sva` directory.

When it is there, T1 builds compile `Axi4PC.sv` unmodified and bind one instance
to each RP's DUT S and M ports (`tb/tb_top.sv`), in a separate `-axi4pc` build
directory; `AXI4PC=0` leaves it out. The recommended MAX_WAIT rules are off,
because the bench stalls READY on purpose. `AXI4PC_MAXBURSTS` (default 512) sizes
its outstanding-burst tracking. Each RP is checked at its own data width.
`tb/aou_axi4pc_msg.svh` turns Axi4PC failures into `UVM_ERROR`s (reporter
`AXI4PC`), so a failing assertion fails the run on every simulator. A failing rule
fires on every cycle, so after `+aou_axi4pc_max=<N>` of them (default 10, 1 stops
at the first, 0 never stops) the run ends with `UVM_FATAL [AXI4PC] N Axi4PC
violations, stopping`, `+aou_axi4pc_stop_cycles=<n>` clocks later (default 10;
errors in those cycles are still reported), so the waves of a `WAVES=1` rerun show
what followed. `check_run.py` judges the run by the errors before the fatal.

Each checker's reset (`tb/aou_axi4pc_gate.sv`) is its port's reset: the DUT core
reset (`I_RESETN` and `AOU_SW_RESET`), which the bench's AXI agents are on as well
(the SoC resets the AXI peers with AOU_CORE, MAS 7.3.6). After an `AOU_SW_RESET`
the checker leaves reset only once the port has no VALID up and nothing in
flight, so a handshake the reset cut is never judged. When the FDI
link is lost while AoU isn't DISABLED, the transactions in flight can't complete, so
`uvm/env/aou_t1_axi4pc_ctl.svh` holds every checker in reset from that event until its
port's next reset (then as above), or to the end of the test; each hold and release
is logged. The same component expects the rules a deliberately unmatched response
from the local subordinate trips (`inject_orphan`, the ID-mismatch tests) on that
port while it is presented (`uvm/env/axi4pc/aou_axi4pc_pkg.sv`). Once the DUT takes
such an orphan, Axi4PC's own transaction tracking is wrong (an unmatched B or RLAST
corrupts its CAMs until reset), so that checker is reset once, in the port's next quiet
cycle and only for that cycle; it is never held while the port is active, and a reset still
waiting at the end of the test is an error.

## Coverage

`COV=1` collects code coverage of the DUT (the files under `RTL/`) in a
separate `build/<build>-cov/` directory. Run any number of tests and seeds, then
merge and summarise them (reports go to `out/<build>-cov/merged/`):

```sh
make build COV=1
make run COV=1 TEST=aou_dp_random_test SEED=1
make run COV=1 TEST=aou_dp_random_test SEED=2
make cov_report COV=1
```

Only runs whose verdict is PASS count: `make run` writes each verdict to
`<run>/verdict.txt`, and `cov_report` skips FAIL, XFAIL and unjudged runs,
printing how many it merged and excluded. It merges every passing run under
`out/<build>/`; `COV_RID=<rid>` (`make cov_report COV=1 COV_RID=cov4`) takes only
the runs of that RID, for the T1 and the folded-in register runs alike, so a
report never mixes two regressions.

The register bench takes the same `CONFIG` as T1, so it builds the same DUT
parameters, and `make cov_report TB=t1` folds in its passing runs from the same
SIM, CONFIG and `RTL_PATCH` (VCS maps them onto `AOU_CORE_TOP` with `urg -map`;
Verilator and Questa merge the files directly). The report stops if that register
build has no runs; `COV_WITH=` leaves them out.

VCS leaves out the cells an integrator replaces (synchroniser, DFT reset mux and
buffer; integration guide 8.7), listed with their reasons in `cov/config/vcs/cov_exclude.hier`
and passed to `-cm_hier` with the bench's own scope file, so the exclusion takes
effect on the next `COV=1` build. For databases built before an entry was added,
`make cov_report COV_EXCLUDE_PREVIEW=1` applies the same list with `urg -hier`.
Dead code (single lines and branches no stimulus can reach) is excluded at report
time instead: `cov/config/vcs/cov_exclude.el`, each item with its reason, goes to
`urg -elfile` (`COV_EL=` leaves it out; DECISIONS.md D10).

| SIM | Metrics | Report |
|---|---|---|
| verilator | line, branch, expression, toggle, covergroups | `summary.txt` (per module), `merged.info` (lcov), `annotated/` |
| vcs | line, cond, toggle, FSM, branch, covergroups | `summary.txt`, `urg/` (URG) |
| questa | branch, cond, expr, statement, FSM, toggle (untested) | `summary.txt` (vcover) |

Verilator and the commercial tools count coverage points differently, so
compare uncovered items per module rather than headline percentages.

`COV=1` also binds AXI4 functional coverage monitors (`cov/`) to every
`AOU_CORE_TOP` instance: one per RP on the S port (`axi_tx_rp<n>`) and one on
the M port (`axi_rx_rp<n>`). Each run writes `aou_axi4_fc.<run-id>.txt` in its run directory,
and `make cov_report` union-merges them into `out/<build>/merged/aou_axi4_fc_merged.txt`,
listing the uncovered bins. Compare simulators with the merged report: it counts
bins directly, while each run's own per-channel percentages come from the
simulator's covergroup scoring, which Verilator weights differently.

### Functional coverage report

Every testbench covergroup (L1 `cg_fdi_*`, L2 `cg_link_state` and
`cg_bringup_fsm`, the six L3 groups, the AXI monitor's `txn_cg` and `zero_cg`,
and the T1 env's `xfer.attr_cg`, `xfer.excl_cg` and `xfer.chan_cg`: request
attributes carried, exclusive outcomes and channel orderings) also feeds the coverage service in `cov/sv/aou_fc_pkg.sv`, which counts each bin
itself rather than asking the simulator: Verilator 5.052 compiles covergroups
but scores them as 0%, and VCS weights coverpoints and crosses its own way. A
covergroup and the service take their bins from one table macro
(`*_fc_bins.svh`, see `cov/sv/aou_fc_macros.svh`), which expands to the
covergroup's `bins` and to the service's declaration, so the two can't drift.
Cross exclusions (`ignore`, `illegal`) and spec tags are the service's alone,
since Verible can't parse a macro inside a cross: a coverpoint bin can be
ignored (`IGN`, no target) or illegal (`ILL`, out of the denominator; a hit is
reported under the rule that owns it), and a cross cell is ignored or made
illegal by pattern (`XIGN`, `XILL`; see `aou_fc_point::mark`). The service's
count is the number; the simulators' covergroup scores are not used.

With `COV=1` each run writes `<run>/fc.json`: every group, coverpoint and
cross, every declared bin with its hit count (zero-hit bins included, so holes
show), the samples that fell outside every bin, and `spec` and `plan_ids`
fields. A bin's `spec` names the AoU revision it needs (`v0.8`) and an illegal
bin carries `"illegal": true`; ignored bins are not written; `plan_ids` is
empty for now. Without
`COV=1` nothing is written: the AXI4 monitors exist only in COV builds, so a
report from another build would silently leave out their bins.

`make fc_report` (same `SIM`, `TB`, `CONFIG` and `COV=1` as `cov_report`, which
runs it) union-merges the passing runs' `fc.json` and AXI4 text reports (as
groups `axi4.<interface>.<covergroup>`) into `out/<build>/merged/fc/`:
`summary.txt` (bins hit/total per group and coverpoint), `holes.txt` (every
bin no passing run hit), `index.html` (the same, self-contained) and
`fc_merged.json`. It prints the merged/excluded run counts like `cov_report`.
A group's percentage is its hit bins over all its bins, crosses included.
Bins tagged `v0.8` stay in every count; the summary adds a column and a total
for them, and `holes.txt` marks them `[v0.8]`. Illegal bins are not counted,
and any that a passing run hit are listed.
The closure target is 100% and there are no waivers: an unreachable bin stays
a hole until the user agrees to waive it. Closure is measured on the union of
every configuration; the plan, its status and the owner's decisions are in
[docs/COVERAGE_CLOSURE.md](docs/COVERAGE_CLOSURE.md).

### Reset transitions and X-propagation

VCS FSM coverage leaves out every transition that only the asynchronous reset
makes (an FSM sent to its reset state from the middle of another state), via
`-cm_fsmresetfilter cov/config/vcs/cov_fsm_reset.filter` on `I_RESETN`, `I_PRESETN`,
`I_S_PRESETN` and `I_M_PRESETN`. Transitions that functional logic also makes
stay in. `COV_FSM_RESET=1` keeps the reset transitions (build `<build>-cov-fsmrst`).
Reset correctness is checked instead with an X-propagation build (D10):

```sh
make build XPROP=tmerge                  # or xmerge (more pessimistic)
make run XPROP=tmerge TEST=aou_reset_test PLUSARGS='+reset=core +when=traffic' WAVES=1
```

`XPROP` (VCS only, `TB=t1` or `reg`) instruments only the DUT (`<top>.u_dut`, an
X-prop configuration file written to the build directory) and builds into
`<build>-xprop-<mode>`; the default build is unchanged. The build directory's
`xprop.log` and `unifiedInference.log` list what was instrumented and which flops
have an asynchronous reset. In the run, the bench's X checks (AXI and APB
monitors) fail on an X reaching a DUT output, and the waves show any register
still X after reset is released.

## Test-plan status

`docs/test_plan_items.yaml` lists every item of the old test plan (the
verification branch's `dv/doc/AOU_RTL_TEST_PLAN.md`, sections 2.1-2.22) with the
corrections in `docs/test_plan_corrections.yaml` applied: reworded items,
duplicates merged into one surviving ID, and items dropped as untestable on this
RTL. Change the corrections, never the output, and run
`scripts/gen_plan_items.py` to regenerate it: the file keeps what it took from
the old plan with a digest, so the old plan itself is needed only when that
changes (`scripts/gen_plan_items.py <old plan>`). `make check-config` runs
`gen_plan_items.py --check`, which fails when the file is stale or was edited by
hand.

`testlists/plan_ids.yaml` names the items each scenario covers. `make plan_status`
matches every run under `out/` to its scenario by test class, plusargs (from
`run.sh`) and TB/CONFIG (from the build directory; a scenario without `target`
matches every config), and writes
`out/plan_status.md`. Each item is covered (a PASS run), xfail-only (only XFAIL
runs, with their bugs), failing, blocked (only `blocked:` entries list it) or not
covered, followed by per-section and total counts. As for coverage, only PASS
counts. `make compare BASELINE=<dir>` compares the `results*.csv` under `out/`
with a kept baseline and reports every run whose verdict got worse
(`scripts/compare_results.py`). A run is matched by build (a `-cov` in the build
name is ignored, so a coverage build compares with a plain one), test, plusargs
and seed; a run that occurs twice on a side (two lists running the same test and
seed) is a separate run, paired by occurrence. `COMPARE_OPTS='--base-rid <b>
--after-rid <a>'` (or `--rid` for both) compares only those regressions' runs. It reads files only, so it needs no LSF. `PLAN_OUT=<dir>` reads another
`out/`, and `PLAN_STATUS_OPTS=--judge` also judges runs that have no
`verdict.txt` (`scripts/plan_status.py --format csv` gives CSV).

`python3 scripts/test_plan_status.py` tests these scripts.

## Performance targets

Bandwidth windows are judged against the saturated packing limit that
`d2d_model.py` from d2d-compare computes for the exact configuration and
traffic. d2d-compare is an optional external dependency: set `D2D_COMPARE` to
a checkout. Simulations never need it; they read the committed table.

- `docs/perf_scenarios.yaml` defines the windows (scenarios S1 to S6): traffic
  direction, write share, burst length, strobes, RPs. The perf sequence drives
  the same windows.
- `make perf_targets` (needs `D2D_COMPARE`; `OPTIONAL=1` adds S6) regenerates
  `uvm/env/perf/aou_perf_targets.svh`, keyed by (CONFIG, active PHY, scenario,
  window, link direction). Each entry holds the model's delivered bytes per
  cycle on that link, the tolerance (default 0.03), the above-model margin
  (one flit of bytes per window), the model's message mix on that link and
  the d2d-compare commit it came from. It also regenerates
  `uvm/env/perf/aou_perf_windows.svh`, the windows each CONFIG runs. Commit both
  with the change that caused them. The model is fed the traffic as it
  crosses the link: whole bursts (the DUT's transaction splitter divides the
  requests it receives, at its manager port, and never changes what crosses
  the link), narrow AxSIZE where a burst would exceed 4 KB (d2d-compare's
  `Txn.beat`).
- `uvm/env/perf/perf_overrides.yaml` widens the tolerance of single targets, each
  with a measured structural reason. It is empty by default.
- `make perf_check` judges every `out/**/perf.json` (docs/PERF_JSON.md) against
  the table (PASS, BELOW, ABOVE, NO_TARGET) and, with `D2D_COMPARE` set,
  reports drift between the table and the live model plus each run's own model
  and message-mix error. `make perf_report` adds the model, ratio and verdict per
  build and active PHY.

`D2D_COMPARE=<checkout> python3 scripts/test_perf_model.py` tests the adapter,
including the MAS Table 9 limits and the model's own AoU specification check.

## Checker inventory

`uvm/env/checkers/rules.csv` lists every rule the testbench checks, with exactly one
primary checker (`checker`), any cross-checks (`secondary`) and a scope: DUT
(the rule binds the DUT), MODEL (it binds the partner our models play, which
are self-checked or obey it by construction) or N/A (this DUT's interface cannot
exercise it). A checker written `via AOU-Rn` reports under that rule's ID.
A checker belongs to the environment and is passive, so its rule is checked in
every test that reaches it; tests provide stimulus. [AGENTS.md](AGENTS.md)
("Where checks live") gives the rule and its carve-outs.

Every checker counts its evaluations and violations in a rule ledger
(`uvm/env/checkers/aou_rule_log.svh`), and each T1 run prints it at the end as
`RULE-LEDGER <rule> <checker> checks=<n> fires=<n>` lines. `make rule_inventory`
collects them from the runs under `out/` and writes `docs/checker_inventory.md`.
For the AoU specification's 45 checkable rules and UCIe r1.1's 41 FDI handshake
rules, it gives the primary checker, the test that exercises it most, and the
evidence: fires in a negative test, and checks in passing runs. The summary lists the rules with no
checker, two primaries, a checker that never runs, or one that never fired.

## RTL assertions

Some RTL modules carry their own checks under `ASSERTION_ON` (FIFO ready/valid,
M-port AW/AR stability in the 1xN switch, table ID errors in the early-response,
aggregator, splitter and downsizer tables, AWREADY within 500 cycles of AWVALID in
the WLAST generator). The WLAST generator's check is turned off with `$assertoff` in
`+rtl_asserts=1` runs (BUGS/054: AXI puts no bound on AWREADY); every other one stays
on. `make build RTL_ASSERT=1` compiles them into its own `-assert` build
directory, and `run_list.py --target <CONFIG>-assert` runs on it. A firing assertion calls
`$finish` before the UVM report, which `check_run.py` judges FAIL.
`testlists/assertions.toml` is the representative regression (plan 11.18);
its entries pass `+rtl_asserts=1`, which is fatal on a build without the
assertions, so they cannot pass on an ordinary build. The assertions use SVA
ranges (`##[0:500]`), so the build is VCS-only for now.

## Building against a candidate RTL fix

`make build RTL_PATCH=<absolute path>` copies `RTL/` into the build directory
(`build/<sim>-...-fix-<name>/rtl/`, `<name>` being the patch's file name without its
extension), applies the patch there and compiles that copy, so the source tree is
never modified. Runs of that build go to `out/<build>-fix-<name>/`, and
`run_list.py --rtl-patch <path>` runs a list on it. The patch stays outside the
repository; this is how a proposed RTL fix is tested before it is published.

## Register tests

`TB=reg` builds `tb/aou_reg_top.sv`, which is `AOU_CORE_TOP` with only its APB port
driven, and runs the register tests in `uvm/tests/reg/`: `aou_reg_hw_reset_test`,
`aou_reg_bit_bash_test`, `aou_reg_access_test`, `aou_reg_reserved_test`,
`aou_reg_alias_test` and `aou_reg_feature_seq_test`.

```sh
make build TB=reg
make run TB=reg TEST=aou_reg_access_test SEED=1
```

They use the register model generated from `csr/aou-core.rdl` and committed as
`uvm/env/gen/aou_core_csr_uvm_pkg.sv` (`make ral` regenerates it; `make lint` fails
when it is stale) with explicit prediction from the APB monitor. `uvm/env/apb/aou_reg_policy.svh`
lists which fields are compared and why. Failures caused by known DUT bugs are listed
in `expected_fail.yaml`. Each entry gives the bug and the exact failing check. Rule IDs
(`APB-Rnn`, `REG-Rnn`) are defined in `uvm/env/checkers/rules.csv`.

## Acknowledgements

**GitHub PR 80** ("verif: add Verilator-first UVM verification flow", Vinh
Trieu and Quang Le, VNCHIPLabs, Apache-2.0) is where this testbench started: a
pinned uvm-core compiled from source, a Verilator-first build, AXI, FDI, APB,
reset and status interfaces, AXI and FDI components, a minimal FDI peer and a
deterministic four-RP write/read smoke test. Its three commits are kept with
their authorship. Still in use, with their VNCHIPLabs copyright and SPDX headers
(ours added where we changed a file):

- `uvm_dpi_verilator.cc`: the uvm-core DPI shim for Verilator, written for PR 80.
  It follows the structure of uvm-core's `src/dpi/uvm_dpi.cc` and compiles the
  uvm-core DPI sources it includes.
- `scripts/get_uvm_core.sh`: fetches the pinned uvm-core (`make setup`).
- `uvm/env/pkg/core/aou_pkg.sv`: an independent AoU message and flit encoder, kept
  unchanged as the cross-check of the L3 codec in `aou_l3_codec_test`
  (`TB=l3_unit`).
- `tb/aou_status_if.sv`: T1's `status` interface (moved from `intf/`).
- The Makefile, whose header and basic build/run structure come from PR 80.

`uvm/env/axi/aou_axi_bus_if.sv` and `uvm/env/apb/aou_apb_if.sv` were derived from PR 80's AXI
and APB interfaces, and the clock, reset and tie-off code of `tb/tb_top.sv`
and `tb/aou_reg_top.sv` from its testbench top; each says so in its header.

The smoke bench itself (`aou_tb_top`, `aou_multi_rp_smoke_test`, its
environment, FDI peer, AXI driver and FDI monitor, `aou_uvm_pkg` and its file
list, and the AXI, FDI, APB and reset interfaces only it used) has been retired:
T1 covers the same ground with the layered models, and keeping it meant a
second set of components and lint waivers for code no longer developed
(docs/DECISIONS.md D0). It remains in the history.

**Third-party material.** Nothing below is vendored; `make setup` installs it
into the git-ignored `.deps/`.

| Component | Used for | Licence |
|---|---|---|
| [Accellera uvm-core](https://github.com/accellera-official/uvm-core) 2020.3.1, pinned commit | UVM library on every simulator | Apache-2.0 |
| [z3-solver](https://pypi.org/project/z3-solver/) (Microsoft Z3) | Verilator's `randomize()` solver | MIT |
| [PeakRDL](https://github.com/SystemRDL/PeakRDL), peakrdl-cli, [peakrdl-uvm](https://github.com/SystemRDL/PeakRDL-uvm) | Register model generated from `csr/aou-core.rdl` | LGPL-3.0 |
| [systemrdl-compiler](https://github.com/SystemRDL/systemrdl-compiler) (PeakRDL dependency) | RDL front end | MIT |
| [pywellen](https://pypi.org/project/pywellen/) 0.25.6 | FST/VCD reader for `scripts/waveq.py` and `scripts/axi_outstanding.py` | BSD-3-Clause |
| Arm Axi4PC ([BP063](https://developer.arm.com/downloads/view/BP063)), optional; unpacked only from a tarball the user downloads (`AXI4PC_TGZ`) | AXI4 protocol assertions on the T1 DUT's AXI ports | Arm's, no redistribution |

The APB interface assertions (`uvm/env/apb/aou_apb_if.sv`, rules `APB-R01`..`APB-R14`)
are adapted from the interface checks of
[amiq_apb](https://github.com/amiq-consulting/amiq_apb) (AMIQ Consulting,
Apache-2.0); the file and `uvm/env/checkers/rules.csv` say which.

Protocol rules from specifications are cited by document and section only, and
no specification text is reproduced: AXI4 (Arm IHI 0022, sections such as
A3.4.1), AMBA APB (Arm IHI 0024), UCIe r1.1 chapter 8 (FDI) and the AoU
specification. Arm's AXI4 protocol checker (BP063) is optional and never
committed (see "Optional: Arm AXI4 protocol assertions").
