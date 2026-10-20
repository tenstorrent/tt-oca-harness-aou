// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Test intent for Arm's Axi4PC (tb/aou_axi4pc_msg.svh routes its failures here).
// While the bench itself presents a deliberate AXI violation on a port (an error
// injection the DUT must handle), the Axi4PC rules that violation trips on that
// port's checker are expected: allow() opens them, revoke() closes them, and a
// failure of an open rule is logged (first one per window at UVM_LOW) instead of
// reported as an error. Every other failure is a UVM_ERROR.
// Axi4PC fails a rule on every cycle the condition holds, so after the
// +aou_axi4pc_max=<N> (default 10; 0: no limit) unexpected failures the run ends with
// a UVM_FATAL; check_run.py judges it by the errors before it. The fatal waits
// +aou_axi4pc_stop_cycles=<n> clocks (default 10; aou_t1_axi4pc_ctl), so the waves
// hold what followed the failure.
package aou_axi4pc_pkg;
  import uvm_pkg::*;

  class aou_axi4pc_intent;
    // "<checker instance>|<rule>" -> why the bench breaks it, while open.
    local static string why[string];
    local static bit    seen[string];
    static int unsigned n_errors;
    local static bit    stopped;
    // Set by a component that ends the run on stop_ev; without one the stop is
    // immediate.
    static bit          stop_waiter;
    static uvm_event    stop_ev = new("aou_axi4pc_stop");
    static int unsigned n_expected;

    static function void allow(string inst, string rule, string reason);
      string k = {inst, "|", rule};
      if (!why.exists(k)) seen[k] = 1'b0;
      why[k] = reason;
    endfunction

    static function void revoke(string inst, string rule);
      why.delete({inst, "|", rule});
    endfunction

    // path: the failing assertion (%m); msg: Axi4PC's "<RULE>: <text>".
    static function void report_error(string path, string msg);
      string inst = path;
      string rule = msg;
      string k;
      for (int i = path.len() - 1; i > 0; i--)
        if (path[i] == ".") begin
          inst = path.substr(0, i - 1);
          break;
        end
      for (int i = 0; i < msg.len(); i++)
        if (msg[i] == ":") begin
          rule = msg.substr(0, i - 1);
          break;
        end
      k = {inst, "|", rule};
      if (!why.exists(k)) begin
        int unsigned max = 10;
        // After a UVM_FATAL (this stop or any other) the end-of-simulation checks
        // only see transactions the abort cut short.
        if (stopped) return;
        if (uvm_is_match("*_ALL_DONE_EOS", rule) &&
            uvm_report_server::get_server().get_severity_count(UVM_FATAL) != 0)
          return;
        void'($value$plusargs("aou_axi4pc_max=%d", max));
        uvm_report_error("AXI4PC", $sformatf("%s: %s", path, msg), UVM_NONE);
        if (max != 0 && ++n_errors == max) begin
          if (stop_waiter) stop_ev.trigger();
          else stop();
        end
        return;
      end
      n_expected++;
      uvm_report_info("AXI4PC", $sformatf("%s: %s (expected: %s)", path, rule, why[k]),
                      seen[k] ? UVM_HIGH : UVM_LOW);
      seen[k] = 1'b1;
    endfunction

    static function void stop();
      stopped = 1'b1;
      uvm_report_fatal("AXI4PC", $sformatf("%0d Axi4PC violations, stopping", n_errors),
                       UVM_NONE);
    endfunction
  endclass
endpackage
