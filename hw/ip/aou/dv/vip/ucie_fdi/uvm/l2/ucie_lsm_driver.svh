// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Adapter side of the FDI link state (UCIe r1.1 §8.2.3-8.2.9, §8.3.3):
// drives pl_state_sts on every PHY, pl_inband_pres, pl_clk_req,
// pl_wake_ack and pl_rx_active_req, and runs Adapter-initiated events from
// ucie_lsm_item. pl_wake_ack follows lp_wake_req in the background. Before
// leaving Active it closes the L1 gates (flit boundary in both directions)
// and lowers rx_active (FDI-R29); every entry to Active repeats the
// rx_active handshake (FDI-R34). Reset aborts the current event.
//
// With cfg.react_en and cfg.react_linkerror_en the Adapter also answers the
// DUT's lp_linkerror while no event runs and the link is
// Active (r3.0 Table 10-3): LinkError, then Reset on its own internal request
// after the dwell (software clearing the error; r3.0 §10.3.3.7). Every
// LinkError, whoever entered it, is held while lp_linkerror is 1 (Table 10-3:
// "It must stay there as long as lp_linkerror=1"). A later LSM_EV_LINKERROR,
// the test's own answer to the same request, then only runs the bringup. The model answers no other
// request of the Protocol Layer: a PM entry the Protocol Layer requests
// (lp_state_req L1/L2) is not modelled.
// After LinkError/LinkReset/Disabled -> Reset the training restarts on
// cfg.restart_on (UCIe r3.0 §10.3.3.8 allows either trigger): by default
// software on the UCIe controller restarts it (cfg.sw_restart_delay cycles,
// its Start UCIe Link Training), or the Protocol Layer's NOP->Active on
// lp_state_req does, even before pl_inband_pres, or whichever comes first.
//
// In Reset the Adapter starts the Active entry only on a request: lp_state_req
// NOP for at least one clock while pl_state_sts is Reset, then Active (r3.0
// §10.3.3.1 rule 1, Table 10-4 note a). The NOP may come at any time in that
// Reset, before pl_inband_pres too; an Active held into Reset from the state
// before (an exit request in LinkError, LinkReset or Disabled, Table 10-4) is
// not one. track_reset_req follows it, afresh on every entry to Reset. With
// cfg.remote_active_first_pct the rx_active handshake of an Active entry from
// Reset or Retrain may come before the request (the remote die went first).
//
// The status outputs follow the state: pl_protocol_vld rises with
// pl_inband_pres and falls on entry to LinkError or Reset (r3.0 Table 10-3),
// pl_phyinl1 is high in L1 and, with cfg.recenter_en, pl_phyinrecenter while
// the link trains. pl_protocol, pl_protocol_flitfmt, pl_speedmode,
// pl_max_speedmode and pl_lnk_cfg hold the cfg's values; pl_phyinl2,
// pl_cerror, pl_nferror and pl_trainerror stay 0 (no L2, no error reporting).
//
// Events can also end another way (ucie_lsm_item::to): a Retrain that ends in
// LinkError, LinkReset or Disabled, a LinkReset or Disabled that escalates to
// LinkError, and LSM_EV_ABORT, a bringup or a PM exit from L1 that the
// Adapter abandons part-way (do_abort). LinkError may follow any state,
// Disabled and LinkReset any but LinkError (UCIe r3.0 Figure 10-19).
//
// The Protocol Layer may gate its clocks in Reset, LinkReset, Disabled and L1
// (r3.0 §10.2.3; lsm_gated). Every status change out of one of those states
// follows r3.0 §10.2.3.2: to anything but LinkError pl_clk_req is raised
// first and held until the new status is out (rule 7); to LinkError it comes
// first as well, except where an abort deliberately reports the status first,
// and then the Adapter waits for lp_clk_ack before its next transition (rule
// 6). Every move of pl_inband_pres, pl_rx_active_req, pl_phyinl1 or
// pl_phyinrecenter in one of those states is covered by a pl_clk_req handshake
// (rule 5). The link-state monitor checks all three (FDI-R20, R21, R22).
class ucie_lsm_driver extends uvm_driver #(ucie_lsm_item);
  `uvm_component_utils(ucie_lsm_driver)

  virtual ucie_fdi_lsm_if lsm_vif;
  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[2];
  ucie_lsm_cfg     cfg;
  ucie_fdi_agent   phy[$];       // the link's mainband agents (ucie_lsm_agent::phy)
  ucie_lsm_fcov    fcov;         // the model's own coverage; null: none
  ucie_lsm_state_e state = LSM_RESET;
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
  local time      clk_req_t;     // when pl_clk_req last rose
  local bit       wake_ack_q;
  local bit       wake_ack_hold; // an abort keeps pl_wake_ack low (ucie_lsm_item::hold_wake_ack)
  local bit       rx_req_q;
  // lp_state_req in Reset (track_reset_req): rst_req 0 nothing yet, 1 NOP
  // seen, 2 Active after a NOP (a request; back to 1 on NOP); pl_restart the
  // Protocol Layer has given NOP->Active in this Reset (the training trigger,
  // r3.0 §10.3.3.8, kept when it returns to NOP); rst_t when the status last
  // entered Reset (the request is observed from the next clock on).
  local int unsigned rst_req;
  local bit       pl_restart;
  local time      rst_t;
  local ucie_fdi_gate         gate[$];  // of each mainband agent
  local ucie_fdi_tx_responder rsp[$];   // of each mainband agent; null when passive

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    foreach (phy[i]) begin
      gate.push_back(phy[i].cfg.gate);
      rsp.push_back(phy[i].rsp);
    end
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
            error_loop();
            reset_req_loop();
            restart_loop();
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

  // Everything the Adapter drives, back to its reset value; at time 0 and on
  // every reset.
  local task drive_idle();
    lsm_vif.drv_cb.pl_protocol <= cfg.protocol;
    lsm_vif.drv_cb.pl_protocol_flitfmt <= UCIE_FLITFMT_6;
    lsm_vif.drv_cb.pl_speedmode <= cfg.speedmode;
    lsm_vif.drv_cb.pl_max_speedmode <= cfg.max_speedmode;
    lsm_vif.drv_cb.pl_lnk_cfg <= cfg.lnk_cfg;
    lsm_vif.drv_cb.pl_phyinl2 <= 1'b0;
    lsm_vif.drv_cb.pl_cerror <= 1'b0;
    lsm_vif.drv_cb.pl_nferror <= 1'b0;
    lsm_vif.drv_cb.pl_trainerror <= 1'b0;
    lsm_vif.drv_cb.pl_protocol_vld <= 1'b0;
    set_recenter(1'b0);
    set_state(LSM_RESET);
    set_inband(1'b0);
    set_clk_req(1'b0);
    set_rx_req(1'b0);
    foreach (gate[i]) gate[i].open = 1'b0;
    foreach (gate[i]) gate[i].rx_early = 1'b0;
    foreach (gate[i]) gate[i].retrain_req = 1'b0;
    link_active = 1'b0;
    down_reset = 1'b0;
    wake_ack_hold = 1'b0;
    rst_req = 0;
    pl_restart = 1'b0;
    rst_t = $time;
  endtask

  local task main_loop();
    ev_busy = 1'b1;
    if (cfg.auto_bringup) begin
      if (fcov != null) fcov.sample_own(ucie_lsm_fcov::EV_BRINGUP);
      do_bringup();
    end
    ev_busy = 1'b0;
    forever begin
      seq_item_port.get_next_item(req);
      busy = 1'b1;
      while (reacting) @(lsm_vif.drv_cb);
      ev_busy = 1'b1;
      `uvm_info(get_type_name(), {"event ", req.convert2string()}, UVM_MEDIUM)
      if (fcov != null) fcov.sample_event(req);
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
        `uvm_info(get_type_name(), "lp_linkerror: Adapter enters LinkError (r3.0 Table 10-3)",
                  UVM_LOW)
        n_le_react++;
        if (fcov != null) fcov.sample_own(ucie_lsm_fcov::EV_LINKERROR_ON_REQUEST);
        linkerror_down(cfg.dwell());
        le_absorbed = 1'b1;
        reacting = 1'b0;
      end
    end
  endtask

  // The Adapter's answer to a PM exit the Protocol Layer starts in L1
  // (lp_wake_req; UCIe r3.0 §10.2.9): pl_wake_ack (wake_responder), the
  // pl_clk_req handshake before the status leaves L1 (§10.2.3.2 rule 7),
  // Retrain, and Active once the DUT requests it. A Protocol Layer does this
  // when it has traffic to send while the link is in L1.
  local task pm_exit_loop();
    forever begin
      @(lsm_vif.drv_cb);
      if (!cfg.react_en || busy || ev_busy || reacting || state != LSM_L1 ||
          lsm_vif.drv_cb.lp_wake_req !== 1'b1)
        continue;
      reacting = 1'b1;
      `uvm_info(get_type_name(), "lp_wake_req in L1: Adapter exits L1 (8.2.9)", UVM_LOW)
      if (fcov != null) fcov.sample_own(ucie_lsm_fcov::EV_L1_EXIT_ON_WAKE);
      wait_cycles(cfg.lat());
      move_to(LSM_RETRAIN);
      wait_req(LSM_REQ_ACTIVE, "FDI-R41");
      clk_handshake(1'b0);
      active_entry();
      reacting = 1'b0;
    end
  endtask

  // Follows lp_state_req in Reset on every clock, so a NOP given while no
  // event waits for the request (before pl_inband_pres, say) still counts.
  local task reset_req_loop();
    forever begin
      @(lsm_vif.drv_cb);
      track_reset_req();
    end
  endtask

  // lp_state_req while pl_state_sts is Reset (UCIe r3.0 §10.3.3.1 rule 1):
  // NOP seen for a clock, then Active, is a request; a held Active, or one
  // that follows any other request, is not. Samples from the clock after the
  // status entered Reset (set_state restarts it). Every process that decides
  // on rst_req or pl_restart calls this first, on a clock edge, so it decides
  // on that clock's sample whichever process the simulator runs first; a
  // second call on the same sample changes nothing.
  local function void track_reset_req();
    logic [3:0] r;
    if (state != LSM_RESET || $time == rst_t) return;
    r = lsm_vif.drv_cb.lp_state_req;
    if (r === req_code(LSM_REQ_NOP)) begin
      rst_req = 1;
    end else if (r === req_code(LSM_REQ_ACTIVE)) begin
      if (rst_req != 0) begin
        rst_req = 2;
        pl_restart = 1'b1;
      end
    end else begin
      rst_req = 0;
    end
  endfunction

  // cfg.restart_on PL or EITHER: a link left in Reset after a link-down, with
  // no event running, trains again on the Protocol Layer's NOP->Active (UCIe
  // r3.0 §10.3.3.8: "The Adapter must trigger this on RDI if the Protocol
  // Layer has triggered this even if pl_inband_pres = 0").
  local task restart_loop();
    forever begin
      @(lsm_vif.drv_cb);
      track_reset_req();
      if (cfg.restart_on == LSM_RESTART_SW || !cfg.react_en || busy || ev_busy || reacting ||
          state != LSM_RESET || !down_reset || !pl_restart)
        continue;
      reacting = 1'b1;
      `uvm_info(get_type_name(), "NOP->Active in Reset: the Adapter trains the link again",
                UVM_MEDIUM)
      do_bringup();
      reacting = 1'b0;
    end
  endtask

  // A framing error the Adapter flagged on pl_error (an L1 gate's
  // retrain_req): the Adapter retrains the link (UCIe r3.0 Table 10-3
  // pl_error), and the PL driver replays the cancelled half once the link is
  // Active again. Waits for any event in progress; one Retrain serves every
  // request made before it.
  local task error_loop();
    forever begin
      bit req;
      @(lsm_vif.drv_cb);
      if (busy || ev_busy || reacting || state != LSM_ACTIVE || !link_active) continue;
      foreach (gate[i]) req |= gate[i].retrain_req;
      if (!req) continue;
      reacting = 1'b1;
      foreach (gate[i]) gate[i].retrain_req = 1'b0;
      `uvm_info(get_type_name(), "pl_error: the Adapter retrains the link", UVM_MEDIUM)
      if (fcov != null) fcov.sample_own(ucie_lsm_fcov::EV_RETRAIN_ON_ERROR);
      do_retrain(cfg.dwell());
      reacting = 1'b0;
    end
  endtask

  task execute(ucie_lsm_item it);
    int unsigned dwell = it.cycles != 0 ? it.cycles : cfg.dwell();
    if (it.kind != LSM_EV_LINKERROR) le_absorbed = 1'b0;
    case (it.kind)
      LSM_EV_BRINGUP:     do_bringup();
      LSM_EV_RETRAIN:     do_retrain(dwell, it.to);
      LSM_EV_LINKERROR:   do_linkerror(dwell);
      LSM_EV_L1_ENTRY:    do_l1_entry();
      LSM_EV_L1_EXIT:     do_l1_exit();
      LSM_EV_LINK_RESET:  do_link_reset(dwell, it.to == LSM_LINKERROR);
      LSM_EV_INBAND_DROP: do_inband_drop(dwell);
      LSM_EV_CLK_WAKE:    do_clk_wake();
      LSM_EV_DISABLED:    do_disabled(dwell, it.to == LSM_LINKERROR);
      LSM_EV_ABORT:       do_abort(it, dwell);
      default:            wait_cycles(dwell);
    endcase
  endtask

  // -------------------------------------------------------------------------
  // Signal helpers
  // -------------------------------------------------------------------------
  task set_state(ucie_lsm_state_e s);
    bit ok;
    logic [3:0] code = sts_code(s, ok);
    bit ok_r;
    logic [3:0] rst_code = sts_code(LSM_RESET, ok_r);
    if (!ok) `uvm_fatal(get_type_name(), {s.name(), " has no pl_state_sts encoding"})
    if (s != state) `uvm_info(get_type_name(), $sformatf("pl_state_sts %s -> %s (0x%0h)",
                                                         state.name(), s.name(), code), UVM_MEDIUM)
    if (s != state && s inside {LSM_LINKERROR, LSM_RESET})
      lsm_vif.drv_cb.pl_protocol_vld <= 1'b0;
    lsm_vif.drv_cb.pl_phyinl1 <= s == LSM_L1;
    // Retrain is training; Active and the link-down states are not. Reset
    // keeps the value: a bringup raises it when training starts.
    if (s == LSM_RETRAIN) set_recenter(1'b1);
    else if (s != LSM_RESET) set_recenter(1'b0);
    if (s == LSM_RESET && state != LSM_RESET) begin
      rst_t = $time;
      rst_req = 0;
      pl_restart = 1'b0;
    end
    state = s;
    if (s inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}) down_reset = 1'b1;
    for (int p = 0; p < cfg.n_phy && p < 2; p++) begin
      if (p == 0) mb_vif[0].lsm_cb.pl_state_sts <= parked(p) ? rst_code : code;
      else mb_vif[1].lsm_cb.pl_state_sts <= parked(p) ? rst_code : code;
    end
  endtask

  // The FDI the Protocol Layer does not follow, kept in Reset (cfg.park_idle_phy).
  function bit parked(int unsigned p);
    return cfg.park_idle_phy && cfg.n_phy > 1 && p != cfg.active_phy;
  endfunction

  // pl_protocol_vld is 1 whenever pl_inband_pres is (the values are valid
  // before the Protocol Layer samples them, r3.0 Table 10-3).
  local task set_inband(bit v);
    lsm_vif.drv_cb.pl_inband_pres <= v;
    if (v) lsm_vif.drv_cb.pl_protocol_vld <= 1'b1;
  endtask

  local task set_recenter(bit v);
    lsm_vif.drv_cb.pl_phyinrecenter <= v && cfg.recenter_en;
  endtask

  local task set_clk_req(bit v);
    if (v && !clk_req_q) clk_req_t = $time;
    clk_req_q = v;
    lsm_vif.drv_cb.pl_clk_req <= v;
  endtask

  local task set_rx_req(bit v);
    rx_req_q = v;
    lsm_vif.drv_cb.pl_rx_active_req <= v;
  endtask

  task wait_cycles(int unsigned n);
    repeat (n) @(lsm_vif.drv_cb);
  endtask

  // A status change. Out of a state where the Protocol Layer may be clock
  // gated (lsm_gated) pl_clk_req goes first, acknowledged or at least one clock
  // before the change (UCIe r3.0 §10.2.3.2 rule 7; for LinkError, rule 6's
  // first option). It stays high past the change; the caller releases it
  // (clk_release) when its sequence allows.
  local task move_to(ucie_lsm_state_e s);
    if (s != state && lsm_gated(state)) begin
      if (!clk_req_q) clk_handshake(1'b1);
      else if (clk_req_t == $time) @(lsm_vif.drv_cb);
    end
    set_state(s);
  endtask

  // Release pl_clk_req a clock after a status change at the earliest, so it is
  // still high when the new status is seen (rule 7: "it must stay asserted
  // until the state status transitions").
  local task clk_release();
    if (!clk_req_q) return;
    @(lsm_vif.drv_cb);
    clk_handshake(1'b0);
  endtask

  // Wait until a DUT output reaches `v`; an error after req_timeout cycles.
  local task wait_dut(string sig, logic [3:0] v, string rule);
    int unsigned n;
    ucie_rule_log::check(rule, get_type_name());
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
        ucie_rule_log::fire(rule, get_type_name());
        `uvm_error(get_type_name(), $sformatf("%s: %s stayed 0x%0h, waited %0d cycles for 0x%0h",
                                              rule, sig, cur, n, v))
        return;
      end
    end
  endtask

  local task wait_req(ucie_lsm_req_e r, string rule);
    wait_dut("lp_state_req", req_code(r), rule);
  endtask

  // In Reset: wait for the Protocol Layer's request to leave it, NOP for a
  // clock and then Active (track_reset_req; UCIe r3.0 §10.3.3.1 rule 1); an
  // error after req_timeout cycles (FDI-R33, a liveness bound). Called on a
  // clock edge; a trigger withdrawn to NOP by this clock is no request.
  local task wait_reset_active();
    int unsigned n;
    ucie_rule_log::check("FDI-R33", get_type_name());
    track_reset_req();
    while (rst_req != 2) begin
      @(lsm_vif.drv_cb);
      track_reset_req();
      n++;
      if (cfg.req_timeout != 0 && n == cfg.req_timeout) begin
        ucie_rule_log::fire("FDI-R33", get_type_name());
        `uvm_error(get_type_name(), $sformatf({"FDI-R33: no request to leave Reset (lp_state_req ",
                   "NOP for a clock, then Active) in %0d cycles; lp_state_req is 0x%0h"}, n,
                   lsm_vif.drv_cb.lp_state_req))
        return;
      end
    end
  endtask

  // After a link-down, in Reset: wait for what restarts the training
  // (cfg.restart_on; UCIe r3.0 §10.3.3.8).
  local task restart_wait();
    int unsigned n;
    if (!down_reset) return;
    case (cfg.restart_on)
      LSM_RESTART_SW: begin
        if (cfg.sw_restart_delay != 0)
          `uvm_info(get_type_name(), $sformatf(
                    "link-down: software restarts the link in %0d cycles", cfg.sw_restart_delay),
                    UVM_MEDIUM)
        wait_cycles(cfg.sw_restart_delay);
      end
      LSM_RESTART_PL: begin
        ucie_rule_log::check("FDI-R33", get_type_name());
        track_reset_req();
        while (!pl_restart) begin
          @(lsm_vif.drv_cb);
          track_reset_req();
          if (cfg.req_timeout != 0 && ++n == cfg.req_timeout) begin
            ucie_rule_log::fire("FDI-R33", get_type_name());
            `uvm_error(get_type_name(), $sformatf({"FDI-R33: link-down, and no NOP->Active on ",
                       "lp_state_req to restart the training in %0d cycles"}, n))
            break;
          end
        end
      end
      default: begin
        track_reset_req();
        while (!pl_restart && n < cfg.sw_restart_delay) begin
          @(lsm_vif.drv_cb);
          track_reset_req();
          n++;
        end
      end
    endcase
    if (pl_restart)
      `uvm_info(get_type_name(), "link-down: the Protocol Layer's NOP->Active restarts the link",
                UVM_MEDIUM)
    down_reset = 1'b0;
  endtask

  // Whether this Active entry starts with the rx_active handshake, before the
  // Protocol Layer's request (cfg.remote_active_first_pct).
  local function bit remote_first();
    return cfg.remote_active_first_pct != 0 && $urandom_range(99) < cfg.remote_active_first_pct;
  endfunction

  local task wake_responder();
    forever begin
      @(lsm_vif.drv_cb);
      if (lsm_vif.drv_cb.rst_n !== 1'b1) begin
        wake_ack_q = 1'b0;
        lsm_vif.drv_cb.pl_wake_ack <= 1'b0;
      end else if ((lsm_vif.drv_cb.lp_wake_req === 1'b1) != wake_ack_q &&
                   !(wake_ack_hold && !wake_ack_q)) begin
        bit want = !wake_ack_q;
        repeat (cfg.lat() - 1) @(lsm_vif.drv_cb);
        if ((lsm_vif.drv_cb.lp_wake_req === 1'b1) == want && !(want && wake_ack_hold)) begin
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
    foreach (gate[i]) gate[i].open = 1'b0;
    foreach (gate[i]) gate[i].rx_early = 1'b0;
    wait_cycles(2);
    foreach (gate[i]) begin
      while (!gate[i].quiet()) begin
        @(lsm_vif.drv_cb);
        if (++n == 100000) begin
          `uvm_error(get_type_name(), $sformatf("phy%0d mainband never reached a flit boundary", i))
          return;
        end
      end
    end
  endtask

  // With cfg.rx_early the RX mainband opens once rx_active req and sts are
  // both 1, while pl_state_sts is still Reset (UCIe r3.0 §10.2.7 rule 3). An
  // rx_active handshake already started (remote_first) is only completed.
  local task active_entry();
    wait_cycles(cfg.lat());
    if (rx_req_q) wait_dut("lp_rx_active_sts", 4'h1, "FDI-R26");
    else rx_active(1'b1);
    if (cfg.rx_early > 0 && state == LSM_RESET) begin
      foreach (gate[i]) gate[i].abort = 1'b0;
      foreach (gate[i]) gate[i].rx_early = !parked(i);
      wait_cycles(cfg.rx_early);
    end
    wait_cycles(cfg.lat());
    set_state(LSM_ACTIVE);
    foreach (gate[i]) gate[i].abort = 1'b0;
    foreach (gate[i]) gate[i].open = !parked(i);
    foreach (gate[i]) gate[i].rx_early = 1'b0;
    link_active = 1'b1;
  endtask

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  // UCIe r3.0 §10.2.8: clk_req handshake, inband_pres, then wait for the
  // DUT's request to leave Reset (NOP for a clock, then Active; §10.3.3.1
  // rule 1, FDI-R33) and run the Active entry. pl_clk_req is high from before
  // pl_inband_pres until the status has left Reset (§10.2.3.2 rules 5 and 7);
  // with cfg.clk_req_hold_bringup 0 it is released as pl_inband_pres rises
  // (the Protocol Layer, still ungated then, sees it) and raised again before
  // pl_rx_active_req and Active. After a link-down the training waits for its
  // restart (restart_wait, cfg.restart_on; §10.3.3.8). With remote_first the
  // rx_active handshake comes before the request (§10.2.7 rule 1, §10.2.8
  // step 4), under pl_clk_req.
  task do_bringup();
    move_to(LSM_RESET);
    restart_wait();
    wait_cycles(cfg.lat());
    clk_handshake(1'b1);
    set_recenter(1'b1);
    wait_cycles(cfg.lat());
    set_inband(1'b1);
    if (!cfg.clk_req_hold_bringup) clk_handshake(1'b0);
    if (remote_first()) begin
      @(lsm_vif.drv_cb);
      if (!clk_req_q) clk_handshake(1'b1);
      rx_active(1'b1);
    end
    wait_reset_active();
    if (!clk_req_q) clk_handshake(1'b1);
    active_entry();
    clk_release();
  endtask

  // Retrain entered from Active ends on a NOP->Active request (UCIe r3.0
  // §10.3.3.4 rule 1). The Adapter registers that transition whenever it
  // happens in Retrain, including during the dwell, and starts Active entry
  // after both the dwell and the transition; with remote_first it raises
  // pl_rx_active_req a clock into the dwell, before the request
  // (§10.2.7 rule 1). With `to` LinkError, LinkReset or Disabled it
  // ends there instead after the dwell (all legal exits of Retrain, §10.3.3;
  // no clk_req handshake: UCIe r3.0 §10.2.3.2 rules 6 and 7 cover Reset,
  // LinkReset, Disabled and PM only). A LinkError the DUT raises on lp_linkerror meanwhile is answered as
  // in Active (r3.0 Table 10-3: LinkError, held while lp_linkerror is 1).
  task do_retrain(int unsigned dwell, ucie_lsm_state_e to = LSM_UNKNOWN);
    int unsigned trig = 0;
    int unsigned n = 0;
    bit          rx_first;
    if (state != LSM_ACTIVE) begin
      `uvm_error(get_type_name(), $sformatf("Retrain requested in %s; ignored", state.name()))
      return;
    end
    if (!(to inside {LSM_UNKNOWN, LSM_ACTIVE, LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}))
      `uvm_fatal(get_type_name(), {"a Retrain cannot end in ", to.name()})
    close_gates();
    rx_active(1'b0);
    set_state(LSM_RETRAIN);
    if (to inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}) begin
      wait_cycles(dwell);
      `uvm_info(get_type_name(), {"Retrain ends in ", to.name()}, UVM_LOW)
      if (to == LSM_LINKERROR) linkerror_down(dwell);
      else link_down(to, dwell);
      if (cfg.rebringup_after_down) do_bringup();
      return;
    end
    ucie_rule_log::check("FDI-R48", get_type_name());
    rx_first = remote_first();
    while (n < dwell || trig < 2) begin
      @(lsm_vif.drv_cb);
      n++;
      if (rx_first && n == 1 && !rx_req_q && lsm_vif.drv_cb.lp_rx_active_sts === 1'b0)
        set_rx_req(1'b1);
      if (cfg.react_en && cfg.react_linkerror_en && lsm_vif.drv_cb.lp_linkerror === 1'b1) begin
        `uvm_info(get_type_name(),
                  "lp_linkerror in Retrain: Adapter enters LinkError (r3.0 Table 10-3)", UVM_LOW)
        n_le_react++;
        if (fcov != null) fcov.sample_own(ucie_lsm_fcov::EV_LINKERROR_ON_REQUEST);
        linkerror_down(cfg.dwell());
        if (cfg.rebringup_after_down) do_bringup();
        return;
      end
      trig = retrain_trigger(trig);
      if (n >= dwell && cfg.req_timeout != 0 && n - dwell == cfg.req_timeout) begin
        ucie_rule_log::fire("FDI-R48", get_type_name());
        `uvm_error(get_type_name(), $sformatf({"FDI-R48: no NOP->Active request on lp_state_req ",
                   "%0d cycles after the Retrain dwell"}, cfg.req_timeout))
        break;
      end
    end
    active_entry();
  endtask

  // NOP->Active progress in Retrain: 0 none, 1 NOP seen, 2 Active after NOP
  // (stays 2: the Adapter has taken the request).
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
      foreach (gate[i]) begin
        tx |= gate[i].tx_busy;
        rx |= gate[i].rx_busy;
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
    if (fcov != null) fcov.sample_own(ucie_lsm_fcov::EV_LINKERROR_MID_FLIT);
    `uvm_info(get_type_name(), $sformatf("LinkError mid-flit (TX %0b, RX %0b)", tx, rx), UVM_LOW)
    link_active = 1'b0;
    foreach (gate[i]) begin
      gate[i].abort = 1'b1;
      gate[i].open = 1'b0;
      gate[i].rx_early = 1'b0;
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
  // internal request (software clearing the error; §10.3.3.7) once
  // lp_linkerror is 0 (leave_linkerror). From Reset or L1 the pl_clk_req
  // handshake comes first and is held through the dwell (UCIe r3.0 §10.2.3.2
  // rule 6; it also covers pl_inband_pres and pl_phyinl1 falling, rule 5).
  local task linkerror_down(int unsigned dwell);
    close_gates();
    move_to(LSM_LINKERROR);
    set_inband(1'b0);
    rx_active(1'b0);
    wait_cycles(dwell);
    if (clk_req_q) clk_handshake(1'b0);
    leave_linkerror();
  endtask

  // LinkError -> Reset. UCIe r3.0 Table 10-3 lp_linkerror: the Adapter stays
  // in LinkError "as long as lp_linkerror=1", and the Protocol Layer may hold
  // it as long as it likes, so the wait has no bound and no error (the monitor
  // checks the exit, FDI-R49). cfg.linkerror_hold_report only reports it.
  local task leave_linkerror();
    int unsigned n;
    while (lsm_vif.drv_cb.lp_linkerror === 1'b1) begin
      @(lsm_vif.drv_cb);
      n++;
      if (n == cfg.linkerror_hold_report)
        `uvm_info(get_type_name(), $sformatf({"lp_linkerror still 1 after %0d cycles: the ",
                  "Adapter stays in LinkError while it is held (UCIe r3.0 Table 10-3)"}, n),
                  UVM_NONE)
    end
    if (n != 0)
      `uvm_info(get_type_name(), $sformatf("lp_linkerror released (+%0d cycles)", n), UVM_MEDIUM)
    set_state(LSM_RESET);
  endtask

  // PM entry: stall the DUT TX at a flit boundary first (§8.3.2, FDI-R38).
  task do_l1_entry();
    if (state != LSM_ACTIVE) begin
      `uvm_error(get_type_name(), $sformatf("L1 entry requested in %s; ignored", state.name()))
      return;
    end
    close_gates();
    foreach (rsp[i]) if (rsp[i] != null && !parked(i)) rsp[i].stall_begin();
    rx_active(1'b0);
    set_state(LSM_L1);
    wait_cycles(cfg.lat());
    foreach (rsp[i]) if (rsp[i] != null && !parked(i)) rsp[i].stall_end();
  endtask

  // PM exit requested by the remote side: clk_req before leaving L1, then
  // Retrain, and Active once the DUT requests it (UCIe r3.0 §10.2.9,
  // §10.2.3.2 rule 7; FDI-R41).
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

  task do_link_reset(int unsigned dwell, bit escalate = 1'b0);
    link_down(LSM_LINKRESET, dwell, escalate);
    if (cfg.rebringup_after_down) do_bringup();
  endtask

  // Adapter-initiated Disabled (software Link Disable or the remote partner,
  // §8.3.3.6).
  task do_disabled(int unsigned dwell, bit escalate = 1'b0);
    link_down(LSM_DISABLED, dwell, escalate);
    if (cfg.rebringup_after_down) do_bringup();
  endtask

  // LinkReset or Disabled for `dwell` cycles, then Reset on the Adapter's
  // internal request (software on the UCIe controller; §8.3.3.5 rule 1,
  // §8.3.3.6). The DUT should request nothing meanwhile. With `escalate` the
  // Adapter goes on to LinkError before Reset (LinkReset and Disabled may both
  // move to LinkError, §8.3.3). LinkReset and Disabled are states where the
  // Protocol Layer may gate its clocks (UCIe r3.0 §10.2.3), so pl_clk_req is
  // released for the dwell and raised again before the status leaves (rules 6
  // and 7); entered from Reset or L1, the request comes first there as well.
  local task link_down(ucie_lsm_state_e s, int unsigned dwell, bit escalate = 1'b0);
    close_gates();
    rx_active(1'b0);
    move_to(s);
    set_inband(1'b0);
    clk_release();
    wait_cycles(dwell);
    if (escalate) begin
      `uvm_info(get_type_name(), {s.name(), " escalates to LinkError"}, UVM_LOW)
      move_to(LSM_LINKERROR);
      wait_cycles(dwell);
      clk_handshake(1'b0);
      leave_linkerror();
      return;
    end
    move_to(LSM_RESET);
    clk_release();
  endtask

  // The Adapter abandons a bringup, or a PM exit from L1 (it.in_l1), part-way
  // and reports it.to instead: LinkError (training or the Active entry failed,
  // UCIe §8.3.3.7), LinkReset or Disabled (software or the remote die takes the
  // link down), or, from Reset only, it drops pl_inband_pres again (UCIe r3.0
  // §10.2.3: the Protocol Layer then returns lp_state_req to NOP). Where
  // (it.at):
  //   LSM_AB_RESET       Reset, before pl_inband_pres (from Active the link
  //                      first goes down through LinkReset);
  //   LSM_AB_WAKE        it.gap cycles after the pl_clk_req that wakes the DUT:
  //                      in Reset once pl_inband_pres is 1 and pl_clk_req was
  //                      released (the DUT waits for a trigger), or in L1;
  //                      it.gap 0 sends the status first and the clk_req after;
  //   LSM_AB_REQ_ACTIVE  it.gap cycles after the DUT, woken by pl_clk_req,
  //                      requests Active, before the Active entry starts.
  // it.hold_wake_ack keeps pl_wake_ack low until then. pl_clk_req follows UCIe
  // r3.0 §10.2.3.2: for a LinkError (rule 6) before the status change and held
  // until it, or after it with the ack awaited; for LinkReset and Disabled
  // (rule 7) strictly before, so those need it.gap of at least 1 at
  // LSM_AB_WAKE (at LSM_AB_REQ_ACTIVE a request raised in the cycle the DUT is
  // found requesting Active is held a clock before the change). The request
  // is held through the dwell and until the status has left LinkReset or
  // Disabled for Reset; a pl_inband_pres drop (it.to Reset) is covered by it
  // too (rule 5). After the dwell the Adapter reports Reset and, with
  // cfg.rebringup_after_down, trains again.
  task do_abort(ucie_lsm_item it, int unsigned dwell);
    bit linkdown = it.to inside {LSM_LINKRESET, LSM_DISABLED};
    if (!(it.to inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED, LSM_RESET}))
      `uvm_fatal(get_type_name(), {"an abort cannot end in ", it.to.name()})
    if (it.to == LSM_RESET && (it.in_l1 || it.at == LSM_AB_RESET))
      `uvm_fatal(get_type_name(), "pl_inband_pres can fall only in Reset, after it rose")
    if (it.in_l1 && it.at == LSM_AB_RESET)
      `uvm_fatal(get_type_name(), "LSM_AB_RESET is no point of a PM exit")
    if (linkdown && it.at != LSM_AB_REQ_ACTIVE && it.gap == 0)
      `uvm_fatal(get_type_name(), {"pl_clk_req must come before ", it.to.name(),
                                   " (UCIe r3.0 §10.2.3.2 rule 7; it.gap 0)"})
    `uvm_info(get_type_name(), {"abort: ", it.convert2string()}, UVM_LOW)
    if (it.in_l1) begin
      if (state != LSM_ACTIVE) begin
        `uvm_error(get_type_name(), $sformatf("L1 abort requested in %s; ignored", state.name()))
        return;
      end
      do_l1_entry();
      wait_cycles(dwell);
    end else begin
      if (state != LSM_RESET) link_down(LSM_LINKRESET, dwell);
      restart_wait();
      wait_cycles(cfg.lat());
      if (it.at != LSM_AB_RESET) begin
        // Training done; pl_clk_req released with pl_inband_pres rising, so
        // the DUT waits for a trigger (the bringup test's cold start).
        clk_handshake(1'b1);
        set_recenter(1'b1);
        wait_cycles(cfg.lat());
        set_inband(1'b1);
        clk_handshake(1'b0);
        wait_cycles(cfg.lat());
      end
    end
    wake_ack_hold = it.hold_wake_ack;
    if (it.at == LSM_AB_REQ_ACTIVE) begin
      set_clk_req(1'b1);
      // In L1 the request is taken as a level (r3.0 §10.3.3.4 rule 1); in
      // Reset it is NOP for a clock, then Active (§10.3.3.1 rule 1).
      if (it.in_l1) wait_req(LSM_REQ_ACTIVE, "FDI-R41");
      else wait_reset_active();
      wait_cycles(it.gap);
    end else if (it.gap != 0) begin
      set_clk_req(1'b1);
      wait_cycles(it.gap);
    end
    if (it.to == LSM_RESET) begin
      // The DUT goes back to Reset and requests NOP; it sees the drop through
      // the pl_clk_req handshake (rule 5).
      if (!clk_req_q) set_clk_req(1'b1);
      set_inband(1'b0);
      wait_dut("lp_clk_ack", 4'h1, "FDI-R18");
      wait_cycles(dwell);
      wake_ack_hold = 1'b0;
      // Presence again with pl_clk_req held (rule 20), which wakes the DUT.
      if (!clk_req_q) clk_handshake(1'b1);
      set_inband(1'b1);
      wait_reset_active();
      active_entry();
      clk_release();
      return;
    end
    if (linkdown) move_to(it.to);
    else set_state(it.to);
    set_inband(1'b0);
    // A LinkError reported first: the clk_req handshake follows, and the
    // Adapter waits for the ack before its next transition (rule 6).
    if (!clk_req_q) set_clk_req(1'b1);
    wait_dut("lp_clk_ack", 4'h1, "FDI-R18");
    wake_ack_hold = 1'b0;
    wait_cycles(dwell);
    if (it.to == LSM_LINKERROR) begin
      clk_handshake(1'b0);
      leave_linkerror();
    end else begin
      // LinkReset or Disabled -> Reset with pl_clk_req still high (rule 7).
      move_to(LSM_RESET);
      clk_release();
    end
    if (cfg.rebringup_after_down) do_bringup();
  endtask

  // pl_inband_pres low for `dwell` cycles in Reset, then high again. It must
  // stay high in Retrain, Active, L1 and L2 (UCIe r3.0 Table 10-3), so the
  // event is a usage error anywhere else. Each move is covered by a pl_clk_req
  // handshake (§10.2.3.2 rule 5): the drop comes with the request, which is
  // released once acknowledged (after the drop the Protocol Layer may move
  // lp_state_req to NOP and gate again, §10.2.3); the rise comes after it, as
  // in the bringup. pl_clk_req ends as it was, so a bringup holding it keeps it.
  task do_inband_drop(int unsigned dwell);
    bit held = clk_req_q;
    if (state != LSM_RESET) begin
      `uvm_error(get_type_name(), $sformatf({"LSM_EV_INBAND_DROP in %s: pl_inband_pres may fall ",
                 "only in Reset (UCIe r3.0 Table 10-3); ignored"}, state.name()))
      return;
    end
    if (!clk_req_q) set_clk_req(1'b1);
    set_inband(1'b0);
    wait_dut("lp_clk_ack", 4'h1, "FDI-R18");
    if (!held) clk_handshake(1'b0);
    wait_cycles(dwell);
    if (!clk_req_q) clk_handshake(1'b1);
    wait_cycles(cfg.lat());
    set_inband(1'b1);
    if (!held) clk_handshake(1'b0);
  endtask

  task do_clk_wake();
    clk_handshake(1'b1);
    wait_cycles(cfg.lat());
    clk_handshake(1'b0);
  endtask
endclass
