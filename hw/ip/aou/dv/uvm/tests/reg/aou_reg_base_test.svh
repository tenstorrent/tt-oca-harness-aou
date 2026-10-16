// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of the register tests: APB agent and register model, run after reset.
// Plusargs: +apb_b2b=0|1 (default random), +apb_max_idle=<n>.
class aou_reg_base_test extends uvm_test;
  `uvm_component_utils(aou_reg_base_test)

  aou_reg_env env;
  aou_apb_cfg apb_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    int b2b;
    int unsigned max_idle;
    super.build_phase(phase);
    apb_cfg = aou_apb_cfg::type_id::create("apb_cfg");
    if ($value$plusargs("apb_b2b=%d", b2b)) apb_cfg.back_to_back = (b2b != 0);
    else apb_cfg.back_to_back = ($urandom_range(1) != 0);
    if ($value$plusargs("apb_max_idle=%d", max_idle)) apb_cfg.max_idle_cycles = max_idle;
    env = aou_reg_env::type_id::create("env", this);
    env.apb_cfg = apb_cfg;
    uvm_root::get().set_timeout(5ms, 1);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("APB back_to_back=%0b idle=%0d..%0d",
              apb_cfg.back_to_back, apb_cfg.min_idle_cycles, apb_cfg.max_idle_cycles), UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    env.apb.wait_reset_released();
    // Both resets release together; give the core-side synchronisers time.
    env.apb.wait_cycles(10);
    env.regmodel.reset();
    run_body();
    env.apb.wait_cycles(4);
    phase.drop_objection(this);
  endtask

  virtual task run_body();
  endtask

  function void prep(aou_reg_base_seq s);
    s.rm = env.regmodel;
    s.apb_sqr = env.apb.sqr;
  endfunction
endclass
