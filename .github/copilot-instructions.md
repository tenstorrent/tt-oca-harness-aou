<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Copilot instructions

The repository's instructions are in [AGENTS.md](../AGENTS.md) at the root, and for
the UVM testbench in [hw/ip/aou/dv/AGENTS.md](../hw/ip/aou/dv/AGENTS.md). They apply in
full; this file adds only what is specific to a GitHub-hosted runner.

## On a GitHub-hosted runner

The runner has no commercial simulators and no LSF, so only the open-source flow
works:

- **Simulator:** Verilator, at the version pinned in `.github/tool-versions.env`
  (the lint workflow installs it with `veryl-lang/setup-verilator`). There is no
  VCS, Verdi, Xcelium or Questa, so no FSDB waves and no VCS coverage; `SIM`
  defaults to Verilator when `vcs` is not on PATH.
- **No batch system:** without `bsub` on PATH the Makefile sets `LSF=0` and runs
  builds and simulations on the runner itself; no `site/site.mk` is needed. Single
  runs work this way (for example
  `make run SIM=verilator TEST=aou_fdi_t1_bringup_test SEED=1` passes). The local
  path times each job with GNU `/usr/bin/time` (Ubuntu package `time`).
- **Setup:** `cd hw/ip/aou/dv && make setup` needs network access (uvm-core from
  GitHub, z3, PeakRDL and pywellen from PyPI) and Python 3 with `venv`.
- **What runs** (from `hw/ip/aou/dv`):
  - `make lint` (also needs `verible-verilog-lint` on PATH);
  - `make build SIM=verilator JOBS=<cores>`: a T1 build takes 10 to 15 CPU-minutes
    and up to about 3 GB of memory, so match `JOBS` to the runner's cores;
  - `make run` / `make test`, and short run lists with `scripts/run_list.py -j <cores>`;
  - `make plan_status`, and `make fc_report` / `make cov_report` on `COV=1`
    Verilator runs;
  - `make check-public PUBLIC_BASE=origin/main` (without the git-ignored site
    patterns it checks the built-in patterns only);
  - `python3 scripts/test_*.py` (the script unit tests).
- **Keep it small:** a full regression is hours of CPU time; on a runner, run the
  tests that cover the change, not every configuration.
