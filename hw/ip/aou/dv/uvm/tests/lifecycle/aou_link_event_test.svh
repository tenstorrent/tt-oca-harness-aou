// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// FDI link events mid-traffic: Retrain, clk_req, L1, LinkError, LinkReset,
// inband_pres (aou_link_event_vseq).
class aou_link_event_test extends aou_base_test;
  `uvm_component_utils(aou_link_event_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_link_event_vseq";
    num_txns = 20;
  endfunction

  // Disabled has only the UCIe encoding (UCIe r1.1 Table 8-2); the teardown
  // and its training trigger are checked with it too.
  function void configure();
    string ev;
    if ($value$plusargs("event=%s", ev) && ev inside {"disabled", "teardown_int"})
      cfg.fdi_enc = AOU_FDI_ENC_SPEC;
  endfunction

  // A hang shows within 2 ms of simulated time; every scenario here,
  // the 2^18-cycle time-outs included, ends well before.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(2ms, 1);
  endfunction
endclass
