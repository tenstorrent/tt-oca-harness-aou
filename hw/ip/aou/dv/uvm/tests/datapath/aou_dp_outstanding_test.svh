// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Outstanding transactions (plan 8.1-8.15): batches of +dp_batch requests are
// issued before any completes, reads and writes mixed by +dp_wr_pct, with ID
// patterns +dp_ids=random|unique|same|high (out-of-order completion across
// IDs, in-order within one ID, IDs 0x3F0-0x3FF). The scoreboard matches every
// response to its request by ID and order. Both directions.
// +dp_mfull=<cycles> (plan 9.20): remote-originated only, the local
// subordinate answers every burst that many cycles late and the remote die
// keeps 64 requests of one kind in flight per RP, so the M-port pending-ID
// tables fill: the env's aou_t1_mo_chk holds the M port to 32 (FEAT-R22) and
// its cg_mo full bin records that the limit was reached; the DUT must
// back-pressure without an error or a lost transfer.
class aou_dp_outstanding_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_outstanding_test)

  int unsigned mfull;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.lens = '{0, 1, 3, 7};
    k.batch = 4;
    k.wr_pct = 50;
    k.max_id = 15;
    k.n = 64;
    void'($value$plusargs("dp_mfull=%d", mfull));
    if (mfull != 0) begin
      k.dir = AOU_T1_R2L;
      k.lens = '{0, 1, 3};
      // 64 slots fill the 256 KB window; run reads and writes apart
      // (+dp_wr_pct=0|100) so one kind has 64 in flight.
      k.batch = 64;
      k.num_slots = 64;
      k.max_id = 63;
      k.n = 192;
    end
  endfunction

  function void configure_test();
    if (mfull == 0) return;
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      cfg.m_sub_cfg[r].timing.b_lat.set_fixed(mfull);
      cfg.m_sub_cfg[r].timing.r_lat.set_fixed(mfull);
      cfg.r_mgr_cfg[r].max_rd_outstanding = 128;
      cfg.r_mgr_cfg[r].max_wr_outstanding = 128;
    end
  endfunction
endclass
