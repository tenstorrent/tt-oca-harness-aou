// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The bringup test with UCIe state encodings and a LinkError the protocol
// layer raises itself (I_SW_LINKERROR_INJECT). UCIe r1.1 Table 8-2: the
// protocol layer signals it on lp_linkerror, and the Adapter takes the link
// to LinkError, then Reset, once it sees it. The bringup model checks the
// raise and hold on the DUT's O_LP_LINKERROR (FDI-M07); the Adapter then
// takes the link down, which brings the DUT back. Then the same request
// while the Adapter holds the link in Retrain: LinkError may follow any state
// (UCIe r3.0 Figure 10-19), so the Adapter answers it there too, and the DUT
// must raise and hold lp_linkerror as in Active.
class aou_fdi_t1_linkerror_spec_test extends aou_fdi_t1_bringup_test;
  `uvm_component_utils(aou_fdi_t1_linkerror_spec_test)

  int unsigned linkerror_wait = 200;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
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
    send_flits(2, 25);
    linkerror_in_retrain();
  endtask

  // A Retrain held long enough for the request to land inside it; the
  // Adapter answers lp_linkerror there and trains again afterwards.
  local task linkerror_in_retrain();
    aou_lsm_retrain_seq rt = aou_lsm_retrain_seq::type_id::create("retrain");
    int unsigned n = 0;
    rt.ev_cycles = 400;
    fork
      rt.start(env.lsm.sqr);
      begin
        while (env.lsm.drv.state != LSM_RETRAIN && n++ < link_timeout) @(lsm_vif.mon_cb);
        repeat ($urandom_range(100, 5)) @(lsm_vif.mon_cb);
        `uvm_info(get_type_name(), "pulsing I_SW_LINKERROR_INJECT in Retrain", UVM_LOW)
        env.lsm.drv.pulse_sw(LSM_SW_LINKERROR, 2);
      end
    join
    wait_link_up("LinkError in Retrain recovery");
  endtask
endclass
