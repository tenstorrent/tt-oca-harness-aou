// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Zero credit for one class (port of aou_zero_{wreq,rreq,wdata,rdata,wresp}
// _credit_test). The remote die advertises no credit of that class at
// activation; traffic that needs it must stay queued in the DUT, never sent
// without credit (AOU-R16, checked by the model) and never dropped. After
// +hold cycles the remote die grants +grant credits and everything completes
// with correct data.
// Knobs: +credit=wreq|rreq|wdata|rdata|wresp (random) +hold=<cycles>
// +grant=<credits> +T1_TXN=<transactions>.
// +starve_rp=<r> (plan 3.15/12.14): only RP r has no credit of the class;
// traffic runs on every RP, and the others' may complete while RP r's stays
// queued.
// +limit=<k> with +credit=wreq|rreq (plan 8.3/8.6): every RP gets credit for
// exactly k requests and the remote die returns none of it until released,
// with more than k requests queued per RP.
// +limit=<k> with +credit=wdata: WDATA credit for k WriteData messages of the
// widest RP, none returned until released, and every write at least k+1 beats
// long: the DUT commits each RP's first WriteReq and then runs out of WDATA
// credit with that write's data still owed, by a known number of beats.
// +hold_wreq_rp=<r>: remote-to-DUT writes on every RP; for +hold cycles the
// remote die sends no WriteReq on RP r while that RP's WriteData still goes on
// WDATA credit, so the data of several writes waits in the DUT's RX W FIFO
// ahead of their WriteReqs (AoU v0.8 5.7 does not order them). Then the
// WriteReqs go and every write completes with correct data.
// +fair=1: DUT TX write fairness. Local writes only, the managers presenting
// with no gaps: RP +fair_short (default 0) issues single-beat writes only,
// RP +fair_long (default 1) bursts of AWLEN +fair_min..+fair_max (31..63);
// +fair_short_n and +fair_long_n writes (400 and 40).
// A burst the DUT has committed must not be held open by the stream of short
// writes. aou_t1_crd_flow_chk checks that it keeps making progress while it
// holds credit and is next in write-data order (T1-C43); it does not bound how
// long the short writes may slow a burst that still trickles.
// aou_t1_crd_flow_chk judges both in every test: an RP with credit and queued
// work keeps sending while another RP has none (T1-C01), the DUT uses all the
// credit it holds (T1-C02), never more (AOU-R16, the L3 model).
// +deact=1 (plan 2.5; MAS 7.3.3): with the traffic still queued for want of
// credit, software sets DEACTIVATE_START, and the grant comes +deact_hold
// cycles later. Messages waiting for credit remain to be transmitted (MAS
// 7.1): requests must still go out before the DUT's DeactivateReq (AOU-R34,
// AOU-R33 in the L3 model), responses to the remote die before DISABLED, and
// every transaction completes (scoreboard).
class aou_zero_credit_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_zero_credit_vseq)

  // WriteReq and ReadReq are 3 granules (Tables 2 and 4).
  static const int unsigned REQ_GRANULES = 3;

  protected bit others_done;
  protected bit deact_done;

  function new(string name = "aou_zero_credit_vseq");
    super.new(name);
  endfunction

  task body();
    string names[5] = '{"wreq", "rreq", "wdata", "rdata", "wresp"};
    aou_cred_class_e c = class_of(arg_str("credit", names[$urandom_range(4)]));
    int starve = arg_int("starve_rp", -1);
    int unsigned limit = arg_int("limit", 0);
    int hold_rp = arg_int("hold_wreq_rp", -1);
    if (arg_int("fair", 0) != 0) begin
      fair_bursts();
      return;
    end
    if (hold_rp >= 0) begin
      hold_wreq(hold_rp);
      return;
    end
    if (starve >= 0) begin
      starve_one(c, starve);
      return;
    end
    if (limit != 0) begin
      credit_limit(c, limit);
      return;
    end
    zero_all(c);
  endtask

  // DUT requests and write data need traffic from the local side; its
  // read data and write responses answer requests from the remote side.
  function aou_t1_dir_e dir_for(aou_cred_class_e c);
    return (c inside {AOU_CC_RDATA, AOU_CC_WRESP}) ? AOU_T1_R2L : AOU_T1_L2R;
  endfunction

  function aou_t1_traffic_cfg profile_for(aou_cred_class_e c);
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
    p.wr_pct = (c inside {AOU_CC_RREQ, AOU_CC_RDATA}) ? 0 : 100;
    return p;
  endfunction

  function int unsigned default_grant(aou_cred_class_e c);
    // Enough for the largest message of the class at 512 bits (Tables 2-13).
    return (c inside {AOU_CC_WRESP, AOU_CC_WREQ, AOU_CC_RREQ}) ? 8 : 64;
  endfunction

  task grant_rp(aou_cred_class_e c, int unsigned r, int unsigned n);
    aou_l3_overgrant_seq g = aou_l3_overgrant_seq::type_id::create("g");
    g.cls = c;
    g.n = n;
    g.rp = 2'(r);
    g.start(p_sequencer.l3_sqr);
  endtask

  task starve_one(aou_cred_class_e c, int unsigned sr);
    int unsigned hold = arg_int("hold", 2000);
    int unsigned grant = arg_int("grant", default_grant(c));
    int unsigned wait_max = arg_int("others_max", 50000);
    aou_t1_dir_e dir = dir_for(c);
    aou_t1_traffic_cfg ps = profile_for(c);
    aou_t1_traffic_cfg po = profile_for(c);
    int unsigned n = 0;
    if (cfg.n_rp < 2) `uvm_fatal(get_type_name(), "+starve_rp needs a build with several RPs")
    if (sr >= cfg.n_rp)
      `uvm_fatal(get_type_name(), $sformatf("+starve_rp=%0d, build has %0d RPs", sr, cfg.n_rp))
    ps.rp_mask = 4'(1 << sr);
    po.rp_mask = 4'((1 << cfg.n_rp) - 1) & ~ps.rp_mask;
    `uvm_info(get_type_name(), $sformatf("RP%0d has no %s credit, %s traffic on every RP",
                                         sr, aou_cc_name(c), dir.name()), UVM_LOW)
    link_up();
    cfg.l3_cfg.rx_starve[sr][c] = 1'b1;
    env.l3.model.crd.reset_link();
    sw_activate();
    others_done = 1'b0;
    traffic_nb(dir, num_txns, ps);
    fork
      begin
        traffic(dir, num_txns, po);
        others_done = 1'b1;
      end
    join_none
    while (!others_done && n < wait_max) begin
      wait_cycles(1);
      n++;
    end
    wait_cycles(hold);
    if (!others_done)
      `uvm_info(get_type_name(), $sformatf("RPs %4b did not complete in %0d cycles", po.rp_mask,
                                           wait_max), UVM_LOW)
    if (n_traffic == 0)
      `uvm_error(get_type_name(), $sformatf("T1-L11: RP%0d traffic completed with no %s credit",
                                            sr, aou_cc_name(c)))
    if (env.l3.model.crd.rx_outstanding[sr][c] != 0)
      `uvm_error(get_type_name(), $sformatf(
          "T1-L12: %0d %s credits outstanding on RP%0d, none granted",
          env.l3.model.crd.rx_outstanding[sr][c], aou_cc_name(c), sr))
    cfg.l3_cfg.rx_starve[sr][c] = 1'b0;
    grant_rp(c, sr, grant);
    wait_traffic();
    wait (others_done);
    drain();
    sw_deactivate();
  endtask

  // Granules of a full-width WriteData the DUT sends for local RP r (Tables 5-7).
  function int unsigned wdata_granules(int unsigned r);
    return cfg.rp_bytes[r] <= 32 ? 8 : cfg.rp_bytes[r] <= 64 ? 15 : 30;
  endfunction

  task credit_limit(aou_cred_class_e c, int unsigned k);
    int unsigned hold = arg_int("hold", 3000);
    aou_t1_traffic_cfg p = profile_for(c);
    aou_cred_ret_e ret = cfg.l3_cfg.ret_policy[c];
    int unsigned n = num_txns;
    int unsigned unit = REQ_GRANULES;
    int unsigned used[AOU_RP_MAX];
    if (!(c inside {AOU_CC_WREQ, AOU_CC_RREQ, AOU_CC_WDATA}))
      `uvm_fatal(get_type_name(), "+limit needs +credit=wreq, +credit=rreq or +credit=wdata")
    if (c == AOU_CC_WDATA) begin
      // Credit for k WriteData messages of the widest RP; every write is longer.
      for (int unsigned r = 0; r < cfg.n_rp; r++)
        if (wdata_granules(r) > unit) unit = wdata_granules(r);
      p.min_len = 8'(k);
      p.max_len = 8'(k + 8);
      p.wr_pct = 100;
      if (n < 8) n = 8;
      p.num_slots = n;
    end else begin
      // Every RP must queue more requests than its credit covers.
      if (n < k + 4) n = k + 4;
      p.num_slots = n;
      p.max_len = 0;
    end
    `uvm_info(get_type_name(), $sformatf("%s credit for %0d messages (%0d granules) per RP, %0d %s",
                                         aou_cc_name(c), k, k * unit, n,
                                         c == AOU_CC_WDATA ? "writes of more beats per RP" :
                                         "queued per RP"), UVM_LOW)
    link_up();
    cfg.l3_cfg.rx_depth[c] = k * unit;
    cfg.l3_cfg.ret_policy[c] = AOU_RET_WITHHELD;
    env.l3.model.crd.reset_link();
    sw_activate();
    traffic_nb(AOU_T1_L2R, n, p);
    wait_cycles(hold);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      int unsigned left = env.l3.model.crd.rx_outstanding[r][c];
      used[r] = k * unit - left;
      `uvm_info(get_type_name(), $sformatf(
                "RP%0d: %0d of %0d granules of %s credit used, %0d left", r, used[r], k * unit,
                aou_cc_name(c), left), UVM_LOW)
    end
    if (n_traffic == 0)
      `uvm_error(get_type_name(), $sformatf("T1-L11: traffic completed on %0d %s credits",
                                            k, aou_cc_name(c)))
    cfg.l3_cfg.ret_policy[c] = ret;
    env.l3.model.release_withheld();
    // The model frees a write's WDATA credit only once the whole write has
    // arrived, which these writes cannot do on k messages: return what was
    // used, as a die that frees each beat on receipt would have.
    if (c == AOU_CC_WDATA)
      for (int unsigned r = 0; r < cfg.n_rp; r++) if (used[r] != 0) grant_rp(c, r, used[r]);
    wait_traffic();
    drain();
    sw_deactivate();
  endtask

  task hold_wreq(int unsigned hr);
    int unsigned hold = arg_int("hold", 3000);
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
    bit [AOU_RP_MAX-1:0] hold0 = cfg.l3_cfg.pol.hold_wreq_rps;
    int unsigned n = num_txns;
    if (hr >= cfg.n_rp)
      `uvm_fatal(get_type_name(), $sformatf("+hold_wreq_rp=%0d, build has %0d RPs", hr, cfg.n_rp))
    p.wr_pct = 100;
    p.max_len = 8'(arg_int("hold_max_len", 7));
    if (n < 16) n = 16;
    `uvm_info(get_type_name(), $sformatf(
              "remote WriteReqs on RP%0d held for %0d cycles while their WriteData goes", hr,
              hold), UVM_LOW)
    link_up();
    sw_activate();
    cfg.l3_cfg.pol.hold_wreq_rps[cfg.l3_cfg.dest_rp[hr]] = 1'b1;
    traffic_nb(AOU_T1_R2L, n, p);
    wait_cycles(hold);
    if (n_traffic == 0)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-L11: remote writes on RP%0d completed with their WriteReqs held", hr))
    cfg.l3_cfg.pol.hold_wreq_rps = hold0;
    env.l3.model.kick();
    wait_traffic();
    drain();
    sw_deactivate();
  endtask

  task fair_bursts();
    int unsigned rs = arg_int("fair_short", 0);
    int unsigned rl = arg_int("fair_long", 1);
    int unsigned lo = arg_int("fair_min", 31);
    int unsigned hi = arg_int("fair_max", 63);
    aou_t1_traffic_cfg ps = aou_t1_traffic_cfg::named("rand");
    aou_t1_traffic_cfg pl = aou_t1_traffic_cfg::named("rand");
    if (cfg.n_rp < 2) `uvm_fatal(get_type_name(), "+fair needs a build with several RPs")
    if (rs >= cfg.n_rp || rl >= cfg.n_rp || rs == rl)
      `uvm_fatal(get_type_name(), $sformatf("+fair_short=%0d +fair_long=%0d on %0d RPs", rs, rl,
                                            cfg.n_rp))
    ps.wr_pct = 100;
    ps.max_len = 0;
    ps.num_slots = 32;
    ps.rp_mask = 4'(1 << rs);
    pl.wr_pct = 100;
    pl.min_len = 8'(lo);
    pl.max_len = 8'(hi);
    pl.num_slots = 8;
    pl.rp_mask = 4'(1 << rl);
    `uvm_info(get_type_name(), $sformatf(
              "write fairness: RP%0d single-beat writes, RP%0d bursts of AWLEN %0d..%0d", rs, rl,
              lo, hi), UVM_LOW)
    link_up();
    sw_activate();
    // The managers present every beat at once and take responses at once,
    // for both streams together (a profile's own timing ends with its stream).
    apply_timing(AOU_AXI_TIMING_ZERO, 0);
    traffic_nb(AOU_T1_L2R, arg_int("fair_short_n", 400), ps);
    traffic_nb(AOU_T1_L2R, arg_int("fair_long_n", 40), pl);
    wait_traffic();
    apply_timing(cfg.local_timing, cfg.remote_lat_max);
    drain();
    sw_deactivate();
  endtask

  task zero_all(aou_cred_class_e c);
    int unsigned depth0;
    int unsigned hold = arg_int("hold", 2000);
    int unsigned grant = arg_int("grant", default_grant(c));
    aou_t1_dir_e dir = dir_for(c);
    aou_t1_traffic_cfg p = profile_for(c);
    `uvm_info(get_type_name(), $sformatf("zero %s credit, %s traffic, grant %0d after %0d cycles",
                                         aou_cc_name(c), dir.name(), grant, hold), UVM_LOW)
    link_up();
    // The modelled RX buffer of class c is empty of credit from the start.
    depth0 = cfg.l3_cfg.rx_depth[c];
    cfg.l3_cfg.rx_depth[c] = 0;
    env.l3.model.crd.reset_link();
    sw_activate();
    traffic_nb(dir, num_txns, p);
    wait_cycles(hold);
    if (n_traffic == 0)
      `uvm_error(get_type_name(), $sformatf("T1-L11: traffic completed with no %s credit",
                                            aou_cc_name(c)))
    if (env.l3.model.crd.rx_outstanding[0][c] != 0)
      `uvm_error(get_type_name(), $sformatf("T1-L12: %0d %s credits outstanding, none granted",
                                            env.l3.model.crd.rx_outstanding[0][c],
                                            aou_cc_name(c)))
    if (arg_int("deact", 0) != 0) begin
      deact_pending(c, grant, depth0);
      return;
    end
    for (int unsigned r = 0; r < cfg.n_rp; r++) grant_rp(c, r, grant);
    wait_traffic();
    drain();
    sw_deactivate();
  endtask

  task deact_pending(aou_cred_class_e c, int unsigned grant, int unsigned depth0);
    int unsigned dhold = arg_int("deact_hold", 2000);
    deact_done = 1'b0;
    `uvm_info(get_type_name(), $sformatf("DEACTIVATE_START with %s traffic waiting for credit",
                                         aou_cc_name(c)), UVM_LOW)
    fork
      begin
        deactivate(AOU_T1_BY_APB);
        deact_done = 1'b1;
      end
    join_none
    wait_cycles(dhold);
    `uvm_info(get_type_name(), $sformatf("%0d cycles after DEACTIVATE_START: DeactivateReq %0s",
                                         dhold, env.l3.model.lnk.dreq_rcvd || deact_done ?
                                         "received" : "not received"), UVM_LOW)
    // Later epochs (software activates again for what it still has to send)
    // get the credit back.
    cfg.l3_cfg.rx_depth[c] = depth0;
    for (int unsigned r = 0; r < cfg.n_rp; r++) grant_rp(c, r, grant);
    wait_traffic();
    wait (deact_done);
    drain();
  endtask
endclass
