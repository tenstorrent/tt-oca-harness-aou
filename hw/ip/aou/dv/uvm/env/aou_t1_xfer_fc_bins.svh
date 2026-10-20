// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Bins tables of aou_t1_xfer_cov (aou_fc_macros.svh).
`define AOU_XFER_FC_PATH(B) `B``_BIN(l2r, 0, 0) `B``_BIN(r2l, 1, 1)
`define AOU_XFER_FC_DIR(B) `B``_BIN(wr, 0, 0) `B``_BIN(rd, 1, 1)
`define AOU_XFER_FC_QOS(B) `B``_VALS(qos, 0, 15)
`define AOU_XFER_FC_PROT(B) `B``_VALS(prot, 0, 7)
// AXI4 A4.4 Table A4-5: the AxCACHE encodings that are not reserved.
`define AOU_XFER_FC_CACHE(B) \
  `B``_VALS(dev, 0, 1) `B``_VALS(normal_nc, 2, 3) `B``_VALS(wt_ra, 6, 7) \
  `B``_VALS(wt_wa, 10, 11) `B``_VALS(wt_rwa, 14, 15)
`define AOU_XFER_FC_EXRESP(B) `B``_BIN(okay, 0, 0) `B``_BIN(exokay, 1, 1)
// Channel orderings (aou_t1_xfer_cov::ev_e). w_taken_before_aw is no target:
// the DUT holds WREADY until the burst's AW is accepted whether or not early
// response is on (AOU_EARLY_BRESP_CTRL_AWCACHE w_write_aw_credit; MAS 3.7.5).
`define AOU_XFER_FC_EVENT(B) \
  `B``_BIN(w_before_aw, 0, 0) `B``_IGN(w_taken_before_aw, 1, 1) `B``_BIN(m_r_interleave, 2, 2) \
  `B``_BIN(rdata_msg_interleave, 3, 3) `B``_BIN(s_r_interleave, 4, 4)
// Width pairing (aou_t1_xfer_cov::width_cg): an AXI data width in bytes, the
// requester's AxSIZE, and whether it is its full bus width.
`define AOU_XFER_FC_WIDTH(B) `B``_BIN(w256, 32, 32) `B``_BIN(w512, 64, 64) `B``_BIN(w1024, 128, 128)
`define AOU_XFER_FC_SIZE(B) \
  `B``_BIN(sub256, 0, 4) `B``_BIN(s256, 5, 5) `B``_BIN(s512, 6, 6) `B``_BIN(s1024, 7, 7)
`define AOU_XFER_FC_REQ(B) `B``_BIN(native, 0, 0) `B``_BIN(narrower, 1, 1)
// A request is never wider than its requester's bus: the DUT's RP on l2r, the
// remote die's on r2l. Cells: path, direction, DUT width, remote width, size.
`define AOU_XFER_FC_X_SIZE(B) \
  `B``_XIGN("l2r,*,w256,*,s512|s1024") `B``_XIGN("l2r,*,w512,*,s1024") \
  `B``_XIGN("r2l,*,*,w256,s512|s1024") `B``_XIGN("r2l,*,*,w512,s1024")
// The remote splitter's maximum burst length (beats) and whether a request was
// split. A legal burst is at most 4KB, at least 32 bytes a beat: 128 beats, so
// a maximum of 128 or 256 never splits.
`define AOU_XFER_FC_MAX_BURST(B) \
  `B``_BIN(b1, 1, 1) `B``_BIN(b2, 2, 2) `B``_BIN(b4, 4, 4) `B``_BIN(b8, 8, 8) \
  `B``_BIN(b16, 16, 16) `B``_BIN(b32, 32, 32) `B``_BIN(b64, 64, 64) \
  `B``_BIN(b128, 128, 128) `B``_BIN(b256, 256, 256)
`define AOU_XFER_FC_SPLIT(B) `B``_BIN(whole, 0, 0) `B``_BIN(split, 1, 1)
`define AOU_XFER_FC_X_SPLIT(B) `B``_XIGN("b128|b256,split")
// Small requests (AxSIZE 0..4, 1 to 16 bytes). 4- and 8-byte register accesses
// are the usual ones; 1-, 2- and 16-byte ones are rare by design
// (+small_size_wt), so their bins carry the tag "rare" instead of reading as
// ordinary holes.
`define AOU_XFER_FC_SMALL(B) \
  `B``_BIN(b1, 0, 0) `B``_BIN(b2, 1, 1) `B``_BIN(b4, 2, 2) `B``_BIN(b8, 3, 3) `B``_BIN(b16, 4, 4)
`define AOU_XFER_FC_SMALL_RARE(B) `B``_TAG("b1|b2|b16", "rare")
`define AOU_XFER_FC_X_SMALL_RARE(B) `B``_TAG("*,*,b1|b2|b16", "rare")
