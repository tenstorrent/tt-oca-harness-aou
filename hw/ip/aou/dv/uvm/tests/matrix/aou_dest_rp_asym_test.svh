// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// [NEG] Asymmetric DEST_RP between the dies (plan 12.13). The DUT maps RP0 to
// remote plane 1 and RP1 to plane 0; the remote die keeps the identity map,
// so it answers a request from the DUT's RP0 on plane 1. MAS 3.10.1 requires
// symmetry and says nothing of the result (BUGS/031). Interim expectation:
// the DUT tags its requests with its own DEST_RP (FEAT-R09); RP0's reads and
// writes never complete at the S port (T1-M04); and no response reaches an S
// port with no request outstanding on that ID (AXI4 A5.3: RP1 would report
// AXI-R07/R08). After the wait the test abandons the stuck transactions.
class aou_dest_rp_asym_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_dest_rp_asym_vseq)

  function new(string name = "aou_dest_rp_asym_vseq");
    super.new(name);
  endfunction

  task body();
    aou_t1_traffic_cfg p = make_profile();
    int unsigned done0;
    link_up();
    configure_dut();
    activate(AOU_T1_BY_APB, AOU_T1_ORDER_RANDOM);
    p.rp_mask = 4'b0001;
    done0 = env.sb.n_l2r_wr + env.sb.n_l2r_rd;
    traffic_nb(AOU_T1_L2R, num_txns, p);
    wait_cycles(5000);
    if (env.sb.n_l2r_wr + env.sb.n_l2r_rd != done0)
      `uvm_error(get_type_name(), $sformatf(
                 "T1-M04: %0d RP0 transactions completed though the remote die answers on plane 1",
                 env.sb.n_l2r_wr + env.sb.n_l2r_rd - done0))
    stop_traffic();
    wait_traffic();
  endtask
endclass

class aou_dest_rp_asym_test extends aou_dest_rp_test;
  `uvm_component_utils(aou_dest_rp_asym_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_dest_rp_asym_vseq";
    min_l2r = 0;
    min_r2l = 0;
  endfunction

  function void set_knobs();
    super.set_knobs();
    if (AOU_T1_RP_COUNT < 2) `uvm_fatal(get_type_name(), "needs a build with 2 or more RPs")
    perm.delete();
    for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) perm.push_back(r);
    perm[0] = 1;
    perm[1] = 0;
    foreach (perm[r]) k.feat.dest_rp[r] = perm[r];
    k.n = 8;
  endfunction

  function void configure_test();
    for (int unsigned r = 0; r < 4; r++) cfg.l3_cfg.dest_rp[r] = 2'(r);
  endfunction
endclass
