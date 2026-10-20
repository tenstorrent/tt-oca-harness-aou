// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data width conversion (plan 2.14). The remote die's width per RP comes from
// +remote_bytes (one value, or one per RP), so one build with RPs of 256, 512
// and 1024 bits covers every upsize, downsize and bypass pairing. Both
// directions, every size up to each side's width, 1-16 beats, each batch
// read back (+dp_loopback): the scoreboard checks bytes end to end, the AXI
// monitors WLAST at the M port, L3 the ReadData DLENGTH per ARSIZE (AOU-R13),
// and aou_dw_chk replication of narrow read data, the DUT's WriteData
// DLENGTH and that every targeted conversion happened.
class aou_dw_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dw_test)

  aou_dw_chk chk;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    k.dir = AOU_T1_BOTH_DIRS;
    k.lens = '{0, 1, 3, 7, 15};
    k.strb = aou_dp_knobs::DP_STRB_MIXED;
    k.loopback = 1'b1;
    k.batch = 8;
    k.n = 64;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_dw_chk::type_id::create("chk", this);
    chk.n_rp = cfg.n_rp;
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      chk.rp_bytes[r] = cfg.rp_bytes[r];
      chk.remote_bytes[r] = cfg.remote_bytes_of(r);
    end
    chk.req_r2l = (k.dir != AOU_T1_L2R);
    chk.req_l2r = (k.dir != AOU_T1_R2L);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (env.s_mgr[r]) env.s_mgr[r].ap.connect(chk.loc_fifo.analysis_export);
    foreach (env.m_sub[r]) env.m_sub[r].ap.connect(chk.sub_fifo.analysis_export);
    env.l3.ap_rx_msg.connect(chk.dut_fifo.analysis_export);
    env.l3.ap_tx_msg.connect(chk.tb_fifo.analysis_export);
  endfunction
endclass

// The 1024-to-256-bit downsizer (plan 14.5) on its own: the remote die is
// 1024 bits wide on the 256-bit RPs and 512 bits on the others, so the
// unaligned AWSIZE=6 conversion (tenstorrent/tt-oca-harness-aou#90, fixed by RTL PR #89) is exercised
// here and nowhere else.
class aou_dw_down1024_test extends aou_dw_test;
  `uvm_component_utils(aou_dw_down1024_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Half the transfers at 512 bits (wider than the RP, narrower than the remote
  // die) and every start unaligned, so every seed exercises that conversion.
  function void set_knobs();
    super.set_knobs();
    // Seven sizes against six lengths: every pairing recurs, single-beat
    // narrow writes included (DP-R04).
    k.sizes = '{6, 7, 6, 5, 6, 3, 5};
    k.lens = '{0, 1, 3, 7, 15, 0};
    k.align = aou_dp_knobs::DP_ALIGN_UNALIGNED;
  endfunction

  function void configure_test();
    super.configure_test();
    for (int unsigned r = 0; r < cfg.n_rp; r++)
      cfg.rp_remote_bytes[r] = (cfg.rp_bytes[r] == 32) ? 128 : 64;
  endfunction
endclass
