#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""Self-check for perf_model (the d2d_model adapter and the target table).

The model tests need D2D_COMPARE (a d2d-compare checkout) and are skipped
without it. Run: D2D_COMPARE=<checkout> python3 scripts/test_perf_model.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_model as pm  # noqa: E402

HAVE_MODEL = bool(os.environ.get("D2D_COMPARE"))
needs_model = unittest.skipUnless(HAVE_MODEL, "D2D_COMPARE not set")

# MAS Table 9 (DOC/MAS/ppa-appendices.adoc), "AoU limit by spec": 512-bit AXI,
# 64-byte FDI. (beats, data type, uni-direction %, bi-direction %).
MAS_TABLE_9 = [
    (16, "read", 85.7, 84.6), (16, "write", 79.0, 78.7), (16, "writefull", 84.6, 84.2),
    (1, "read", 85.7, 70.6), (1, "write", 66.7, 63.1), (1, "writefull", 70.6, 66.7),
]


def side(kind, beats, width, partial=False, count=1, offset=0):
    return [(kind, beats * width, offset, width, width, partial, count)]


@needs_model
class ModelTest(unittest.TestCase):
    def test_spec_check(self):
        """d2d_model's own AoU spec reproduction: 24/24 within 0.2 %."""
        m = pm.model()
        rows = m.check_aou_spec(verbose=False)
        self.assertEqual(len(rows), 24)
        self.assertEqual([r for r in rows if abs(r[4]) >= 0.002], [])

    def test_mas_table_9(self):
        """Every MAS Table 9 limit, uni- and bi-directional. The table gives 0.1 pp and
        truncates (63.16 % is listed as 63.1 %)."""
        for beats, typ, uni, bid in MAS_TABLE_9:
            kind = "R" if typ == "read" else "W"
            s = side(kind, beats, 64, partial=(typ == "write"))
            link = "r2l" if kind == "R" else "l2r"    # where the data travels, local issue
            u = pm.model_window(64, s, [])[link]["eff"]
            b = pm.model_window(64, s, s)[link]["eff"]
            with self.subTest(beats=beats, typ=typ):
                self.assertAlmostEqual(100 * u, uni, delta=0.1)
                self.assertAlmostEqual(100 * b, bid, delta=0.1)

    def test_saturated_bandwidth(self):
        """16-beat reads, one side: 85.7 % of a 64 B/cycle link, saturated."""
        r = pm.model_window(64, side("R", 16, 64), [])
        self.assertAlmostEqual(r["r2l"]["bpc"], 64 * 6 / 7, places=3)
        self.assertAlmostEqual(r["r2l"]["duty"], 1.0)
        self.assertEqual(r["l2r"]["bpc"], 0)

    def test_asymmetric_widths(self):
        """1x256-sp32 bw_wr: local 16 x 32 B writes, remote 16 x 64 B, same rate.
        DUT TX carries WriteDataFull256 at the local width, DUT RX WriteDataFull512;
        l2r delivers half of r2l, and r2l is the saturated link."""
        r = pm.model_window(32, side("W", 16, 32), side("W", 16, 64))
        self.assertAlmostEqual(r["l2r"]["bpc"] * 2, r["r2l"]["bpc"], places=6)
        self.assertAlmostEqual(r["r2l"]["duty"], 1.0)
        self.assertLess(r["l2r"]["duty"], 0.6)
        self.assertEqual(r["l2r"]["msgs"], {"WriteReq": 1, "WriteDataFull256": 16, "WriteResp": 1})
        self.assertEqual(r["r2l"]["msgs"], {"WriteReq": 1, "WriteDataFull512": 16, "WriteResp": 1})

    def test_asymmetric_reads(self):
        """Reads: local ReadData returns on r2l at the local width; the DUT answers the
        remote's reads on l2r at the remote width."""
        r = pm.model_window(64, side("R", 16, 32), side("R", 16, 128))
        self.assertEqual(r["l2r"]["msgs"], {"ReadReq": 1, "ReadData1024": 16})
        self.assertEqual(r["r2l"]["msgs"], {"ReadReq": 1, "ReadData256": 16})
        self.assertAlmostEqual(r["l2r"]["bpc"], 4 * r["r2l"]["bpc"], places=6)

    def test_symmetric_matches_bidir(self):
        """A partner pattern equal to the local one is the model's bidir scenario."""
        m = pm.model()
        s = side("W", 4, 64) + side("R", 4, 64)
        r = pm.model_window(64, s, s)
        ref = m.run_dirs(m.AoU(m.Config()), m.Scenario("b", pm._txns(m, s), bidir=True))
        self.assertAlmostEqual(r["l2r"]["bpc"], ref["Bpb_AB"], places=9)
        self.assertAlmostEqual(r["r2l"]["bpc"], ref["Bpb_BA"], places=9)

    def test_remote_only_mirrors_local_only(self):
        a = pm.model_window(64, side("W", 16, 64), [])
        b = pm.model_window(64, [], side("W", 16, 64))
        self.assertAlmostEqual(a["l2r"]["bpc"], b["r2l"]["bpc"], places=9)
        self.assertEqual(a["l2r"]["msgs"], b["r2l"]["msgs"])

    def test_partial_strobe(self):
        r = pm.model_window(64, side("W", 16, 64, partial=True), [])
        self.assertEqual(r["l2r"]["msgs"], {"WriteReq": 1, "WriteData512": 16})
        self.assertAlmostEqual(r["l2r"]["eff"], 0.790, places=3)

    def test_run_from_perf_json(self):
        """A perf.json window rebuilds the model; full_pct splits the remote's writes."""
        perf = {"build": {"beat_bytes": 64, "writefull": True, "remote_full_pct": 50},
                "windows": [{"name": "bw_wr", "scenario": "S1", "txn_hist": [
                    {"init": "l2r", "kind": "W", "rp": 0, "bytes": 1024, "beat_bytes": 64,
                     "offset_mod_4k": 0, "full_strb": True, "count": 32},
                    {"init": "r2l", "kind": "W", "rp": 0, "bytes": 1024, "beat_bytes": 64,
                     "offset_mod_4k": 0, "full_strb": True, "count": 32}]}]}
        loc, rem = pm.run_sides(perf["build"], perf["windows"][0])
        self.assertEqual(loc, [("W", 1024, 0, 64, 64, False, 32)])
        self.assertEqual(sorted(rem), [("W", 1024, 0, 64, 64, False, 16),
                                       ("W", 1024, 0, 64, 64, True, 16)])
        r = pm.model_run(perf)["bw_wr"]
        self.assertEqual(r["r2l"]["msgs"]["WriteData512"], r["r2l"]["msgs"]["WriteDataFull512"])

    def test_local_bursts_whole(self):
        """A 32-beat local write crosses the link as one WriteReq whatever the DUT's
        AXI_SPLIT_TR_RPn holds: the splitter acts on received requests, at the manager
        port, not on what the subordinate port sends."""
        loc = [("W", 2048, 0, 64, 64, False, 1)]
        r = pm.model_window(64, loc, [])
        self.assertEqual(r["l2r"]["msgs"], {"WriteReq": 1, "WriteDataFull512": 32})
        b = {"beat_bytes": 64, "rp_bytes": [64], "remote_bytes": [64], "max_awlen": [15],
             "max_arlen": [15]}
        w = {"txn_hist": [{"init": "l2r", "kind": "W", "rp": 0, "bytes": 2048, "beat_bytes": 64,
                           "offset_mod_4k": 0, "full_strb": True, "count": 4}]}
        self.assertEqual(pm.run_sides(b, w)[0], [("W", 2048, 0, 64, 64, False, 4)])

    def test_narrow_axsize(self):
        """256 beats within 4 KB on a 64 B bus: 16 B AxSIZE, one 256-bit message per beat,
        with strobes (the message is wider than the beat)."""
        w = {"window": "bl_256", "traffic_dir": "l2r", "wr_pct": "100", "beats": "256"}
        loc, _ = pm.window_sides(w, {"rp_bytes": [64], "phy_bytes": [64]})
        self.assertEqual(loc, [("W", 4096, 0, 64, 16, False, 1)])
        r = pm.model_window(64, loc, [])
        self.assertEqual(r["l2r"]["msgs"], {"WriteReq": 1, "WriteData256": 256})

    def test_committed_table_current(self):
        """uvm/env/perf/aou_perf_targets.svh matches the live model (make perf_check drift)."""
        table = pm.read_svh()
        opt = any(k.split("|")[2] == "S6" for k in table)
        fresh = {pm.key_of(r): r for r in pm.gen_targets(optional=opt)}
        self.assertEqual(set(fresh), set(table))
        for k, r in fresh.items():
            self.assertAlmostEqual(r["model"], table[k]["model"], delta=1e-4, msg=k)


class ScenarioTest(unittest.TestCase):
    CONFS = {"1x512": {"rp_bytes": [64], "phy_bytes": [64]},
             "4xmix": {"rp_bytes": [128, 32, 64, 32], "phy_bytes": [128]}}

    def test_configs_from_sim_cfg(self):
        c = pm.read_configs()
        self.assertEqual(c["1x512-sp64"], {"rp_bytes": [64], "phy_bytes": [64]})
        self.assertEqual(c["4xmix4211-sp128"]["rp_bytes"], [128, 64, 32, 32])
        self.assertEqual(c["2xmix-tp64_128"]["phy_bytes"], [64, 128])

    def test_scenario_file(self):
        wins = pm.load_scenarios()
        names = [w["window"] for w in wins]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue({"bw_wr", "bw_rd", "bw_mix"} <= set(names))
        self.assertEqual({w["scenario"] for w in wins}, {"S1", "S2", "S3", "S4", "S5", "S6"})

    def test_4k_boundary(self):
        """Bursts narrow their AxSIZE to stay within 4 KB; a fixed size cannot."""
        self.assertEqual(pm.axsize(128, 64), 32)
        self.assertEqual(pm.axsize(64, 64), 64)
        self.assertEqual(pm.axsize(256, 128), 16)
        w = {"window": "t", "traffic_dir": "both", "wr_pct": "50", "bytes": "4096", "offset": "16"}
        self.assertIsNone(pm.window_sides(w, self.CONFS["1x512"]))
        w["offset"] = "0"
        self.assertIsNotNone(pm.window_sides(w, self.CONFS["1x512"]))

    def test_widest_share(self):
        w = {"window": "pl_w50", "traffic_dir": "both", "wr_pct": "100", "beats": "16",
             "widest_pct": "50"}
        loc, rem = pm.window_sides(w, self.CONFS["4xmix"])
        self.assertEqual([(e[1], e[3], e[6]) for e in loc],
                         [(2048, 128, 3), (512, 32, 1), (1024, 64, 1), (512, 32, 1)])
        self.assertEqual(pm.rp_weights(w, self.CONFS["4xmix"]), [3, 1, 1, 1])
        self.assertEqual({e[3] for e in rem}, {64})
        w["widest_pct"] = "0"
        loc, _ = pm.window_sides(w, self.CONFS["4xmix"])
        self.assertEqual([e[3] for e in loc], [32, 64, 32])

    def test_direction_and_mix(self):
        w = {"window": "x", "traffic_dir": "r2l", "wr_pct": "50", "beats": "1", "strb": "partial"}
        loc, rem = pm.window_sides(w, self.CONFS["1x512"])
        self.assertEqual(loc, [])
        self.assertEqual(sorted(rem), [("R", 64, 0, 64, 64, False, 1), ("W", 64, 0, 64, 64, True, 1)])
        self.assertEqual(pm.rp_weights(w, self.CONFS["1x512"]), [2])


class TableTest(unittest.TestCase):
    ROWS = [dict(config="1x512-sp64", active_phy=0, scenario="S1", window="bw_wr", dir="l2r",
                 model=53.8947, eff=0.8421, duty=1.0, tol=0.03, eps=256, reason="",
                 mix={"WriteReq": 1 / 18, "WriteDataFull512": 16 / 18, "WriteResp": 1 / 18}),
            dict(config="1x512-sp64", active_phy=0, scenario="S2", window="sm_wr", dir="r2l",
                 model=30.0, eff=0.6, duty=0.9, tol=0.05, eps=256, reason='measured "pad"')]

    def test_svh_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.svh")
            pm.write_svh(self.ROWS, p)
            t = pm.read_svh(p)
        self.assertEqual(t["1x512-sp64|0|S2|sm_wr|r2l"]["reason"], 'measured \\"pad\\"')
        self.assertEqual(t["1x512-sp64|0|S1|bw_wr|l2r"]["model"], 53.8947)
        self.assertEqual(t["1x512-sp64|0|S1|bw_wr|l2r"]["eps"], 256)
        self.assertAlmostEqual(t["1x512-sp64|0|S1|bw_wr|l2r"]["mix"]["WriteDataFull512"], 16 / 18,
                               places=6)

    def test_judge(self):
        tgt = {"model": 50.0, "tol": 0.03, "eps": 256}
        self.assertEqual(pm.judge({"bpc": 48.6, "cycles": 1000}, tgt)[0], "PASS")
        self.assertEqual(pm.judge({"bpc": 48.4, "cycles": 1000}, tgt)[0], "BELOW")
        self.assertEqual(pm.judge({"bpc": 50.25, "cycles": 1000}, tgt)[0], "PASS")
        self.assertEqual(pm.judge({"bpc": 50.3, "cycles": 1000}, tgt)[0], "ABOVE")
        self.assertEqual(pm.judge({"bpc": 50.0, "cycles": 1000}, None)[0], "NO_TARGET")
        # the link's own steady-state messages fit more than the model's rate: the
        # above-model bound is that capacity, the lower bound stays the model's
        self.assertEqual(pm.judge({"bpc": 51.0, "cycles": 1000, "mix_cap": 51.2}, tgt)[0], "PASS")
        self.assertEqual(pm.judge({"bpc": 51.5, "cycles": 1000, "mix_cap": 51.2}, tgt)[0], "ABOVE")
        self.assertEqual(pm.judge({"bpc": 48.4, "cycles": 1000, "mix_cap": 40.0}, tgt)[0], "BELOW")
        self.assertEqual(pm.judge({"bpc": 48.4, "cycles": 1000, "ss_ok": False}, tgt)[0],
                         "BELOW+SHORT")

    def test_mix(self):
        mix = {"WriteReq": 1 / 18, "WriteDataFull512": 16 / 18, "WriteResp": 1 / 18}
        tgt = {"model": 50.0, "tol": 0.03, "eps": 256, "mix": mix}
        ok = {"WriteReq": 100, "WriteDataFull512": 1600, "WriteResp": 100, "CrdtGrant": 7}
        self.assertEqual(pm.judge({"bpc": 50.0, "cycles": 1000, "msgs": ok}, tgt)[0], "PASS")
        bad = dict(ok, WriteDataFull512=1500, WriteData512=100)
        self.assertEqual(pm.judge({"bpc": 50.0, "cycles": 1000, "msgs": bad}, tgt)[0], "MIX")

    def test_check_runs(self):
        """judge_runs reads perf.json link values (steady-state copies) and keys them."""
        win = {"name": "bw_wr", "scenario": "S1", "dir": {
            "l2r": {"app_bytes": 53000, "cycles": 1000, "duty": 0.99,
                    "ss": {"ss_ok": True, "msgs_by_msg": {}}},
            "r2l": {"app_bytes": 40000, "cycles": 1000, "duty": 0.99, "ss": None}}}
        perf = {"build": {"config": "1x512-sp64", "active_phy": 0}, "windows": [win]}
        table = {"1x512-sp64|0|S1|bw_wr|l2r": {"model": 53.8947, "tol": 0.03, "eps": 256},
                 "1x512-sp64|0|S1|bw_wr|r2l": {"model": 53.8947, "tol": 0.03, "eps": 256}}
        with tempfile.TemporaryDirectory() as d:
            run = os.path.join(d, "vcs-t1-1x512-sp64", "aou_perf_test.rid.1")
            os.makedirs(run)
            with open(os.path.join(run, "perf.json"), "w", encoding="utf-8") as fh:
                json.dump(perf, fh)
            rows = {r["dir"]: r for r in pm.judge_runs(d, table)}
        self.assertEqual(rows["l2r"]["verdict"], "PASS")
        self.assertEqual(rows["r2l"]["verdict"], "BELOW+SHORT")
        self.assertEqual(rows["l2r"]["build"], "vcs-t1-1x512-sp64")


if __name__ == "__main__":
    unittest.main()
