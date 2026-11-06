// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Traffic in both directions with the stress the model can apply: RX cancels
// of every shape, bubbles and gaps, pl_trdy holes and stand-alone stalls
// (mid-flit ones included; from 256 B up, where a flit is one beat, cancels
// cover every flit of the beat and stalls start at flit boundaries). On a 512
// or 1024 B FDI some RX beats carry fewer flits than lanes, the rest NOPs.
// Knobs: +beat_bytes=32|64|128|256|512|1024 (FDI width),
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
    env.fdi_cfg.partial_beat_pct = 20;
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
    // The traffic plans cancels on a quarter of the flits: none seen means the
    // cancel path at this width went untested.
    if (env.fdi.mon.n_rx_cancels == 0) `uvm_error(get_type_name(), "no RX flit was cancelled")
    // A fifth of the wide RX beats are sent short: none seen means the NOP
    // lanes went untested.
    if (env.fdi_cfg.fpb() > 1 && env.fdi.mon.n_rx_nops == 0)
      `uvm_error(get_type_name(), "no RX beat carried a NOP lane")
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
// that ends in LinkError. pl_phyinrecenter reports the training here.
class ucie_fdi_events_test extends ucie_fdi_smoke_test;
  `uvm_component_utils(ucie_fdi_events_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    n_flits = 600;
    env.lsm_cfg.le_mid_flit_pct = 100;
    env.lsm_cfg.recenter_en = 1'b1;
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

// Every link event and ending the model has, for its own coverage
// (ucie_fdi_fcov, ucie_lsm_fcov): the events test's traffic under Retrains
// that end in each state, LinkReset and Disabled escalated to LinkError, the
// L1 exits by both sides, a LinkError the Protocol Layer requests (and the
// test's LinkError event that then brings the link up), and
// bringups and L1 exits aborted at every point into every state. Stalls keep
// their pl_trdy policy so that some start mid-flit with pl_trdy low, and
// some drop pl_stallreq as soon as lp_stallack is seen.
class ucie_fdi_cov_test extends ucie_fdi_events_test;
  `uvm_component_utils(ucie_fdi_cov_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    n_flits = 900;
    env.fdi_cfg.stall_trdy_free = 1'b1;
    env.fdi_cfg.stall_hold_min = 0;
  endfunction

  local task cev(ucie_lsm_ev_e kind, ucie_lsm_state_e to = LSM_UNKNOWN);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(kind);
    s.ev_to = to;
    s.start(env.lsm.sqr);
  endtask

  local task abort(ucie_lsm_abort_e at, ucie_lsm_state_e to, int unsigned gap, bit in_l1 = 1'b0);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(LSM_EV_ABORT);
    s.ev_to = to;
    s.ev_at = at;
    s.ev_gap = gap;
    s.ev_in_l1 = in_l1;
    s.start(env.lsm.sqr);
    cev(LSM_EV_IDLE);
  endtask

  // Wait (bounded) until the link is Active again with no event running.
  local task wait_active();
    int unsigned n;
    do begin
      @(env.pl.lsm.mon_cb);
      n++;
    end while (!(env.lsm.drv.state == LSM_ACTIVE && env.lsm.drv.link_active) && n < 50000);
    if (n == 50000) `uvm_error(get_type_name(), "the link did not come back to Active")
  endtask

  task events();
    ucie_lsm_l1_seq l1 = ucie_lsm_l1_seq::type_id::create("l1");
    int unsigned n_react = env.lsm.drv.n_le_react;
    cev(LSM_EV_IDLE);
    cev(LSM_EV_RETRAIN);
    cev(LSM_EV_RETRAIN, LSM_LINKERROR);
    cev(LSM_EV_RETRAIN, LSM_LINKRESET);
    cev(LSM_EV_RETRAIN, LSM_DISABLED);
    cev(LSM_EV_LINKERROR);
    cev(LSM_EV_LINK_RESET, LSM_LINKERROR);
    cev(LSM_EV_DISABLED, LSM_LINKERROR);
    cev(LSM_EV_CLK_WAKE);
    l1.start(env.lsm.sqr);
    // An L1 exit the Protocol Layer starts.
    cev(LSM_EV_L1_ENTRY);
    env.pl.wake_in_l1 = 1'b1;
    wait_active();
    env.pl.wake_in_l1 = 1'b0;
    // A LinkError the Protocol Layer requests.
    env.pl.linkerror_req = 1'b1;
    repeat (20000) begin
      @(env.pl.lsm.mon_cb);
      if (env.lsm.drv.n_le_react != n_react) break;
    end
    if (env.lsm.drv.n_le_react == n_react)
      `uvm_error(get_type_name(), "the Adapter did not answer lp_linkerror")
    // The test's own answer to the request: the Adapter, already down, only
    // brings the link up again (ucie_lsm_driver react_loop).
    cev(LSM_EV_LINKERROR);
    wait_active();
    // Bringups and L1 exits abandoned part-way.
    abort(LSM_AB_RESET, LSM_LINKERROR, 2);
    abort(LSM_AB_RESET, LSM_LINKRESET, 2);
    abort(LSM_AB_WAKE, LSM_DISABLED, 3);
    abort(LSM_AB_WAKE, LSM_RESET, 2);
    abort(LSM_AB_REQ_ACTIVE, LSM_LINKERROR, 1);
    abort(LSM_AB_REQ_ACTIVE, LSM_RESET, 1);
    abort(LSM_AB_WAKE, LSM_LINKERROR, 0, 1'b1);
    abort(LSM_AB_WAKE, LSM_LINKRESET, 2, 1'b1);
    abort(LSM_AB_WAKE, LSM_DISABLED, 2, 1'b1);
  endtask
endclass

// Demotes the errors of one rule to infos and counts them (ucie_fdi_neg_test).
class ucie_fdi_expect_catcher extends uvm_report_catcher;
  string       rule;
  int unsigned n;

  function new(string name = "ucie_fdi_expect_catcher");
    super.new(name);
  endfunction

  function action_e catch();
    string m = get_message();
    if (get_severity() == UVM_ERROR && rule != "" && m.substr(0, rule.len() - 1) == rule) begin
      n++;
      set_severity(UVM_INFO);
    end
    return THROW;
  endfunction
endclass

// Negative test of the model's checks: the stub makes one deliberate violation
// (+neg=dllp|retimer|stream, see ucie_pl_stub::bad), and the rule that must
// catch it has to fire; its errors are expected and demoted. Any other error
// still fails the run.
class ucie_fdi_neg_test extends ucie_fdi_smoke_test;
  `uvm_component_utils(ucie_fdi_neg_test)

  ucie_fdi_expect_catcher catcher;
  string                  neg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    n_flits = 60;
    if (!$value$plusargs("neg=%s", neg)) neg = "stream";
    catcher = new("catcher");
    case (neg)
      "dllp":    catcher.rule = "FDI-R62";
      "retimer": catcher.rule = "FDI-R63";
      "stream":  catcher.rule = "FDI-R64";
      default:   `uvm_fatal(get_type_name(), {"+neg: unknown violation ", neg})
    endcase
    uvm_report_cb::add(null, catcher);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.bad = neg;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (catcher.n == 0)
      `uvm_error(get_type_name(), $sformatf("%s: the stub's %s violation was not caught",
                                            catcher.rule, neg))
    else
      `uvm_info(get_type_name(), $sformatf("%s caught the stub's %s violation (%0d reports)",
                                           catcher.rule, neg, catcher.n), UVM_NONE)
  endfunction
endclass
