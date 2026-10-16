// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3: the remote die's AoU protocol layer (messages, flits, packing,
// credits, activation) and the AOU_FDI_CHECKER adapter.
// See docs/ARCHITECTURE.md for the L1 and L4a boundaries.
`timescale 1ns/1ps
package aou_l3_pkg;
  import uvm_pkg::*;
  import aou_rule_pkg::*;
  import aou_fc_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  `include "aou_fc_macros.svh"

  typedef class aou_l3_cov;

  `include "aou_l3_types.svh"
  `include "aou_l3_rule_chk.svh"
  `include "aou_msg.svh"
  `include "aou_msg_req.svh"
  `include "aou_msg_wreq.svh"
  `include "aou_msg_rreq.svh"
  `include "aou_msg_wdata.svh"
  `include "aou_msg_rdata.svh"
  `include "aou_msg_wresp.svh"
  `include "aou_msg_act.svh"
  `include "aou_msg_crdtgrant.svh"
  `include "aou_msg_raw.svh"
  `include "aou_msg_codec.svh"
  `include "aou_flit.svh"
  `include "aou_l3_flit_item.svh"
  `include "aou_packer_policy.svh"
  `include "aou_l4a_if_c.svh"
  `include "aou_l3_cfg.svh"
  `include "aou_l3_fc_bins.svh"
  `include "aou_l3_cov.svh"
  `include "aou_credit_mgr.svh"
  `include "aou_link_ctrl.svh"
  `include "aou_packer.svh"
  `include "aou_unpacker.svh"
  `include "aou_l3_model.svh"
  `include "aou_l3_wr_txn.svh"
  `include "aou_l3_sequencer.svh"
  `include "aou_l3_msg_driver.svh"
  `include "aou_l3_agent.svh"
  `include "aou_fdi_chk_adapter.svh"
  `include "seq/aou_l3_base_seq.svh"
  `include "seq/aou_l3_bad_type_seq.svh"
  `include "seq/aou_l3_rsvd_seq.svh"
  `include "seq/aou_l3_no_credit_seq.svh"
  `include "seq/aou_l3_act_inject_seq.svh"
  `include "seq/aou_l3_flit_inject_seq.svh"
  `include "seq/aou_l3_overgrant_seq.svh"
endpackage
