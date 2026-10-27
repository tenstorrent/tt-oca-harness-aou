// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// DFT scan mode (plan 11.19). TIEL_DFT_MODESCAN=1 switches the core reset mux to
// its scan input, which the integration guide (3.13.1) says de-asserts the
// software reset so that scan shifting is not disturbed: the core comes out of
// any software reset and AOU_SW_RESET has no effect while scan mode lasts.
// Sequence: traffic; the link goes to Reset as for a software reset; a marker
// value goes into a configuration register; scan mode on; the marker must
// survive (T1-DFT02, register read-backs at the end of each step), also after an
// AOU_SW_RESET write; scan mode off, and the pending software reset takes effect
// (the marker reads its reset value); a hard reset and traffic again. The core
// reset itself is judged by aou_t1_sw_reset_chk (T1-DFT01) whenever scan mode is on.
class aou_dft_scan_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_dft_scan_vseq)

  localparam int unsigned SCAN_CYCLES = 200;
  localparam int unsigned APB_TIMEOUT = 20000;

  function new(string name = "aou_dft_scan_vseq");
    super.new(name);
  endfunction

  task body();
    uvm_reg_field marker = p_sequencer.regs.lp_linkreset.msgcredit_time_out_value;
    bit rebringup = cfg.lsm_cfg.rebringup_after_down;
    link_up();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
    // No flit may be in flight when the core resets (MAS 7.3.6 order).
    cfg.lsm_cfg.rebringup_after_down = 1'b0;
    link_event(LSM_EV_LINK_RESET);
    cfg.lsm_cfg.rebringup_after_down = rebringup;
    wr(marker, 6);
    check_field(marker, 6, "T1-DFT02", "marker before scan mode");

    `uvm_info(get_type_name(), "TIEL_DFT_MODESCAN=1", UVM_LOW)
    scan(1'b1);
    wait_cycles(SCAN_CYCLES);
    apb_check(marker, 6, "marker in scan mode");
    `uvm_info(get_type_name(), "AOU_SW_RESET in scan mode", UVM_LOW)
    apb_write_sw_reset();
    wait_cycles(SCAN_CYCLES);
    apb_check(marker, 6, "AOU_SW_RESET in scan mode must not reset the SFRs");
    `uvm_info(get_type_name(), "TIEL_DFT_MODESCAN=0", UVM_LOW)
    scan(1'b0);
    wait_cycles(SCAN_CYCLES);
    // The AOU_SW_RESET bit lives in the SFRs, which scan mode kept out of reset, so the
    // write above is still pending and resets the core once the mux selects it again.
    check_field(marker, marker.get_reset(), "T1-DFT02", "software reset pending at scan exit");
    check_field(p_sequencer.regs.aou_con0.aou_sw_reset, 0, "T1-DFT02",
                "software reset pending at scan exit");
    aou_rule_log::check("T1-DFT02", get_type_name());
    `uvm_info(get_type_name(), "hard reset", UVM_LOW)
    hard_reset(AOU_T1_RST_BOTH);
    traffic(AOU_T1_BOTH_DIRS, num_txns / 2 + 1, null);
    drain();
  endtask

  task scan(bit on);
    @(env.rst.vif.drv_cb);
    env.rst.vif.drv_cb.dft_modescan <= on;
    @(env.rst.vif.drv_cb);
  endtask

  // APB accesses during scan mode with a time-out, so a bridge that never
  // answers is an error rather than a hang.
  local task apb_check(uvm_reg_field f, uvm_reg_data_t exp, string why);
    bit done;
    fork
      begin
        fork
          begin
            check_field(f, exp, "T1-DFT02", why);
            done = 1'b1;
          end
          wait_cycles(APB_TIMEOUT);
        join_any
        disable fork;
      end
    join
    aou_rule_log::check("T1-DFT02", get_type_name());
    if (!done) `uvm_error(get_type_name(), {"T1-DFT02: APB read timed out in scan mode: ", why})
  endtask

  local task apb_write_sw_reset();
    bit done;
    fork
      begin
        fork
          begin
            wr(p_sequencer.regs.aou_con0.aou_sw_reset, 1);
            done = 1'b1;
          end
          wait_cycles(APB_TIMEOUT);
        join_any
        disable fork;
      end
    join
    if (!done)
      `uvm_error(get_type_name(), "T1-DFT02: APB write of AOU_SW_RESET timed out in scan mode")
  endtask
endclass
