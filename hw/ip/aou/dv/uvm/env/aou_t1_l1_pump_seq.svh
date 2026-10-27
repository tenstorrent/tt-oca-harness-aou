// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3 -> L1: runs on the L1 sequencer for the whole test, pulling each flit L3
// builds (tx_flit_export, blocks until L3 has one) and driving it with a
// random cancel plan, gaps and bubbles. L1 drives only while L2 reports
// Active (or, with +fdi_rx_early, an RX that is already Active in Reset). A flit L3 built before a reset (flush(), from the env's
// reset_flush) is dropped rather than sent after the link recovers: it holds
// stale credits and messages.
class aou_t1_l1_pump_seq extends uvm_sequence #(aou_flit_item);
  `uvm_object_utils(aou_t1_l1_pump_seq)

  aou_l3_agent  l3;
  aou_fdi_agent fdi;
  int unsigned  n_dropped;
  protected int unsigned flush_gen;
  int unsigned cancel_pct = 10;
  int unsigned gap_pct = 10;
  int unsigned bubble_pct = 10;
  bit          cancel_mix = 1'b0;  // cancel plans over every shape (aou_flit_item::mix_cancel_plan)
  int unsigned n_flits;
  bit          busy;    // holding a flit L3 built that L1 has not finished driving

  function new(string name = "aou_t1_l1_pump_seq");
    super.new(name);
  endfunction

  function void flush();
    flush_gen++;
  endfunction

  task body();
    if (l3 == null || fdi == null) `uvm_fatal(get_type_name(), "l3 or fdi not set")
    forever begin
      aou_l3_flit_item lit;
      aou_flit_item it;
      bit cancel;
      bit gap;
      int unsigned gen;
      l3.tx_flit_export.get(lit);
      busy = 1'b1;
      gen = flush_gen;   // L3 built the flit in this time step
      // Hand the flit to L1 only once the link can receive (Active, or Reset
      // with +fdi_rx_early), so a reset while it waits can still cancel it.
      while (!fdi.cfg.gate.rx_open() && gen == flush_gen) @(fdi.vif.mon_cb);
      if (gen != flush_gen) begin
        n_dropped++;
        busy = 1'b0;
        `uvm_info(get_type_name(), "flit built before a reset dropped", UVM_MEDIUM)
        continue;
      end
      it = aou_flit_item::type_id::create("it");
      cancel = $urandom_range(99) < cancel_pct;
      gap = $urandom_range(99) < gap_pct;
      start_item(it);
      `AOU_RANDOMIZE_WITH(it, {
        if (!cancel) { cancel_h0 == AOU_CANCEL_NONE; cancel_h1 == AOU_CANCEL_NONE; }
        else { cancel_h0 != AOU_CANCEL_NONE || cancel_h1 != AOU_CANCEL_NONE; }
        if (!gap) pre_gap == 0; else pre_gap inside {[1:6]};
        beat_gap_pct == bubble_pct;
      })
      if (cancel && cancel_mix) it.mix_cancel_plan();
      foreach (it.data[i]) it.data[i] = lit.bytes[i];
      it.clear_adapter_bytes();
      if (it.data[0][7:6] == 2'b00) it.data[0][7:6] = 2'b11;
      finish_item(it);
      n_flits++;
      busy = 1'b0;
    end
  endtask
endclass
