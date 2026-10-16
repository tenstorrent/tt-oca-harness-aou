// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Drives flits into the DUT RX (pl_valid/pl_data/pl_flit_cancel). A flit
// starts only while the gate is open (L2 reports Active) and out of reset;
// once started it runs to completion, cancels and replays included. A
// cancel comes in the cycle after the last beat of its 128B half
// (FDI-R05), either with pl_valid low or with the replay's first beat. A
// LinkError mid-flit (gate abort) abandons the flit at once.
class aou_fdi_pl_driver extends uvm_driver #(aou_flit_item);
  `uvm_component_utils(aou_fdi_pl_driver)

  virtual aou_fdi_mb_if #(.DATA_W(BUS_W)) vif;
  aou_fdi_cfg cfg;

  local bit cancel_next;  // the next beat carries pl_flit_cancel
  local int unsigned epoch;  // gate epoch when the current item was fetched

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.pl_valid <= 1'b0;
    vif.drv_cb.pl_flit_cancel <= 1'b0;
    vif.drv_cb.pl_data <= '0;
    forever begin
      seq_item_port.try_next_item(req);
      if (req == null) begin
        idle_cycle(1'b0);
        continue;
      end
      epoch = cfg.gate.epoch;
      while (!(cfg.gate.open && vif.drv_cb.rst_n === 1'b1)) idle_cycle(1'b0);
      if (epoch != cfg.gate.epoch) begin
        `uvm_info(get_type_name(), "flit fetched before a link reset dropped", UVM_MEDIUM)
        seq_item_port.item_done();
        continue;
      end
      cfg.gate.rx_busy = 1'b1;
      drive_flit(req);
      cfg.gate.rx_busy = 1'b0;
      seq_item_port.item_done();
    end
  endtask

  local task idle_cycle(bit cancel);
    vif.drv_cb.pl_valid <= 1'b0;
    vif.drv_cb.pl_flit_cancel <= cancel;
    @(vif.drv_cb);
  endtask

  local task drive_flit(aou_flit_item it);
    int unsigned seg_half[$];
    aou_fdi_cancel_e seg_cancel[$];
    int unsigned bph = cfg.bph();
    aou_flit_item poison;

    if (!valid_beat_bytes(cfg.beat_bytes))
      `uvm_fatal(get_type_name(), $sformatf("unsupported beat_bytes %0d", cfg.beat_bytes))
    if (cfg.random_adapter_bytes) it.randomize_adapter_bytes();
    poison = aou_flit_item::type_id::create("poison");
    poison.randomize_payload();
    poison.randomize_adapter_bytes();

    if (it.cancel_h0 != AOU_CANCEL_NONE) begin
      int unsigned rep = it.cancel_h1 != AOU_CANCEL_NONE ? 1 : it.cancel_repeat;
      repeat (rep < 1 ? 1 : rep) begin
        seg_half.push_back(0); seg_cancel.push_back(it.cancel_h0);
      end
      if (it.cancel_h1 != AOU_CANCEL_NONE) begin
        seg_half.push_back(1); seg_cancel.push_back(it.cancel_h1);
      end
      seg_half.push_back(0); seg_cancel.push_back(AOU_CANCEL_NONE);
      seg_half.push_back(1); seg_cancel.push_back(AOU_CANCEL_NONE);
    end else begin
      int unsigned rep = it.h1_replay_resend_h0 ? 1 : it.cancel_repeat;
      seg_half.push_back(0); seg_cancel.push_back(AOU_CANCEL_NONE);
      if (it.cancel_h1 == AOU_CANCEL_NONE) begin
        seg_half.push_back(1); seg_cancel.push_back(AOU_CANCEL_NONE);
      end else begin
        repeat (rep < 1 ? 1 : rep) begin
          seg_half.push_back(1); seg_cancel.push_back(it.cancel_h1);
        end
        if (it.h1_replay_resend_h0) begin
          seg_half.push_back(0); seg_cancel.push_back(it.cancel_h1);
        end
        seg_half.push_back(1); seg_cancel.push_back(AOU_CANCEL_NONE);
      end
    end

    repeat (it.pre_gap) idle_cycle(1'b0);
    it.t_start = $time;
    cancel_next = 1'b0;
    foreach (seg_half[s]) begin
      bit cancelled = seg_cancel[s] != AOU_CANCEL_NONE;
      for (int unsigned b = 0; b < bph; b++) begin
        int unsigned idx = seg_half[s] * bph + b;
        // A VALID cancel rides on this half's first beat: no gap before it.
        if (!(b == 0 && cancel_next) && !(s == 0 && b == 0) &&
            $urandom_range(99) < it.beat_gap_pct)
          repeat ($urandom_range(it.max_beat_gap, 1)) idle_cycle(1'b0);
        if (vif.drv_cb.rst_n !== 1'b1 || cfg.gate.abort) begin
          if (cfg.gate.abort) cfg.gate.n_abandoned++;
          `uvm_info(get_type_name(), cfg.gate.abort ? "LinkError during a flit; flit abandoned" :
                                     "reset during a flit; flit dropped", UVM_MEDIUM)
          // A half that failed CRC is still cancelled in the cycle after its last
          // chunk (Table 8-2): without it the Protocol Layer may consume the half.
          idle_cycle(cancel_next && cfg.gate.abort);
          cancel_next = 1'b0;
          return;
        end
        vif.drv_cb.pl_valid <= 1'b1;
        vif.drv_cb.pl_flit_cancel <= cancel_next;
        vif.drv_cb.pl_data <= (cancelled && cfg.poison_cancelled) ?
                              poison.get_beat(cfg.beat_bytes, idx) :
                              it.get_beat(cfg.beat_bytes, idx);
        cancel_next = 1'b0;
        @(vif.drv_cb);
      end
      case (seg_cancel[s])
        AOU_CANCEL_IDLE:  idle_cycle(1'b1);
        AOU_CANCEL_VALID: cancel_next = 1'b1;
        default: ;
      endcase
    end
    it.t_end = $time;
    `uvm_info(get_type_name(), {"sent ", it.convert2string()}, UVM_HIGH)
  endtask
endclass
