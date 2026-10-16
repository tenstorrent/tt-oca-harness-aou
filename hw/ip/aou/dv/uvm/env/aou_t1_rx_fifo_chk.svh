// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Passive checks on what the DUT's RX FIFOs hold and on its deactivation gate.
// A remote WriteReq/ReadReq (3 granules) sits in the DUT's RX FIFO from the
// remote die sending it until its AW/AR handshake on the M port, give or take
// what the stages between the FIFO and the M port hold (register slice,
// splitter, width converter: at most `slack` messages per RP and class).
// Splitting only adds handshakes, so it never makes the checks stricter.
// T1-C41 (MAS 3.9: credit returns at RX FIFO dequeue): the credit the DUT still
//   holds for RP r, its maximum minus the remote die's counter, covers every
//   such message beyond the slack.
// T1-L40 (MAS 7.3.2/7.3.4: the FIFO is emptied before ActivateReq): no more
//   than the slack of them is still waiting when the DUT's ActivateReq arrives.
// T1-L46 (MAS 7.1 DEACTIVATE_TIME_OUT_VALUE, read as a quiet window: BUGS/057
//   interim): a DeactivateReq comes at least 2^(v+3) cycles (less tov_slack for
//   the TX pipeline) after the DUT's last credited message; PropertyReq=1
//   (DEACTIVATE_FORCE, BUGS/010) is exempt.
// T1-L47 (MAS 7.1 DEACTIVATE_START condition 1, CREDIT_MANAGE=0): a
//   DeactivateReq comes only once the DUT has answered every remote request
//   it had for more than cross_cycles (a request still crossing the link may
//   meet it). Responses retire the oldest open request of their kind (any RP,
//   so DEST_RP remapping does not matter): an out-of-order answer only makes
//   the check younger, never stricter.
// The checks other than T1-L46 stop for good once the remote die sends beyond its credit
// or the DUT requests LinkReset (injection tests: the DUT may drop messages).
`uvm_analysis_imp_decl(_rx_fifo_tb)

class aou_t1_rx_fifo_chk extends uvm_component;
  `uvm_component_utils(aou_t1_rx_fifo_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_rx_fifo_chk) dut_imp;   // DUT -> remote die messages
  uvm_analysis_imp_rx_fifo_tb #(aou_msg, aou_t1_rx_fifo_chk) tb_imp;   // remote die -> DUT

  aou_axi_vif_t  vif[];                        // M ports
  aou_l3_model   model;
  aou_t1_status  status;
  aou_core       rm;
  int unsigned   slack = 8;                    // messages per RP and class
  int unsigned   tov_slack = 8;                // cycles
  int unsigned   cross_cycles = 200;

  protected longint unsigned cycle;
  protected int unsigned     hs[AOU_RP_MAX][2];      // M-port AW, AR handshakes
  protected int unsigned     answered[AOU_RP_MAX][2]; // WriteResp, last ReadData the DUT sent
  protected int unsigned     base[AOU_RP_MAX][2];    // remote granules sent at the last flush
  protected bit              flagged[AOU_RP_MAX][2];
  protected bit              crd_off;
  protected bit              req_seen;
  protected longint          last_msg = -1;
  protected longint unsigned req_t[2][$];   // remote writes, reads open: send cycle

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dut_imp = new("dut_imp", this);
    tb_imp = new("tb_imp", this);
  endfunction

  // Requests the remote die sent on RP r (k: 0 WriteReq, 1 ReadReq) whose AW/AR
  // has not been taken on the M port yet. A request the DUT answered has left
  // the FIFO even without an M-port handshake (the debug FIFO window answers
  // inside the DUT).
  function int unsigned waiting(int unsigned r, int unsigned k);
    aou_cred_class_e c = k == 0 ? AOU_CC_WREQ : AOU_CC_RREQ;
    int unsigned sent = (model.crd.tx_consumed[r][c] - base[r][k]) / 3;
    int unsigned gone = (answered[r][k] > hs[r][k]) ? answered[r][k] : hs[r][k];
    return (sent > gone) ? sent - gone : 0;
  endfunction

  function void reset_flush();
    foreach (hs[r, k]) begin
      aou_cred_class_e c = k == 0 ? AOU_CC_WREQ : AOU_CC_RREQ;
      hs[r][k] = 0;
      answered[r][k] = 0;
      base[r][k] = model.crd.tx_consumed[r][c];
      flagged[r][k] = 1'b0;
    end
    req_seen = 1'b0;
    last_msg = -1;
    foreach (req_t[k]) req_t[k].delete();
  endfunction

  task run_phase(uvm_phase phase);
    if (vif.size() == 0 || model == null) return;
    reset_flush();
    forever begin
      @(vif[0].mon_cb);
      cycle++;
      foreach (vif[r]) begin
        if (vif[r] == null || r >= AOU_RP_MAX) continue;
        if (vif[r].mon_cb.awvalid === 1'b1 && vif[r].mon_cb.awready === 1'b1) hs[r][0]++;
        if (vif[r].mon_cb.arvalid === 1'b1 && vif[r].mon_cb.arready === 1'b1) hs[r][1]++;
      end
      if (!crd_off && (model.crd.tx_underflows != 0 ||
                       (status != null && status.rises["INT_REQ_LINKRESET"] != 0))) begin
        crd_off = 1'b1;
        `uvm_info(get_type_name(), "credit checks off: injection or LinkReset request", UVM_LOW)
      end
      if (crd_off) continue;
      check_held();
      if (model.lnk.req_rcvd && !req_seen) check_activate();
      req_seen = model.lnk.req_rcvd;
    end
  endtask

  protected function void check_held();
    if (!(model.lnk.state inside {AOU_LS_ENABLED, AOU_LS_DEACTIVATE})) return;
    foreach (vif[r]) begin
      if (r >= AOU_RP_MAX) continue;
      for (int unsigned k = 0; k < 2; k++) begin
        aou_cred_class_e c = k == 0 ? AOU_CC_WREQ : AOU_CC_RREQ;
        int unsigned mx = model.cfg.dut_max_cred[r][c];
        int unsigned w = waiting(r, k);
        int unsigned held;
        bit bad;
        if (mx == 0 || model.crd.tx_cred[r][c] > mx) continue;
        held = mx - model.crd.tx_cred[r][c];
        bad = 3 * w > held + 3 * slack;
        if (bad && !flagged[r][k]) begin
          aou_rule_log::fire("T1-C41", get_type_name());
          `uvm_error(get_type_name(), $sformatf(
              {"T1-C41: RP%0d %s: the DUT holds %0d credits but %0d requests (%0d granules) ",
               "still wait for the M port; at most %0d may have left the RX FIFO"},
              r, aou_cc_name(c), held, w, 3 * w, slack))
        end
        if (!flagged[r][k]) aou_rule_log::check("T1-C41", get_type_name());
        flagged[r][k] = bad;
      end
    end
  endfunction

  protected function void check_activate();
    foreach (vif[r]) begin
      if (r >= AOU_RP_MAX) continue;
      for (int unsigned k = 0; k < 2; k++) begin
        int unsigned w = waiting(r, k);
        aou_rule_log::check("T1-L40", get_type_name());
        if (w > slack) begin
          aou_rule_log::fire("T1-L40", get_type_name());
          `uvm_error(get_type_name(), $sformatf(
              {"T1-L40: DUT ActivateReq with %0d remote %s on RP%0d still in its RX FIFO ",
               "(M port has not taken them; slack %0d)"},
              w, k == 0 ? "WriteReq" : "ReadReq ", r, slack))
        end
      end
    end
  endfunction

  function void write_rx_fifo_tb(aou_msg m);
    if (int'(m.rp) >= vif.size()) return;   // beyond RP_COUNT: dropped (plan 9.15)
    if (m.msg_type == AOU_MT_WREQ) req_t[0].push_back(cycle);
    if (m.msg_type == AOU_MT_RREQ) req_t[1].push_back(cycle);
  endfunction

  protected function void retire(aou_msg m);
    aou_msg_rdata rd;
    if (m.msg_type == AOU_MT_WRESP) begin
      if (req_t[0].size() != 0) void'(req_t[0].pop_front());
      if (int'(m.rp) < AOU_RP_MAX) answered[m.rp][0]++;
    end
    if ($cast(rd, m) && rd.last) begin
      if (req_t[1].size() != 0) void'(req_t[1].pop_front());
      if (int'(m.rp) < AOU_RP_MAX) answered[m.rp][1]++;
    end
  endfunction

  protected function void check_answered();
    string kind[2] = '{"write(s)", "read(s)"};
    if (crd_off || rm == null || rm.aou_con0.credit_manage.get_mirrored_value() != 0) return;
    foreach (req_t[k]) begin
      aou_rule_log::check("T1-L47", get_type_name());
      if (req_t[k].size() != 0 && cycle - req_t[k][0] > 64'(cross_cycles)) begin
        aou_rule_log::fire("T1-L47", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            {"T1-L47: DUT DeactivateReq (CREDIT_MANAGE=0) with %0d remote %s unanswered, ",
             "the oldest sent %0d cycles before"}, req_t[k].size(),
            kind[k], cycle - req_t[k][0]))
      end
    end
  endfunction

  function void write(aou_msg m);
    aou_msg_act a;
    if (m.cred_class() != AOU_CC_NONE) begin
      last_msg = longint'(cycle);
      retire(m);
      return;
    end
    if ($cast(a, m) && a.op == AOU_DEACT_REQ) check_answered();
    if (!$cast(a, m) || a.op != AOU_DEACT_REQ || a.property_req || rm == null) return;
    if (last_msg >= 0) begin
      int unsigned v = int'(rm.aou_init.deactivate_time_out_value.get_mirrored_value());
      longint gap = longint'(cycle) - last_msg;
      longint win = longint'(1) << (v + 3);
      aou_rule_log::check("T1-L46", get_type_name());
      `uvm_info(get_type_name(), $sformatf(
          {"DeactivateReq %0d cycles after the DUT's last credited message ",
           "(TIME_OUT_VALUE %0d: %0d)"},
          gap, v, win), UVM_MEDIUM)
      if (gap + longint'(tov_slack) < win) begin
        aou_rule_log::fire("T1-L46", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            {"T1-L46: DeactivateReq %0d cycles after the DUT's last credited message; ",
             "DEACTIVATE_TIME_OUT_VALUE=%0d needs %0d idle cycles"}, gap, v, win))
      end
    end
  endfunction
endclass
