// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Sends n_flits flits with random cancel plans and gaps. Payloads are empty
// AoU flits (all zero: no MsgStart, no MsgCredit) unless random_payload is
// set or flits are queued in `payloads`, which go first.
class aou_flit_seq extends uvm_sequence #(aou_flit_item);
  `uvm_object_utils(aou_flit_seq)

  int unsigned  n_flits = 8;
  int unsigned  cancel_pct = 0;   // chance a flit gets a cancel plan
  int unsigned  gap_pct = 30;     // chance of idle cycles before a flit
  int unsigned  bubble_pct;       // chance of a bubble before a beat
  bit           cancel_mix = 1'b0;  // cancel plans over every shape (mix_cancel_plan)
  bit           random_payload = 1'b0;
  bit [1:0]     pid = 2'b11;      // Flit Header Protocol ID when a payload leaves it 0
  aou_flit_item payloads[$];

  function new(string name = "aou_flit_seq");
    super.new(name);
  endfunction

  task body();
    for (int unsigned n = 0; n < n_flits || payloads.size() != 0; n++) begin
      aou_flit_item it = aou_flit_item::type_id::create("flit");
      bit cancel = $urandom_range(99) < cancel_pct;
      bit gap = $urandom_range(99) < gap_pct;
      start_item(it);
      `AOU_RANDOMIZE_WITH(it, {
        if (!cancel) { cancel_h0 == AOU_CANCEL_NONE; cancel_h1 == AOU_CANCEL_NONE; }
        else { cancel_h0 != AOU_CANCEL_NONE || cancel_h1 != AOU_CANCEL_NONE; }
        if (!gap) pre_gap == 0; else pre_gap inside {[1:6]};
        beat_gap_pct == bubble_pct;
      })
      if (cancel && cancel_mix) it.mix_cancel_plan();
      if (payloads.size() != 0) it.copy_data(payloads.pop_front());
      else if (random_payload) it.randomize_payload();
      else it.clear();
      it.clear_adapter_bytes();
      if (it.data[0][7:6] == 2'b00) it.data[0][7:6] = pid;
      finish_item(it);
    end
  endtask
endclass
