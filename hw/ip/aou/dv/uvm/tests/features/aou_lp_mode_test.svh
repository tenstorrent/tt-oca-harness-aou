// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power mode (plan 21.1-21.6; old F7). +lp_mode=0|1 and +lp_thr=T
// (default: random 1..255 when +lp_mode=1) are programmed before activation;
// aou_lp_mode_vseq counts idle flits from the L1 monitor. Traffic both ways
// before and after the idle window, so credits are returned in LP mode (21.6).
class aou_lp_mode_test extends aou_dp_base_test;
  `uvm_component_utils(aou_lp_mode_test)

  aou_flit_counter cnt;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_lp_mode_vseq";
  endfunction

  function void set_knobs();
    int lp = 0;
    int thr = -1;
    void'($value$plusargs("lp_mode=%d", lp));
    void'($value$plusargs("lp_thr=%d", thr));
    if (thr < 0) thr = (lp != 0) ? $urandom_range(255, 1) : 4;
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    k.feat.lp_mode = lp;
    k.feat.lp_threshold = thr;
    k.lens = '{0, 1, 3};
    k.wr_pct = 50;
    k.n = 32;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cnt = aou_flit_counter::type_id::create("cnt", this);
    uvm_config_db#(aou_flit_counter)::set(null, "*", "lp_flit_counter", cnt);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Two-PHY builds pick the active PHY per seed; the idle flits go out on it.
    env.fdi[cfg.lsm_cfg.active_phy].mon.ap_tx.connect(cnt.analysis_export);
  endfunction
endclass
