// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Interrupt and activation-status watcher (aou_irq_if, config_db key "irq").
// Every rising edge of an error interrupt is a UVM_ERROR "<INT name>: ...",
// which the expectation registry demotes when a test declared it.
// INT_ACTIVATE_START / INT_DEACTIVATE_START belong to normal activation and
// are only counted.
class aou_t1_status extends uvm_component;
  `uvm_component_utils(aou_t1_status)

  localparam int N_INT = 6;

  virtual aou_irq_if vif;
  bit                checks_en = 1'b1;
  int unsigned       rises[string];
  bit                enabled;     // O_AOU_ACTIVATE_ST_ENABLED, sampled
  bit                disabled;    // O_AOU_ACTIVATE_ST_DISABLED, sampled
  uvm_event          state_ev;
  bit                act_ok;      // result of wait_act_state()
  uvm_event          act_start_ev;    // INT_ACTIVATE_START rose
  uvm_event          deact_start_ev;  // INT_DEACTIVATE_START rose

  function new(string name, uvm_component parent);
    super.new(name, parent);
    state_ev = new("state_ev");
    act_start_ev = new("act_start_ev");
    deact_start_ev = new("deact_start_ev");
  endfunction

  static function string int_name(int unsigned i);
    case (i)
      0: return "INT_REQ_LINKRESET";
      1: return "INT_SI0_ID_MISMATCH";
      2: return "INT_MI0_ID_MISMATCH";
      3: return "INT_EARLY_RESP_ERR";
      4: return "INT_ACTIVATE_START";
      default: return "INT_DEACTIVATE_START";
    endcase
  endfunction

  static function bit is_error(int unsigned i);
    return i < 4;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual aou_irq_if)::get(this, "", "irq", vif))
      `uvm_fatal(get_type_name(), "no aou_irq_if under config_db key irq")
    for (int unsigned i = 0; i < N_INT; i++) rises[int_name(i)] = 0;
  endfunction

  function bit [N_INT-1:0] sample();
    return {vif.mon_cb.int_deactivate_start, vif.mon_cb.int_activate_start,
            vif.mon_cb.int_early_resp_err, vif.mon_cb.int_mi0_id_mismatch,
            vif.mon_cb.int_si0_id_mismatch, vif.mon_cb.int_req_linkreset};
  endfunction

  task run_phase(uvm_phase phase);
    bit [N_INT-1:0] prev = '0;
    forever begin
      bit [N_INT-1:0] cur;
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) begin
        prev = '0;
        continue;
      end
      if (vif.mon_cb.act_st_enabled !== enabled || vif.mon_cb.act_st_disabled !== disabled) begin
        enabled = vif.mon_cb.act_st_enabled === 1'b1;
        disabled = vif.mon_cb.act_st_disabled === 1'b1;
        state_ev.trigger();
      end
      cur = sample();
      for (int unsigned i = 0; i < N_INT; i++) begin
        if (cur[i] && !prev[i]) begin
          rises[int_name(i)]++;
          if (i == 4) act_start_ev.trigger();
          if (i == 5) deact_start_ev.trigger();
          if (is_error(i) && checks_en)
            `uvm_error(get_type_name(), $sformatf("%s: interrupt asserted", int_name(i)))
          else
            `uvm_info(get_type_name(), $sformatf("%s asserted", int_name(i)), UVM_MEDIUM)
        end
      end
      prev = cur;
    end
  endtask

  // Waits until the DUT reports ENABLED (en=1) or DISABLED (en=0); act_ok = 0
  // on time-out.
  task wait_act_state(bit en, int unsigned timeout);
    int unsigned n = 0;
    act_ok = 1'b1;
    while ((en ? enabled : disabled) != 1'b1) begin
      @(vif.mon_cb);
      if (++n >= timeout) begin
        act_ok = 1'b0;
        return;
      end
    end
  endtask

  function void reset_flush();
    enabled = 1'b0;
    disabled = 1'b0;
  endfunction

  function void report_phase(uvm_phase phase);
    string s = "";
    super.report_phase(phase);
    foreach (rises[k]) s = {s, $sformatf(" %s=%0d", k, rises[k])};
    `uvm_info(get_type_name(), {"interrupt rises:", s}, UVM_LOW)
  endfunction
endclass
