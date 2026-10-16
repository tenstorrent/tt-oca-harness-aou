# AOU CSR Documentation

All files in this directory are generated from the SystemRDL source
(`csr/aou-core.rdl`).  Do not edit them by hand -- regenerate instead.

## Generated outputs

| File | Description |
| :--- | :--- |
| [aou-core-csrs.md](aou-core-csrs.md) | Markdown register reference (address map, fields, access, reset values). |
| [aou_core_csr.h](aou_core_csr.h) | C header with `#define` macros for register offsets and field masks. |
| [html/](html/) | Interactive HTML register browser (open `html/content/index.html` locally or host on GitLab Pages). |

Additional generated collateral lives outside this directory:

| File | Description |
| :--- | :--- |
| `INTEG/ipxact/gen/aou_core_regmap.xml` | IP-XACT (IEEE 1685-2014) register memoryMap for SoC integration tools. |
| `INTEG/uvm/aou_core_csr_uvm_pkg.sv` | UVM register model package (`uvm_reg_block`) for downstream UVM verification environments. |

Note: the in-repo UVM testbench (`hw/ip/aou/dv/`) generates its own copy
of this model with the same PeakRDL command
(`hw/ip/aou/dv/scripts/regen_ral.sh`, `make ral`) and commits it as
`hw/ip/aou/dv/uvm/env/gen/aou_core_csr_uvm_pkg.sv`; its `make lint`
fails when that copy and the RDL drift apart. The `INTEG/uvm/` package
is the integration collateral for users whose own verification
environments are UVM-based.

## Regeneration

A single script regenerates all of the above from the RDL source:

```bash
source venv/bin/activate
bash scripts/gen_collateral.sh
```

See the top-level [README.md](../../README.md) for virtual-environment setup instructions.
