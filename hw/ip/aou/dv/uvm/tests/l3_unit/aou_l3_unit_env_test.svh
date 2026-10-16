// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Clocked unit environment: two L3 agents (A on the LP stream in the DUT's
// place, B on PL as the remote model), each with a memory L4a and a traffic
// generator, joined by aou_l3_unit_link, with AOU_FDI_CHECKER on both streams.
// Plusargs: +L3_POLICY=dut|sparse|min|max|random|split, +L3_FORK=1,
// +L3_RET=consume|delayed|immediate, +L3_TXN=<n>.
class aou_l3_unit_env_test extends aou_l3_unit_base_test;
  `uvm_component_utils(aou_l3_unit_env_test)

  virtual aou_l3_unit_if uvif;
  aou_l3_cfg          cfg_a;
  aou_l3_cfg          cfg_b;
  aou_l3_agent        a;
  aou_l3_agent        b;
  aou_l3_unit_link    link;
  aou_l3_unit_gen     gen_a;
  aou_l3_unit_gen     gen_b;
  aou_l3_unit_l4a     mem_a;
  aou_l3_unit_l4a     mem_b;
  aou_fdi_chk_adapter fdi_chk;
  string              policy = "dut";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void apply_policy(aou_l3_cfg c);
    string ret = "consume";
    int unsigned f = 0;
    case (policy)
      "sparse": c.pol.set_sparse();
      "min":    c.pol.set_min_density();
      "max":    c.pol.set_max_density();
      "random": c.pol.set_random();
      "split": begin
        c.pol.set_dut_like();
        c.pol.split_at = $urandom_range(1, 26);
      end
      default:  c.pol.set_dut_like();
    endcase
    void'($value$plusargs("L3_FORK=%d", f));
    c.resp_fork = f != 0;
    void'($value$plusargs("L3_RET=%s", ret));
    if (ret == "delayed") begin
      c.ret_policy = '{AOU_RET_DELAYED, AOU_RET_DELAYED, AOU_RET_DELAYED, AOU_RET_DELAYED,
                       AOU_RET_DELAYED};
      c.ret_delay = $urandom_range(1, 6);
    end else if (ret == "immediate") begin
      c.ret_policy = '{AOU_RET_IMMEDIATE, AOU_RET_IMMEDIATE, AOU_RET_IMMEDIATE,
                       AOU_RET_IMMEDIATE, AOU_RET_IMMEDIATE};
    end
    `uvm_info(get_type_name(), {c.get_name(), ": ", c.convert2string()}, UVM_LOW)
  endfunction

  function void build_phase(uvm_phase phase);
    int unsigned n = 16;
    super.build_phase(phase);
    if (!uvm_config_db#(virtual aou_l3_unit_if)::get(this, "", "l3_unit", uvif))
      `uvm_fatal(get_type_name(), "no aou_l3_unit_if")
    void'($value$plusargs("L3_POLICY=%s", policy));
    void'($value$plusargs("L3_TXN=%d", n));
    cfg_a = mk_cfg("cfg_a");
    cfg_b = mk_cfg("cfg_b");
    apply_policy(cfg_a);
    apply_policy(cfg_b);
    mem_a = aou_l3_unit_l4a::type_id::create("mem_a");
    mem_b = aou_l3_unit_l4a::type_id::create("mem_b");
    mem_a.vif = uvif;
    mem_b.vif = uvif;
    cfg_a.l4a = mem_a;
    cfg_b.l4a = mem_b;
    a = aou_l3_agent::type_id::create("a", this);
    b = aou_l3_agent::type_id::create("b", this);
    a.cfg = cfg_a;
    b.cfg = cfg_b;
    link = aou_l3_unit_link::type_id::create("link", this);
    gen_a = aou_l3_unit_gen::type_id::create("gen_a", this);
    gen_b = aou_l3_unit_gen::type_id::create("gen_b", this);
    gen_a.n_txn = n;
    gen_b.n_txn = n;
    gen_a.base = 64'h0000_0001_0000_0000;
    gen_b.base = 64'h0000_0002_0000_0000;
    fdi_chk = aou_fdi_chk_adapter::type_id::create("fdi_chk", this);
    fdi_chk.chk = chk;
    uvm_top.set_timeout(5ms);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    link.a = a;
    link.b = b;
    gen_a.agt = a;
    gen_b.agt = b;
    a.ap_rx_msg.connect(gen_a.rsp_imp);
    b.ap_rx_msg.connect(gen_b.rsp_imp);
  endfunction

  task bring_up();
    fork
      a.activate();
      b.wait_state(AOU_LS_ENABLED);
    join
  endtask

  task traffic();
    fork
      gen_a.run_traffic();
      gen_b.run_traffic();
    join
  endtask

  task idle(int unsigned cycles);
    repeat (cycles) @(uvif.drv_cb);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    bring_up();
    traffic();
    a.deactivate();
    b.wait_state(AOU_LS_DISABLED);
    idle(20);
    phase.drop_objection(this);
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    expect_true(gen_a.mismatches == 0 && gen_b.mismatches == 0, "no read-data mismatch");
    expect_true(gen_a.rd_done == gen_a.n_txn && gen_b.rd_done == gen_b.n_txn,
                $sformatf("all reads complete (%0d, %0d of %0d)", gen_a.rd_done, gen_b.rd_done,
                          gen_a.n_txn));
    expect_true(a.model.lnk.enabled_cnt == 1 && b.model.lnk.enabled_cnt == 1, "one activation");
  endfunction
endclass
