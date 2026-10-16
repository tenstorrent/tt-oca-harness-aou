// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// QoS arbitration: PRIOR_RP_AXI (mode, per-RP priority, QoS-to-HP/NP thresholds)
// and PRIOR_TIMER. -1 leaves a field unchanged.
class aou_reg_qos_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_qos_seq)

  int arb_mode = -1;
  int rp_prior[4] = '{-1, -1, -1, -1};
  int qos_to_hp = -1;
  int qos_to_np = -1;
  int timer_threshold = -1;
  int timer_resolution = -1;

  function new(string name = "aou_reg_qos_seq");
    super.new(name);
  endfunction

  task body();
    want(rm.prior_rp_axi.arb_mode, arb_mode);
    foreach (rp_prior[i])
      want(field(rm.prior_rp_axi, $sformatf("rp%0d_prior", i)), rp_prior[i]);
    want(rm.prior_rp_axi.axi_qos_to_hp, qos_to_hp);
    want(rm.prior_rp_axi.axi_qos_to_np, qos_to_np);
    want(rm.prior_timer.timer_threshold, timer_threshold);
    want(rm.prior_timer.timer_resolution, timer_resolution);
    commit();
  endtask
endclass
