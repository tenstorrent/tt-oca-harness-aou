// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test with UCIe state encodings. Reset/Active bringup works
// (those codes agree), then the Adapter reports Retrain as 1011b. A
// compliant DUT leaves Active and ends Retrain with a NOP->Active request;
// with BUGS/001 the DUT ignores the code. Expected to fail
// (expected_fail.yaml).
class aou_fdi_t1_bringup_spec_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_bringup_spec_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.fdi_enc = AOU_FDI_ENC_SPEC;
    env.lsm_cfg.req_timeout = 2000;
  endfunction

  task link_events();
    aou_lsm_retrain_seq retrain = aou_lsm_retrain_seq::type_id::create("retrain");
    `uvm_info(get_type_name(), "Adapter-initiated Retrain (pl_state_sts=1011b)", UVM_LOW)
    retrain.start(env.lsm.sqr);
    wait_link_up("retrain");
  endtask
endclass
