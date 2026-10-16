<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Debugging failures from waves

How to debug a failing `hw/ip/aou/dv` run (a `make run`, or a regression) from
waveforms plus logs: triage by signature, rerunning with `WAVES=1`, reading the
waves as text with `scripts/waveq.py`, where to look in T1, and the evidence a
fix or a bug link must cite. Paths below are relative to `hw/ip/aou/dv` unless they
start with a top-level directory of the repository.

Waves answer "what actually happened on the wires" in one query, where logs
leave you guessing. Use them before the second guess at a fix, not after the
fifth.

## 1. Triage by signature

1. List the failing runs and their first error:
   `grep -m1 -E "UVM_(ERROR|FATAL) " out/<build>/<run>/sim.log`
2. Group runs by signature: the checker or rule ID plus the message with times,
   IDs and addresses stripped.
3. For each signature, pick the **shortest** failing run (smallest sim time at
   the first error, then the smallest `run_s` in `build/metrics.jsonl`).
4. Rerun only that one with waves, same test and seed, new RID:

```bash
make run SIM=<vcs|verilator> TB=<tb> [CONFIG=..] TEST=<test> SEED=<seed> RID=w1 WAVES=1 [PLUSARGS=..]
```

Copy every plusarg from the failing run's `run.sh`. Default builds are
wave-capable, so this never rebuilds. A `-nowaves` build (`WAVES_BUILD=0`)
can't dump; `make` stops with an error if you try.

Output in the new run directory: `waves.fsdb` on VCS (written by the generated
`waves.tcl` UCLI script), `waves.fst` on Verilator. On VCS, the `ANF: ...
undefined symbol` lines in `novas_dump.log` are harmless dumper noise.

## 2. Read the waves with waveq.py

`hw/ip/aou/dv/scripts/waveq.py` reads FST and VCD with pywellen (installed by
`make setup`) and FSDB through Verdi's `fsdb2vcd` (load the VCS/Verdi module;
the converted VCD is cached next to the FSDB). If `WAVEIO_WQ` names a
directory holding a compatible external waveform-to-text reader, FSDB goes
through that instead.

```bash
Q="python3 -I hw/ip/aou/dv/scripts/waveq.py"
```

Work outward from the first error's time in `sim.log` (UVM prints ps at the
`1ns/1ps` timescale; `@ 709000` is 709 ns).

```bash
# Find names first: a plain word matches by suffix; prints path and width.
$Q search waves.fsdb bvalid
# Indexed interfaces need regex: in a glob, [0] is a character class.
$Q search --kind regex waves.fsdb 's_axi\[0\]\.b[a-z]+$'
# One signal's history.
$Q changes waves.fsdb tb_top.fdi_mb0.pl_state_sts
# Several signals sampled just before each rising clock edge, rows on change.
$Q multi waves.fsdb tb_top.s_axi[0].bvalid tb_top.s_axi[0].bready \
    tb_top.s_axi[0].bid --clock tb_top.clk --from 690ns --to 711ns
# Time ranges where a signal equals (or doesn't equal) a value.
$Q find waves.fsdb tb_top.irq.int_req_linkreset --eq 1
# Values at one time.
$Q at waves.fsdb tb_top.irq.act_st_enabled --time 709ns
```

Gotchas:
- Paths have no bit range (`bid`, not `bid[9:0]`); a range is accepted and
  ignored. Search, then copy the path.
- `multi` numbers rows by rising edge from the start of the file; on T1's
  1 ns `clk` (first edge at 0.5 ns), edge N is the cycle ending at N.5 ns, so
  it lines up with the ns in `sim.log`.
- An empty `find` means the value never held in the window.
- Times need a unit (`709ns`); bare numbers are refused.
- Verilator is two-state, so an FST has no X or Z. Judge X-propagation on VCS.
- Verilator writes packed structs as member scopes (`--trace-structs`); query
  the members.
- The first FSDB read converts it to VCD, which takes a few seconds and about
  40 times the FSDB's disk space; later reads reuse it.

## 3. Where to look in T1 (`tb_top`)

Clock `tb_top.clk` is 1 ns; APB `pclk` is 10 ns.

| Area | Paths |
|---|---|
| AXI, local side (TB manager to DUT) | `tb_top.s_axi[N].{aw,w,b,ar,r}*` |
| AXI, remote side (DUT to TB subordinate) | `tb_top.m_axi[N].*` |
| FDI main band | `tb_top.fdi_mb0.*` (`fdi_mb1` in two-PHY builds): `pl_state_sts[3:0]`, `lp_valid`, `lp_irdy`, `lp_data[1023:0]`, `pl_valid`, `pl_trdy`, `pl_data[1023:0]`, `pl_stallreq`, `lp_stallack`, `pl_flit_cancel` |
| FDI link state | `tb_top.fdi_lsm.*`: `lp_state_req[3:0]`, `fdi_link_up`, ... |
| Interrupts and activation status | `tb_top.irq.*` (`int_req_linkreset`, `int_activate_start`, `int_deactivate_start`, `act_st_enabled`, `act_st_disabled`, ...) |
| Registers | `tb_top.apb.*` (`psel`, `penable`, `paddr[31:0]`, `pwdata`, `prdata[31:0]`, `pready`) |
| DUT activation FSM | `tb_top.u_dut.u_aou_core_top.u_aou_core.u_aou_activation_ctrl.*` (`r_cur_st[3:0]`, `I_ACTMSG_VALID`, `I_ACTMSG_ACTIVATION_OP[3:0]`, `O_ACTMSG_*`, `O_INVALID_ACTMSG_ERR`) |
| DUT FDI bringup | `tb_top.u_dut.u_fdi_bringup_ctrl.r_cur_st[11:0]` |
| Per-RP DUT logic | `tb_top.u_dut.u_aou_core_top.u_aou_core.gen_aou_core_rp[N].u_aou_core_rp.*` |

Interface signals named `*_cb.*` are clocking-block copies; prefer the plain
interface signal. Other TBs: search from their top
(`aou_reg_top`, `aou_axi_selftest_top`, `aou_l3_unit_top`).

DUT internals explain a failure; they never define the expected behaviour.
Expectations still come from the AXI4/UCIe/AoU specs and the MAS
([AGENTS.md](../AGENTS.md), "Boundaries").

## 4. Decide, fix, record

- **Testbench bug** (checker timing, sequence, model): fix it, rerun the
  waves run without `WAVES=1` and the original failing seeds, then the
  affected testlist.
- **DUT bug or unspecified behaviour**: add or update the draft in the staging
  area, or comment on the GitHub issue once it is filed (see
  [AGENTS.md](../AGENTS.md), "Reporting bugs"), with the wave evidence, and tie
  the failure to it in `expected_fail.yaml`.
- **Evidence** (required in the context of commit messages, reports and bug drafts):
  the waves run directory, the signals, and the times or cycles that explain
  the failure, for example "`s_axi[0].bvalid` rises at cycle 704, `bready`
  low until 709; checker timed B from the handshake".
