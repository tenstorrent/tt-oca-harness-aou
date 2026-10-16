// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Resets at awkward moments, then recovery and traffic (plan 11.10-11.12,
// 11.15). The DUT is first programmed away from its reset values; each loop
// picks a reset and a moment:
//   +reset  sw    AOU_SW_RESET inside the MAS LinkReset sequence (BUGS/007
//                 interim: every register returns to its reset value)
//           core  I_RESETN only     } BUGS/016 interim: the registers are on
//           apb   I_PRESETN only    } the core reset, so they return to their
//           both  both resets       } reset values on I_RESETN and keep their
//                                   } values on I_PRESETN alone
//   +when   idle, traffic (transactions in flight), activating (in the
//           middle of the activation handshake), queued (DUT TX queue held
//           non-empty by zero WREQ credit).
// After the reset software checks the registers, reprograms, brings the
// link up and activates; in-flight transactions count as aborted and all
// later traffic must complete with correct data.
// Knobs: +reset=sw|core|apb|both|rand +when=idle|traffic|activating|queued|
// rand +loops +T1_TXN.
class aou_reset_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_reset_vseq)

  aou_t1_feature_cfg f;
  bit                queued;     // WREQ credit withheld for the current loop
  uvm_reg_field      prog_f[$];
  int                prog_v[$];

  function new(string name = "aou_reset_vseq");
    super.new(name);
  endfunction

  task body();
    string resets[4] = '{"sw", "core", "apb", "both"};
    string whens[4] = '{"idle", "traffic", "activating", "queued"};
    int unsigned loops = arg_range("loops", 1, 3);
    string r_arg = arg_str("reset", "rand");
    string w_arg = arg_str("when", "rand");
    pick_config();
    link_up();
    program_cfg(f);
    sw_activate();
    for (int unsigned i = 0; i < loops; i++) begin
      string rs = (r_arg == "rand") ? resets[$urandom_range(3)] : r_arg;
      string wh = (w_arg == "rand") ? whens[$urandom_range(3)] : w_arg;
      `uvm_info(get_type_name(), $sformatf("loop %0d/%0d: %s reset while %s", i + 1, loops,
                                           rs, wh), UVM_LOW)
      setup(wh);
      do_reset(rs);
      wait_traffic();
      drain();
      check_traffic(num_txns);
    end
    sw_deactivate();
  endtask

  // Register settings away from reset that leave traffic legal.
  function void pick_config();
    aou_core rm = p_sequencer.regs;
    int unsigned bl[5] = '{7, 15, 31, 63, 127};
    f = aou_t1_feature_cfg::type_id::create("f");
    f.lp_threshold = $urandom_range(255, 5);
    f.ack_timeout = $urandom_range(7, 5);
    f.msgcredit_timeout = $urandom_range(7, 5);
    f.mask_early_resp = 1;
    f.mask_mi0_id_mismatch = 1;
    f.split_ar[0] = bl[$urandom_range(4)];
    f.split_aw[0] = bl[$urandom_range(4)];
    note(rm.aou_con0.tx_lp_mode_threshold, f.lp_threshold);
    note(rm.lp_linkreset.ack_time_out_value, f.ack_timeout);
    note(rm.lp_linkreset.msgcredit_time_out_value, f.msgcredit_timeout);
    note(rm.aou_interrupt_mask.int_early_resp_mask, 1);
    note(rm.aou_interrupt_mask.int_mi0_id_mismatch_mask, 1);
    note(rm.axi_split_tr_rp0.max_arburstlen, f.split_ar[0]);
    note(rm.axi_split_tr_rp0.max_awburstlen, f.split_aw[0]);
  endfunction

  function void note(uvm_reg_field fld, int v);
    prog_f.push_back(fld);
    prog_v.push_back(v);
  endfunction

  // Each programmed field reads its programmed value (kept=1) or its reset
  // value (kept=0).
  task check_config(bit kept, string why);
    foreach (prog_f[i]) begin
      uvm_reg_data_t exp = kept ? uvm_reg_data_t'(prog_v[i]) : prog_f[i].get_reset();
      check_field(prog_f[i], exp, "T1-L23", why);
    end
  endtask

  task setup(string wh);
    case (wh)
      "idle": check_traffic(num_txns);
      "traffic": begin
        traffic_nb(AOU_T1_BOTH_DIRS, num_txns);
        wait_cycles($urandom_range(600, 20));
      end
      "activating": begin
        sw_deactivate();
        // Both sides start; the reset lands inside the handshake.
        ensure_link();
        dut_activate(AOU_T1_BY_APB);
        env.l3.model.lnk.request_activate();
        env.l3.model.kick();
        wait_cycles($urandom_range(80, 1));
      end
      "queued": begin
        aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
        sw_deactivate();
        cfg.l3_cfg.rx_depth[AOU_CC_WREQ] = 0;
        // A deactivation that failed leaves the DUT holding credit L3 must keep
        // counting; only a link that reached DISABLED starts from rx_depth.
        if (env.l3.model.lnk.state == AOU_LS_DISABLED) env.l3.model.crd.reset_link();
        sw_activate();
        p.wr_pct = 100;
        traffic_nb(AOU_T1_L2R, num_txns, p);
        queued = 1'b1;
        wait_cycles(500);
        // The next activation after the reset advertises WREQ credit again.
        cfg.l3_cfg.rx_depth[AOU_CC_WREQ] = 64;
      end
      default: `uvm_fatal(get_type_name(), {"unknown moment ", wh})
    endcase
  endtask

  task do_reset(string rs);
    case (rs)
      "sw": begin
        recover(null, 1'b0);
        check_config(1'b0, "after AOU_SW_RESET (BUGS/007 interim)");
        program_cfg(f);
      end
      "core": begin
        hard_reset(AOU_T1_RST_CORE, 1'b0);
        check_config(1'b0, "I_RESETN resets the registers (BUGS/016 interim)");
        program_cfg(f);
        link_up();
      end
      "apb": begin
        hard_reset(AOU_T1_RST_APB, 1'b0);
        check_config(1'b1, "I_PRESETN alone keeps the registers (BUGS/016 interim)");
      end
      "both": begin
        hard_reset(AOU_T1_RST_BOTH, 1'b0);
        check_config(1'b0, "after both resets");
        program_cfg(f);
        link_up();
      end
      default: `uvm_fatal(get_type_name(), {"unknown reset ", rs})
    endcase
    if (rs == "apb") begin
      // I_PRESETN alone leaves the core and the AoU link running (BUGS/016);
      // a handshake in progress completes and withheld credit is granted
      // here, since no new activation will advertise it.
      env.status.wait_act_state(1'b1, cfg.act_timeout);
      if (!env.status.act_ok)
        `uvm_error(get_type_name(), "T1-L24: AoU not ENABLED after I_PRESETN alone")
      if (queued) begin
        for (int unsigned r = 0; r < cfg.n_rp; r++) begin
          aou_l3_overgrant_seq g = aou_l3_overgrant_seq::type_id::create("g");
          g.cls = AOU_CC_WREQ;
          g.rp = 2'(r);
          g.n = 64;
          g.start(p_sequencer.l3_sqr);
        end
      end
    end else begin
      sw_activate();
    end
    queued = 1'b0;
  endtask
endclass
