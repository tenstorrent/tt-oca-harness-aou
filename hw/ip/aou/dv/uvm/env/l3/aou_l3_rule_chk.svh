// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One place where every protocol-rule finding is reported and counted. A
// finding is a uvm_error whose message starts with the rule ID, unless a test
// declared the rule expected (error injection), in which case it is logged as
// information and counted. Tests then assert the count.
class aou_l3_rule_chk extends uvm_object;
  `uvm_object_utils(aou_l3_rule_chk)

  // Findings per rule ID, and per "rule@source".
  int unsigned hits[string];
  // Rules a test has declared expected; their findings are not errors.
  bit expected[string];

  function new(string name = "aou_l3_rule_chk");
    super.new(name);
  endfunction

  function void expect_rule(string rule_id);
    expected[rule_id] = 1'b1;
  endfunction

  function void unexpect_rule(string rule_id);
    if (expected.exists(rule_id)) expected.delete(rule_id);
  endfunction

  function void clear_counts();
    hits.delete();
  endfunction

  function int unsigned count(string rule_id, string src = "");
    string key = (src == "") ? rule_id : {rule_id, "@", src};
    return hits.exists(key) ? hits[key] : 0;
  endfunction

  function int unsigned total();
    int unsigned n = 0;
    foreach (hits[k]) begin
      if (!aou_l3_rule_chk::has_at(k)) n += hits[k];
    end
    return n;
  endfunction

  static function bit has_at(string k);
    for (int i = 0; i < k.len(); i++) begin
      if (k[i] == "@") return 1'b1;
    end
    return 1'b0;
  endfunction

  // src is the reporting class (the report ID); msg is the detail.
  function void violation(string rule_id, string src, string msg);
    string key = {rule_id, "@", src};
    hits[rule_id] = hits.exists(rule_id) ? hits[rule_id] + 1 : 1;
    hits[key] = hits.exists(key) ? hits[key] + 1 : 1;
    aou_rule_log::fire(rule_id, src);
    if (expected.exists(rule_id)) begin
      `uvm_info(src, $sformatf("%s: [expected] %s", rule_id, msg), UVM_MEDIUM)
    end else begin
      `uvm_error(src, $sformatf("%s: %s", rule_id, msg))
    end
  endfunction

  function string summary();
    string s = "";
    foreach (hits[k]) begin
      if (!aou_l3_rule_chk::has_at(k)) s = {s, $sformatf(" %s=%0d", k, hits[k])};
    end
    return (s == "") ? " none" : s;
  endfunction
endclass
