// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data-path and feature scenarios: optionally program DUT features (before
// activation, as the MAS requires for split, aggregator and DEST_RP), activate,
// run traffic phases, drain. The test fills the fields; feature vseqs extend
// configure_dut() and scenario().
class aou_dp_vseq extends aou_base_test_seq;
  `uvm_object_utils(aou_dp_vseq)

  aou_dp_knobs k;

  function new(string name = "aou_dp_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    if (!uvm_config_db#(aou_dp_knobs)::get(null, "*", "dp_knobs", k)) begin
      k = aou_dp_knobs::type_id::create("k");
      k.apply_plusargs();
    end
    if (k.n != 0) num_txns = k.n;
  endtask

  function aou_t1_traffic_cfg make_profile();
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named(k.profile);
    if (k.wr_pct >= 0) p.wr_pct = k.wr_pct;
    if (k.num_slots >= 0) p.num_slots = k.num_slots;
    p.max_id = 10'(k.max_id);
    p.rp_mask = k.rp_mask;
    return p;
  endfunction

  virtual task configure_dut();
    if (k.feat != null) program_cfg(k.feat);
  endtask

  virtual task scenario();
    for (int unsigned i = 0; i < k.phases; i++) traffic(k.dir, num_txns, make_profile());
  endtask

  task body();
    link_up();
    configure_dut();
    // Remote-only activation waits for software to answer INT_ACTIVATE_START,
    // which activate() does not do; the link tests cover it.
    activate(($urandom_range(1) == 1) ? AOU_T1_BY_APB : AOU_T1_BY_BOTH, AOU_T1_ORDER_RANDOM);
    scenario();
    drain();
  endtask

  // Reads a register field over APB (front door).
  task read_field(uvm_reg_field f, output uvm_reg_data_t v);
    aou_dp_rd_seq s = aou_dp_rd_seq::type_id::create("rd");
    prep_reg(s);
    s.f = f;
    s.start(null);
    v = s.value;
  endtask

  task expect_field(uvm_reg_field f, uvm_reg_data_t exp, string rule);
    uvm_reg_data_t v;
    read_field(f, v);
    if (v != exp)
      `uvm_error(get_type_name(), $sformatf("%s: %s reads 0x%0h, expected 0x%0h", rule,
                                            f.get_full_name(), v, exp))
  endtask
endclass
