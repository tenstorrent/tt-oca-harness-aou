// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of aou_t1_rp_map_chk (aou_fc_macros.svh).
// cg_rp_map_req, one sample per WriteReq/ReadReq the DUT sends: its direction,
// the local port it came from, the TX lane it went on, and how the port was
// routed (mapping disabled; enabled, alone on its own lane; alone on another
// port's lane; merged with other ports).
`define AOU_T1_RPMAP_FC_DIR(B) `B``_BIN(wr, 0, 0) `B``_BIN(rd, 1, 1)
`define AOU_T1_RPMAP_FC_PORT(B) `B``_VALS(port, 0, 3)
`define AOU_T1_RPMAP_FC_LANE(B) `B``_VALS(lane, 0, 3)
`define AOU_T1_RPMAP_FC_ROUTE(B) \
  `B``_BIN(disabled, 0, 0) `B``_BIN(own_lane, 1, 1) `B``_BIN(moved, 2, 2) `B``_BIN(merged, 3, 3)
// cg_rp_map_cfg, one sample per mapping that carried a request (the first
// request after it was programmed or the link was activated again):
// - shape: disabled (with the lane selects at reset or not), enabled as the
//   identity, singletons only with some moved, one merge group of 2, 3 or 4
//   ports, two groups of 2 (MAS 3.10.4);
// - the DUT's RP count against the remote die's (r<DUT>p<remote>);
// - whether a merge group mixes AXI data widths, and whether a port sends on a
//   lane whose own port is narrower (MAS 3.10.4 "Data width").
`define AOU_T1_RPMAP_FC_SHAPE(B) \
  `B``_BIN(off_reset, 0, 0) `B``_BIN(off_sel, 1, 1) `B``_BIN(identity, 2, 2) \
  `B``_BIN(moved, 3, 3) `B``_BIN(pair, 4, 4) `B``_BIN(triple, 5, 5) `B``_BIN(quad, 6, 6) \
  `B``_BIN(two_pairs, 7, 7)
`define AOU_T1_RPMAP_FC_PAIR(B) \
  `B``_BIN(r2p1, 21, 21) `B``_BIN(r2p2, 22, 22) `B``_BIN(r2p3, 23, 23) `B``_BIN(r2p4, 24, 24) \
  `B``_BIN(r3p1, 31, 31) `B``_BIN(r3p2, 32, 32) `B``_BIN(r3p3, 33, 33) `B``_BIN(r3p4, 34, 34) \
  `B``_BIN(r4p1, 41, 41) `B``_BIN(r4p2, 42, 42) `B``_BIN(r4p3, 43, 43) `B``_BIN(r4p4, 44, 44)
`define AOU_T1_RPMAP_FC_MERGE(B) `B``_BIN(none, 0, 0) `B``_BIN(merged, 1, 1)
`define AOU_T1_RPMAP_FC_WIDTH(B) \
  `B``_IGN(no_group, 0, 0) `B``_BIN(same_width, 1, 1) `B``_BIN(mixed_width, 2, 2)
`define AOU_T1_RPMAP_FC_WIDE(B) `B``_IGN(no, 0, 0) `B``_BIN(wider_port_on_lane, 1, 1)
