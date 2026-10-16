// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Expectation registry (docs/ARCHITECTURE.md, "Expectations"). A test or
// virtual sequence declares the errors its scenario is supposed to cause with
// add(id, min, max); id is a rule ID ("AOU-R16"), an interrupt
// ("INT_REQ_LINKRESET") or a scoreboard check ("AXI-S01"). The catcher
// demotes a UVM_ERROR whose message starts with "<id>:" (or whose report ID
// is id) to UVM_INFO and counts it. At check_phase every count must lie in
// [min, max]; other errors fail the test as usual.
class aou_t1_expect_catcher extends uvm_report_catcher;
  `uvm_object_utils(aou_t1_expect_catcher)

  int unsigned min_cnt[string];
  int unsigned max_cnt[string];
  int unsigned hits[string];

  function new(string name = "aou_t1_expect_catcher");
    super.new(name);
  endfunction

  function string match(string msg, string rid);
    foreach (min_cnt[id]) begin
      int unsigned n = id.len();
      if (rid == id) return id;
      if (msg.len() > n && msg.substr(0, n - 1) == id && msg[n] == ":") return id;
    end
    return "";
  endfunction

  function action_e catch();
    string id;
    if (get_severity() != UVM_ERROR) return THROW;
    id = match(get_message(), get_id());
    if (id == "") return THROW;
    hits[id] = hits.exists(id) ? hits[id] + 1 : 1;
    set_severity(UVM_INFO);
    set_verbosity(UVM_LOW);
    set_message({"[expected] ", get_message()});
    return THROW;
  endfunction
endclass
