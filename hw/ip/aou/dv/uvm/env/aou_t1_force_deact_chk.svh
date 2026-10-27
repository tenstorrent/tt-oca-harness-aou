// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AOU_CON0.DEACTIVATE_FORCE (MAS software-operation 7.1) is an implementation-
// defined escape hatch for a deactivation that is not completing: it sends a
// DeactivateReq at once, without the DEACTIVATE_START conditions, and nothing
// is promised after it (software resets the device). The one thing checked is
// that the DeactivateReq does go out promptly (T1-L52): an APB write that sets
// the bit while the DUT is ENABLED or DEACTIVATE, the FDI link up and the
// DUT's own DeactivateReq not yet sent, must be followed by a DUT DeactivateReq
// within `bound` of the write's setup phase.
//
// The bound is taken from the RTL, the only place the latency is defined, with
// margin: the asynchronous APB bridge passes the write to the core clock in
// at most one PCLK plus about five core cycles (a two-stage synchroniser and
// the bridge's setup state, which writes the register); the activation
// controller then queues the DeactivateReq on the next cycle, and the TX core
// takes it at the next flit boundary, a few cycles more plus the Adapter's
// pl_trdy back-pressure. Allowing BOUND_PCLKS PCLK periods and BOUND_CLKS core
// cycles leaves several times that. Core cycles in which the Adapter holds
// pl_trdy low, or a stall is acknowledged, do not count: they extend both the deadline and the PropertyReq
// window below, since FDI backpressure is a stress case, not the DUT's delay.
//
// The RTL marks the forced DeactivateReq with PropertyReq=1, a bit v0.7 keeps
// for ActivateReq and v0.8 reserves. The bench accepts that mark on a DUT
// DeactivateReq only inside this window (aou_l3_cfg::force_deact_window(), used
// by aou_unpacker and aou_fdi_chk_adapter for AOU-R11); outside it the bit is
// still a reserved-field violation.
//
// Cost: one sample per PCLK edge (the APB setup phase) and per core clock while
// a forced DeactivateReq is owed.
class aou_t1_force_deact_chk extends uvm_component;
  `uvm_component_utils(aou_t1_force_deact_chk)

  localparam int unsigned BOUND_PCLKS = 4;
  localparam int unsigned BOUND_CLKS = 256;

  uvm_analysis_imp #(aou_msg, aou_t1_force_deact_chk) dut_imp;   // DUT -> remote die messages

  virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)) apb_vif;
  virtual aou_rst_if     rst_vif;   // core clock and core reset
  virtual aou_fdi_lsm_if lsm_vif;
  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) mb_vif[AOU_T1_N_PHY];
  aou_t1_env_cfg         cfg;
  aou_core               rm;
  aou_t1_status          status;
  aou_l3_cfg             l3_cfg;

  int unsigned n_forced;     // forced deactivations judged
  int unsigned n_late;       // T1-L52 reports
  realtime     max_latency;  // longest write-to-DeactivateReq seen
  realtime     bound;

  protected bit      owed;          // a forced DeactivateReq is expected
  protected realtime t_write;
  protected realtime t_held;        // FDI backpressure since the write
  protected realtime tc;            // core clock period
  protected bit      dut_deact_sent; // the DUT's DeactivateReq of this session went out
  protected bit      was_enabled;   // the DUT reached ENABLED since it was last DISABLED

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dut_imp = new("dut_imp", this);
  endfunction

  // Forced deactivations resolved so far, in time or late: a test waits on it.
  function int unsigned resolved();
    return n_forced + n_late;
  endfunction

  function void reset_flush();
    owed = 1'b0;
    dut_deact_sent = 1'b0;
    was_enabled = 1'b0;
    if (l3_cfg != null) l3_cfg.force_deact_t = -1;
  endfunction

  task run_phase(uvm_phase phase);
    realtime tp;
    if (apb_vif == null || rst_vif == null || rm == null || status == null || l3_cfg == null)
      return;
    // Clock periods, for the bound in time.
    @(apb_vif.mon_cb);
    tp = $realtime;
    @(apb_vif.mon_cb);
    tp = $realtime - tp;
    @(rst_vif.mon_cb);
    tc = $realtime;
    @(rst_vif.mon_cb);
    tc = $realtime - tc;
    bound = BOUND_PCLKS * tp + BOUND_CLKS * tc;
    l3_cfg.force_deact_win = bound;
    `uvm_info(get_type_name(), $sformatf("DeactivateReq bound after DEACTIVATE_FORCE: %0t",
                                         bound), UVM_LOW)
    fork
      watch_apb();
      watch_core();
    join_none
  endtask

  protected task watch_apb();
    uvm_reg_addr_t con0 = rm.aou_con0.get_address();
    int unsigned lsb = rm.aou_con0.deactivate_force.get_lsb_pos();
    forever begin
      @(apb_vif.mon_cb);
      if (apb_vif.mon_cb.psel !== 1'b1 || apb_vif.mon_cb.penable !== 1'b0 ||
          apb_vif.mon_cb.pwrite !== 1'b1 || uvm_reg_addr_t'(apb_vif.mon_cb.paddr) != con0 ||
          apb_vif.mon_cb.pwdata[lsb] !== 1'b1)
        continue;
      if (owed || dut_deact_sent || !(status.enabled || (was_enabled && !status.disabled)) ||
          lsm_vif == null || lsm_vif.mon_cb.fdi_link_up !== 1'b1) begin
        `uvm_info(get_type_name(), "DEACTIVATE_FORCE written with no DeactivateReq owed",
                  UVM_MEDIUM)
        continue;
      end
      owed = 1'b1;
      t_write = $realtime;
      t_held = 0;
      l3_cfg.force_deact_t = t_write;
      l3_cfg.force_deact_win = bound;
      `uvm_info(get_type_name(), "DEACTIVATE_FORCE written: DeactivateReq owed", UVM_MEDIUM)
    end
  endtask

  // DUT state, and the deadline while a DeactivateReq is owed.
  protected task watch_core();
    forever begin
      @(rst_vif.mon_cb);
      if (status.enabled) was_enabled = 1'b1;
      if (status.disabled) begin
        was_enabled = 1'b0;
        dut_deact_sent = 1'b0;
      end
      if (!owed) continue;
      if (rst_vif.mon_cb.rst_n !== 1'b1 || rst_vif.mon_cb.core_rst_n !== 1'b1 ||
          lsm_vif.mon_cb.fdi_link_up !== 1'b1) begin
        // A reset or the link going down takes the expectation with it.
        `uvm_info(get_type_name(), "reset or link down while a forced DeactivateReq was owed",
                  UVM_LOW)
        owed = 1'b0;
        continue;
      end
      if (fdi_held()) begin
        t_held += tc;
        l3_cfg.force_deact_win = bound + t_held;
      end
      if ($realtime - t_write - t_held > bound) begin
        owed = 1'b0;
        n_late++;
        aou_rule_log::check("T1-L52", get_type_name());
        aou_rule_log::fire("T1-L52", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            {"T1-L52: no DUT DeactivateReq within %0t of the DEACTIVATE_FORCE write at %0t, ",
             "FDI backpressure excluded (bound from the RTL path, with margin)"}, bound, t_write))
      end
    end
  endtask

  // The Adapter holds the DUT's TX on the active PHY: pl_trdy low, or a stall
  // the DUT has acknowledged (lp_stallack high).
  protected function bit fdi_held();
    int unsigned p = (cfg == null) ? 0 : cfg.lsm_cfg.active_phy;
    return p < AOU_T1_N_PHY && mb_vif[p] != null &&
           (mb_vif[p].mon_cb.pl_trdy !== 1'b1 || mb_vif[p].mon_cb.lp_stallack === 1'b1);
  endfunction

  function void write(aou_msg m);
    aou_msg_act a;
    realtime lat;
    if (!$cast(a, m)) return;
    if (a.op == AOU_ACT_REQ) dut_deact_sent = 1'b0;
    if (a.op != AOU_DEACT_REQ) return;
    dut_deact_sent = 1'b1;
    if (!owed) return;
    owed = 1'b0;
    lat = $realtime - t_write - t_held;
    n_forced++;
    if (lat > max_latency) max_latency = lat;
    aou_rule_log::check("T1-L52", get_type_name());
    `uvm_info(get_type_name(), $sformatf(
        {"forced DeactivateReq (PropertyReq mark %0b) %0t after the DEACTIVATE_FORCE write, ",
         "FDI backpressure excluded"}, a.forced_deact_mark(), lat), UVM_LOW)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (n_forced != 0 || n_late != 0)
      `uvm_info(get_type_name(), $sformatf(
          "%0d forced DeactivateReqs, longest %0t (bound %0t), %0d late", n_forced,
          max_latency, bound, n_late), UVM_LOW)
  endfunction
endclass
