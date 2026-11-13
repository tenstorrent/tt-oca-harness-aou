// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Multi-RP traffic (plan 2.12): aou_mrp_vseq's scenarios with aou_mrp_chk's
// per-RP accounting (T1-M01, the per-RP statistics of 12.19), arbitration
// (T1-M02) and independence (T1-M03) checks. Both directions, every size up
// to each side's width, 1-16 beats. +mrp_scn=crd_rr opens round-robin credit
// windows for the env's aou_t1_crd_rr_chk (T1-C03).
// The arbitration window also reports, without judging (plan 12.19), the per-RP
// service share, the longest service gap, the longest stretch of other RPs
// served in between and the delivered bytes/cycle, plus the window aggregate:
// how the arbiter serves four equal RPs that the scenario drives concurrently
// under sustained contention. The two scenarios that pin every shape knob and
// measure it are mrp_scn-interleave.dp_wr_pct-{0,100}.dp_n-500.4x512-sp64.
class aou_mrp_test extends aou_dp_base_test;
  `uvm_component_utils(aou_mrp_test)

  aou_mrp_chk chk;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_mrp_vseq";
  endfunction

  function void set_knobs();
    k.dir = AOU_T1_BOTH_DIRS;
    k.lens = '{0, 1, 3, 7, 15};
    k.n = 40;
  endfunction

  // crd_rr runs remote-die requests only.
  function void configure_test();
    string scn;
    if ($value$plusargs("mrp_scn=%s", scn) && scn == "crd_rr") min_l2r = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_mrp_chk::type_id::create("chk", this);
    uvm_config_db#(aou_mrp_chk)::set(null, "*", "mrp_chk", chk);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (env.s_mgr[r]) env.s_mgr[r].ap.connect(chk.loc_fifo.analysis_export);
    env.rmgr.ap.connect(chk.rem_fifo.analysis_export);
    env.l3.ap_rx_msg.connect(chk.dut_fifo.analysis_export);
    chk.rp_map = env.rp_map;
  endfunction
endclass
