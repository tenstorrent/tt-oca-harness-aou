// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX low-power configuration is static (T1-LP03; MAS software-operation 7.1
// "Low Power mode"): AOU_CON0.TX_LP_MODE and TX_LP_MODE_THRESHOLD may change
// only while the DUT reports ACTIVATE_STATE_DISABLED, before the first
// activation or between activation sessions. A change on a link that is
// activating, ENABLED or deactivating can land in the middle of a TX flit,
// which the DUT need not preserve; such a write is illegal stimulus, not a DUT
// failure. The checker takes every APB write the monitor publishes, whatever
// sequence issued it, keeps the value the two fields were last written with,
// and reports a write that changes either while the DUT is not DISABLED. A
// write that leaves both fields alone (another AOU_CON0 field, or the same
// value again) is not a change. A core reset returns the fields to their reset
// values; reset_flush() resets the record the same way.
class aou_t1_lp_cfg_chk extends uvm_component;
  `uvm_component_utils(aou_t1_lp_cfg_chk)

  uvm_analysis_imp #(aou_apb_item, aou_t1_lp_cfg_chk) apb_imp;

  aou_core      rm;
  aou_t1_status status;
  int unsigned  n_changes;   // legal changes seen (DISABLED)
  int unsigned  reports;

  protected bit            have_last;
  protected uvm_reg_data_t last_mode;
  protected uvm_reg_data_t last_thr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_imp = new("apb_imp", this);
  endfunction

  function void reset_flush();
    have_last = 1'b0;
  endfunction

  protected function uvm_reg_data_t field_of(uvm_reg_field f, uvm_reg_data_t v);
    return (v >> f.get_lsb_pos()) & ((uvm_reg_data_t'(1) << f.get_n_bits()) - 1);
  endfunction

  function void write(aou_apb_item it);
    uvm_reg_data_t mode, thr;
    if (rm == null || status == null || it.dir != AOU_APB_WRITE) return;
    if (uvm_reg_addr_t'(it.addr) != rm.aou_con0.get_address()) return;
    mode = field_of(rm.aou_con0.tx_lp_mode, uvm_reg_data_t'(it.data));
    thr  = field_of(rm.aou_con0.tx_lp_mode_threshold, uvm_reg_data_t'(it.data));
    if (!have_last) begin
      // Reset values until the first write after a reset.
      last_mode = rm.aou_con0.tx_lp_mode.get_reset();
      last_thr  = rm.aou_con0.tx_lp_mode_threshold.get_reset();
      have_last = 1'b1;
    end
    if (mode != last_mode || thr != last_thr) begin
      aou_rule_log::check("T1-LP03", get_type_name());
      if (status.disabled) begin
        n_changes++;
      end else begin
        string st = status.enabled ? "ENABLED" : "activating or deactivating";
        reports++;
        aou_rule_log::fire("T1-LP03", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            {"T1-LP03: AOU_CON0.TX_LP_MODE/THRESHOLD written %0d/%0d (was %0d/%0d) at %0t ",
             "while the DUT is not DISABLED (%s); TX low-power mode is static configuration ",
             "(MAS software-operation 7.1)"}, mode, thr, last_mode, last_thr, it.t_end, st))
      end
    end
    last_mode = mode;
    last_thr  = thr;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf(
              "%0d LP-mode configuration changes while DISABLED, %0d reports", n_changes, reports),
              UVM_LOW)
  endfunction
endclass
