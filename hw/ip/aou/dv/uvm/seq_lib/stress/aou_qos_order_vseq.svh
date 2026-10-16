// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// QoS arbitration order (MAS 3.2.1, Figures 4-7). Each round holds the DUT's
// TX (hold_tx), then issues reads and single-beat writes on each tier's RP,
// lowest tier first with `gap` cycles between tiers so the ring buffer and the
// lower tiers' queues fill before the higher tiers arrive, releases the TX and
// hands the result to aou_qos_order_chk. Tiers: Port QoS (arb_mode 1) maps
// RPn_PRIOR 3/2/1 to high/normal/low (Figure 6); AXI QoS (arb_mode 2) takes
// each RP's AxQOS against AXI_QOS_TO_HP/NP; round-robin (arb_mode 0, or equal
// priorities) puts every RP in one tier.
class aou_qos_order_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_qos_order_vseq)

  int unsigned rounds = 2;
  int unsigned n = 8;
  int unsigned gap = 800;
  int          tier[4];
  bit [3:0]    qos_of[4];
  aou_qos_order_chk::expect_e exp = aou_qos_order_chk::QOS_ORDER;
  aou_qos_order_chk chk;

  function new(string name = "aou_qos_order_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    if (!uvm_config_db#(aou_qos_order_chk)::get(null, "*", "qos_chk", chk))
      `uvm_fatal(get_type_name(), "no qos_chk")
    if (cfg.n_rp < 2) `uvm_fatal(get_type_name(), "needs a multi-RP CONFIG (4x512-sp64)")
    setup();
  endtask

  // Plusargs (see aou_qos_order_test) -> tiers, AxQOS and the feature settings
  // that configure_dut() programs before activation.
  function void setup();
    string s;
    int arb = 1;
    int hp = 10;
    int np = 5;
    string bounds = "0";
    int prior0 = 0;
    int rps[$];
    int ntier = 3;
    bit eq01 = 1'b0;
    string timer = "off";
    int unsigned v_u;
    void'($value$plusargs("arb_mode=%d", arb));
    void'($value$plusargs("qos_bounds=%s", bounds));
    void'($value$plusargs("qos_prior0=%d", prior0));
    if ($value$plusargs("qos_rounds=%d", v_u)) rounds = v_u;
    if ($value$plusargs("qos_tiers=%s", s)) begin
      eq01 = s == "eq01";
      ntier = (s == "eq" || eq01) ? 1 : s.atoi();
    end
    void'($value$plusargs("qos_timer=%s", timer));
    if (arb == 0 || arb == 3) ntier = 1;
    for (int r = 0; r < int'(cfg.n_rp); r++) rps.push_back(r);
    rps.shuffle();
    if (bounds == "inv") begin
      // HP at or below NP (MAS 3.2.1: the Normal tier is empty). Interim
      // (BUGS/049): a QoS at or above HP is High even
      // when it is below NP, so High is [HP, 15] and Low [0, HP-1].
      if (arb != 2 || ntier != 2)
        `uvm_fatal(get_type_name(), "+qos_bounds=inv needs +arb_mode=2 +qos_tiers=2")
      hp = $urandom_range(15, 1);
      np = $urandom_range(15, hp);
      k.feat.qos_to_hp = hp;
      k.feat.qos_to_np = np;
    end else if (bounds != "0") begin
      hp = $urandom_range(15, 2);
      np = $urandom_range(hp - 1, 1);
      k.feat.qos_to_hp = hp;
      k.feat.qos_to_np = np;
    end
    tier = '{0, 0, 0, 0};
    for (int i = 0; i < ((ntier == 3) ? 3 : 2); i++) begin
      int t = (ntier == 3) ? 3 - i : (ntier == 2) ? 3 - 2 * i : eq01 ? 1 : 2;
      tier[rps[i]] = t;
      case (t)
        3: qos_of[rps[i]] = 4'($urandom_range(15, hp));
        2: qos_of[rps[i]] = 4'($urandom_range(hp - 1, np));
        default: qos_of[rps[i]] = 4'($urandom_range((bounds == "inv" ? hp : np) - 1, 0));
      endcase
    end
    k.feat.arb_mode = arb;
    foreach (k.feat.rp_prior[r]) begin
      if (r >= int'(cfg.n_rp)) continue;
      // Idle RPs get a random priority; PRIOR 0 reads as 1 (MAS 3.2.1).
      // +qos_prior0=1 puts every tier-1 RP on PRIOR 0.
      if (tier[r] == 0) k.feat.rp_prior[r] = $urandom_range(3);
      else if (tier[r] == 1 && (prior0 != 0 || $urandom_range(1) == 1)) k.feat.rp_prior[r] = 0;
      else k.feat.rp_prior[r] = tier[r];
    end
    // eq01: two RPs, PRIOR 0 and PRIOR 1, which must share a tier.
    if (eq01) begin
      k.feat.rp_prior[rps[0]] = 0;
      k.feat.rp_prior[rps[1]] = 1;
    end
    if (arb == 2) foreach (tier[r]) if (tier[r] != 0) k.feat.rp_prior[r] = $urandom_range(3);
    if (arb != 2) foreach (qos_of[r]) qos_of[r] = 4'($urandom_range(15));
    if (timer == "sweep") timer = ($urandom_range(1) == 1) ? "promote" : "off";
    // Timer extremes (plan 13.22). TIMER_RESOLUTION 0 is taken as one cycle
    // per unit (BUGS/049 interim), so it promotes only
    // with a short threshold; THRESHOLD 0 promotes at once whatever the
    // resolution; 0xFFFF units outlast every round.
    case (timer)
      "promote": begin
        int thr[5] = '{1, 2, 4, 8, 16};
        int res[3] = '{1, 2, 4};
        k.feat.timer_threshold = thr[$urandom_range(4)];
        k.feat.timer_resolution = res[$urandom_range(2)];
      end
      "thr0": begin
        int res[3] = '{0, 1, 'hFFFF};
        k.feat.timer_threshold = 0;
        k.feat.timer_resolution = res[$urandom_range(2)];
      end
      "res0": begin
        k.feat.timer_threshold = $urandom_range(16, 1);
        k.feat.timer_resolution = 0;
      end
      "max": begin
        int res[2] = '{0, 'hFFFF};
        k.feat.timer_threshold = 'hFFFF;
        k.feat.timer_resolution = res[$urandom_range(1)];
      end
      "off": begin
        int thr[3] = '{'h400, 'h1000, 'hFFFF};
        int res[2] = '{'h400, 'hFFFF};
        k.feat.timer_threshold = thr[$urandom_range(2)];
        k.feat.timer_resolution = res[$urandom_range(1)];
      end
      default: `uvm_fatal(get_type_name(), {"bad +qos_timer=", timer})
    endcase
    if (ntier == 1) exp = aou_qos_order_chk::QOS_RR;
    else if (timer inside {"promote", "thr0", "res0"}) exp = aou_qos_order_chk::QOS_PROMOTE;
    else exp = aou_qos_order_chk::QOS_ORDER;
    `uvm_info(get_type_name(), $sformatf(
        "arb_mode=%0d tiers=%p qos=%p prior=%p hp/np=%0d/%0d timer=%0d x %0d expect %s",
              arb, tier, qos_of, k.feat.rp_prior, hp, np, k.feat.timer_threshold,
              k.feat.timer_resolution, exp.name()), UVM_LOW)
  endfunction

  task body();
    link_up();
    configure_dut();
    activate(($urandom_range(1) == 1) ? AOU_T1_BY_APB : AOU_T1_BY_BOTH, AOU_T1_ORDER_RANDOM);
    for (int unsigned r = 0; r < rounds; r++) run_round(r);
    drain();
  endtask

  task run_round(int unsigned r);
    aou_burst_seq seqs[$];
    int           order[$];
    bit           inq[bit [63:0]];
    time          t_from;
    time          t_rel;
    foreach (tier[p]) if (tier[p] != 0) order.push_back(p);
    // Lowest tier first; among equals the lowest RP first, since the checker
    // takes the last RP issued as the one that must win the round-robin turns.
    if (exp == aou_qos_order_chk::QOS_RR) order.sort();
    else order.sort() with (tier[item]);
    hold_tx();
    t_from = $time;
    foreach (order[i]) begin
      for (int d = 0; d < 2; d++) begin
        aou_burst_seq s;
        s = aou_burst_seq::type_id::create($sformatf("q%0d_rp%0d_%0d", r, order[i], d));
        s.n = n;
        s.dir = d == 0 ? AOU_AXI_RD : AOU_AXI_WR;
        s.base = chk.base + 64'(order[i]) * chk.stride + 64'(r) * 64'h10_0000 + 64'(d) * 64'h8_0000;
        s.qos = qos_of[order[i]];
        s.id = 10'(16 * d);
        seqs.push_back(s);
        fork
          automatic aou_burst_seq ss = s;
          automatic int unsigned rp = order[i];
          ss.start(p_sequencer.s_mgr_sqr[rp]);
        join_none
      end
      wait_cycles(gap);
    end
    t_rel = $time;
    release_tx();
    wait fork;
    foreach (seqs[i]) foreach (seqs[i].done_q[k])
      if (seqs[i].done_q[k].t_addr < t_rel) inq[seqs[i].done_q[k].addr] = 1'b1;
    `uvm_info(get_type_name(), $sformatf(
        "round %0d: tiers %p, %0d of %0d requests accepted before release",
                                         r, tier, inq.num(), n * 2 * order.size()), UVM_LOW)
    chk.check_round(t_from, tier, inq, exp, $sformatf("round %0d", r));
  endtask
endclass
