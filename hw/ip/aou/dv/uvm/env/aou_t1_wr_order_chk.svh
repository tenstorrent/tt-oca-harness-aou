// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Order of the writes the DUT sends, in every test, from the DUT's messages
// alone (the remote model's own TX may send either order).
//
// DP-R10 (one-way order): a WriteData the DUT sends for RP r follows a
// WriteReq on RP r whose data is still owed. AoU v0.8 5.7 does not order a
// WriteReq against its WriteData, but the owners require the DUT's TX to send
// the request first (PR #98); a receiver may rely on it. The L3 responder
// pairs them by count and would not notice.
//
// That writes keep making progress is aou_t1_crd_flow_chk's per-RP wait
// (T1-C43). A reset, DISABLED and a new activation end every open write.
class aou_t1_wr_order_chk extends uvm_component;
  `uvm_component_utils(aou_t1_wr_order_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_wr_order_chk) rx_msg_imp;

  aou_l3_model   model;
  bit            enable = 1'b1;

  // Beats still owed by each open write per wire RP, oldest first.
  protected int unsigned       owed_q[AOU_RP_MAX][$];
  protected int unsigned       epoch;

  int unsigned n_wreq;
  int unsigned n_wdata;
  int unsigned n_r10;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_msg_imp = new("rx_msg_imp", this);
  endfunction

  protected function void forget();
    foreach (owed_q[w]) owed_q[w].delete();
  endfunction

  // A new activation or DISABLED ends every open write. The link counts an
  // activation epoch on every return to DISABLED, so checking it before each
  // message is enough.
  protected function void link_check();
    if (model.lnk.epoch == epoch && model.lnk.state != AOU_LS_DISABLED) return;
    forget();
    epoch = model.lnk.epoch;
  endfunction

  // Reset contract: nothing the DUT sent before is owed any more.
  function void reset_flush();
    forget();
  endfunction

  function void write(aou_msg m);
    aou_msg_req q;
    int unsigned w = int'(m.rp);
    if (!enable || model == null || w >= AOU_RP_MAX) return;
    link_check();
    if (m.msg_type == AOU_MT_WREQ && $cast(q, m)) begin
      n_wreq++;
      owed_q[w].push_back(int'(q.len) + 1);
      return;
    end
    if (m.cred_class() != AOU_CC_WDATA) return;
    n_wdata++;
    aou_rule_log::check("DP-R10", get_type_name());
    if (owed_q[w].size() == 0) begin
      n_r10++;
      aou_rule_log::fire("DP-R10", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"DP-R10: the DUT sent a WriteData on RP%0d with no WriteReq on that RP owing data ",
           "(the DUT's TX sends each write's WriteReq before its WriteData)"}, w))
      return;
    end
    owed_q[w][0] = owed_q[w][0] - 1;
    if (owed_q[w][0] == 0) void'(owed_q[w].pop_front());
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("%0d WriteReq, %0d WriteData from the DUT; DP-R10 %0d",
                                         n_wreq, n_wdata, n_r10), UVM_LOW)
  endfunction
endclass
