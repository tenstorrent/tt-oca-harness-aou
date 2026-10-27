// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Configuration of the T1 environment. new() fills every agent config with
// the build's defaults; a test changes fields before the env's build_phase
// (aou_base_test::configure()).
class aou_t1_env_cfg extends uvm_object;
  `uvm_object_utils(aou_t1_env_cfg)

  int unsigned   n_rp = AOU_T1_RP_COUNT;
  int unsigned   remote_rp_count = 0;       // the remote die's RP count; 0 = n_rp (MAS 3.10.1)
  int unsigned   rp_bytes[];               // DUT AXI data bytes per RP
  int unsigned   remote_bytes = 64;        // remote die's AXI data width (WriteData DLENGTH)
  int unsigned   rp_remote_bytes[];        // per RP; 0 = remote_bytes
  aou_t1_rwreq_e remote_wreq = AOU_RWREQ_AWSIZE;  // remote WriteReq sizing (remote_mgr_driver)
  int unsigned   remote_max_burst = 256;   // remote splitter's longest burst (2^n beats)
  bit            remote_max_burst_rand = 1'b0;  // re-pick it while the remote is idle
  aou_spec_rev_e spec_rev = AOU_SPEC_V07;

  // Agent configs
  aou_fdi_cfg    fdi_cfg[AOU_T1_N_PHY];
  aou_lsm_cfg    lsm_cfg;
  aou_l3_cfg     l3_cfg;
  aou_axi_cfg    s_mgr_cfg[];              // local managers on the S ports
  aou_axi_cfg    m_sub_cfg[];              // local subordinates on the M ports
  aou_axi_cfg    r_mgr_cfg[];              // remote managers (through L3)
  aou_axi_cfg    remote_cfg;               // remote AXI model behind the L4a adapter
  aou_apb_cfg    apb_cfg;
  aou_mem        local_mem;                // shared by every M-port subordinate

  // Timing profiles applied at build (local agents; remote model latency)
  aou_axi_timing_e local_timing = AOU_AXI_TIMING_RANDOM;
  int unsigned     remote_lat_max = 20;

  // L1 stimulus of the flits L3 sends to the DUT
  int unsigned   l1_cancel_pct = 10;
  int unsigned   l1_bubble_pct = 10;
  int unsigned   l1_gap_pct = 10;
  bit            l1_cancel_mix = 1'b0;     // cancel plans over every shape, repeats included

  // System model on an FDI link-down (LinkReset, LinkError or Disabled,
  // whoever started it; a deactivation never takes the link down). The
  // owners' documents assign AOU_SW_RESET only to the
  // LinkReset AOU_CORE requests itself (MAS 7.3.6) and are silent on the
  // rest; AoU v0.8 reads as the interface state not surviving an FDI reset.
  // With this set, software or the system reset controller resets both dies
  // (AOU_SW_RESET, the remote die's reset) while the link is down, unless
  // both are cleanly DISABLED with no activation message pending or in
  // flight; the dies then activate again from DISABLED.
  // +sysrst_on_linkdown=0 turns it off (docs/DECISIONS.md D18).
  bit            sysrst_on_linkdown = 1'b1;

  // Check enables
  bit            sb_en = 1'b1;
  // aou_t1_attr_chk: request attributes, exclusive responses and FLEX across the link.
  bit            attr_chk_en = 1'b1;
  // The top instantiates AOU_FDI_CHECKER in single-PHY builds only.
  bit            fdi_chk_en = (AOU_T1_N_PHY == 1);
  bit            status_en = 1'b1;
  // Local software answers INT_ACTIVATE_START / INT_DEACTIVATE_START.
  bit            sw_isr_en = 1'b1;
  // Before DEACTIVATE_START the local software stops issuing (MAS 7.3.5);
  // 0 only in a negative test that declares what follows. Drain: it also
  // waits for every response first.
  bit            sw_hold_on_deact = 1'b1;
  // +v0p9draft: hold the DUT to expectations added after v0.7.1, which the
  // DUT implements; the peg is the v0.9 draft until that revision is
  // accepted. Today: the 4.4 Misc placement, AOU-R6 (an Activation message
  // shares its flit only with one CrdtGrant after an ActivateReq/Ack or with
  // responses after a DeactivateReq) and AOU-R7 (at most 2 other Misc per
  // half-flit). Further post-v0.7.1 DUT checks belong behind the same switch.
  bit            v0p9draft;
  bit            sw_drain_before_deact = 1'b0;
  // aou_t1_rx_fifo_chk (T1-C41, T1-L40, T1-L46) and the messages per RP and
  // class it allows past the RX FIFO (register slice, splitter, width converter).
  bit            rx_fifo_chk_en = 1'b1;
  int unsigned   rx_fifo_slack = 8;

  // aou_t1_crd_flow_chk bounds, in cycles the Adapter takes a beat: a credit
  // class may stall this long while an RP has credit and work for it and another
  // RP is starved (T1-C01; covers the TX pipeline and a flit boundary), or at
  // all (T1-C02). +crd_block_cycles / +crd_idle_cycles override them.
  int unsigned   crd_block_cycles = 256;
  int unsigned   crd_idle_cycles = 4096;
  // The per-RP wait of a class (T1-C43): cycles the Adapter takes a beat and
  // no AXI port holds the DUT back, in which an RP holds credit and work for
  // the class and is next in its order, without a message of the class on
  // that RP. The longest wait seen over the stress, link and datapath lists on
  // every config, with extra seeds of the long-burst and backpressure
  // scenarios, was about 250 cycles (a WriteResp); most classes stay under 50.
  // +crd_starve_cycles overrides it.
  int unsigned   crd_starve_cycles = 500;

  // Time-outs in core clock cycles
  int unsigned   link_timeout = 20000;
  int unsigned   act_timeout = 20000;
  int unsigned   drain_timeout = 200000;

  function new(string name = "aou_t1_env_cfg");
    super.new(name);
    lsm_cfg = aou_lsm_cfg::type_id::create("lsm_cfg");
    lsm_cfg.n_phy = AOU_T1_N_PHY;
    // The Adapter answers the DUT's lp_linkerror by itself, as a UCIe Adapter
    // does (react_linkerror_en, on by default in aou_lsm_cfg); +react_linkerror=0
    // leaves it to the test's recover().
    foreach (fdi_cfg[p]) begin
      fdi_cfg[p] = aou_fdi_cfg::type_id::create($sformatf("fdi_cfg%0d", p));
      fdi_cfg[p].phy = p;
      fdi_cfg[p].beat_bytes = p == 0 ? AOU_T1_BEAT0 : AOU_T1_BEAT1;
      fdi_cfg[p].trdy_policy = AOU_TRDY_HOLES;
    end
    l3_cfg = aou_l3_cfg::type_id::create("l3_cfg");
    // L3 hands a write to L4a only once all its WriteData arrived, so with
    // on-consume return a burst longer than the WDATA buffer could never
    // complete. A real remote die streams W beats; model that buffer as
    // returning WDATA credits on receipt.
    l3_cfg.ret_policy[AOU_CC_WDATA] = AOU_RET_IMMEDIATE;
    apb_cfg = aou_apb_cfg::type_id::create("apb_cfg");
    local_mem = aou_mem::type_id::create("local_mem");
    remote_cfg = aou_axi_cfg::type_id::create("remote_cfg");
    remote_cfg.vif_key = "s_axi0";
    remote_cfg.mem = aou_mem::type_id::create("remote_mem");
    set_rp_count(n_rp);
  endfunction

  // (Re)creates the per-RP configs for n RPs.
  function void set_rp_count(int unsigned n);
    n_rp = n;
    rp_bytes = new[n];
    rp_remote_bytes = new[n];
    s_mgr_cfg = new[n];
    m_sub_cfg = new[n];
    r_mgr_cfg = new[n];
    for (int unsigned r = 0; r < n; r++) begin
      rp_bytes[r] = aou_t1_rp_bytes(r);
      s_mgr_cfg[r] = aou_axi_cfg::type_id::create($sformatf("s_mgr_cfg%0d", r));
      s_mgr_cfg[r].vif_key = $sformatf("s_axi%0d", r);
      s_mgr_cfg[r].rp = r;
      s_mgr_cfg[r].incr_only = 1'b1;
      m_sub_cfg[r] = aou_axi_cfg::type_id::create($sformatf("m_sub_cfg%0d", r));
      m_sub_cfg[r].vif_key = $sformatf("m_axi%0d", r);
      m_sub_cfg[r].rp = r;
      m_sub_cfg[r].mem = local_mem;
      r_mgr_cfg[r] = aou_axi_cfg::type_id::create($sformatf("r_mgr_cfg%0d", r));
      r_mgr_cfg[r].vif_key = "";
      r_mgr_cfg[r].rp = r;
      r_mgr_cfg[r].local_side = 1'b0;
    end
  endfunction

  // Pushes the shared settings into the agent configs. The env calls it at
  // build, after the test has configured.
  function void finalize();
    // The remote die is no wider than the widest AoU data message (1024 bits).
    if (remote_bytes > AOU_T1_PEER_MAX_BYTES) begin
      `uvm_info(get_type_name(), $sformatf("remote die %0d bytes wide, limited to the peer's %0d",
                                           remote_bytes, AOU_T1_PEER_MAX_BYTES), UVM_LOW)
      remote_bytes = AOU_T1_PEER_MAX_BYTES;
    end
    foreach (rp_remote_bytes[r])
      if (rp_remote_bytes[r] > AOU_T1_PEER_MAX_BYTES) rp_remote_bytes[r] = AOU_T1_PEER_MAX_BYTES;
    l3_cfg.spec_rev = spec_rev;
    l3_cfg.rp_count = (remote_rp_count != 0) ? remote_rp_count : n_rp;
    l3_cfg.peer_rp_count = n_rp;
    // The credit the DUT may advertise (MAS 3.9) on the RPs both dies have.
    foreach (l3_cfg.dut_max_cred[r, c])
      l3_cfg.dut_max_cred[r][c] = (r < l3_cfg.eff_rp_count()) ? aou_t1_rx_max_credit(r, c) : 0;
    remote_cfg.data_bytes = remote_bytes;
    remote_cfg.timing.b_lat.set_range(0, remote_lat_max);
    remote_cfg.timing.r_lat.set_range(0, remote_lat_max);
    for (int unsigned r = 0; r < n_rp; r++) begin
      s_mgr_cfg[r].data_bytes = rp_bytes[r];
      m_sub_cfg[r].data_bytes = rp_bytes[r];
      m_sub_cfg[r].mem = local_mem;
      r_mgr_cfg[r].data_bytes = remote_bytes_of(r);
    end
  endfunction

  // The remote die's AXI data bytes on RP r.
  function int unsigned remote_bytes_of(int unsigned r);
    return (r < rp_remote_bytes.size() && rp_remote_bytes[r] != 0) ? rp_remote_bytes[r] :
                                                                     remote_bytes;
  endfunction

  // "N" sets remote_bytes; "N0,N1,..." sets rp_remote_bytes per RP.
  function void set_remote_bytes(string s);
    int unsigned q[$];
    int start = 0;
    for (int i = 0; i <= s.len(); i++) begin
      if (i == s.len() || s[i] == ",") begin
        if (i > start) q.push_back(s.substr(start, i - 1).atoi());
        start = i + 1;
      end
    end
    foreach (q[i])
      if (!(q[i] inside {32, 64, 128}))
        `uvm_fatal(get_type_name(), $sformatf("remote bytes %0d not 32, 64 or 128 (%s)", q[i], s))
    if (q.size() == 1) remote_bytes = q[0];
    else foreach (rp_remote_bytes[r]) if (r < q.size()) rp_remote_bytes[r] = q[r];
  endfunction

  // L1 corner knobs from the command line (stall and flit-cancel corners, plan
  // 18.22/18.24): +fdi_trdy=always|random|holes|bursty, +fdi_stall_pct,
  // +fdi_stall_mid_pct, +fdi_stall_trdy_free=0|1 (every PHY), +l1_cancel_pct,
  // +l1_cancel_mix=0|1.
  function void l1_plusargs();
    string s;
    int unsigned v;
    if ($value$plusargs("fdi_trdy=%s", s)) begin
      aou_fdi_trdy_e t;
      case (s)
        "always": t = AOU_TRDY_ALWAYS;
        "random": t = AOU_TRDY_RANDOM;
        "holes":  t = AOU_TRDY_HOLES;
        "bursty": t = AOU_TRDY_BURSTY;
        default:  `uvm_fatal(get_type_name(), {"+fdi_trdy: unknown policy ", s})
      endcase
      foreach (fdi_cfg[p]) fdi_cfg[p].trdy_policy = t;
    end
    if ($value$plusargs("fdi_stall_pct=%d", v)) foreach (fdi_cfg[p]) fdi_cfg[p].stall_pct = v;
    if ($value$plusargs("fdi_stall_mid_pct=%d", v))
      foreach (fdi_cfg[p]) fdi_cfg[p].stall_mid_pct = v;
    if ($value$plusargs("fdi_stall_trdy_free=%d", v))
      foreach (fdi_cfg[p]) fdi_cfg[p].stall_trdy_free = v != 0;
    void'($value$plusargs("l1_cancel_pct=%d", l1_cancel_pct));
    if ($value$plusargs("l1_cancel_mix=%d", v)) l1_cancel_mix = v != 0;
  endfunction

  // Random choices a test usually wants per seed.
  function void randomize_knobs();
    local_timing = aou_axi_timing_e'($urandom_range(4));
    for (int unsigned r = 0; r < n_rp; r++) begin
      s_mgr_cfg[r].timing.apply(local_timing);
      m_sub_cfg[r].timing.apply(local_timing);
      s_mgr_cfg[r].w_before_aw_en = 1'($urandom_range(1));
      m_sub_cfg[r].r_interleave_en = 1'($urandom_range(1));
    end
    l3_cfg.resp_fork = 1'($urandom_range(1));
    remote_lat_max = $urandom_range(30);
  endfunction

  function string convert2string();
    return $sformatf({"n_rp=%0d remote_rp_count=%0d rp_bytes=%p remote_bytes=%0d ",
                      "rp_remote_bytes=%p phy=%0d/%0d ",
                      "spec=%s timing=%s remote_lat<=%0d resp_fork=%0b ",
                      "l1 cancel/bubble=%0d/%0d"},
                     n_rp, remote_rp_count, rp_bytes, remote_bytes, rp_remote_bytes,
                     lsm_cfg.active_phy,
                     lsm_cfg.n_phy, spec_rev.name(),
                     local_timing.name(), remote_lat_max, l3_cfg.resp_fork, l1_cancel_pct,
                     l1_bubble_pct);
  endfunction
endclass
