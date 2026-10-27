// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Software starts activation again just as a deactivation completes.
// The DUT starts the deactivation; the remote die acknowledges
// at once but holds its own DeactivateReq until the test releases it, as a
// remote die still finishing its own requests would (AoU 8.4). The DUT's
// DeactivateAck to that request is then its last message before DISABLED,
// and the test writes AOU_INIT.ACTIVATE_START at a swept offset from the
// DUT's DISABLED, so the DUT's ActivateReq moves across the flit that carries
// the DeactivateAck and the flits after it. A write that lands before
// DISABLED is held by the DUT until DISABLED: the MAS allows ACTIVATE_START
// before link-up (7.3.2) and activation right after DISABLED (7.3.6) but says
// nothing about DEACTIVATE. The placement of the
// Activation messages (one per flit, at G0, AoU 4.4; with +v0p9draft only the
// permitted company beside it) is judged by AOU-R6 in the L3 unpacker and
// AOU_FDI_CHECKER.
// The first loop calibrates the APB write time and the delay from the remote
// DeactivateReq to the DUT's DISABLED; every later loop aims the end of the
// ACTIVATE_START write at DISABLED + offset and logs the offset it got. The
// register takes the write about halfway through (26 of 52 cycles on T1).
// Knobs: +offsets=<o,o,..> (cycles, may be negative; default -12..44)
// +busy=0|1 (-1: random per loop) +T1_TXN.
class aou_act_after_deact_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_act_after_deact_vseq)

  protected longint unsigned cyc;
  protected int              apb_lat;   // ACTIVATE_START write, cycles
  protected int              dis_lat;   // remote DeactivateReq released to DUT DISABLED

  function new(string name = "aou_act_after_deact_vseq");
    super.new(name);
  endfunction

  static function void parse_offsets(string s, ref int q[$]);
    int start = 0;
    for (int i = 0; i <= s.len(); i++) begin
      if (i == s.len() || s[i] == ",") begin
        if (i > start) q.push_back(s.substr(start, i - 1).atoi());
        start = i + 1;
      end
    end
  endfunction

  task body();
    fork
      begin
        fork
          forever begin
            @(env.lsm_vif.mon_cb);
            cyc++;
          end
          scenario();
        join_any
        disable fork;
      end
    join
  endtask

  task scenario();
    int offsets[$];
    string os = arg_str("offsets", "");
    int busy_arg = arg_int("busy", -1);
    if (os != "") begin
      parse_offsets(os, offsets);
    end else begin
      for (int o = -12; o <= 44; o++) offsets.push_back(o);
    end
    link_up();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    for (int i = -1; i < int'(offsets.size()); i++) begin
      bit busy = (busy_arg >= 0) ? 1'(busy_arg) : 1'($urandom_range(1));
      if (busy) begin
        traffic_nb(AOU_T1_BOTH_DIRS, (num_txns + 1) / 2, aou_t1_traffic_cfg::named("short"));
        wait_cycles($urandom_range(200, 10));
      end
      deact_then_activate((i < 0) ? 0 : offsets[i], i < 0, i + 1, offsets.size());
      wait_traffic();
      drain();
    end
    check_traffic(num_txns);
  endtask

  // calib: write ACTIVATE_START once DISABLED is seen and measure the two
  // latencies; otherwise aim the end of the write at DISABLED + off.
  task deact_then_activate(int off, bit calib, int unsigned loop, int unsigned loops);
    aou_reg_activation_seq s = aou_reg_activation_seq::type_id::create("deact");
    longint unsigned t_rel = 0;
    longint unsigned t_dis = 0;
    longint unsigned t_ws = 0;
    longint unsigned t_wr = 0;
    int unsigned n = 0;
    bit dis_ok = 1'b0;
    int lead;
    if (calib) `uvm_info(get_type_name(), $sformatf("loop 0/%0d: calibration", loops), UVM_LOW)
    else `uvm_info(get_type_name(), $sformatf("loop %0d/%0d: ACTIVATE_START aimed at DISABLED %0d",
                                              loop, loops, off), UVM_LOW)
    cfg.l3_cfg.auto_deactivate = 1'b0;
    env.sw_isr.quiesce();
    prep_reg(s);
    s.wait_done = 1'b0;
    s.op = AOU_REG_DEACTIVATE;
    s.start(null);
    env.l3.model.kick();
    // The remote die has the DUT's DeactivateReq and has acknowledged it: the
    // DUT now waits only for the remote DeactivateReq, and an AOU_INIT write
    // can no longer cancel its DEACTIVATE_START.
    while (!(env.l3.model.lnk.dreq_rcvd && env.l3.model.lnk.dack_sent) &&
           n++ < cfg.act_timeout)
      wait_cycles(1);
    cfg.l3_cfg.auto_deactivate = 1'b1;
    if (n >= cfg.act_timeout) begin
      `uvm_error(get_type_name(),
                 $sformatf("T1-L27: remote die did not acknowledge the DeactivateReq (%s)",
                           env.l3.model.lnk.state.name()))
      return;
    end
    wait_cycles($urandom_range(16));
    // lead > 0: the write starts that many cycles before the remote
    // DeactivateReq is released; lead < 0: after it.
    lead = calib ? 0 : apb_lat - dis_lat - off;
    fork
      begin
        if (lead > 0) wait_cycles(lead);
        t_rel = cyc;
        env.l3.model.lnk.request_deactivate();
        env.l3.model.maybe_release_deact();
        env.l3.model.kick();
      end
      begin
        int unsigned k = 0;
        while (env.status.vif.mon_cb.act_st_disabled !== 1'b1 && k++ < cfg.act_timeout)
          @(env.status.vif.mon_cb);
        dis_ok = env.status.vif.mon_cb.act_st_disabled === 1'b1;
        t_dis = cyc;
      end
      begin
        if (calib) while (t_dis == 0) wait_cycles(1);
        else if (lead < 0) wait_cycles(-lead);
        t_ws = cyc;
        dut_activate(AOU_T1_BY_APB);
        t_wr = cyc;
      end
    join
    if (!dis_ok) begin
      `uvm_error(get_type_name(), "T1-L27: DUT not DISABLED after the remote DeactivateReq")
      return;
    end
    if (calib) begin
      apb_lat = int'(t_wr - t_ws);
      dis_lat = int'(t_dis - t_rel);
      `uvm_info(get_type_name(), $sformatf("calibration: APB write %0d cycles, %s %0d cycles",
                                           apb_lat, "remote DeactivateReq to DISABLED", dis_lat),
                UVM_LOW)
    end
    `uvm_info(get_type_name(),
              $sformatf("loop %0d: ACTIVATE_START write ended at DISABLED %0d (aimed %0d)",
                        loop, longint'(t_wr) - longint'(t_dis), off), UVM_LOW)
    env.l3.model.kick();
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(),
                 $sformatf("T1-L27: not ENABLED after ACTIVATE_START (remote %s, DUT ENABLED %0b)",
                           env.l3.model.lnk.state.name(), env.status.act_ok))
    env.sw_isr.hold_requests(1'b0);
    env.sw_isr.wait_idle();
  endtask
endclass
