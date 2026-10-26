// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Adapter side of the FDI link state (UCIe r1.1 §8.2.3-8.2.9, §8.3.3):
// drives pl_state_sts on every PHY, pl_inband_pres, pl_clk_req,
// pl_wake_ack and pl_rx_active_req, and runs Adapter-initiated events from
// aou_lsm_item. pl_wake_ack follows lp_wake_req in the background. Before
// leaving Active it closes the L1 gates (flit boundary in both directions)
// and lowers rx_active (FDI-R29); every entry to Active repeats the
// rx_active handshake (FDI-R34). Reset aborts the current event.
//
// With cfg.react_en and cfg.react_linkerror_en the Adapter also answers the DUT's lp_linkerror while no event runs and the link is
// Active (r1.1 Table 8-2): LinkError, held while lp_linkerror is 1, then
// Reset on its own internal request after the dwell (software clearing the
// error; §8.3.3.7). A later LSM_EV_LINKERROR, the test's own answer to the
// same request, then only runs the bringup. The DUT requests nothing else of
// the link (the bringup model checks that).
// The link is restarted by software on the UCIe controller, not by the DUT:
// after LinkError/LinkReset/Disabled -> Reset the Adapter waits
// cfg.sw_restart_delay cycles (software's Start UCIe Link Training) and then
// trains again by itself, without waiting for a NOP->Active request
// (§8.3.3.8 allows either trigger).
class aou_lsm_driver extends uvm_driver #(aou_lsm_item);
  `uvm_component_utils(aou_lsm_driver)

  virtual aou_fdi_lsm_if lsm_vif;
  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];
  aou_lsm_cfg     cfg;
  aou_lsm_state_e state = LSM_RESET;
  bit             link_active;   // Active and the gates are open
  int unsigned    n_le_react;    // LinkErrors entered on the DUT's lp_linkerror (react_loop)
  int unsigned    n_le;          // Adapter-initiated LinkErrors (events)
  int unsigned    n_le_mid_tx;   // ... entered inside a DUT TX flit
  int unsigned    n_le_mid_rx;   // ... entered inside an RX flit to the DUT

  local bit       busy;
  local bit       ev_busy;       // an event or the reset bringup is running
  local bit       reacting;      // answering a DUT request (react_loop)
  local bit       le_absorbed;   // react_loop took a DUT LinkError down to Reset
  local bit       down_reset;    // Reset entered from LinkError/LinkReset/Disabled
  local bit       clk_req_q;
  local bit       wake_ack_q;
  local bit       rx_req_q;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    drive_idle();
    fork
      wake_responder();
    join_none
    forever begin
      while (lsm_vif.drv_cb.rst_n !== 1'b1) @(lsm_vif.drv_cb);
      fork
        begin
          fork
            main_loop();
            react_loop();
            pm_exit_loop();
            while (lsm_vif.drv_cb.rst_n === 1'b1) @(lsm_vif.drv_cb);
          join_any
          disable fork;
        end
      join
      if (busy) begin
        busy = 1'b0;
        seq_item_port.item_done();
      end
      ev_busy = 1'b0;
      reacting = 1'b0;
      le_absorbed = 1'b0;
      drive_idle();
    end
  endtask

  local task drive_idle();
    set_state(LSM_RESET);
    set_inband(1'b0);
    set_clk_req(1'b0);
    set_rx_req(1'b0);
    lsm_vif.drv_cb.phy_type <= cfg.active_phy == 1;
    set_sw(LSM_SW_ACTIVATE, 1'b0);
    set_sw(LSM_SW_LINKERROR, 1'b0);
    foreach (cfg.gate[i]) cfg.gate[i].open = 1'b0;
    foreach (cfg.gate[i]) cfg.gate[i].rx_early = 1'b0;
    link_active = 1'b0;
    down_reset = 1'b0;
  endtask

  local task main_loop();
    ev_busy = 1'b1;
    if (cfg.auto_bringup) do_bringup();
    ev_busy = 1'b0;
    forever begin
      seq_item_port.get_next_item(req);
      busy = 1'b1;
      while (reacting) @(lsm_vif.drv_cb);
      ev_busy = 1'b1;
      `uvm_info(get_type_name(), {"event ", req.convert2string()}, UVM_MEDIUM)
      execute(req);
      ev_busy = 1'b0;
      busy = 1'b0;
      seq_item_port.item_done();
    end
  endtask

  // The Adapter's answer to the DUT's lp_linkerror.
  local task react_loop();
    forever begin
      @(lsm_vif.drv_cb);
      if (!cfg.react_en || !cfg.react_linkerror_en || busy || ev_busy || reacting ||
          state != LSM_ACTIVE || !link_active)
        continue;
      if (lsm_vif.drv_cb.lp_linkerror === 1'b1) begin
        reacting = 1'b1;
        `uvm_info(get_type_name(), "lp_linkerror: Adapter enters LinkError (Table 8-2)", UVM_LOW)
        n_le_react++;
        linkerror_down(cfg.dwell());
        le_absorbed = 1'b1;
        reacting = 1'b0;
      end
    end
  endtask

  // The Adapter's answer to a PM exit the Protocol Layer starts in L1
  // (lp_wake_req; UCIe r1.1 8.2.9): pl_wake_ack (wake_responder), Retrain,
  // and Active once the DUT requests it. The DUT does this on an activation
  // request while the link is in L1 (integrator guide 6.6): I_SW_ACTIVATE_START
  // or INT_ACTIVATE_START (pending local traffic or a remote ActivateReq with
  // ACTIVATE_START clear), not the ACTIVATE_START write itself.
  local task pm_exit_loop();
    forever begin
      @(lsm_vif.drv_cb);
      if (!cfg.react_en || busy || ev_busy || reacting || state != LSM_L1 ||
          lsm_vif.drv_cb.lp_wake_req !== 1'b1)
        continue;
      reacting = 1'b1;
      `uvm_info(get_type_name(), "lp_wake_req in L1: Adapter exits L1 (8.2.9)", UVM_LOW)
      wait_cycles(cfg.lat());
      set_state(LSM_RETRAIN);
      wait_req(LSM_REQ_ACTIVE, "FDI-R41");
      active_entry();
      reacting = 1'b0;
    end
  endtask

  task execute(aou_lsm_item it);
    int unsigned dwell = it.cycles != 0 ? it.cycles : cfg.dwell();
    if (it.kind != LSM_EV_LINKERROR) le_absorbed = 1'b0;
    case (it.kind)
      LSM_EV_BRINGUP:     do_bringup();
      LSM_EV_RETRAIN:     do_retrain(dwell);
      LSM_EV_LINKERROR:   do_linkerror(dwell);
      LSM_EV_L1_ENTRY:    do_l1_entry();
      LSM_EV_L1_EXIT:     do_l1_exit();
      LSM_EV_LINK_RESET:  do_link_reset(dwell);
      LSM_EV_INBAND_DROP: do_inband_drop(dwell);
      LSM_EV_CLK_WAKE:    do_clk_wake();
      LSM_EV_DISABLED:    do_disabled(dwell);
      default:            wait_cycles(dwell);
    endcase
  endtask

  // -------------------------------------------------------------------------
  // Signal helpers
  // -------------------------------------------------------------------------
  task set_state(aou_lsm_state_e s);
    bit ok;
    logic [3:0] code = sts_code(s, ok);
    bit ok_r;
    logic [3:0] rst_code = sts_code(LSM_RESET, ok_r);
    if (!ok) `uvm_fatal(get_type_name(), {s.name(), " has no pl_state_sts encoding"})
    if (s != state) `uvm_info(get_type_name(), $sformatf("pl_state_sts %s -> %s (0x%0h)",
                                                         state.name(), s.name(), code), UVM_MEDIUM)
    state = s;
    if (s inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}) down_reset = 1'b1;
    for (int p = 0; p < cfg.n_phy && p < 2; p++) begin
      if (p == 0) mb_vif[0].lsm_cb.pl_state_sts <= parked(p) ? rst_code : code;
      else mb_vif[1].lsm_cb.pl_state_sts <= parked(p) ? rst_code : code;
    end
  endtask

  // The PHY I_PHY_TYPE does not select, kept in Reset (cfg.park_idle_phy).
  function bit parked(int unsigned p);
    return cfg.park_idle_phy && cfg.n_phy > 1 && p != cfg.active_phy;
  endfunction

  local task set_inband(bit v);
    lsm_vif.drv_cb.pl_inband_pres <= v;
  endtask

  local task set_clk_req(bit v);
    clk_req_q = v;
    lsm_vif.drv_cb.pl_clk_req <= v;
  endtask

  local task set_rx_req(bit v);
    rx_req_q = v;
    lsm_vif.drv_cb.pl_rx_active_req <= v;
  endtask

  task set_sw(aou_lsm_sw_e which, bit v);
    case (which)
      LSM_SW_ACTIVATE: lsm_vif.drv_cb.sw_activate_start <= v;
      default:         lsm_vif.drv_cb.sw_linkerror_inject <= v;
    endcase
  endtask

  // Pulse one of the DUT's bringup software pins. Safe to call from a test
  // while an event runs.
  task pulse_sw(aou_lsm_sw_e which, int unsigned cycles = 1);
    @(lsm_vif.drv_cb);
    set_sw(which, 1'b1);
    repeat (cycles) @(lsm_vif.drv_cb);
    set_sw(which, 1'b0);
  endtask

  task wait_cycles(int unsigned n);
    repeat (n) @(lsm_vif.drv_cb);
  endtask

  // Wait until a DUT output reaches `v`; an error after req_timeout cycles.
  local task wait_dut(string sig, logic [3:0] v, string rule);
    int unsigned n;
    aou_rule_log::check(rule, get_type_name());
    forever begin
      logic [3:0] cur;
      case (sig)
        "lp_clk_ack":       cur = {3'b0, lsm_vif.drv_cb.lp_clk_ack};
        "lp_rx_active_sts": cur = {3'b0, lsm_vif.drv_cb.lp_rx_active_sts};
        default:            cur = lsm_vif.drv_cb.lp_state_req;
      endcase
      if (cur === v) return;
      @(lsm_vif.drv_cb);
      n++;
      if (cfg.req_timeout != 0 && n == cfg.req_timeout) begin
        aou_rule_log::fire(rule, get_type_name());
        `uvm_error(get_type_name(), $sformatf("%s: %s stayed 0x%0h, waited %0d cycles for 0x%0h",
                                              rule, sig, cur, n, v))
        return;
      end
    end
  endtask

  local task wait_req(aou_lsm_req_e r, string rule);
    wait_dut("lp_state_req", req_code(r), rule);
  endtask

  local task wake_responder();
    forever begin
      @(lsm_vif.drv_cb);
      if (lsm_vif.drv_cb.rst_n !== 1'b1) begin
        wake_ack_q = 1'b0;
        lsm_vif.drv_cb.pl_wake_ack <= 1'b0;
      end else if ((lsm_vif.drv_cb.lp_wake_req === 1'b1) != wake_ack_q) begin
        bit want = !wake_ack_q;
        repeat (cfg.lat() - 1) @(lsm_vif.drv_cb);
        if ((lsm_vif.drv_cb.lp_wake_req === 1'b1) == want) begin
          wake_ack_q = want;
          lsm_vif.drv_cb.pl_wake_ack <= want;
        end
      end
    end
  endtask

  local task clk_handshake(bit v);
    set_clk_req(v);
    wait_dut("lp_clk_ack", {3'b0, v}, v ? "FDI-R18" : "FDI-R19");
  endtask

  local task rx_active(bit v);
    if (v) wait_dut("lp_rx_active_sts", 4'h0, "FDI-R28");
    set_rx_req(v);
    wait_dut("lp_rx_active_sts", {3'b0, v}, v ? "FDI-R26" : "FDI-R28");
  endtask

  // Stop the mainband at a flit boundary in both directions.
  local task close_gates();
    int unsigned n;
    link_active = 1'b0;
    foreach (cfg.gate[i]) cfg.gate[i].open = 1'b0;
    foreach (cfg.gate[i]) cfg.gate[i].rx_early = 1'b0;
    wait_cycles(2);
    foreach (cfg.gate[i]) begin
      while (!cfg.gate[i].quiet()) begin
        @(lsm_vif.drv_cb);
        if (++n == 100000) begin
          `uvm_error(get_type_name(), $sformatf("phy%0d mainband never reached a flit boundary", i))
          return;
        end
      end
    end
  endtask

  // With cfg.rx_early the RX mainband opens once rx_active req and sts are
  // both 1, while pl_state_sts is still Reset (UCIe r1.1 8.2.7 rule 3).
  local task active_entry();
    wait_cycles(cfg.lat());
    rx_active(1'b1);
    if (cfg.rx_early > 0 && state == LSM_RESET) begin
      foreach (cfg.gate[i]) cfg.gate[i].abort = 1'b0;
      foreach (cfg.gate[i]) cfg.gate[i].rx_early = !parked(i);
      wait_cycles(cfg.rx_early);
    end
    wait_cycles(cfg.lat());
    set_state(LSM_ACTIVE);
    foreach (cfg.gate[i]) cfg.gate[i].abort = 1'b0;
    foreach (cfg.gate[i]) cfg.gate[i].open = !parked(i);
    foreach (cfg.gate[i]) cfg.gate[i].rx_early = 1'b0;
    link_active = 1'b1;
  endtask

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  // §8.2.8: clk_req handshake, inband_pres, then wait for the DUT's
  // NOP->Active request (FDI-R33 in the monitor) and run the Active entry.
  // After a link-down the training is software's to restart (its Start UCIe
  // Link Training write, cfg.sw_restart_delay cycles later); the DUT waits in
  // Reset meanwhile and requests nothing (the bringup model checks that).
  task do_bringup();
    set_state(LSM_RESET);
    if (down_reset && cfg.sw_restart_delay != 0) begin
      `uvm_info(get_type_name(), $sformatf("link-down: software restarts the link in %0d cycles",
                                           cfg.sw_restart_delay), UVM_MEDIUM)
      wait_cycles(cfg.sw_restart_delay);
    end
    down_reset = 1'b0;
    wait_cycles(cfg.lat());
    clk_handshake(1'b1);
    wait_cycles(cfg.lat());
    set_inband(1'b1);
    if (!cfg.clk_req_hold_bringup) clk_handshake(1'b0);
    wait_req(LSM_REQ_ACTIVE, "FDI-R33");
    active_entry();
    if (clk_req_q) clk_handshake(1'b0);
  endtask

  task do_retrain(int unsigned dwell);
    int unsigned trig = 0;
    if (state != LSM_ACTIVE) begin
      `uvm_error(get_type_name(), $sformatf("Retrain requested in %s; ignored", state.name()))
      return;
    end
    close_gates();
    rx_active(1'b0);
    set_state(LSM_RETRAIN);
    // Retrain entered from Active ends on a NOP->Active request (§8.3.3.4
    // rule 1). The Adapter registers that transition whenever it happens in
    // Retrain, including during the dwell, and starts Active entry after both
    // the dwell and the transition.
    aou_rule_log::check("FDI-R48", get_type_name());
    repeat (dwell) begin
      @(lsm_vif.drv_cb);
      trig = retrain_trigger(trig);
    end
    if (trig < 1) wait_req(LSM_REQ_NOP, "FDI-R48");
    if (trig < 2) wait_req(LSM_REQ_ACTIVE, "FDI-R48");
    active_entry();
  endtask

  // NOP->Active progress in Retrain: 0 none, 1 NOP seen, 2 Active after NOP.
  local function int unsigned retrain_trigger(int unsigned trig);
    logic [3:0] r = lsm_vif.drv_cb.lp_state_req;
    if (trig == 0 && r === req_code(LSM_REQ_NOP)) return 1;
    if (trig == 1 && r === req_code(LSM_REQ_ACTIVE)) return 2;
    return trig;
  endfunction

  task do_linkerror(int unsigned dwell);
    if (!(le_absorbed && state != LSM_ACTIVE)) begin
      n_le++;
      if (state == LSM_ACTIVE && $urandom_range(99) < cfg.le_mid_flit_pct) abort_mid_flit();
      linkerror_down(dwell);
    end
    le_absorbed = 1'b0;
    if (cfg.rebringup_after_down) do_bringup();
  endtask

  // LinkError mid-flit (r1.1 8.3.3.7): wait (bounded) until a flit is in
  // flight in either direction, then leave Active at once. L1 abandons both
  // flits, and the Protocol Layer must drop its partial ones.
  local task abort_mid_flit();
    int unsigned n;
    bit tx;
    bit rx;
    while (n < 5000) begin
      foreach (cfg.gate[i]) begin
        tx |= cfg.gate[i].tx_busy;
        rx |= cfg.gate[i].rx_busy;
      end
      if (tx || rx) break;
      @(lsm_vif.drv_cb);
      n++;
    end
    if (!(tx || rx)) begin
      `uvm_info(get_type_name(), "LinkError: no flit in flight; entered at a boundary", UVM_LOW)
      return;
    end
    if (tx) n_le_mid_tx++;
    if (rx) n_le_mid_rx++;
    `uvm_info(get_type_name(), $sformatf("LinkError mid-flit (TX %0b, RX %0b)", tx, rx), UVM_LOW)
    link_active = 1'b0;
    foreach (cfg.gate[i]) begin
      cfg.gate[i].abort = 1'b1;
      cfg.gate[i].open = 1'b0;
      cfg.gate[i].rx_early = 1'b0;
    end
    // L1 drops pl_valid and pl_trdy at the next edge; the state changes with them,
    // so no beat is offered outside Active (FDI-R35).
    @(lsm_vif.drv_cb);
    set_state(LSM_LINKERROR);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (n_le != 0)
      `uvm_info(get_type_name(), $sformatf(
                "%0d LinkErrors, %0d inside a TX flit, %0d inside an RX flit", n_le, n_le_mid_tx,
                n_le_mid_rx), UVM_LOW)
  endfunction

  // LinkError, the dwell as minimum residency, then Reset on the Adapter's
  // internal request (software clearing the error; §8.3.3.7). A LinkError the
  // DUT asked for on lp_linkerror is held while lp_linkerror is 1 (Table 8-2,
  // wait_linkerror_release).
  local task linkerror_down(int unsigned dwell);
    bit by_lp = lsm_vif.drv_cb.lp_linkerror === 1'b1;
    close_gates();
    by_lp |= lsm_vif.drv_cb.lp_linkerror === 1'b1;
    set_state(LSM_LINKERROR);
    set_inband(1'b0);
    rx_active(1'b0);
    wait_cycles(dwell);
    if (by_lp) wait_linkerror_release();
    set_state(LSM_RESET);
  endtask

  // Table 8-2: the Adapter stays in LinkError while lp_linkerror is 1. The
  // DUT lowers it once the Adapter has reported LinkError (FDI-M07), so the
  // wait is short; lp_linkerror still high after req_timeout cycles is an
  // error, and the Adapter leaves anyway so the test goes on.
  local task wait_linkerror_release();
    int unsigned n;
    aou_rule_log::check("FDI-R49", get_type_name());
    while (lsm_vif.drv_cb.lp_linkerror === 1'b1) begin
      @(lsm_vif.drv_cb);
      n++;
      if (cfg.req_timeout != 0 && n == cfg.req_timeout) begin
        aou_rule_log::fire("FDI-R49", get_type_name());
        `uvm_error(get_type_name(), $sformatf({"FDI-R49: lp_linkerror still 1 after %0d cycles in ",
                   "a LinkError the DUT requested, with the Adapter reporting LinkError: the ",
                   "Adapter cannot leave while it is held (UCIe r1.1 Table 8-2); leaving anyway"},
                   n))
        return;
      end
    end
    `uvm_info(get_type_name(), $sformatf("lp_linkerror released (+%0d cycles)", n), UVM_MEDIUM)
  endtask

  // PM entry: stall the DUT TX at a flit boundary first (§8.3.2, FDI-R38).
  task do_l1_entry();
    if (state != LSM_ACTIVE) begin
      `uvm_error(get_type_name(), $sformatf("L1 entry requested in %s; ignored", state.name()))
      return;
    end
    close_gates();
    foreach (cfg.rsp[i]) if (!parked(i)) cfg.rsp[i].stall_begin();
    rx_active(1'b0);
    set_state(LSM_L1);
    wait_cycles(cfg.lat());
    foreach (cfg.rsp[i]) if (!parked(i)) cfg.rsp[i].stall_end();
  endtask

  // PM exit requested by the remote side: clk_req before leaving L1, then
  // Retrain, and Active once the DUT requests it (§8.2.9, rules 22 and 41).
  task do_l1_exit();
    if (state != LSM_L1) begin
      `uvm_error(get_type_name(), $sformatf("L1 exit requested in %s; ignored", state.name()))
      return;
    end
    clk_handshake(1'b1);
    wait_cycles(cfg.lat());
    set_state(LSM_RETRAIN);
    wait_req(LSM_REQ_ACTIVE, "FDI-R41");
    clk_handshake(1'b0);
    active_entry();
  endtask

  task do_link_reset(int unsigned dwell);
    link_down(LSM_LINKRESET, dwell);
    if (cfg.rebringup_after_down) do_bringup();
  endtask

  // Adapter-initiated Disabled (software Link Disable or the remote partner,
  // §8.3.3.6).
  task do_disabled(int unsigned dwell);
    link_down(LSM_DISABLED, dwell);
    if (cfg.rebringup_after_down) do_bringup();
  endtask

  // LinkReset or Disabled for `dwell` cycles, then Reset on the Adapter's
  // internal request (software on the UCIe controller; §8.3.3.5 rule 1,
  // §8.3.3.6). The DUT requests nothing meanwhile (the bringup model checks
  // NOP in LINKDOWN).
  local task link_down(aou_lsm_state_e s, int unsigned dwell);
    close_gates();
    rx_active(1'b0);
    set_state(s);
    set_inband(1'b0);
    wait_cycles(dwell);
    set_state(LSM_RESET);
  endtask

  task do_inband_drop(int unsigned dwell);
    if (state != LSM_RESET)
      `uvm_info(get_type_name(), $sformatf("inband_pres drop in %s", state.name()), UVM_LOW)
    set_inband(1'b0);
    wait_cycles(dwell);
    set_inband(1'b1);
  endtask

  task do_clk_wake();
    clk_handshake(1'b1);
    wait_cycles(cfg.lat());
    clk_handshake(1'b0);
  endtask
endclass
