// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Stimulus for activation with data in the RX FIFO (plan 1.10; MAS 7.3.2,
// 7.3.4). The remote die's requests follow the DUT's DeactivateReq, the
// remote die then deactivates with them unanswered, which AoU v0.8 8.4 does
// not allow a remote die but the DUT survives (they are answered after the
// next activation, MAS 7.3.5), and the DUT's M ports hold AWREADY, WREADY and
// ARREADY low, so the requests are still in its RX FIFOs when the link
// reaches DISABLED.
// Software sets ACTIVATE_START and the M ports stay held for +hold cycles,
// then drain; activation follows and every held request completes.
// aou_t1_rx_fifo_chk checks that the DUT's ActivateReq waits for the FIFO
// (T1-L40) and its credit for what is still queued (T1-C41).
// Knobs: +hold=<cycles> +loops +T1_TXN=<per RP>.
class aou_act_rx_drain_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_act_rx_drain_vseq)

  function new(string name = "aou_act_rx_drain_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned loops = arg_range("loops", 1, 2);
    link_up();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    for (int unsigned i = 0; i < loops; i++) one_loop(i + 1, loops);
    check_traffic(num_txns);
  endtask

  function int unsigned sent_open();
    int unsigned n = 0;
    foreach (env.l3.model.our_wr_out[r])
      n += env.l3.model.our_wr_out[r] + env.l3.model.our_rd_out[r];
    return n;
  endfunction

  // Every queued request must go out before the remote die's DeactivateReq,
  // and the held M ports return no credit: n single-beat requests (WriteReq and
  // ReadReq 3 granules, WriteData1024 at most 30) must fit every RP's credit.
  function int unsigned fit_credit(int unsigned n);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      int unsigned k[3];
      k[0] = cfg.l3_cfg.dut_max_cred[r][AOU_CC_WDATA] / 30;
      k[1] = cfg.l3_cfg.dut_max_cred[r][AOU_CC_WREQ] / 3;
      k[2] = cfg.l3_cfg.dut_max_cred[r][AOU_CC_RREQ] / 3;
      foreach (k[i]) if (k[i] != 0 && k[i] < n) n = k[i];
    end
    return n;
  endfunction

  task one_loop(int unsigned loop, int unsigned loops);
    aou_reg_activation_seq s = aou_reg_activation_seq::type_id::create("deact");
    int unsigned hold = arg_int("hold", 3000);
    int unsigned n = 0;
    int unsigned q = 0;
    int unsigned q0;
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
    `uvm_info(get_type_name(), $sformatf(
        "loop %0d/%0d: remote requests behind the DUT's DeactivateReq", loop, loops), UVM_LOW)
    cfg.l3_cfg.deact_own_open = 1'b1;
    foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].hold_req = 1'b1;
    // The remote die's requests wait in its packer until the DUT's DeactivateReq.
    hold_remote_tx();
    p.num_slots = 64;
    p.max_len = 8'd0;
    traffic_nb(AOU_T1_R2L, fit_credit(num_txns), p);
    do begin
      q0 = q;
      wait_cycles(50);
      q = env.l3.model.pk.queued_msgs();
    end while ((q == 0 || q != q0) && n++ < 200);
    env.sw_isr.quiesce();
    prep_reg(s);
    s.wait_done = 1'b0;
    s.op = AOU_REG_DEACTIVATE;
    s.start(null);
    n = 0;
    while (!env.l3.model.lnk.dreq_rcvd && n++ < cfg.act_timeout) wait_cycles(1);
    release_remote_tx();
    fork
      wait_l3(AOU_LS_DISABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b0, cfg.act_timeout);
    join
    env.sw_isr.hold_requests(1'b0);
    cfg.l3_cfg.deact_own_open = 1'b0;
    if (!l3_ok) `uvm_error(get_type_name(), $sformatf("T1-V04: remote (L3) not DISABLED: %s",
                                                      env.l3.model.lnk.state.name()))
    if (!env.status.act_ok)
      `uvm_error(get_type_name(), "T1-V05: DUT not DISABLED (activate_state_disabled)")
    `uvm_info(get_type_name(), $sformatf("DISABLED with %0d remote requests unanswered",
                                         sent_open()), UVM_LOW)
    // Software's ACTIVATE_START (the ISR may have set it already for
    // INT_ACTIVATE_START), with the M ports still held.
    dut_activate(AOU_T1_BY_APB);
    env.l3.model.kick();
    wait_cycles(hold);
    foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].hold_req = 1'b0;
    fork
      wait_l3(AOU_LS_ENABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b1, cfg.act_timeout);
    join
    if (!l3_ok) `uvm_error(get_type_name(), $sformatf("T1-V02: remote (L3) not ENABLED: %s",
                                                      env.l3.model.lnk.state.name()))
    if (!env.status.act_ok)
      `uvm_error(get_type_name(), "T1-V03: DUT not ENABLED (activate_state_enabled)")
    wait_traffic();
    drain();
    env.sw_isr.wait_idle();
  endtask
endclass
