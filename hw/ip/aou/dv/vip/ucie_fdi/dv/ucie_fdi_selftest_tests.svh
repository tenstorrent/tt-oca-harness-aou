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

  protected task cev(ucie_lsm_ev_e kind, ucie_lsm_state_e to = LSM_UNKNOWN);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(kind);
    s.ev_to = to;
    s.start(env.lsm.sqr);
  endtask

  protected task abort(ucie_lsm_abort_e at, ucie_lsm_state_e to, int unsigned gap,
                       bit in_l1 = 1'b0);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(LSM_EV_ABORT);
    s.ev_to = to;
    s.ev_at = at;
    s.ev_gap = gap;
    s.ev_in_l1 = in_l1;
    s.start(env.lsm.sqr);
    cev(LSM_EV_IDLE);
  endtask

  // Wait (bounded) until the link is Active again with no event running.
  protected task wait_active();
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
    // brings the link up again (ucie_lsm_driver answer_linkerror).
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

// The smoke test's traffic with errors both ways, on a link whose protocol
// includes CXL.cachemem (CXL.2, stream 03h): the Adapter flags framing errors
// on pl_error, then cancels the half and retrains before the replay, and the
// stub asks for corrupted CRCs on lp_corrupt_crc.
class ucie_fdi_error_test extends ucie_fdi_smoke_test;
  `uvm_component_utils(ucie_fdi_error_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    env.fdi_cfg.error_pct = 10;
    env.fdi_cfg.stream = 8'h03;
    env.lsm_cfg.protocol = UCIE_PROTO_CXL2;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.corrupt_pct = 20;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.fdi.mon.n_rx_errors == 0) `uvm_error(get_type_name(), "no pl_error was sent")
    if (env.fdi.mon.n_tx_corrupt == 0) `uvm_error(get_type_name(), "no lp_corrupt_crc was seen")
  endfunction
endclass

// The pl_clk_req handshake on every exit from a state where the Protocol
// Layer may be clock gated (UCIe r3.0 §10.2.3.2 rules 5 to 7), with a stub
// that gates its clock whenever it may and acknowledges pl_clk_req only
// `+clk_ack_delay=N` clocks later (default 3; ucie_pl_stub clk_gate): the
// cov test's events and traffic, before them LinkReset, Disabled and
// LinkError from Active, from Reset and from L1, ending in Reset and in a
// bringup; LinkReset and Disabled escalated to LinkError from Reset; both
// L1 exits; two pl_inband_pres drops in Reset (one while the stub requests
// Active); and aborts at the points the cov test leaves out (a pl_inband_pres
// drop sent with its pl_clk_req, LinkReset or Disabled the cycle the
// Protocol Layer requests Active, a LinkError reported before its pl_clk_req).
// +clk_hold=0|1 sets clk_req_hold_bringup (default 1). The model's self-checks
// (FDI-R20, R21, R22) and the stub's must stay silent; the stub must have
// been gated at all.
class ucie_fdi_clk_req_test extends ucie_fdi_cov_test;
  `uvm_component_utils(ucie_fdi_clk_req_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    bit hold = 1'b1;
    super.configure();
    void'($value$plusargs("clk_hold=%b", hold));
    env.lsm_cfg.clk_req_hold_bringup = hold;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.clk_gate = 1'b1;
    env.pl.clk_ack_delay = 3;
    void'($value$plusargs("clk_ack_delay=%d", env.pl.clk_ack_delay));
    `uvm_info(get_type_name(), $sformatf("clk_req_hold_bringup %0b, lp_clk_ack delay %0d",
              env.lsm_cfg.clk_req_hold_bringup, env.pl.clk_ack_delay), UVM_NONE)
  endfunction

  // A link-down that leaves the link in Reset (no bringup after it).
  local task down(ucie_lsm_ev_e kind, ucie_lsm_state_e to = LSM_UNKNOWN);
    env.lsm_cfg.rebringup_after_down = 1'b0;
    cev(kind, to);
    env.lsm_cfg.rebringup_after_down = 1'b1;
  endtask

  task events();
    // From Active, then from Reset, the link left down.
    down(LSM_EV_LINK_RESET);
    down(LSM_EV_DISABLED);
    down(LSM_EV_LINK_RESET);
    down(LSM_EV_LINKERROR);
    // pl_inband_pres in Reset: low already, so it rises at the end; then a
    // true drop while the stub requests Active.
    cev(LSM_EV_INBAND_DROP);
    cev(LSM_EV_INBAND_DROP);
    down(LSM_EV_LINK_RESET, LSM_LINKERROR);
    down(LSM_EV_DISABLED, LSM_LINKERROR);
    cev(LSM_EV_DISABLED);
    // From L1, each ending in a bringup, and one left down.
    cev(LSM_EV_L1_ENTRY);
    cev(LSM_EV_LINK_RESET);
    cev(LSM_EV_L1_ENTRY);
    cev(LSM_EV_DISABLED);
    cev(LSM_EV_L1_ENTRY);
    cev(LSM_EV_LINKERROR);
    cev(LSM_EV_L1_ENTRY);
    down(LSM_EV_LINK_RESET);
    cev(LSM_EV_BRINGUP);
    // Both L1 exits.
    cev(LSM_EV_L1_ENTRY);
    cev(LSM_EV_L1_EXIT);
    cev(LSM_EV_L1_ENTRY);
    env.pl.wake_in_l1 = 1'b1;
    wait_active();
    env.pl.wake_in_l1 = 1'b0;
    // Aborts the cov test leaves out.
    abort(LSM_AB_WAKE, LSM_RESET, 0);
    abort(LSM_AB_REQ_ACTIVE, LSM_LINKRESET, 0);
    abort(LSM_AB_REQ_ACTIVE, LSM_DISABLED, 0);
    abort(LSM_AB_RESET, LSM_LINKERROR, 0);
    abort(LSM_AB_WAKE, LSM_LINKERROR, 0);
    abort(LSM_AB_WAKE, LSM_LINKRESET, 1);
    super.events();
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.pl.n_gated == 0) `uvm_error(get_type_name(), "the stub never gated its clock")
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("clocks the stub was clock gated: %0d", env.pl.n_gated),
              UVM_NONE)
  endfunction
endclass

// The exit from Reset (UCIe r3.0 §10.3.3.1 rule 1, §10.3.3.8) and the
// rx_active handshake ahead of the request (§10.2.7 rule 1), on the cov test's
// events and traffic, with +reset_req=:
//  held      the stub requests Active in LinkError, LinkReset and Disabled and
//            holds it into Reset for 40 clocks of pl_inband_pres, with a clock
//            of LinkReset halfway; the Adapter must wait for its NOP, then
//            Active (the stub reports otherwise);
//  early     the stub gives NOP->Active in Reset before pl_inband_pres, and
//            returns to NOP or holds Active; nothing may hang, and after a
//            trigger withdrawn to NOP the Adapter must wait for the next
//            NOP->Active (the stub reports otherwise);
//  restart   the same, with the training-trigger policy (restart_on PL) and
//            software's delay at 20000 clocks: after every link-down
//            pl_inband_pres must follow the trigger within 300 clocks, and a
//            link left down (rebringup_after_down 0) must come up on it;
//  either    restart_on EITHER, the trigger in half the Resets;
//  rx_first  remote_active_first_pct 100: the Adapter starts the rx_active
//            handshake before the request, in Reset and in Retrain (both
//            must happen).
// +clk_hold=0|1 sets clk_req_hold_bringup (default 1). Any error fails it.
class ucie_fdi_reset_req_test extends ucie_fdi_cov_test;
  `uvm_component_utils(ucie_fdi_reset_req_test)

  string mode = "held";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    bit hold = 1'b1;
    super.configure();
    void'($value$plusargs("reset_req=%s", mode));
    void'($value$plusargs("clk_hold=%b", hold));
    env.lsm_cfg.clk_req_hold_bringup = hold;
    case (mode)
      "held", "early": ;
      "restart": env.lsm_cfg.restart_on = LSM_RESTART_PL;
      "either":  env.lsm_cfg.restart_on = LSM_RESTART_EITHER;
      "rx_first": env.lsm_cfg.remote_active_first_pct = 100;
      default: `uvm_fatal(get_type_name(), {"+reset_req: unknown mode ", mode})
    endcase
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.held_active = mode == "held";
    env.pl.early_trigger = mode inside {"early", "restart", "either"};
    env.pl.remote_first = env.lsm_cfg.remote_active_first_pct != 0;
    if (mode == "either") env.pl.early_pct = 50;
    if (mode == "restart") begin
      env.lsm_cfg.sw_restart_delay = 20000;
      env.pl.restart_bound = 300;
    end
    `uvm_info(get_type_name(), $sformatf("reset_req %s: %s", mode, env.lsm_cfg.convert2string()),
              UVM_NONE)
  endfunction

  task events();
    if (mode == "restart") begin
      // A link left down: only the stub's trigger brings it up.
      env.lsm_cfg.rebringup_after_down = 1'b0;
      cev(LSM_EV_LINK_RESET);
      env.lsm_cfg.rebringup_after_down = 1'b1;
      wait_active();
    end
    super.events();
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    case (mode)
      "held": begin
        if (env.pl.n_held == 0) `uvm_error(get_type_name(), "no Active was held into Reset")
        if (env.pl.n_other == 0)
          `uvm_error(get_type_name(), "no Active followed another request in Reset")
      end
      "early": begin
        if (env.pl.n_early == 0) `uvm_error(get_type_name(), "no early NOP->Active was given")
        if (env.pl.n_early_waits == 0)
          `uvm_error(get_type_name(), "no withdrawn early trigger was checked")
      end
      "either":
        if (env.pl.n_early == 0) `uvm_error(get_type_name(), "no early NOP->Active was given")
      "restart":
        if (env.pl.n_restarts == 0)
          `uvm_error(get_type_name(), "no training restarted on the stub's NOP->Active")
      "rx_first": begin
        if (env.pl.n_rx_first == 0)
          `uvm_error(get_type_name(), "pl_rx_active_req never rose in Reset before the request")
        if (env.pl.n_rx_first_rt == 0)
          `uvm_error(get_type_name(), "pl_rx_active_req never rose in Retrain before the request")
      end
      default: ;
    endcase
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({"held Active requests %0d (LinkReset then Active %0d), ",
              "early triggers %0d (withdrawn and checked %0d), restarts on them %0d, ",
              "rx_active handshakes before the request %0d in Reset, %0d in Retrain"},
              env.pl.n_held, env.pl.n_other, env.pl.n_early, env.pl.n_early_waits,
              env.pl.n_restarts, env.pl.n_rx_first, env.pl.n_rx_first_rt), UVM_NONE)
  endfunction
endclass

// The Protocol Layer's requests the Adapter answers (UCIe r3.0 Table 10-4,
// §10.3.3), before the cov test's events and with its traffic:
//  - LinkReset and Disabled requested in Active, in Retrain (an Adapter
//    Retrain, abandoned), in L1, and in Reset after a NOP, both with the link
//    left down (before pl_inband_pres) and during a bringup (after it, which
//    abandons the bringup); Disabled requested in LinkReset;
//  - requests Table 10-4 ignores: LinkReset in Disabled, LinkReset and
//    Disabled in LinkError (held there by lp_linkerror);
//  - lp_linkerror raised in Reset (link left down, and during a bringup), in
//    Active (between events, and during an idle event, abandoned), in
//    Retrain (held 2000 clocks into LinkError), in L1, in LinkReset and in
//    Disabled (Adapter events, abandoned), and as an L1 entry starts (taken
//    once the entry's stall is done);
//  - requests that stop a job while its pl_clk_req waits for a slow
//    lp_clk_ack (+slow_ack=N clocks, default 50, for these cases only):
//    LinkReset and Disabled in L1 as the Adapter's own L1 exit raises it,
//    lp_linkerror in Reset as a bringup raises it, and lp_linkerror in Reset
//    as the answer to a LinkReset request raises it (one answer stopping
//    another). The status may leave the gated state before the acknowledge
//    (r3.0 §10.2.3.2 rules 6 and 7 only need pl_clk_req up first), but
//    pl_clk_req must stay up until it (rules 3 and 5; the stub and FDI-R20
//    check that). With slow_ack longer than the slowest answer (lat_max +
//    remote_rsp_max + 10) every one of the four must leave the gated state
//    before the acknowledge, so the stop really comes mid-handshake.
// The stub reports a request not answered within its bound, an ignored one
// answered, and with +state_req=exit_pl an exit from LinkReset, Disabled or
// LinkError it did not ask for (ucie_pl_stub). +state_req= picks the
// Adapter's options:
//  basic       requests answered at once, exits on the Adapter's internal request;
//  gated       the stub gates its clock whenever it may (as in the clk_req test)
//              and wakes itself with lp_wake_req for its own requests in Reset,
//              LinkReset, Disabled and L1; the remote die answers up to 30 clocks
//              late (remote_rsp_max);
//  exit_pl     LinkReset, Disabled and LinkError left only on the stub's Active
//              request (down_exit_on PL), LinkError after 200 clocks at least;
//  exit_either either exit, whichever comes first;
//  via_active  a LinkReset or Disabled answered in Retrain or in Reset after
//              pl_inband_pres goes through Active first.
// +clk_hold=0|1 sets clk_req_hold_bringup (default 1). Any error fails it.
class ucie_fdi_state_req_test extends ucie_fdi_cov_test;
  `uvm_component_utils(ucie_fdi_state_req_test)

  string       mode = "basic";
  int unsigned n_plan;  // "Yes" requests the test planned
  int unsigned slow_ack = 50;  // lp_clk_ack delay for the mid-handshake cases
  int unsigned n_mid;   // ... gated states left before lp_clk_ack answered

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    bit hold = 1'b1;
    super.configure();
    void'($value$plusargs("state_req=%s", mode));
    void'($value$plusargs("clk_hold=%b", hold));
    void'($value$plusargs("slow_ack=%d", slow_ack));
    env.lsm_cfg.clk_req_hold_bringup = hold;
    case (mode)
      "basic", "gated": ;
      "exit_pl":     env.lsm_cfg.down_exit_on = LSM_EXIT_PL;
      "exit_either": env.lsm_cfg.down_exit_on = LSM_EXIT_EITHER;
      "via_active":  env.lsm_cfg.linkdown_via_active_pct = 100;
      default: `uvm_fatal(get_type_name(), {"+state_req: unknown mode ", mode})
    endcase
    if (mode == "gated") env.lsm_cfg.remote_rsp_max = 30;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.clk_gate = mode == "gated";
    if (mode == "gated") env.pl.clk_ack_delay = 3;
    env.pl.held_active = mode inside {"exit_pl", "exit_either"};
    env.pl.exit_pl = mode == "exit_pl";
    env.pl.le_min_res = env.lsm_cfg.linkerror_min_res;
    `uvm_info(get_type_name(), $sformatf("state_req %s: %s", mode, env.lsm_cfg.convert2string()),
              UVM_NONE)
  endfunction

  // Wait (bounded) until nothing is under way, then bring a link left down
  // back up: an Adapter LinkError event, which after a LinkError on
  // lp_linkerror only runs the bringup.
  local task settle();
    int unsigned n;
    while (!env.lsm.drv.idle() && n++ < 50000) @(env.pl.lsm.mon_cb);
    repeat (5) @(env.pl.lsm.mon_cb);
    if (env.lsm.drv.state != LSM_ACTIVE && env.lsm.drv.idle()) cev(LSM_EV_LINKERROR);
    wait_active();
  endtask

  local task ask(ucie_lsm_state_e in, ucie_lsm_req_e r, int up = -1, bit ignore = 1'b0);
    ucie_pl_stub::plan_t p;
    p.in = in;
    p.req = r;
    p.up = up;
    p.ignore = ignore;
    env.pl.plan.push_back(p);
    if (!ignore) n_plan++;
  endtask

  // Wait (bounded) until the stub has made every planned request.
  local task plan_done();
    int unsigned n;
    while (env.pl.plan.size() != 0 && n++ < 100000) @(env.pl.lsm.mon_cb);
    if (env.pl.plan.size() != 0)
      `uvm_error(get_type_name(), $sformatf("%0d planned requests never made", env.pl.plan.size()))
  endtask

  // lp_linkerror in `in`; waits (bounded) for the answer.
  local task le_req(ucie_lsm_state_e in, int up = -1);
    int unsigned n;
    int unsigned n0 = env.pl.n_le_answered;
    env.pl.linkerror_in = in;
    env.pl.linkerror_up = up;
    env.pl.linkerror_req = 1'b1;
    while (env.pl.n_le_answered == n0 && n++ < 100000) @(env.pl.lsm.mon_cb);
    if (env.pl.n_le_answered == n0)
      `uvm_error(get_type_name(), {"lp_linkerror in ", in.name(), " was never raised"})
    env.pl.linkerror_req = 1'b0;
    env.pl.linkerror_in = LSM_ACTIVE;
    env.pl.linkerror_up = -1;
  endtask

  // A link-down that leaves the link in Reset (no bringup after it).
  local task down(ucie_lsm_ev_e kind);
    env.lsm_cfg.rebringup_after_down = 1'b0;
    cev(kind);
    env.lsm_cfg.rebringup_after_down = 1'b1;
  endtask

  // An Adapter event of `cycles` running while `body` does its part.
  local task long_event(ucie_lsm_ev_e kind, int unsigned cycles);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(kind);
    s.ev_cycles = cycles;
    s.start(env.lsm.sqr);
  endtask

  // Count, while `mid_on`, status changes out of a gated state made while
  // pl_clk_req is up and lp_clk_ack has not yet answered it.
  local bit mid_on;
  local task count_mid();
    bit acked;
    ucie_lsm_state_e s = env.lsm.drv.state;
    while (mid_on) begin
      @(env.pl.lsm.mon_cb);
      if (env.pl.lsm.mon_cb.pl_clk_req !== 1'b1) acked = 1'b0;
      else if (env.pl.lsm.mon_cb.lp_clk_ack === 1'b1) acked = 1'b1;
      if (env.lsm.drv.state != s && lsm_gated(s) && env.pl.lsm.mon_cb.pl_clk_req === 1'b1 &&
          !acked) begin
        n_mid++;
        `uvm_info(get_type_name(), $sformatf("%s -> %s before lp_clk_ack answered pl_clk_req",
                  s.name(), env.lsm.drv.state.name()), UVM_LOW)
      end
      s = env.lsm.drv.state;
    end
  endtask

  // Wait (bounded) for pl_clk_req to rise.
  local task wait_clk_req();
    int unsigned n;
    while (env.pl.lsm.mon_cb.pl_clk_req !== 1'b1 && n++ < 50000) @(env.pl.lsm.mon_cb);
  endtask

  // Requests that stop a job mid-handshake (see the header).
  local task mid_raise();
    int unsigned ack0 = env.pl.clk_ack_delay;
    int unsigned n;
    env.pl.clk_ack_delay = slow_ack;
    mid_on = 1'b1;
    fork
      count_mid();
    join_none
    // LinkReset and Disabled in L1 as the Adapter's L1 exit raises pl_clk_req.
    for (int i = 0; i < 2; i++) begin
      cev(LSM_EV_L1_ENTRY);
      fork
        cev(LSM_EV_L1_EXIT);
        begin
          wait_clk_req();
          ask(LSM_L1, i == 0 ? LSM_REQ_LINKRESET : LSM_REQ_DISABLED);
        end
      join
      // With a quick acknowledge the exit may leave L1 before the stub
      // could ask; a request made in L1 is answered before the link is up.
      n = 0;
      while (!env.lsm.drv.idle() && n++ < 50000) @(env.pl.lsm.mon_cb);
      if (env.lsm.drv.state == LSM_ACTIVE && env.pl.plan.size() != 0) begin
        `uvm_info(get_type_name(), "the L1 exit was done before the stub could ask", UVM_LOW)
        void'(env.pl.plan.pop_front());
        n_plan--;
      end
      plan_done();
      settle();
    end
    // lp_linkerror in Reset as a bringup raises pl_clk_req.
    down(LSM_EV_LINK_RESET);
    fork
      cev(LSM_EV_BRINGUP);
      begin
        wait_clk_req();
        le_req(LSM_RESET);
      end
    join
    settle();
    // lp_linkerror in Reset as the answer to a LinkReset request raises it.
    down(LSM_EV_LINK_RESET);
    ask(LSM_RESET, LSM_REQ_LINKRESET, 0);
    wait_clk_req();
    le_req(LSM_RESET);
    plan_done();
    settle();
    mid_on = 1'b0;
    env.pl.clk_ack_delay = ack0;
  endtask

  task events();
    // Dwells long enough for the stub's requests in LinkReset, Disabled and
    // LinkError, even after waking from clock gating; the cov test's events
    // after these run with the usual ones.
    env.lsm_cfg.dwell_min = 60;
    env.lsm_cfg.dwell_max = 100;
    // LinkReset and Disabled from Active.
    ask(LSM_ACTIVE, LSM_REQ_LINKRESET);
    plan_done();
    settle();
    ask(LSM_ACTIVE, LSM_REQ_DISABLED);
    plan_done();
    settle();
    // From Retrain: an Adapter Retrain, long enough for the request.
    for (int i = 0; i < 2; i++) begin
      ask(LSM_RETRAIN, i == 0 ? LSM_REQ_LINKRESET : LSM_REQ_DISABLED);
      fork
        long_event(LSM_EV_RETRAIN, 400);
        plan_done();
      join
      settle();
    end
    // From L1.
    for (int i = 0; i < 2; i++) begin
      cev(LSM_EV_L1_ENTRY);
      ask(LSM_L1, i == 0 ? LSM_REQ_LINKRESET : LSM_REQ_DISABLED);
      plan_done();
      settle();
    end
    // From Reset after a NOP: the link left down, then during a bringup.
    for (int i = 0; i < 2; i++) begin
      down(LSM_EV_LINK_RESET);
      ask(LSM_RESET, i == 0 ? LSM_REQ_LINKRESET : LSM_REQ_DISABLED, 0);
      plan_done();
      settle();
      ask(LSM_RESET, i == 0 ? LSM_REQ_LINKRESET : LSM_REQ_DISABLED, 1);
      cev(LSM_EV_LINK_RESET);
      plan_done();
      settle();
    end
    // Disabled from LinkReset.
    ask(LSM_ACTIVE, LSM_REQ_LINKRESET);
    ask(LSM_LINKRESET, LSM_REQ_DISABLED);
    plan_done();
    settle();
    // Ignored: LinkReset in Disabled; LinkReset and Disabled in LinkError.
    ask(LSM_ACTIVE, LSM_REQ_DISABLED);
    ask(LSM_DISABLED, LSM_REQ_LINKRESET, -1, 1'b1);
    plan_done();
    settle();
    env.pl.linkerror_hold = 100;
    ask(LSM_LINKERROR, LSM_REQ_LINKRESET, -1, 1'b1);
    ask(LSM_LINKERROR, LSM_REQ_DISABLED, -1, 1'b1);
    le_req(LSM_ACTIVE);
    plan_done();
    env.pl.linkerror_hold = 0;
    settle();
    // lp_linkerror in every state.
    down(LSM_EV_LINK_RESET);
    le_req(LSM_RESET, 0);
    settle();
    fork
      cev(LSM_EV_LINK_RESET);
      le_req(LSM_RESET, 1);
    join
    settle();
    fork
      long_event(LSM_EV_IDLE, 400);
      le_req(LSM_ACTIVE);
    join
    settle();
    env.pl.linkerror_hold = 2000;
    fork
      long_event(LSM_EV_RETRAIN, 400);
      le_req(LSM_RETRAIN);
    join
    env.pl.linkerror_hold = 0;
    settle();
    cev(LSM_EV_L1_ENTRY);
    le_req(LSM_L1);
    settle();
    fork
      long_event(LSM_EV_LINK_RESET, 400);
      le_req(LSM_LINKRESET);
    join
    settle();
    fork
      long_event(LSM_EV_DISABLED, 400);
      le_req(LSM_DISABLED);
    join
    settle();
    // During an L1 entry: raised as the entry starts, while the status is
    // still Active.
    fork
      cev(LSM_EV_L1_ENTRY);
      begin
        while (env.lsm.drv.idle()) @(env.pl.lsm.mon_cb);
        le_req(LSM_UNKNOWN);
      end
    join
    settle();
    mid_raise();
    env.lsm_cfg.dwell_min = 8;
    env.lsm_cfg.dwell_max = 40;
    super.events();
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.pl.n_down < n_plan)
      `uvm_error(get_type_name(), $sformatf("%0d of %0d LinkReset and Disabled requests answered",
                                            env.pl.n_down, n_plan))
    if (env.pl.n_ignored < 3)
      `uvm_error(get_type_name(), $sformatf("%0d of 3 ignored requests made", env.pl.n_ignored))
    if (mode == "gated" && (env.pl.n_le_gated == 0 || env.pl.n_req_gated == 0))
      `uvm_error(get_type_name(), $sformatf({"requests made after waking from clock gating: ",
                 "%0d lp_linkerror, %0d lp_state_req"}, env.pl.n_le_gated, env.pl.n_req_gated))
    if (mode == "exit_pl" && env.pl.n_exits == 0)
      `uvm_error(get_type_name(), "no link-down state left on the stub's Active request")
    if (mode inside {"exit_pl", "exit_either"} && env.lsm.drv.n_exit_req == 0)
      `uvm_error(get_type_name(), "the Adapter never left a link-down state on the Active request")
    if (mode == "via_active" && env.lsm.drv.n_via_active == 0)
      `uvm_error(get_type_name(), "no request was answered through Active")
    if (slow_ack > env.lsm_cfg.lat_max + env.lsm_cfg.remote_rsp_max + 10 && n_mid < 4)
      `uvm_error(get_type_name(), $sformatf({"%0d of 4 mid-handshake requests left the gated ",
                 "state before lp_clk_ack answered"}, n_mid))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({"requests answered: LinkReset/Disabled %0d (driver %0d, ",
              "%0d through Active), ignored %0d, lp_linkerror %0d (driver %0d; %0d and %0d ",
              "requests after waking from clock gating), exits on Active %0d (stub-checked %0d), ",
              "%0d gated states left mid-handshake (lp_clk_ack after %0d clocks)"},
              env.pl.n_down, env.lsm.drv.n_down_req, env.lsm.drv.n_via_active, env.pl.n_ignored,
              env.pl.n_le_answered, env.lsm.drv.n_le_react, env.pl.n_le_gated,
              env.pl.n_req_gated, env.lsm.drv.n_exit_req, env.pl.n_exits, n_mid, slow_ack),
              UVM_NONE)
  endfunction
endclass

// Wait (bounded) until the stub has a flit to send back.
task automatic wait_flit_queued(ucie_fdi_selftest_env env);
  int unsigned n;
  while (env.pl.idle() && n < 50000) begin
    @(env.pl.lsm.mon_cb);
    n++;
  end
endtask

// The cov test's events and traffic with a Protocol Layer that does what UCIe
// r3.0 allows but a stricter reading would reject (ucie_pl_stub): it presents
// flits without waiting for pl_trdy and keeps them up through Retrain,
// LinkError and the start of LinkReset and Disabled, and a few clocks into
// Reset after LinkError (`early`); drives lp_valid without lp_irdy between
// flits (`valid`); drops lp_clk_ack and lp_rx_active_sts 30 clocks after
// their requests (`hs_lag`); holds lp_linkerror 25000 clocks into LinkError
// (`le_hold`); and raises lp_wake_req a clock after its Active request in
// Reset (`wake_late`). +legal=all (default) or a comma-separated list of
// those names. Any error fails the run. Before the cov test's events, the TX
// is held back (tx_hold) through a Retrain, a LinkReset, a Disabled and a
// LinkError, so a flit is sure to wait out each of them presented.
class ucie_fdi_legal_test extends ucie_fdi_cov_test;
  `uvm_component_utils(ucie_fdi_legal_test)

  string legal = "all";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Whether +legal names `what` (or is "all").
  function bit on(string what);
    string rest = {legal, ","};
    int b = 0;
    if (legal == "all") return 1'b1;
    for (int i = 0; i < rest.len(); i++)
      if (rest[i] == ",") begin
        if (rest.substr(b, i - 1) == what) return 1'b1;
        b = i + 1;
      end
    return 1'b0;
  endfunction

  function void configure();
    super.configure();
    void'($value$plusargs("legal=%s", legal));
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.early_present = on("early");
    env.pl.valid_alone = on("valid");
    env.pl.hs_lag = on("hs_lag") ? 30 : 0;
    env.pl.linkerror_hold = on("le_hold") ? 25000 : 0;
    env.pl.wake_late = on("wake_late");
    `uvm_info(get_type_name(), $sformatf("legal behaviours: %s", legal), UVM_NONE)
  endfunction

  local task lev(ucie_lsm_ev_e kind);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(kind);
    s.start(env.lsm.sqr);
  endtask

  task events();
    wait_flit_queued(env);
    env.fdi_cfg.tx_hold = 1'b1;
    lev(LSM_EV_RETRAIN);
    lev(LSM_EV_LINK_RESET);
    lev(LSM_EV_DISABLED);
    lev(LSM_EV_LINKERROR);
    env.fdi_cfg.tx_hold = 1'b0;
    super.events();
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.pl.early_present && env.pl.n_presented_down == 0)
      `uvm_error(get_type_name(), "no flit was presented outside Active")
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("clocks a flit was presented outside Active: %0d",
                                         env.pl.n_presented_down), UVM_NONE)
  endfunction
endclass

// Demotes the errors of one rule to infos and counts them (ucie_fdi_neg_test);
// those of `also`, a rule the same fault breaks on the way, are demoted
// without being counted.
class ucie_fdi_expect_catcher extends uvm_report_catcher;
  string       rule;
  string       also;
  int unsigned n;

  function new(string name = "ucie_fdi_expect_catcher");
    super.new(name);
  endfunction

  function action_e catch();
    string m = get_message();
    if (get_severity() == UVM_ERROR && rule != "" && m.substr(0, rule.len() - 1) == rule) begin
      n++;
      set_severity(UVM_INFO);
    end else if (get_severity() == UVM_ERROR && also != "" &&
                 m.substr(0, also.len() - 1) == also) begin
      set_severity(UVM_INFO);
    end
    return THROW;
  endfunction
endclass

// Negative test of the model's checks: the stub makes one deliberate violation
// (+neg=dllp|retimer|stream|corrupt_mid|corrupt_h0|corrupt_proto|clk_ack|
// irdy_reset|wake|wake_held, see ucie_pl_stub::bad; corrupt_mid and
// corrupt_h0 need an FDI of 128 B or less), or the top breaks the Adapter
// (ucie_fdi_selftest_top): with +neg=xfer it forces pl_trdy high for a clock
// while the stub presents a flit in Retrain (needs an FDI of 256 B or more,
// where that transfer is a whole flit), with +neg=le_exit it reports Reset
// for a clock while the stub holds lp_linkerror in LinkError, with
// +neg=rx_inactive it drops pl_rx_active_req in Active while flits go on, and
// with clk_exit, le_after and level it breaks the pl_clk_req handshake around
// a LinkReset, a LinkError from Reset and a level signal in Reset (see the
// top; FDI-R22, R21, R20). +neg=inband_active asks the model for a
// pl_inband_pres drop in Active, a usage error the driver refuses. With
// +neg=held_forever the stub holds an Active request from a LinkReset into
// Reset for good, so it never asks to leave Reset (NOP, then Active; r3.0
// §10.3.3.1 rule 1), and with +neg=no_restart the training waits for the
// Protocol Layer's NOP->Active after the LinkReset (restart_on PL), which
// the stub never gives: the driver's liveness bound, req_timeout (3000
// here), reports each as FDI-R33. With +neg=wake_down the stub, the link
// left in Reset, requests LinkReset after a NOP with no lp_wake_req, and
// with +neg=wake_le raises lp_linkerror there with no lp_wake_req (FDI-R16,
// r3.0 §10.2.3.1); with +neg=unanswered the Adapter answers nothing
// (react_en 0), so the stub's own checks must report its LinkReset request
// in Active and its lp_linkerror unanswered (req_bound 300 here). The
// rule that must catch it has to fire, as often as the violation is made
// (wake_held: the first bringup and the one after each of three LinkErrors);
// its errors are expected and demoted. Any other error still fails the run.
// xfer and irdy_reset hold the TX back (tx_hold) through a Retrain, a
// LinkReset and a Disabled, with the stub presenting early.
class ucie_fdi_neg_test extends ucie_fdi_smoke_test;
  `uvm_component_utils(ucie_fdi_neg_test)

  ucie_fdi_expect_catcher catcher;
  string                  neg;
  int unsigned            min_n = 1;  // reports the violation must draw

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
      "corrupt_mid", "corrupt_h0": begin
        catcher.rule = neg == "corrupt_mid" ? "FDI-R59" : "FDI-R60";
        // A protocol where lp_corrupt_crc applies, so only the placement is wrong.
        env.fdi_cfg.stream = 8'h03;
        env.lsm_cfg.protocol = UCIE_PROTO_CXL2;
        if (env.fdi_cfg.bpf() == 1)
          `uvm_fatal(get_type_name(), {"+neg=", neg, " needs an FDI of 128 B or less"})
      end
      "corrupt_proto": catcher.rule = "FDI-R61";
      "clk_ack":    catcher.rule = "FDI-R18";
      "irdy_reset": catcher.rule = "FDI-R44";
      "wake":       catcher.rule = "FDI-R16";
      "wake_held": begin
        catcher.rule = "FDI-R16";
        min_n = 4;
      end
      "le_exit": begin
        // The Reset the top forces also re-enters LinkError from Reset with
        // no pl_clk_req (r3.0 §10.2.3.2 rule 6).
        catcher.rule = "FDI-R49";
        catcher.also = "FDI-R21";
      end
      "clk_exit": begin
        // The forced drop also withdraws pl_clk_req before the stub's own
        // lp_clk_ack answered it, which the stub reports as well.
        catcher.rule = "FDI-R22";
        catcher.also = "Protocol Layer stub: pl_clk_req fell";
      end
      "le_after":    catcher.rule = "FDI-R21";
      "level":       catcher.rule = "FDI-R20";
      "inband_active": catcher.rule = "LSM_EV_INBAND_DROP";
      "held_forever", "no_restart": begin
        // No request to leave Reset, or no trigger to restart the training:
        // the driver's liveness bound (shortened here) reports it.
        catcher.rule = "FDI-R33";
        env.lsm_cfg.req_timeout = 3000;
        if (neg == "no_restart") env.lsm_cfg.restart_on = LSM_RESTART_PL;
      end
      "rx_inactive": catcher.rule = "FDI-R35";
      "wake_down", "wake_le": catcher.rule = "FDI-R16";
      "unanswered": begin
        catcher.rule = "Protocol Layer stub: no answer";
        min_n = 2;
        env.lsm_cfg.react_en = 1'b0;
      end
      "xfer": begin
        catcher.rule = "FDI-R43";
        if (env.fdi_cfg.bpf() != 1)
          `uvm_fatal(get_type_name(), "+neg=xfer needs an FDI of 256 B or more")
      end
      default:   `uvm_fatal(get_type_name(), {"+neg: unknown violation ", neg})
    endcase
    uvm_report_cb::add(null, catcher);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.bad = neg;
    env.pl.early_present = neg inside {"xfer", "irdy_reset"};
    // le_after: an acknowledge slow enough for the top to strike before it.
    if (neg == "le_after") env.pl.clk_ack_delay = 4;
    if (neg == "unanswered") env.pl.req_bound = 300;
  endfunction

  local task nev(ucie_lsm_ev_e kind);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(kind);
    s.start(env.lsm.sqr);
  endtask

  task events();
    if (neg == "wake_held") begin
      repeat (3) nev(LSM_EV_LINKERROR);
      return;
    end
    if (neg == "le_exit") begin
      // A LinkError the stub requests and then holds, which the top cuts short.
      int unsigned n_react = env.lsm.drv.n_le_react;
      env.pl.linkerror_hold = 200;
      env.pl.linkerror_req = 1'b1;
      repeat (20000) begin
        @(env.pl.lsm.mon_cb);
        if (env.lsm.drv.n_le_react != n_react) break;
      end
      // The Adapter, already down, only brings the link up again.
      nev(LSM_EV_LINKERROR);
      return;
    end
    case (neg)
      "clk_exit", "level", "held_forever", "no_restart": begin
        nev(LSM_EV_LINK_RESET);
        return;
      end
      "inband_active": begin
        nev(LSM_EV_INBAND_DROP);
        return;
      end
      "wake_down", "wake_le": begin
        // The link left in Reset, before pl_inband_pres.
        env.lsm_cfg.rebringup_after_down = 1'b0;
        nev(LSM_EV_LINK_RESET);
        env.lsm_cfg.rebringup_after_down = 1'b1;
        if (neg == "wake_down") begin
          ucie_pl_stub::plan_t p;
          p.in = LSM_RESET;
          p.req = LSM_REQ_LINKRESET;
          p.up = 0;
          p.ignore = 1'b0;
          env.pl.plan.push_back(p);
          // The stub drops the request if it is not answered (req_bound).
          while (env.pl.plan.size() != 0) @(env.pl.lsm.mon_cb);
        end else begin
          env.pl.linkerror_in = LSM_RESET;
          env.pl.linkerror_req = 1'b1;
          // Cleared on the answer, or by the stub when there is none.
          while (env.pl.linkerror_req) @(env.pl.lsm.mon_cb);
        end
        // Left in Reset (after a LinkError, or with no answer): bring it up.
        while (!env.lsm.drv.idle()) @(env.pl.lsm.mon_cb);
        if (env.lsm.drv.state == LSM_RESET) nev(LSM_EV_LINKERROR);
        return;
      end
      "unanswered": begin
        ucie_pl_stub::plan_t p;
        int unsigned n0 = catcher.n;
        p.in = LSM_ACTIVE;
        p.req = LSM_REQ_LINKRESET;
        p.up = -1;
        p.ignore = 1'b0;
        env.pl.plan.push_back(p);
        while (env.pl.plan.size() != 0) @(env.pl.lsm.mon_cb);
        env.pl.linkerror_req = 1'b1;
        while (catcher.n == n0 + 1 && env.pl.linkerror_req) @(env.pl.lsm.mon_cb);
        return;
      end
      "le_after": begin
        // A LinkError from Reset reported before its pl_clk_req (rule 6's
        // second option), which the top cuts short with a Reset.
        ucie_lsm_event_seq s = ucie_lsm_event_seq::of(LSM_EV_ABORT);
        s.ev_to = LSM_LINKERROR;
        s.ev_at = LSM_AB_RESET;
        s.ev_gap = 0;
        s.start(env.lsm.sqr);
        return;
      end
      default: ;
    endcase
    if (!(neg inside {"xfer", "irdy_reset"})) return;
    wait_flit_queued(env);
    env.fdi_cfg.tx_hold = 1'b1;
    nev(LSM_EV_RETRAIN);
    nev(LSM_EV_LINK_RESET);
    nev(LSM_EV_DISABLED);
    env.fdi_cfg.tx_hold = 1'b0;
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (catcher.n < min_n)
      `uvm_error(get_type_name(), $sformatf("the %s violation was not caught (%s, %0d of %0d)",
                                            neg, catcher.rule, catcher.n, min_n))
    else
      `uvm_info(get_type_name(), $sformatf("%s caught the %s violation (%0d reports)",
                                           catcher.rule, neg, catcher.n), UVM_NONE)
  endfunction
endclass
