// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// How the packer lays messages into flits. The default is DUT-like: messages
// in submission order, except that requests and responses go ahead of bulk
// data (bulk_last), packed back to back from the first free granule,
// spanning freely into the next flit, credits returned through the header,
// except that a few writes send WriteData ahead of their WriteReq
// (wdata_first_pct). Every other setting is still legal unless a field says
// "injection".
class aou_packer_policy extends uvm_object;
  `uvm_object_utils(aou_packer_policy)

  // Messages started per flit; 0 is no limit (1 gives minimum density).
  int unsigned      max_msgs_per_flit;
  // With max_msgs_per_flit, a WriteData placed right after a WriteReq does not
  // count: the pair shares the flit (max_msgs_per_flit 1 then gives one
  // request, or one WriteReq with its first WriteData, per flit).
  bit               wreq_wdata_pair = 1'b0;
  // Percent chance of leaving 1..max_hole empty granules before a message.
  int unsigned      hole_pct;
  int unsigned      max_hole = 4;
  // First new message in each flit starts here when >= 0 (MsgStart anywhere).
  int               start_granule = -1;
  // A message longer than split_at starts at 48 - split_at, so exactly
  // split_at of its granules land in this flit (forced split at granule k).
  int               split_at = -1;
  bit               allow_span = 1'b1;
  // Pick randomly among the eligible queue heads instead of oldest first:
  // reorders across RPs and credit classes, never within one.
  bit               random_order;
  // Requests, write responses and Misc go ahead of queued ReadData and
  // WriteData, oldest first among themselves, as a die with a separate lane
  // per message class sends them (the DUT does). Without it every message
  // waits behind all data queued before it: a ReadReq or WriteResp queued
  // behind 32 bursts of read data waits hundreds of cycles, and the other
  // die's link idles for want of requests. 0 is the plain oldest-first order,
  // still legal. random_order ignores it.
  bit               bulk_last = 1'b1;
  // Send a flit that only returns credits when nothing else is ready.
  bit               credit_only_flits = 1'b1;
  // Percent chance that a flit with work pending goes out empty instead.
  int unsigned      empty_flit_pct;
  aou_cred_method_e cred_method = AOU_CRM_DUT_LIKE;
  // Non-Activation Misc messages per half-flit (v0.8 4.4 allows 2, so only
  // 1 and 2 are legal). There is no knob for the v0.7 layout (anything beside
  // an Activation message), which v0.8 forbids and whose receiver reaction it
  // does not define.
  int unsigned      misc_per_half_max = 2;
  // Percent of our Activation flits that carry what 4.4 (v0.9 draft) lets
  // share them: the initial CrdtGrant beside our ActivateAck (or beside our
  // ActivateReq when that follows our Ack and the grant is still due), and
  // the WriteResp/ReadData we still owe beside our DeactivateReq. The rest,
  // and every DeactivateAck flit, carry the Activation alone. The DUT's RX
  // has to take both layouts.
  int unsigned      act_share_pct = 50;
  // Hold every credited message back (Misc still goes) until cleared, so a
  // batch queues up and leaves in densely packed flits; the caller kicks the
  // model when it clears the hold.
  bit               hold_credited;
  // Percent chance that an AXI message to the DUT gets a random FLEX. v0.8
  // makes FLEX the AXI USER[15:0] (5.2 / 11.1); the DUT has no USER outputs,
  // so what it receives goes nowhere and any value is legal. The model
  // randomises FLEX[11:0] (v0.7's PROF) and keeps FLEX[15:12] 0, the only
  // PROFEXTLEN a v0.7 receiver takes; the name predates v0.8.
  int unsigned      prof_pct;
  // A message that would not end in this flit is swapped for the largest
  // eligible queue head that does (reorders across queues only), so flits
  // fill to exactly G47.
  bit               best_fit;
  // Zero-credit CrdtGrant messages added to a flit, up to misc_per_half_max
  // per half (legal Misc no DUT sends).
  int unsigned      zero_grants;
  // Percent of flits whose CrdtGrant (when credit is due) starts at G47 and
  // ends in G0 of the next flit, after empty granules, instead of going early
  // in the flit. 4.4 lets any message continue in G0 of the next flit; no DUT
  // layout puts a Misc message there.
  int unsigned      grant_span_pct;
  // Percent of WriteReqs held back until wdata_first_beats of their own
  // WriteData messages have gone first. AoU v0.8 5.7 does not order a
  // WriteReq against its WriteData, and another die may send the data first;
  // the DUT's RX has to take either order. 0 sends every WriteReq in
  // submission order. A WriteReq is held only while the RP's next WriteData
  // can go (it has WDATA credit and the link allows it), so the order never
  // waits on credit the DUT returns only once the WriteReq has arrived.
  int unsigned      wdata_first_pct = 5;
  // WriteData messages sent ahead of the held WriteReq: 0 picks 1 to the
  // whole burst per write; N sends N, or the whole burst when shorter.
  int unsigned      wdata_first_beats;
  // Stimulus: no WriteReq goes on these RPs (bit r: RP field r), as if the
  // model had no WREQ credit there, while their WriteData still goes on WDATA
  // credit. The data of several writes then waits at the receiver ahead of
  // every WriteReq, up to the WDATA credit it advertised. The caller clears
  // the mask and kicks the model to let the WriteReqs go.
  bit [AOU_RP_MAX-1:0] hold_wreq_rps;

  function new(string name = "aou_packer_policy");
    super.new(name);
  endfunction

  function void set_dut_like();
    max_msgs_per_flit = 0;
    hole_pct = 0;
    start_granule = -1;
    split_at = -1;
    allow_span = 1'b1;
    random_order = 1'b0;
    bulk_last = 1'b1;
    empty_flit_pct = 0;
    cred_method = AOU_CRM_DUT_LIKE;
    hold_credited = 1'b0;
    prof_pct = 0;
    zero_grants = 0;
    grant_span_pct = 0;
    best_fit = 1'b0;
    wdata_first_pct = 5;
    wdata_first_beats = 0;
    hold_wreq_rps = '0;
  endfunction

  function void set_sparse();
    set_dut_like();
    hole_pct = 50;
    max_hole = 6;
    random_order = 1'b1;
    cred_method = AOU_CRM_MIXED;
  endfunction

  function void set_max_density();
    set_dut_like();
  endfunction

  function void set_min_density();
    set_dut_like();
    max_msgs_per_flit = 1;
    allow_span = 1'b0;
  endfunction

  function void set_random();
    set_dut_like();
    hole_pct = $urandom_range(0, 40);
    max_hole = $urandom_range(1, 8);
    max_msgs_per_flit = $urandom_range(0, 3) == 0 ? $urandom_range(1, 4) : 0;
    allow_span = 1'($urandom_range(0, 3) != 0);
    random_order = 1'($urandom_range(0, 1));
    bulk_last = 1'($urandom_range(0, 1));
    empty_flit_pct = $urandom_range(0, 1) * 5;
    cred_method = aou_cred_method_e'($urandom_range(0, 3));
    wdata_first_pct = $urandom_range(0, 2) * 25;
    wdata_first_beats = ($urandom_range(0, 1) == 0) ? 0 : 256;
  endfunction

  virtual function string convert2string();
    return $sformatf({"max_msgs=%0d/pair=%0d hole=%0d%%/%0d start=%0d split=%0d span=%0d rand=%0d ",
                      "cred_only=%0d empty=%0d%% cred=%0d misc_half=%0d hold=%0d ",
                      "prof=%0d%% zero_grants=%0d grant_span=%0d%% best_fit=%0d ",
                      "wdata_first=%0d%%/%0d hold_wreq=%b bulk_last=%0d"},
                     max_msgs_per_flit, wreq_wdata_pair, hole_pct, max_hole, start_granule,
                     split_at, allow_span, random_order, credit_only_flits, empty_flit_pct,
                     cred_method, misc_per_half_max, hold_credited, prof_pct,
                     zero_grants, grant_span_pct, best_fit, wdata_first_pct, wdata_first_beats,
                     hold_wreq_rps, bulk_last);
  endfunction
endclass
