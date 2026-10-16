<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# AGENTS.md

Instructions for coding agents (and people) working in this repository. This is
the single source: `CLAUDE.md` only imports it, and `.github/copilot-instructions.md`
only points here. Directories can add their own `AGENTS.md` with more specific rules.

## What this is

Open-source RTL for the AXI-over-UCIe (AoU) bridge: AXI4 traffic carried over the
UCIe Flit-Die Interface, with `AOU_TOP` and `AOU_CORE_TOP` as the top levels and an
APB configuration port. [README.md](README.md) describes the design, the directory
layout and the collateral flow (`scripts/gen_collateral.sh`).

## Ownership

- `RTL/`, `csr/` and `DOC/` belong to the RTL maintainers. Agents don't edit them,
  not even to make a test pass; changes to `RTL/`, `csr/` and `hw/ip/aou/dv/` need the
  maintainers' review (`.github/CODEOWNERS`).
- A proposed RTL fix goes on its own `bugfix/` branch for the maintainers to review,
  in one commit whose message gives the root cause and the resolution. It holds the
  RTL change only and starts from `main`, unless the fix also needs a testbench change
  (for example, the bench model must accept newly legal behaviour). In that case the
  same commit carries both, and the branch starts from the branch that holds the
  testbench. Branch names must start with `feature/`, `bugfix/`, `hotfix/`, `chore/`
  or `dependabot/` (checked in CI).

## Verification

- The verification environment is the VIP-free SystemVerilog UVM testbench in
  `hw/ip/aou/dv`. Its rules are in [hw/ip/aou/dv/AGENTS.md](hw/ip/aou/dv/AGENTS.md); read it
  before working there, and [hw/ip/aou/dv/docs/DECISIONS.md](hw/ip/aou/dv/docs/DECISIONS.md)
  before changing its structure or policy.
- There is no other testbench. The GitHub workflow `uvm-smoke.yml` runs the UVM
  bench's `ci` group (smoke, the short lists and the datapath area) on Verilator
  as the check-in qualification.

## Bugs

DUT bugs, RTL/documentation mismatches and unspecified behaviour are reported as
GitHub issues on `tenstorrent/tt-oca-harness-aou`; the issue is the record. A test
failure caused by one is tied to it by an entry in
`hw/ip/aou/dv/expected_fail.yaml` (`bug: tenstorrent/tt-oca-harness-aou#<n>` plus the
exact failing check), so the run is judged XFAIL instead of FAIL. Findings are
drafted and triaged first in `BUGS/` at the repository root, a git-ignored staging
area that is never committed; until a draft is filed the bench cites it as
`BUGS/<NNN>`, and `make check-config` lists those. The procedure, the template and
the filing tool are in `hw/ip/aou/dv/AGENTS.md` "Reporting bugs" and
`hw/ip/aou/dv/scripts/bugs/`.

## Public repository

This repository is public. Nothing site-internal goes into the tree or the commit
history: no site paths, hostnames, home directories, internal tools or tracker keys.
Site settings live in the git-ignored `hw/ip/aou/dv/site/`. Before anything is pushed,
run

```sh
python3 hw/ip/aou/dv/scripts/check_public.py --range origin/main..HEAD
```

(`make check-public` in `hw/ip/aou/dv` does the same against `main`). It must report
nothing; a line that documents a pattern on purpose ends in `public-ok`.

## Commits

- Short subject with an area prefix (`verif:`, `doc:`, ...), one concern
  per commit.
- The body explains why, not what; no file lists.
- Don't push unless asked; the integrator merges.
