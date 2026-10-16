// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of the data-path and feature tests. A test sets its default knobs in
// set_knobs(); +dp_* plusargs then override them (aou_dp_knobs), and the knobs
// go to uvm_config_db for aou_dp_vseq and aou_dp_seq. With use_dp_seq the
// env's random traffic runs aou_dp_seq (factory override).
class aou_dp_base_test extends aou_base_test;
  `uvm_component_utils(aou_dp_base_test)

  aou_dp_knobs k;
  bit          use_dp_seq = 1'b1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_dp_vseq";
  endfunction

  virtual function void set_knobs();
  endfunction

  function void build_phase(uvm_phase phase);
    k = aou_dp_knobs::type_id::create("k");
    set_knobs();
    k.apply_plusargs();
    uvm_config_db#(aou_dp_knobs)::set(null, "*", "dp_knobs", k);
    if (use_dp_seq) aou_axi_rand_seq::type_id::set_type_override(aou_dp_seq::get_type());
    super.build_phase(phase);
    `uvm_info(get_type_name(), {"knobs: ", k.convert2string()}, UVM_LOW)
  endfunction

  function void configure();
    if (k.dir == AOU_T1_L2R) min_r2l = 0;
    if (k.dir == AOU_T1_R2L) min_l2r = 0;
    configure_test();
  endfunction

  virtual function void configure_test();
  endfunction
endclass
