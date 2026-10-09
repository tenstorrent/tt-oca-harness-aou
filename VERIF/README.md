<!--
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2026 Tenstorrent USA Inc
-->

# AOU-RTL Verification

Open-source, Python-driven testbench for `AOU_CORE_TOP`, built on
[cocotb](https://www.cocotb.org/) +
[`cocotbext-axi`](https://github.com/alexforencich/cocotbext-axi). All
verification IP is fetched at install time via `pip` -- no commercial
VIP and no PULP-Platform sources are vendored into this repository.

The testbench runs out of the box on the open-source
[Verilator](https://verilator.org/) simulator and (optionally) on
Synopsys VCS for those with a commercial license.

## What it does

- Instantiates two `AOU_CORE_TOP` cores (`u_dut1`, `u_dut2`) connected
  back-to-back via single-PHY FDI loopback, with `RP_COUNT=1`. Three
  parallel harness top modules cover three FDI widths and are selected
  via the `FDI_CONFIG` Make knob (default `sp32b`):
  - `aou_cocotb_top`         -- `FDI_CFG_SP_32B`  (256b FDI)
  - `aou_cocotb_top_sp64b`   -- `FDI_CFG_SP_64B`  (512b FDI)
  - `aou_cocotb_top_sp128b`  -- `FDI_CFG_SP_128B` (1024b FDI, 2-step packing)
- Exposes the four AXI buses and two APB slave buses as flat top-level
  ports using `cocotbext-axi`'s canonical signal naming so the Python
  side can use `AxiBus.from_prefix(dut, "<prefix>")` /
  `ApbBus.from_prefix(dut, "<prefix>")`:
  - `s_axi_d1_*` -- DUT1 slave  (512-bit data) -- driven by `AxiMaster`
  - `m_axi_d1_*` -- DUT1 master (512-bit data) -- terminated by `AxiRam`
  - `s_axi_d2_*` -- DUT2 slave  (256-bit data) -- driven by `AxiMaster`
  - `m_axi_d2_*` -- DUT2 master (256-bit data) -- terminated by `AxiRam`
  - `apb1_*` -- DUT1 APB slave (32-bit data) -- driven by `ApbMaster`
  - `apb2_*` -- DUT2 APB slave (32-bit data) -- driven by `ApbMaster`
- APB activation (write `0x1` to `paddr=0x8`) is driven from Python via
  `cocotbext.axi.ApbMaster` after each reset deassertion. The harness
  has no SV-side activate sequence and no `o_apb_init_done` handshake;
  the activation step lives in `apb_activate()` inside
  `tests/dut_setup.py` and runs as part of every `bring_up()`.
- FDI loopback tests: one AXI write + one AXI read on each DUT slave;
  pass iff the read data byte-for-byte matches the previously written
  data.
- CSR reset readback test: reads every register defined in
  [`csr/aou-core.rdl`](../csr/aou-core.rdl) over APB on both DUTs
  immediately after reset (and *before* APB activation), verifying
  every sw-readable, reset-bearing field matches the RDL-defined reset
  value. The expected-value table is built at runtime from the RDL via
  `systemrdl-compiler`, so it self-updates whenever the RDL changes.

## Prerequisites

- Python 3.10+ compiled with shared library support (most distro
  packages already are; `find_libpython` will surface a clear error if
  yours is not).
- Verilator 5.046+ (built with `--timing` support) for the default
  flow, or Synopsys VCS 2023.x+ for the commercial flow.
- A C++20-capable `g++` (GCC 10 or newer) on `PATH` for Verilator's
  C++ build phase. On RHEL/CentOS-derived systems use
  `scl enable gcc-toolset-13 bash` (or similar) before invoking `make`.
- A clean POSIX shell (the scripts are bash-based).
- `systemrdl-compiler` -- installed automatically by
  `setup_cocotb_env.sh` via `requirements.txt`. Used by the CSR reset
  readback test to parse `csr/aou-core.rdl` and derive the expected
  post-reset values.

## One-time setup

```bash
cd VERIF
bash setup_cocotb_env.sh
source venv/bin/activate
```

`setup_cocotb_env.sh` creates a local venv under `VERIF/venv/`
(gitignored) and installs every Python dependency in
`requirements.txt`. Override the venv location with `VENV_DIR=...` or
the interpreter with `PYTHON=/usr/bin/python3.12`.

## Running the tests

From `VERIF/` with the venv activated:

```bash
make                     # Verilator (default), 8 parallel C++ compile jobs
make SIM=vcs             # Synopsys VCS
make WAVES=1             # enable waveform dump
                         #   verilator -> dump.vcd  (in this directory)
                         #   vcs       -> dump.fsdb (if Verdi is on PATH)
                         #             or dump.vpd  (otherwise)
make SIM=vcs WAVES=1 WAVES_FORMAT=vpd   # force VPD instead of FSDB
make FDI_LOG=1           # enable fdi_flit_decoder under +define+FDI_LOG
make FDI_CONFIG=sp32b    # 32B FDI loopback (default; aou_cocotb_top)
make FDI_CONFIG=sp64b    # 64B FDI loopback (aou_cocotb_top_sp64b)
make FDI_CONFIG=sp128b   # 128B FDI loopback (aou_cocotb_top_sp128b)
make JOBS=16             # override C++ compile parallelism (default 8)
make JOBS=1              # serial compile (useful when debugging compile errors)
make JOBS=0              # use all available cores
make clean               # remove sim_build/ and generated artefacts
```

`JOBS` controls how many `g++` invocations Verilator runs in parallel
during the C++ build phase. Each translation unit can use up to ~1 GB
of RAM, so cap `JOBS` if memory is tight.

A successful run prints `*** SIMULATION PASSED ***` and writes a
per-(simulator, FDI config) `results_<sim>_<fdi_config>.xml` JUnit file
(e.g. `results_verilator_sp32b.xml`) at the end of each cocotb test
module, so back-to-back runs that switch simulator do not clobber each
other's results.

### Running all three FDI variants in parallel

The CI workflow runs `sp32b`, `sp64b`, and `sp128b` on separate matrix
runners. Locally you can launch all three concurrently from the same
`VERIF/` directory; produced artefacts are namespaced by FDI config so
they never collide:

```bash
make FDI_CONFIG=sp32b  & \
make FDI_CONFIG=sp64b  & \
make FDI_CONFIG=sp128b & \
wait
```

Per-config artefacts (each lives in `VERIF/`):

- `results_<sim>_<config>.xml`   JUnit test results
- `sim_build/<sim>_<config>/`    Verilator/VCS build artefacts
- `dut1_fdi_<config>.log`,
  `dut2_fdi_<config>.log`        FDI flit-decoder logs (`FDI_LOG=1`)
- `dump_<config>.vcd`            Verilator VCD (`WAVES=1`)
- `dump_<config>.fsdb`,
  `dump_<config>.vpd`            VCS waveform dumps (`SIM=vcs WAVES=1`)

## Repository layout

```
VERIF/
  README.md              this file
  .gitignore             venv/, sim_build/, waveforms, etc.
  requirements.txt       pinned Python deps
  setup_cocotb_env.sh    venv + pip install bootstrap
  Makefile               make-flow entry point (Verilator + VCS)
  aou_cocotb_top.sv         SV harness, 32B FDI loopback (default top)
  aou_cocotb_top_sp64b.sv   SV harness, 64B FDI loopback
  aou_cocotb_top_sp128b.sv  SV harness, 128B FDI loopback
  aou_cocotb.f           file list (RTL + harness)
  decoder/
    fdi_flit_decoder.sv  passive FDI flit decoder (gated by FDI_LOG)
  tests/
    conftest.py          pytest fixtures (sim parametrisation)
    dut_setup.py         shared bring-up helpers (clocks, reset,
                         BFM construction, APB activate, watchdogs)
    test_aou_loopback.py FDI loopback test (Python ApbMaster + AxiMaster)
    test_csr_reset.py    CSR reset-value readback test (RDL-driven)
    csr_reset_model.py   parses csr/aou-core.rdl into expected
                         (mask, value) per register
    axi_helpers.py       AxiBus / ApbBus signal-map factories
```

## Test coverage

| Test | Direction | Master | Memory | Check |
|------|-----------|--------|--------|-------|
| `test_forward_loopback` | `u_dut1.SI` -> FDI -> `u_dut2.MI` | `AxiMaster` on `s_axi_d1` (512b) | `AxiRam` on `m_axi_d2` (256b) | read-data == write-data |
| `test_reverse_loopback` | `u_dut2.SI` -> FDI -> `u_dut1.MI` | `AxiMaster` on `s_axi_d2` (256b) | `AxiRam` on `m_axi_d1` (512b) | read-data == write-data |
| `test_both_directions` | both, concurrent | both masters | both rams | both reads match their writes |
| `test_csr_reset_values` | both DUTs, APB-only, pre-activation | `ApbMaster` on `apb1`/`apb2` (32b) | n/a | `(read_value & mask) == expected` per RDL register |

Loopback address space is `0x0..0x3F` (64 bytes).

`test_csr_reset_values` runs `bring_up(dut, activate=False)` so
registers like `aou_init` (which the activation write mutates) are
still in their virgin reset state when sampled. Only sw-readable
fields with an RDL-defined `reset` property contribute to the mask;
hw-driven status bits and write-only fields are deliberately excluded
so the check stays deterministic.

## Watchdogs

Each test has an overall sim-time timeout (`OVERALL_TIMEOUT_US = 500`)
plus per-phase budgets for reset, APB activate write, APB read, AXI
write, and AXI read. On stall, the test fails with

```
WATCHDOG: stuck waiting for '<phase>' for <N> ns
```

followed by a snapshot of the relevant signal values (resets, APB
`psel/penable/pready/pslverr` on both DUTs, AXI valid/ready on every
interface, etc.) so the stuck phase is named in the failure log
instead of the simulator spinning silently. Tune the `*_TIMEOUT_NS`
constants at the top of `tests/dut_setup.py` if your simulator is
slow or your scenario legitimately needs more time.

## Current scope and limitations

- `RP_COUNT` is fixed at 1.
- `TWO_PHY` is intentionally not exercised (single-PHY only, matches
  the FDI configuration overridden on each DUT instance).
- APB write coverage today is limited to the AOU activate register and
  the CSR-reset readback exercises APB reads only; field-level RW
  round-trip coverage via `ApbMaster.read()` / `.write()` is a
  follow-up. The BFMs are already constructed in `bfms["d1_apb"]` /
  `bfms["d2_apb"]` and are reusable from any new test.
- Random stress and constrained-random regression suites are not yet
  in scope.
- Cocotb's VPI-bridged simulation is throughput-limited compared to
  native SV testbenches; for very large regressions plan accordingly.

## Optional SystemVerilog UVM smoke

`VERIF/uvm/` contains a separate Verilator/UVM smoke flow. It complements the
Python/cocotb tests above and does not replace their loopback, FDI-width, or
CSR-reset coverage. See [`VERIF/uvm/README.md`](uvm/README.md) for setup and
usage.
