// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1-L30: every ActivateReq the DUT received is answered by an ActivateAck
// whose last FDI beat transfers before lp_linkerror rises. A die answers every
// ActivateReq, valid or not (MAS software-operation 7.3), and an Adapter may
// drop whatever is not yet on FDI once it sees lp_linkerror (UCIe r1.1
// 8.3.3.7), so an Ack still inside the DUT at the rise may never be sent
// (BUGS/037 interim).
//
// An ActivateReq counts as received on the edge the last beat of its flit
// transferred to the DUT: L3 hands the flit to L1 (ap_tx_flit, right after
// ap_tx_msg names its messages), and the L1 monitor's next delivered flit
// with the same bytes outside the Adapter-owned bytes is that flit. The DUT's
// Acks answer the received Reqs in order (L3 ap_rx_msg, timed by the last
// beat of their flit). A rise is judged on the next edge, so an Ack on the
// rise edge itself counts as late. Reqs that reach the DUT on or after the
// rise edge are not judged; the rise ends every open handshake.
class aou_t1_act_chk extends uvm_component;
  `uvm_component_utils(aou_t1_act_chk)

  uvm_analysis_imp_act_txmsg #(aou_msg, aou_t1_act_chk)           tx_msg_imp;
  uvm_analysis_imp_act_txflit #(aou_l3_flit_item, aou_t1_act_chk) tx_flit_imp;
  uvm_analysis_imp_act_rxflit #(aou_flit_item, aou_t1_act_chk)    rx_flit_imp;
  uvm_analysis_imp_act_rxmsg #(aou_msg, aou_t1_act_chk)           rx_msg_imp;

  virtual aou_fdi_lsm_if vif;

  int unsigned n_reqs;
  int unsigned n_rises;

  protected int unsigned    want_flit;   // ActivateReqs in the flit L3 hands over next
  protected int unsigned    flit_reqs[$];
  protected bit [7:0]       flit_bytes[$][FLIT_BYTES];
  protected time            req_t[$];    // received, not yet answered
  protected time            done_req_t[$];
  protected time            done_ack_t[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_msg_imp = new("tx_msg_imp", this);
    tx_flit_imp = new("tx_flit_imp", this);
    rx_flit_imp = new("rx_flit_imp", this);
    rx_msg_imp = new("rx_msg_imp", this);
  endfunction

  static function bit is_act(aou_msg m, bit [3:0] op);
    aou_msg_act a;
    return $cast(a, m) && a.op == op;
  endfunction

  function void write_act_txmsg(aou_msg m);
    if (is_act(m, AOU_ACT_REQ)) want_flit++;
  endfunction

  function void write_act_txflit(aou_l3_flit_item it);
    bit [7:0] b[FLIT_BYTES];
    if (want_flit == 0) return;
    foreach (b[i]) b[i] = it.bytes[i];
    flit_bytes.push_back(b);
    flit_reqs.push_back(want_flit);
    want_flit = 0;
  endfunction

  function void write_act_rxflit(aou_flit_item f);
    if (flit_bytes.size() == 0) return;
    for (int unsigned i = 1; i < FLIT_BYTES; i++)
      if (!aou_fdi_pkg::is_adapter_byte(i) && f.data[i] != flit_bytes[0][i]) return;
    void'(flit_bytes.pop_front());
    repeat (flit_reqs.pop_front()) req_t.push_back($time);
    n_reqs++;
  endfunction

  function void write_act_rxmsg(aou_msg m);
    if (!is_act(m, AOU_ACT_ACK) || req_t.size() == 0) return;
    aou_rule_log::check("T1-L30", get_type_name());
    done_req_t.push_back(req_t.pop_front());
    done_ack_t.push_back($time);
    // A rise is judged one edge later; older answers no longer matter.
    while (done_req_t.size() > 8) begin
      void'(done_req_t.pop_front());
      void'(done_ack_t.pop_front());
    end
  endfunction

  // Reset contract: the link was reset; nothing in flight is owed an answer.
  function void reset_flush();
    want_flit = 0;
    flit_reqs.delete();
    flit_bytes.delete();
    req_t.delete();
    done_req_t.delete();
    done_ack_t.delete();
  endfunction

  task run_phase(uvm_phase phase);
    bit  prev = 1'b0;
    bit  pend = 1'b0;
    time rise_t;
    if (vif == null) return;
    forever begin
      bit cur;
      @(vif.mon_cb);
      if (pend) begin
        judge(rise_t);
        pend = 1'b0;
      end
      cur = vif.mon_cb.lp_linkerror === 1'b1;
      if (cur && !prev) begin
        rise_t = $time;
        pend = 1'b1;
      end
      prev = cur;
    end
  endtask

  protected function void judge(time rise);
    time   late_req = 0;
    time   late_ack = 0;
    bit    late = 1'b0;
    bit    missing = 1'b0;
    n_rises++;
    foreach (done_req_t[i]) begin
      if (done_req_t[i] < rise && done_ack_t[i] >= rise && !late) begin
        late = 1'b1;
        late_req = done_req_t[i];
        late_ack = done_ack_t[i];
      end
    end
    foreach (req_t[i]) begin
      if (req_t[i] < rise && !late && !missing) begin
        missing = 1'b1;
        late_req = req_t[i];
      end
    end
    if (late || missing) begin
      aou_rule_log::fire("T1-L30", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "T1-L30: lp_linkerror rose at %0t %s (ActivateReq received at %0t)", rise,
          late ? $sformatf("before the last FDI beat of the ActivateAck (%0t)", late_ack) :
                 "with the ActivateAck to an ActivateReq not yet on FDI", late_req))
    end
    req_t.delete();
    done_req_t.delete();
    done_ack_t.delete();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("%0d ActivateReqs received, %0d lp_linkerror rises",
                                         n_reqs, n_rises), UVM_LOW)
  endfunction
endclass
