# SystemVerilog UVM smoke

This directory provides an optional SystemVerilog UVM flow alongside the
existing Python/cocotb verification in `VERIF/`. It does not replace or alter
the cocotb tests.

Credits: Vinh Trieu and Quang Le (VNCHIPLabs).

The smoke uses Verilator, the repository RTL filelist, and one write/read
round trip on each of the four RPs. It uses RP_COUNT=4, AXI_DATA_BYTES=64
(AXI_DATA_W=512), and FDI_CONFIG=SP64B (FDI_DATA_W=512). It demonstrates the
UVM build and reusable driver/environment path; the existing cocotb suite
remains the maintained loopback, FDI-width, and CSR-reset flow.

## Setup and run

Use Verilator 5.052, a C++ compiler, GNU Make, Python-free simulator runtime,
and Git. Setup fetches Accellera UVM-core 2020.3.1 at commit
`78c06547a2a0a29b3dc9dcafae62b75b2ff61544` into the ignored `.deps/` directory.
From the repository root, run:

```sh
cd VERIF/uvm
make setup
make test TEST=aou_multi_rp_smoke_test SEED=1
```

Build output and the run log are kept under the ignored `build/` directory.

This smoke does not use a register abstraction layer. Future UVM CSR tests
should consume `INTEG/uvm/aou_core_csr_uvm_pkg.sv`, generated from
`csr/aou-core.rdl` by `bash scripts/gen_collateral.sh`; do not maintain a
second register model in this testbench.
