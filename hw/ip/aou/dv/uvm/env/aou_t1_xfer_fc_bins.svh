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
