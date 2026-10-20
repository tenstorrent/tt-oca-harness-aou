// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// How the packer lays messages into flits. The default is DUT-like: messages
// in submission order, packed back to back from the first free granule,
// spanning freely into the next flit, credits returned through the header.
// Every other setting is still legal unless a field says "injection".
class aou_packer_policy extends uvm_object;
  `uvm_object_utils(aou_packer_policy)

  // Messages started per flit; 0 is no limit (1 gives minimum density).
  int unsigned      max_msgs_per_flit;
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
  // Send a flit that only returns credits when nothing else is ready.
  bit               credit_only_flits = 1'b1;
  // Percent chance that a flit with work pending goes out empty instead.
  int unsigned      empty_flit_pct;
  aou_cred_method_e cred_method = AOU_CRM_DUT_LIKE;
  // Non-Activation Misc messages per half-flit (v0.8 4.4 allows 2, so only
  // 1 and 2 are legal). An Activation message always travels alone in its
  // flit (v0.8 4.4); there is no knob for the v0.7 layout, which v0.8 forbids
  // and whose receiver reaction it does not define.
  int unsigned      misc_per_half_max = 2;
  // Hold every credited message back (Misc still goes) until cleared, so a
  // batch queues up and leaves in densely packed flits; the caller kicks the
  // model when it clears the hold.
  bit               hold_credited;
  // Percent chance that an AXI message gets a random PROF (FLEX[11:0]);
  // PROFEXTLEN (FLEX[15:12]) stays 0, the only length the TB models.
  int unsigned      prof_pct;
  // A message that would not end in this flit is swapped for the largest
  // eligible queue head that does (reorders across queues only), so flits
  // fill to exactly G47.
  bit               best_fit;
  // Zero-credit CrdtGrant messages added to a flit, up to misc_per_half_max
  // per half (legal Misc no DUT sends).
  int unsigned      zero_grants;

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
    empty_flit_pct = 0;
    cred_method = AOU_CRM_DUT_LIKE;
    hold_credited = 1'b0;
    prof_pct = 0;
    zero_grants = 0;
    best_fit = 1'b0;
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
    empty_flit_pct = $urandom_range(0, 1) * 5;
    cred_method = aou_cred_method_e'($urandom_range(0, 3));
  endfunction

  virtual function string convert2string();
    return $sformatf({"max_msgs=%0d hole=%0d%%/%0d start=%0d split=%0d span=%0d rand=%0d ",
                      "cred_only=%0d empty=%0d%% cred=%0d misc_half=%0d hold=%0d ",
                      "prof=%0d%% zero_grants=%0d best_fit=%0d"},
                     max_msgs_per_flit, hole_pct, max_hole, start_granule, split_at,
                     allow_span, random_order, credit_only_flits, empty_flit_pct,
                     cred_method, misc_per_half_max, hold_credited, prof_pct,
                     zero_grants, best_fit);
  endfunction
endclass
