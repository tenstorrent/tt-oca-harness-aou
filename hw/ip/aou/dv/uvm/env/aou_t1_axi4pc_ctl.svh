// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link events and Arm's Axi4PC (README "Optional: Arm AXI4 protocol assertions").
// Losing the FDI link while AoU is not DISABLED (pl_state_sts leaves Active or
// Retrain for Reset, LinkError, LinkReset or Disabled, outside I_RESETN) strands
// every transaction then in flight, and any the S ports accept before software resets
// the core: they never complete, so the DUT's AXI ports break AXI4 until their reset
// (MAS 7.3.6: the link loss forces DISABLED, and the reset that follows loses them). On that event every
// port's checker is held in reset (tb/aou_axi4pc_gate.sv) until its port's next
// reset and then until the bench side of the port is idle; with no port reset it
// stays off to the end of the test. Each hold and release is logged.
//
// Test intent: an unmatched B or R the local subordinate presents on purpose
// (aou_axi_sub_driver::inject_orphan, the ID-mismatch error injection) breaks the
// rules a response with no request trips on that M port's checker; they are
// expected (aou_axi4pc_pkg) from the injection until four cycles after the orphan
// is taken or withdrawn. An orphan the DUT takes leaves that checker's transaction
// tracking wrong (tb/aou_axi4pc_gate.sv), so the checker is then reset once (resync),
// in the port's next quiet cycle and only for that cycle; the R rules include the
// read-CAM underflow seen before that reset.
// At the end of the test, a resync still waiting for a quiet cycle is a UVM_ERROR (the
// port never went idle: a transaction did not complete, and the checker ran on with
// the stale entry), and so is a checker still held with no link event behind it (the
// bench side of the port never went idle after a port reset, so Axi4PC was off). Holds
// a link event caused are logged as before.
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
  protected int unsigned    orph_taken[8];

  // Rules an unmatched response trips: [0] B, [1] R (no read, so no defined lanes;
  // its RLAST pops the empty read CAM). "" pads.
  protected static const string ORPH_RULES[2][3] = '{
      '{"AXI4_ERRS_BRESP_AW", "AXI4_ERRS_BRESP_WLAST", ""},
      '{"AXI4_ERRS_RID", "AXI4_ERRS_RDATA_X", "AXI4_AUX_RCAM_UNDERFLOW"}};

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
    if (!lost || vif == null || vif.present !== 1'b1) return;
    n_events++;
    pending = 1'b1;
    `uvm_info(get_type_name(), $sformatf({"Axi4PC held on every port: FDI link lost (%s) with ",
              "AoU not DISABLED; transactions in flight cannot complete until the ports' ",
              "reset (MAS 7.3.6)"}, o.sts.name()), UVM_LOW)
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
      begin
        bit [7:0] resync = '0;
        foreach (m_drv[r]) if (m_drv[r] != null && r < 8) resync[r] = orphan_intent(r);
        vif.cb.m_resync <= resync;
      end
    end
  endtask

  // Opens and closes the orphan rules of m_axi<r>; returns 1 when the DUT has taken
  // an orphan since the last call (the checker needs a resync).
  protected function bit orphan_intent(int unsigned r);
    string inst = $sformatf("%s[%0d].u_m_axi4pc", vif.chk_scope, r);
    bit taken = m_drv[r].n_orphan_taken != orph_taken[r];
    orph_taken[r] = m_drv[r].n_orphan_taken;
    if (taken)
      `uvm_info(get_type_name(), $sformatf({"m_axi%0d: the DUT took an orphan response; ",
                "resetting its Axi4PC once to drop the unmatched entry"}, r), UVM_LOW)
    for (int c = 0; c < 2; c++) begin
      if (m_drv[r].orphans_pending_on(c[0]) != 0) begin
        if (orph_grace[r][c] == 0)
          for (int k = 0; k < 3; k++) if (ORPH_RULES[c][k] != "")
            aou_axi4pc_intent::allow(inst, ORPH_RULES[c][k], $sformatf(
                "the local subordinate presents an unmatched %s on m_axi%0d (error injection)",
                c[0] ? "R" : "B", r));
        orph_grace[r][c] = 4;
      end else if (orph_grace[r][c] != 0 && --orph_grace[r][c] == 0) begin
        for (int k = 0; k < 3; k++)
          if (ORPH_RULES[c][k] != "") aou_axi4pc_intent::revoke(inst, ORPH_RULES[c][k]);
      end
    end
    return taken;
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
    if (vif == null || vif.present !== 1'b1) return;
    for (int unsigned r = 0; r < 8; r++) begin
      if (vif.s_sync_wait[r] === 1'b1)
        `uvm_error(get_type_name(), $sformatf({"s_axi%0d: Axi4PC resync still waiting for a ",
                   "quiet port at the end of the test (a transaction never completed)"}, r))
      if (vif.m_sync_wait[r] === 1'b1)
        `uvm_error(get_type_name(), $sformatf({"m_axi%0d: Axi4PC resync still waiting for a ",
                   "quiet port at the end of the test (a transaction never completed)"}, r))
      report_off("s_axi", r, off_s[r], since_s[r]);
      report_off("m_axi", r, off_m[r], since_m[r]);
    end
    if (n_events != 0)
      `uvm_info(get_type_name(), $sformatf("%0d link event(s) held Axi4PC", n_events), UVM_LOW)
  endfunction

  protected function void report_off(string port, int unsigned r, bit off, time since);
    string msg = $sformatf("%s%0d: Axi4PC off from %0t to the end of the test", port, r, since);
    if (!off) return;
    if (n_events != 0) `uvm_info(get_type_name(), msg, UVM_LOW)
    else `uvm_error(get_type_name(), {msg, " with no link event (a transaction never completed)"})
  endfunction
endclass
