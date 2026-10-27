// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Flit packing in both directions (plan 6.3-6.8, 6.14, 6.18-6.21, 11.1, 11.2,
// 11.5, 11.9, 11.14). The remote die's L3 packer runs non-DUT-like policies;
// aou_pack_stats reports targeted layouts that did not occur (coverage, not
// an error), and the scoreboard and L3 rule checks judge them. +pk=:
//   crossflit  every L3 data message longer than split_at (1-7) is forced
//              across the flit boundary; sizes 256/512/1024 (+remote_bytes)
//   mixed      sparse layout (holes, random order, mixed credit grants) with
//              L3 backlog bursts: WriteReq + ReadReq + WriteResp in one flit
//   single     one message per flit, MsgStart at a random granule 1-18
//   full       best-fit packing with backlog bursts: flits filled to G47
//   wresp48    remote reads of nothing but WriteResp backlog: 48 in one flit
//   rp         multi-RP builds: messages of several RPs in one flit
//   act        activation cycles with traffic, two zero CrdtGrants per half
//   crdt       credits only through CrdtGrant messages, plus zero grants
//   b2b        no idle cycles on FDI either way (trdy always, no gaps)
//   prof       random PROF (FLEX[11:0]) in AXI messages to the DUT
class aou_pack_test extends aou_dp_base_test;
  `uvm_component_utils(aou_pack_test)

  string         pk = "crossflit";
  aou_pack_stats stats;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_pack_vseq";
  endfunction

  function void set_knobs();
    void'($value$plusargs("pk=%s", pk));
    k.dir = AOU_T1_BOTH_DIRS;
    k.wr_pct = 50;
    case (pk)
      "crossflit": begin
        k.sizes = '{5, 6, 7};
        k.lens = '{0, 1, 3};
        // The DUT's ReadData256 crossing a flit (TX:span_R8) comes from its own
        // packing, 1-9 times in 96 transactions, and none in one seed once the
        // remote die's Activation travels alone (v0.8 4.4); 128 gives margin.
        k.n = 128;
      end
      "mixed", "full": begin
        k.sizes = '{0, 2, 4, 6};
        k.lens = '{0, 1};
        k.n = 128;
      end
      "wresp48": begin
        k.dir = AOU_T1_L2R;
        k.sizes = '{0, 3};
        k.lens = '{0};
        k.wr_pct = 100;
        k.num_slots = 64;
        k.n = 256;
      end
      "single": begin
        k.lens = '{0, 1, 3};
        k.n = 48;
      end
      "b2b": begin
        k.sizes = '{6};
        k.lens = '{7, 15};
        k.align = aou_dp_knobs::DP_ALIGN_ALIGNED;
        k.num_slots = 32;
        k.n = 64;
      end
      "rp", "act", "crdt", "prof": begin
        k.lens = '{0, 1, 3};
        k.n = 48;
      end
      default: `uvm_fatal(get_type_name(), {"bad +pk=", pk})
    endcase
  endfunction

  function void configure_test();
    aou_packer_policy pol = cfg.l3_cfg.pol;
    case (pk)
      "crossflit": pol.split_at = $urandom_range(7, 1);
      "mixed": pol.set_sparse();
      "single": begin
        pol.set_min_density();
        pol.start_granule = $urandom_range(18, 1);
      end
      "full", "wresp48": begin
        pol.best_fit = 1'b1;
        pol.allow_span = 1'b0;
      end
      "act": begin
        pol.zero_grants = 2;
        pol.cred_method = AOU_CRM_MIXED;
      end
      "crdt": begin
        pol.cred_method = AOU_CRM_GRANT;
        pol.zero_grants = 1;
      end
      "b2b": begin
        foreach (cfg.fdi_cfg[p]) cfg.fdi_cfg[p].trdy_policy = AOU_TRDY_ALWAYS;
        cfg.l1_cancel_pct = 0;
        cfg.l1_gap_pct = 0;
        cfg.l1_bubble_pct = 0;
        cfg.remote_lat_max = 0;
        foreach (cfg.s_mgr_cfg[r]) begin
          cfg.s_mgr_cfg[r].timing.apply(AOU_AXI_TIMING_ZERO);
          cfg.m_sub_cfg[r].timing.apply(AOU_AXI_TIMING_ZERO);
        end
      end
      "prof": pol.prof_pct = 50;
      default: ;
    endcase
    if (pk == "wresp48")
      foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].timing.apply(AOU_AXI_TIMING_ZERO);
    if (pk == "rp" && cfg.n_rp < 2) `uvm_fatal(get_type_name(), "+pk=rp needs a multi-RP CONFIG")
    `uvm_info(get_type_name(), {"L3 policy: ", pol.convert2string()}, UVM_LOW)
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    stats = aou_pack_stats::type_id::create("stats", this);
    case (pk)
      "crossflit": begin
        // ReadData follows ARSIZE (spec 5.7); the remote die's width bounds
        // its ARSIZE and the WriteData it sends, the local RPs' widths bound
        // the DUT's. The DUT's WriteData DLENGTH is its RP width, so a build
        // without a 512-bit RP sends no WriteData512.
        int unsigned max_b = 0;
        bit has_512 = 1'b0;
        foreach (cfg.rp_bytes[r]) begin
          if (cfg.rp_bytes[r] > max_b) max_b = cfg.rp_bytes[r];
          if (cfg.rp_bytes[r] == 64) has_512 = 1'b1;
        end
        stats.req = '{"RX:span_R8"};
        if (max_b >= 64) stats.req.push_back("RX:span_R14");
        stats.req.push_back(has_512 ? "TX:span_W15" : "TX:span_wdata");
        // The env limits the remote die to the 1024-bit AoU maximum,
        // AOU_T1_PEER_MAX_BYTES (aou_t1_env_cfg::finalize(), after this), so the
        // layouts follow that width.
        case ((cfg.remote_bytes > AOU_T1_PEER_MAX_BYTES) ? AOU_T1_PEER_MAX_BYTES
                                                         : cfg.remote_bytes)
          32:      stats.req = {stats.req, "RX:span_W8", "TX:span_R8"};
          128:     stats.req = {stats.req, "RX:span_W30", "TX:span_R27"};
          default: stats.req = {stats.req, "RX:span_W15", "TX:span_R14"};
        endcase
      end
      "mixed":   stats.req = '{"RX:mixed_bubble"};
      "single":  stats.req = '{"RX:single_off>=10", "TX:single"};
      "full":    stats.req = '{"RX:full", "TX:full"};
      "wresp48": stats.req = '{"RX:wresp_max>=48"};
      "rp":      stats.req = '{"RX:multi_rp", "TX:multi_rp"};
      "act":     stats.req = '{"RX:misc2_half", "RX:act>=4", "TX:act>=4"};
      "crdt":    stats.req = '{"RX:crdt>=20", "TX:crdt"};
      "b2b":     stats.req = '{"RX:b2b_run>=8", "TX:b2b_run>=8"};
      "prof":    stats.req = '{"RX:prof>=20"};
      default: ;
    endcase
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.l3.ap_rx_msg.connect(stats.dut_fifo.analysis_export);
    env.l3.ap_tx_msg.connect(stats.tb_fifo.analysis_export);
    // Only one PHY carries flits at a time; in two-PHY builds it can be either.
    foreach (env.fdi[p]) begin
      env.fdi[p].mon.ap_tx.connect(stats.l1_tx_imp);
      env.fdi[p].mon.ap_rx.connect(stats.l1_rx_imp);
    end
  endfunction
endclass
