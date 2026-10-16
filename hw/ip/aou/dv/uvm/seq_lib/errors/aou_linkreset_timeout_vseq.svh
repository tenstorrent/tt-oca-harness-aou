// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The three time-out LinkReset sources (MAS §7.2.3; plan 1.3, 2.6, 3.18):
//   act_ack:   the remote die never answers the DUT's ActivateReq;
//   deact_ack: it never answers the DUT's DeactivateReq;
//   msgcredit: it completes activation but never sends a CrdtGrant.
// The time-out is shortened through its register (+tmo, 2^(tmo+18) cycles).
// The sticky bit must still be clear shortly before the time-out and set
// after it, with INT_REQ_LINKRESET unless the source is masked (BUGS/014).
// Software then recovers and traffic must work.
// Knobs: +src=act_ack|deact_ack|msgcredit|rand +mask=0|1 +tmo=0..7.
class aou_linkreset_timeout_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_linkreset_timeout_vseq)

  function new(string name = "aou_linkreset_timeout_vseq");
    super.new(name);
  endfunction

  task body();
    string srcs[3] = '{"act_ack", "deact_ack", "msgcredit"};
    string src = arg_str("src", srcs[$urandom_range(2)]);
    bit mask = 1'(arg_int("mask", 0));
    int tmo = arg_int("tmo", 0);
    int unsigned cycles = 1 << (tmo + 18);
    aou_t1_feature_cfg f = aou_t1_feature_cfg::type_id::create("f");
    aou_l3_cfg c = cfg.l3_cfg;
    aou_core rm = p_sequencer.regs;
    uvm_reg_field err;
    int unsigned depth[AOU_CC_NUM] = c.rx_depth;
    `uvm_info(get_type_name(), $sformatf("time-out %s, %0d cycles, mask=%0b", src, cycles, mask),
              UVM_LOW)
    case (src)
      "act_ack": begin
        f.ack_timeout = tmo;
        f.mask_act_ack = int'(mask);
        err = rm.lp_linkreset.act_ack_err;
      end
      "deact_ack": begin
        f.ack_timeout = tmo;
        f.mask_deact_ack = int'(mask);
        err = rm.lp_linkreset.deact_ack_err;
      end
      "msgcredit": begin
        f.msgcredit_timeout = tmo;
        f.mask_msgcredit_timeout = int'(mask);
        err = rm.lp_linkreset.msgcredit_err;
      end
      default: `uvm_fatal(get_type_name(), {"unknown time-out source ", src})
    endcase
    if (!mask) expect_event("INT_REQ_LINKRESET", 1, 1);
    link_up();
    program_cfg(f);
    case (src)
      "act_ack": begin
        c.auto_ack = 1'b0;
        c.auto_activate = 1'b0;
        ensure_link();
        dut_activate(AOU_T1_BY_APB);
        wait_l3(AOU_LS_ACTIVATE, cfg.act_timeout);
        if (!l3_ok) `uvm_error(get_type_name(), "T1-L13: no ActivateReq from the DUT")
      end
      "deact_ack": begin
        aou_reg_activation_seq d = aou_reg_activation_seq::type_id::create("d");
        sw_activate();
        check_traffic(num_txns);
        c.auto_deact_ack = 1'b0;
        c.auto_deactivate = 1'b0;
        prep_reg(d);
        d.op = AOU_REG_DEACTIVATE;
        d.wait_done = 1'b0;
        d.start(null);
        wait_l3(AOU_LS_DEACTIVATE, cfg.act_timeout);
        if (!l3_ok) `uvm_error(get_type_name(), "T1-L13: no DeactivateReq from the DUT")
      end
      default: begin
        // No credit at all, so no CrdtGrant after the remote's ActivateAck.
        c.initial_grant = 1'b0;
        foreach (c.rx_depth[k]) c.rx_depth[k] = 0;
        env.l3.model.crd.reset_link();
        sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
      end
    endcase
    // The counter starts at the request (or ActivateAck) just sent; allow
    // 2% for the APB and flit latency before it.
    wait_cycles(cycles - cycles / 50);
    check_field(err, 0, "T1-L17", "before the time-out expired");
    wait_cycles(cycles / 25);
    check_linkreset_status(err.get_name());
    clear_linkreset_status(err);
    c.auto_ack = 1'b1;
    c.auto_activate = 1'b1;
    c.auto_deact_ack = 1'b1;
    c.auto_deactivate = 1'b1;
    c.initial_grant = 1'b1;
    c.rx_depth = depth;
    recover(f);
    check_traffic(num_txns);
    sw_deactivate();
  endtask
endclass
