// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Stimulus for the DUT's RX credit (plan 3.20, 3.23, 3.25; MAS 3.4, 3.9).
// Every loop is one activation epoch: the DUT advertises its credit, then
// (+bp=1) every M port holds AWREADY, WREADY and ARREADY low for +hold cycles
// while the remote die sends writes and reads, so they queue in the DUT's RX
// FIFOs; the ports are released, traffic runs both ways and drains, and the
// link deactivates. A last activation ends the test quiescent in ENABLED.
// The checks are passive: aou_l3_model (T1-C40: never more credit than the
// MAS 3.9 maximum for the RP's RX FIFO depth and width, and all of it once
// quiescent) and aou_t1_rx_fifo_chk (T1-C41: credit for messages still in the
// RX FIFO stays with the DUT). The -rxf configuration builds the DUT with
// non-default FIFO depths and the RX FIFO register slices off (3.25).
// Knobs: +loops +hold=<cycles> +bp=0|1 +T1_TXN=<remote transactions per RP
// while held>.
class aou_rx_credit_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_rx_credit_vseq)

  function new(string name = "aou_rx_credit_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned loops = arg_range("loops", 2, 3);
    bit bp = 1'(arg_int("bp", 1));
    link_up();
    for (int unsigned i = 0; i < loops; i++) begin
      sw_activate();
      if (bp) held_traffic();
      traffic(AOU_T1_BOTH_DIRS, 8, aou_t1_traffic_cfg::named("short"));
      drain();
      sw_deactivate();
    end
    sw_activate();
    check_traffic(8);
  endtask

  task held_traffic();
    aou_credit_mgr crd = env.l3.model.crd;
    int unsigned hold = arg_int("hold", 3000);
    int unsigned g0[AOU_RP_MAX][AOU_CC_NUM];
    int unsigned k0[AOU_RP_MAX][AOU_CC_NUM];
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
    p.max_len = 8'd1;
    p.num_slots = 64;
    foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].hold_req = 1'b1;
    g0 = crd.tx_granted;
    k0 = crd.tx_consumed;
    `uvm_info(get_type_name(), $sformatf("M ports held: %0d remote transactions per RP", num_txns),
              UVM_LOW)
    traffic_nb(AOU_T1_R2L, num_txns, p);
    wait_cycles(hold);
    for (int unsigned r = 0; r < cfg.n_rp; r++)
      for (int unsigned c = 0; c < 3; c++)
        `uvm_info(get_type_name(), $sformatf("M port held: RP%0d %s used %0d, returned %0d", r,
                                             aou_cc_name(aou_cred_class_e'(c)),
                                             crd.tx_consumed[r][c] - k0[r][c],
                                             crd.tx_granted[r][c] - g0[r][c]), UVM_LOW)
    foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].hold_req = 1'b0;
    wait_traffic();
    drain();
  endtask
endclass
