// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// A minimal Protocol Layer on top of the model, as a stand-in for a design:
// it answers the FDI handshakes and loops every flit the Adapter delivers
// (the mainband monitor's ap_rx) back on its TX side.
//  - lp_clk_ack and lp_rx_active_sts follow their requests one clock later
//    (UCIe r3.0 §10.2.3.2, §10.2.7); with `hs_lag` they fall that many clocks
//    after their request does (rule 3 and rule 4 give no time).
//  - lp_wake_req is high while the link is wanted up: in Reset once
//    pl_inband_pres is 1, and in Active and Retrain (§8.2.3.1); low in L1, so
//    the Adapter's PM exit stays its own (the self-test's L1 events), unless
//    `wake_in_l1` asks the stub to start the exit itself (r3.0 §10.2.9).
//  - `linkerror_req` raises lp_linkerror in Active and holds it until the
//    Adapter reports LinkError (r3.0 Table 10-3), then clears itself; with
//    `linkerror_hold` it keeps it high that many clocks into LinkError, which
//    the Adapter must sit out ("It must stay there as long as lp_linkerror=1").
//  - lp_state_req: in Reset NOP, then Active once pl_wake_ack is high
//    (§8.2.8, §8.3.3.1); Active in Active; in Retrain NOP for a clock, then
//    Active (§8.3.3.4); L1 in L1; NOP elsewhere. With `wake_late` it requests
//    Active in Reset without waiting for pl_wake_ack and raises lp_wake_req a
//    clock after the request (r3.0 §10.2.3.1 rule 5 orders them no further).
//  - TX: a flit starts only in Active with the Receiver active and pl_trdy
//    high, then runs to its end with no bubbles (§8.2.4). pl_stallreq is
//    acknowledged at the next flit boundary, a clock later at the earliest
//    (§8.3.2). A flit cut off when the Adapter leaves Active mid-flit is sent
//    again from its start, so the loopback loses nothing.
//  - With `early_present` a queued flit is presented (lp_valid, lp_irdy)
//    without waiting for pl_trdy, in Active and through Retrain and LinkError,
//    and for the first `down_present` clocks of LinkReset or Disabled (r3.0
//    §10.2.4: the Adapter just keeps pl_trdy low; Table 10-3 lp_irdy forbids
//    only Reset). After LinkError -> Reset lp_irdy stays up `irdy_linger` more
//    clocks, which Table 10-3 allows ("a few clocks"). Never with a stall
//    under way, nor in Reset otherwise, L1 or L2.
//  - With `valid_alone` lp_valid toggles without lp_irdy between flits, which
//    transfers nothing (Table 10-3 lp_irdy).
//  - On a 512 or 1024 B FDI a TX transfer carries 2 or 4 flits; one sent
//    with fewer flits queued fills the other lanes with a Protocol Flit with
//    empty slots (UCIe r3.0 10.3.1: valid data on the full width), here a
//    flit with a non-zero Protocol ID and an all-zero payload, which the
//    scoreboard skips.
//  - lp_stream is tied to `stream`; no DLLPs or Retimer credits.
//  - With `corrupt_pct`, a transfer of flits asks the Adapter to corrupt their
//    CRC (lp_corrupt_crc, UCIe r3.0 Table 10-3): with lp_valid on the last
//    transfer of the second 128B half, or of both halves; from 256 B up on the
//    one transfer. Only legal when the protocol includes CXL.cachemem.
//  - `bad` makes one deliberate violation, on the first beat of a flit after
//    the eighth one sent, for the negative tests of the model's checks
//    (ucie_fdi_neg_test): "dllp" an lp_dllp_valid pulse, "retimer" an
//    lp_retimer_crd pulse, "stream" a wrong lp_stream; "corrupt_mid"
//    lp_corrupt_crc on a transfer that does not end a half, "corrupt_h0" on the
//    first half only (both up to 128 B), "corrupt_proto" a well-placed one
//    while the protocol has no CXL.cachemem; "clk_ack" an lp_clk_ack pulse
//    without pl_clk_req (once, in Active); "irdy_reset" a flit presented
//    through LinkReset and Disabled and into the Reset that follows (needs
//    `early_present`); "wake" requests Active in Reset with lp_wake_req
//    never raised; "wake_held" does the same but holds lp_wake_req through
//    LinkError (rule 3 allows that) and drops it on entry to the Reset that
//    follows, before its request there: a handshake over before the request
//    is not one used for it (r3.0 §10.2.3.1).
class ucie_pl_stub extends uvm_component;
  `uvm_component_utils(ucie_pl_stub)

  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) mb;
  virtual ucie_fdi_lsm_if lsm;
  int unsigned beat_bytes = 64;
  bit [7:0]    stream = UCIE_STREAM_S0_STREAMING;  // lp_stream, tied as an integration would

  uvm_analysis_imp #(ucie_flit_item, ucie_pl_stub) rx_imp;

  int unsigned n_sent;       // flits whose last beat transferred
  int unsigned n_restarted;  // flits cut off mid-flit and sent again
  int unsigned n_fill;       // empty flits sent to fill a wide transfer
  string       bad;          // a deliberate violation (see above); "" for none
  bit          wake_in_l1;   // start a PM exit in L1 (lp_wake_req)
  bit          linkerror_req; // request a LinkError (lp_linkerror) once
  int unsigned corrupt_pct;  // chance a transfer of flits carries lp_corrupt_crc
  int unsigned n_corrupt;    // transfers sent with lp_corrupt_crc
  // Legal behaviours the model must accept (see above).
  bit          early_present;
  int unsigned down_present = 4;
  int unsigned irdy_linger = 2;
  bit          valid_alone;
  int unsigned hs_lag;
  int unsigned linkerror_hold;
  bit          wake_late;
  int unsigned n_presented_down; // clocks a flit was presented outside Active
  local bit [MAX_BEATS_PER_FLIT-1:0] cc_mask;  // the transfers of cur with lp_corrupt_crc
  bit          bad_done;

  local ucie_flit_item txq[$];
  local ucie_flit_item cur[$];  // the flits of the transfer, one per lane
  local int unsigned   beat;
  local bit            presenting;
  local bit            stallack;
  local bit            nop_seen;
  local ucie_lsm_state_e st;       // pl_state_sts as last seen
  local ucie_lsm_state_e st_from;  // ... and the state before it
  local int unsigned   st_cycles;  // clocks since st was entered
  local int unsigned   clk_low;    // clocks pl_clk_req has been low
  local int unsigned   rx_low;     // clocks pl_rx_active_req has been low
  local int unsigned   le_held;    // clocks lp_linkerror was held in LinkError

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_imp = new("rx_imp", this);
  endfunction

  // A delivered flit, to be sent back: the payload with the Adapter-owned
  // bytes cleared and a non-zero Protocol ID (Format 6 TX rule).
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
      track_state(sts_decode(mb.mon_cb.pl_state_sts));
      handshakes();
      state_req(mb.mon_cb.pl_state_sts);
      linkerror(mb.mon_cb.pl_state_sts);
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
    stallack = 1'b0;
    nop_seen = 1'b0;
    bad_done = 1'b0;
    st = LSM_RESET;
    st_from = LSM_RESET;
    st_cycles = 0;
    clk_low = 0;
    rx_low = 0;
    le_held = 0;
  endfunction

  local function void track_state(ucie_lsm_state_e s);
    if (s != st) begin
      st_from = st;
      st = s;
      st_cycles = 0;
    end else if (st_cycles < 1000) begin
      st_cycles++;
    end
  endfunction

  // lp_clk_ack and lp_rx_active_sts: up a clock after their request, down
  // hs_lag clocks after it falls (one clock with hs_lag 0); "clk_ack" pulses
  // lp_clk_ack once without pl_clk_req.
  local function void handshakes();
    bit creq = lsm.mon_cb.pl_clk_req === 1'b1;
    bit rreq = lsm.mon_cb.pl_rx_active_req === 1'b1;
    clk_low = creq ? 0 : clk_low + 1;
    rx_low = rreq ? 0 : rx_low + 1;
    lsm.lp_clk_ack <= creq || lsm.mon_cb.lp_clk_ack === 1'b1 && clk_low < hs_lag;
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
        if (wake_late || no_wake()) begin
          // The request first, lp_wake_req a clock after it (or never).
          lsm.lp_wake_req <= !no_wake() && up && lsm.mon_cb.lp_state_req === act;
          lsm.lp_state_req <= up && nop_seen ? act : nop;
        end else begin
          lsm.lp_wake_req <= up;
          if (up && nop_seen && lsm.mon_cb.pl_wake_ack === 1'b1) lsm.lp_state_req <= act;
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
      end
    endcase
  endfunction

  local function void linkerror(logic [3:0] sts);
    bit in_le = sts_decode(sts) == LSM_LINKERROR;
    bit cur_le = lsm.mon_cb.lp_linkerror === 1'b1;
    if (in_le) linkerror_req = 1'b0;
    if (!in_le) begin
      le_held = 0;
    end else if (cur_le && le_held < linkerror_hold) begin
      le_held++;
      return;  // lp_linkerror stays 1
    end
    lsm.lp_linkerror <= linkerror_req && sts_decode(sts) == LSM_ACTIVE || cur_le && !in_le;
  endfunction

  local function void tx(logic [3:0] sts);
    bit trdy = mb.mon_cb.pl_trdy === 1'b1;
    bit stallreq = mb.mon_cb.pl_stallreq === 1'b1;
    bit active = sts == FDI_STS_ACTIVE;
    bit rx_on = mb.mon_cb.rx_active === 1'b1;
    int unsigned bpf = beats_per_flit(beat_bytes);
    if (presenting && trdy) begin
      beat++;
      if (beat == bpf) begin
        n_sent += cur.size();
        cur.delete();
        beat = 0;
      end
    end
    if (!active && beat != 0) begin
      // Cut off mid-flit (a LinkError): send the whole flit again later.
      n_restarted++;
      beat = 0;
    end
    if (stallreq && !stallack && beat == 0) stallack = 1'b1;
    else if (!stallreq && stallack) stallack = 1'b0;
    if (beat != 0) begin
      presenting = 1'b1;
    end else begin
      if (cur.size() == 0 && txq.size() != 0) begin
        int unsigned fpb = flits_per_beat(beat_bytes);
        while (cur.size() < fpb && txq.size() != 0) cur.push_back(txq.pop_front());
        while (cur.size() < fpb) cur.push_back(filler());
        cc_mask = corrupt_plan();
      end
      if (early_present)
        presenting = cur.size() != 0 && !stallack && !stallreq && may_present();
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

  // A Protocol Flit with no messages: Protocol ID 11b, everything else zero.
  local function ucie_flit_item filler();
    ucie_flit_item f = ucie_flit_item::type_id::create("fill");
    f.dir = UCIE_FDI_TX;
    f.data[0] = 8'hC0;
    n_fill++;
    return f;
  endfunction
endclass
