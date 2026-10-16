// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The expectation registry; see aou_t1_expect_catcher.
class aou_t1_expect extends uvm_component;
  `uvm_component_utils(aou_t1_expect)

  aou_t1_expect_catcher catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    catcher = aou_t1_expect_catcher::type_id::create("catcher");
    uvm_report_cb::add(null, catcher);
  endfunction

  // Declares id expected between min and max times (max 0: unbounded).
  function void add(string id, int unsigned min = 1, int unsigned max = 0);
    catcher.min_cnt[id] = min;
    catcher.max_cnt[id] = max;
    if (!catcher.hits.exists(id)) catcher.hits[id] = 0;
    `uvm_info(get_type_name(), $sformatf("expecting %s %0d..%0s times", id, min,
                                         max == 0 ? "any" : $sformatf("%0d", max)), UVM_LOW)
  endfunction

  function void remove(string id);
    if (catcher.min_cnt.exists(id)) begin
      catcher.min_cnt.delete(id);
      catcher.max_cnt.delete(id);
    end
  endfunction

  function int unsigned count(string id);
    return catcher.hits.exists(id) ? catcher.hits[id] : 0;
  endfunction

  function bit is_expected(string id);
    return catcher.min_cnt.exists(id);
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (catcher.min_cnt[id]) begin
      int unsigned n = count(id);
      if (n < catcher.min_cnt[id] || (catcher.max_cnt[id] != 0 && n > catcher.max_cnt[id]))
        `uvm_error(get_type_name(), $sformatf("T1-EXP: %s seen %0d times, expected %0d..%0s",
                   id, n, catcher.min_cnt[id],
                   catcher.max_cnt[id] == 0 ? "any" : $sformatf("%0d", catcher.max_cnt[id])))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    foreach (catcher.min_cnt[id])
      `uvm_info(get_type_name(), $sformatf("%s: %0d hit(s)", id, count(id)), UVM_LOW)
  endfunction
endclass
