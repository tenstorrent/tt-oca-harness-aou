// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1-C42: the DUT's RX flit framing matches the Adapter's. Every flit carries
// one header MsgCredit, at bytes 128-129 (AoU 6.4.1 Table 16), so the DUT takes
// exactly one MsgCredit per flit delivered to it, in order, with that flit's
// value. The L1 monitor of the PHY that feeds the RX path names the delivered
// flits (after cancel rollback); the DUT side is a white-box tap of the RX
// core's MsgCredit output (aou_rst_if rx_msgcrdt*), taken whatever the AoU
// activation state, since the framing does not depend on it. A delivered flit
// whose MsgCredit never comes (a flit dropped, or the DUT reading it from
// another position), a MsgCredit no delivered flit carried, or a different
// value fails within slack cycles. Not judged:
// - a MsgCredit the DUT takes while pl_state_sts is neither Active nor Reset,
//   when nothing is pending: the cancel slot of a flit the Adapter abandoned
//   on entering LinkError, which the monitor drops and the DUT may consume
//   (UCIe r1.1 Table 8-2);
// - anything pending at a reset of the link or of the core (AOU_SW_RESET).
class aou_t1_rx_align_chk extends uvm_component;
  `uvm_component_utils(aou_t1_rx_align_chk)

  uvm_analysis_imp #(aou_flit_item, aou_t1_rx_align_chk) rx_flit_imp;

  virtual aou_rst_if                      rst_vif;
  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif;   // the PHY feeding the RX path
  longint      slack = 16;    // cycles between a delivered flit and its MsgCredit

  int unsigned n_ok;
  int unsigned n_err;
  int unsigned n_may;         // MsgCredits of abandoned flits the DUT took

  protected bit [15:0]   exp_mc[$];
  protected longint      exp_cyc[$];
  protected bit [15:0]   got_mc[$];
  protected longint      got_cyc[$];
  protected bit          got_may[$];
  protected longint      cyc;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_flit_imp = new("rx_flit_imp", this);
  endfunction

  function void write(aou_flit_item it);
    exp_mc.push_back({it.data[129], it.data[128]});
    exp_cyc.push_back(cyc);
  endfunction

  protected function void fail(string msg);
    n_err++;
    aou_rule_log::fire("T1-C42", get_type_name());
    `uvm_error(get_type_name(), {"T1-C42: ", msg})
  endfunction

  protected function void flush();
    exp_mc.delete(); exp_cyc.delete();
    got_mc.delete(); got_cyc.delete(); got_may.delete();
  endfunction

  protected function void match();
    while (exp_mc.size() != 0 && got_mc.size() != 0) begin
      bit [15:0] e = exp_mc.pop_front();
      bit [15:0] g = got_mc.pop_front();
      void'(exp_cyc.pop_front());
      void'(got_cyc.pop_front());
      void'(got_may.pop_front());
      aou_rule_log::check("T1-C42", get_type_name());
      if (e == g) begin
        n_ok++;
      end else begin
        fail($sformatf({"MsgCredit 0x%04h taken for a delivered flit that carries 0x%04h ",
                        "(RX flit framing differs from the Adapter's)"}, g, e));
        flush();  // one report per desynchronisation
      end
    end
    if (got_mc.size() != 0 && got_may[0]) begin
      n_may++;
      got_mc.delete(); got_cyc.delete(); got_may.delete();
    end
    if (exp_mc.size() != 0 && cyc - exp_cyc[0] > slack) begin
      aou_rule_log::check("T1-C42", get_type_name());
      fail($sformatf("flit delivered %0d cycles ago with MsgCredit 0x%04h, not taken by the DUT",
                     cyc - exp_cyc[0], exp_mc[0]));
      flush();
    end
    if (got_mc.size() != 0 && cyc - got_cyc[0] > slack) begin
      aou_rule_log::check("T1-C42", get_type_name());
      fail($sformatf("MsgCredit 0x%04h taken %0d cycles ago, no delivered flit carries it",
                     got_mc[0], cyc - got_cyc[0]));
      flush();
    end
  endfunction

  task run_phase(uvm_phase phase);
    if (rst_vif == null || mb_vif == null) return;
    forever begin
      @(rst_vif.mon_cb);
      cyc++;
      if (rst_vif.mon_cb.rst_n !== 1'b1 || rst_vif.mon_cb.core_rst_n !== 1'b1) begin
        flush();
        continue;
      end
      if (rst_vif.mon_cb.rx_msgcrdt_valid === 1'b1) begin
        logic [3:0] sts = mb_vif.mon_cb.pl_state_sts;
        got_mc.push_back(rst_vif.mon_cb.rx_msgcrdt);
        got_cyc.push_back(cyc);
        got_may.push_back(sts != FDI_STS_ACTIVE && sts != FDI_STS_RESET);
      end
      // Monitor writes of this edge may land before or after this process;
      // match() pairs whatever both sides have queued.
      match();
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        "%0d delivered flits matched by the DUT's MsgCredit, %0d of abandoned flits taken",
        n_ok, n_may), UVM_LOW)
  endfunction
endclass
