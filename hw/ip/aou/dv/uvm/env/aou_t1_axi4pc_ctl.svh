// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link events and Arm's Axi4PC (README "Optional: Arm AXI4 protocol assertions").
// Losing the FDI link while AoU is not DISABLED (pl_state_sts leaves Active or
// Retrain for Reset, LinkError, LinkReset or Disabled, outside I_RESETN) strands
// every transaction then in flight, and any the S ports accept before software resets
// the core: they never complete, so the DUT's AXI ports break AXI4 until their reset
// (BUGS/015 interim, BUGS/021). On that event every port's checker is held in reset
// (tb/aou_axi4pc_gate.sv) until its port's next reset and then until the bench side of
// the port is idle; with no port reset it stays off to the end of the test. With the
// BUGS/021 guard the ports stay protocol-clean through the event, so nothing is held.
// Each hold and release is logged.
//
// Test intent: an unmatched B or R the local subordinate presents on purpose
// (aou_axi_sub_driver::inject_orphan, the ID-mismatch error injection) breaks the
// rules a response with no request trips on that M port's checker; they are
// expected (aou_axi4pc_pkg) from the injection until two cycles after the orphan
// is taken or withdrawn.
class aou_t1_axi4pc_ctl extends uvm_component;
  `uvm_component_utils(aou_t1_axi4pc_ctl)

  uvm_analysis_imp #(aou_lsm_obs, aou_t1_axi4pc_ctl) lsm_imp;
  virtual aou_axi4pc_ctl_if vif;
  aou_axi_sub_driver m_drv[];
  int unsigned n_events;

  protected bit             pending;
  protected bit             have_prev;
  protected aou_lsm_state_e prev_sts;
  protected bit             prev_rst_n;
  protected bit             off_s[8];
  protected bit             off_m[8];
  protected time            since_s[8];
  protected time            since_m[8];
  protected int unsigned    orph_grace[8][2];

  // Rules an unmatched response trips: [0] B, [1] R (no read, so no defined lanes).
  protected static const string ORPH_RULES[2][2] = '{
      '{"AXI4_ERRS_BRESP_AW", "AXI4_ERRS_BRESP_WLAST"},
      '{"AXI4_ERRS_RID", "AXI4_ERRS_RDATA_X"}};

  function new(string name, uvm_component parent);
    super.new(name, parent);
    lsm_imp = new("lsm_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db #(virtual aou_axi4pc_ctl_if)::get(this, "", "axi4pc_ctl", vif));
  endfunction

  function void write(aou_lsm_obs o);
    bit lost = have_prev && o.rst_n && prev_rst_n &&
               prev_sts inside {LSM_ACTIVE, LSM_RETRAIN} &&
               o.sts inside {LSM_RESET, LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED} &&
               !o.act_st_disabled;
    have_prev = 1'b1;
    prev_sts = o.sts;
    prev_rst_n = o.rst_n;
    if (!lost || vif == null || vif.present !== 1'b1 || vif.guard === 1'b1) return;
    n_events++;
    pending = 1'b1;
    `uvm_info(get_type_name(), $sformatf({"Axi4PC held on every port: FDI link lost (%s) with ",
              "AoU not DISABLED; transactions in flight cannot complete until the ports' ",
              "reset (BUGS/015, BUGS/021)"}, o.sts.name()), UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    if (vif == null) return;
    aou_axi4pc_intent::stop_waiter = 1'b1;
    fork
      begin
        int unsigned n = 10;
        void'($value$plusargs("aou_axi4pc_stop_cycles=%d", n));
        aou_axi4pc_intent::stop_ev.wait_on();
        repeat (n) @(vif.cb);
        aou_axi4pc_intent::stop();
      end
    join_none
    forever begin
      @(vif.cb);
      vif.cb.off_set <= pending;
      pending = 1'b0;
      for (int unsigned r = 0; r < 8; r++) begin
        track("s_axi", r, vif.cb.s_off[r] === 1'b1, off_s[r], since_s[r]);
        track("m_axi", r, vif.cb.m_off[r] === 1'b1, off_m[r], since_m[r]);
      end
      foreach (m_drv[r]) if (m_drv[r] != null && r < 8) orphan_intent(r);
    end
  endtask

  protected function void orphan_intent(int unsigned r);
    string inst = $sformatf("%s[%0d].u_m_axi4pc", vif.chk_scope, r);
    for (int c = 0; c < 2; c++) begin
      if (m_drv[r].orphans_pending_on(c[0]) != 0) begin
        if (orph_grace[r][c] == 0)
          for (int k = 0; k < 2; k++)
            aou_axi4pc_intent::allow(inst, ORPH_RULES[c][k], $sformatf(
                "the local subordinate presents an unmatched %s on m_axi%0d (error injection)",
                c[0] ? "R" : "B", r));
        orph_grace[r][c] = 3;
      end else if (orph_grace[r][c] != 0 && --orph_grace[r][c] == 0) begin
        for (int k = 0; k < 2; k++) aou_axi4pc_intent::revoke(inst, ORPH_RULES[c][k]);
      end
    end
  endfunction

  protected function void track(string port, int unsigned r, bit now, ref bit was, ref time since);
    if (now && !was) since = $time;
    if (!now && was)
      `uvm_info(get_type_name(), $sformatf("%s%0d: Axi4PC back on, held since %0t", port, r,
                                           since), UVM_LOW)
    was = now;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (n_events == 0) return;
    for (int unsigned r = 0; r < 8; r++) begin
      if (off_s[r])
        `uvm_info(get_type_name(), $sformatf("s_axi%0d: Axi4PC off from %0t to the end of the test",
                                             r, since_s[r]), UVM_LOW)
      if (off_m[r])
        `uvm_info(get_type_name(), $sformatf("m_axi%0d: Axi4PC off from %0t to the end of the test",
                                             r, since_m[r]), UVM_LOW)
    end
    `uvm_info(get_type_name(), $sformatf("%0d link event(s) held Axi4PC", n_events), UVM_LOW)
  endfunction
endclass
