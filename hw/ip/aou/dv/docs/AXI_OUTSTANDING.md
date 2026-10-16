<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Outstanding AXI transactions from waves

A histogram of outstanding AXI transactions (time spent at each outstanding
level, peak, mean, and the depth each new request saw) on one or more AXI
interfaces, from a run's waves. Use it for questions about AXI queue depth or
concurrency, how many reads or writes were in flight, or whether a test
exercised deep outstanding traffic.

`hw/ip/aou/dv/scripts/axi_outstanding.py` counts, at each rising edge of the
interface clock:

- **write:** +1 per AW handshake, −1 per B handshake;
- **read:** +1 per AR handshake, −1 per R handshake with RLAST.

It prints, per interface and direction: issued, completed, still outstanding
at the end, peak, mean (over all cycles and over busy cycles), and a table of
cycles spent at each level with how many new requests were issued at that
level. Signals are sampled just before each rising edge, so the clock's phase
doesn't matter. It reads FST and VCD with pywellen (`make setup` installs
it) and FSDB through Verdi's `fsdb2vcd`, via `scripts/waveio.py`; see
[WAVE_DEBUG.md](WAVE_DEBUG.md) for the details.

## 1. Get waves

Use the run's `waves.fsdb` (VCS) or `waves.fst` (Verilator). If the run has
none, rerun the same test and seed with `WAVES=1` and a new `RID`, copying the
plusargs from its `run.sh` (no rebuild; see [WAVE_DEBUG.md](WAVE_DEBUG.md)).

## 2. Pick the interface and direction

```bash
S=hw/ip/aou/dv/scripts/axi_outstanding.py
python3 -I $S <run>/waves.fsdb --list
```

`--list` prints each prefix with the directions it has. If the request
doesn't name both the interface and the direction, ask the user before running
anything:

- **Interface** (single-select, or multi-select when they may want several):
  offer the testbench interfaces first, with what they are. In T1:
  - `tb_top.s_axi[N].`: local side, TB manager driving the DUT's
    subordinate port for RP N;
  - `tb_top.m_axi[N].`: remote side, DUT's manager port driving the TB
    subordinate for RP N.

  Mention that the DUT's ports and internal buses are listed too (the
  `u_dut...` names) and can be chosen through "Other". Skip the
  `tb_top.s_` / `m_` flattened port names; they duplicate `s_axi[N]` /
  `m_axi[N]`.
- **Direction:** Write (AW to B), Read (AR to last R), or Both.

If there is only one AXI interface (for example `aou_axi_selftest_top.axi0.`),
don't ask about it; ask only about the direction if that's unclear.

## 3. Run and report

```bash
python3 -I $S <run>/waves.fsdb --if 'tb_top.s_axi[0].' --dir write
# several interfaces; a window; CSV for plotting
python3 -I $S <wave> --if 'tb_top.s_axi[0].' --if 'tb_top.m_axi[0].' --dir both \
    --from 270ns --to 1600ns --csv <run>/outstanding.csv
```

Pass the prefix exactly as `--list` printed it, trailing `.` included. Times
need a unit. The default window is the whole run.

The DUT's own ports split channels across stems (B for `I_AOU_TX_AXI_S_*`
comes out on `O_AOU_RX_AXI_S_BVALID`), so `--list` marks them `missing ...`.
Point the missing roles at the right signals:

```bash
P=tb_top.u_dut
python3 -I $S <wave> --if $P.aou_tx_axi_s_ --dir write --clock $P.I_CLK \
    --sig bvalid=$P.O_AOU_RX_AXI_S_BVALID --sig bready=$P.I_AOU_RX_AXI_S_BREADY
```

Report the table as the script prints it, then a sentence or two: the peak,
where most time was spent, and anything odd. Odd things to call out:

- **Issued ≠ completed + still outstanding**, or responses with nothing
  outstanding (the script warns): a protocol problem, or a `--from` that starts
  mid-traffic. Move `--from` to an idle point before blaming the design.
- **Still outstanding at the end of a passing test:** a transaction the
  scoreboard never closed.
- **Peak at a limit:** compare it with the configured outstanding limits
  (TB agent config, DUT credits and FIFO depths) to tell whether a test
  reached them.

Cross-check against the scoreboard summary in `sim.log`
(`[aou_scoreboard] local->remote N writes M reads ...`): issued writes and
reads on `s_axi[N]` equal its local-to-remote counts.

## Limits

- Counts whole transactions, not beats, and ignores IDs; W beats don't
  matter (AXI4 B can't precede its AW).
- Vector-packed ports (one `awvalid[N-1:0]` for N ports) aren't split; `--list`
  marks them, so use the per-RP interface instances.
- About 0.3 s per 20,000 cycles on FST; the first read of an FSDB also
  converts it to VCD.
