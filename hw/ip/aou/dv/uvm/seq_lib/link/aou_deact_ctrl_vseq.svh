// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Deactivation controls in AOU_INIT.
// +mode=tov (plan 2.12; MAS 7.1 AOU_INIT.DEACTIVATE_TIME_OUT_VALUE): for each
//   value v in +tov_values (default 0..7, shuffled) the remote die starts a few
//   reads and software sets DEACTIVATE_START +0..200 cycles
//   later, so the DUT's last ReadData lands near the deactivation and its
//   DeactivateReq has to wait out the 2^(v+3)-cycle quiet window behind it
//   (MAS 7.1: the window may already have elapsed when the TX was idle).
//   aou_t1_rx_fifo_chk checks the window on every DeactivateReq (T1-L46).
// +mode=property (plan 2.10; MAS 7.1 AOU_INIT.INT_DEACTIVATE_PROPERTY): the remote
//   die deactivates with PropertyReq 0, the only value it may send (the bit is
//   reserved on DeactivateReq in v0.7 and RsvdZero in v0.8, which defines no
//   reaction to a set bit). Software holds off DEACTIVATE_START, so the DUT
//   stays in DEACTIVATE while the test reads INT_DEACTIVATE_PROPERTY back: 0
//   before any DeactivateReq, in DEACTIVATE and again in the next ENABLED epoch
//   (T1-L45, interim expectation). Its value once DISABLED is only logged.
class aou_deact_ctrl_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_deact_ctrl_vseq)

  function new(string name = "aou_deact_ctrl_vseq");
    super.new(name);
  endfunction

  task body();
    string mode = arg_str("mode", "tov");
    link_up();
    case (mode)
      "tov":      tov_sweep();
      "property": property_loops();
      default:    `uvm_fatal(get_type_name(), {"unknown +mode=", mode})
    endcase
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    check_traffic(num_txns);
  endtask

  // ---------------------------------------------------------------------
  // 2.12
  // ---------------------------------------------------------------------
  task tov_sweep();
    int vals[$];
    string vs = arg_str("tov_values", "");
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
    p.wr_pct = 0;
    if (vs != "") aou_act_after_deact_vseq::parse_offsets(vs, vals);
    else begin
      for (int v = 0; v < 8; v++) vals.push_back(v);
      vals.shuffle();
    end
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    foreach (vals[i]) begin
      `uvm_info(get_type_name(), $sformatf("DEACTIVATE_TIME_OUT_VALUE=%0d", vals[i]), UVM_LOW)
      write_field(p_sequencer.regs.aou_init.deactivate_time_out_value,
                  uvm_reg_data_t'(vals[i]));
      traffic_nb(AOU_T1_R2L, 2, p);
      wait_cycles($urandom_range(200));
      deactivate(AOU_T1_BY_APB, 1'b0);
      sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
      wait_traffic();
      drain();
    end
    sw_deactivate(AOU_T1_BY_APB);
  endtask

  // ---------------------------------------------------------------------
  // 2.10
  // ---------------------------------------------------------------------
  task property_loops();
    property_once(1'b0);
  endtask

  task property_once(bit prop);
    aou_core rm = p_sequencer.regs;
    uvm_reg_data_t v;
    int unsigned base = irq_rises("INT_DEACTIVATE_START");
    int unsigned n = 0;
    `uvm_info(get_type_name(), $sformatf("remote DeactivateReq with PropertyReq=%0b", prop),
              UVM_LOW)
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    aou_rule_log::check("T1-L45", get_type_name());
    check_field(rm.aou_init.int_deactivate_property, 0, "T1-L45", "ENABLED, no DeactivateReq yet");
    check_traffic(4);
    // The DUT stays in DEACTIVATE until the test sets DEACTIVATE_START itself.
    env.sw_isr.enable = 1'b0;
    cfg.l3_cfg.deact_prop = prop;
    env.l3.model.lnk.request_deactivate();
    env.l3.model.maybe_release_deact();
    env.l3.model.kick();
    while (irq_rises("INT_DEACTIVATE_START") == base && n++ < cfg.act_timeout) wait_cycles(1);
    if (irq_rises("INT_DEACTIVATE_START") == base)
      `uvm_error(get_type_name(), "T1-L06: no INT_DEACTIVATE_START after a remote DeactivateReq")
    repeat (2) begin
      check_field(rm.aou_init.int_deactivate_property, uvm_reg_data_t'(prop), "T1-L45",
                  "DEACTIVATE after the remote DeactivateReq, its PropertyReq");
      wait_cycles($urandom_range(300, 20));
    end
    check_field(rm.aou_init.activate_state_enabled, 0, "T1-L45", "still in DEACTIVATE");
    check_field(rm.aou_init.activate_state_disabled, 0, "T1-L45", "still in DEACTIVATE");
    write_field(rm.aou_init.deactivate_start, 1);
    fork
      wait_l3(AOU_LS_DISABLED, cfg.act_timeout);
      env.status.wait_act_state(1'b0, cfg.act_timeout);
    join
    if (!l3_ok || !env.status.act_ok)
      `uvm_error(get_type_name(), "T1-V05: deactivation did not complete")
    cfg.l3_cfg.deact_prop = 1'b0;
    rd(rm.aou_init.int_deactivate_property, v);
    `uvm_info(get_type_name(), $sformatf("DISABLED after PropertyReq=%0b: %s=%0d", prop,
                                         "INT_DEACTIVATE_PROPERTY", v), UVM_LOW)
    write_field(rm.aou_init.int_deactivate_start, 1);
    env.sw_isr.enable = 1'b1;
    wait_cycles(32);
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    check_field(rm.aou_init.int_deactivate_property, 0, "T1-L45",
                "a new ENABLED epoch after the deactivation");
    sw_deactivate(AOU_T1_BY_APB);
  endtask
endclass
