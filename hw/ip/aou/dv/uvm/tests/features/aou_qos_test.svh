// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX QoS arbitration modes (plan 13.1, 13.4, 13.11-13.14; 4x512-sp64 13.2-13.7).
// +arb_mode=0..3 (3 is reserved and behaves as round-robin per MAS), random
// per-RP priorities including 0 (treated as 1), random starvation timer
// including 0 and 0xFFFF, and with +qos_bounds=1 random AXI_QOS_TO_HP >
// AXI_QOS_TO_NP. Local traffic uses AxQOS values at and either side of both
// boundaries. Checks: every transfer intact and in ID order under each mode.
// The arbitration order itself (FEAT-R11..R14) is checked by
// aou_qos_order_test, which builds a backlog behind hold_tx().
class aou_qos_test extends aou_dp_base_test;
  `uvm_component_utils(aou_qos_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    int arb = 2;
    int bounds = 0;
    int hp = 10;
    int np = 5;
    int extremes[3] = '{0, 1, 'hFFFF};
    void'($value$plusargs("arb_mode=%d", arb));
    void'($value$plusargs("qos_bounds=%d", bounds));
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    k.feat.arb_mode = arb;
    foreach (k.feat.rp_prior[r]) k.feat.rp_prior[r] = $urandom_range(3);
    k.feat.timer_threshold = ($urandom_range(1) == 1) ? extremes[$urandom_range(2)]
                                                      : $urandom_range(64);
    k.feat.timer_resolution = ($urandom_range(1) == 1) ? extremes[$urandom_range(2)]
                                                       : $urandom_range(16);
    if (bounds != 0) begin
      hp = $urandom_range(15, 1);
      np = $urandom_range(hp - 1);
      k.feat.qos_to_hp = hp;
      k.feat.qos_to_np = np;
    end
    k.qos = '{0, 15};
    if (np > 0) k.qos.push_back(np - 1);
    k.qos.push_back(np);
    k.qos.push_back(hp - 1);
    k.qos.push_back(hp);
    k.dir = AOU_T1_L2R;
    k.lens = '{0, 1, 3, 15};
    k.wr_pct = 50;
    k.n = 128;
  endfunction
endclass
