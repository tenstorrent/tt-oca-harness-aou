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
    traffic_on(env, n_flits);
  endtask

  // n random flits into the Protocol Layer of env's link.
  protected task traffic_on(ucie_fdi_selftest_env e, int unsigned n);
    ucie_flit_seq seq = ucie_flit_seq::type_id::create("flits");
    for (int unsigned i = 0; i < n; i++) begin
      ucie_flit_item f = ucie_flit_item::type_id::create("payload");
      f.randomize_payload();
      seq.payloads.push_back(f);
      e.sb.expect_rx(f);
    end
    seq.n_flits = 0;
    seq.cancel_pct = 25;
    seq.cancel_mix = 1'b1;
    seq.gap_pct = 30;
    seq.bubble_pct = 10;
    seq.start(e.fdi.sqr);
  endtask

  // Link events alongside the traffic; none here.
  virtual task events();
  endtask

  task drain();
    drain_on(env);
  endtask

  // Until everything sent on env's link is delivered and looped back (bounded).
  protected task drain_on(ucie_fdi_selftest_env e);
    int unsigned n;
    while (!(e.sb.rx_exp.size() == 0 && e.sb.lb_exp.size() == 0 && e.pl.idle()) &&
           n < drain_timeout) begin
      @(e.pl.lsm.mon_cb);
      n++;
    end
    repeat (100) @(e.pl.lsm.mon_cb);
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

// NOP flits (r3.0 Table 3-5) both ways, on the smoke test's traffic. RX: the
// PL driver forwards NOPs (nop_pct 15, or +ucie_nop_pct) with random sequence
// number and Ack/Nak bits and an all-zero body (r3.0 §3.1), at every width: through uncancelled,
// cancelled and replayed, cancelled and never replayed, and from 512 B up in
// lanes among other flits. The Protocol Layer must discard them (Table 10-3
// pl_flit_cancel), so the scoreboard, which takes every delivered flit for the
// next one sent, must see none. With +nop_tx=1 the link is CXL.2 (stream 03h),
// where a Protocol Layer may send a NOP, and the stub starts a tenth of its TX
// transfers with one, which FDI-R45 must accept. Fails if the run saw no NOP
// of each kind.
class ucie_fdi_nop_test extends ucie_fdi_smoke_test;
  `uvm_component_utils(ucie_fdi_nop_test)

  bit nop_tx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    env.fdi_cfg.nop_pct = 15;
    void'($value$plusargs("nop_tx=%b", nop_tx));
    if (nop_tx) begin
      env.fdi_cfg.stream = 8'h03;
      env.lsm_cfg.protocol = UCIE_PROTO_CXL2;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (nop_tx) env.pl.tx_nop_pct = 10;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.fdi.drv.n_nops_dropped == 0 || env.fdi.mon.n_rx_nop_cancels == 0)
      `uvm_error(get_type_name(), "no RX NOP was cancelled and dropped")
    if (env.fdi.mon.n_rx_nops == 0) `uvm_error(get_type_name(), "no uncancelled RX NOP was seen")
    if (nop_tx && env.fdi.mon.n_tx_nops == 0) `uvm_error(get_type_name(), "no TX NOP was seen")
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({"NOPs: %0d forwarded (%0d dropped), %0d discarded ",
                                          "uncancelled, %0d cancels of NOPs; %0d sent and %0d ",
                                          "seen on TX"}, env.fdi.drv.n_nops,
                                         env.fdi.drv.n_nops_dropped, env.fdi.mon.n_rx_nops,
                                         env.fdi.mon.n_rx_nop_cancels, env.pl.n_tx_nop,
                                         env.fdi.mon.n_tx_nops), UVM_NONE)
  endfunction
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
//            the Adapter's own restart decision delayed to 20000 clocks
//            (sw_restart_delay): after every link-down
//            pl_inband_pres must follow the trigger within 300 clocks, and a
//            link left down (rebringup_after_down 0) must come up on it;
//  either    restart_on EITHER, the trigger in half the Resets;
//  rx_first  remote_active_first_pct 100: the Adapter starts the rx_active
//            handshake before the request, in Reset and in Retrain (both
//            must happen);
//  drop      the stub waits 100 clocks of pl_inband_pres before it requests
//            Active (software first), and the test drops pl_inband_pres
//            (do_inband_drop, 30 clocks) beside the bringup while it waits for
//            that request, with the Adapter's latencies at one clock
//            (pl_wake_ack a clock after lp_wake_req): once in the first
//            bringup, and once in the bringup of a LinkReset event (the drop
//            waits until the link has been in LinkReset, then for that
//            bringup to wait in Reset). As pl_inband_pres falls
//            the stub gives NOP->Active for one clock and returns to NOP: no
//            request (r3.0 §10.2.3.2, last paragraph; §10.3.3.8), so the
//            Adapter must wait for the next NOP->Active (the stub reports
//            otherwise), and the Active entry it then makes must keep
//            pl_clk_req up until Active whatever the drop does with it
//            (§10.2.3.2 rule 7, FDI-R22). The test fails unless each drop was
//            made in its bringup, in Reset (it logs where each one was made),
//            and unless each drop's pl_clk_req rises inband_drop_clk_lag
//            clocks after it (+ucie_inband_drop_clk_lag=N: the drop first,
//            r3.0 §10.2.3.2 rule 5; FDI-R20 must stay silent).
//            clk_req_hold_bringup defaults to 0, and the mode cannot run with
//            +clk_hold=1: the drop waits for pl_clk_req to be released in
//            Reset;
//  drop_overlap  the same stub, and one drop (30 clocks) beside the bringup
//            of a LinkReset event as it waits to restart the training
//            (sw_restart_delay 4), pl_inband_pres and pl_clk_req low, with
//            the stub acknowledging pl_clk_req 20 clocks late: the bringup
//            raises its own pl_clk_req while the drop's still waits for
//            lp_clk_ack, raises pl_inband_pres once acknowledged and releases
//            its request, all inside the drop. pl_clk_req must stay up from
//            that lp_clk_ack until pl_inband_pres rises, although the drop
//            releases its own request in between: the test's watcher checks the
//            model's own bringup sequence, while FDI-R20 (§10.2.3.2 rule 5) is
//            the spec-level check that reports a rise without the handshake
//            (rule 7 does not apply here: the status does not change).
//            clk_req_hold_bringup defaults to 0.
// +clk_hold=0|1 sets clk_req_hold_bringup (default 1). Any error fails it.
class ucie_fdi_reset_req_test extends ucie_fdi_cov_test;
  `uvm_component_utils(ucie_fdi_reset_req_test)

  string mode = "held";
  // drop, drop_overlap: pl_inband_pres drops made beside a bringup, those of
  // them made where intended, and where each was made (one line per drop).
  int unsigned n_overlaps;
  int unsigned n_placed;
  string       drop_at[$];
  int unsigned n_kept_up;   // drop_overlap: pl_clk_req kept up until pl_inband_pres rose
  int unsigned drop_lag[$]; // drop: clocks from each drop to its pl_clk_req
  local bit    lr_done;     // the LinkReset event (and its bringup) has ended

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    bit hold = 1'b1;
    super.configure();
    void'($value$plusargs("reset_req=%s", mode));
    if (mode inside {"drop", "drop_overlap"}) hold = 1'b0;
    void'($value$plusargs("clk_hold=%b", hold));
    env.lsm_cfg.clk_req_hold_bringup = hold;
    case (mode)
      "held", "early", "drop", "drop_overlap": ;
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
    if (mode inside {"drop", "drop_overlap"}) env.pl.act_delay = 100;
    if (mode == "drop") env.pl.drop_pulse = 1'b1;
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
    if (mode == "drop") begin
      drop_beside(1'b0);
      fork
        begin
          cev(LSM_EV_LINK_RESET);
          lr_done = 1'b1;
        end
        drop_beside(1'b1);
      join
      wait_active();
    end
    if (mode == "drop_overlap") begin
      int unsigned delay = env.lsm_cfg.sw_restart_delay;
      env.lsm_cfg.sw_restart_delay = 4;
      fork
        begin
          cev(LSM_EV_LINK_RESET);
          lr_done = 1'b1;
        end
        drop_overlap();
      join
      env.lsm_cfg.sw_restart_delay = delay;
      wait_active();
    end
    super.events();
  endtask

  // Wait (bounded) for a drop's moment: with after_lr first until the link has
  // been in LinkReset (the LinkReset event the caller runs alongside), then
  // until it is in Reset with pl_inband_pres at `pres` and pl_clk_req and
  // lp_clk_ack low. Then records where the drop is made: the link state, and
  // the bringup it is beside, the first one (the link never Active yet) or,
  // with after_lr, the LinkReset event's (the event still running and the link
  // not Active since LinkReset). `found` 0: the moment never came.
  local task drop_point(bit after_lr, bit pres, output bit found);
    int unsigned n;
    bit seen_lr, was_up, ok;
    string job, at;
    found = 1'b0;
    while (n < 50000) begin
      ucie_lsm_state_e s;
      @(env.pl.lsm.mon_cb);
      n++;
      s = env.lsm.drv.state;
      if (s == LSM_ACTIVE) was_up = 1'b1;
      if (after_lr && !seen_lr) begin
        if (s != LSM_LINKRESET) continue;
        seen_lr = 1'b1;
        was_up = 1'b0;
      end
      if (s == LSM_RESET && env.pl.lsm.mon_cb.pl_inband_pres === pres &&
          env.pl.lsm.mon_cb.pl_clk_req === 1'b0 && env.pl.lsm.mon_cb.lp_clk_ack === 1'b0) begin
        found = 1'b1;
        break;
      end
    end
    if (!found) return;
    job = env.lsm.drv.idle() ? "no job" :
          was_up ? "a later bringup" :
          !after_lr ? "the first bringup" :
          !lr_done ? "the LinkReset event's bringup" : "a later bringup";
    ok = job inside {"the first bringup", "the LinkReset event's bringup"};
    n_overlaps++;
    at = $sformatf("drop %0d @ %0t beside %s, link state %s", n_overlaps, $time, job,
                   env.lsm.drv.state.name());
    if (ok) n_placed++;
    else at = {at, " (not where intended)"};
    drop_at.push_back(at);
    `uvm_info(get_type_name(), at, UVM_LOW)
  endtask

  // drop: once the bringup waits in Reset for the request (pl_inband_pres 1,
  // pl_clk_req released), drop pl_inband_pres from this thread, beside it,
  // with the Adapter's latencies at one clock. With after_lr, in the bringup
  // that follows a LinkReset.
  local task drop_beside(bit after_lr);
    int unsigned lat_min = env.lsm_cfg.lat_min;
    int unsigned lat_max = env.lsm_cfg.lat_max;
    bit found;
    env.lsm_cfg.lat_min = 1;
    env.lsm_cfg.lat_max = 1;
    drop_point(after_lr, 1'b1, found);
    if (found) begin
      bit done;
      int n = 0, fell = -1;
      fork
        begin
          env.lsm.drv.do_inband_drop(30);
          done = 1'b1;
        end
        // Clocks from the pl_inband_pres fall to the pl_clk_req rise.
        while (!done && n < 1000) begin
          @(env.pl.lsm.mon_cb);
          if (fell == -1 && env.pl.lsm.mon_cb.pl_inband_pres !== 1'b1) fell = n;
          if (env.pl.lsm.mon_cb.pl_clk_req === 1'b1) begin
            if (fell == -1) fell = n;
            drop_lag.push_back(n - fell);
            break;
          end
          n++;
        end
      join
    end else
      `uvm_error(get_type_name(), "the bringup never waited in Reset with pl_clk_req released")
    env.lsm_cfg.lat_min = lat_min;
    env.lsm_cfg.lat_max = lat_max;
  endtask

  // drop_overlap: once the LinkReset event's bringup waits in Reset to
  // restart the training (pl_inband_pres, pl_clk_req and lp_clk_ack low), drop
  // pl_inband_pres beside it with lp_clk_ack 20 clocks late, and watch that
  // pl_clk_req stays up from the drop's lp_clk_ack until the bringup raises
  // pl_inband_pres.
  local task drop_overlap();
    int unsigned ack_delay = env.pl.clk_ack_delay;
    bit found, done, acked, rose, kept = 1'b1;
    drop_point(1'b1, 1'b0, found);
    if (!found) begin
      `uvm_error(get_type_name(), "the LinkReset event's bringup never waited in Reset to restart")
      return;
    end
    env.pl.clk_ack_delay = 20;
    fork
      begin
        env.lsm.drv.do_inband_drop(30);
        done = 1'b1;
      end
      while (!done) begin
        @(env.pl.lsm.mon_cb);
        if (!acked) acked = env.pl.lsm.mon_cb.lp_clk_ack === 1'b1;
        else if (!rose) begin
          if (env.pl.lsm.mon_cb.pl_inband_pres === 1'b1) rose = 1'b1;
          else if (env.pl.lsm.mon_cb.pl_clk_req !== 1'b1) kept = 1'b0;
        end
      end
    join
    env.pl.clk_ack_delay = ack_delay;
    if (rose && kept) n_kept_up++;
    else
      `uvm_error(get_type_name(), $sformatf({"drop_overlap: %s inside the drop (lp_clk_ack %0b, ",
                 "pl_inband_pres rose %0b, pl_clk_req up until then %0b)"},
                 rose ? "pl_clk_req fell before the bringup raised pl_inband_pres" :
                 "the bringup did not raise pl_inband_pres", acked, rose, kept))
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
      "drop": begin
        if (n_overlaps != 2 || n_placed != 2)
          `uvm_error(get_type_name(), $sformatf({"%0d drops made, %0d where intended (one beside ",
                     "the first bringup, one beside the LinkReset event's)"}, n_overlaps, n_placed))
        if (env.pl.n_drop_pulses < 2)
          `uvm_error(get_type_name(), "the stub gave no NOP->Active as pl_inband_pres fell")
        if (drop_lag.size() != n_overlaps)
          `uvm_error(get_type_name(), $sformatf("%0d drops, %0d of them with a pl_clk_req seen",
                     n_overlaps, drop_lag.size()))
        foreach (drop_lag[i])
          if (drop_lag[i] != env.lsm_cfg.inband_drop_clk_lag)
            `uvm_error(get_type_name(), $sformatf({"drop %0d: pl_clk_req %0d clocks after ",
                       "pl_inband_pres fell, inband_drop_clk_lag %0d"}, i + 1, drop_lag[i],
                       env.lsm_cfg.inband_drop_clk_lag))
      end
      "drop_overlap":
        if (n_overlaps != 1 || n_placed != 1 || n_kept_up != 1)
          `uvm_error(get_type_name(), $sformatf({"%0d drops made, %0d beside the LinkReset ",
                     "event's bringup, %0d with pl_clk_req kept up"}, n_overlaps, n_placed,
                     n_kept_up))
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
              "rx_active handshakes before the request %0d in Reset, %0d in Retrain, ",
              "drops beside a bringup %0d (%0d where intended, %0d with pl_clk_req kept up), ",
              "NOP->Active pulses as pl_inband_pres fell %0d"},
              env.pl.n_held, env.pl.n_other, env.pl.n_early, env.pl.n_early_waits,
              env.pl.n_restarts, env.pl.n_rx_first, env.pl.n_rx_first_rt, n_overlaps, n_placed,
              n_kept_up, env.pl.n_drop_pulses), UVM_NONE)
    foreach (drop_at[i]) `uvm_info(get_type_name(), drop_at[i], UVM_NONE)
    foreach (drop_lag[i])
      `uvm_info(get_type_name(), $sformatf("drop %0d: pl_clk_req %0d clocks after the drop",
                i + 1, drop_lag[i]), UVM_NONE)
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

// Stand-alone stalls around the Adapter's exits from Active. In Flit mode the
// stall handshake belongs to PM entry only (UCIe r3.0 §10.3.2), and pl_trdy may
// be high only in Active, or in LinkError during a stall handshake (Table 10-3
// pl_trdy); the model's stand-alone stalls are stress beyond that, and a
// handshake under way when the link leaves Active must neither leave pl_trdy
// high outside Active nor be cut (rule 3). Stalls here are dense (stall_pct,
// +stall_pct=N, default 25), pl_trdy is held high between pl_stallreq and
// lp_stallack (+stall_trdy_free=1 has it follow the policy instead), and the
// stub acknowledges late: +stall_ack=N clocks after the flit boundary
// (default 40; with +stall_exit=random a random 0..N per stall). With
// +hold_present=1 the stub presents flits without waiting for pl_trdy and
// keeps a presented flit up through pl_stallreq until it transfers (legal:
// §10.2.4, §10.3.2 rules 6 and 7), so a stall in which the Adapter withholds pl_trdy never
// ends; the run must then see such a flit accepted. +stall_exit=:
//  directed  Retrain, LinkReset and Disabled issued while a stall waits for
//            lp_stallack, a LinkError entered mid-flit then (retried up to
//            five times until one catches a flit in flight), a LinkError at
//            a flit boundary then, and a PM entry and exit after one;
//  req       Protocol Layer requests during a stall: LinkReset stopping an
//            Adapter Retrain, lp_linkerror stopping an Adapter LinkReset, and
//            a Disabled request with no event running;
//  le_drop   lp_linkerror raised during a stall and dropped a clock later,
//            before LinkError is reported, with a LinkReset or Disabled
//            request in its place (the stub's le_drop), with no event
//            running and while an Adapter Retrain waits for the stall: the
//            link must still leave Active for LinkError and come back up
//            (the Adapter has seen the assertion; LinkError has priority,
//            r3.0 §10.3.3.8);
//  le_mid    (below 256 B) Adapter LinkErrors entered mid-flit while a stall waits for
//            lp_stallack with a TX flit part-way (stall_mid_pct 90, pl_trdy
//            random at 25 % meanwhile, the stall's own pl_trdy as
//            stall_trdy_free has it): up to 40
//            tries, until 3 catch the stub inside a flit with pl_stallreq up;
//            at least one must. +le_stall_drain=1 (any mode) sets the model's
//            le_stall_drain: the Adapter performs the handshake in LinkError
//            and drains the Protocol Layer (§10.3.3.7: "must provide pl_trdy
//            to the upper layer to drain the packets"), abandoning it on the
//            exit to Reset; by default it abandons it on entry. With
//            +keep_partial=1 (any mode) the stub keeps such a flit presented
//            in LinkError, as a Protocol Layer may that cleans up its data
//            path later (§10.3.3.7 sets no time); with the drain it finishes
//            the flit there and acknowledges at its boundary (rule 4), and
//            le_mid fails unless a flit was drained so. With +le_ignore=1
//            (any mode) it keeps the flit presented but takes no pl_trdy
//            outside Active and never acknowledges in LinkError, which r3.0
//            allows (§10.3.3.7 requires the upper layer to clean up "even if
//            pl_trdy is not asserted", not to acknowledge). With le_ignore,
//            or without the drain, le_mid fails unless a handshake was
//            abandoned (pl_stallreq fell unacknowledged);
//  random    nothing of its own.
// Each mode then runs the cov test's events. Besides the monitor's FDI-R43
// (pl_trdy outside Active) the test checks that the status leaves Active for
// Retrain, LinkReset or Disabled only with the handshake done (pl_stallreq and
// lp_stallack low), that pl_stallreq is low once LinkError has gone to Reset
// (the exit abandons an open handshake), and that the model
// raises pl_trdy in LinkError only to drain, while pl_stallreq is high and
// lp_stallack was still low a clock before. With +stall_ack=20 or more it also checks
// that a LinkError (the Adapter's at a flit boundary, or the answer to
// lp_linkerror) is entered without waiting for lp_stallack (r3.0 §10.3.3.7,
// Table 10-3 lp_linkerror). With +trdy_le_stall=1 the top forces pl_trdy high
// for a clock in LinkError during a stall handshake, which r3.0 allows and
// FDI-R43 must accept (the pl_trdy check in LinkError is then off; it implies
// +le_stall_drain=1, so the handshake runs on in LinkError).
class ucie_fdi_stall_exit_test extends ucie_fdi_cov_test;
  `uvm_component_utils(ucie_fdi_stall_exit_test)

  string           mode = "directed";
  int unsigned     stall_ack = 40;
  bit              trdy_forced;
  bit              hold;
  bit              keep;        // +keep_partial: the stub keeps a cut flit up in LinkError
  bit              ignore;      // +le_ignore: ... and takes no pl_trdy or stall there
  bit              drain;       // +le_stall_drain: the model's le_stall_drain
  int unsigned     n_hit;       // events and requests started while a stall waited for its ack
  int unsigned     n_le_stall;  // LinkErrors entered with pl_stallreq high
  int unsigned     n_le_drop_held;  // le_drop cases started with a flit held at pl_trdy low
  int unsigned     n_exits;     // exits from Active checked
  int unsigned     n_after;     // ... to Retrain, LinkReset, Disabled or LinkError within 10
                                // clocks of a stall handshake's end (it likely waited for it)
  ucie_lsm_state_e exit_to;     // the state the link last left Active for

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    int unsigned v;
    super.configure();
    void'($value$plusargs("stall_exit=%s", mode));
    void'($value$plusargs("stall_ack=%d", stall_ack));
    if (!(mode inside {"directed", "req", "le_drop", "le_mid", "random"}))
      `uvm_fatal(get_type_name(), {"+stall_exit: unknown mode ", mode})
    void'($value$plusargs("trdy_le_stall=%b", trdy_forced));
    void'($value$plusargs("hold_present=%b", hold));
    void'($value$plusargs("keep_partial=%b", keep));
    void'($value$plusargs("le_ignore=%b", ignore));
    void'($value$plusargs("le_stall_drain=%b", drain));
    drain |= trdy_forced;
    env.fdi_cfg.le_stall_drain = drain;
    env.fdi_cfg.stall_pct = 25;
    if (mode == "le_mid") env.fdi_cfg.stall_mid_pct = 90;
    if ($value$plusargs("stall_pct=%d", v)) env.fdi_cfg.stall_pct = v;
    env.fdi_cfg.stall_trdy_free = 1'b0;
    if ($value$plusargs("stall_trdy_free=%d", v)) env.fdi_cfg.stall_trdy_free = v != 0;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.pl.stall_ack_delay = stall_ack;
    env.pl.stall_ack_rand = mode == "random";
    env.pl.hold_present = hold;
    env.pl.keep_partial = keep;
    env.pl.le_ignore = ignore;
    `uvm_info(get_type_name(), $sformatf(
              "stall_exit %s: stall_ack %0d, hold_present %0b, keep_partial %0b, le_ignore %0b, %s",
              mode, stall_ack, hold, keep, ignore, env.fdi_cfg.convert2string()), UVM_NONE)
  endfunction

  // The test's own checks (see the header), every clock.
  local task watch();
    ucie_lsm_state_e prev = LSM_RESET;
    int unsigned since = 1000;  // clocks since lp_stallack last fell
    bit sa_q;
    forever begin
      ucie_lsm_state_e s;
      bit sr;
      bit sa;
      bit sa_prev = sa_q;
      @(env.pl.mb.mon_cb);
      if (env.pl.mb.mon_cb.rst_n !== 1'b1) begin
        prev = LSM_RESET;
        continue;
      end
      s = sts_decode(env.pl.mb.mon_cb.pl_state_sts);
      sr = env.pl.mb.mon_cb.pl_stallreq === 1'b1;
      sa = env.pl.mb.mon_cb.lp_stallack === 1'b1;
      if (sa_q && !sa) since = 0;
      else if (since < 1000) since++;
      sa_q = sa;
      if (prev == LSM_ACTIVE && s != LSM_ACTIVE) begin
        exit_to = s;
        n_exits++;
        if (s != LSM_L1 && since <= 10) n_after++;
        if (s inside {LSM_RETRAIN, LSM_LINKRESET, LSM_DISABLED} && (sr || sa))
          `uvm_error(get_type_name(), $sformatf({"Active -> %s with a stall handshake under way ",
                     "(pl_stallreq %0b, lp_stallack %0b)"}, s.name(), sr, sa))
        if (s == LSM_LINKERROR && sr) n_le_stall++;
      end
      if (prev == LSM_LINKERROR && s == LSM_RESET && sr)
        `uvm_error(get_type_name(), "LinkError -> Reset with pl_stallreq still high")
      // The drain: pl_trdy follows a lp_stallack still low (sampled a clock
      // before) with pl_stallreq high.
      if (s == LSM_LINKERROR && !trdy_forced && env.pl.mb.mon_cb.pl_trdy === 1'b1 &&
          (!sr || sa_prev))
        `uvm_error(get_type_name(), $sformatf({"the model drove pl_trdy high in LinkError with ",
                   "no stall handshake to drain (pl_stallreq %0b, lp_stallack %0b a clock ",
                   "before)"}, sr, sa_prev))
      prev = s;
    end
  endtask

  // Wait (bounded) until the link is Active with no event running and a stall
  // is waiting for lp_stallack.
  local task wait_stall();
    int unsigned n;
    while (!stall_waiting() && n++ < 50000) @(env.pl.mb.mon_cb);
    if (n >= 50000) `uvm_error(get_type_name(), "no stall waited for lp_stallack in Active")
    else n_hit++;
  endtask

  local function bit stall_waiting();
    return env.lsm.drv.idle() && env.lsm.drv.state == LSM_ACTIVE && env.lsm.drv.link_active &&
           env.pl.mb.mon_cb.pl_stallreq === 1'b1 && env.pl.mb.mon_cb.lp_stallack !== 1'b1;
  endfunction

  // As wait_stall, preferring (for up to 5000 clocks) a stall with a flit
  // presented and pl_trdy low, a flit the stub keeps up until it transfers
  // (hold_present), so lp_stallack cannot come yet. Returns whether it found
  // one; otherwise it waits for the start of a stall, so the whole of
  // stall_ack is still ahead.
  local task wait_stall_held(output bit held);
    int unsigned n;
    held = 1'b0;
    while (n++ < 5000) begin
      held = stall_waiting() && env.pl.mb.mon_cb.lp_valid === 1'b1 &&
             env.pl.mb.mon_cb.pl_trdy !== 1'b1;
      if (held) break;
      @(env.pl.mb.mon_cb);
    end
    if (held) begin
      n_hit++;
      return;
    end
    n = 0;
    while (env.pl.mb.mon_cb.pl_stallreq === 1'b1 && n++ < 50000) @(env.pl.mb.mon_cb);
    wait_stall();
  endtask

  // Wait (bounded) until nothing is under way and the link is Active again.
  local task settle();
    int unsigned n;
    while (!(env.lsm.drv.idle() && env.pl.plan.size() == 0) && n++ < 100000)
      @(env.pl.lsm.mon_cb);
    if (n >= 100000) `uvm_error(get_type_name(), "a request or event never finished")
    wait_active();
  endtask

  local task ask(ucie_lsm_req_e r);
    ucie_pl_stub::plan_t p;
    p.in = LSM_ACTIVE;
    p.req = r;
    p.up = -1;
    p.ignore = 1'b0;
    env.pl.plan.push_back(p);
  endtask

  local function void expect_exit(ucie_lsm_state_e s, string what);
    if (exit_to != s)
      `uvm_error(get_type_name(), {what, ": the link left Active for ", exit_to.name(),
                                   ", not ", s.name()})
  endfunction

  // LinkError does not wait for the Protocol Layer's lp_stallack (r3.0
  // §10.3.3.7: "It is not required to complete the stallreq/ack handshake
  // before entering this state"; Table 10-3 lp_linkerror: "immediate action").
  // Checked only when the stub acknowledges late enough to tell.
  local function void expect_le_early(int unsigned n0, string what);
    if (stall_ack >= 20 && n_le_stall == n0)
      `uvm_error(get_type_name(), {what, ": LinkError was not entered while the stall ",
                                   "waited for lp_stallack"})
  endfunction

  local task directed();
    ucie_lsm_ev_e kinds[3] = '{LSM_EV_RETRAIN, LSM_EV_LINK_RESET, LSM_EV_DISABLED};
    int unsigned  le_mid;
    int unsigned  n0;
    foreach (kinds[i]) begin
      wait_active();
      wait_stall();
      cev(kinds[i]);
    end
    for (int k = 0; k < 5 && n_le_stall == 0; k++) begin
      wait_active();
      wait_stall();
      cev(LSM_EV_LINKERROR);
    end
    if (n_le_stall == 0)
      `uvm_error(get_type_name(), "no LinkError was entered during a stall handshake")
    // A LinkError at a flit boundary while a stall waits.
    le_mid = env.lsm_cfg.le_mid_flit_pct;
    env.lsm_cfg.le_mid_flit_pct = 0;
    wait_active();
    wait_stall();
    n0 = n_le_stall;
    cev(LSM_EV_LINKERROR);
    expect_le_early(n0, "LinkError at a flit boundary during a stall");
    env.lsm_cfg.le_mid_flit_pct = le_mid;
    // A PM entry after a stall (its own stall at a closed gate), and the exit.
    wait_active();
    wait_stall();
    cev(LSM_EV_L1_ENTRY);
    cev(LSM_EV_L1_EXIT);
  endtask

  local task req_cases();
    int unsigned n0;
    int unsigned le0;
    // LinkReset requested while an Adapter Retrain waits for the stall.
    wait_active();
    wait_stall();
    fork
      cev(LSM_EV_RETRAIN);
      begin
        repeat (4) @(env.pl.mb.mon_cb);
        ask(LSM_REQ_LINKRESET);
      end
    join
    settle();
    expect_exit(LSM_LINKRESET, "LinkReset request during a Retrain's wait");
    // lp_linkerror while an Adapter LinkReset waits for the stall.
    wait_stall();
    n0 = env.pl.n_le_answered;
    le0 = n_le_stall;
    fork
      cev(LSM_EV_LINK_RESET);
      begin
        repeat (4) @(env.pl.mb.mon_cb);
        env.pl.linkerror_req = 1'b1;
        while (env.pl.n_le_answered == n0 && env.pl.linkerror_req) @(env.pl.mb.mon_cb);
        env.pl.linkerror_req = 1'b0;
      end
    join
    settle();
    expect_exit(LSM_LINKERROR, "lp_linkerror during a LinkReset's wait");
    expect_le_early(le0, "lp_linkerror during a LinkReset's wait");
    // A Disabled request during a stall, no event running.
    wait_stall();
    ask(LSM_REQ_DISABLED);
    settle();
    expect_exit(LSM_DISABLED, "Disabled request during a stall");
  endtask

  // lp_linkerror dropped before LinkError for a LinkReset or Disabled
  // request (see the header). Between events the LinkError leaves the link in
  // Reset; the test's own LSM_EV_LINKERROR then brings it up.
  local task le_drop_cases();
    ucie_lsm_req_e rs[2] = '{LSM_REQ_LINKRESET, LSM_REQ_DISABLED};
    foreach (rs[i]) for (int ev = 0; ev < 2; ev++) begin
      int unsigned d0 = env.pl.n_le_dropped;
      int unsigned le0 = n_le_stall;
      int unsigned n;
      bit held;
      string what = {"lp_linkerror dropped for ", rs[i].name()};
      if (ev) what = {what, " during a Retrain's wait"};
      wait_active();
      wait_stall_held(held);
      if (held) n_le_drop_held++;
      env.pl.le_drop = 1;
      env.pl.le_drop_req = rs[i];
      fork
        if (ev) cev(LSM_EV_RETRAIN);
        begin
          if (ev) repeat (4) @(env.pl.mb.mon_cb);
          env.pl.linkerror_req = 1'b1;
          while (env.pl.linkerror_req) @(env.pl.mb.mon_cb);
        end
      join
      while (!(env.lsm.drv.idle() && env.pl.plan.size() == 0) && n++ < 100000)
        @(env.pl.lsm.mon_cb);
      if (n >= 100000) `uvm_error(get_type_name(), {what, ": the request never finished"})
      env.pl.le_drop = 0;
      if (env.pl.n_le_dropped == d0)
        `uvm_error(get_type_name(), {what, ": the stub's lp_linkerror reached LinkError undropped"})
      expect_exit(LSM_LINKERROR, what);
      expect_le_early(le0, what);
      if (env.lsm.drv.state != LSM_ACTIVE) cev(LSM_EV_LINKERROR);
      wait_active();
    end
  endtask

  // Adapter LinkErrors mid-flit with a stall open and a TX flit part-way (see
  // the header). The stub counts the flits so cut (n_cut_stalled). Meanwhile
  // pl_trdy is random at 25 %, so a flit lasts long enough to be caught.
  local task le_mid_cases();
    int unsigned    le_mid = env.lsm_cfg.le_mid_flit_pct;
    ucie_fdi_trdy_e pol = env.fdi_cfg.trdy_policy;
    int unsigned    pct = env.fdi_cfg.trdy_pct;
    env.lsm_cfg.le_mid_flit_pct = 100;
    env.fdi_cfg.trdy_policy = UCIE_TRDY_RANDOM;
    env.fdi_cfg.trdy_pct = 25;
    for (int k = 0; k < 40 && env.pl.n_cut_stalled < 3; k++) begin
      int unsigned n;
      wait_active();
      while (!(stall_waiting() && env.fdi_cfg.gate.tx_busy) && n++ < 50000) @(env.pl.mb.mon_cb);
      if (n >= 50000) continue;
      n_hit++;
      cev(LSM_EV_LINKERROR);
    end
    env.lsm_cfg.le_mid_flit_pct = le_mid;
    env.fdi_cfg.trdy_policy = pol;
    env.fdi_cfg.trdy_pct = pct;
    wait_active();
  endtask

  task events();
    fork
      watch();
    join_none
    case (mode)
      "directed": directed();
      "req":      req_cases();
      "le_drop":  le_drop_cases();
      "le_mid":   le_mid_cases();
      default: ;
    endcase
    super.events();
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (mode != "random" && n_hit < 3)
      `uvm_error(get_type_name(), $sformatf("only %0d exits started during a stall", n_hit))
    if (hold && env.pl.n_kept == 0)
      `uvm_error(get_type_name(), "no flit presented at pl_stallreq was kept up and accepted")
    if (mode == "le_mid" && env.pl.n_cut_stalled == 0)
      `uvm_error(get_type_name(), "no LinkError cut a TX flit with pl_stallreq up")
    if (mode == "le_mid" && drain && keep && !ignore && env.pl.n_drained == 0)
      `uvm_error(get_type_name(), "no flit cut by LinkError was drained to its end")
    if (mode == "le_mid" && (ignore || !drain) && env.pl.n_stall_unacked == 0)
      `uvm_error(get_type_name(), "no stall handshake was abandoned in LinkError")
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({"exits from Active %0d, started during a stall %0d, ",
              "within 10 clocks of a stall's end %0d, LinkErrors entered during one %0d, ",
              "stalls %0d, flits kept up through pl_stallreq and accepted %0d, lp_linkerror ",
              "dropped before LinkError %0d (%0d with a flit held), TX flits cut by LinkError ",
              "with pl_stallreq up %0d, flits drained in LinkError %0d, stalls ended ",
              "unacknowledged %0d"}, n_exits, n_hit, n_after, n_le_stall, env.fdi.mon.n_stalls,
              env.pl.n_kept, env.pl.n_le_dropped, n_le_drop_held, env.pl.n_cut_stalled,
              env.pl.n_drained, env.pl.n_stall_unacked), UVM_NONE)
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
// (+neg=dllp|retimer|stream|nop_tx|corrupt_mid|corrupt_h0|corrupt_proto|clk_ack|
// irdy_reset|wake|wake_held, see ucie_pl_stub::bad; corrupt_mid and
// corrupt_h0 need an FDI of 128 B or less), or the top breaks the Adapter
// (ucie_fdi_selftest_top): with +neg=xfer it forces pl_trdy high for a clock
// while the stub presents a flit in Retrain (needs an FDI of 256 B or more,
// where that transfer is a whole flit), with +neg=trdy_down it forces pl_trdy
// high for a clock in Retrain with no flit presented, and with +neg=trdy_le
// in LinkError with no stall handshake (FDI-R43 either way: pl_trdy only in
// Active, or in LinkError while pl_stallreq is high; r3.0 Table 10-3), with
// +neg=le_exit it reports Reset
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
      "nop_tx":  catcher.rule = "FDI-R45";
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
      "trdy_down", "trdy_le": catcher.rule = "FDI-R43";
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
      "trdy_down", "trdy_le": begin
        nev(neg == "trdy_down" ? LSM_EV_RETRAIN : LSM_EV_LINKERROR);
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

`uvm_analysis_imp_decl(_act)
`uvm_analysis_imp_decl(_pas)

// Compares the flits of two monitors on the same FDI, one by one: the active
// agent's and a passive one's (ucie_fdi_reuse_test). They publish in the same
// clock, in either order, so a flit waits only for its twin.
class ucie_fdi_flit_cmp extends uvm_component;
  `uvm_component_utils(ucie_fdi_flit_cmp)

  uvm_analysis_imp_act #(ucie_flit_item, ucie_fdi_flit_cmp) act_imp;
  uvm_analysis_imp_pas #(ucie_flit_item, ucie_fdi_flit_cmp) pas_imp;
  int unsigned n_match;
  local ucie_flit_item act_q[$];
  local ucie_flit_item pas_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    act_imp = new("act_imp", this);
    pas_imp = new("pas_imp", this);
  endfunction

  function void write_act(ucie_flit_item f);
    pair(f, pas_q, act_q);
  endfunction

  function void write_pas(ucie_flit_item f);
    pair(f, act_q, pas_q);
  endfunction

  local function void pair(ucie_flit_item f, ref ucie_flit_item other[$],
                           ref ucie_flit_item mine[$]);
    if (other.size() == 0) begin
      mine.push_back(f);
      return;
    end
    if (other[0].dir != f.dir || !other[0].same_payload(f) || other[0].data[0] != f.data[0])
      `uvm_error(get_type_name(), {"the passive monitor's flit differs from the active one's: ",
                                   f.convert2string(), " vs ", other[0].convert2string()})
    else
      n_match++;
    void'(other.pop_front());
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (act_q.size() != 0 || pas_q.size() != 0)
      `uvm_error(get_type_name(), $sformatf(
                 "%0d flits of the active monitor and %0d of the passive one unmatched",
                 act_q.size(), pas_q.size()))
  endfunction
endclass

// Counts what a link-state monitor sees (ucie_fdi_reuse_test): entries to each
// state, and the clocks from a Reset entered after a link-down to
// pl_inband_pres, the restart on the Adapter's own decision (the shortest
// one).
class ucie_fdi_reuse_obs implements ucie_lsm_observer;
  int unsigned n_enter[ucie_lsm_state_e];
  int unsigned min_restart = '1;
  int unsigned n_restart;
  local int unsigned down_cycles;  // clocks in Reset after a link-down; 0: none
  virtual function void observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev);
    if (!cur.rst_n) begin
      down_cycles = 0;
      return;
    end
    if (cur.sts != prev.sts) n_enter[cur.sts] = n_enter.exists(cur.sts) ? n_enter[cur.sts] + 1 : 1;
    if (cur.sts == LSM_RESET && prev.sts inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED})
      down_cycles = 1;
    else if (down_cycles != 0 && cur.sts == LSM_RESET && !cur.inband_pres)
      down_cycles++;
    else if (down_cycles != 0) begin
      if (cur.inband_pres && down_cycles < min_restart) min_restart = down_cycles;
      if (cur.inband_pres) n_restart++;
      down_cycles = 0;
    end
  endfunction
  function int unsigned n(ucie_lsm_state_e s);
    return n_enter.exists(s) ? n_enter[s] : 0;
  endfunction
endclass

// The model as a second consumer uses it, on the events test's traffic and
// events (mid-flit LinkErrors included) plus three more LinkErrors. UCIe r3.0
// has one FDI, and one link state, per protocol stack (§10.2, §10.2.8,
// §10.3.3.8). +reuse=:
//  passive   a passive set of monitors (mainband and link-state agents with
//            is_active 0, so no gate) on the same interfaces as the active
//            model: it must publish the same flits, compared one by one, and
//            count the same cancels, stalls and abandoned flits, with no error.
//  two_link  a second link (env1: FDI 1 and its own link-state interface) with
//            traffic of its own and only LinkErrors as events; its state must
//            move by itself (no Retrain, LinkReset or Disabled, which only link
//            0 runs). Both cfgs set le_mid_flit_pct 100, and the run gives
//            +ucie_le_mid_flit_pct@uvm_test_top.env1.lsm=0, which must reach
//            link 1 only: its LinkErrors fall at flit boundaries.
//  mirror    two FDIs under one link state (n_phy 2, the mirrored mode): FDI 1
//            must report the same pl_state_sts as FDI 0 every clock, and be
//            stalled before the L1 entry too (the top acknowledges for it);
//  park      the same with park_idle_phy: FDI 1 stays in Reset, never stalled.
//  restart   sw_restart_delay set to 777 in the cfg (or +expect_restart=N, to
//            check a value given by plusarg) must stand, and every software
//            restart after a link-down must take at least that long.
// In every mode the stub samples pl_protocol and pl_protocol_flitfmt in Reset
// before it requests Active and checks pl_stream with pl_valid.
class ucie_fdi_reuse_test extends ucie_fdi_events_test;
  `uvm_component_utils(ucie_fdi_reuse_test)

  string                mode = "passive";
  int unsigned          exp_restart = 777;
  ucie_fdi_selftest_env env1;
  ucie_fdi_agent        pfdi;
  ucie_lsm_agent        plsm;
  ucie_fdi_flit_cmp     cmp;
  ucie_fdi_reuse_obs    obs0, obs1;
  int unsigned          n_mirror_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    super.configure();
    void'($value$plusargs("reuse=%s", mode));
    case (mode)
      "passive", "two_link": ;
      "mirror": env.lsm_cfg.n_phy = 2;
      "park": begin
        env.lsm_cfg.n_phy = 2;
        env.lsm_cfg.park_idle_phy = 1'b1;
      end
      "restart": begin
        void'($value$plusargs("expect_restart=%d", exp_restart));
        env.lsm_cfg.sw_restart_delay = 777;
      end
      default: `uvm_fatal(get_type_name(), {"+reuse: unknown mode ", mode})
    endcase
    env.fdi1_cfg.beat_bytes = env.fdi_cfg.beat_bytes;
    env.fdi1_cfg.trdy_policy = env.fdi_cfg.trdy_policy;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    obs0 = new();
    if (mode == "passive") begin
      ucie_fdi_cfg pc = ucie_fdi_cfg::type_id::create("pfdi_cfg");
      ucie_lsm_cfg lc = ucie_lsm_cfg::type_id::create("plsm_cfg");
      pc.is_active = 1'b0;
      pc.beat_bytes = env.fdi_cfg.beat_bytes;
      pc.stream = env.fdi_cfg.stream;
      lc.is_active = 1'b0;
      lc.protocol = env.lsm_cfg.protocol;
      pfdi = ucie_fdi_agent::type_id::create("pfdi", this);
      pfdi.cfg = pc;
      plsm = ucie_lsm_agent::type_id::create("plsm", this);
      plsm.cfg = lc;
      plsm.phy.push_back(pfdi);
      cmp = ucie_fdi_flit_cmp::type_id::create("cmp", this);
    end
    if (mode == "two_link") begin
      env1 = ucie_fdi_selftest_env::type_id::create("env1", this);
      env1.fdi_cfg.phy = 1;
      env1.lsm_key = "fdi_lsm1";
      env1.fdi_cfg.beat_bytes = env.fdi_cfg.beat_bytes;
      env1.fdi_cfg.trdy_policy = env.fdi_cfg.trdy_policy;
      env1.fdi_cfg.partial_beat_pct = env.fdi_cfg.partial_beat_pct;
      env1.lsm_cfg.le_mid_flit_pct = 100;
      obs1 = new();
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.lsm.mon.add_observer(obs0);
    if (mode == "passive") begin
      env.fdi.mon.ap_rx.connect(cmp.act_imp);
      env.fdi.mon.ap_tx.connect(cmp.act_imp);
      pfdi.mon.ap_rx.connect(cmp.pas_imp);
      pfdi.mon.ap_tx.connect(cmp.pas_imp);
    end
    if (mode == "two_link") env1.lsm.mon.add_observer(obs1);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    if (mode inside {"mirror", "park"})
      fork
        watch_mirror();
      join_none
    fork
      traffic();
      begin
        events();
        repeat (3) begin
          ev_on(env, LSM_EV_IDLE);
          ev_on(env, LSM_EV_LINKERROR);
        end
      end
      begin
        if (mode == "two_link") traffic_on(env1, n_flits);
      end
      begin
        if (mode == "two_link")
          repeat (3) begin
            ev_on(env1, LSM_EV_IDLE);
            ev_on(env1, LSM_EV_LINKERROR);
          end
      end
    join
    drain();
    if (mode == "two_link") drain_on(env1);
    phase.drop_objection(this);
  endtask

  local task ev_on(ucie_fdi_selftest_env e, ucie_lsm_ev_e kind);
    ucie_lsm_event_seq s = ucie_lsm_event_seq::of(kind);
    s.start(e.lsm.sqr);
  endtask

  // Mirrored mode: FDI 1 reports FDI 0's status (Reset when parked), every
  // clock, until the test ends.
  local task watch_mirror();
    forever begin
      logic [3:0] s0, s1;
      @(env.fdi.vif.mon_cb);
      s0 = env.fdi.vif.mon_cb.pl_state_sts;
      s1 = env.fdi1.vif.mon_cb.pl_state_sts;
      if (env.fdi.vif.mon_cb.rst_n === 1'b1 && s1 !== (mode == "park" ? FDI_STS_RESET : s0)) begin
        if (n_mirror_bad++ == 0)
          `uvm_error(get_type_name(), $sformatf("FDI 1 reports pl_state_sts %0h with FDI 0 at %0h",
                                                s1, s0))
      end
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.pl.n_proto == 0) `uvm_error(get_type_name(), "the stub never sampled pl_protocol")
    if (env.pl.n_stream == 0) `uvm_error(get_type_name(), "the stub never checked pl_stream")
    case (mode)
      "passive": begin
        ucie_fdi_monitor a = env.fdi.mon, p = pfdi.mon;
        if (cmp.n_match == 0) `uvm_error(get_type_name(), "no flit compared")
        if (a.n_tx_flits != p.n_tx_flits || a.n_rx_flits != p.n_rx_flits ||
            a.n_rx_cancels != p.n_rx_cancels || a.n_stalls != p.n_stalls ||
            a.n_tx_abandoned != p.n_tx_abandoned || a.n_rx_abandoned != p.n_rx_abandoned)
          `uvm_error(get_type_name(), $sformatf({"active and passive monitors differ: TX %0d/%0d, ",
                     "RX %0d/%0d, cancels %0d/%0d, stalls %0d/%0d, abandoned TX %0d/%0d, RX ",
                     "%0d/%0d"}, a.n_tx_flits, p.n_tx_flits, a.n_rx_flits, p.n_rx_flits,
                     a.n_rx_cancels, p.n_rx_cancels, a.n_stalls, p.n_stalls, a.n_tx_abandoned,
                     p.n_tx_abandoned, a.n_rx_abandoned, p.n_rx_abandoned))
      end
      "two_link": begin
        if (env1.sb.n_tx == 0) `uvm_error(get_type_name(), "no flit looped back on link 1")
        if (env.lsm_cfg.le_mid_flit_pct != 100 || env1.lsm_cfg.le_mid_flit_pct != 0)
          `uvm_error(get_type_name(), $sformatf({"le_mid_flit_pct %0d on link 0, %0d on link 1; ",
                     "expected 100 and 0 (+ucie_le_mid_flit_pct@uvm_test_top.env1.lsm=0)"},
                     env.lsm_cfg.le_mid_flit_pct, env1.lsm_cfg.le_mid_flit_pct))
        if (env1.lsm.drv.n_le != 3 || env1.lsm.drv.n_le_mid_tx + env1.lsm.drv.n_le_mid_rx != 0)
          `uvm_error(get_type_name(), $sformatf(
                     "link 1: %0d LinkErrors, %0d mid-flit; expected 3, 0", env1.lsm.drv.n_le,
                     env1.lsm.drv.n_le_mid_tx + env1.lsm.drv.n_le_mid_rx))
        if (obs1.n(LSM_LINKERROR) != 3 || obs1.n(LSM_RETRAIN) != 0 ||
            obs1.n(LSM_LINKRESET) != 0 || obs1.n(LSM_DISABLED) != 0)
          `uvm_error(get_type_name(), $sformatf({"link 1 entered LinkError %0d, Retrain %0d, ",
                     "LinkReset %0d, Disabled %0d times; expected 3, 0, 0, 0"},
                     obs1.n(LSM_LINKERROR), obs1.n(LSM_RETRAIN), obs1.n(LSM_LINKRESET),
                     obs1.n(LSM_DISABLED)))
        if (obs0.n(LSM_RETRAIN) == 0 || obs0.n(LSM_LINKRESET) == 0 || obs0.n(LSM_DISABLED) == 0)
          `uvm_error(get_type_name(), "link 0 missed a Retrain, LinkReset or Disabled")
      end
      "mirror", "park": begin
        if (env.fdi1 == null || obs0.n(LSM_ACTIVE) == 0)
          `uvm_error(get_type_name(), "no mirrored FDI, or the link never came up")
        else if ((env.fdi1.mon.n_stalls == 0) != (mode == "park"))
          `uvm_error(get_type_name(), $sformatf("%0d stall handshakes on FDI 1 in mode %s",
                                                env.fdi1.mon.n_stalls, mode))
      end
      "restart": begin
        if (env.lsm_cfg.sw_restart_delay != exp_restart)
          `uvm_error(get_type_name(), $sformatf("sw_restart_delay is %0d, expected %0d",
                                                env.lsm_cfg.sw_restart_delay, exp_restart))
        if (obs0.n_restart == 0 || obs0.min_restart < exp_restart)
          `uvm_error(get_type_name(), $sformatf({"%0d restarts after a link-down, the shortest ",
                     "%0d clocks; expected some, none shorter than %0d"}, obs0.n_restart,
                     obs0.min_restart, exp_restart))
      end
      default: ;
    endcase
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({"reuse %s: %0d flits compared, %0d pl_protocol ",
              "samples, %0d pl_stream checks, %0d restarts (shortest %0d clocks)"}, mode,
              cmp != null ? cmp.n_match : 0, env.pl.n_proto, env.pl.n_stream, obs0.n_restart,
              obs0.min_restart), UVM_NONE)
  endfunction
endclass
