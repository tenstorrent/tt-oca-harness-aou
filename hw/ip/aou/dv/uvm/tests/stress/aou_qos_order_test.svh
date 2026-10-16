// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// QoS arbitration order with a TX backlog (plan 13.1-13.3, 13.5-13.11,
// 13.14-13.18, 13.20-13.22; rules FEAT-R11..R14). Multi-RP builds only. Plusargs:
//   +arb_mode=0|1|2      round-robin, Port QoS, AXI QoS
//   +qos_tiers=3|2|eq|eq01  three RPs on high/normal/low, two RPs on high/low,
//                        two RPs on one tier (round-robin among equals), or
//                        two RPs with PRIOR 0 and PRIOR 1 (one tier: 0 reads as 1)
//   +qos_prior0=1        every low-tier RP (tier 1) programmed with PRIOR 0
//   +qos_timer=off|promote|sweep|thr0|res0|max  starvation timer far beyond
//                        the test, short enough to promote the low tier, a
//                        random one of the two, or the extremes: THRESHOLD 0
//                        (promotes at once), RESOLUTION 0 with a short
//                        threshold (promotes), THRESHOLD 0xFFFF (never within
//                        the test)
//   +qos_bounds=1|inv    random AXI_QOS_TO_HP > AXI_QOS_TO_NP, or HP at or
//                        below NP (empty Normal tier; arb_mode 2, two tiers)
//   +qos_rounds=N
class aou_qos_order_test extends aou_dp_base_test;
  `uvm_component_utils(aou_qos_order_test)

  aou_qos_order_chk chk;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_qos_order_vseq";
    use_dp_seq = 1'b0;
  endfunction

  function void set_knobs();
    k.dir = AOU_T1_L2R;
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
  endfunction

  function void configure();
    super.configure();
    if (cfg.n_rp < 2) `uvm_fatal(get_type_name(), "needs a multi-RP CONFIG (4x512-sp64)")
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_qos_order_chk::type_id::create("chk", this);
    uvm_config_db#(aou_qos_order_chk)::set(null, "*", "qos_chk", chk);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.l3.ap_rx_msg.connect(chk.fifo.analysis_export);
  endfunction
endclass
