// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Interrupt status, masks and write-1-to-clear (plan 19.5, 19.9, 19.11,
// 19.12; MAS interrupts-errors 4, software-operation 7.1/7.2). Modes:
//   w1c   (old aou_int_w1c_test) the local software is off. A remote
//         ActivateReq sets INT_ACTIVATE_START and a remote DeactivateReq
//         INT_DEACTIVATE_START; reading them or writing 0 leaves them (and the
//         interrupt) set, writing 1 clears them. Then an ActivateAck in
//         ENABLED sets LP_LINKRESET.INVALID_ACTMSG_ERR, which behaves the same
//         and takes INVALID_ACTMSG_INFO with it; the link is recovered.
//   early every RP gets a bufferable write whose remote completion is an
//         error at the same time: early OKAY, then WRITE_RESP_ERR with ID and
//         type, and INT_EARLY_RESP_ERR until the last RP is cleared. +mask=1
//         sets INT_EARLY_RESP_MASK: status still set, interrupt low until the
//         mask is cleared (interim, BUGS/029).
//   multi on every RP at once an early-response error and a WriteResp
//         nobody asked for (subordinate checker on, BUGS/003), then an
//         ActivateAck in ENABLED (LinkReset). All three interrupts and every
//         status bit are set; clearing one source leaves the others; the link
//         is recovered. (An M-port ID mismatch cannot join: BUGS/029.)
//   race  a write-1-to-clear of WRITE_RESP_ERR swept across the cycle a new
//         early-response error sets it: the new error must never be lost
//         (interim, BUGS/029: a set in the clearing cycle wins).
// Knobs: +mode=all|w1c|early|multi|race +mask=0|1 +race_span=<cycles>.
class aou_int_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_int_vseq)

  static const bit [63:0] EARLY_BASE = 64'h0000_0064_0000_0000;

  bit          masked;
  int unsigned n_early;     // early-response errors provoked (scoreboard AXI-S01)
  int unsigned rise_cyc;    // result of early_err(): cycles to the interrupt, 0 if none

  function new(string name = "aou_int_vseq");
    super.new(name);
  endfunction

  // Called by the test before the scoreboard copies the memories.
  static function void add_regions(aou_t1_env_cfg c);
    for (int unsigned r = 0; r < c.n_rp; r++)
      for (int unsigned k = 0; k < 64; k++)
        c.remote_cfg.mem.add_error_region(early_addr(r, k), early_addr(r, k) + EARLY_STRIDE - 1,
                                          early_resp_of(k));
  endfunction

  // One full-width beat of the widest RP (1024 bits) per region, so a write
  // never reaches the next region's response.
  static const bit [63:0] EARLY_STRIDE = 64'h80;

  static function bit [63:0] early_addr(int unsigned rp, int unsigned k);
    return EARLY_BASE + 64'(rp) * 64'h0100_0000 + 64'(k % 64) * EARLY_STRIDE;
  endfunction

  static function bit [1:0] early_resp_of(int unsigned k);
    return k[0] ? AOU_AXI_DECERR : AOU_AXI_SLVERR;
  endfunction

  task body();
    string mode = arg_str("mode", "all");
    masked = arg_int("mask", 0) != 0;
    // Every early OKAY replaces the error the scoreboard expects.
    if (mode != "w1c") expect_event("AXI-S01", 1, 0);
    if (mode inside {"all", "early", "multi", "race"}) expect_event("INT_EARLY_RESP_ERR", 1, 0);
    if (mode inside {"all", "multi"}) expect_event("INT_SI0_ID_MISMATCH", 1, 0);
    if (mode inside {"all", "w1c", "multi"}) begin
      expect_event("INT_REQ_LINKRESET", 1, mode == "all" ? 2 : 1);
      expect_event("AOU-R40", 0, 0);
    end
    link_up();
    if (mode inside {"all", "w1c"}) w1c_part();
    else sw_activate();
    check_traffic(num_txns);
    // Early response only around the parts that need it: the scoreboard
    // checks memory when B arrives, which an early B precedes.
    if (mode inside {"all", "early"}) begin
      set_early(1'b1);
      early_part();
      set_early(1'b0);
    end
    if (mode inside {"all", "multi"}) begin
      set_early(1'b1);
      multi_part();
      set_early(1'b0);
    end
    if (mode inside {"all", "race"}) begin
      set_early(1'b1);
      race_part();
      set_early(1'b0);
    end
    check_traffic(num_txns);
    sw_deactivate();
    if (env.expects.is_expected("AXI-S01") && env.expects.count("AXI-S01") != n_early)
      `uvm_error(get_type_name(), $sformatf(
          "T1-E09: %0d early OKAYs replaced an error, %0d provoked",
                                            env.expects.count("AXI-S01"), n_early))
  endtask

  // ---------------------------------------------------------------------
  // Reads twice and writes 0: the bit stays set and so does the interrupt
  // (irq "" for none); then writes 1: both clear, and so does `info`.
  task w1c_check(uvm_reg_field f, string irq, string what, uvm_reg_field info = null,
                 int info_val = 0);
    check_field(f, 1, "T1-E10", {what, ": set"});
    check_field(f, 1, "T1-E10", {what, ": a read does not clear"});
    if (info != null) check_field(info, uvm_reg_data_t'(info_val), "T1-E10", {what, ": INFO"});
    wr(f, 0);
    check_field(f, 1, "T1-E10", {what, ": writing 0 does not clear"});
    if (irq != "") check_pin(irq, 1'b1, "T1-E10", {what, ": interrupt after writing 0"});
    wr(f, 1);
    check_field(f, 0, "REG-R04", {what, ": after write-1-to-clear"});
    if (info != null) check_field(info, 0, "T1-E10", {what, ": INFO clears with the error"});
    if (irq != "") check_pin(irq, 1'b0, "T1-E10", {what, ": interrupt after write-1-to-clear"});
  endtask

  // MAS 3.7.8: change EARLY_BRESP_EN only with no write pending
  // (WRITE_RESP_DONE = 1).
  task set_early(bit en);
    drain();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      poll(rpf("write_early_response", r, "write_resp_done"), 1);
      if (!poll_ok)
        `uvm_error(get_type_name(), $sformatf("T1-E11: RP%0d WRITE_RESP_DONE not 1 when idle", r))
      wr(rpf("write_early_response", r, "early_bresp_en"), int'(en));
    end
  endtask

  task wait_pin(string irq, int unsigned timeout);
    int unsigned n = 0;
    while (!pin(irq) && n++ < timeout) wait_cycles(1);
    if (!pin(irq)) `uvm_error(get_type_name(), {"T1-E10: ", irq, " not raised"})
  endtask

  task w1c_part();
    aou_core rm = p_sequencer.regs;
    env.sw_isr.enable = 1'b0;
    `uvm_info(get_type_name(), "w1c: remote ActivateReq", UVM_LOW)
    env.l3.model.lnk.request_activate();
    env.l3.model.kick();
    wait_pin("INT_ACTIVATE_START", cfg.act_timeout);
    check_field(rm.aou_init.int_activate_start, 1, "T1-E10", "INT_ACTIVATE_START: set");
    check_field(rm.aou_init.int_activate_start, 1, "T1-E10", "INT_ACTIVATE_START: read again");
    wr(rm.aou_init.int_activate_start, 0);
    check_field(rm.aou_init.int_activate_start, 1, "T1-E10", "INT_ACTIVATE_START: after writing 0");
    check_pin("INT_ACTIVATE_START", 1'b1, "T1-E10", "after writing 0");
    write_field(rm.aou_init.activate_start, 1);
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok) `uvm_error(get_type_name(), "T1-V03: activation incomplete")
    w1c_check(rm.aou_init.int_activate_start, "INT_ACTIVATE_START", "INT_ACTIVATE_START");
    check_traffic(num_txns);

    `uvm_info(get_type_name(), "w1c: remote DeactivateReq", UVM_LOW)
    env.l3.model.lnk.request_deactivate();
    env.l3.model.maybe_release_deact();
    env.l3.model.kick();
    wait_pin("INT_DEACTIVATE_START", cfg.act_timeout);
    check_field(rm.aou_init.int_deactivate_start, 1, "T1-E10", "INT_DEACTIVATE_START: set");
    wr(rm.aou_init.int_deactivate_start, 0);
    check_field(rm.aou_init.int_deactivate_start, 1, "T1-E10",
                "INT_DEACTIVATE_START: after writing 0");
    write_field(rm.aou_init.deactivate_start, 1);
    env.l3.model.maybe_release_deact();
    env.l3.model.kick();
    fork
      wait_l3(AOU_LS_DISABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b0, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok) `uvm_error(get_type_name(), "T1-V05: deactivation incomplete")
    w1c_check(rm.aou_init.int_deactivate_start, "INT_DEACTIVATE_START", "INT_DEACTIVATE_START");
    wait_cycles(32);

    `uvm_info(get_type_name(), "w1c: ActivateAck in ENABLED (LP_LINKRESET)", UVM_LOW)
    env.sw_isr.enable = 1'b1;
    ensure_link();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    env.sw_isr.wait_idle();
    env.sw_isr.enable = 1'b0;
    inject("act_ack");
    wait_cycles(1000);
    w1c_check(rm.lp_linkreset.invalid_actmsg_err, "", "LP_LINKRESET.INVALID_ACTMSG_ERR",
              rm.lp_linkreset.invalid_actmsg_info, int'(AOU_ACT_ACK));
    recover();
  endtask

  // ---------------------------------------------------------------------
  // A bufferable write from RP rp's local manager into the k-th remote error
  // block: early OKAY, then the remote error. rise_cyc: cycles from the start
  // to INT_EARLY_RESP_ERR (0 if it did not rise, or was already high).
  task early_err(int unsigned rp, int unsigned k, bit [9:0] id, int unsigned watch = 0);
    aou_axi_txn t = mk(1'b0, rp, AOU_AXI_WR, id, early_addr(rp, k), 0, 4'b0011);
    n_early++;
    rise_cyc = 0;
    fork
      run_one(1'b0, rp, t);
      begin
        int unsigned n = 0;
        while (watch != 0 && n < watch && !pin("INT_EARLY_RESP_ERR")) begin
          wait_cycles(1);
          n++;
        end
        if (watch != 0 && n < watch) rise_cyc = n;
      end
    join
  endtask

  // Polls rp's WRITE_RESP_ERR until set.
  task wait_early_status(int unsigned rp);
    poll(rpf("write_early_response", rp, "write_resp_err"), 1);
    if (!poll_ok)
      `uvm_error(get_type_name(), $sformatf("T1-E11: RP%0d WRITE_RESP_ERR not set", rp))
  endtask

  task early_part();
    aou_core rm = p_sequencer.regs;
    bit [9:0] ids[];
    ids = new[cfg.n_rp];
    if (masked) wr(rm.aou_interrupt_mask.int_early_resp_mask, 1);
    foreach (ids[r]) ids[r] = 10'($urandom_range(10'h3FF));
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      fork
        automatic int unsigned rr = r;
        begin
          early_err(rr, rr + 1, ids[rr]);
          wait_early_status(rr);
        end
      join_none
    end
    wait fork;
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      string what = $sformatf("RP%0d early-response error", r);
      check_field(rpf("write_early_response", r, "write_resp_err_id_info"),
                  uvm_reg_data_t'(ids[r]), "T1-E11",
                  what);
      check_field(rpf("write_early_response", r, "write_resp_err_type_info"),
                  uvm_reg_data_t'(early_resp_of(r + 1)), "T1-E11", what);
    end
    check_pin("INT_EARLY_RESP_ERR", !masked, "T1-E06", "every RP's error pending");
    if (masked) begin
      wr(rm.aou_interrupt_mask.int_early_resp_mask, 0);
      check_pin("INT_EARLY_RESP_ERR", 1'b1, "T1-E07",
                "mask cleared with errors pending (BUGS/029)");
    end
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      string what = $sformatf("RP%0d early-response error", r);
      wr(rpf("write_early_response", r, "write_resp_err"), 1);
      check_field(rpf("write_early_response", r, "write_resp_err"), 0, "REG-R04", what);
      check_field(rpf("write_early_response", r, "write_resp_err_id_info"), 0, "T1-E11",
                  {what, ": ID clears with the error"});
      check_field(rpf("write_early_response", r, "write_resp_err_type_info"), 0, "T1-E11",
                  {what, ": type clears with the error"});
      check_pin("INT_EARLY_RESP_ERR", r + 1 < cfg.n_rp, "T1-E12",
                $sformatf("%0d of %0d RPs cleared", r + 1, cfg.n_rp));
    end
  endtask

  // ---------------------------------------------------------------------
  task multi_part();
    aou_core rm = p_sequencer.regs;
    string srcs[3] = '{"INT_EARLY_RESP_ERR", "INT_SI0_ID_MISMATCH", "INT_REQ_LINKRESET"};
    string order[$];
    bit [9:0] ids[];
    bit [9:0] bogus[];
    ids = new[cfg.n_rp];
    bogus = new[cfg.n_rp];
    drain();
    for (int unsigned r = 0; r < cfg.n_rp; r++)
      raw_write(rm.get_reg_by_name($sformatf("axi_slv_id_mismatch_err_rp%0d", r)), 32'h0040_0000);
    foreach (ids[r]) begin
      ids[r] = 10'($urandom_range(10'h1FF));
      bogus[r] = 10'($urandom_range(10'h3FF, 10'h200));
    end
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      aou_msg_wresp m = aou_msg_wresp::type_id::create("bogus_b");
      m.rp = env.l3.cfg.dest_rp[r];
      m.id = bogus[r];
      m.resp = AOU_AXI_OKAY;
      env.l3.send(m);
      fork
        automatic int unsigned rr = r;
        begin
          early_err(rr, rr + 8, ids[rr]);
          wait_early_status(rr);
        end
      join_none
    end
    env.l3.model.kick();
    wait fork;
    drain();
    env.sw_isr.wait_idle();
    env.sw_isr.enable = 1'b0;
    inject("act_ack");
    wait_cycles(1000);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      string what = $sformatf("RP%0d, all sources", r);
      check_field(rpf("write_early_response", r, "write_resp_err"), 1, "T1-E12", what);
      check_field(rpf("write_early_response", r, "write_resp_err_id_info"),
                  uvm_reg_data_t'(ids[r]), "T1-E12",
                  what);
      check_field(rpf("axi_slv_id_mismatch_err", r, "axi_slv_bid_mismatch_err"), 1, "T1-E12", what);
      check_field(rpf("axi_slv_id_mismatch_err", r, "axi_slv_bid_mismatch_info"),
                  uvm_reg_data_t'(bogus[r]),
                  "T1-E12", what);
    end
    check_field(rm.lp_linkreset.invalid_actmsg_err, 1, "T1-E12", "all sources");
    foreach (srcs[i]) check_pin(srcs[i], 1'b1, "T1-E12", "all sources pending");
    foreach (srcs[i]) order.push_back(srcs[i]);
    order.shuffle();
    foreach (order[i]) begin
      case (order[i])
        "INT_EARLY_RESP_ERR":
          for (int unsigned r = 0; r < cfg.n_rp; r++)
            wr(rpf("write_early_response", r, "write_resp_err"), 1);
        "INT_SI0_ID_MISMATCH":
          for (int unsigned r = 0; r < cfg.n_rp; r++)
            wr(rpf("axi_slv_id_mismatch_err", r, "axi_slv_bid_mismatch_err"), 1);
        default: wr(rm.lp_linkreset.invalid_actmsg_err, 1);
      endcase
      for (int unsigned j = 0; j < order.size(); j++)
        check_pin(order[j], j > i, "T1-E12", $sformatf("after clearing %s", order[i]));
    end
    recover();
  endtask

  // ---------------------------------------------------------------------
  // Trial 0 measures when the interrupt rises after the write starts (L) and
  // how long a register write takes (W); trial k starts the write-1-to-clear
  // at L - W + k, k in [-span, span], so its clearing cycle crosses the
  // setting cycle.
  task race_part();
    aou_core rm = p_sequencer.regs;
    uvm_reg_field f = rpf("write_early_response", 0, "write_resp_err");
    int unsigned span = arg_int("race_span", 24);
    int unsigned lat;
    int unsigned wlen;
    int unsigned lost = 0;
    int unsigned n_cleared = 0;
    time t0;
    drain();
    if (masked) wr(rm.aou_interrupt_mask.int_early_resp_mask, 0);
    // Fixed latencies make the sweep land where it aims.
    apply_timing(AOU_AXI_TIMING_ZERO, 0);
    early_err(0, 40, 10'h155, 4000);
    lat = rise_cyc;
    wait_early_status(0);
    t0 = $time;
    wr(f, 1);
    wlen = int'(($time - t0) / 1ns);
    check_pin("INT_EARLY_RESP_ERR", 1'b0, "T1-E10", "race: cleared before the sweep");
    if (lat == 0) begin
      `uvm_error(get_type_name(), "T1-E08: race: INT_EARLY_RESP_ERR did not rise in calibration")
      return;
    end
    `uvm_info(get_type_name(), $sformatf(
              "race: interrupt %0d cycles after the write; W1C takes %0d",
                                         lat, wlen), UVM_LOW)
    for (int k = -int'(span); k <= int'(span); k++) begin
      int start = int'(lat) - int'(wlen) + k;
      int unsigned rises0 = irq_rises("INT_EARLY_RESP_ERR");
      bit [9:0] id = 10'(k + 512);
      if (start < 0) start = 0;
      fork
        early_err(0, 41 + (k + span) % 20, id);
        begin
          wait_cycles(start);
          wr(f, 1);
        end
      join
      wait_cycles(400);
      if (irq_rises("INT_EARLY_RESP_ERR") == rises0) begin
        lost++;
        `uvm_error(get_type_name(), $sformatf({"T1-E08: race offset %0d: the early-response error ",
                   "never raised INT_EARLY_RESP_ERR; the W1C cleared it (BUGS/029)"}, k))
      end
      if (pin("INT_EARLY_RESP_ERR")) begin
        check_field(rpf("write_early_response", 0, "write_resp_err_id_info"),
                    uvm_reg_data_t'(id), "T1-E11",
                    $sformatf("race offset %0d: the late error's ID", k));
        wr(f, 1);
      end else begin
        n_cleared++;
      end
      check_pin("INT_EARLY_RESP_ERR", 1'b0, "T1-E10", $sformatf("race offset %0d: cleared", k));
    end
    apply_timing(cfg.local_timing, cfg.remote_lat_max);
    `uvm_info(get_type_name(), $sformatf({"race: %0d trials, %0d cleared after the set, ",
              "%0d still set at the end, %0d lost"}, 2 * span + 1, n_cleared,
              2 * span + 1 - n_cleared, lost),
              UVM_LOW)
  endtask
endclass
