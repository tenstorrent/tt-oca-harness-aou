<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# perf.json: performance record of one run

`aou_perf_test` writes `perf.json` next to `perf.txt` in its run directory. It
holds what ran (the build and the traffic issued) and what was measured, so a
reference model can be rebuilt for exactly that run and compared with it.
`perf.txt` (one `metric value` per line, read by `scripts/perf_report.py`) is
unchanged. Schema version: 1.

## Conventions

- **Directions.** `l2r` is the link from the DUT to the remote die (DUT TX
  flits); `r2l` is the link from the remote die to the DUT (DUT RX flits).
  Under `dir`, everything is per link direction. Under `init`, `l2r` means the
  transactions issued by the local managers (DUT S-ports) and `r2l` those issued
  by the remote-die managers, which is what `perf.txt`'s `<win>.l2r.*` and
  `<win>.r2l.*` metrics measure.
- **Application bytes on a link** (`dir.<d>.app_bytes`): the payload carried on
  that link, i.e. write data of transactions issued on the sending side plus read
  data of transactions issued on the receiving side. Bytes are AXI bytes,
  `(len + 1) << size` per transaction (every perf window uses full strobes).
- **Cycles** are core clock cycles (1 ns). The FDI runs on the same clock in
  every configuration, two-PHY builds included, so `beat_bytes` is bytes per
  core cycle. Times (`t_*`) are in cycles since time 0.
- **Steady state.** For each link direction, take the data messages
  (WriteData*, ReadData*) that crossed it, in time order. Drop the first and
  the last `ss_drop_pct` percent (default 10). The sub-window runs from the last
  dropped head message (`t_start`) to the last kept one (`t_end`); `flits` and
  `granules_by_msg` count what crossed in `(t_start, t_end]`. Its `app_bytes`
  are the DLENGTH bytes of the data messages in it, scaled by the window's AXI
  bytes per DLENGTH byte on that link (exactly 1 for full-width, full-strobe
  bursts). Data messages, not completions, set the sub-window, because a write
  completes when its B returns, which can lag and bunch. `ss_ok` is true when at
  least `min_ss_flits` (default 2000) flits crossed in the sub-window. A link
  with no data in the window has `"ss": null`. `full` counts transactions by
  completion, from `t_open` to the last completion of a transaction whose data
  cross the link.
- Message names are the AoU specification's (and `d2d_model.py`'s): `ReadReq`,
  `WriteReq`, `WriteResp`, `ReadData256|512|1024`, `WriteData256|512|1024`,
  `WriteDataFull256|512|1024`, plus `CrdtGrant` and the activation messages
  (`ActivateReq`, `ActivateAck`, `DeactivateReq`, `DeactivateAck`). A message is
  counted when the remote-die model has decoded it (DUT TX) or put it in a flit
  (DUT RX); flits are counted per cycle.
- Knobs: `+perf_ss_drop_pct`, `+perf_min_ss_flits`;
  `+perf_remote_full_pct=<pct>`; `+perf_kb=<KB>` (at least this much payload
  per direction per bandwidth window, default 768) or `+perf_n=<n>`
  (transactions per RP and direction); `+perf_dir=l2r|r2l|both` (which side
  issues, default both); `+perf_slots=<n>` (outstanding transactions per
  manager, default 32); `+perf_l3_depth=env` (the env's small remote-die
  credit depths instead of the perf ones).

## Layout

```json
{
  "schema": 2,
  "build": {
    "config": "1x512-sp64",
    "sim": "vcs",
    "test": "aou_perf_test",
    "seed": 1,
    "perf_mode": "bw",
    "active_phy": 0,
    "n_phy": 1,
    "beat_bytes": 64,
    "rp_count": 1,
    "rp_bytes": [64],
    "remote_bytes": [64],
    "max_awlen": [15],
    "max_arlen": [15],
    "writefull": true,
    "remote_full_pct": 100,
    "l3_rx_depth": {"WREQ": 64, "RREQ": 64, "WDATA": 256, "RDATA": 256, "WRESP": 32},
    "ss_drop_pct": 10,
    "min_ss_flits": 2000
  },
  "windows": [
    {
      "name": "bw_wr",
      "scenario": "S1",
      "traffic_dir": "both",
      "wr_pct": 100,
      "t_open": 12345,
      "t_close": 15000,
      "dir": {
        "l2r": {
          "full": {"app_bytes": 32768, "cycles": 658, "flits": 164,
                   "granules": 7296, "duty": 0.997},
          "ss": {"app_bytes": 26214, "cycles": 506, "t_start": 12400, "t_end": 12906,
                 "flits": 126, "granules": 6000, "duty": 0.996, "ss_ok": false,
                 "granules_by_msg": {"WriteReq": 75, "WriteDataFull512": 5600, "WriteResp": 25},
                 "msgs_by_msg": {"WriteReq": 25, "WriteDataFull512": 400, "WriteResp": 25}},
          "app_bytes": 26214,
          "cycles": 506,
          "flits": 126,
          "granules_by_msg": {"WriteReq": 75, "WriteDataFull512": 5600, "WriteResp": 25},
          "duty": 0.996
        },
        "r2l": {"...": "same fields"}
      },
      "init": {
        "l2r": {"txns": 32, "bytes": 32768, "cycles": 658},
        "r2l": {"txns": 32, "bytes": 32768, "cycles": 658}
      },
      "dut_credit_low": {"wreq": 497, "rreq": 512, "wdata": 1890, "rdata": 2048, "wresp": 512},
      "txn_hist": [
        {"init": "l2r", "kind": "W", "rp": 0, "bytes": 1024, "beat_bytes": 64,
         "offset_mod_4k": 0, "full_strb": true, "count": 32}
      ]
    }
  ]
}
```

## Fields

`build`

| Field | Meaning |
|---|---|
| `config` | Build configuration (`CONFIG`, README "Build configurations"); `""` when the run was not started by `make run`. |
| `sim` | `vcs`, `verilator`, `xcelium`, `questa` or `unknown`. |
| `test`, `seed`, `perf_mode` | `+UVM_TESTNAME`, the run's seed (`SEED`), `+perf_mode`. |
| `active_phy`, `n_phy` | The PHY the link runs on (two-PHY builds pick it per seed unless `+active_phy=P`), and the PHY count. |
| `beat_bytes` | FDI data bytes per cycle on the active PHY; peak flit rate is `beat_bytes / 256`. |
| `rp_count`, `rp_bytes[]` | DUT AXI data bytes per RP. |
| `remote_bytes[]` | Remote die's AXI data bytes per RP (its WriteData/ReadData DLENGTH). |
| `max_awlen[]`, `max_arlen[]` | The DUT's split-transaction maximum AxLEN per RP, read from the RAL mirror (`AXI_SPLIT_TR_RPn`) when the window opens. The splitter divides the requests the DUT receives, at its manager port; bursts cross the link whole. |
| `writefull` | True when the windows' writes use full strobes, so WriteDataFull is the expected data message. |
| `remote_full_pct` | Percentage of the remote die's full-strobe write beats sent as WriteDataFull (the rest as WriteData). Perf runs use 100. |
| `l3_rx_depth` | Credits (granules) the remote-die model advertises per credit class and RP; the bench must not be the limit. |
| `ss_drop_pct`, `min_ss_flits` | Steady-state parameters (see Conventions). |

`windows[]`

| Field | Meaning |
|---|---|
| `name` | Window name, as the `perf.txt` prefix (`bw_wr`, `bw_rd`, `bw_mix`, `lat_wr`, ...). |
| `scenario` | Plan scenario the window serves (`S1` stream; `lat`, `drain` for the latency and drain windows). |
| `traffic_dir` | `l2r`, `r2l` or `both`: which sides issue transactions. |
| `wr_pct` | Write percentage of the traffic profile. |
| `t_open`, `t_close` | Window open, and close (after the last completion). |
| `dir.<d>.full` | The whole window: `app_bytes`, `cycles` (open to the last completion of a transaction whose data crosses this link), `flits`, `granules`, `duty`, `granules_by_msg`, `msgs_by_msg`. |
| `dir.<d>.ss` | The steady-state sub-window (Conventions), with `granules_by_msg` and `msgs_by_msg`; `null` without data on this link. `mix_cap`: the bytes per cycle the link could carry saturated with the messages it carried in the sub-window (48 five-byte granules per 256-byte flit at `beat_bytes` per cycle, as d2d_model packs). |
| `window_msgs.<d>` | Every message that crossed link `d` while the window was open, by type (the message-mix check, T1-P04). |
| `dir.<d>.app_bytes`, `cycles`, `flits`, `granules_by_msg`, `duty` | Copies of the `ss` values (of `full` when `ss` is null), for consumers that only want the gated numbers. Delivered bandwidth is `app_bytes / cycles`. |
| `duty` | `flits / (cycles * beat_bytes / 256)`: FDI flit-slot utilisation. |
| `init.<d>` | Transactions issued by side `d` in the window: count, AXI bytes, and cycles from open to that side's last completion. |
| `dut_credit_low` | Lowest credit (granules) the DUT held from the remote die per class during the window, over the RPs. Near 0 means remote-die credit could have limited the DUT. |
| `txn_hist[]` | The issued traffic, one entry per distinct (`init`, `kind`, `rp`, `bytes`, `beat_bytes`, `offset_mod_4k`, `full_strb`) with its `count`. `kind` is `W` or `R`; `beat_bytes` is `1 << AxSIZE`; `offset_mod_4k` is the start address modulo 4096. Aborted transactions are left out. |

Adding a field is compatible; renaming or removing one bumps `schema`.
