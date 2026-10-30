// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Demotes the scoreboard's AXI-S errors and the monitor's AXI-R05 errors to
// info and counts them, for tests that inject those faults on purpose.
class aou_axi_selftest_catcher extends uvm_report_catcher;
  `uvm_object_utils(aou_axi_selftest_catcher)

  int unsigned n_caught;
  int unsigned by_rule[string];   // scoreboard errors per rule (AXI-S01..)
  int unsigned n_proto;
  int unsigned n_axi_r03;
  bit r03_control = 1'b0;

  function new(string name = "aou_axi_selftest_catcher");
    super.new(name);
  endfunction

  function action_e catch();
    string msg = get_message();
    if (get_severity() == UVM_ERROR && get_id() == "aou_scoreboard" && msg.len() > 6 &&
        msg.substr(0, 4) == "AXI-S") begin
      n_caught++;
      if (by_rule.exists(msg.substr(0, 6))) by_rule[msg.substr(0, 6)]++;
      else by_rule[msg.substr(0, 6)] = 1;
      if (!r03_control) set_severity(UVM_INFO);
    end
    if (!r03_control && get_severity() == UVM_ERROR && get_id() == "aou_axi_monitor" &&
        msg.len() > 7 &&
        msg.substr(0, 7) == "AXI-R05:") begin
      n_proto++;
      set_severity(UVM_INFO);
    end
    // Count the real production error without changing its severity.
    if (get_severity() == UVM_ERROR && get_id() == "aou_axi_monitor" && msg.len() > 7 &&
        msg.substr(0, 7) == "AXI-R03:") n_axi_r03++;
    return THROW;
  endfunction
endclass
