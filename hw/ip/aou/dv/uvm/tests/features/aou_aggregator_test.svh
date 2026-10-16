// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Aggregator (plan 17.1-17.14; old F4-F6). +agg_en=0|1|per_rp programs
// RPn_AXI_AGGREGATOR_EN before activation; per_rp (17.13) enables it on a
// random half of the RPs (at least one on and one off), each RP checked
// against its own setting. Remote-originated narrow bursts
// (and single beats and full-width bursts, which are never aggregated) with
// random strobes, each read back; aou_agg_chk checks the M-port shapes and the
// scoreboard the bytes (WDATA/WSTRB merge, R split and RLAST regeneration).
// +agg_need=<beat bytes>:<RP bytes> makes the checker require that promotion
// (17.3: +dp_size=5 +agg_need=32:128 on a build with a 1024-bit RP).
class aou_aggregator_test extends aou_dp_base_test;
  `uvm_component_utils(aou_aggregator_test)

  aou_agg_chk chk;
  bit         agg_en[4] = '{1, 1, 1, 1};

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    string s;
    if ($value$plusargs("agg_en=%s", s)) begin
      if (s == "per_rp") begin
        int unsigned on = $urandom_range(AOU_T1_RP_COUNT - 1);
        if (AOU_T1_RP_COUNT < 2) `uvm_fatal(get_type_name(), "+agg_en=per_rp needs several RPs")
        foreach (agg_en[r]) agg_en[r] = 1'($urandom_range(1));
        // At least one RP each way: RP `on` enabled, the next one disabled.
        agg_en[on] = 1'b1;
        agg_en[(on + 1) % AOU_T1_RP_COUNT] = 1'b0;
      end else begin
        foreach (agg_en[r]) agg_en[r] = s.atoi() != 0;
      end
    end
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) k.feat.aggregator[r] = int'(agg_en[r]);
    k.dir = AOU_T1_R2L;
    k.sizes = '{0, 1, 2, 3, 4, 5, 6};
    k.lens = '{1, 3, 7, 15, 0};
    k.align = aou_dp_knobs::DP_ALIGN_ANY;
    k.strb = aou_dp_knobs::DP_STRB_RANDOM;
    k.loopback = 1'b1;
    k.batch = 4;
    k.wr_pct = 100;
    k.n = 42;
  endfunction

  function void build_phase(uvm_phase phase);
    string need;
    super.build_phase(phase);
    chk = aou_agg_chk::type_id::create("chk", this);
    chk.agg_en = agg_en;
    if ($value$plusargs("agg_need=%s", need)) begin
      int unsigned q[$];
      foreach (need[i]) if (need[i] == ":") need[i] = ",";
      if (aou_dp_knobs::parse_list(need, q) != 2)
        `uvm_fatal(get_type_name(), {"bad +agg_need=", need})
      chk.need_from = q[0];
      chk.need_to = q[1];
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    chk.rp_bytes = cfg.rp_bytes;
    env.rmgr.ap.connect(chk.orig_fifo.analysis_export);
    foreach (env.m_sub[r]) env.m_sub[r].ap.connect(chk.mport_fifo.analysis_export);
  endfunction
endclass
