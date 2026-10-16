// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

class aou_lsm_cfg extends uvm_object;
  `uvm_object_utils(aou_lsm_cfg)

  aou_fdi_enc_e fdi_enc = AOU_FDI_ENC_RTL;
  int unsigned  n_phy = 1;
  int unsigned  active_phy = 0;          // drives I_PHY_TYPE
  // Two-PHY builds: the PHY I_PHY_TYPE does not select stays in Reset with its
  // mainband closed and no stalls, instead of mirroring the active PHY's state,
  // so the DUT must take state and stalls from the selected PHY (+park_idle_phy).
  bit           park_idle_phy = 1'b0;
  bit           is_active = 1'b1;

  // Adapter response latencies in cycles (each draw uniform in [min:max]).
  // UCIe needs at least one cycle between a request and its acknowledge.
  int unsigned  lat_min = 1;
  int unsigned  lat_max = 6;
  int unsigned  dwell_min = 8;           // time spent in Retrain, L1, LinkError, ...
  int unsigned  dwell_max = 40;

  bit           auto_bringup = 1'b1;     // bring the link up after every reset
  bit           clk_req_hold_bringup = 1'b1; // keep pl_clk_req until the state leaves Reset
  bit           rebringup_after_down = 1'b1; // LinkError/LinkReset events end with a bringup
  int unsigned  req_timeout = 20000;     // cycles to wait for a DUT request; 0 waits forever
  bit           react_en = 1'b1;         // fdi_enc=SPEC: answer the DUT's LinkReset/Disabled
                                         // requests between events
  bit           react_linkerror_en = 1'b1; // ... and its lp_linkerror
  // fdi_enc=SPEC: after LinkError/LinkReset/Disabled the Adapter trains again
  // only on a NOP->Active request (FDI-R51); after train_timeout cycles
  // software starts the training instead.
  bit           train_trigger_en = 1'b1;
  int unsigned  train_timeout = 2000;
  // Chance an Adapter-initiated LinkError is entered mid-flit: without the flit
  // boundary, while a flit is in flight in either direction (UCIe r1.1
  // 8.3.3.7 needs neither a stall nor a boundary). +le_mid_flit_pct.
  int unsigned  le_mid_flit_pct = 0;

  // Monitor and reference model
  bit           checks_en = 1'b1;
  bit           model_en = 1'b1;
  bit           cov_en = 1'b1;
  int unsigned  ref_slack = 3;           // cycles a DUT output may lag the model
  // The DUT drives lp_linkerror; without it the top ties it low (BUGS/002).
`ifdef AOU_DUT_LP_LINKERROR
  bit           dut_lp_linkerror = 1'b1;
`else
  bit           dut_lp_linkerror = 1'b0;
`endif

  // L1 handles of each PHY, set by the environment.
  aou_fdi_gate         gate[$];
  aou_fdi_tx_responder rsp[$];

  function new(string name = "aou_lsm_cfg");
    super.new(name);
  endfunction

  function int unsigned lat();
    return $urandom_range(lat_max, lat_min < 1 ? 1 : lat_min);
  endfunction

  function int unsigned dwell();
    return $urandom_range(dwell_max, dwell_min);
  endfunction

  function string convert2string();
    return $sformatf({"fdi_enc=%s n_phy=%0d active_phy=%0d lat=[%0d:%0d] auto_bringup=%0b ",
                      "clk_hold=%0b"},
                     fdi_enc.name(), n_phy, active_phy, lat_min, lat_max, auto_bringup,
                     clk_req_hold_bringup);
  endfunction
endclass
