// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test with UCIe state encodings and a Retrain alone as its link
// event: the Adapter reports Retrain as 1011b, and a compliant DUT leaves
// Active and ends Retrain with a NOP->Active request (FDI-R48).
class aou_fdi_t1_bringup_spec_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_bringup_spec_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.req_timeout = 2000;
  endfunction

  task link_events();
    aou_lsm_retrain_seq retrain = aou_lsm_retrain_seq::type_id::create("retrain");
    `uvm_info(get_type_name(), "Adapter-initiated Retrain (pl_state_sts=1011b)", UVM_LOW)
    retrain.start(env.lsm.sqr);
    wait_link_up("retrain");
  endtask
endclass
