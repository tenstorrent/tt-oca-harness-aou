// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// RP remapping (plan 12.10, 12.11). DEST_RP is a random permutation of the
// local RPs, programmed before activation, and the remote die's map is its
// inverse (symmetric, MAS 3.10.1). Traffic both ways on every RP;
// aou_dest_rp_chk checks the RP field of every AXI message the DUT sends and
// the CrdtGrant slots, the scoreboard and remote manager that each response
// returns to its own plane. With one RP the permutation is identity.
class aou_dest_rp_test extends aou_dp_base_test;
  `uvm_component_utils(aou_dest_rp_test)

  aou_dest_rp_chk chk;
  int unsigned    perm[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) perm.push_back(r);
    perm.shuffle();
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    foreach (perm[r]) k.feat.dest_rp[r] = perm[r];
    k.lens = '{0, 1, 3};
    k.wr_pct = 50;
    k.n = 48;
  endfunction

  function void configure_test();
    foreach (perm[r]) cfg.l3_cfg.dest_rp[perm[r]] = 2'(r);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_dest_rp_chk::type_id::create("chk", this);
    chk.local_rp_count = perm.size();
    foreach (perm[r]) chk.dest_rp[r] = 2'(perm[r]);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.l3.ap_rx_msg.connect(chk.dut_fifo.analysis_export);
    env.l3.ap_tx_msg.connect(chk.tb_fifo.analysis_export);
  endfunction
endclass
