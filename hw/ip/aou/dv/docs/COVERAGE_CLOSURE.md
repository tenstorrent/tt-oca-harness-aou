<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
-->

# Coverage-closure plan and test-plan gap analysis

The plan that drives coverage closure of the VIP-free UVM bench: where code and
functional coverage stand, why each hole is open, which test-plan items lack
evidence, and the work packages that close them. It was written against the
bench at `a4bf59a` and reviewed by the owner on 2026-10-14; the owner's answers
are in [Decisions](#decisions) and bind the work packages in §6. The coverage
policy itself is DECISIONS D10. Sections 1-5 are the analysis as written; what has
changed since is in the Status column of §6 (updated through PR #121), and fixes
that landed since are noted where they change a hole's class.

| | |
|---|---|
| Bench | `feature/vip-free-uvm-tb` at `a4bf59a` |
| Coverage data | Regression RID `cov3`: 7 configurations, VCS, COV=1, exclusions active at build time, every T1 run list plus `registers`, passing runs only |
| Earlier data | Commit `d04b2da` (5 configurations, old names, before exclusions), used only for comparison |
| Specs | AoU v0.7 (the RTL) and v0.8; UCIe r1.1 chapter 8 and r2.0 10.2/10.3 (cited by section); AXI4 IHI 0022; MAS `DOC/MAS/*.adoc` |
| Configurations | The cov3 data has one 4-RP mixed build, RP widths 1024/256/512/256 on SP_128B. The tables call it `4xmix`, or `4xmix4121-sp128` under the README digit rule, which it predates. WP10 replaced it with `4xmix4211-sp128` (1024/512/256/256) and `4xmix2144-sp64` (512/256/1024/1024), so cov3's 4xmix numbers don't carry over to either. |

## Decisions

The owner's answers to §7, 2026-10-14:

| # | Decision |
|---|---|
| D1 | **INCR bursts only.** AoU carries no AxBURST, so WRAP and FIXED are out of scope: `axi.txn_cg` loses its burst coverpoint, plan items 4.16/4.17 are dropped, the S-port agents are INCR-only and AXI-R19 flags any other burst as a stimulus error (DECISIONS D5). |
| D2 | **Bin fixes done.** Every row of §3.1 is applied, with one change: `cg_link_state cp_req` keeps `linkreset` and `disabled` as targets, because the bringup model expects them for teardown under SPEC encodings (FDI-M01); only `reserved` is illegal (FDI-R46 checks it). `cg_flit_occ cp_misc_half1 over` stays a v0.7 target; its v0.8 reading is left for later. |
| D3 | **v0.8 bins stay as holes**, in the denominator and tagged `spec: v0.8` in `fc.json` so reports show them apart; not waived. Which AoU revision `main`'s RTL implements is under investigation. |
| D4 | **Reset-only FSM transitions are excluded**, with reset behaviour checked another way (mechanism pending). |
| D5 | **Line and branch exclusions are deferred** to the end of closure. |
| D6 | **Closure is measured on the all-configurations union.** |
| D7 | **UCIe r2.0 is deferred** to the RTL/architecture review. |
| D8 | **The ID-mismatch "detect, then hard reset" variant is a test option** (`aou_id_mismatch_test +detect_only=1`), documented as dropping the check that the DUT takes the stray response within 500 cycles; the default runs keep it. A response that answers no request is illegal AXI (AXI4 A5), and MAS 7.2.2 defines only its detection, which is all the test checks. |
| D9 | **Plan changes approved:** drop 9.8, 22.5, 1.4 and 12.13 (2.7/2.10 stay until the spec drops PropertyReq); add the 51 items of §4.3 (the r2.0 ones are deferred with D7); retitle 9.5. |

**Hole classes** used throughout:

| Class | Meaning |
|---|---|
| **a** | reachable with new stimulus |
| **b** | blocked by an open DUT bug; "variant" means a bug-avoiding run could cover it now |
| **c** | config-dependent: needs a particular CONFIG or parameter |
| **d** | unreachable or dead in this IP's configuration; an exclusion or waiver candidate for owner review |
| **e** | needs formal or another method |
| **cg-bug** | the covergroup is wrong. Fix the bins: this is not a waiver |
| **v0.8** | a bin that only an AoU v0.8 partner or DUT can hit |

---

## 1. Status snapshot

Work-package progress since this snapshot is in the Status column of §6, which supersedes it.

### 1.1 Runs (cov3, LSF, 08:32 to 08:46)

| CONFIG | T1 runs | merged (PASS) | XFAIL | FAIL / unjudged |
|---|---|---|---|---|
| 1x512-sp64 | 312 | 281 | 31 | 0 |
| 4x512-sp64 | 265 | 219 | 45 | 1 FAIL |
| 3x512-sp64 (new) | 216 | 178 | 38 | 0 |
| 4xmix4121-sp128 | 225 | 184 | 40 | 1 unjudged |
| 1x256-sp32 | 207 | 166 | 41 | 0 |
| 2xmix-tp64_128 | 218 | 184 | 34 | 0 |
| 2x512-tp32_64 (new) | 214 | 183 | 31 | 0 |
| **T1 total** | **1657** | **1395** | **260** | **2** |
| reg bench (7 × 12) | 84 | 28 | 56 (three register findings; two fixed since by PR #118 and PR #113) | 0 |

The untriaged mix4, w256 and tp2 failures from `d04b2da` are gone (`err_resp`, `credit_return`,
`pack crossflit`, `lp_mode_traffic`, `int early`, `invalid_actmsg` on mix4); those tests now pass or
XFAIL. There are two new failures, not triaged here:

- **4x512-sp64 `aou_act_after_deact_test` seed 1.** AOU-R26 "DUT MsgCredit RDATA RP2=1 in DISABLED",
  plus AOU-R29. This looks like the credit-after-deactivation bugs PR #122 fixed, with a signature that `expected_fail.yaml`
  doesn't match on this config.
- **4xmix4121-sp128 `aou_pack_test +pk=crossflit +remote_bytes=128` seed 1.** AXI-R10, a 4 KB crossing
  on the RP1 (256-bit) M port. This looks like tenstorrent/tt-oca-harness-aou#90 with a signature `expected_fail.yaml`
  doesn't match. No `verdict.txt` was written.

**XFAIL runs per finding.** Each of these runs is coverage the merge loses. Findings fixed or
retired since are marked with the PR that did it.

| Finding | Runs | Tests |
|---|---|---|
| Activation messages out of step: late ActivateReq, re-sent ActivateReq, which messages are invalid | 49 + 42 + 23 | `aou_invalid_actmsg_test`, `linkreset_timeout` |
| Reserved bit 22 of the ID-mismatch error register is an enable (PR #118) | 42 | reg bench |
| AXI_SPLIT_TR_EN has no storage | 42 | reg bench |
| AOU_SW_RESET during traffic truncates bursts and strands beats (PR #113) | 42 + 30 | `link_event`, `reset` |
| A response that answers no request (illegal stimulus; detection-only checks since PR #117) | 35 | `aou_id_mismatch_test` (every run) |
| Credits after DeactivateAck, and a MsgCredit in its flit | 33 + 3 | `act_after_deact`, `credit_return`, `link_act_deact`, `reset`, … |
| AOU_SW_RESET behaviour undocumented (PR #113) | 28 | reg bench |
| FDI bring-up does not follow UCIe, no `lp_linkerror`, no restart after link-down (PR #108) | 21 + 14 + 14 | `fdi_t1_{bringup,linkdown,linkerror}_spec` |
| DEACTIVATE_FORCE sends PropertyReq on a DeactivateReq | 14 | `link_force_deact` |
| 1024-to-256-bit downsizer misplaces unaligned writes (#90, PR #89) | 8 | `dw_down1024` 5, `pack` 3 |
| Remote RX credit overrun (illegal stimulus; test removed) | 7 | `credit_violation` |
| Debug window through a narrow RP (PR #111) | 6 | `err_resp` |
| Two Activation messages in a flit | 6 | |
| LP mode switched while active (static configuration, PR #105/#106) | 5 | |
| Asymmetric DEST_RP (illegal configuration; test removed) | 5 | |

A run can name several bugs.

### 1.2 Code coverage (URG module-definition summary, T1 plus that config's reg bench)

| Report | Score | Line | Cond | Toggle | FSM | Branch |
|---|---|---|---|---|---|---|
| 1x512-sp64 | 81.55 | 94.17 | 90.68 | 73.55 | **58.62 (34/58)** | 90.75 |
| 4x512-sp64 | 80.67 | 93.81 | 92.00 | 70.79 | 53.45 (31/58) | 93.29 |
| 3x512-sp64 | 79.90 | 92.73 | 90.78 | 71.26 | 53.45 | 91.29 |
| 4xmix4121-sp128 | 78.31 | 89.67 | 88.98 | 68.97 | 53.45 | 90.49 |
| 1x256-sp32 | 73.08 | 88.83 | 82.22 | 57.00 | 53.45 | 83.91 |
| 2xmix-tp64_128 | 79.30 | 90.61 | 89.60 | 72.66 | 53.45 | 90.17 |
| 2x512-tp32_64 | 79.28 | 91.88 | 89.64 | 71.78 | 53.45 | 89.66 |
| **all-configs (union)** | **85.09** | **96.75** | **96.03** | **78.77** | **58.62** | **95.28** |
| d04b2da all-configs | 85.06 | 96.54 | 95.97 | 79.05 | 58.62 | 95.14 |

Union raw counts:

| Metric | Covered / total | Uncovered |
|---|---|---|
| Line | 4318/4463 | 145 |
| Cond | 10747/11191 | 444 |
| Toggle | 788313/1000816 | 212k |
| FSM | 34/58 | 24 |
| Branch | 4661/4892 | 231 |

- The union is a lower bound: there are 438 UCAPI-INSTANCEMISMATCH warnings. Two examples:
  - `AOU_RX_CORE_IN_MUX` toggle reads 50%; it is 99.97% in d04b2da. This is a merge-order artefact.
  - The reg bench's data doesn't map into some datapath instances on the mixed-width, two-PHY
    and 256-bit builds (UCAPI-MAP-SHAPEMISMATCH); only the register logic is mapped there.
- The FSM figure is 31/58 outside 1x512-sp64 because `AOU_AGGREGATOR`'s FSM is 0/4 there. The
  aggregator test is pinned to 1x512-sp64. No config adds FSM coverage over 1x512-sp64.
- The exclusions (3 LIB cells plus `AOU_TPSRAM`) move every metric by at most 0.02 points, as
  the preview predicted.

### 1.3 Functional coverage (bins counted by the bench, crosses included, no waivers)

| Group | 1x512 | 4x512 | 3x512 | 4xmix | 1x256 | 2xmix-tp | 2x512-tp | **all-configs** |
|---|---|---|---|---|---|---|---|---|
| axi.txn_cg | 135/403 | 135/403 | 135/403 | 154/403 | 116/403 | 154/403 | 135/403 | **154/403 (38%)** |
| axi.zero_cg | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 | 8/8 |
| axi4.*.cg_ar | 267/306 | 986/1224 | 744/918 | 960/1198 | 239/280 | 517/638 | 500/612 | 1043/1276 |
| axi4.*.cg_aw | 266/306 | 1002/1224 | 750/918 | 974/1198 | 238/280 | 525/638 | 507/612 | 1057/1276 |
| axi4.*.cg_b | 6/8 | 24/32 | 18/24 | 8/32 | 2/8 | 12/16 | 12/16 | 24/32 |
| axi4.*.cg_bp | 17/24 | 67/96 | 49/72 | 60/96 | 17/24 | 30/48 | 34/48 | 67/96 |
| axi4.*.cg_cmd | 4/4 | 16/16 | 12/12 | 16/16 | 4/4 | 8/8 | 8/8 | 16/16 |
| axi4.*.cg_os | 13/20 | 48/80 | 36/60 | 48/80 | 13/20 | 24/40 | 24/40 | 49/80 |
| axi4.*.cg_r | 10/12 | 40/48 | 30/36 | 24/48 | 6/12 | 20/24 | 20/24 | 40/48 |
| axi4.*.cg_w | 16/16 | 64/64 | 48/48 | 64/64 | 16/16 | 32/32 | 32/32 | 64/64 |
| l1.cg_fdi_cancel | 6/11 | 6/11 | 6/11 | 6/11 | 6/11 | 6/11 | 6/11 | 6/11 |
| l1.cg_fdi_stall | 7/17 | 7/17 | 7/17 | 7/17 | 7/17 | 9/17 | 9/17 | 11/17 |
| l1.cg_fdi_xfer | 24/26 | 24/26 | 24/26 | 23/26 | 24/26 | 25/26 | 25/26 | 26/26 |
| l2.cg_bringup_fsm | 17/22 | 17/22 | 17/22 | 17/22 | 17/22 | 17/22 | 17/22 | 17/22 |
| l2.cg_link_state | 31/80 | 31/80 | 31/80 | 31/80 | 31/80 | 31/80 | 31/80 | **31/80 (39%)** |
| l3.cg_act_fsm | 4/8 | 4/8 | 4/8 | 4/8 | 4/8 | 4/8 | 4/8 | 4/8 |
| l3.cg_act_op | 15/29 | 15/29 | 15/29 | 17/29 | 15/29 | 15/29 | 15/29 | 17/29 |
| l3.cg_credit | 49/84 | 49/84 | 49/84 | 49/84 | 49/84 | 54/84 | 49/84 | 54/84 |
| l3.cg_flit_layout | 439/562 | 447/562 | 449/562 | 508/562 | 381/562 | 479/562 | 464/562 | 508/562 |
| l3.cg_flit_occ | 28/30 | 28/30 | 28/30 | 28/30 | 28/30 | 28/30 | 28/30 | 28/30 |
| l3.cg_msg | 43/132 | 101/132 | 83/132 | 94/132 | 36/132 | 64/132 | 63/132 | 113/132 |
| **TOTAL** | 1405/2108 66.7% | 3119/4196 74.3% | 2543/3500 72.7% | 3100/4144 74.8% | 1257/2056 61.1% | 2062/2856 72.2% | 1991/2804 71.0% | **3337/4300 77.60%** |

Notes on the FC numbers:
- The axi4 groups sum over the 2, 6 or 8 AXI4 interfaces each config has.
- d04b2da all-configs was 3334/4271 (78.06%). The 29 new bins are the link-down/Disabled bins and
  `cp_fdi_enc`. Of those, only `cp_fdi_enc rtl` is hit.
- The `spec` bin needs a passing SPEC-encoded run, possible since PR #108 made the DUT use the UCIe encodings.

**Of the 963 holes in the union:**

| Kind | Holes | What they are |
|---|---|---|
| cg-bug | about 290 | AXI-illegal cross cells, never-sampled bins, Misc × RP, requests the DUT can't drive |
| v0.8 | 56 | ERROR state, 4-granule ActivateReq, half-flit Misc limit |
| a | about 560 | Mostly AXI cx_size_x_len and burst-type cells, then attributes, FDI events and credit corners |
| b | about 30 | Behind open bugs |
| c | 8 | Config-dependent |

The details are in §3. Correcting the cg-bug bins alone takes the union from 77.6% to about **83%**
with no new run.

### 1.4 Test plan (316 counted items)

| Status | Items | Earlier report (d04b2da) |
|---|---|---|
| covered | **259** | 260 |
| xfail-only | **16** | 12 |
| failing | **0** | 3 |
| blocked | **1** | 1 |
| not covered | **40** | 40 |

- **Bench bug.** The published `scripts/plan_status.py` doesn't ignore `+aou_fc_json=…`, which
  every COV=1 run adds. So `make plan_status` on a coverage regression reports **0 covered**. The
  numbers above come from a copy of the script that ignores the plusarg. The
  fix is in WP1.
- **xfail-only (16):**
  - 1.3, 1.8, 1.9 (BUGS/019/013/020/023)
  - 2.7 (forced deactivation; the test was reworked to accept the forced DeactivateReq)
  - 9.5 (a remote RX credit overrun: illegal peer stimulus, test since removed)
  - 9.9, 9.10, 19.8 (a response that answers no request: illegal stimulus, detection-only checks since PR #117)
  - 12.13 (an asymmetric DEST_RP: illegal configuration, test since removed)
  - 14.5 (tenstorrent/tt-oca-harness-aou#90)
  - 20.4, 20.10, 20.12, 20.13, 20.15, 20.16 (reg bench: AXI_SPLIT_TR_EN; the reserved enable bit and AOU_SW_RESET were fixed by PR #118 and PR #113)
- **blocked (1):** 9.8.
- **not covered (40), all "no run-list entry":**
  - Activation, deactivation and credits: 1.4, 2.5, 2.10, 3.15, 3.19, 3.20
  - Burst types, responses and attributes: 4.16, 4.17, 4.23–4.28, 5.21–5.26
  - Outstanding and ordering: 8.3, 8.6, 8.14
  - Splitter: 15.11, 15.13, 15.16, 15.17
  - Early response: 16.11, 16.12, 16.14, 16.15
  - Aggregator: 17.3, 17.13
  - FDI configs and RX FDI: 18.1, 18.3, 18.4, 18.5, 18.11, 18.12
  - Integration: 22.5

---

## 2. Code-coverage holes

The per-module numbers below are **uncovered line/cond/branch/FSM** from the fresh cov3 report.
They match the d04b2da analysis to within a few items, so that analysis carries over.

### 2.1 Four causes explain most of the gap

1. **Run-list config pins (class c, cheap).**
   - What's pinned: `run_list.py` skips entries whose `target` is another target. Every
     `datapath.toml` entry is pinned to 1x512-sp64, and so are the split, aggregator,
     early-bresp, qos, lp_mode and dest_rp entries in `features.toml`.
   - Effect: AGGREGATOR, AGGREGATOR_INFO, EARLY_TABLE, SPLIT_TR and the aggregator's
     SYNC_FIFO_REG are 30-117 lines, 40-366 cond and 21-120 branches worse in every other
     config. Their FSM is 0/4.
   - Gap left in the union: the 1024-bit and 256-bit aggregators run nowhere.
2. **XFAIL'd tests carry the error paths (class b).** The table in §1.1 lists them. Most have a
   bug-avoiding variant (§2.4, WP3).
3. **Dead code from constant parameters and tie-offs (class d).** This covers:
   - the whole upsizer branch gap;
   - the single-PHY halves of the two-PHY muxes;
   - `PHY_TYPE`/DLENGTH/RP_COUNT arms inside `always` blocks;
   - the SFR `PREADY=1` tie-off;
   - FSM `default` arms.
4. **Narrow FDI stimulus (class a).**
   - The LSM driver enters LinkError only from Active.
   - L1 exit is always initiated by the PL.
   - `I_SW_RETRAIN_REQ` is never driven.
   - The linkerror and linkdown spec tests XFAILed on the FDI bring-up findings PR #108 fixed.

### 2.2 Ranked modules (uncovered line/cond/branch/FSM per config, cov3)

| Module | 1x512 | 4x512 | 3x512 | 4xmix | 1x256 | 2xmix-tp | 2x512-tp | union | Main class / action |
|---|---|---|---|---|---|---|---|---|---|
| AOU_AGGREGATOR | 5/17/6/1 | 39/120/40/4 | 39/120/40/4 | 117/366/120/4 | 40/122/40/4 | 77/244/80/4 | 39/120/40/4 | 6/29/44/1 | c: unpin `aou_aggregator_test` (WP1); HALT→IDLE is reset-only (§2.3) |
| AOU_CORE_SFR | 66/177/80 | 27/99/35 | 49/141/62 | 47/144/59 | 71/188/86 | 59/161/73 | 59/161/73 | 27/99/35 | b: reg bench XFAILs on AXI_SPLIT_TR_EN (the other two register findings are fixed) → skip-known-bugs variant (WP3); a: error-info regs → `+detect_only` (WP3); e: constant RO bits |
| AOU_AGGREGATOR_INFO | 0/4/0 | 34/40/21 | 34/40/21 | 102/130/63 | 32/45/19 | 70/85/44 | 34/40/21 | 24/4/24 | c: as AGGREGATOR |
| AOU_TX_CRD_CTRL | 35/37/26 | 35/2/26 | 45/7/30 | 80/2/44 | 36/37/26 | 50/22/32 | 50/22/32 | 30/2/24 | a/e: 20 lines saturate the received credit at `RP*_MAX_CREDIT`=2048 (L476-548), so an L3 over-grant past 2048 is needed; check reachability first. c: `I_RP_DEST_RP` arms (L572-610) → full DEST_RP permutation on the multi-RP configs |
| AOU_ERROR_INFO | 4/15/3 | 4/14/3 | 4/14/3 | 28/55/25 | 28/55/25 | 4/14/3 | 4/14/3 | 4/14/3 | b: on 4xmix and 1x256 the debug FIFO path was empty while the window could not answer a width-converted read (fixed) → rerun `err_resp` there. a: B+R error in one cycle with one slot left |
| AOU_RX_CORE | 14/11/14 | 14/19/14 | 14/19/14 | 23/57/21 | 25/6/17 | 23/25/21 | 14/7/14 | 13/46/35 | d per config: `PHY_TYPE` arms in `always_comb` (L750-809). a: write-data mask continuation across chunks (L344-387, crossflit layouts); 7+ WriteResp per chunk (cond L1163, `+pk=wresp48` on more configs) |
| AOU_AXI4MUX_3X1_TOP / _256 | 0/0/0 | 0/4/0 | 0/4/0 | 0/94+64/24 | 6/45+64/25 | 0/49/0 | 0/4/0 | 0/9/0 | a: CH2 (1024-bit remote slot) on 256-bit RPs was reached only by tenstorrent/tt-oca-harness-aou#90 runs; #90 is fixed (PR #89), so a rerun of `aou_dw_test` covers it |
| AOU_ACTIVATION_CTRL | 16/51/17/1 | 16/53/17/1 | 16/51/17/1 | 11/42/12/1 | 11/49/12/1 | 13/47/14/1 | 15/48/16/1 | 9/38/10/1 | b: ACTIVATE→DISABLED and invalid-op lines (019/013/023) → check-then-hard-reset variant. a: `DEACTIVATE_TIME_OUT_VALUE` 2,4-7; remote DeactivateReq with PropertyReq=1; ACTMSG_READY back-pressure |
| AOU_SYNC_FIFO_REG | 0/24/0 | 15/63/0 | … | 15/63/0 | 15/63/0 | 15/63/0 | 15/63/0 | 0/0/0 | c: aggregator W FIFO, as AGGREGATOR |
| AOU_SLV_AXI_INFO | 9/44/4 | 0/10/0 | 5/12/3 | 4/8/2 | 16/52/8 | 5/19/3 | 5/14/3 | 0/7/0 | a: reads with `slv_id_mismatch_en=1` on every config; a: `aou_id_mismatch_test +kind=r` for the R-mismatch path |
| AOU_AXI_DOWN | 0/4/0 | 0/10/0 | 0/4/0 | 0/63/13 | 0/59/13 | 0/5/0 | 0/4/0 | 0/26/8 | a: dn_1024_256 empty (tenstorrent/tt-oca-harness-aou#90, fixed by PR #89) → rerun; a: AW FIFO full and AR table full (deep outstanding) |
| AOU_RX_CRD_CTRL | 13/31/25 | 2/1/0 | 1/6/5 | 1/1/0 | 15/31/25 | 6/16/15 | 7/16/15 | 0/1/0 | c/d per config: multi-RP MsgCredit select is unreachable with 1 RP; the union covers it |
| AOU_EARLY_TABLE | 1/8/1 | 19/35/9 | 19/35/9 | 19/35/9 | 19/35/9 | 19/35/9 | 19/35/9 | 1/8/1 | c: unpin `aou_early_bresp_test`. a: same-ID back-to-back bufferable (L151) |
| AOU_FDI_BRINGUP_CTRL | 17/9/17/**18** | same | same | same | same | same | same | same | a: §2.3 (14 functional transitions), 4 reset-only |
| AOU_AXI_SPLIT_TR / ADDRGEN | 6/13/6, 4/-/4 | | | 7/23/13 | 10/26/16 | | | 4/12/4, 2/-/2 | a: MAX_ARBURSTLEN 0/3 and MAX_AWBURSTLEN 0/1/31 never programmed; c: size 7 only on 1024-bit RPs; d: ADDRGEN `default` |
| AOU_CORE_RP | 6/15/3 | 6/8/3 | 6/9/3 | 4/9/2 | 6/33/3 | 6/9/3 | 6/9/3 | 4/8/2 | a: RID-mismatch mux (`aou_id_mismatch_test`); a: 1024-wide B/R with ready low |
| AOU_AXIMUX_1XN_SS | 0/11/0 | 0/12/0 | 0/12/0 | 0/41/0 | 0/41/0 | 0/12/0 | 0/12/0 | 0/11/0 | a: `*_sel_err_info` (`aou_id_mismatch_test`); a: back-pressure |
| AOU_DATA_R/W_FIFO_NS1M_TPSRAM | 8/12/3 | 8/12/3 | 8/12/3 | 0/2/0 | 16/16/6 | 0/8/0 | 8/12/3 | 0/2/0 | a: multi-request decode chunks (back-to-back 256-bit read data, `+pk=full`) |
| AOU_4X1_RR_ARBITER / 3X1_RR | 4/-/5 | 0/-/1 | 4/-/5 | 0/-/1 | 14/-/12 | 4/-/5 | 4/-/5 | 0/-/1 | c: absent requesters with fewer RPs; a: 3X1_RR needs three remote widths contending on one RP |
| AOU_AXI_UP | 0/1/6 | 0/1/6 | 0/1/6 | 4/0/15 | n/a | 4/0/15 | 0/1/6 | 2/0/14 | d: §2.5 (every branch hole is dead); a: three cond (back-pressure) |
| AOU_TX_AXI_BUFFER / TX_CORE / TX_FDI_IF | 4/4/3, 0/9/0, 0/6/0 | | | 0/17/4 | 6/12/4, 4/12/2 | | | 0/18/0, 0/15/0 | c/d: DLENGTH arms dead for the build's widths. a: TX_LP_MODE with an activation in flight (illegal stimulus: LP mode is static configuration, programmed only while DISABLED; accepted exclusion); TX_FDI_IF `trdy` outside Active (R20-02 makes it legal only during a LinkError stall) and stall-release ordering (R20-03) |

**Toggle.** Most of the 212k uncovered union bits are in wide datapath registers:
- `AOU_FWD_RS` and `AOU_FIFO_RP` (about 26k each in 1x512);
- `AOU_AXI_DOWN_RDATA_ORDER` (26k; 93k in 4xmix);
- `TX_AXI_BUFFER`, `SYNC_FIFO_NS1M_SREADY`, `TX_CORE`;
- the split and aggregator pending tables.

The untoggled bits come in structured ranges: header fields a build never produces, high ID or
address bits, deep entries. Before writing any toggle stimulus, a **toggle triage script** (WP7)
should map the untoggled ranges onto `packet_def_pkg` fields. That splits them into structural
(d/e) and data-pattern (a: `+dp_ids=high`, full 64-bit addresses with split/agg/early on, deep
outstanding, non-OKAY responses through the downsizer). More than half are expected to be
structural.

### 2.3 FSM: 34/58. Every unvisited transition and how to reach it

There are five FSMs in the database. Every state is visited, and URG scores transitions only.
The 24 holes split as follows:
- **14 need stimulus**;
- **1 is behind BUGS/019**;
- **9 are reachable only through an asynchronous reset mid-state**.

**AOU_FDI_BRINGUP_CTRL `r_cur_st`: 17/35** (`RTL/AOU_FDI_BRINGUP_CTRL.sv:155-330`, 12 one-hot states)

| Uncovered transition | How to reach | Class |
|---|---|---|
| RESET→LINKERROR | `pl_state_sts`=LinkError while the DUT sits in RESET (`auto_bringup=0`, or during link-down) | a |
| WAIT_PRESENCE→LINKERROR | LinkError after `inband_pres`=1, before `clk_req`/wake | a |
| WAKE_ASSERT→LINKERROR | 1-cycle state: LinkError exactly 1 cycle after `pl_clk_req` | a, cycle-exact |
| WAKE_WAIT_ACK→LINKERROR | delay `pl_wake_ack` (new `+wake_ack_delay`), then LinkError | a |
| WAKE_WAIT_ACK→RESET | inband drop plus Reset during the wake handshake | a |
| REQ_ACTIVE→LINKERROR | LinkError after the Active request, before Active entry | a |
| REQ_ACTIVE→RESET | inband drop plus Reset before Active entry | a |
| RETRAIN→LINKERROR | LinkError during the Retrain dwell (`+event=retrain_linkerror`) | a |
| DEACTIVATE→LINKERROR | 1-cycle state: `I_SW_DEACTIVATE_START`, then LinkError 1 cycle later | a, cycle-exact |
| UNWAKE_WAIT→LINKERROR | LinkError after `lp_wake_req` drops, before PL Reset | a |
| L1→WAKE_ASSERT | **LP-initiated L1 exit** (`I_SW_ACTIVATE_START` in L1 without `pl_clk_req`). Needs an L2 responder for an LP wake from L1 | a, bench change |
| L1→LINKERROR | LinkError in L1 | a |
| L1→RESET | LinkReset or Reset while in L1 | a |
| L1_CLK_WAKE→LINKERROR | 1-cycle state: LinkError 1 cycle after `pl_clk_req` in L1 | a, cycle-exact |
| RETRAIN→RESET, WAKE_ASSERT→RESET, DEACTIVATE→RESET, L1_CLK_WAKE→RESET | `I_RESETN` only, mid-state (the last three are 1-cycle states) | reset-only, see decision D4 |

Other holes in the same module:
- **cond L241:** `I_SW_RETRAIN_REQ` is never driven. One `pulse_sw(LSM_SW_RETRAIN)` covers it.
- **cond L134 and L135:** SW deactivate and SW linkerror inject. They are driven only by the spec
  tests, which XFAIL.
- **cond L228:** `pl_active && !rx_active_req` would need a non-compliant adapter. Class d/e.
- **Lines 328, 350, 470:** one-hot `default` arms. Class d.

**Proposal:** a new `aou_fdi_t1_bringup_corner_test`, quiet (no traffic), that walks a table of (DUT state, injected event, offset). It needs three LSM
extensions: event-at-state injection, `wake_ack` delay, and LP-initiated L1 exit. Expected yield:
bringup FSM 17→31/35 and **global FSM 34→48/58**.

**AOU_ACTIVATION_CTRL: 5/6.** ACTIVATE→DISABLED is missing. It is class **b** (BUGS/019).
- Variant: `aou_invalid_actmsg_test +state=activate +op=deact_req`, ending right after the
  LinkReset interrupt and `activate_state_disabled` are checked, then `hard_reset()` instead of
  re-activating. BUGS/019 and 020 only show after the LinkReset.
- An ActivateAck timeout run built the same way also reaches it.

**AOU_AGGREGATOR: 3/4 on 1x512, 0/4 elsewhere.**
- Elsewhere: class **c**; unpin the test.
- HALT→IDLE: async reset only, with a narrow aggregated burst half-collected. It needs
  `aou_reset_test +reset=core +when=traffic` with `agg_en=1` and W stalls, or a reset filter.

**ASYNC_APB_BRIDGE_SI: 5/7, and MI: 4/6.** Every hole (SETUP/ACCESS→IDLE) is reset-only.
- SI: `I_PRESETN` during an APB access waiting for the CDC round trip. That's easy:
  `aou_reset_test +reset=apb +when=apb_access`.
- MI: SETUP and ACCESS last 1 cycle each because `AOU_CORE_SFR.v:1355` ties `O_PREADY=1`.
  Reaching them needs cycle-exact `I_RESETN` or the filter.
- Also worth an assertion: after an MI-side reset, SI's request is still pending, so the access
  replays into freshly reset SFRs. The integration guide (3.1.1) now requires the bridge to be idle
  before either reset, so this is outside legal use.

**FSM outlook:**

| Packages | Reset-caused transitions | FSM |
|---|---|---|
| WP5 (bringup corner) + WP3 (activation variant) | tested | 49/58 |
| + WP6, 9 reset-in-state scenarios (5 cycle-exact) | tested | **58/58** |
| + WP6 with `-cm_fsmresetfilter` | filtered | **49/49** |

The filter option name still needs confirming on X-2025.06. The choice is decision D4.

### 2.4 Bug-blocked code and the variants available now

| Bug | Code held back | Variant now? |
|---|---|---|
| Register model: AXI_SPLIT_TR_EN (the reserved enable bit and AOU_SW_RESET were fixed by PR #118 and PR #113) | SFR: ~35 lines, ~80 cond, ~45 branches, ~1.5k toggle bits per config | **Yes.** `+reg_skip_known_bugs`: `NO_CHECK`/`NO_REG_BIT_BASH_TEST` on `aou_con0.axi_split_tr_en`, run as extra PASS entries. Keep the strict XFAIL entries. |
| Activation messages out of step (BUGS/019, 013) | ACTIVATION FSM 1, ~10 lines, ~15 cond | **Yes:** check, then hard reset. |
| A response that answers no request | SFR error-info set/info registers (24 lines), CORE_RP and AXIMUX mismatch muxes, SLV_AXI_INFO R path | **Done.** The stimulus is illegal AXI and MAS 7.2.2 defines only the detection, so the test checks the detection and, where the DUT holds the stray response, ends with a hard reset (`+detect_only=1`, decision D8). |
| 1024-to-256-bit downsizer (tenstorrent/tt-oca-harness-aou#90, fixed by PR #89) | dn_1024_256, its RDATA_ORDER, AXI4MUX_3X1_256 CH2: ~6 lines, ~120 cond, ~37 branches and ~60k toggle bits per config | **Not needed now.** The aligned `aou_dw_test +remote_bytes=128 +dp_align=aligned` entries on `4xmix4211-sp128` (RP2/RP3) and `4xmix2144-sp64` (RP1) were added as the variant (WP10); with the fix every `aou_dw_test` run counts. |
| Debug window through a narrow RP (fixed by PR #111) | ERROR_INFO debug FIFO on 4xmix and 1x256 | **Not needed now:** `err_resp` passes there. |
| AOU_SW_RESET during traffic (fixed by PR #113) | LinkReset, LinkError and inband drop in `link_event` with traffic | **Not needed now:** the `link_event` and `reset` families pass with traffic. |
| FDI bring-up (fixed by PR #108) | linkerror and linkdown spec tests (bringup linkdown bins, SW-inject conds) | **Not needed now.** The DUT follows the UCIe encodings, drives `lp_linkerror`, and software restarts the link after a link-down. The spec tests pass in both FDI encodings. |
| Small items | | A remote RX credit overrun and an asymmetric DEST_RP are illegal stimulus (tests removed). DEACTIVATE_FORCE's PropertyReq is an owner question. LP mode is static configuration (PR #105/#106); the tests program it only while DISABLED. |

The rerun gains when fixes land are in §6, WP13.

### 2.5 Converters

**Upsizer `AOU_AXI_UP`.** The branch figure is 65-71% (14/21 for 256→512 and 256→1024, 15/23
for 512→1024).
- **Every missing branch is dead code (d):**
  - `if (SUPPORT_AWSIZE_n)` is a constant-true localparam (`AOU_AXI_UP.v:153-160`), so its
    `else` can never run.
  - The `default` size arm needs a size larger than the bus, which is AXI-illegal (A3.4.1).
  - Excluding these gives every upsizer 100% branch.
- **Real holes:** cond L182 (`AWVALID && !AWREADY`), L384/385 (AW FIFO full) and L399/400 (AR
  slot unavailable). They need M-port back-pressure with a narrow remote:
  `aou_dp_random_test +dp_profile=stall +remote_bytes=32` on every config, and per-RP mixes on the
  mix configs.

**Downsizer `AOU_AXI_DOWN`.**
- **dn_1024_256** (4xmix4121 RP1/RP3 and 1x256): no transaction passed in cov3 (tenstorrent/tt-oca-harness-aou#90).
  #90 is fixed (PR #89), so this is class **a** now (§2.4).
- **dn_1024_512 and dn_512_256:** line and branch are complete. The only holes are AW FIFO full
  (depth 8) and AR reorder table full (32). Class **a**: `+dp_batch≥32` through the downsizer,
  with M-port W/R back-pressure.
- **RDATA_ORDER L143:** a second same-ID read while the first is pending (`+dp_ids=same`).

**Missing transfer shapes:**

| Shape | Bench today | Class |
|---|---|---|
| Narrow unaligned INCR through a converter | `dp_size`/`dp_unaligned` are pinned to 1x512 at equal width | c: unpin and set `+remote_bytes` different from the local width |
| Long bursts converted | `dp_burst` 31/63/255 is pinned to 1x512 | c |
| Deep outstanding | batch ≤ 16 | a |
| WRAP and FIXED | never generated, and the converters ignore AxBURST | **question first** (below) |

**WRAP/FIXED are a spec question, not just a coverage hole.**
- The AoU wire carries no AxBURST, so INCR is assumed (AoU §2.5; spec Table 31 lists BURST as
  INCR only).
- `AOU_AXI_UP.v:184-186`, `AOU_AXI_DOWN.v:219,264-267` and `AOU_AGGREGATOR.v:387` compute
  addresses as INCR.
- So a downsized 16-beat WRAP becomes a 64-beat "WRAP", which AXI forbids. The MAS is silent on
  whether WRAP and FIXED are accepted on the S port.
- Decision D1 settled it: INCR bursts only. WRAP and FIXED are out of scope and AXI-R19 flags
  them as a stimulus error (DECISIONS D5).

### 2.6 RX and TX cores

- **AOU_RX_CORE:**
  - The `PHY_TYPE` arms are dead per config and covered in the union (d per config).
  - Data-mask continuation across chunks needs specific crossflit layouts (a): `+pk=crossflit`
    with `+dp_size` mixes on several configs. This overlaps FC `cg_flit_layout` multi-flit.
  - 7+ WriteResp per chunk (a): `+pk=wresp48` beyond 4x512.
  - The RX FDI staging buffer and `r_phase` (plan 18.11/18.12) need a white-box FC group (§4.2).
- **AOU_TX_CORE / TX_AXI_BUFFER / TX_FDI_IF:**
  - DLENGTH byte-swap arms for widths the build doesn't have (c/d).
  - TX_LP_MODE switched while an activation message is in flight (a): illegal stimulus, LP
    mode is static configuration programmed only while DISABLED (T1-LP03); accepted exclusion.
  - TX_FDI_IF `pl_trdy` outside Active: r2.0 (R20-02) makes it legal only during a stall in
    LinkError, so there is a stimulus for it.
  - Stall-release ordering: R20-03 sequences A and B.
- **AOU_TX/RX_CRD_CTRL:** credit saturation at 2048 (a/e), DEST_RP permutations (c), and the
  multi-RP MsgCredit select (c).

### 2.7 Exclusion candidates (class d). None applied; each needs owner review.

| # | Scope | Items | Evidence | Mechanism |
|---|---|---|---|---|
| D1 | `AOU_AXI_UP` `else` of `if (SUPPORT_AWSIZE_n)` | 6-7 branches per variant | constant-true localparam, `AOU_AXI_UP.v:153-160` | `.el`, or `-cm_noconst` |
| D2 | `AOU_AXI_UP` `default` of `case(w_cur_awsize)` | 1 branch and 2 lines per variant | size larger than the bus is AXI-illegal | `.el` |
| D3 | FSM and decoder `default` arms | FDI L328/350/470, ACT L375, AGG L737, SI L118, ADDRGEN L54/71, AGGREGATOR L359/537 | fully decoded or one-hot | `.el` |
| D4 | ASYNC_APB_BRIDGE_MI L108 (ACCESS wait), `PREADY`/`PSLVERR` toggles | about 1 line, 1 branch, 2 cond, 4 bits | `AOU_CORE_SFR.v:1355-1356` ties PREADY=1 and PSLVERR=0 | `.el`, or `-cm_noconst` |
| D5 | Single-PHY builds: `RX_CORE_IN_MUX`/`TX_CORE_OUT_MUX` `I_PHY_TYPE` true arms | 1x256: 9 cond, 8 branches, ~2k bits | `AOU_CORE.sv:1392` ties `I_PHY_TYPE=0` | only if per-config reports must close (decision D6) |
| D6 | `PHY_TYPE`/DLENGTH/RP_COUNT arms in `always` blocks | RX_CORE L750-809, TX_AXI_BUFFER L675-684 and L1071/1112, RX_CRD_CTRL L458 and L629-642, 4X1_RR L95-111 | dead for that build, live in another | as D5 |
| D7 | Reset-only FSM transitions | 9 | only `I_RESETN`/`I_PRESETN` reach them | `-cm_fsmresetfilter` or `.el` (decision D4) |
| D8 | FDI cond L228 | 1 | needs a UCIe-violating adapter | `.el`, or keep as a robustness target (e) |
| D9 | ADDRGEN L53/70, AGGREGATOR L358 (size 7) in 256/512 builds | 2-3 per build | 128-B transfers are illegal on narrower buses | per-config `.el` |

D10 now allows reviewed line and branch items in `cov/config/vcs/cov_exclude.el` (`urg
-elfile`, applied by `make cov_report`) for dead code; its first entries are the six
`AOU_ACTIVATION_CTRL` time-out arms that #108's abort pre-empts. D1-D9 still need the owner's
review before they join it, or `-cm_noconst` (decision D5).

---

## 3. Functional-coverage holes per covergroup

The "cg-bug" rows are bin fixes for FC2. They are **not waivers**: each corrects a bin that
can't mean what it says. They are listed for owner review because the denominator changes.

### 3.1 FC2 covergroup bug fixes

| Group / point | Bug | Fix | Bins out / in |
|---|---|---|---|
| `axi.txn_cg x_txn` | The cross keeps AXI-illegal cells: WRAP with an unaligned address, WRAP of 1 beat or over 16 beats (A3.4.1), FIXED over 16 beats, `size[0]` unaligned (a 1-byte transfer is always aligned) | `ignore_bins` (and the same exclusion in the service table) | −142 |
| `axi4.*.cx_size_x_len` | Cells whose size × beats exceed 4 KB, which can't avoid crossing a 4 KB boundary (A3.4.1): bytes_7×{64,128,256}, bytes_6×{128,256}, bytes_5×256 | ignore per interface (it depends on MAX_SIZE_CODE) | −72 |
| `l2.cg_link_state x_sts_req` (and `cp_req`) | The full sts×req cross has 49 cells. The DUT drives only NOP, Active, L1 and Retrain (`AOU_FDI_BRINGUP_CTRL.sv:338-350`): it never requests LinkReset, Disabled or reserved values. Many pairs are "ignored" per r1.1 Table 8-3  and never occur. | Replace with explicit bins: the requests Table 8-3 marks as considered, limited to what the DUT can drive. That is reset×{nop,active}, active×{active,l1,retrain}, l1×{l1,active}, retrain×{retrain,active}, linkerror×{nop,active}, linkreset×{nop,active}, disabled×{nop,active}, about 15 bins. `cp_req reserved`/`linkreset`/`disabled` become illegal_bins (a checker, FDI-R rule). | −24 / about +0 |
| `l2.cg_link_state cp_tr l1_active` | L1 exits through Retrain (r1.1 §8.3.3, the PM exit path L1→Retrain→Active); a direct L1→Active isn't an FDI transition | remove; `l1_retrain` + `retrain_active` already cover the exit | −1 |
| `l3.cg_act_fsm` | Samples the model's FSM. It has v0.8 ERROR bins but no v0.7 LinkReset→DISABLED bins | add `activate_disabled_lr`, `enabled_disabled_lr`, `deactivate_disabled_lr` (the model returns to DISABLED on link loss / LinkReset). Tag the four `*_error` bins v0.8 (§3.3) | +3 |
| `l3.cg_act_op x_op_dir_legal` | `reserved,*,legal` can't happen. `*,rx,illegal` = the DUT sending an illegal op, which is a checker hit (AOU-R40) and can't occur in a PASS run. `*,tx,illegal` are never sampled because injection bypasses `link_ctrl` (that is why 1.5 is "covered" with empty illegal bins). | drop `reserved,*,legal` and `*,rx,illegal`; sample `tx,illegal` (op and reserved) from the L3 inject path | −7 |
| `l3.cg_credit x_ev_cls_dir` | `saturate`/`overflow` are sampled only in RX (the DUT over-granting or over-running the model, which are DUT bugs). TX `saturate`/`overflow` and RX `zero_stall` are never sampled. The group describes the model, not the DUT (gaps B-a). | Re-home: keep `zero_stall,tx` (the model waits on DUT credit). Add DUT-side events: `dut_zero_stall` (the DUT holds a message the model hasn't credited), `dut_saturate` (the DUT absorbs a model over-grant, `+overgrant`), `inj_overflow,tx` (negative test: the model sends without credit; AoU v0.8 §6.1 binds only the sender, so the DUT's reaction is undefined). Make RX overflow an illegal_bin (AOU-R16 already checks it). | −27 / +15 |
| `l3.cg_msg x_kind_rp_dir` | Activation and CrdtGrant are Misc messages with no RP field (AoU Table 15/27; CrdtGrant carries every RP). `act,rp[1],tx` is hit today, which means the sample reads a non-wire field. | restrict `act`/`crdt` to one RP-less bin per direction | −12 (one hit removed) |
| `l3.cg_flit_layout x_size_span g1,multi_flit` | A 1-granule message can't span | ignore | −1 |
| `xfer.chan_cg cp_event w_taken_before_aw` | The DUT never takes W data before the burst's AW: `AOU_EARLY_BRESP_CTRL_AWCACHE` holds `WREADY` until the AW is accepted with early response on (table gating) and, since PR #89, off as well (`w_write_aw_credit`; MAS 3.7.5). `w_before_aw` still records the manager presenting W first (plan 4.31). | ignore | −1 |
| `l1.cg_fdi_xfer cp_width b32` | none. Keep it unless R20-19 drops 32 B (decision D7) | — | 0 |

**Net effect:**
- **About 286 bins out and 18 in.** The union goes from 3337/4300 (77.6%) to about 3336/4032
  (**82.7%**) with no new run.
- The `axi.txn_cg` FIXED/WRAP legal cells (106) stay until decision D1.

### 3.2 Real holes per covergroup (after the FC2 fixes)

| Group | Holes | Class and action |
|---|---|---|
| **axi.txn_cg** | `cp_burst wrap`. Legal FIXED cells (74; `fixed` is hit only for a few size/len cells, by some directed run) and legal WRAP cells (32). INCR: 120/120 | **a, after decision D1.** `aou_t1_traffic_cfg` hard-codes `fixed_pct=wrap_pct=lock_pct=0` with no plusarg (`env/aou_t1_traffic_cfg.svh:14-16`), so no T1 test can generate them. Add `+fixed_pct/+wrap_pct/+lock_pct` (or `+dp_burst=wrap|fixed`). Alternatively, if D1 rules them out-of-spec, drop `burst` from the cross (−107). |
| **axi4.*.cx_size_x_len** (legal) | 197 on axi_rx (M port), 91 on axi_tx (S port) | **a.** S port: `max_len` is 63 in rand traffic, so add `+max_len=255` and narrow sizes. M port: the splitter clamps to `MAX_AxBURSTLEN` (reset 0xF), so long M-port bursts need `MAX_AWBURSTLEN/ARBURSTLEN=255` programmed, plus long remote bursts. Downsizing multiplies beats (beat_64+ via 1024→256). |
| **axi4.*.cp_*_lock exclusive, cp_b/r_resp exokay** | 32 (8 interfaces × 4) | **a.** The Basic Profile carries AxLOCK (AoU spec §9, Table 31: Exclusive_Accesses true). Add `+lock_pct`, and have the remote memory model return EXOKAY for a matching exclusive pair. Plan items 4.25/5.23. |
| **axi4.*.cp_*_len beat_32..256** (M port), `cp_*_id id_mid/high/max` (rp1-3), `cp_*_addr_range low` (rp1-3) | ~70 | **a:** program MAX_AxBURSTLEN; `max_id`=1023 (it is 7 today); the address base for rp≥1 is `base + rp*stride`, so it never falls in "low". Add a low window per RP. |
| **axi4.*.cg_os / cg_bp** (`os_mid/hi/max`, `*_stall_at_max_os`, `stall_len cyc_gt_1k`) | ~56 | **a:** deep outstanding (`+dp_batch=64 +dp_wr_pct=100`, small remote credit) and long back-pressure at max outstanding. Plan 8.3/8.6, 16.11. Also check that `MAX_OUTSTANDING` in the FC module matches `S_WR_MO_CNT`=32. |
| **l1.cg_fdi_cancel** | `cp_half h1`, `cp_repeat second/more`, `x_half_kind h1,*` (5) | **a:** a flit cancel on the second 128 B half, and consecutive cancels (L1 driver knobs; `aou_t1_slice_test` only cancels the first half). r2.0 R20-04 adds a `nop` kind (§5). |
| **l1.cg_fdi_stall** | `cp_hold h1/h2_4`; `x_where_lat boundary×{l3,l4_6,l7_up}`, `mid_flit,l2` (6) | **a:** short stall holds and stallreq at a flit boundary with a slow ack. 2-PHY builds hit 2 more, so the latency depends on the FDI width. Add R20-03 `cp_seq` and R20-02 `cp_state` (§5). |
| **l2.cg_bringup_fsm** | `retrain_linkerr`, `l1_wake` (a); `active_linkdown`, `deact_linkdown`, `linkdown_unwake` (b) | `retrain_linkerr` and `l1_wake`: WP5 (LP-initiated L1 exit). The linkdown bins are the **bench model's** expected link-down path, so they are **b**: the linkdown and linkerror spec tests XFAILed until PR #108 fixed the DUT's link-down handling, so they close with passing runs on a bench that has it. |
| **l2.cg_link_state cp_tr** | `retrain_linkerror`, `active_linkreset`, `linkreset_reset`, `active_disabled`, `disabled_reset`, `reset_linkerror`; `cp_sts linkreset/disabled` | **a/b.** Adapter-driven transitions. `link_event +event=link_reset/inband_drop` used to XFAIL on the since-retired SW-reset sightings because of traffic and SW reset. A **quiet** link-event variant closes them now. `reset_linkerror` and `retrain_linkerror` come with WP5. |
| **l3.cg_act_op** (after the fix) | `tx,illegal` × op0-3 and reserved (5) | **a:** sample the inject path. `aou_invalid_actmsg_test` covers every op×state, but those runs XFAIL on 019/013/023, so run the check-then-hard-reset variant (WP3). |
| **l3.cg_credit** (after the fix) | `zero_stall,tx` for wreq/rreq/wresp; the new DUT-side bins | **a:** the model must exhaust the DUT's credit (`aou_zero_credit_test +credit=...` exists for model→DUT; the model-stalled direction needs bursts of remote-initiated requests beyond the DUT's advertised RX depth). |
| **l3.cg_flit_layout** | `g[47],g2` and `g2,multi_flit` (CrdtGrant starting at G47 and spanning into G0; legal per AoU §4.4) | **a:** an L3 packer policy knob to place the initial CrdtGrant at G47. g4 cells are v0.8 (§3.3). |
| **l3.cg_flit_occ** | `x_nmsgs_dir dense,rx` (16+ messages in a DUT→model flit); `cp_misc_half1 over` | dense: **a**, a WriteResp-heavy burst with M-port B released at once (`+pk=wresp48` on more configs). `over` (3+ Misc in one half-flit): v0.8 forbids it (half-flit Misc limit), and v0.7 doesn't say. **Ask:** make it an illegal_bin under v0.8 and a target under v0.7? |
| **l3.cg_msg** (after the fix) | `w256/w1024/wf256/wf1024 rp2/3 rx`, `r1024 rp2/3 tx` (8) | **c.** No config gives RP2 or RP3 a 1024-bit local width, and w256 rp2 rx needs narrow writes on a 512-bit RP2 that the DUT sends as WriteData256. Options: (i) a new config such as `4xmix2-sp128` with RP2/RP3 at 1024, (ii) a per-RP waiver, (iii) per-RP width bins instead of rp × kind. Decision D6. **Done (WP10), option (i):** `4xmix4211-sp128` builds RP2 at 256 and `4xmix2144-sp64` builds RP2/RP3 at 1024. |

### 3.3 AoU v0.8 bins

| Bin | Why only v0.8 | How it could be hit |
|---|---|---|
| `cg_act_fsm activate_error/enabled_error/deactivate_error/error_disabled` (4) | ERROR state (v0.8 §8.3.3) | model under `spec_rev=V08` with an illegal op received |
| `cg_flit_layout cp_size g4` and every `g*,g4` start cell, `x_size_span g4,*` (51) | 4-granule ActivateReq with ProfileID/Rev/Opt (v0.8 Table 27/§5.6) | a v0.8 DUT, or a model that sends it |
| `cg_flit_occ cp_misc_half1 over` (1) | half-flit Misc limit (v0.8 §4.4) | negative test |
| **to add:** `l3.cg_flex cp_flex {zero, nonzero} × dir`, `cg_act_req_profile {basic, other}`, `cg_rdata_variant {matches_arsize, wider}`, `cg_deact_credit {credit_after_deact_req, after_deact_ack}` | FLEX = USER[15:0]; ActivateReq profile; ReadData-variant rule; DEACTIVATE credit rules | as above |

**Problem.** No T1 test sets `spec_rev=V08`, and there is no plusarg for it. A v0.8 model can't
interoperate with the v0.7 DUT, because ActivateReq sizes differ (4 granules against 1). So T1
can reach these bins only through negative or one-sided cases. Three ways to close them
(decision D3):

| Option | What it means |
|---|---|
| A | Run the L3 model against itself in `TB=l3_unit` (loopback) under v0.8, with FC enabled, and report it as a separate "model v0.8" section. It proves the bench, not the DUT. |
| B | Keep them as holes, reported separately, until the RTL moves to v0.8. |
| C | Waive them for v0.7 closure (the 100% target then excludes them). |

My recommendation is A plus B: report them separately, and close them for the DUT when the RTL
moves to v0.8.

---

## 4. Test-plan gap analysis

The full gap tables were kept with the review notes; this section summarises them.

### 4.1 Items with no test, a blocked test or XFAIL only (57)

**Add a plan ID only: a passing run already does the work (11).**
- 4.23, 4.24, 5.21, 5.22: `aou_axi_err_resp_test` already returns SLVERR/DECERR on every RP;
  AXI-S01/S03 check them.
- 18.1 (1x256-sp32), 18.3 (4xmix4211-sp128), 18.4 (2x512-tp32_64, now run), 18.5 (2xmix-tp64_128):
  name them on those configs' entries.
- 18.11 and 18.12: `aou_t1_slice_test` (they also need a white-box FC bin, §4.2).
- 14.5 (xfail-only): tagged on `aou_dw_test +remote_bytes=128,64,128,64` on 4xmix4121-sp128, but
  that list gave 1024-bit remote data only to RP0 (1024-bit) and RP2 (512-bit), never to a
  256-bit RP. WP10 moves 14.5 to the tenstorrent/tt-oca-harness-aou#90-avoiding `+remote_bytes=128 +dp_align=aligned`
  entries on the 4xmix builds.
- Also add 20.10, 20.12 and 20.13 to passing T1 tests: `linkreset_timeout`, `err_resp`, and
  `id_mismatch +side=sub +kind=b`.

**Add a plan ID plus a new check (9).**

| Item | New check |
|---|---|
| 3.19 | rule AOU-R46: header MsgCredit RPs rotate round-robin (MAS 3.9) |
| 3.20 | the initial grant per class and RP equals the MAS 3.9 formula, from FIFO depth and width |
| 4.26-4.28, 5.24-5.26 | scoreboard rule AXI-S06: AxCACHE, PROT, QOS and LOCK arrive unchanged. Every value is already driven, and nothing checks it. |
| 8.14 | an R-interleave bin |

**Knob on an existing test (21).** `+lock_pct` and `+burst` belong to WP4.

| Items | Knob |
|---|---|
| 1.4 | `+act_prop=1`, or drop (see the drop list) |
| 2.5 | `+starve` in `link_act_deact` |
| 2.10 | `+remote_force=1` |
| 3.15 | `+credit_rp=<n>` |
| 4.16/4.17 | `+dp_burst=wrap/fixed`, after decision D1 |
| 4.25/5.23 | `+dp_lock` |
| 8.3/8.6 | `+dp_batch=64` |
| 15.11/15.13 | `+split_err` |
| 15.16 | per-RP `+split_aw` |
| 15.17 | split after downsizing on 1x256 |
| 16.11/16.12 | `+early_fill` |
| 16.14 | `+early_toggle` |
| 16.15 | per-RP `+early_en` |
| 17.3 | aggregator on 4xmix RP0 |
| 17.13 | per-RP `+agg_en` |

**Bug-avoiding variants possible now:**
- 14.5: yes, the aligned `aou_dw_test` entries (WP10).
- 20.4, 20.10, 20.12: yes, with the reg skip-known-bugs entry.
- 20.13, 20.15, 20.16: partly.
- 9.9, 9.10, 19.8: done, with the `+detect_only` entries (decision D8).

**Wait for a fix or a spec answer:**
- 1.3, 1.8, 1.9 (BUGS/019; fix verified on `bugfix/BUGS-019-activation-linkreset-hold`)

**Drop candidates (owner decision, via `test_plan_corrections.yaml`):**
- 9.8: the RTL has no RX incomplete-flit timeout, and FDI completes or cancels flits.
- 9.5: a remote RX credit overrun is a peer credit violation; AoU v0.8 §6.1 binds only the
  sender and leaves the receiver's reaction undefined.
- 22.5: the bench integrates only AOU_TOP.
- 1.4: PropertyReq on ActivateReq has no RTL effect and is gone in v0.8.
- 12.13: an asymmetric DEST_RP is a misconfiguration MAS 3.10.1 forbids.
- 2.7 and 2.10: only if the spec drops PropertyReq.

**Run-list cleanup:** remove the dropped ID 9.7 from the `aou_rx_msg_error_test` entry.

### 4.2 Covered items whose intent no FC bin evidences

Only flit packing (2.6), write/read (2.4/2.5) and bringup (2.22) are wholly evidenced by bins
today. The new groups below are white-box where allowed. Each new bin gets `plan_ids` filled in
`fc.json`, which is empty today, so plan_status can show the bins per item.

| Section | Proposed group (key coverpoints) |
|---|---|
| 2.1 Activation | `dut.cg_act` on AOU_ACTIVATION_CTRL `r_cur_st`: transitions including the error paths to DISABLED; `cp_initiator {sw_local, remote, both}` × `cp_order {local_first, remote_first, same_cycle}`; `cp_epoch {1,2,3+}` |
| 2.2 Deactivation | `dut.cg_deact`: `cp_cm {0,1}` × `cp_who` × `cp_pending {none,wr,rd,both}`; `cp_gate_wait` buckets; `cp_rsp_in_deact`. `dut.cg_lp_linkreset`: `cp_src {act_ack_tmo, deact_ack_tmo, msgcredit_tmo, invalid_actmsg}` × `cp_mask`, and `cp_invalid_op × cp_state` |
| 2.3 Credits | DUT-side credit bins (§3.1); `cp_enc {e0..e128} × cls × method` (WRESP limited to e0-e8); `cp_rr_step` for 3.19; `cp_partial_wait` |
| 2.8 Ordering | `axi4.cg_order`: `cp_b_reorder`, `cp_r_reorder`, `cp_same_id_depth`, `cp_r_interleaved` |
| 2.9 Errors | `l3.cg_rx_inject cp_kind` (10 malformed kinds); `dut.cg_id_mismatch` (side × kind × rp × mask × slv_en); `dut.cg_dbg_fifo` (occupancy at push, simultaneous B and R, drop, empty read) |
| 2.11 Resets | `tb.cg_reset`: `cp_kind {sw, core, apb, both, hard}` × `cp_when {idle, traffic, activating, queued, deactivating}`; `l3.cg_flex` |
| 2.12 Multi-RP | `dut.cg_dest_rp`: permutation id (24, and 3-RP subsets), identity, duplicate |
| 2.13 QoS | `dut.cg_qos`: `arb_mode {rr, port, axi, rsvd3}` × chan × contention pair; winner tier; promoted; timer resolution and threshold buckets |
| 2.14 Width conversion | `dut.cg_dw`: local × remote width × dir; up/down/bypass; beats out; WLAST regen; R replication |
| 2.15 Split | `dut.cg_split`: `max_len` (9 legal values) × nsub × dir; illegal write stored as 0xF; sub-burst error position |
| 2.16 Early response | `dut.cg_early`: en × buf × same-ID mix; error after early; table occupancy {0, 1-15, 16-31, full}; AW stall when full |
| 2.17 Aggregator | `dut.cg_agg`: en × dir × ratio × len_in × outcome × rp width |
| 2.18 FDI | `dut.cg_rx_fdi_if` (phase step, phase at cancel, staging valid); add `cp_fdi_cfg` and `cp_active_phy` to `l1.cg_fdi_xfer` |
| 2.19 Interrupts | `tb.cg_irq`: src × {raised, masked while pending, unmask raises, W1C cleared, W1C race}; concurrency |
| 2.20 Registers | reg bench: uvm_reg coverage (`UVM_CVR_ADDR_MAP`, `UVM_CVR_FIELD_VALS`) fed into the service as `reg.cg_access` and `reg.cg_field_kind` |
| 2.21 Low power | `dut.cg_lp`: lp_mode × threshold bucket × {heartbeat seen}; credit-only flit in LP; programmed in DISABLED × {before the first activation, between sessions}; traffic after each switch |

These map onto the earlier FC plan's Part A (A1-A9) and Part B (B1-B6). The cross-layer groups
X1-X4 (link event × activation state × outstanding; reset × state × mid-burst; zero credit × FDI
back-pressure; deactivation phase × message class) are still to be added.

### 4.3 Features with no plan item: 51 proposed

New IDs continue each section's numbering. 26 already have a test doing the work (they need only
the item and a `plan_ids` entry), 36 have a checker, and 11 have an FC bin.

| Area | New items (examples; full list in `gaps.md` §C) | Cites |
|---|---|---|
| Activation and deactivation (8) | 1.10 activation waits for the RX FIFO to drain; 1.11 ACTIVATE_START before FDI Active; 1.12 each INT_ACTIVATE_START source; 1.13 reserved ACTIVATIONOP received; 2.11 no credit in DISABLED or after DeactivateAck; 2.12 DEACTIVATE_TIME_OUT_VALUE sweep; 2.13 no DeactivateReq with own requests outstanding; 2.14 responses still sent in DEACTIVATE | AoU §8.2-8.4, Table 27; MAS 7.1, 7.3.2-7.3.5 |
| Credits (4) | 3.22 TX saturation on over-grant; 3.23 credit returned at dequeue only; 3.24 initial CrdtGrant covers every class and RP; 3.25 non-default RX FIFO depths and RS_EN=0 | AoU v0.7.1 §6.4, §6.4.3; MAS 3.4, 3.9 |
| AXI (2) | 4.30 FLEX/USER carriage; 4.31 W before AW | AoU §5.2; AXI4 A3.3.1 |
| Errors and debug (8) | 9.15 RP ≥ RP_COUNT received; 9.16 reserved MISCOP/DLENGTH/RsvdZero/stray MsgStart; 9.17-9.19 debug FIFO depth, disable and narrow-RP read; 9.20 M-port tables full; 9.21 ReadData wider than the remote; 9.22 subordinate ID-check enable | AoU Table 15, §4.4, §6.4.1; MAS 7.2.2, 7.2.4, §2.1 |
| Performance (2) | 10.14 numeric bounds; 10.15 back-pressure per channel | MAS PPA tables 8/9; AXI4 A3.2.1; UCIe r1.1 §8.2.4 |
| Reset, CDC, build (4) | 11.16 independent I_RESETN/I_PRESETN; 11.17 PCLK:CLK ratios; 11.18 an ASSERTION_ON build; 11.19 DFT scan mode (drop candidate) | integration guide 3.1.1, 8.7, 3.13.1 |
| RP, QoS, width, early (6) | 12.20 local and remote RP count differ; 13.19-13.22 reserved ARB_MODE, PRIOR=0, HP≤NP misconfiguration, timer extremes; 14.17 peer max width < 1024 (dropped: PR #96 fixed the width at 1024); 16.17 write kept waiting at the early-response limit (O_PENDING_CNT_OVER, removed by PR #89) | MAS 3.2.1, 3.7.5, 3.10.1; AoU §6.2 |
| UCIe FDI (14) | 18.13 Retrain with traffic; 18.14 LinkError; 18.15 L1 with the MAS PM sequence; 18.16 L2 (unsupported: drop or document); 18.17 LinkReset; 18.18 Disabled; 18.19 rx_active; 18.20 wake; 18.21 inband_pres drop; 18.22 stall corners; 18.23 state leaves Active mid-flit; 18.24 cancel corners; 18.25 two-PHY with PHY1 active (`+active_phy` exists, and no entry uses it); 18.26 flit-header fields | UCIe r1.1 §8.2.3-8.2.9, §8.3.2-8.3.3, Table 8-2; MAS 7.3.6, 7.3.7; BUGS/014 |
| Bringup (2) | 22.6 every AOU_FDI_BRINGUP_CTRL transition (this ties the FSM work to the plan); 22.7 restart after link-down needs NOP→Active | integration guide 6.6; UCIe r1.1 §8.3.3.8 |

The r2.0 items in §5 add four more if adopted: reset values (R20-01), NOP-flit discard (R20-04),
the LinkError hold (R20-09), and remote-initiated link-down (R20-11).

---

## 5. FC3: UCIe r1.1 → r2.0 FDI rule changes for this DUT's signals

**Method.** A word-level diff of r1.1 §8.2/8.3 against r2.0 §10.2/10.3. Citations give the
section only, in paraphrase.

**The DUT's FDI signals:**

| | Signals |
|---|---|
| **Has** | `pl_valid`/`data`/`flit_cancel`/`trdy`/`stallreq`/`state_sts`; `lp_data`/`valid`/`irdy`/`stallack`, per PHY; `pl_inband_pres`, `pl_clk_req`, `pl_wake_ack`, `pl_rx_active_req`; `lp_state_req`, `lp_wake_req`, `lp_clk_ack`, `lp_rx_active_sts`, `lp_linkerror` |
| **Lacks** | `pl_error`/`cerror`/`nferror`/`trainerror`, `pl_protocol*`, `pl_phyinrecenter`, `pl_phyinl1/l2`, stream IDs, DLLP, sideband, `dm_*` |

The DUT also ignores the flit header on RX.

| ID | r1.1 → r2.0 | Change (paraphrased) | Affects DUT? | Bench change | Rec. |
|---|---|---|---|---|---|
| R20-01 | (none) → §10.2.1 | Every FDI signal must come out of reset at 0 | **Yes**, every `lp_*` output (only stallack is checked today) | new FDI-R52 (DUT), and a MODEL copy for the drivers | **adopt** | public-ok
| R20-02 | Table 8-2 → Table 10-3 `pl_trdy` | `pl_trdy` only in Active, or during a stall in LinkError | partly: it makes a LinkError stall handshake legal | FDI-R53 (MODEL); `cg_fdi_stall cp_state {active, linkerror}` | **adopt** |
| R20-03 | §8.3.2 → §10.3.2 Impl. Note | Two acceptable lower-layer stall sequences (state change before or after the stallreq drop) | **yes** | L1 knob `stall_seq {A,B}`; `cg_fdi_stall cp_seq` × where/lat | **adopt** | public-ok
| R20-04 | Table 8-2 → Table 10-3 `pl_flit_cancel` | The Adapter may cancel NOP flits; the PL must **discard an uncancelled NOP flit** | **yes**: the DUT ignores the FH, so an all-zero flit is decoded as AoU content. **Likely new finding** | NOP-flit injection with and without cancel; FDI-R54 (no effect); `cg_fdi_cancel` `nop` kind; `cg_fdi_xfer cp_nop` | **adopt** |
| R20-05 | §8.2.3.1 → §10.2.3.1 | `lp_wake_req` before `lp_state_req` changes out of **any** clock-gated state (Reset, LinkReset, Disabled, PM) | yes (the DUT's request from LinkReset/Disabled) | re-cite FDI-R16 to r2.0; `cg_link_state cp_wake_from` | **adopt** | public-ok
| R20-06 | §8.2.7 → §10.2.7 | Typo fix: ≥1 clock between `pl_rx_active_req` rising and `lp_rx_active_sts` rising | already read this way | re-cite FDI-R26 | **adopt** (citation) | public-ok
| R20-07 | Table 8-2 → Table 10-3 | Once Active, `pl_inband_pres` drops only in LinkReset, Disabled or LinkError | model legality | FDI-R55 (MODEL); limit `aou_lsm_inband_drop_seq` | **adopt** |
| R20-08 | §8.2.9 → §10.2.9 | A PM response or PMNAK acts only from Active | no (the DUT never requests PM) | — | ignore | public-ok
| R20-09 | §8.3.3.7 → §10.3.3.7 | The lower layer may hold LinkError after an Active request | **yes**: the DUT must keep requesting Active | LSM `linkerror_hold`; FDI-R49 extended; `cg_link_state cp_le_exit {prompt, held}` | **adopt** | public-ok
| R20-10 | §8.3.3.8 → §10.3.3.8 | After LinkError/LinkReset/Disabled→Reset, training may restart on NOP→Active **or any Ch. 4 trigger** | partly: other agents can restart the link | re-cite FDI-R51; optional `restart_by` bin | answered: the owner assigned the restart to software | public-ok
| R20-11 | (none) → §10.3.3.8 Impl. Note | Streaming LinkReset/Disabled flow: exit = an Active request, then NOP→Active in Reset; the remote may go on to Reset or return to Disabled | **yes**: the spec basis for the link-down behaviour and FDI-R51. FDI-R50 stays an interim expectation | L2 scenarios (remote-initiated, local-only with RDI down, Adapter-autonomous → Reset); `cg_link_state cp_ld_origin` | **adopt** | public-ok
| R20-12 | (none) → §10.3.3.8 | L2 vs virtual-L2 exit | no (no L2) | — | ignore | public-ok
| R20-13 | §8.2.8 → §10.2.8 | Adapter sequence-number handshake and NOPs before local Active | no | — | ignore | public-ok
| R20-14..16 | Table 8-2 → Table 10-3 | `pl_error`/`cerror`/`nferror`/`trainerror` semantics | no (the signals are absent) | — | ignore |
| R20-17/18 | Table 8-2 → Table 10-3 | `pl_protocol` widened to 4 bits, `pl_lnk_cfg` x4, stream IDs with MT | no | — | ignore |
| R20-19 | §8.3.1 → §10.3.1 Impl. Note | FDI widths of 64/128/256/512 B strongly recommended in Flit mode | partly: SP_32B and TP_32B_64B are outside the recommendation | — | **ask**: keep the 32 B configs in closure scope? | public-ok
| R20-20 | §3 Tables 3-4/3-5 | FH Byte 1 [7:6] named "Flit Type" | no (the DUT sends 00b) | optional re-cite of FDI-R45 | ignore |
| R20-21 | sideband / management | atomic cfg access, credits, `dm_*` | no (out of scope, D5) | — | ignore |

**Totals:** adopt 9, ignore 10, ask 2.

**Unchanged in r2.0**, though a change was plausible:
- the `pl_state_sts`/`lp_state_req` encodings, the state machine, and the request table
  (Table 8-3 = 10-4);
- `lp_linkerror`, the clock request/ack rules, flit-cancel timing, the four-phase stall rules,
  Retrain, Reset and the Format 6 map.

So adopting r2.0 changed nothing for the FDI encoding and `lp_linkerror` findings (fixed by PR #108) or for the early `lp_linkerror` question (not a bug).

**Bench cost of the nine "adopt" rows:**
- four rules: FDI-R52 to R55;
- five re-cites;
- about 7 coverpoints (about 25 bins);
- L1/L2 knobs: NOP flit, stall sequence, LinkError hold, remote link-down.

They fold into WP5.

---

## 6. Work plan

The packages are ordered by yield over cost. The gains are estimates: union FC, and per-config
code coverage where it differs.

| # | Package | Scope | Expected gain | Depends on | Size | Decision | Status (upstream main `8ef393c`, 2026-10-19; WP3 and WP13 updated through PR #121) |
|---|---|---|---|---|---|---|---|
| **WP1** | **Bench hygiene and unpinning** | (1) `plan_status.py`: add `aou_fc_json=` to `INFRA_ARG`. (2) Unpin the `datapath.toml` and `features.toml` entries (aggregator, early_bresp, split, qos, lp_mode, dest_rp) so they run on every config, with per-RP `data_bytes` in the aggregator checker. (3) Add plan IDs for 4.23, 4.24, 5.21, 5.22, 14.5, 18.1, 18.3, 18.4, 18.5, 18.11, 18.12, 20.10, 20.12, 20.13 to existing passing entries, and drop 9.7 from the run list. (4) Triage the two new FAILs (4x512 `act_after_deact` AOU-R26; 4xmix `pack crossflit` AXI-R10) and match their signatures. | Plan: 259 → ~270 covered. Code per non-1x512 config: +34-117 lines, +120-366 cond, +40-120 branches (aggregator, agg_info, early_table, split, regfifo). FSM 31 → **34/58 on every config**. Union: the 1024- and 256-bit aggregators (~30 lines, ~35 cond, ~70 branches). | none | **S** | none | Done: `aou_fc_json=` is in `INFRA_ARG`, the data-path and feature entries run on every config, the plan IDs are on passing entries and 9.7 is gone. |
| **WP2** | **FC2 covergroup fixes** | Every row of §3.1: `x_txn` and `cx_size_x_len` AXI-illegal ignores; explicit `x_sts_req`; drop `l1_active`; v0.7 `cg_act_fsm` bins; `cg_act_op` inject sampling; re-homed `cg_credit` with DUT-side events; `cg_msg` Misc without RP; g1 multi_flit. Tag v0.8 bins (a `spec` field in `fc.json`). | Union FC **77.6% → ~82.7%** (−286 / +18 bins) with no new run | none | **S-M** | approve the bin removals (D2) | Done: every §3.1 fix is in the bins tables, and the v0.8 bins carry a `spec` tag. |
| **WP3** | **Bug-avoiding variants** | (1) Reg bench `+reg_skip_known_bugs` entries. (2) tenstorrent/tt-oca-harness-aou#90-avoiding `aou_dw_test` (aligned, or size ≠ 6) on 1x256 and 4xmix. (3) Check-then-hard-reset variants of `invalid_actmsg` (per state and op) and the `act_ack` timeout. (4) Same for `id_mismatch` (stray responses), if D8 allows. (5) A quiet `link_event` (`link_reset`, `inband_drop`, `linkerror`) without traffic or SW reset. (6) `err_resp` at matching remote widths. | Code per config: SFR ~35 lines, ~80 cond, ~45 branches, ~1.5k bits; ACTIVATION FSM +1; dn_1024_256 and 3X1_256 CH2 ~6 lines, ~120 cond, ~37 branches, ~60k bits; ERROR_INFO 24 lines on 4xmix and 1x256; SFR/CORE_RP/SLV_AXI_INFO ~40 lines (stray responses). FC: `cg_link_state` LinkReset/Disabled (~8 bins), `cg_act_op tx,illegal` (5). Plan: 20.4, 20.10, 20.12, 20.15, 20.16 (and 9.9, 9.10, 19.8 with D8). | WP2 for the act_op bins | **M** | D8 (weakened stray-response check) | Mostly done or no longer needed: `+detect_only` and the aligned `aou_dw_test` on both 4xmix builds are done; PR #113 (link events and resets pass with traffic), PR #111 (debug window on narrow RPs) and PR #89 (#90) removed the need for the quiet `link_event`, matching-width `err_resp` and 1x256 aligned variants. Missing: a reg skip-known-bugs entry for AXI_SPLIT_TR_EN and check-then-hard-reset `invalid_actmsg`/`act_ack`. |
| **WP4** | **AXI stimulus knobs** | `+lock_pct` and remote EXOKAY for exclusive pairs; `+max_len=255`; `+max_id=1023`; a low address window per RP; programming MAX_AWBURSTLEN/ARBURSTLEN=255 for long M-port bursts; deep outstanding and long back-pressure at max outstanding (`+dp_batch=64`, slow remote B/R, `cyc_gt_1k`); narrow and unaligned through converters on every config; `+fixed_pct/+wrap_pct` **only after D1**. New AXI-S06 attribute check. | FC: about 168 AXI4 attribute and OS/BP bins and most of the 288 legal `cx_size_x_len` cells; `txn_cg` legal FIXED/WRAP (106) after D1. Code: upsizer and downsizer back-pressure cond, AXI4MUX AW FIFO full, RDATA_ORDER, and pending-table toggles. Plan: 4.25-4.28, 5.23-5.26, 8.3, 8.6, 8.14 (and 4.16/4.17 after D1). | D1 for FIXED/WRAP | **M** | D1 | Partly: exclusives with EXOKAY, the attribute check (`aou_attr_test`), W-first and R-interleave, high IDs and 64-deep M-port tables are done; `+max_len`/`+max_id` for random traffic, a low address window per RP and back-pressure over 1k cycles are missing (FIXED/WRAP dropped by D1). |
| **WP5** | **FDI corner stimulus and r2.0 adopt items (FC3)** | `aou_fdi_t1_bringup_corner_test` with the three LSM extensions (event-at-state, wake_ack delay, LP-initiated L1 exit); `pulse_sw` retrain; second-half and repeated flit cancel; stall hold and latency knobs; the nine r2.0 adopt items (NOP flit R20-04, stall sequences R20-02/03, LinkError hold R20-09, remote link-down R20-11, reset-zero R20-01, inband rule R20-07, re-cites); `+active_phy=1` entries on the TP configs. | FSM **34 → 48/58**; `cg_bringup_fsm` +2; `cg_link_state` ~6; `l1.cg_fdi_cancel` +5 and `cg_fdi_stall` +6; new r2.0 bins (~25); plan 18.4/18.5 PHY1, new 18.13-18.25 | D7 (r2.0 asks) | **M-L** | D7 | Partly: second-half and repeated flit cancels, stall knobs, PHY1 entries and plan 18.13-18.26 are done; `aou_fdi_t1_bringup_corner_test`, its LSM extensions and a SW retrain pulse are missing, and the r2.0 items are blocked on D7. |
| **WP6** | **Reset-in-state** | `aou_reset_test +when=retrain/apb_access/agg_halt` and the cycle-exact WAKE_ASSERT/DEACTIVATE/L1_CLK_WAKE/MI resets, **or** `-cm_fsmresetfilter` | FSM +9 (58/58), or denominator 49 | D4 | **S** (filter) / **M** (tests) | D4 | Done by the filter (D4): COV=1 builds pass `-cm_fsmresetfilter` (`COV_FSM_RESET=1` keeps the transitions), and an `XPROP` build checks reset behaviour. |
| **WP7** | **Exclusions and toggle triage** | A reviewed `cov/cov_exclude.el` (or `-cm_noconst`) for D1-D9; a toggle triage script that maps untoggled ranges onto `packet_def_pkg` fields | Upsizer branch → 100%; ~10 FSM-default lines and branches; 1x256 PHY1 ~17 cond and branches; separates more than half of the 212k toggle bits as structural | D5, D6 | **S** after the decision | D5, D6 | Not started: no `.el` or `-cm_noconst` (deferred by D5) and no toggle triage script; only whole-module exclusions exist. |
| **WP8** | **New FC groups for plan intent (Part A, B, X)** | The §4.2 groups: `dut.cg_act/deact/lp_linkreset/qos/split/early/agg/dw/dbg_fifo/id_mismatch/lp/rx_fdi_if`, `tb.cg_irq/cg_reset`, `axi4.cg_order`, `l3.cg_rx_inject/cg_flex`, `reg.cg_access`; the cross-layer X1-X4; `plan_ids` filled per bin | Evidence for ~100 covered plan items. **Adds** perhaps 500-800 bins, so the percentage drops before it recovers. | WP2 | **L** | none (part of the agreed FC plan) | Partly: credit-flow, credit round-robin, early-table, M-port outstanding and AXI attribute/channel/exclusive groups exist; the `dut.*`, `tb.*` and `reg.*` groups, X1-X4 and per-bin `plan_ids` (still empty in `fc.json`) are missing. |
| **WP9** | **New plan items and corrections** | Add the 51 (plus 4 r2.0) items to the corrections and items; `plan_ids` on the 26 that existing tests already do; the approved drops | Plan traceability for the uncovered spec and MAS areas | D9 | **S** | D9 | Done for D9: the 51 items are added, the four drops and the 9.5 retitle applied, and every added item but 10.14 has a run-list entry; the four r2.0 items wait on D7. |
| **WP10** | **Config-dependent leftovers** | DEST_RP full permutations on 4x512, 3x512 and 4xmix; split MAX_AxBURSTLEN 0/1/3/31 and split on 1024-bit RPs; credit over-grant past 2048 (confirm reachability first, otherwise e); B+R error same cycle with the debug FIFO at depth−1; `cg_msg` rp2/rp3 1024 (a new config or a waiver, D6). **RP-width part done:** `4xmix4211-sp128` retuned and `4xmix2144-sp64` added (DECISIONS D9), so every RP is built at every local width | TX_CRD_CTRL 15-36 lines per config, plus 20 saturation lines; SPLIT_TR and ADDRGEN ~8; ERROR_INFO 4; `cg_msg` 8 | D6 | **M** | D6 | Partly: the RP-width configs, split limits 0/1/3 and split on 1024-bit RPs, and same-cycle B+R debug-FIFO errors have entries; a full DEST_RP permutation sweep and the over-grant past 2048 are missing. |
| **WP11** | **v0.8 coverage** | Per D3: a `+spec_rev` plusarg, an `l3_unit` loopback FC report section, and the v0.8 bins (FLEX, profile, ReadData variant, DEACTIVATE credits) | 56 existing plus ~10 new bins, reported separately | D3 | **M** | D3 | Not started: no `+spec_rev` plusarg, loopback FC section or new v0.8 bins; the existing v0.8 bins are tagged (WP2). |
| **WP12** | **Remaining a-class FC** | L3 packer knob for a CrdtGrant at G47; a dense WriteResp flit to the model; model-side zero_stall on wreq/rreq/wresp; `misc_half1 over` per decision D2 | `cg_flit_layout` +2, `cg_flit_occ` +1-2, `cg_credit` +3 | WP2 | **S** | the `over` bin (D2) | Not started: no CrdtGrant-at-G47 entry, `+pk=wresp48` still runs only on 4x512-sp64 and there is no model-side zero-stall stimulus; `misc_half1 over` stays a v0.7 target (D2). |
| **WP13** | **Rerun when the RTL fixes land** | Merge each fix branch into a coverage build and rerun the full regression | Activation messages out of step: ACTIVATION FSM, plan 1.3/1.8/1.9. AXI_SPLIT_TR_EN: the rest of the reg bench. Credits after deactivation: `credit_return` and `link_act_deact`. | the RTL owners | **S** per fix | none | Partly: the FDI bring-up (PR #108), AOU_SW_RESET (PR #113), the downsizer (PR #89), the debug window (PR #111) and the reserved enable bit (PR #118) fixes are on main and in the coverage runs; stray responses were ruled illegal stimulus. The activation-message, AXI_SPLIT_TR_EN and credit-after-deactivation findings are still open. |

**Suggested order:**
1. WP1 + WP2, in parallel: both cheap. Together they take FC to ~83% and FSM to 34/58 on every
   config.
2. WP3 and WP4.
3. Decide D4, D5 and D6, then WP6 and WP7.
4. WP5.
5. WP8 (the largest).
6. WP9 to WP12.
7. WP13 as fixes land.

**Projected position after WP1-WP7 (excluding WP8's new bins):**

| Metric | Union projection |
|---|---|
| FSM | 58/58 (or 49/49 with the filter) |
| Line | ~99% |
| Cond | ~98% |
| Branch | ~98% (with D1-D3 exclusions) |
| FC (existing groups, v0.8 reported separately) | ~93-95% |

What remains would be config-dependent and bug-blocked holes, plus anything that needs a waiver
from the owner.

---

## 7. Decisions asked of the owner

1. **D1: AXI WRAP/FIXED.**
   - The facts: AoU carries no AxBURST (INCR assumed, §2.5), and the converters compute
     addresses as INCR. A downsized WRAP becomes an illegal-length WRAP. The MAS is silent.
   - Approve an interim expectation, then WRAP/FIXED stimulus.
   - Otherwise, declare WRAP/FIXED unsupported on the S port and drop `burst` from `axi.txn_cg`
     (−107 bins) and plan items 4.16/4.17.
2. **D2: the FC2 bin corrections (§3.1, about 286 bins).**
   - They are covergroup bugs, not waivers, but they change the denominator. Approve them as a
     set or per row.
   - Also: should `cg_flit_occ misc_half1 over` (3+ Misc in a half-flit) be a v0.7 target or a
     v0.8 illegal bin?
3. **D3: v0.8 bins (56 now, ~10 to add).**
   - (A) close them on the model in an `l3_unit` loopback, reported separately;
   - (B) keep them as holes until the RTL moves to v0.8;
   - (C) waive them for v0.7 closure.
   - Recommendation: A + B.
4. **D4: reset-caused FSM transitions (9, five of them needing cycle-exact timing).** Test them
   (WP6, M), or filter with `-cm_fsmresetfilter` (S; D10 gains a rule).
5. **D5: line and branch exclusions.** Amend D10 to allow a reviewed `.el` and/or `-cm_noconst`,
   then approve D1-D9 in §2.7 one by one. D1-D3 are clear dead code; D8 is arguable.
6. **D6: closure metric and config-dependent holes.**
   - Is closure measured on the **all-configs union** (D5/D6 exclusions unnecessary) or **per
     config**?
   - And for `cg_msg` 1024-bit data on RP2/RP3 (8 bins): add a config with 1024-bit RP2/RP3, waive
     them, or re-model the bins per RP width?
7. **D7: UCIe r2.0.**
   - Adopt the 9 rows marked adopt (R20-01 to -07, -09, -11)?
   - R20-10: answered: restarting the link after a link-down is software's (owner decision).
   - R20-19: do the 32 B FDI configs (1x256-sp32, 2x512-tp32_64) stay in closure scope?
8. **D8: weakened-check variants.** Allow the ID-mismatch "detect, then hard reset" variant for
   9.9, 9.10 and 19.8? It drops the check that the DUT takes the stray response within 500 cycles.
9. **D9: the plan itself.**
   - Approve the drops: 9.8, 22.5, 1.4, 12.13 (and 2.7/2.10 if PropertyReq goes).
   - Add the 51 new items (and 4 from r2.0)?
   - Retitle 9.5.
