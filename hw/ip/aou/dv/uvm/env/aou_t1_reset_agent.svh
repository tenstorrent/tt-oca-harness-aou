// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Drives mid-test resets of I_RESETN and/or I_PRESETN through aou_rst_if
// (config_db key "rst"; the top adds its own power-on reset). on_reset fires
// when a reset this agent drove takes effect, so the env can flush.
//
// Reset rule (integration guide 3.1.1): I_RESETN or I_PRESETN is asserted only
// with the APB master idle (PSEL low, nothing waiting on PREADY) and the async
// APB bridge's request/done handshake drained in both clock domains, both
// clocks running (they are free-running in every top). do_reset() does this
// through quiesce_apb() unless a test passes quiesce = 0 AND states why in its
// header; the checker in run_phase reports any reset asserted otherwise, from
// this agent or not. Power-on holds both resets with both clocks running (the
// top), and APB/AXI drivers wait for their resets to release.
class aou_t1_reset_agent extends uvm_component;
  `uvm_component_utils(aou_t1_reset_agent)

  virtual aou_rst_if vif;
  uvm_event          on_reset;
  int unsigned       n_resets;
  aou_t1_rst_e       last_which = AOU_T1_RST_BOTH;   // the reset on_reset reports
  aou_apb_cfg        apb_cfg;                        // set by the env
  bit                unquiesced_ok;                  // a deliberate violation is in progress
  int unsigned       n_violations;

  // PCLK cycles of continuous quiet the bridge must show, and the longest wait.
  localparam int unsigned QUIET_PCLKS = 4;
  localparam int unsigned DRAIN_TIMEOUT_PCLKS = 2000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    on_reset = new("on_reset");
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual aou_rst_if)::get(this, "", "rst", vif))
      `uvm_fatal(get_type_name(), "no aou_rst_if under config_db key rst")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.resetn <= 1'b1;
    vif.pdrv_cb.presetn <= 1'b1;
    check_rule();
  endtask

  // Flags a reset asserted while the APB master or the bridge was busy. The
  // state is the one sampled on the last CLK edge before the assertion (the
  // bridge's own flops reset asynchronously). Power-on is not checked.
  task check_rule();
    bit quiet_q = 1'b1;
    bit armed = 1'b0;
    bit reported = 1'b0;
    fork
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.rst_n === 1'b1 && vif.mon_cb.prst_n === 1'b1) begin
          armed = 1'b1;
          reported = 1'b0;
          quiet_q = vif.mon_cb.apb_quiet;
        end
      end
      forever begin
        @(negedge vif.rst_n or negedge vif.prst_n);
        if (armed && !quiet_q && !unquiesced_ok && !reported) begin
          reported = 1'b1;
          n_violations++;
          `uvm_error(get_type_name(), $sformatf(
              "reset rule (integration guide 3.1.1): %s asserted with the APB side busy",
              which_low()))
        end
      end
    join_none
  endtask

  function string which_low();
    if (vif.rst_n === 1'b0 && vif.prst_n === 1'b0) return "I_RESETN and I_PRESETN";
    return (vif.rst_n === 1'b0) ? "I_RESETN" : "I_PRESETN";
  endfunction

  // Stops new APB transfers, lets the one in flight finish, then waits until PSEL
  // is low and the bridge handshake has been idle in both domains for
  // QUIET_PCLKS PCLK cycles (and as many CLK cycles). The master-visible
  // completion of a write is not enough: the done/req handshake still has to
  // return to idle. apb_cfg.hold stays set until release_apb().
  task quiesce_apb();
    int unsigned n = 0;
    int unsigned waited = 0;
    if (apb_cfg != null) apb_cfg.hold = 1'b1;
    while (n < QUIET_PCLKS) begin
      @(vif.pmon_cb);
      if (vif.pmon_cb.apb_quiet) n++;
      else n = 0;
      if (++waited > DRAIN_TIMEOUT_PCLKS) begin
        `uvm_error(get_type_name(), "APB master/bridge did not go idle before the reset")
        break;
      end
    end
    repeat (QUIET_PCLKS) @(vif.mon_cb);
  endtask

  task release_apb();
    if (apb_cfg != null) apb_cfg.hold = 1'b0;
  endtask

  // Quiesces the APB side (quiesce_apb), holds the selected reset(s) low for
  // `cycles` core clocks (APB reset at least 2 PCLK), then releases them, waits
  // until both are high and lets the APB driver go on. quiesce = 0 skips the
  // quiesce on purpose; the calling test's header must say so and must not claim
  // compliance with the reset rule.
  task do_reset(aou_t1_rst_e which, int unsigned cycles = 20, bit quiesce = 1'b1);
    bit core = which inside {AOU_T1_RST_CORE, AOU_T1_RST_BOTH};
    bit apb = which inside {AOU_T1_RST_APB, AOU_T1_RST_BOTH};
    `uvm_info(get_type_name(), $sformatf("asserting %s reset for %0d cycles", which.name(),
                                         cycles), UVM_LOW)
    n_resets++;
    last_which = which;
    if (quiesce) quiesce_apb();
    else unquiesced_ok = 1'b1;
    fork
      if (core) begin
        @(vif.drv_cb);
        vif.drv_cb.resetn <= 1'b0;
      end
      if (apb) begin
        @(vif.pdrv_cb);
        vif.pdrv_cb.presetn <= 1'b0;
      end
    join
    @(vif.mon_cb);
    on_reset.trigger();
    repeat (cycles) @(vif.mon_cb);
    if (apb) repeat (2) @(vif.pdrv_cb);
    fork
      if (core) begin
        @(vif.drv_cb);
        vif.drv_cb.resetn <= 1'b1;
      end
      if (apb) begin
        @(vif.pdrv_cb);
        vif.pdrv_cb.presetn <= 1'b1;
      end
    join
    wait_released();
    unquiesced_ok = 1'b0;
    release_apb();
  endtask

  task wait_released();
    do @(vif.mon_cb); while (vif.mon_cb.rst_n !== 1'b1 || vif.mon_cb.prst_n !== 1'b1);
  endtask
endclass
