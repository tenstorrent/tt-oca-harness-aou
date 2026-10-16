// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI requests before AoU activation (plan 9.6). With the link up but AoU
// DISABLED the DUT has no credits and may send only ActivateReq (AoU 8.4;
// MAS 7.3.1), so local requests must wait: none completes and no request
// reaches the remote die (its L3 checker and AOU_FDI_CHECKER would report a
// credited message outside ENABLED). A request waiting to be sent raises
// INT_ACTIVATE_START (MAS 7.3.5, condition 1); the local software is held
// off, so the interrupt must stay set until software activates. Once both
// dies are ENABLED every request completes with correct data.
// Knobs: +hold=<cycles to wait before activating> (default 500..3000).
class aou_before_enable_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_before_enable_vseq)

  function new(string name = "aou_before_enable_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned hold = arg_range("hold", 500, 3000);
    int unsigned rx0;
    link_up();
    check_field(p_sequencer.regs.aou_init.activate_state_enabled, 0, "T1-E14", "before activation");
    rx0 = env.l3.model.rx_flits;
    env.sw_isr.enable = 1'b0;
    traffic_nb(AOU_T1_L2R, num_txns);
    wait_cycles(hold);
    if (env.sb.n_l2r_wr + env.sb.n_l2r_rd != 0)
      `uvm_error(get_type_name(), $sformatf("T1-E14: %0d requests completed before activation",
                                            env.sb.n_l2r_wr + env.sb.n_l2r_rd))
    if (env.remote.n_wr + env.remote.n_rd != 0)
      `uvm_error(get_type_name(), $sformatf(
          "T1-E14: the remote die served %0d requests before activation",
                                            env.remote.n_wr + env.remote.n_rd))
    `uvm_info(get_type_name(), $sformatf("%0d flits from the DUT while DISABLED, nothing completed",
                                         env.l3.model.rx_flits - rx0), UVM_LOW)
    check_field(p_sequencer.regs.aou_init.int_activate_start, 1, "T1-E14",
                "a request waiting before activation");
    check_field(p_sequencer.regs.aou_init.activate_state_enabled, 0, "T1-E14",
                "software has not activated");
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    wr(p_sequencer.regs.aou_init.int_activate_start, 1);
    env.sw_isr.enable = 1'b1;
    wait_traffic();
    drain();
    check_traffic(num_txns);
    sw_deactivate();
  endtask
endclass
