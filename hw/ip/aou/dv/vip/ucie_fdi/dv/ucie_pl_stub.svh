// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// A minimal Protocol Layer on top of the model, as a stand-in for a design:
// it answers the FDI handshakes and loops every flit the Adapter delivers
// (the mainband monitor's ap_rx) back on its TX side.
//  - lp_clk_ack and lp_rx_active_sts follow their requests one clock later
//    (UCIe r3.0 §10.2.3.2, §10.2.7); with `hs_lag` they fall that many clocks
//    after their request does (rule 3 and rule 4 give no time); lp_clk_ack
//    rises `clk_ack_delay` clocks after pl_clk_req (at least one). A
//    pl_clk_req that falls before lp_clk_ack has answered it is an error: the
//    handshake is a full one, and only the acknowledge shows the Protocol
//    Layer saw what the request covers (§10.2.3.2 rules 3 and 5).
//  - With `clk_gate` the stub gates its clock whenever r3.0 §10.2.3 lets it:
//    in Reset, LinkReset, Disabled or L1 with pl_clk_req and lp_clk_ack low,
//    nothing presented, no stall under way and nothing left to do (in Reset:
//    no pl_inband_pres seen, or Active already requested; in L1: no PM exit
//    of its own). While gated it sees nothing and changes nothing until
//    pl_clk_req wakes it (its lp_clk_ack). A status change it would miss is
//    an error: one to anything but LinkError without pl_clk_req in the clock
//    before (§10.2.3.2 rule 7, reported as FDI-R22), and a second change
//    after a LinkError entered that way, before the stub has acknowledged
//    (rule 6, FDI-R21).
//  - lp_wake_req is high while the link is wanted up: in Reset once
//    pl_inband_pres is 1, and in Active and Retrain (§10.2.3.1); low in L1, so
//    the Adapter's PM exit stays its own (the self-test's L1 events), unless
//    `wake_in_l1` asks the stub to start the exit itself (r3.0 §10.2.9).
//  - `linkerror_req` raises lp_linkerror in `linkerror_in` (Active by
//    default; LSM_UNKNOWN: any state but LinkError; out of Active from the
//    state's second clock, in Reset with `linkerror_up` 0 or 1 only before
//    or after pl_inband_pres) and holds it until the Adapter reports
//    LinkError (r3.0 Table 10-3, Table 10-4: answered in every state), then
//    clears itself; with `linkerror_hold` it keeps it high that many clocks
//    into LinkError, which the Adapter must sit out ("It must stay there as
//    long as lp_linkerror=1"). Raised in Reset, LinkReset, Disabled or L1 it
//    comes with lp_wake_req (§10.2.3.1), kept until LinkError. No LinkError
//    within `req_bound` clocks is an error. With `le_drop` it drops
//    lp_linkerror after that many clocks if LinkError is not reported yet and
//    requests `le_drop_req` (LinkReset or Disabled) in its place, as a plan
//    entry that LinkError also ends (r3.0 does not require lp_linkerror held
//    until LinkError, and the Adapter has seen the assertion); n_le_dropped
//    counts them.
//  - `plan` lists LinkReset and Disabled requests to make on lp_state_req,
//    in order, each in a given state (in Reset after a NOP of at least a
//    clock, before or after pl_inband_pres as the entry says; Table 10-4 note
//    a), with lp_wake_req (§10.2.3.1). One Table 10-4 answers ("Yes") must
//    reach its state within `req_bound` clocks, through Active or not; the
//    stub then stops requesting. LinkError ends it too, but only after the
//    stub raised lp_linkerror meanwhile: r3.0 lets an Adapter enter LinkError
//    from any state on an internal request (§10.3.3.5 rule 4, §10.3.3.6,
//    §10.3.3.8, which also sends a LinkReset or Disabled the remote die never
//    answers to LinkError), so a general Protocol Layer must accept it, but
//    the self-test starts no Adapter LinkError while a request is on, and
//    one here would mean the request was answered wrongly. One Table 10-4 ignores
//    (`ignore`) is made for 20 clocks, and the status must not become the
//    requested state then or in the 20 clocks after.
//  - With `clk_gate`, a request of its own (lp_linkerror, a plan entry) due
//    in a state where it is clock gated wakes the stub after `gated_wait`
//    gated clocks, as lp_wake_req needs no clock (r3.0 §10.2.3.1);
//    n_le_gated and n_req_gated count them.
//  - With `exit_pl` (the Adapter's cfg.down_exit_on PL) the Adapter must
//    leave LinkReset, Disabled and LinkError for Reset only after the stub
//    asked with Active (`held_active`), and LinkError not before
//    `le_min_res` clocks there (r3.0 §10.3.3.5 rule 1, §10.3.3.6,
//    §10.3.3.7).
//  - lp_state_req: in Reset NOP, then Active once pl_wake_ack is high
//    (§10.2.8 step 2, §10.3.3.1 rule 1); Active in Active; in Retrain NOP for
//    a clock, then Active (§10.3.3.4 rule 1); L1 in L1; NOP elsewhere. With `wake_late` it requests
//    Active in Reset without waiting for pl_wake_ack and raises lp_wake_req a
//    clock after the request (r3.0 §10.2.3.1 rule 5 orders them no further).
//  - Requests around Reset (UCIe r3.0 §10.3.3.1 rule 1, Table 10-4, §10.3.3.8):
//    with `held_active` it requests Active (with lp_wake_req) in LinkError,
//    LinkReset and Disabled, the exit request there, and holds it into Reset
//    until pl_inband_pres has been 1 for `held_cycles` clocks; only then NOP
//    for a clock and Active. Halfway through the hold it requests LinkReset
//    for a clock and then Active again: with no NOP in this Reset neither is
//    a request, and an Adapter that then enters LinkReset (within 20 clocks)
//    is an error. An Adapter that starts the Active entry (pl_rx_active_req)
//    while it holds is an error: a held Active is no request. With
//    `early_trigger` it gives NOP->Active in Reset before pl_inband_pres,
//    once per Reset and with chance `early_pct`, and returns to NOP 1 to 3
//    clocks later (or, half the time, holds Active, which then is its
//    request). Once it has been back at NOP for two clocks with
//    pl_inband_pres still 0, the withdrawn trigger is no request any more: an
//    Adapter that then raises pl_rx_active_req before the stub's next Active
//    is an error, unless `remote_first` says the Adapter may start the
//    handshake before the request. With `restart_bound` the Adapter must
//    raise pl_inband_pres within that many clocks of the trigger after a
//    link-down (the training-trigger policy). n_rx_first and n_rx_first_rt
//    count pl_rx_active_req rising in Reset and in Retrain before the stub
//    requested Active.
//  - TX: a flit starts only in Active with the Receiver active and pl_trdy
//    high, then runs to its end with no bubbles (§10.2.4). pl_stallreq is
//    acknowledged at the next flit boundary, a clock later at the earliest
//    (r3.0 §10.3.2 rules 4 and 8), or `stall_ack_delay` clocks after that
//    boundary (with `stall_ack_rand`, a random 0 to `stall_ack_delay` per
//    stall; rule 4 gives no time). A flit cut off when the Adapter leaves Active mid-flit is sent
//    again from its start, so the loopback loses nothing.
//  - With `early_present` a queued flit is presented (lp_valid, lp_irdy)
//    without waiting for pl_trdy, in Active and through Retrain and LinkError,
//    and for the first `down_present` clocks of LinkReset or Disabled (r3.0
//    §10.2.4: the Adapter just keeps pl_trdy low; Table 10-3 lp_irdy forbids
//    only Reset). After LinkError -> Reset lp_irdy stays up `irdy_linger` more
//    clocks, which Table 10-3 allows ("a few clocks"). Never with a stall
//    under way, nor in Reset otherwise, L1 or L2.
//  - With `hold_present` flits are presented as with `early_present`, and a
//    flit presented in Active is kept up until it transfers, through a
//    pl_stallreq that rises meanwhile. That is legal: a Protocol Layer may
//    present a flit and wait for pl_trdy (§10.2.4, Table 10-3 lp_irdy), and
//    §10.3.2 rule 7 makes the Adapter accept data presented before
//    lp_stallack, which then waits until nothing is presented (rule 6). If
//    the status leaves Active first, the flit is withdrawn (in LinkError the
//    Protocol Layer cleans up its data path, §10.3.3.7). n_kept counts the
//    flits presented when pl_stallreq was seen that then transferred.
//  - With `valid_alone` lp_valid toggles without lp_irdy between flits, which
//    transfers nothing (Table 10-3 lp_irdy).
//  - On a 512 or 1024 B FDI a TX transfer carries 2 or 4 flits; one sent
//    with fewer flits queued fills the other lanes with a Protocol Flit with
//    empty slots (UCIe r3.0 §10.3.1: valid data on the full width), here a
//    flit with a non-zero Protocol ID and an all-zero payload, which the
//    scoreboard skips.
//  - lp_stream is tied to `stream`; no DLLPs or Retimer credits. pl_stream,
//    relevant with pl_valid (r3.0 Table 10-3), must carry `stream` then.
//  - The negotiated protocol (r3.0 Table 10-3 pl_protocol_vld): pl_protocol
//    and pl_protocol_flitfmt are sampled and stored in Reset with
//    pl_protocol_vld and pl_inband_pres 1, kept until Reset with
//    pl_inband_pres 0, and must be `protocol` and Format 6. The stub requests
//    Active in Reset only once it holds them (§10.2.8 step 2: "permitted
//    ... to wait until pl_protocol_vld = 1 before requesting Active").
//  - With `tx_nop_pct` a TX transfer starts with a NOP flit (Protocol ID 00b,
//    the rest zero), which a CXL Protocol Layer may send (r3.0 Table 3-5; a
//    Streaming one never does), and which the scoreboard skips as an empty
//    flit.
//  - With `corrupt_pct`, a transfer of flits asks the Adapter to corrupt their
//    CRC (lp_corrupt_crc, UCIe r3.0 Table 10-3): with lp_valid on the last
//    transfer of the second 128B half, or of both halves; from 256 B up on the
//    one transfer. Only legal when the protocol includes CXL.cachemem.
//  - `bad` makes one deliberate violation, on the first beat of a flit after
//    the eighth one sent, for the negative tests of the model's checks
//    (ucie_fdi_neg_test): "dllp" an lp_dllp_valid pulse, "retimer" an
//    lp_retimer_crd pulse, "stream" a wrong lp_stream, "nop_tx" a NOP flit
//    (Protocol ID 00b, which a Streaming Protocol Layer never sends; r3.0
//    Table 3-5) in the first lane of a transfer; "corrupt_mid"
//    lp_corrupt_crc on a transfer that does not end a half, "corrupt_h0" on the
//    first half only (both up to 128 B), "corrupt_proto" a well-placed one
//    while the protocol has no CXL.cachemem; "clk_ack" an lp_clk_ack pulse
//    without pl_clk_req (once, in Active); "irdy_reset" a flit presented
//    through LinkReset and Disabled and into the Reset that follows (needs
//    `early_present`); "wake" requests Active in Reset with lp_wake_req
//    never raised; "wake_held" does the same but holds lp_wake_req through
//    LinkError (rule 3 allows that) and drops it on entry to the Reset that
//    follows, before its request there: a handshake over before the request
//    is not one used for it (r3.0 §10.2.3.1); "held_forever" holds an Active
//    request from a link-down into Reset for good, so the Adapter never sees
//    a request to leave Reset (no `held_cycles` check then); "wake_down" makes
//    the plan's requests in a clock-gated state without lp_wake_req, and
//    "wake_le" raises lp_linkerror there without it (r3.0 §10.2.3.1).
class ucie_pl_stub extends uvm_component;
  `uvm_component_utils(ucie_pl_stub)

  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) mb;
  virtual ucie_fdi_lsm_if lsm;
  int unsigned beat_bytes = 64;
  bit [7:0]    stream = UCIE_STREAM_S0_STREAMING;  // lp_stream, tied as an integration would
  bit [3:0]    protocol = UCIE_PROTO_STREAMING;    // the pl_protocol to expect
  int unsigned n_proto;      // pl_protocol samples taken (one per Reset with pl_inband_pres)
  int unsigned n_stream;     // RX beats whose pl_stream was checked

  uvm_analysis_imp #(ucie_flit_item, ucie_pl_stub) rx_imp;

  int unsigned n_sent;       // flits whose last beat transferred
  int unsigned n_restarted;  // flits cut off mid-flit and sent again
  int unsigned n_fill;       // empty flits sent to fill a wide transfer
  int unsigned tx_nop_pct;   // chance a TX transfer starts with a NOP flit (see above)
  int unsigned n_tx_nop;     // NOP flits sent
  string       bad;          // a deliberate violation (see above); "" for none
  bit          wake_in_l1;   // start a PM exit in L1 (lp_wake_req)
  bit          linkerror_req; // request a LinkError (lp_linkerror) once
  int unsigned corrupt_pct;  // chance a transfer of flits carries lp_corrupt_crc
  int unsigned n_corrupt;    // transfers sent with lp_corrupt_crc
  // Legal behaviours the model must accept (see above).
  bit          early_present;
  bit          hold_present;
  int unsigned n_kept;           // hold_present: flits presented at pl_stallreq, then sent
  int unsigned down_present = 4;
  int unsigned irdy_linger = 2;
  bit          valid_alone;
  int unsigned hs_lag;
  int unsigned linkerror_hold;
  bit          wake_late;
  bit          clk_gate;
  int unsigned clk_ack_delay = 1;
  int unsigned n_gated;          // clocks the stub spent clock gated
  bit          held_active;
  int unsigned held_cycles = 40;
  bit          early_trigger;
  int unsigned early_pct = 100;
  int unsigned restart_bound;
  int unsigned n_held;           // held Active requests released after held_cycles
  int unsigned n_early;          // early NOP->Active triggers given
  int unsigned n_restarts;       // ... of them after a link-down, answered by pl_inband_pres
  bit          remote_first;     // the Adapter may raise pl_rx_active_req before the request
  int unsigned n_other;          // held: LinkReset, then Active, given in Reset with no NOP
  int unsigned n_early_waits;    // Resets left after a withdrawn early trigger was checked
  int unsigned n_rx_first;       // pl_rx_active_req rises in Reset before the stub's Active
  int unsigned n_rx_first_rt;    // ... in Retrain
  int unsigned n_presented_down; // clocks a flit was presented outside Active
  int unsigned stall_ack_delay;  // clocks from the flit boundary to lp_stallack (see above)
  bit          stall_ack_rand;
  // Requests of its own (see the header).
  typedef struct {
    ucie_lsm_state_e in;      // the state to make it in
    ucie_lsm_req_e   req;     // LinkReset or Disabled
    int              up;      // in Reset: -1 any, 0 before pl_inband_pres, 1 after
    bit              ignore;  // Table 10-4 ignores it there
  } plan_t;
  plan_t           plan[$];
  ucie_lsm_state_e linkerror_in = LSM_ACTIVE;
  int              linkerror_up = -1;
  int unsigned     req_bound = 5000;
  int unsigned     gated_wait = 3;
  bit              exit_pl;
  int unsigned     le_min_res;
  int unsigned     n_down;       // plan requests answered ("Yes")
  int unsigned     n_ignored;    // plan requests ignored as Table 10-4 says
  int unsigned     n_le_answered; // lp_linkerror raised and answered
  int unsigned     n_le_gated;   // ... raised after waking itself from clock gating
  int unsigned     n_req_gated;  // plan requests made after waking itself
  int unsigned     n_exits;      // link-down states left on its Active request (exit_pl)
  int unsigned     le_drop;       // drop lp_linkerror after this many clocks (0: hold it)
  ucie_lsm_req_e   le_drop_req = LSM_REQ_LINKRESET;  // ... and request this instead
  int unsigned     n_le_dropped;  // lp_linkerror dropped before LinkError (le_drop)
  local bit [MAX_BEATS_PER_FLIT-1:0] cc_mask;  // the transfers of cur with lp_corrupt_crc
  bit          bad_done;

  local ucie_flit_item txq[$];
  local ucie_flit_item cur[$];  // the flits of the transfer, one per lane
  local int unsigned   beat;
  local bit            presenting;
  local bit            kept;       // hold_present: the flit presented was kept through pl_stallreq
  local bit            stallack;
  local bit            sa_armed;   // pl_stallreq seen at a flit boundary, lp_stallack due
  local int unsigned   sa_left;    // ... in this many clocks
  local bit            nop_seen;
  local ucie_lsm_state_e st;       // pl_state_sts as last seen
  local ucie_lsm_state_e st_from;  // ... and the state before it
  local int unsigned   st_cycles;  // clocks since st was entered
  local int unsigned   clk_low;    // clocks pl_clk_req has been low
  local int unsigned   rx_low;     // clocks pl_rx_active_req has been low
  local int unsigned   le_held;    // clocks lp_linkerror was held in LinkError
  local int unsigned   clk_high;   // clocks pl_clk_req has been high
  local bit            creq_q;     // pl_clk_req in the previous clock
  local bit            creq_h;     // ... as handshakes() last saw it
  local bit            clk_acked;  // lp_clk_ack has answered the pl_clk_req that is up
  local bit            frozen;     // clock gated (clk_gate)
  local ucie_lsm_state_e gst;      // pl_state_sts last seen while gated
  local bit            le_unseen;  // LinkError entered while gated with no pl_clk_req before
  local bit            inband_seen;
  local bit            holding;     // held_active: Active requested in a link-down state
  local int unsigned   held_up;     // ... clocks of it in Reset with pl_inband_pres 1
  local bit            held_err;    // ... reported the Adapter taking it
  local bit            early_done;  // early_trigger given (or passed up) in this Reset
  local int unsigned   early_left;  // clocks of Active left (early_trigger)
  local bit            early_hold;  // ... held until the status leaves Reset
  local int unsigned   trig_wait;   // clocks since an early trigger after a link-down, 0: none
  local bit            early_given; // an early trigger given and withdrawn in this Reset
  local int unsigned   early_quiet; // ... clocks of NOP since, pl_inband_pres 0
  local bit            early_armed; // ... long enough that it is no request any more
  local bit            rreq_q;      // pl_rx_active_req in the previous clock
  local bit            req_on;      // making plan[0]
  local bit            req_le;      // ... and lp_linkerror was raised meanwhile
  local int unsigned   req_wait;    // ... clocks since it started
  local int unsigned   ign_watch;   // clocks left to watch after an ignored request
  local ucie_lsm_state_e ign_st;    // ... the state it must not lead to
  local int unsigned   le_wait;     // clocks lp_linkerror has waited for LinkError; 0: none
  local bit            own_woke;    // woke itself for a request of its own
  local int unsigned   frozen_n;    // clocks gated with a request of its own due
  local bit            exit_asked;  // requested Active in this link-down state
  local bit            proto_held;  // pl_protocol and pl_protocol_flitfmt sampled and stored

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_imp = new("rx_imp", this);
  endfunction

  // A delivered flit, to be sent back: the payload with the Adapter-owned
  // bytes cleared and a non-zero Protocol ID (a protocol flit, never a NOP).
  function void write(ucie_flit_item t);
    ucie_flit_item c = ucie_flit_item::type_id::create("loopback");
    c.dir = UCIE_FDI_TX;
    c.copy_data(t);
    c.clear_adapter_bytes();
    if (c.data[0][7:6] == 2'b00) c.data[0][7:6] = 2'b11;
    txq.push_back(c);
  endfunction

  function bit idle();
    return txq.size() == 0 && cur.size() == 0;
  endfunction

  task run_phase(uvm_phase phase);
    drive_reset();
    forever begin
      @(lsm.mon_cb);
      if (lsm.mon_cb.rst_n !== 1'b1) begin
        txq.delete();
        cur.delete();
        drive_reset();
        continue;
      end
      if (clk_gate && gate_check()) begin
        handshakes();
        continue;
      end
      track_state(sts_decode(mb.mon_cb.pl_state_sts));
      inband_seen = lsm.mon_cb.pl_inband_pres === 1'b1;
      negotiated();
      handshakes();
      state_req(mb.mon_cb.pl_state_sts);
      linkerror(mb.mon_cb.pl_state_sts);
      requests();
      tx(mb.mon_cb.pl_state_sts);
    end
  endtask

  local function void drive_reset();
    lsm.lp_state_req <= 4'h0;
    lsm.lp_wake_req <= 1'b0;
    lsm.lp_clk_ack <= 1'b0;
    lsm.lp_rx_active_sts <= 1'b0;
    lsm.lp_linkerror <= 1'b0;
    mb.lp_valid <= 1'b0;
    mb.lp_irdy <= 1'b0;
    mb.lp_data <= '0;
    mb.lp_stallack <= 1'b0;
    mb.lp_corrupt_crc <= 1'b0;
    cc_mask = '0;
    mb.lp_stream <= stream;
    mb.lp_dllp <= '0;
    mb.lp_dllp_valid <= 1'b0;
    mb.lp_dllp_ofc <= 1'b0;
    mb.lp_retimer_crd <= 1'b0;
    beat = 0;
    presenting = 1'b0;
    kept = 1'b0;
    stallack = 1'b0;
    sa_armed = 1'b0;
    nop_seen = 1'b0;
    bad_done = 1'b0;
    st = LSM_RESET;
    st_from = LSM_RESET;
    st_cycles = 0;
    clk_low = 0;
    rx_low = 0;
    le_held = 0;
    clk_high = 0;
    creq_q = 1'b0;
    creq_h = 1'b0;
    clk_acked = 1'b0;
    frozen = 1'b0;
    le_unseen = 1'b0;
    inband_seen = 1'b0;
    holding = 1'b0;
    held_up = 0;
    held_err = 1'b0;
    early_done = 1'b0;
    early_left = 0;
    early_hold = 1'b0;
    trig_wait = 0;
    early_given = 1'b0;
    early_quiet = 0;
    early_armed = 1'b0;
    rreq_q = 1'b0;
    req_on = 1'b0;
    req_wait = 0;
    ign_watch = 0;
    le_wait = 0;
    own_woke = 1'b0;
    frozen_n = 0;
    exit_asked = 1'b0;
    proto_held = 1'b0;
  endfunction

  // clk_gate: whether the stub is clock gated this clock, and the status
  // changes it would miss (see above). Gating starts only from a state the
  // stub has seen for a few clocks, with nothing to do.
  local function bit gate_check();
    bit creq = lsm.mon_cb.pl_clk_req === 1'b1;
    bit ack = lsm.mon_cb.lp_clk_ack === 1'b1;
    ucie_lsm_state_e s = sts_decode(mb.mon_cb.pl_state_sts);
    if (!frozen) begin
      bit asked = lsm.mon_cb.lp_state_req === req_code(LSM_REQ_ACTIVE);
      bit idle = st == LSM_RESET ? !inband_seen || asked : st == LSM_L1 ? !wake_in_l1 : 1'b1;
      // Awake for a request of its own: stays awake until it is made.
      if (own_woke) begin
        creq_q = creq;
        return 1'b0;
      end
      if (!(lsm_gated(st) && s == st && !creq && !ack && idle && st_cycles >= 2 && !presenting &&
            mb.mon_cb.lp_valid !== 1'b1 && !stallack && mb.mon_cb.pl_stallreq !== 1'b1)) begin
        creq_q = creq;
        return 1'b0;
      end
      frozen = 1'b1;
      gst = st;
      le_unseen = 1'b0;
      frozen_n = 0;
    end
    if (s != gst && !creq_q) begin
      if (s == LSM_LINKERROR && !le_unseen) le_unseen = 1'b1;
      else if (le_unseen)
        `uvm_error(get_type_name(), $sformatf({"FDI-R21 (Protocol Layer stub, clock gated): ",
                   "LinkError -> %s before the stub acknowledged a pl_clk_req"}, s.name()))
      else
        `uvm_error(get_type_name(), $sformatf({"FDI-R22 (Protocol Layer stub, clock gated): ",
                   "pl_state_sts %s -> %s with no pl_clk_req to wake the stub"}, gst.name(),
                   s.name()))
    end
    gst = s;
    creq_q = creq;
    if (ack || st == LSM_L1 && wake_in_l1) begin
      // Clocks back (pl_clk_req, or the stub's own PM exit, which needs no
      // clock: lp_wake_req): from the next clock it follows the link again.
      frozen = 1'b0;
      return 1'b1;
    end
    // A request of its own due here wakes it the same way (lp_wake_req).
    if (s == gst && own_due(s) && ++frozen_n >= gated_wait) begin
      frozen = 1'b0;
      own_woke = 1'b1;
      return 1'b1;
    end
    n_gated++;
    return 1'b1;
  endfunction

  local function void track_state(ucie_lsm_state_e s);
    if (s != st && exit_pl && s == LSM_RESET &&
        st inside {LSM_LINKRESET, LSM_DISABLED, LSM_LINKERROR}) begin
      if (!exit_asked)
        `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: the Adapter left %s for ",
                   "Reset without its Active request (down_exit_on PL; UCIe r3.0 Table 10-4, ",
                   "§10.3.3.5 rule 1, §10.3.3.6, §10.3.3.7)"}, st.name()))
      // st_cycles counts from 0 on the first clock that showed LinkError.
      else if (st == LSM_LINKERROR && st_cycles + 1 < le_min_res)
        `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: the Adapter left LinkError ",
                   "after %0d clocks, before the minimum residency of %0d (UCIe r3.0 ",
                   "§10.3.3.7)"}, st_cycles + 1, le_min_res))
      else
        n_exits++;
    end
    if (s != st) begin
      exit_asked = 1'b0;
      own_woke = 1'b0;
    end
    if (ign_watch != 0) begin
      if (s != st && s == ign_st)
        `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: the status became %s on a ",
                   "request UCIe r3.0 Table 10-4 ignores (or that was no request)"}, s.name()))
      ign_watch--;
    end
    if (s != st) begin
      st_from = st;
      st = s;
      st_cycles = 0;
      if (early_armed) n_early_waits++;
      early_given = 1'b0;
      early_quiet = 0;
      early_armed = 1'b0;
      early_done = 1'b0;
      early_left = 0;
      early_hold = 1'b0;
      trig_wait = 0;
      if (s != LSM_RESET && !(s inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}))
        holding = 1'b0;
    end else if (st_cycles < 1000) begin
      st_cycles++;
    end
  endfunction

  // What the Adapter reports as negotiated, and the stream of the RX data
  // (see the header).
  local function void negotiated();
    if (st == LSM_RESET && !inband_seen) proto_held = 1'b0;
    if (st == LSM_RESET && inband_seen && lsm.mon_cb.pl_protocol_vld === 1'b1 && !proto_held) begin
      proto_held = 1'b1;
      n_proto++;
      if (lsm.mon_cb.pl_protocol !== protocol || lsm.mon_cb.pl_protocol_flitfmt !== UCIE_FLITFMT_6)
        `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: pl_protocol %04b, ",
                   "pl_protocol_flitfmt %04b sampled in Reset; expected %04b and 0110b ",
                   "(Format 6)"}, lsm.mon_cb.pl_protocol, lsm.mon_cb.pl_protocol_flitfmt,
                   protocol))
    end
    if (mb.mon_cb.pl_valid === 1'b1) begin
      n_stream++;
      if (mb.mon_cb.pl_stream !== stream)
        `uvm_error(get_type_name(), $sformatf(
                   "Protocol Layer stub: pl_stream %02h with pl_valid; expected %02h",
                   mb.mon_cb.pl_stream, stream))
    end
  endfunction

  // lp_clk_ack and lp_rx_active_sts: up a clock after their request, down
  // hs_lag clocks after it falls (one clock with hs_lag 0); "clk_ack" pulses
  // lp_clk_ack once without pl_clk_req.
  local function void handshakes();
    bit creq = lsm.mon_cb.pl_clk_req === 1'b1;
    bit rreq = lsm.mon_cb.pl_rx_active_req === 1'b1;
    clk_low = creq ? 0 : clk_low + 1;
    clk_high = creq ? clk_high + 1 : 0;
    rx_low = rreq ? 0 : rx_low + 1;
    if (creq && lsm.mon_cb.lp_clk_ack === 1'b1) clk_acked = 1'b1;
    if (!creq && creq_h && !clk_acked)
      `uvm_error(get_type_name(), {"Protocol Layer stub: pl_clk_req fell before lp_clk_ack ",
                 "answered it (UCIe r3.0 §10.2.3.2 rules 3 and 5)"})
    if (!creq) clk_acked = 1'b0;
    creq_h = creq;
    if (rreq && !rreq_q && st inside {LSM_RESET, LSM_RETRAIN} &&
        lsm.mon_cb.lp_state_req !== req_code(LSM_REQ_ACTIVE)) begin
      if (st == LSM_RETRAIN) n_rx_first_rt++;
      else n_rx_first++;
      if (st == LSM_RESET && early_armed && !remote_first)
        `uvm_error(get_type_name(), {"Protocol Layer stub: the Adapter started the Active entry ",
                   "on an early NOP->Active the stub had withdrawn to NOP (UCIe r3.0 §10.3.3.8, ",
                   "§10.3.3.1 rule 1: the request is the next NOP->Active)"})
    end
    rreq_q = rreq;
    lsm.lp_clk_ack <= creq && (clk_high >= clk_ack_delay || lsm.mon_cb.lp_clk_ack === 1'b1) ||
                      lsm.mon_cb.lp_clk_ack === 1'b1 && !creq && clk_low < hs_lag;
    lsm.lp_rx_active_sts <= rreq || lsm.mon_cb.lp_rx_active_sts === 1'b1 && rx_low < hs_lag;
    if (bad == "clk_ack" && !bad_done && n_sent >= 8 && st == LSM_ACTIVE && !creq &&
        lsm.mon_cb.lp_clk_ack !== 1'b1) begin
      bad_done = 1'b1;
      lsm.lp_clk_ack <= 1'b1;
    end
  endfunction

  // The "wake" and "wake_held" violations: no lp_wake_req for a request in Reset.
  local function bit no_wake();
    return bad inside {"wake", "wake_held"};
  endfunction

  // Whether early_present may present a flit in this state (see above).
  local function bit may_present();
    case (st)
      LSM_ACTIVE, LSM_RETRAIN, LSM_LINKERROR: return 1'b1;
      LSM_LINKRESET, LSM_DISABLED: return bad == "irdy_reset" || st_cycles < down_present;
      LSM_RESET: return (st_from == LSM_LINKERROR ||
                         bad == "irdy_reset" && st_from inside {LSM_LINKRESET, LSM_DISABLED}) &&
                        st_cycles < irdy_linger;
      default:                                return 1'b0;
    endcase
  endfunction

  local function void state_req(logic [3:0] sts);
    logic [3:0] nop = req_code(LSM_REQ_NOP);
    logic [3:0] act = req_code(LSM_REQ_ACTIVE);
    case (sts_decode(sts))
      LSM_RESET: begin
        bit up = lsm.mon_cb.pl_inband_pres === 1'b1;
        if (reset_hold(up)) return;
        if (wake_late || no_wake()) begin
          // The request first, lp_wake_req a clock after it (or never).
          lsm.lp_wake_req <= !no_wake() && up && lsm.mon_cb.lp_state_req === act;
          lsm.lp_state_req <= up && nop_seen && proto_held ? act : nop;
        end else begin
          lsm.lp_wake_req <= up;
          if (up && nop_seen && proto_held && lsm.mon_cb.pl_wake_ack === 1'b1)
            lsm.lp_state_req <= act;
          else lsm.lp_state_req <= nop;
        end
        nop_seen = up;
      end
      LSM_ACTIVE: begin
        lsm.lp_wake_req <= 1'b1;
        lsm.lp_state_req <= act;
        nop_seen = 1'b0;
      end
      LSM_RETRAIN: begin
        lsm.lp_wake_req <= 1'b1;
        lsm.lp_state_req <= nop_seen ? act : nop;
        nop_seen = 1'b1;
      end
      LSM_L1: begin
        lsm.lp_wake_req <= wake_in_l1;
        lsm.lp_state_req <= req_code(LSM_REQ_L1);
        nop_seen = 1'b0;
      end
      default: begin
        lsm.lp_wake_req <= bad == "wake_held" && sts_decode(sts) == LSM_LINKERROR;
        lsm.lp_state_req <= nop;
        nop_seen = 1'b0;
        // The exit request of LinkError, LinkReset and Disabled (Table 10-4),
        // with its wake handshake (r3.0 §10.2.3.1).
        if ((held_active || bad == "held_forever") && st_cycles >= 2 && !plan_due(st) &&
            sts_decode(sts) inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}) begin
          holding = 1'b1;
          exit_asked = 1'b1;
          held_up = 0;
          held_err = 1'b0;
          lsm.lp_wake_req <= 1'b1;
          lsm.lp_state_req <= act;
        end
      end
    endcase
  endfunction

  // Requests in Reset that are not the usual NOP, then Active once
  // pl_inband_pres is up (see the header): an Active held from the state
  // before, and the early NOP->Active trigger. 1 when one of them drove
  // lp_state_req this clock.
  local function bit reset_hold(bit up);
    logic [3:0] act = req_code(LSM_REQ_ACTIVE);
    if (holding) begin
      if (lsm.mon_cb.pl_rx_active_req === 1'b1 && !held_err && bad != "held_forever") begin
        held_err = 1'b1;
        `uvm_error(get_type_name(), {"Protocol Layer stub: the Adapter started the Active entry ",
                   "on an Active request held into Reset (UCIe r3.0 §10.3.3.1 rule 1: NOP for a ",
                   "clock, then Active)"})
      end
      if (up) held_up++;
      // A planned request due in this Reset ends the hold: NOP for a clock,
      // then the request (requests()).
      if (bad != "held_forever" && plan_due(LSM_RESET)) begin
        holding = 1'b0;
        nop_seen = 1'b0;
        return 1'b0;
      end
      if (bad == "held_forever" || held_up < held_cycles) begin
        lsm.lp_wake_req <= 1'b1;
        lsm.lp_state_req <= act;
        // Halfway, LinkReset for a clock: no NOP came first, so neither it
        // nor the Active after it is a request (Table 10-4 note a).
        if (bad != "held_forever" && up && held_up == held_cycles / 2) begin
          lsm.lp_state_req <= req_code(LSM_REQ_LINKRESET);
          n_other++;
          ign_st = LSM_LINKRESET;
          ign_watch = 20;
        end
        nop_seen = 1'b0;
        return 1'b1;
      end
      holding = 1'b0;
      n_held++;
      return 1'b0;  // NOP now (nop_seen is 0), Active from the next clock
    end
    if (early_trigger && !up && !early_done && st_cycles >= 2 &&
        lsm.mon_cb.lp_state_req === req_code(LSM_REQ_NOP)) begin
      early_done = 1'b1;
      if ($urandom_range(99) < early_pct) begin
        n_early++;
        early_hold = $urandom_range(1) != 0;
        early_given = !early_hold;
        early_left = $urandom_range(3, 1);
        if (st_from inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED}) trig_wait = 1;
      end
    end
    if (trig_wait != 0) begin
      if (up) begin
        n_restarts++;
        trig_wait = 0;
      end else if (restart_bound != 0 && trig_wait++ == restart_bound) begin
        `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: no pl_inband_pres %0d ",
                   "clocks after its NOP->Active in Reset restarted the training (UCIe r3.0 ",
                   "§10.3.3.8)"}, restart_bound))
      end
    end
    if (early_hold || early_left != 0) begin
      if (early_left != 0) early_left--;
      lsm.lp_wake_req <= 1'b1;
      lsm.lp_state_req <= act;
      nop_seen = 1'b0;
      return 1'b1;
    end
    // Back at NOP: pl_inband_pres too close to the trigger may have let the
    // Adapter take it as the request, so the check arms only after two quiet
    // clocks.
    if (early_given && !early_armed) begin
      if (up) early_given = 1'b0;
      else if (++early_quiet >= 2) early_armed = 1'b1;
    end
    return 1'b0;
  endfunction

  // lp_linkerror (see the header): raised on linkerror_req where it is due,
  // held until LinkError and then for linkerror_hold clocks.
  local function void linkerror(logic [3:0] sts);
    bit in_le = st == LSM_LINKERROR;
    bit cur_le = lsm.mon_cb.lp_linkerror === 1'b1;
    bit raise;
    if (in_le) begin
      if (le_wait != 0) n_le_answered++;
      le_wait = 0;
      linkerror_req = 1'b0;
      if (cur_le && le_held < linkerror_hold) begin
        le_held++;
        return;  // lp_linkerror stays 1
      end
      lsm.lp_linkerror <= 1'b0;
      return;
    end
    le_held = 0;
    if (le_drop != 0 && cur_le && le_wait >= le_drop) begin
      plan_t p;
      p.in = st;
      p.req = le_drop_req;
      p.up = -1;
      p.ignore = 1'b0;
      plan.push_front(p);
      n_le_dropped++;
      le_wait = 0;
      linkerror_req = 1'b0;
      lsm.lp_linkerror <= 1'b0;
      `uvm_info(get_type_name(), $sformatf({"Protocol Layer stub: drops lp_linkerror in %s ",
                "before LinkError and requests %s instead"}, st.name(), le_drop_req.name()),
                UVM_MEDIUM)
      return;
    end
    raise = !cur_le && le_due(st);
    if (raise) begin
      le_wait = 1;
      if (own_woke) n_le_gated++;
      own_woke = 1'b0;
    end else if (le_wait != 0 && ++le_wait > req_bound) begin
      `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: no answer to lp_linkerror, ",
                 "still %s %0d clocks after it rose (UCIe r3.0 Table 10-3, Table 10-4)"},
                 st.name(), req_bound))
      le_wait = 0;
      linkerror_req = 1'b0;
      lsm.lp_linkerror <= 1'b0;
      return;
    end
    lsm.lp_linkerror <= raise || cur_le;
    // The wake handshake for a request leaving a clock-gated state (r3.0
    // §10.2.3.1), kept until LinkError (rule 3).
    if ((raise || cur_le) && lsm_gated(st) && bad != "wake_le") lsm.lp_wake_req <= 1'b1;
  endfunction

  // linkerror_req is due in state `s` (see the header).
  local function bit le_due(ucie_lsm_state_e s);
    if (!linkerror_req || s == LSM_LINKERROR) return 1'b0;
    if (linkerror_in == LSM_ACTIVE) return s == LSM_ACTIVE;
    if (linkerror_in != LSM_UNKNOWN && s != linkerror_in) return 1'b0;
    if (s == LSM_RESET && linkerror_up >= 0 && inband_seen != (linkerror_up != 0)) return 1'b0;
    return st_cycles >= 2;
  endfunction

  // plan[0] is due in state `s` (before the Reset NOP check).
  local function bit plan_due(ucie_lsm_state_e s);
    if (plan.size() == 0 || req_on) return req_on && plan.size() != 0 && plan[0].in == s;
    if (plan[0].in != s || st_cycles < 2) return 1'b0;
    if (s == LSM_RESET && plan[0].up >= 0 && inband_seen != (plan[0].up != 0)) return 1'b0;
    return 1'b1;
  endfunction

  // A request of its own is due in `s` (gate_check wakes for it).
  local function bit own_due(ucie_lsm_state_e s);
    return le_due(s) || plan_due(s);
  endfunction

  // The plan's LinkReset and Disabled requests (see the header); last word on
  // lp_state_req and lp_wake_req this clock.
  local function void requests();
    ucie_lsm_state_e to;
    if (!req_on) begin
      if (!plan_due(st) || holding && st == LSM_RESET) return;
      // In Reset only after a NOP of at least one clock (Table 10-4 note a).
      if (st == LSM_RESET && lsm.mon_cb.lp_state_req !== req_code(LSM_REQ_NOP)) return;
      req_on = 1'b1;
      req_le = 1'b0;
      req_wait = 0;
      if (own_woke) n_req_gated++;
      own_woke = 1'b0;
      if (plan[0].ignore) begin
        ign_st = plan[0].req == LSM_REQ_LINKRESET ? LSM_LINKRESET : LSM_DISABLED;
        ign_watch = 40;
      end
      `uvm_info(get_type_name(), $sformatf("Protocol Layer stub: requests %s in %s%s",
                plan[0].req.name(), st.name(), plan[0].ignore ? " (ignored there)" : ""),
                UVM_MEDIUM)
    end
    to = plan[0].req == LSM_REQ_LINKRESET ? LSM_LINKRESET : LSM_DISABLED;
    req_wait++;
    if (lsm.mon_cb.lp_linkerror === 1'b1) req_le = 1'b1;
    if (!plan[0].ignore && st == LSM_LINKERROR && !req_le)
      `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: lp_state_req %s made in %s ",
                 "led to LinkError, which the stub did not request (UCIe r3.0 Table 10-4)"},
                 plan[0].req.name(), plan[0].in.name()))
    if (plan[0].ignore ? req_wait > 20 || st != plan[0].in : st == to || st == LSM_LINKERROR) begin
      if (plan[0].ignore) n_ignored++;
      else n_down++;
      void'(plan.pop_front());
      req_on = 1'b0;
      return;
    end
    if (!plan[0].ignore && req_wait > req_bound) begin
      `uvm_error(get_type_name(), $sformatf({"Protocol Layer stub: no answer to lp_state_req %s ",
                 "made in %s, still %s %0d clocks later (UCIe r3.0 Table 10-4)"},
                 plan[0].req.name(), plan[0].in.name(), st.name(), req_bound))
      void'(plan.pop_front());
      req_on = 1'b0;
      return;
    end
    lsm.lp_state_req <= req_code(plan[0].req);
    if (bad != "wake_down" || !lsm_gated(st)) lsm.lp_wake_req <= 1'b1;
    else lsm.lp_wake_req <= 1'b0;
  endfunction

  local function void tx(logic [3:0] sts);
    bit trdy = mb.mon_cb.pl_trdy === 1'b1;
    bit stallreq = mb.mon_cb.pl_stallreq === 1'b1;
    bit active = sts == FDI_STS_ACTIVE;
    bit rx_on = mb.mon_cb.rx_active === 1'b1;
    int unsigned bpf = beats_per_flit(beat_bytes);
    bit done = 1'b0;
    bit keep;
    if (hold_present && presenting && beat == 0 && stallreq) kept = 1'b1;
    if (presenting && trdy) begin
      beat++;
      if (beat == bpf) begin
        n_sent += cur.size();
        if (kept) n_kept++;
        cur.delete();
        beat = 0;
        done = 1'b1;
      end
    end
    if (!active && beat != 0) begin
      // Cut off mid-flit (a LinkError): send the whole flit again later.
      n_restarted++;
      beat = 0;
    end
    // hold_present: a flit presented at a boundary that has not transferred
    // stays up, and lp_stallack waits for it (see the header).
    keep = hold_present && presenting && !done && beat == 0 && active;
    if (!presenting || done || !active) kept = 1'b0;
    if (stallreq && !stallack && beat == 0 && !keep) begin
      if (!sa_armed) begin
        sa_armed = 1'b1;
        sa_left = stall_ack_rand ? $urandom_range(stall_ack_delay) : stall_ack_delay;
      end
      if (sa_left == 0) begin
        stallack = 1'b1;
        sa_armed = 1'b0;
      end else begin
        sa_left--;
      end
    end else if (!stallreq && stallack) begin
      stallack = 1'b0;
    end
    if (beat != 0) begin
      presenting = 1'b1;
    end else begin
      if (cur.size() == 0 && txq.size() != 0) begin
        int unsigned fpb = flits_per_beat(beat_bytes);
        if (bad == "nop_tx" && !bad_done && n_sent >= 8) begin
          bad_done = 1'b1;
          cur.push_back(nop());
        end else if (tx_nop_pct != 0 && $urandom_range(99) < tx_nop_pct) begin
          cur.push_back(nop());
        end
        while (cur.size() < fpb && txq.size() != 0) cur.push_back(txq.pop_front());
        while (cur.size() < fpb) cur.push_back(filler());
        cc_mask = corrupt_plan();
      end
      if (early_present || hold_present)
        presenting = cur.size() != 0 && !stallack && (!stallreq || keep) && may_present();
      else
        presenting = cur.size() != 0 && active && rx_on && trdy && !stallack && !stallreq;
    end
    if (presenting && !active) n_presented_down++;
    misbehave(presenting && beat == 0 && !bad_done && bad inside {"dllp", "retimer", "stream"} &&
              n_sent >= 8);
    mb.lp_stallack <= stallack;
    mb.lp_corrupt_crc <= presenting && cc_mask[beat];
    mb.lp_valid <= presenting || valid_alone && !stallack && $urandom_range(1) != 0;
    mb.lp_irdy <= presenting;
    mb.lp_data <= presenting ? beat_data() : '0;
  endfunction

  // Which transfers of the next flit carry lp_corrupt_crc: the last of a 128B
  // half (the second, or both), or a deliberate misplacement (`bad`).
  local function bit [MAX_BEATS_PER_FLIT-1:0] corrupt_plan();
    int unsigned bpf = beats_per_flit(beat_bytes);
    int unsigned bph = beats_per_half(beat_bytes);
    bit [MAX_BEATS_PER_FLIT-1:0] m = '0;
    if (!bad_done && n_sent >= 8 && bad inside {"corrupt_mid", "corrupt_h0", "corrupt_proto"}) begin
      bad_done = 1'b1;
      n_corrupt++;
      case (bad)
        "corrupt_mid": m[0] = 1'b1;
        "corrupt_h0":  m[bph-1] = 1'b1;
        default:       m[bpf-1] = 1'b1;
      endcase
      return m;
    end
    if ($urandom_range(99) >= corrupt_pct) return m;
    n_corrupt++;
    m[bpf-1] = 1'b1;
    if (bph < bpf && $urandom_range(1) != 0) m[bph-1] = 1'b1;
    return m;
  endfunction

  // The violation `bad` names, in this cycle when `now`; the idle values otherwise.
  local function void misbehave(bit now);
    if (now) bad_done = 1'b1;
    mb.lp_dllp_valid <= now && bad == "dllp";
    mb.lp_retimer_crd <= now && bad == "retimer";
    mb.lp_stream <= (now && bad == "stream") ? ~stream : stream;
  endfunction

  local function ucie_fdi_beat_t beat_data();
    ucie_fdi_beat_t b = '0;
    foreach (cur[l]) b |= cur[l].get_beat(beat_bytes, beat, l);
    return b;
  endfunction

  // A NOP flit: Protocol ID 00b, everything else zero.
  local function ucie_flit_item nop();
    ucie_flit_item f = ucie_flit_item::type_id::create("nop");
    f.dir = UCIE_FDI_TX;
    n_tx_nop++;
    return f;
  endfunction

  // A Protocol Flit with no messages: Protocol ID 11b, everything else zero.
  local function ucie_flit_item filler();
    ucie_flit_item f = ucie_flit_item::type_id::create("fill");
    f.dir = UCIE_FDI_TX;
    f.data[0] = 8'hC0;
    n_fill++;
    return f;
  endfunction
endclass
