// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Traffic in both directions with the stress the model can apply: RX cancels
// of every shape, bubbles and gaps, pl_trdy holes and stand-alone stalls
// (mid-flit ones included). Knobs: +beat_bytes=32|64|128 (FDI width),
// +n_flits=N, +trdy=always|random|bursty|holes.
class ucie_fdi_smoke_test extends uvm_test;
  `uvm_component_utils(ucie_fdi_smoke_test)

  ucie_fdi_selftest_env env;
  int unsigned          n_flits = 300;
  int unsigned          drain_timeout = 200000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string trdy;
    super.build_phase(phase);
    env = ucie_fdi_selftest_env::type_id::create("env", this);
    void'($value$plusargs("beat_bytes=%d", env.fdi_cfg.beat_bytes));
    void'($value$plusargs("n_flits=%d", n_flits));
    env.fdi_cfg.trdy_policy = UCIE_TRDY_HOLES;
    if ($value$plusargs("trdy=%s", trdy))
      case (trdy)
        "always": env.fdi_cfg.trdy_policy = UCIE_TRDY_ALWAYS;
        "random": env.fdi_cfg.trdy_policy = UCIE_TRDY_RANDOM;
        "bursty": env.fdi_cfg.trdy_policy = UCIE_TRDY_BURSTY;
        "holes":  env.fdi_cfg.trdy_policy = UCIE_TRDY_HOLES;
        default:  `uvm_fatal(get_type_name(), {"+trdy: unknown policy ", trdy})
      endcase
    env.fdi_cfg.stall_pct = 3;
    env.fdi_cfg.stall_mid_pct = 30;
    env.fdi_cfg.random_adapter_bytes = 1'b1;
    configure();
  endfunction

  // Test-specific settings, before the agents are built.
  virtual function void configure();
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    fork
      traffic();
      events();
    join
    drain();
    phase.drop_objection(this);
  endtask

  task traffic();
    ucie_flit_seq seq = ucie_flit_seq::type_id::create("flits");
    for (int unsigned i = 0; i < n_flits; i++) begin
      ucie_flit_item f = ucie_flit_item::type_id::create("payload");
      f.randomize_payload();
      seq.payloads.push_back(f);
      env.sb.expect_rx(f);
    end
    seq.n_flits = 0;
    seq.cancel_pct = 25;
    seq.cancel_mix = 1'b1;
    seq.gap_pct = 30;
    seq.bubble_pct = 10;
    seq.start(env.fdi.sqr);
  endtask

  // Link events alongside the traffic; none here.
  virtual task events();
  endtask

  task drain();
    int unsigned n;
    while (!(env.sb.rx_exp.size() == 0 && env.sb.lb_exp.size() == 0 && env.pl.idle()) &&
           n < drain_timeout) begin
      @(env.pl.lsm.mon_cb);
      n++;
    end
    repeat (100) @(env.pl.lsm.mon_cb);
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.sb.n_tx == 0) `uvm_error(get_type_name(), "no flit looped back")
  endfunction

  // The model's rule ledger: how often each rule was evaluated and violated.
  function void report_phase(uvm_phase phase);
    string q[$];
    super.report_phase(phase);
    ucie_rule_log::lines(q);
    foreach (q[i]) `uvm_info(get_type_name(), q[i], UVM_NONE)
  endfunction
endclass

// The smoke test's traffic under the Adapter's link events: Retrain, an L1
// entry and remote exit, a clock-request wake, LinkError (entered mid-flit),
// LinkReset and Disabled, each followed by the bringup again, and a Retrain
// that ends in LinkError.
class ucie_fdi_events_test extends ucie_fdi_smoke_test;
  `uvm_component_utils(ucie_fdi_events_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    n_flits = 600;
    env.lsm_cfg.le_mid_flit_pct = 100;
  endfunction

  local task ev(ucie_lsm_ev_e kind, ucie_lsm_state_e to = LSM_UNKNOWN);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::type_id::create("ev");
    s.ev_kind = kind;
    s.ev_to = to;
    s.start(env.lsm.sqr);
  endtask

  task events();
    ucie_lsm_l1_seq l1 = ucie_lsm_l1_seq::type_id::create("l1");
    ev(LSM_EV_IDLE);
    ev(LSM_EV_RETRAIN);
    ev(LSM_EV_IDLE);
    l1.start(env.lsm.sqr);
    ev(LSM_EV_CLK_WAKE);
    ev(LSM_EV_IDLE);
    ev(LSM_EV_LINKERROR);
    ev(LSM_EV_IDLE);
    ev(LSM_EV_LINK_RESET);
    ev(LSM_EV_IDLE);
    ev(LSM_EV_DISABLED);
    ev(LSM_EV_IDLE);
    ev(LSM_EV_RETRAIN, LSM_LINKERROR);
  endtask
endclass
