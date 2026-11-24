// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Drives flits into the Protocol Layer's RX (pl_valid/pl_data/pl_flit_cancel). A flit
// starts only while the gate is open for RX (L2 reports Active, or the
// Receiver is Active in Reset with +ucie_rx_early) and out of reset;
// once started it runs to completion, cancels and replays included. A
// cancel comes in the cycle after the last beat of its 128B half
// (FDI-R05), either with pl_valid low or with the replay's first beat. On a
// 256 B FDI the flit is one beat and its cancel covers the whole flit. On a
// 512 or 1024 B FDI a transfer carries up to 2 or 4 flits, taken from the
// sequence as they are ready, on the low lanes with zeros (NOP flits) on the
// rest; the first flit's cancel plan is the transfer's, and a cancel covers
// every flit in it (UCIe r3.0 10.3.1). A LinkError mid-flit (gate abort)
// abandons the flit at once.
//
// With cfg.error_pct a flit meets a framing error instead of its cancel plan
// (UCIe r3.0 Table 10-3 pl_error): pl_error rides with pl_valid on one
// transfer of a cancel unit; the unit is finished and cancelled (with
// pl_valid low: no replay can follow at once), the driver asks L2 for a
// Retrain (gate.retrain_req) and replays the unit once the gate has closed and
// opened again.
//
// With cfg.nop_pct the driver forwards NOP flits of its own (Protocol ID 00b,
// r3.0 Table 3-5) among the sequence's: a NOP transfer before a flit, and from
// 512 B up NOPs in further lanes of a transfer. A stand-alone NOP goes through
// uncancelled, or is cancelled and replayed, or is cancelled and never
// replayed (Table 10-3 pl_flit_cancel); the Protocol Layer must deliver none.
class ucie_fdi_pl_driver extends uvm_driver #(ucie_flit_item);
  `uvm_component_utils(ucie_fdi_pl_driver)

  virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  ucie_fdi_cfg cfg;

  local bit cancel_next;  // the next beat carries pl_flit_cancel
  local int unsigned epoch;  // gate epoch when the current item was fetched
  // Random bytes for the cancelled copies of a half (cfg.poison_cancelled),
  // refilled for every flit that has a cancel.
  local ucie_flit_item poison;
  local ucie_flit_item lanes[$];  // the flits of the transfer being driven
  local bit nop_drop;  // the transfer is a NOP the driver cancels and never replays

  int unsigned n_nops;          // NOP flits forwarded (cfg.nop_pct), lanes included
  int unsigned n_nops_dropped;  // ... of them cancelled and never replayed

  function new(string name, uvm_component parent);
    super.new(name, parent);
    poison = new("poison");
    // A cancelled copy is never a NOP, so a monitor does not take it for one.
    poison.data[0][7:6] = 2'b11;
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.pl_valid <= 1'b0;
    vif.drv_cb.pl_flit_cancel <= 1'b0;
    vif.drv_cb.pl_data <= '0;
    vif.drv_cb.pl_error <= 1'b0;
    // Tied: the stream ID, and no DLLPs or Retimer credits (not modelled).
    vif.drv_cb.pl_stream <= cfg.stream;
    vif.drv_cb.pl_dllp <= '0;
    vif.drv_cb.pl_dllp_valid <= 1'b0;
    vif.drv_cb.pl_dllp_ofc <= 1'b0;
    vif.drv_cb.pl_retimer_crd <= 1'b0;
    forever begin
      seq_item_port.try_next_item(req);
      if (req == null) begin
        idle_cycle(1'b0);
        continue;
      end
      epoch = cfg.gate.epoch;
      wait_open();
      if (cfg.nop_pct != 0 && epoch == cfg.gate.epoch && $urandom_range(99) < cfg.nop_pct) begin
        send_nop();
        wait_open();
      end
      if (epoch != cfg.gate.epoch) begin
        `uvm_info(get_type_name(), "flit fetched before a link reset dropped", UVM_MEDIUM)
        seq_item_port.item_done();
        continue;
      end
      cfg.gate.rx_busy = 1'b1;
      lanes.delete();
      lanes.push_back(req);
      if (cfg.fpb() > 1) begin
        // Several flits per transfer: release each as it is taken so the
        // sequence can offer the next one in the same cycle.
        seq_item_port.item_done();
        fill_lanes();
      end
      drive_flit();
      cfg.gate.rx_busy = 1'b0;
      if (cfg.fpb() == 1) seq_item_port.item_done();
    end
  endtask

  // The lanes of the transfer that are not NOPs: the flits an abandon loses.
  local function int unsigned n_lane_flits();
    int unsigned n = 0;
    foreach (lanes[l]) if (!lanes[l].is_nop()) n++;
    return n;
  endfunction

  local task wait_open();
    while (!(cfg.gate.rx_open() && vif.drv_cb.rst_n === 1'b1)) idle_cycle(1'b0);
  endtask

  // A NOP transfer of its own (cfg.nop_pct): through uncancelled, cancelled
  // and replayed, or cancelled and dropped, a third each.
  local task send_nop();
    ucie_flit_item n = new("nop");
    int unsigned kind = $urandom_range(2);
    n.make_nop();
    if (kind == 1) n.mix_cancel_plan();
    nop_drop = kind == 2;
    n_nops++;
    if (nop_drop) n_nops_dropped++;
    lanes.delete();
    lanes.push_back(n);
    cfg.gate.rx_busy = 1'b1;
    drive_flit();
    cfg.gate.rx_busy = 1'b0;
    nop_drop = 1'b0;
  endtask

  // The other lanes of a wide transfer: the flits the sequence has ready now,
  // fewer with partial_beat_pct; with nop_pct a lane may be a NOP instead.
  local task fill_lanes();
    int unsigned n = cfg.fpb();
    if ($urandom_range(99) < cfg.partial_beat_pct) n = $urandom_range(n - 1, 1);
    while (lanes.size() < n) begin
      ucie_flit_item it;
      if (cfg.nop_pct != 0 && $urandom_range(99) < cfg.nop_pct) begin
        it = new("nop");
        it.make_nop();
        lanes.push_back(it);
        n_nops++;
        continue;
      end
      seq_item_port.try_next_item(it);
      if (it == null) break;
      lanes.push_back(it);
      seq_item_port.item_done();
    end
  endtask

  // Beat idx of the transfer: each lane's flit, or the poison copy for a
  // cancelled one; lanes without a flit stay zero.
  local function ucie_fdi_beat_t beat(int unsigned idx, bit poisoned);
    ucie_fdi_beat_t b = '0;
    foreach (lanes[l]) begin
      ucie_flit_item src = poisoned ? poison : lanes[l];
      b |= src.get_beat(cfg.beat_bytes, idx, l);
    end
    return b;
  endfunction

  local task idle_cycle(bit cancel);
    vif.drv_cb.pl_valid <= 1'b0;
    vif.drv_cb.pl_flit_cancel <= cancel;
    @(vif.drv_cb);
  endtask

  // After a framing error: L2 retrains the link (it closes the gate, takes the
  // link through Retrain and opens it again), then the replay goes on.
  // ok 0: the flit was dropped (reset, LinkError or a link reset under the
  // layers above).
  local task wait_retrain(output bit ok);
    int unsigned n;
    bit closed = !cfg.gate.open;
    cfg.gate.retrain_req = cfg.gate.open;
    cfg.gate.rx_busy = 1'b0;
    while (!(closed && cfg.gate.open)) begin
      if (vif.drv_cb.rst_n !== 1'b1 || cfg.gate.abort || epoch != cfg.gate.epoch) begin
        if (cfg.gate.abort) cfg.gate.n_abandoned += n_lane_flits();
        `uvm_info(get_type_name(), "link down while waiting to replay after pl_error; flit dropped",
                  UVM_MEDIUM)
        ok = 1'b0;
        return;
      end
      if (++n == cfg.error_retrain_timeout) begin
        `uvm_error(get_type_name(), $sformatf("no Retrain %0d cycles after pl_error; replaying", n))
        break;
      end
      idle_cycle(1'b0);
      closed |= !cfg.gate.open;
    end
    cfg.gate.rx_busy = 1'b1;
    ok = 1'b1;
  endtask

  local task drive_flit();
    ucie_flit_item it = lanes[0];  // its plan is the transfer's
    int unsigned seg_half[$];
    ucie_fdi_cancel_e seg_cancel[$];
    int unsigned bph = cfg.bph();
    int err_seg = -1;              // the segment that carries pl_error
    int unsigned err_beat;         // ... on this transfer of it

    if (!valid_beat_bytes(cfg.beat_bytes))
      `uvm_fatal(get_type_name(), $sformatf(
                 "beat_bytes %0d: not 32, 64, 128, 256, 512 or 1024", cfg.beat_bytes))
    if (cfg.random_adapter_bytes) foreach (lanes[l]) lanes[l].randomize_adapter_bytes();
    if (it.has_cancel() && cfg.poison_cancelled) begin
      poison.randomize_payload();
      poison.randomize_adapter_bytes();
    end

    if (nop_drop) begin
      // A NOP cancelled and not replayed: its first unit, and nothing after.
      seg_half.push_back(0); seg_cancel.push_back(UCIE_CANCEL_IDLE);
    end else if (halves_per_flit(cfg.beat_bytes) == 1) begin
      // 256 B and up: one cancel unit, the transfer. A plan that cancels either half
      // cancels the whole flit, cancel_repeat times, in the kind of its first
      // cancelled half; then the flit goes through.
      ucie_fdi_cancel_e kind = it.cancel_h0 != UCIE_CANCEL_NONE ? it.cancel_h0 : it.cancel_h1;
      if (kind != UCIE_CANCEL_NONE) begin
        int unsigned rep = it.cancel_repeat;
        repeat (rep < 1 ? 1 : rep) begin
          seg_half.push_back(0); seg_cancel.push_back(kind);
        end
      end
      seg_half.push_back(0); seg_cancel.push_back(UCIE_CANCEL_NONE);
    end else if (it.cancel_h0 != UCIE_CANCEL_NONE) begin
      int unsigned rep = it.cancel_h1 != UCIE_CANCEL_NONE ? 1 : it.cancel_repeat;
      repeat (rep < 1 ? 1 : rep) begin
        seg_half.push_back(0); seg_cancel.push_back(it.cancel_h0);
      end
      if (it.cancel_h1 != UCIE_CANCEL_NONE) begin
        seg_half.push_back(1); seg_cancel.push_back(it.cancel_h1);
      end
      seg_half.push_back(0); seg_cancel.push_back(UCIE_CANCEL_NONE);
      seg_half.push_back(1); seg_cancel.push_back(UCIE_CANCEL_NONE);
    end else begin
      int unsigned rep = it.h1_replay_resend_h0 ? 1 : it.cancel_repeat;
      seg_half.push_back(0); seg_cancel.push_back(UCIE_CANCEL_NONE);
      if (it.cancel_h1 == UCIE_CANCEL_NONE) begin
        seg_half.push_back(1); seg_cancel.push_back(UCIE_CANCEL_NONE);
      end else begin
        repeat (rep < 1 ? 1 : rep) begin
          seg_half.push_back(1); seg_cancel.push_back(it.cancel_h1);
        end
        if (it.h1_replay_resend_h0) begin
          seg_half.push_back(0); seg_cancel.push_back(it.cancel_h1);
        end
        seg_half.push_back(1); seg_cancel.push_back(UCIE_CANCEL_NONE);
      end
    end

    // A framing error replaces the plan: one unit is flagged and cancelled, then
    // the flit goes through. Only while the link is Active (pl_error needs the
    // Receiver active, r3.0 Table 10-3).
    if (cfg.error_pct != 0 && !nop_drop && cfg.gate.open &&
        $urandom_range(99) < cfg.error_pct) begin
      int unsigned u = halves_per_flit(cfg.beat_bytes) == 1 ? 0 : $urandom_range(1);
      seg_half.delete();
      seg_cancel.delete();
      if (u == 1) begin
        seg_half.push_back(0); seg_cancel.push_back(UCIE_CANCEL_NONE);
      end
      err_seg = seg_half.size();
      seg_half.push_back(u); seg_cancel.push_back(UCIE_CANCEL_IDLE);
      seg_half.push_back(u); seg_cancel.push_back(UCIE_CANCEL_NONE);
      if (u == 0 && halves_per_flit(cfg.beat_bytes) == 2) begin
        seg_half.push_back(1); seg_cancel.push_back(UCIE_CANCEL_NONE);
      end
      err_beat = $urandom_range(bph - 1);
      if (cfg.poison_cancelled && !it.has_cancel()) begin
        poison.randomize_payload();
        poison.randomize_adapter_bytes();
      end
    end

    repeat (it.pre_gap) idle_cycle(1'b0);
    foreach (lanes[l]) lanes[l].t_start = $time;
    cancel_next = 1'b0;
    foreach (seg_half[s]) begin
      bit cancelled = seg_cancel[s] != UCIE_CANCEL_NONE;
      for (int unsigned b = 0; b < bph; b++) begin
        int unsigned idx = seg_half[s] * bph + b;
        // A VALID cancel rides on this half's first beat: no gap before it.
        if (!(b == 0 && cancel_next) && !(s == 0 && b == 0) &&
            $urandom_range(99) < it.beat_gap_pct)
          repeat ($urandom_range(it.max_beat_gap, 1)) idle_cycle(1'b0);
        if (vif.drv_cb.rst_n !== 1'b1 || cfg.gate.abort) begin
          if (cfg.gate.abort) cfg.gate.n_abandoned += n_lane_flits();
          `uvm_info(get_type_name(), cfg.gate.abort ? "LinkError during a flit; flit abandoned" :
                                     "reset during a flit; flit dropped", UVM_MEDIUM)
          // A half that failed CRC is still cancelled in the cycle after its last
          // chunk (r3.0 Table 10-3): without it the Protocol Layer may consume the half.
          idle_cycle(cancel_next && cfg.gate.abort);
          cancel_next = 1'b0;
          return;
        end
        vif.drv_cb.pl_valid <= 1'b1;
        vif.drv_cb.pl_flit_cancel <= cancel_next;
        vif.drv_cb.pl_data <= beat(idx, cancelled && cfg.poison_cancelled && !nop_drop);
        vif.drv_cb.pl_error <= s == err_seg && b == err_beat;
        cancel_next = 1'b0;
        @(vif.drv_cb);
        vif.drv_cb.pl_error <= 1'b0;
      end
      case (seg_cancel[s])
        UCIE_CANCEL_IDLE:  idle_cycle(1'b1);
        UCIE_CANCEL_VALID: cancel_next = 1'b1;
        default: ;
      endcase
      if (s == err_seg) begin
        bit ok;
        wait_retrain(ok);
        if (!ok) return;
      end
    end
    foreach (lanes[l]) begin
      lanes[l].t_end = $time;
      `uvm_info(get_type_name(), $sformatf("sent (lane %0d) %s", l, lanes[l].convert2string()),
                UVM_HIGH)
    end
  endtask
endclass
