// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Message packing (+dp_pack=wresp|crossflit|granule; plan 6.2, 6.9, 11.4,
// 11.6, 11.7). aou_msg_stats requires the targeted layout to occur:
// - wresp: many single-beat remote writes with zero-latency local B, so the
//   DUT packs several 1-granule WriteResp into one flit.
// - crossflit: mixed sizes and lengths with the L3 packer allowed to span
//   flits, so messages cross flit boundaries into and out of the DUT.
// - granule: 3-granule requests and 8-granule ReadData256 (reads of 32 B or
//   less) in both directions.
class aou_dp_packing_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dp_packing_test)

  string        pack = "wresp";
  aou_msg_stats stats;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    void'($value$plusargs("dp_pack=%s", pack));
    case (pack)
      "wresp": begin
        k.dir = AOU_T1_R2L;
        k.sizes = '{0, 1, 2, 3};
        k.lens = '{0};
        k.wr_pct = 100;
        k.num_slots = 32;
        k.n = 192;
      end
      "crossflit": begin
        k.lens = '{0, 1, 3, 7};
        k.strb = aou_dp_knobs::DP_STRB_MIXED;
        k.wr_pct = 50;
        k.n = 128;
      end
      "granule": begin
        k.sizes = '{0, 2, 4, 5};
        k.lens = '{0, 1};
        k.wr_pct = 50;
        k.n = 64;
      end
      default: `uvm_fatal(get_type_name(), {"bad +dp_pack=", pack})
    endcase
  endfunction

  function void configure_test();
    if (pack == "wresp")
      foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].timing.apply(AOU_AXI_TIMING_ZERO);
    if (pack == "crossflit") cfg.l3_cfg.pol.allow_span = 1'b1;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    stats = aou_msg_stats::type_id::create("stats", this);
    case (pack)
      "wresp":     stats.req_wresp_per_flit[0] = 2;
      "crossflit": begin
        stats.req_span[0] = 1;
        stats.req_span[1] = 1;
      end
      default: begin
        stats.req_granules[0] = '{3, 8};
        stats.req_granules[1] = '{3, 8};
      end
    endcase
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.l3.ap_rx_msg.connect(stats.dut_fifo.analysis_export);
    env.l3.ap_tx_msg.connect(stats.tb_fifo.analysis_export);
  endfunction
endclass
