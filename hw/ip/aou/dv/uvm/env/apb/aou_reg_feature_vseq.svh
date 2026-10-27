// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Runs every feature-programming sequence with random arguments and reads back
// the fields each one programmed (REG-R02). Activation is requested last and
// then forced off, since nothing answers on FDI in a register-only bench.
class aou_reg_feature_vseq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_feature_vseq)

  bit with_activation = 1'b1;

  function new(string name = "aou_reg_feature_vseq");
    super.new(name);
  endfunction

  task expect_field(uvm_reg_field f, int unsigned exp);
    uvm_reg_data_t got;
    rd_field(f, got);
    if (got != uvm_reg_data_t'(exp))
      `uvm_error(get_type_name(), $sformatf("REG-R02: %s read 0x%0h, expected 0x%0h",
                                            f.get_full_name(), got, exp))
  endtask

  function void prep(aou_reg_base_seq s);
    s.rm = rm;
    s.apb_sqr = apb_sqr;
  endfunction

  task body();
    for (int unsigned rp = 0; rp < 4; rp++) begin
      aou_reg_split_seq      split = aou_reg_split_seq::type_id::create("split");
      aou_reg_aggregator_seq agg   = aou_reg_aggregator_seq::type_id::create("agg");
      aou_reg_early_resp_seq early = aou_reg_early_resp_seq::type_id::create("early");
      aou_reg_dest_rp_seq    dest  = aou_reg_dest_rp_seq::type_id::create("dest");
      uvm_reg split_rg = rm.get_reg_by_name($sformatf("axi_split_tr_rp%0d", rp));
      uvm_reg early_rg = rm.get_reg_by_name($sformatf("write_early_response_rp%0d", rp));
      prep(split);
      split.rp = rp;
      split.max_arburstlen = (1 << $urandom_range(8)) - 1;
      split.max_awburstlen = (1 << $urandom_range(8)) - 1;
      split.start(null, this);
      expect_field(field(split_rg, "max_arburstlen"), split.max_arburstlen);
      expect_field(field(split_rg, "max_awburstlen"), split.max_awburstlen);
      // MAS: a value other than 2^n - 1 is stored as 0xF.
      split.max_arburstlen = -1;
      split.max_awburstlen = 2 * $urandom_range(127, 1);
      split.start(null, this);
      expect_field(field(split_rg, "max_awburstlen"), 'hF);
      prep(agg);
      agg.rp = rp;
      agg.enable = $urandom_range(1);
      agg.start(null, this);
      expect_field(field(rm.aou_con0, $sformatf("rp%0d_axi_aggregator_en", rp)), agg.enable);
      prep(early);
      early.rp = rp;
      early.enable = $urandom_range(1);
      early.wdt_en = $urandom_range(1);
      early.start(null, this);
      expect_field(field(early_rg, "early_bresp_en"), early.enable);
      expect_field(field(early_rg, "wdt_en"), early.wdt_en);
      prep(dest);
      dest.rp = rp;
      dest.dest = $urandom_range(3);
      dest.start(null, this);
      expect_field(field(rm.dest_rp, $sformatf("rp%0d_dest", rp)), dest.dest);
    end
    run_qos();
    run_lp_and_masks();
    for (int unsigned rp = 0; rp < 4; rp++) begin
      aou_reg_error_info_seq ei = aou_reg_error_info_seq::type_id::create("ei");
      prep(ei);
      ei.rp = rp;
      ei.access_en = 1;
      ei.clear = 1'b1;
      ei.start(null, this);
      expect_field(field(rm.aou_con0, $sformatf("rp%0d_error_info_access_en", rp)), 1);
    end
    if (with_activation) run_activation();
  endtask

  task run_qos();
    aou_reg_qos_seq qos = aou_reg_qos_seq::type_id::create("qos");
    prep(qos);
    qos.arb_mode = $urandom_range(3);
    foreach (qos.rp_prior[i]) qos.rp_prior[i] = $urandom_range(3);
    qos.qos_to_hp = $urandom_range(15);
    qos.qos_to_np = $urandom_range(15);
    qos.timer_threshold = $urandom_range(32'hFFFF);
    qos.timer_resolution = $urandom_range(32'hFFFF);
    qos.start(null, this);
    expect_field(rm.prior_rp_axi.arb_mode, qos.arb_mode);
    foreach (qos.rp_prior[i])
      expect_field(field(rm.prior_rp_axi, $sformatf("rp%0d_prior", i)), qos.rp_prior[i]);
    expect_field(rm.prior_rp_axi.axi_qos_to_hp, qos.qos_to_hp);
    expect_field(rm.prior_rp_axi.axi_qos_to_np, qos.qos_to_np);
    expect_field(rm.prior_timer.timer_threshold, qos.timer_threshold);
    expect_field(rm.prior_timer.timer_resolution, qos.timer_resolution);
  endtask

  task run_lp_and_masks();
    aou_reg_lp_mode_seq  lp   = aou_reg_lp_mode_seq::type_id::create("lp");
    aou_reg_int_mask_seq mask = aou_reg_int_mask_seq::type_id::create("mask");
    aou_reg_timeout_seq  tmo  = aou_reg_timeout_seq::type_id::create("tmo");
    prep(lp);
    lp.enable = $urandom_range(1);
    lp.threshold = $urandom_range(255);
    lp.start(null, this);
    expect_field(rm.aou_con0.tx_lp_mode, lp.enable);
    expect_field(rm.aou_con0.tx_lp_mode_threshold, lp.threshold);
    prep(mask);
    mask.set_all(1);
    mask.early_resp = 0;
    mask.start(null, this);
    expect_field(rm.aou_interrupt_mask.int_si0_id_mismatch_mask, 1);
    expect_field(rm.aou_interrupt_mask.int_early_resp_mask, 0);
    expect_field(rm.aou_interrupt_mask.int_req_linkreset_act_ack_mask, 1);
    prep(tmo);
    tmo.msgcredit = $urandom_range(7);
    tmo.ack = $urandom_range(7);
    tmo.deactivate = $urandom_range(7);
    tmo.start(null, this);
    expect_field(rm.lp_linkreset.msgcredit_time_out_value, tmo.msgcredit);
    expect_field(rm.lp_linkreset.ack_time_out_value, tmo.ack);
    expect_field(rm.aou_init.deactivate_time_out_value, tmo.deactivate);
  endtask

  task run_activation();
    aou_reg_activation_seq act = aou_reg_activation_seq::type_id::create("act");
    aou_reg_activation_seq deact = aou_reg_activation_seq::type_id::create("deact");
    prep(act);
    act.op = AOU_REG_ACTIVATE;
    act.wait_done = 1'b0;
    act.start(null, this);
    prep(deact);
    deact.op = AOU_REG_FORCE_DEACTIVATE;
    deact.start(null, this);
  endtask
endclass
