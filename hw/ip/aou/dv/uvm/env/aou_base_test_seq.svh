// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of every T1 virtual sequence (docs/ARCHITECTURE.md, "Base virtual
// sequence"), on the shared library's ocah_sequence: scenario_seed,
// random_count and loop_index are set by aou_base_test when it starts a
// scenario pass (run_single_scenario / run_looped_scenario); a body that
// wants its draws replayable from them calls seed_scenario_rng() first
// (aou_sanity_test_seq does; the older virtual sequences draw from the
// simulator seed as before). Subclasses compose the helper tasks in body();
// the default body brings the link up, activates, runs random traffic both
// ways and drains. Helper failures are UVM_ERRORs whose message starts with
// a T1-V rule ID.
class aou_base_test_seq extends ocah_sequence;
  `uvm_object_utils(aou_base_test_seq)
  `uvm_declare_p_sequencer(aou_t1_vseqr)

  aou_t1_env     env;
  aou_t1_env_cfg cfg;
  int unsigned   num_txns = 100;

  protected int unsigned n_traffic;
  protected uvm_event    traffic_ev;
  protected bit          paused;
  // Results of the wait helpers (tasks cannot write outputs after waiting on
  // every simulator).
  bit                    link_ok;
  bit                    l3_ok;
  int unsigned           n_sysrst;    // system resets on an FDI link-down (sys_reset())
  bit                    sysrst_done; // the last relink() reset both dies
  protected aou_t1_feature_cfg last_prog; // the last program_cfg(), reapplied after a reset
  // INT_FDI_LINK_DOWN bookkeeping (expect_link_down()).
  bit                    link_down_masked;  // the test set INT_FDI_LINK_DOWN_MASK
  protected int unsigned n_ld_min;          // link-downs that found AoU in use
  protected int unsigned n_ld_max;          // link-downs
  protected bit          ld_expected;       // the last link-down found AoU in use
  // Longest wait from the AOU_SW_RESET write to the core reset (sw_reset()); the
  // DUT may first wait for its AXI handshakes to complete.
  localparam int unsigned SW_RESET_WAIT_CYCLES = 10000;

  function new(string name = "aou_base_test_seq");
    super.new(name);
    traffic_ev = new("traffic_ev");
  endfunction

  // The env and its cfg come from the virtual sequencer; the test's
  // plumb_scenario_seq() sets the same handles before start() for a scenario
  // pass, and pre_body keeps them for a sequence started any other way.
  task pre_body();
    if (env == null) env = p_sequencer.env;
    cfg = env.cfg;
  endtask

  task body();
    link_up();
    activate(AOU_T1_BY_RANDOM, AOU_T1_ORDER_RANDOM);
    traffic(AOU_T1_BOTH_DIRS, num_txns, null);
    drain();
  endtask

  // ---------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------
  task wait_cycles(int unsigned n);
    repeat (n) @(env.lsm_vif.mon_cb);
  endtask

  function bit link_is_up();
    return env.lsm_vif.mon_cb.fdi_link_up === 1'b1 && env.lsm.drv.link_active;
  endfunction

  // Waits up to `timeout` cycles for the link; link_ok = 0 on time-out.
  task wait_link(int unsigned timeout);
    int unsigned n = 0;
    link_ok = 1'b1;
    while (!link_is_up()) begin
      @(env.lsm_vif.mon_cb);
      if (++n >= timeout) begin
        link_ok = 1'b0;
        return;
      end
    end
  endtask

  // Waits for the L3 link state; l3_ok = 0 on time-out.
  task wait_l3(aou_link_state_e s, int unsigned timeout);
    l3_ok = 1'b0;
    fork
      begin
        fork
          begin
            env.l3.wait_state(s);
            l3_ok = 1'b1;
          end
          wait_cycles(timeout);
        join_any
        disable fork;
      end
    join
  endtask

  function void prep_reg(aou_reg_base_seq s);
    s.rm = p_sequencer.regs;
    s.apb_sqr = p_sequencer.apb_sqr;
  endfunction

  task write_field(uvm_reg_field f, uvm_reg_data_t value);
    aou_t1_field_seq s = aou_t1_field_seq::type_id::create("field");
    prep_reg(s);
    s.f = f;
    s.value = value;
    s.start(null);
  endtask

  // ---------------------------------------------------------------------
  // link_up: L2 bringup to Active
  // ---------------------------------------------------------------------
  task link_up();
    env.rst.wait_released();
    wait_link(cfg.link_timeout / 4);
    if (!link_ok) begin
      // With pl_clk_req released during bringup the DUT waits in WAIT_PRESENCE
      // for its software pin.
      `uvm_info(get_type_name(), "link not up yet: pulsing I_SW_ACTIVATE_START", UVM_LOW)
      env.lsm.drv.pulse_sw(LSM_SW_ACTIVATE, 2);
      wait_link(cfg.link_timeout);
    end
    if (!link_ok) `uvm_error(get_type_name(), "T1-V01: FDI link not Active after bringup")
    else `uvm_info(get_type_name(), "FDI link Active", UVM_LOW)
  endtask

  // ---------------------------------------------------------------------
  // activate / deactivate
  // ---------------------------------------------------------------------
  function aou_t1_who_e pick_who(aou_t1_who_e who);
    int unsigned r = $urandom_range(4);
    if (who != AOU_T1_BY_RANDOM) return who;
    // Weights 2:1:2 (no return inside randcase: CODING_GUIDELINES).
    if (r < 2) return AOU_T1_BY_APB;
    if (r == 2) return AOU_T1_BY_REMOTE;
    return AOU_T1_BY_BOTH;
  endfunction

  function aou_t1_order_e pick_order(aou_t1_order_e order);
    if (order != AOU_T1_ORDER_RANDOM) return order;
    return aou_t1_order_e'($urandom_range(2));
  endfunction

  task dut_activate(aou_t1_who_e who);
    if (who == AOU_T1_BY_PIN) begin
      env.lsm.drv.pulse_sw(LSM_SW_ACTIVATE, 2);
    end else begin
      aou_reg_activation_seq s = aou_reg_activation_seq::type_id::create("act");
      prep_reg(s);
      s.op = AOU_REG_ACTIVATE;
      s.wait_done = 1'b0;
      s.start(null);
    end
  endtask

  // Starts activation from the DUT side (APB or pin), the remote side (L3)
  // or both in the given order, then waits until both report ENABLED.
  task activate(aou_t1_who_e who = AOU_T1_BY_APB, aou_t1_order_e order = AOU_T1_DUT_FIRST);
    int unsigned gap = $urandom_range(200);
    who = pick_who(who);
    order = pick_order(order);
    env.sw_isr.wait_idle();
    if (!link_is_up()) begin
      // A link an earlier event left down (a deactivation never takes it
      // down): the Adapter (L2) resets and brings it up again.
      `uvm_info(get_type_name(), "link down before activation: Adapter LinkReset and bringup",
                UVM_LOW)
      relink();
    end
    `uvm_info(get_type_name(), $sformatf("activate: %s %s gap=%0d", who.name(), order.name(),
                                         gap), UVM_LOW)
    case (who)
      AOU_T1_BY_REMOTE: env.l3.model.lnk.request_activate();
      AOU_T1_BY_BOTH: begin
        case (order)
          AOU_T1_DUT_FIRST: begin
            dut_activate(AOU_T1_BY_APB);
            wait_cycles(gap);
            env.l3.model.lnk.request_activate();
          end
          AOU_T1_REMOTE_FIRST: begin
            env.l3.model.lnk.request_activate();
            env.l3.model.kick();
            wait_cycles(gap);
            dut_activate(AOU_T1_BY_APB);
          end
          default: begin
            fork
              dut_activate(AOU_T1_BY_APB);
              env.l3.model.lnk.request_activate();
            join
          end
        endcase
      end
      default: dut_activate(who);
    endcase
    env.l3.model.kick();
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok)
      `uvm_error(get_type_name(), $sformatf("T1-V02: remote (L3) not ENABLED: %s",
                                            env.l3.model.lnk.state.name()))
    if (!env.status.act_ok)
      `uvm_error(get_type_name(), "T1-V03: DUT not ENABLED (activate_state_enabled)")
    if (l3_ok && env.status.act_ok) `uvm_info(get_type_name(), "activation complete", UVM_LOW)
  endtask

  // Orderly (or, by APB, forced) deactivation from the DUT, the remote side
  // or both; waits for DISABLED on both sides. New local requests are held
  // from before DEACTIVATE_START until DISABLED.
  task deactivate(aou_t1_who_e who = AOU_T1_BY_APB, bit forced = 1'b0);
    who = pick_who(who);
    `uvm_info(get_type_name(), $sformatf("deactivate: %s forced=%0b", who.name(), forced),
              UVM_LOW)
    // The remote request goes first: an APB access takes long enough for the
    // whole handshake to finish, and a request made in DISABLED would linger
    // until the next activation.
    if (who inside {AOU_T1_BY_REMOTE, AOU_T1_BY_BOTH} && env.l3.model.lnk.state == AOU_LS_ENABLED)
    begin
      env.l3.model.lnk.request_deactivate();
      env.l3.model.maybe_release_deact();
      env.l3.model.kick();
    end
    // The local software stops issuing first (MAS 7.3.5; env.sw_isr does the
    // same when the remote die starts). A forced deactivation is not the
    // DEACTIVATE_START flow and leaves traffic alone.
    if (who != AOU_T1_BY_REMOTE && !forced) env.sw_isr.quiesce();
    if (who != AOU_T1_BY_REMOTE) begin
      aou_reg_activation_seq s = aou_reg_activation_seq::type_id::create("deact");
      prep_reg(s);
      s.wait_done = 1'b0;
      // Deactivation has no pin (only I_SW_ACTIVATE_START exists), so BY_PIN
      // deactivates through the register like BY_APB.
      s.op = forced ? AOU_REG_FORCE_DEACTIVATE : AOU_REG_DEACTIVATE;
      s.start(null);
    end
    env.l3.model.maybe_release_deact();
    env.l3.model.kick();
    fork
      wait_l3(AOU_LS_DISABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b0, cfg.act_timeout);
    join
    if (!l3_ok)
      `uvm_error(get_type_name(), $sformatf("T1-V04: remote (L3) not DISABLED: %s",
                                            env.l3.model.lnk.state.name()))
    if (!env.status.act_ok)
      `uvm_error(get_type_name(), "T1-V05: DUT not DISABLED (activate_state_disabled)")
    env.sw_isr.hold_requests(1'b0);
    // Let the local software finish (it clears INT_DEACTIVATE_START) and the
    // DUT's bringup controller react to the deactivation (it may drop wake
    // and leave the link to the Adapter).
    env.sw_isr.wait_idle();
    wait_cycles(32);
  endtask

  // ---------------------------------------------------------------------
  // program_cfg (the API's program(); "program" is an SV keyword): DUT features
  // through the register sequences
  // ---------------------------------------------------------------------
  task program_cfg(aou_t1_feature_cfg f);
    last_prog = f;
    // The threshold first, so a watchdog enabled below counts against it.
    if (f.wdt_threshold >= 0)
      write_field(p_sequencer.regs.write_early_response_wdt_ctl.wdt_threshold,
                  uvm_reg_data_t'(f.wdt_threshold));
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (f.split_ar[r] >= 0 || f.split_aw[r] >= 0) begin
        aou_reg_split_seq s = aou_reg_split_seq::type_id::create("split");
        prep_reg(s);
        s.rp = r;
        s.max_arburstlen = f.split_ar[r];
        s.max_awburstlen = f.split_aw[r];
        s.start(null);
      end
      if (f.aggregator[r] >= 0) begin
        aou_reg_aggregator_seq s = aou_reg_aggregator_seq::type_id::create("agg");
        prep_reg(s);
        s.rp = r;
        s.enable = f.aggregator[r];
        s.start(null);
      end
      if (f.early_resp[r] >= 0 || f.wdt_en[r] >= 0) begin
        aou_reg_early_resp_seq s = aou_reg_early_resp_seq::type_id::create("early");
        prep_reg(s);
        s.rp = r;
        s.enable = f.early_resp[r];
        s.wdt_en = f.wdt_en[r];
        s.start(null);
      end
      if (f.dest_rp[r] >= 0) begin
        aou_reg_dest_rp_seq s = aou_reg_dest_rp_seq::type_id::create("dest");
        prep_reg(s);
        s.rp = r;
        s.dest = f.dest_rp[r];
        s.start(null);
      end
      if (f.error_info_access[r] >= 0) begin
        aou_reg_error_info_seq s = aou_reg_error_info_seq::type_id::create("einfo");
        prep_reg(s);
        s.rp = r;
        s.access_en = f.error_info_access[r];
        s.start(null);
      end
    end
    if (f.any_qos()) begin
      aou_reg_qos_seq s = aou_reg_qos_seq::type_id::create("qos");
      prep_reg(s);
      s.arb_mode = f.arb_mode;
      s.rp_prior = f.rp_prior;
      s.qos_to_hp = f.qos_to_hp;
      s.qos_to_np = f.qos_to_np;
      s.timer_threshold = f.timer_threshold;
      s.timer_resolution = f.timer_resolution;
      s.start(null);
    end
    if (f.lp_mode >= 0 || f.lp_threshold >= 0) begin
      aou_reg_lp_mode_seq s = aou_reg_lp_mode_seq::type_id::create("lp");
      // Static configuration (MAS software-operation 7.1, T1-LP03): only while
      // the DUT is DISABLED. A test that gets here on a live link is wrong, and
      // the rest of its run would exercise an illegal state, so stop it.
      if (!env.status.disabled) begin
        string st = env.status.enabled ? "ENABLED" : "activating or deactivating";
        `uvm_fatal(get_type_name(), $sformatf(
                   {"TX_LP_MODE/THRESHOLD programmed while the DUT is %s; LP mode is static ",
                    "configuration, program it before activation or after deactivation"}, st))
      end
      prep_reg(s);
      s.enable = f.lp_mode;
      s.threshold = f.lp_threshold;
      s.start(null);
      // With a heartbeat threshold T the idle DUT sends one flit per T+1 cycles
      // after the last, each carrying one RP's floor-encoded MsgCredit (MAS 7.1,
      // AoU v0.7 6.4), so returning a class takes several flits per RP.
      if (f.lp_mode > 0 && f.lp_threshold > 0) begin
        int unsigned need = cfg.l3_cfg.rp_count * 12 *
                            (f.lp_threshold + 1 + cfg.fdi_cfg[0].bpf());
        if (need > cfg.l3_cfg.cred_return_cycles) cfg.l3_cfg.cred_return_cycles = need;
      end
    end
    if (f.any_mask()) begin
      aou_reg_int_mask_seq s = aou_reg_int_mask_seq::type_id::create("mask");
      prep_reg(s);
      s.si0_id_mismatch = f.mask_si0_id_mismatch;
      s.mi0_id_mismatch = f.mask_mi0_id_mismatch;
      s.early_resp = f.mask_early_resp;
      s.msgcredit_timeout = f.mask_msgcredit_timeout;
      s.invalid_actmsg = f.mask_invalid_actmsg;
      s.deact_ack = f.mask_deact_ack;
      s.act_ack = f.mask_act_ack;
      s.fdi_link_down = f.mask_fdi_link_down;
      s.early_wdt = f.mask_early_wdt;
      s.start(null);
    end
    if (f.any_timeout()) begin
      aou_reg_timeout_seq s = aou_reg_timeout_seq::type_id::create("tmo");
      prep_reg(s);
      s.msgcredit = f.msgcredit_timeout;
      s.ack = f.ack_timeout;
      s.deactivate = f.deactivate_timeout;
      s.start(null);
    end
  endtask

  // TX low-power mode. Static configuration: call it only while the DUT is
  // DISABLED (before activation, or after a deactivation has completed).
  task lp_mode(bit en, int threshold = -1);
    aou_t1_feature_cfg f = aou_t1_feature_cfg::type_id::create("lp");
    f.lp_mode = int'(en);
    f.lp_threshold = threshold;
    program_cfg(f);
  endtask

  // Back-pressure on the DUT's TX: pl_trdy low from the next flit boundary on
  // every PHY until release_tx(), so the DUT's requests back up behind its
  // ring buffer and arbiters. Returns once the hold is in force.
  task hold_tx();
    foreach (cfg.fdi_cfg[p]) cfg.fdi_cfg[p].tx_hold = 1'b1;
    repeat (cfg.fdi_cfg[0].bpf() + 2) @(env.lsm_vif.mon_cb);
  endtask

  task release_tx();
    foreach (cfg.fdi_cfg[p]) cfg.fdi_cfg[p].tx_hold = 1'b0;
  endtask

  // The remote die's counterpart: L3 holds back every credited message (Misc
  // still goes) until release_remote_tx(), then packs the backlog densely.
  function void hold_remote_tx();
    cfg.l3_cfg.pol.hold_credited = 1'b1;
  endfunction

  function void release_remote_tx();
    cfg.l3_cfg.pol.hold_credited = 1'b0;
    env.l3.model.kick();
  endfunction

  // ---------------------------------------------------------------------
  // Traffic
  // ---------------------------------------------------------------------
  protected task run_seq(aou_axi_sequencer sqr, int unsigned n, aou_t1_traffic_cfg p,
                         bit [63:0] base);
    case (p.kind)
      AOU_T1_SEQ_UNALIGNED: begin
        aou_axi_unaligned_wr_seq s = aou_axi_unaligned_wr_seq::type_id::create("unal");
        s.base = base;
        s.start(sqr);
      end
      AOU_T1_SEQ_B_ZERO: begin
        aou_axi_b_zero_seq s = aou_axi_b_zero_seq::type_id::create("bzero");
        s.num_txns = n;
        s.base = base;
        s.start(sqr);
      end
      default: begin
        aou_axi_rand_seq s = aou_axi_rand_seq::type_id::create("rand");
        s.num_txns = n;
        s.num_slots = p.num_slots;
        s.addr_lo = base;
        s.addr_hi = base + p.span - 64'd1;
        s.wr_pct = p.wr_pct;
        s.lock_pct = p.lock_pct;
        s.fixed_pct = p.fixed_pct;
        s.wrap_pct = p.wrap_pct;
        s.max_id = p.max_id;
        s.max_len = p.max_len;
        s.min_len = p.min_len;
        s.strb_mode = p.strb_mode;
        s.start(sqr);
      end
    endcase
  endtask

  protected function void apply_timing(aou_axi_timing_e local_t, int unsigned remote_max);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      cfg.s_mgr_cfg[r].timing.apply(local_t);
      cfg.m_sub_cfg[r].timing.apply(local_t);
    end
    if (remote_max == 0) begin
      cfg.remote_cfg.timing.b_lat.set_zero();
      cfg.remote_cfg.timing.r_lat.set_zero();
    end else begin
      cfg.remote_cfg.timing.b_lat.set_range(0, remote_max);
      cfg.remote_cfg.timing.r_lat.set_range(0, remote_max);
    end
  endfunction

  // n transactions per RP (of p.rp_mask) and direction with profile p (null: "rand").
  task traffic(aou_t1_dir_e dir, int unsigned n, aou_t1_traffic_cfg p = null);
    if (p == null) p = aou_t1_traffic_cfg::named("rand");
    `uvm_info(get_type_name(), $sformatf("traffic %s n=%0d: %s", dir.name(), n,
                                         p.convert2string()), UVM_LOW)
    if (!p.keep_timing) apply_timing(p.timing, p.timing == AOU_AXI_TIMING_ZERO ? 0 : 20);
    // The outer fork keeps disable fork away from the caller's other threads.
    fork
      begin
        fork
          begin
            for (int unsigned r = 0; r < cfg.n_rp; r++) begin
              if (!p.rp_mask[r]) continue;
              fork
                automatic int unsigned rr = r;
                begin
                  if (dir != AOU_T1_R2L)
                    run_seq(p_sequencer.s_mgr_sqr[rr], n, p, p.base + 64'(rr) * p.rp_stride);
                end
                begin
                  if (dir != AOU_T1_L2R)
                    run_seq(p_sequencer.r_mgr_sqr[rr], n, p, p.base + 64'(rr) * p.rp_stride);
                end
              join_none
            end
            wait fork;
          end
          begin
            // A DUT that stops responding ends the test with errors, not a hang.
            string why;
            wait_cycles(cfg.drain_timeout);
            void'(env.outstanding(why));
            `uvm_error(get_type_name(), {"T1-V08: traffic did not complete:", why})
            stop_traffic();
            wait_cycles(1000000000);
          end
        join_any
        disable fork;
      end
    join
    if (!p.keep_timing) apply_timing(cfg.local_timing, cfg.remote_lat_max);
  endtask

  task traffic_nb(aou_t1_dir_e dir, int unsigned n, aou_t1_traffic_cfg p = null);
    n_traffic++;
    fork
      begin
        traffic(dir, n, p);
        n_traffic--;
        traffic_ev.trigger();
      end
    join_none
  endtask

  // Waits for traffic_nb() traffic; after `timeout` cycles (default
  // cfg.drain_timeout) it reports T1-V08 and stops it (stop_traffic()), so a
  // DUT that stops responding ends the test with errors instead of a hang.
  task wait_traffic(int unsigned timeout = 0);
    int unsigned n = 0;
    string why;
    if (timeout == 0) timeout = cfg.drain_timeout;
    while (n_traffic != 0) begin
      @(env.lsm_vif.mon_cb);
      if (++n == timeout) begin
        void'(env.outstanding(why));
        `uvm_error(get_type_name(), {"T1-V08: traffic did not complete:", why})
        stop_traffic();
      end
    end
  endtask

  // Kills every traffic sequence and ends what the AXI managers have
  // outstanding as aborted (env.abort_traffic()).
  task stop_traffic();
    foreach (p_sequencer.s_mgr_sqr[r]) p_sequencer.s_mgr_sqr[r].stop_sequences();
    foreach (p_sequencer.r_mgr_sqr[r]) p_sequencer.r_mgr_sqr[r].stop_sequences();
    env.abort_traffic();
  endtask

  // Stops every traffic source at its next transaction (sequencers grabbed),
  // then waits until nothing is in flight.
  task pause_traffic();
    if (paused) return;
    paused = 1'b1;
    foreach (p_sequencer.s_mgr_sqr[r]) grab(p_sequencer.s_mgr_sqr[r]);
    foreach (p_sequencer.r_mgr_sqr[r]) grab(p_sequencer.r_mgr_sqr[r]);
    drain();
  endtask

  task resume_traffic();
    if (!paused) return;
    foreach (p_sequencer.s_mgr_sqr[r]) ungrab(p_sequencer.s_mgr_sqr[r]);
    foreach (p_sequencer.r_mgr_sqr[r]) ungrab(p_sequencer.r_mgr_sqr[r]);
    paused = 1'b0;
  endtask

  // Waits until nothing is outstanding anywhere for 50 consecutive cycles.
  task drain(int unsigned timeout = 0);
    int unsigned n = 0;
    int unsigned quiet = 0;
    string why;
    if (timeout == 0) timeout = cfg.drain_timeout;
    while (quiet < 50) begin
      @(env.lsm_vif.mon_cb);
      if (env.outstanding(why) == 0) quiet++;
      else quiet = 0;
      if (++n >= timeout) begin
        `uvm_error(get_type_name(), {"T1-V06: not drained:", why})
        return;
      end
    end
    `uvm_info(get_type_name(), $sformatf("drained after %0d cycles", n), UVM_MEDIUM)
  endtask

  // ---------------------------------------------------------------------
  // Link events, injection, resets, expectations
  // ---------------------------------------------------------------------
  // INT_FDI_LINK_DOWN (T1-L49): an Adapter LinkError, LinkReset or Disabled
  // that finds the DUT out of DISABLED with the link established raises it
  // exactly once (the DUT disables itself, T1-L48 in aou_t1_status); one
  // that finds it DISABLED may not (0..1: a remote activation message can be
  // moving the DUT as the link goes down). A link the DUT already took down
  // itself (its own LinkError request on an Ack time-out or an invalid
  // message, bringup model in LINKERROR) has no edge left to report: the
  // DUT disabled itself then, and the Adapter's report changes nothing.
  // The same holds for any event issued while the link is already down
  // (bringup model in RESET, LINKERROR or LINKDOWN: the Adapter LinkReset
  // sw_reset() issues after a LinkError, for one): no edge, so neither
  // bound moves, and one loss stays exactly one interrupt. Nothing else
  // raises it: the watcher reports a rise no test declared, and the upper
  // bound a second one per event. With the mask set the pin never rises (no
  // declaration, so any rise is an error) and the status bit is checked
  // instead (check_link_down_status()).
  protected function void expect_link_down(aou_lsm_ev_e kind);
    if (!(kind inside {LSM_EV_LINKERROR, LSM_EV_LINK_RESET, LSM_EV_DISABLED})) return;
    if (env.lsm.mon.model.st inside {BRG_RESET, BRG_LINKERROR, BRG_LINKDOWN}) return;
    if (!env.status.disabled &&
        env.lsm.mon.model.st inside {BRG_ACTIVE, BRG_RETRAIN, BRG_L1, BRG_L1_CLK_WAKE}) begin
      ld_expected = 1'b1;   // until check_link_down_status()
      n_ld_min++;
    end
    n_ld_max++;
    if (!link_down_masked) expect_event("INT_FDI_LINK_DOWN", n_ld_min, n_ld_max);
  endfunction

  // With INT_FDI_LINK_DOWN masked the sticky bit is still set by a link loss
  // with AoU in use (the mask gates the pin only); read before the system
  // reset clears it with the other registers.
  task check_link_down_status();
    uvm_reg_data_t v;
    aou_reg_base_seq s = aou_reg_base_seq::type_id::create("s");
    bit due = link_down_masked && ld_expected;
    ld_expected = 1'b0;
    if (!due) return;
    prep_reg(s);
    s.rd_field(p_sequencer.regs.aou_init.int_fdi_link_down, v);
    `uvm_info(get_type_name(), $sformatf("masked INT_FDI_LINK_DOWN: status bit reads %0d", v),
              UVM_LOW)
    if (v != 1)
      `uvm_error(get_type_name(),
                 "T1-L49: AOU_INIT.INT_FDI_LINK_DOWN reads 0 after a link loss with AoU in use")
  endtask

  task link_event(aou_lsm_ev_e kind, int unsigned cycles = 0);
    aou_lsm_event_seq s = aou_lsm_event_seq::type_id::create("ev");
    // A link-down the Adapter brings back up by itself while AoU state is in
    // use: the system resets both dies while the link is down, then they
    // activate again (cfg.sysrst_on_linkdown).
    if (cfg.lsm_cfg.rebringup_after_down && kind inside {LSM_EV_LINKERROR, LSM_EV_LINK_RESET,
        LSM_EV_DISABLED} && sysrst_due()) begin
      cfg.lsm_cfg.rebringup_after_down = 1'b0;
      link_event(kind, cycles);
      cfg.lsm_cfg.rebringup_after_down = 1'b1;
      check_link_down_status();
      sys_reset();
      link_event(LSM_EV_BRINGUP);
      if (last_prog != null) program_cfg(last_prog);
      activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
      return;
    end
    expect_link_down(kind);
    s.ev_kind = kind;
    s.ev_cycles = cycles;
    `uvm_info(get_type_name(), {"link event ", kind.name()}, UVM_LOW)
    s.start(p_sequencer.lsm_sqr);
    if (kind inside {LSM_EV_RETRAIN, LSM_EV_L1_EXIT, LSM_EV_BRINGUP} ||
        (cfg.lsm_cfg.rebringup_after_down &&
         kind inside {LSM_EV_LINKERROR, LSM_EV_LINK_RESET, LSM_EV_DISABLED})) begin
      wait_link(cfg.link_timeout);
      if (!link_ok) `uvm_error(get_type_name(), {"T1-V07: link not Active after ", kind.name()})
    end
  endtask

  // Brings a link that is down back up: an Adapter LinkReset and bringup, or
  // only the bringup when the Adapter is already in Reset (after a LinkError
  // it took down on the DUT's lp_linkerror). If AoU state
  // is still in use, the system resets both dies while the link is down
  // (sys_reset()); both are then DISABLED and the caller activates them as
  // after any relink. Returns with sysrst_done set when it reset them.
  task relink();
    bit down = env.lsm.drv.state == LSM_RESET;
    sysrst_done = 1'b0;
    if (!sysrst_due()) begin
      link_event(down ? LSM_EV_BRINGUP : LSM_EV_LINK_RESET);
      return;
    end
    if (!down) begin
      bit keep = cfg.lsm_cfg.rebringup_after_down;
      cfg.lsm_cfg.rebringup_after_down = 1'b0;
      link_event(LSM_EV_LINK_RESET);
      cfg.lsm_cfg.rebringup_after_down = keep;
      check_link_down_status();
    end
    sys_reset();
    link_event(LSM_EV_BRINGUP);
    if (last_prog != null) program_cfg(last_prog);
    sysrst_done = 1'b1;
  endtask

  // Both dies cleanly DISABLED with no activation message pending or in
  // flight in either direction. A message the DUT has handed to its TX path
  // or received leaves it out of DISABLED (it moves on the hand-over), and
  // one on its way to or queued in the remote die leaves the remote out of
  // DISABLED or its queue non-empty, so the two states and the remote's queue
  // cover every place an activation message can be.
  function bit aou_quiet();
    return env.status.disabled && env.l3.model.lnk.state == AOU_LS_DISABLED &&
           env.l3.model.lnk.out_q.size() == 0;
  endfunction

  function bit sysrst_due();
    return cfg.sysrst_on_linkdown && !aou_quiet();
  endfunction

  // The system's reset of both dies on an FDI link-down, with the link down:
  // software resets AOU_CORE (AOU_SW_RESET, as in the MAS 7.3.6 LinkReset
  // sequence; the bring-up controller is outside AOU_CORE and keeps its state)
  // and the remote die resets its own AoU state. Messages queued on either
  // side before the reset are void (AoU v0.8 reading: the interface state
  // does not survive an FDI reset).
  task sys_reset();
    n_sysrst++;
    `uvm_info(get_type_name(),
              $sformatf("FDI link down, AoU in use (DUT %s, remote %s, %0d queued): system reset",
                        env.status.disabled ? "DISABLED" : "active",
                        env.l3.model.lnk.state.name(), env.l3.model.lnk.out_q.size()), UVM_LOW)
    env.sw_isr.cancel();
    env.sw_isr.wait_idle();
    sw_reset_core();
  endtask

  // AOU_SW_RESET and the environment's matching flush (both dies), the link
  // already down. The flush follows the core reset: the local AXI agents are on
  // the DUT's AXI-port reset (tb_top axi_port_rst_n), so to them the software
  // reset is a bus reset (bus_reset = 1): every transaction in flight or queued
  // is lost, as the MAS says (7.3.6), and the agents restart idle with the core.
  // A core reset that never comes is T1-L31.
  task sw_reset_core();
    env.sw_reset_window(1'b1);
    fork
      write_field(p_sequencer.regs.aou_con0.aou_sw_reset, 1);
      begin
        env.rst.wait_core_reset(SW_RESET_WAIT_CYCLES);
        if (!env.rst.core_reset_seen)
          `uvm_error(get_type_name(), $sformatf(
                     {"T1-L31: AOU_SW_RESET did not put the DUT core in reset within %0d ",
                      "cycles; flushing anyway"}, SW_RESET_WAIT_CYCLES))
        env.sw_reset_window(1'b0);
        env.reset_flush(AOU_T1_RST_BOTH, 1'b1);
      end
    join
    wait_cycles(20);
    p_sequencer.regs.reset();
  endtask

  // L3 error injection. kind: bad_type (arg: kind of bad granule), rsvd
  // (arg: RsvdZero value in a zero CrdtGrant), act_ack / act_req / deact_req / deact_ack
  // (out-of-state activation message), flip_start (arg: granule), fdid
  // (arg: value), overgrant (arg: credits, WREQ class).
  task inject(string kind, int arg = 0);
    `uvm_info(get_type_name(), $sformatf("inject %s (%0d)", kind, arg), UVM_LOW)
    case (kind)
      "bad_type": begin
        aou_l3_bad_type_seq s = aou_l3_bad_type_seq::type_id::create("inj");
        s.kind = arg;
        s.start(p_sequencer.l3_sqr);
      end
      "rsvd": begin
        // RsvdZero bits set in a CrdtGrant that grants nothing: no message
        // the DUT must answer, so nothing unsolicited follows.
        aou_msg_crdtgrant g = aou_msg_crdtgrant::type_id::create("inj");
        g.rsvd = 17'(arg > 0 ? arg : 1);
        env.l3.send(g);
      end
      "act_req", "act_ack", "deact_req", "deact_ack": begin
        aou_l3_act_inject_seq s = aou_l3_act_inject_seq::type_id::create("inj");
        case (kind)
          "act_req":   s.op = AOU_ACT_REQ;
          "act_ack":   s.op = AOU_ACT_ACK;
          "deact_req": s.op = AOU_DEACT_REQ;
          default:     s.op = AOU_DEACT_ACK;
        endcase
        s.start(p_sequencer.l3_sqr);
      end
      "flip_start", "fdid": begin
        aou_l3_flit_inject_seq s = aou_l3_flit_inject_seq::type_id::create("inj");
        if (kind == "flip_start") s.flip_start = arg;
        else s.fdid = arg;
        s.start(p_sequencer.l3_sqr);
      end
      "overgrant": begin
        aou_l3_overgrant_seq s = aou_l3_overgrant_seq::type_id::create("inj");
        if (arg > 0) s.n = arg;
        s.start(p_sequencer.l3_sqr);
      end
      default: `uvm_fatal(get_type_name(), {"inject: unknown kind ", kind})
    endcase
  endtask

  // AXI error responses from a memory: the remote memory (l2r=1) or the local
  // memory answers [lo, hi] with resp (SLVERR/DECERR); the scoreboard expects it.
  function void inject_mem_error(bit l2r, bit [63:0] lo, bit [63:0] hi, bit [1:0] resp);
    aou_mem m = l2r ? cfg.remote_cfg.mem : cfg.local_mem;
    m.add_error_region(lo, hi, resp);
  endfunction

  // Pulses I_RESETN and/or I_PRESETN; the env flushes (the reset agent
  // triggers it; I_PRESETN alone flushes only the APB side). After a
  // core reset the link comes up and activation runs again.
  task hard_reset(aou_t1_rst_e which = AOU_T1_RST_BOTH, bit reactivate = 1'b1);
    // The reset agent's on_reset makes the env flush (reset_flush(which)).
    env.rst.do_reset(which);
    // The SFRs are on the core reset (integration guide 3.1.1): I_PRESETN alone keeps them.
    if (which != AOU_T1_RST_APB) p_sequencer.regs.reset();
    // I_PRESETN alone leaves the core and the AoU link running.
    if (!reactivate || which == AOU_T1_RST_APB) return;
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
  endtask

  // AOU_CON0.AOU_SW_RESET as the MAS uses it (7.3.6: while handling LinkReset):
  // the Adapter takes the link to Reset, software resets AOU_CORE (every SFR,
  // the bit itself included, the activation state and the RX FIFOs),
  // the remote die drops its activation state, the link comes back up,
  // software reprograms and both dies activate again.
  // The env flushes on the first core clock that samples the core in reset, and
  // the local AXI agents reset with it (sw_reset_core): every request handshaked
  // before the flush went to the old core and is lost or, for a write acknowledged
  // early, lost or landed (reset_outstanding; the scoreboard allows either), and
  // every one after it goes to the new core and is tracked normally. The local
  // managers issue until the reset and resume once it is over, so requests do
  // arrive right up to the reset. The APB write can complete after the core reset
  // has ended, so it is not the boundary.
  task sw_reset(aou_t1_feature_cfg reprogram = null, bit reactivate = 1'b1);
    bit rebringup = cfg.lsm_cfg.rebringup_after_down;
    cfg.lsm_cfg.rebringup_after_down = 1'b0;
    link_event(LSM_EV_LINK_RESET);
    cfg.lsm_cfg.rebringup_after_down = rebringup;
    check_link_down_status();
    // Software is one thread: a service the ISR began before the link went
    // down (its APB write may still be queued behind this sequence's) ends or
    // is abandoned before software requests the reset, as in sys_reset().
    // Otherwise that write lands on the reset core (ACTIVATE_START after the
    // reset makes the DUT activate without INT_ACTIVATE_START, T1-L05).
    env.sw_isr.cancel();
    env.sw_isr.wait_idle();
    sw_reset_core();
    link_event(LSM_EV_BRINGUP);
    if (reprogram != null) program_cfg(reprogram);
    if (reactivate) activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
  endtask

  function void expect_event(string id, int unsigned min = 1, int unsigned max = 0);
    env.expects.add(id, min, max);
  endfunction
endclass
