// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Stimulus for AXI request attributes across the link, both directions (plan
// 4.26-4.28, 5.24-5.26, 4.30): every transfer steps AxQOS 0-15, AxPROT 0-7 and
// the legal AxCACHE encodings, separately for writes and reads
// (+dp_attr_sweep), and the remote die puts a random PROF (FLEX[11:0]) in half
// its AXI messages. The env's aou_t1_attr_chk checks the attributes on both
// ends of the link and FLEX 0 from the DUT, the scoreboard the data (FLEX the
// DUT receives must be ignored; it has no USER ports), and xfer_cov.attr_cg
// shows every value was carried. FLEX[15:12] (v0.7 PROFEXTLEN) stays 0,
// BUGS/027.
// +attr_excl=1 (plan 4.25, 5.23) adds the exclusive rounds of aou_attr_vseq
// first; aou_t1_attr_chk checks each exclusive response is the subordinate's,
// and xfer_cov.excl_cg counts EXOKAY and failed exclusives each way.
// +attr_early=1 enables early write responses on every RP, makes the
// exclusive accesses bufferable (AWCACHE[0]=1) and the traffic after them
// writes only (half bufferable, no sweep): an exclusive write still gets its
// real EXOKAY, since only the subordinate can grant it (MAS 3.7.1: AWLOCK=1
// is never answered early, whatever AWCACHE[0] and EARLY_ALWAYS_EN say).
class aou_attr_test extends aou_dp_base_test;
  `uvm_component_utils(aou_attr_test)

  int          excl;
  int          early;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_attr_vseq";
  endfunction

  function void set_knobs();
    void'($value$plusargs("attr_excl=%d", excl));
    void'($value$plusargs("attr_early=%d", early));
    k.dir = AOU_T1_BOTH_DIRS;
    k.attr_sweep = 1'b1;
    k.lens = '{0, 1, 3, 7};
    k.n = 48;
    if (early != 0) begin
      k.feat = aou_t1_feature_cfg::type_id::create("feat");
      for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) k.feat.early_resp[r] = 1;
      // Writes only after the exclusive rounds, so no read races an early B.
      k.wr_pct = 100;
      k.attr_sweep = 1'b0;
      k.bufferable_pct = 50;
    end
    uvm_config_db#(bit)::set(null, "*", "attr_excl", excl != 0);
    uvm_config_db#(bit [3:0])::set(null, "*", "attr_excl_cache", (early != 0) ? 4'b0011 : 4'b0010);
  endfunction

  function void configure_test();
    cfg.l3_cfg.pol.prof_pct = 50;
  endfunction

  // TB gap, as in aou_early_bresp_test: the scoreboard compares remote memory
  // when B arrives, which an early B precedes; the end-of-test comparison stays.
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    if (early != 0) env.expects.add("AXI-S02", 0, 100000);
  endfunction
endclass
