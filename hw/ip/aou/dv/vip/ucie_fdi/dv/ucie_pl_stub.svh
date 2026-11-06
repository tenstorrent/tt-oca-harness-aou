// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// A minimal Protocol Layer on top of the model, as a stand-in for a design:
// it answers the FDI handshakes and loops every flit the Adapter delivers
// (the mainband monitor's ap_rx) back on its TX side.
//  - lp_clk_ack and lp_rx_active_sts follow their requests one clock later
//    (UCIe r1.1 §8.2.3.2, §8.2.7).
//  - lp_wake_req is high while the link is wanted up: in Reset once
//    pl_inband_pres is 1, and in Active and Retrain (§8.2.3.1); low in L1, so
//    the Adapter's PM exit stays its own (the self-test's L1 events).
//  - lp_state_req: in Reset NOP, then Active once pl_wake_ack is high
//    (§8.2.8, §8.3.3.1); Active in Active; in Retrain NOP for a clock, then
//    Active (§8.3.3.4); L1 in L1; NOP elsewhere.
//  - TX: a flit starts only in Active with the Receiver active and pl_trdy
//    high, then runs to its end with no bubbles (§8.2.4). pl_stallreq is
//    acknowledged at the next flit boundary, a clock later at the earliest
//    (§8.3.2). A flit cut off when the Adapter leaves Active mid-flit is sent
//    again from its start, so the loopback loses nothing.
//  - On a 512 or 1024 B FDI a TX transfer carries 2 or 4 flits; one sent
//    with fewer flits queued fills the other lanes with a Protocol Flit with
//    empty slots (UCIe r3.0 10.3.1: valid data on the full width), here a
//    flit with a non-zero Protocol ID and an all-zero payload, which the
//    scoreboard skips.
//  - lp_stream is tied to `stream`; no DLLPs or Retimer credits.
//  - `bad` makes one deliberate violation, on the first beat of a flit after
//    the eighth one sent, for the negative tests of the model's checks
//    (ucie_fdi_neg_test): "dllp" an lp_dllp_valid pulse, "retimer" an
//    lp_retimer_crd pulse, "stream" a wrong lp_stream.
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
  bit          bad_done;

  local ucie_flit_item txq[$];
  local ucie_flit_item cur[$];  // the flits of the transfer, one per lane
  local int unsigned   beat;
  local bit            presenting;
  local bit            stallack;
  local bit            nop_seen;

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
      lsm.lp_clk_ack <= lsm.mon_cb.pl_clk_req;
      lsm.lp_rx_active_sts <= lsm.mon_cb.pl_rx_active_req;
      state_req(mb.mon_cb.pl_state_sts);
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
  endfunction

  local function void state_req(logic [3:0] sts);
    logic [3:0] nop = req_code(LSM_REQ_NOP);
    logic [3:0] act = req_code(LSM_REQ_ACTIVE);
    case (sts_decode(sts))
      LSM_RESET: begin
        bit up = lsm.mon_cb.pl_inband_pres === 1'b1;
        lsm.lp_wake_req <= up;
        if (up && nop_seen && lsm.mon_cb.pl_wake_ack === 1'b1) lsm.lp_state_req <= act;
        else lsm.lp_state_req <= nop;
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
        lsm.lp_wake_req <= 1'b0;
        lsm.lp_state_req <= req_code(LSM_REQ_L1);
        nop_seen = 1'b0;
      end
      default: begin
        lsm.lp_wake_req <= 1'b0;
        lsm.lp_state_req <= nop;
        nop_seen = 1'b0;
      end
    endcase
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
      end
      presenting = cur.size() != 0 && active && rx_on && trdy && !stallack && !stallreq;
    end
    misbehave(presenting && beat == 0 && !bad_done && bad != "" && n_sent >= 8);
    mb.lp_stallack <= stallack;
    mb.lp_valid <= presenting;
    mb.lp_irdy <= presenting;
    mb.lp_data <= presenting ? beat_data() : '0;
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
