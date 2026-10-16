// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test with UCIe state encodings and a LinkError the protocol
// layer raises itself (I_SW_LINKERROR_INJECT). UCIe r1.1 Table 8-2: the
// protocol layer signals it on lp_linkerror, and the Adapter takes the link
// to LinkError, then Reset, once it sees it. AOU_TOP has no lp_linkerror
// (BUGS/002), so the bringup model reports FDI-M07. The Adapter then takes
// the link down anyway, which brings the DUT back. Expected to fail
// (expected_fail.yaml).
class aou_fdi_t1_linkerror_spec_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_linkerror_spec_test)

  int unsigned linkerror_wait = 200;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    env.lsm_cfg.fdi_enc = AOU_FDI_ENC_SPEC;
    env.lsm_cfg.req_timeout = 2000;
  endfunction

  task link_events();
    aou_lsm_linkerror_seq le = aou_lsm_linkerror_seq::type_id::create("linkerror");
    int unsigned n = 0;
    `uvm_info(get_type_name(), "pulsing I_SW_LINKERROR_INJECT", UVM_LOW)
    env.lsm.drv.pulse_sw(LSM_SW_LINKERROR, 2);
    while (lsm_vif.mon_cb.lp_linkerror !== 1'b1 && n < linkerror_wait) begin
      @(lsm_vif.mon_cb);
      n++;
    end
    if (lsm_vif.mon_cb.lp_linkerror === 1'b1)
      `uvm_info(get_type_name(), $sformatf("lp_linkerror after %0d cycles", n), UVM_LOW)
    // The re-bringup must not wait for I_SW_ACTIVATE_START.
    env.lsm_cfg.clk_req_hold_bringup = 1'b1;
    le.start(env.lsm.sqr);
    wait_link_up("LinkError recovery");
  endtask
endclass
