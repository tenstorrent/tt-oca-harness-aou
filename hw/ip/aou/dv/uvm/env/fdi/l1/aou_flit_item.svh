// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One 256B Format 6 flit. For driving it carries a cancel plan per 128B half
// and idle gaps; the monitor fills in what it observed.
//
// Cancel plan (UCIe r1.1 §8.2.5, Synopsys FDI notes §3.3):
//   cancel_h0 only        H0 (cancelled), H0, H1
//   cancel_h0 and h1      H0 (cancelled), H1 (cancelled), H0, H1
//   cancel_h1 only        H0, H1 (cancelled), then either
//                         h1_replay_resend_h0=1: H0 (cancelled again), H1
//                         h1_replay_resend_h0=0: H1
// The kind of each cancel (IDLE or VALID) is the kind given for that half.
// cancel_repeat > 1 cancels the first cancelled half that many times in a row
// before it goes through (cancel_h0 only, or cancel_h1 without the resend).
class aou_flit_item extends uvm_sequence_item;
  `uvm_object_utils(aou_flit_item)

  bit [7:0]             data[FLIT_BYTES];
  int unsigned          phy = 0;
  aou_fdi_dir_e         dir = AOU_FDI_RX;

  rand aou_fdi_cancel_e cancel_h0;
  rand aou_fdi_cancel_e cancel_h1;
  rand bit              h1_replay_resend_h0;
  rand int unsigned     cancel_repeat;
  rand int unsigned     pre_gap;       // idle cycles before the first beat
  rand int unsigned     beat_gap_pct;  // chance of idle cycles before each later beat
  rand int unsigned     max_beat_gap;  // longest such gap

  // The solver behind Verilator's randomize() can pick enum values that have
  // no name unless they are excluded.
  constraint c_plan {
    cancel_h0 inside {AOU_CANCEL_NONE, AOU_CANCEL_IDLE, AOU_CANCEL_VALID};
    cancel_h1 inside {AOU_CANCEL_NONE, AOU_CANCEL_IDLE, AOU_CANCEL_VALID};
    soft cancel_h0 == AOU_CANCEL_NONE;
    soft cancel_h1 == AOU_CANCEL_NONE;
    soft cancel_repeat == 1;
    cancel_repeat inside {[1:4]};
    soft pre_gap == 0;
    soft beat_gap_pct == 0;
    soft max_beat_gap == 2;
    pre_gap <= 64;
    beat_gap_pct <= 100;
    max_beat_gap inside {[1:16]};
  }

  // Observed by the monitor
  int unsigned          n_cancel_h0 = 0; // cancels seen while collecting half 0
  int unsigned          n_cancel_h1 = 0;
  int unsigned          n_cancel_valid = 0; // cancels with pl_valid high in the same cycle
  int unsigned          n_stall_cycles = 0; // TX: trdy-low cycles inside the flit; RX: bubbles
  int unsigned          gap_before;     // idle cycles since the previous flit
  time                  t_start;
  time                  t_end;

  function new(string name = "aou_flit_item");
    super.new(name);
  endfunction

  function aou_fdi_beat_t get_beat(int unsigned beat_bytes, int unsigned idx);
    aou_fdi_beat_t b = '0;
    for (int unsigned i = 0; i < beat_bytes; i++) b[8*i +: 8] = data[idx*beat_bytes + i];
    return b;
  endfunction

  function void put_beat(int unsigned beat_bytes, int unsigned idx, aou_fdi_beat_t b);
    for (int unsigned i = 0; i < beat_bytes; i++) data[idx*beat_bytes + i] = b[8*i +: 8];
  endfunction

  function void clear();
    foreach (data[i]) data[i] = 8'h00;
  endfunction

  function void randomize_payload();
    foreach (data[i]) if (!is_adapter_byte(i)) data[i] = 8'($urandom);
  endfunction

  // The Adapter fills FH (except Byte0[7:6]) and CRC; the PL drives them 0.
  function void clear_adapter_bytes();
    data[0] = data[0] & 8'hC0;
    data[1] = 8'h00;
    data[126] = 8'h00; data[127] = 8'h00;
    data[254] = 8'h00; data[255] = 8'h00;
  endfunction

  function void randomize_adapter_bytes();
    data[0] = 8'($urandom); data[1] = 8'($urandom);
    data[126] = 8'($urandom); data[127] = 8'($urandom);
    data[254] = 8'($urandom); data[255] = 8'($urandom);
  endfunction

  // Format 6 TX rule: Protocol ID (Byte0[7:6]) non-zero, every other
  // Adapter-owned bit zero.
  function bit tx_adapter_bytes_legal();
    return data[0][7:6] != 2'b00 && data[0][5:0] == 6'h00 && data[1] == 8'h00 &&
           data[126] == 8'h00 && data[127] == 8'h00 && data[254] == 8'h00 && data[255] == 8'h00;
  endfunction

  // Payload comparison; Adapter-owned bytes never take part.
  function bit same_payload(aou_flit_item rhs);
    foreach (data[i]) if (!is_adapter_byte(i) && data[i] != rhs.data[i]) return 1'b0;
    return 1'b1;
  endfunction

  function void copy_data(aou_flit_item rhs);
    data = rhs.data;
  endfunction

  // A cancel plan drawn evenly over the four shapes above (first half,
  // second half, both, second half with the first resent), each cancel IDLE
  // or VALID, and a single-half cancel repeated 1-3 times (UCIe r1.1
  // Table 8-2: the Adapter replays a half until it goes through uncancelled).
  function void mix_cancel_plan();
    aou_fdi_cancel_e k0 = $urandom_range(1) != 0 ? AOU_CANCEL_VALID : AOU_CANCEL_IDLE;
    aou_fdi_cancel_e k1 = $urandom_range(1) != 0 ? AOU_CANCEL_VALID : AOU_CANCEL_IDLE;
    int unsigned shape = $urandom_range(3);
    cancel_repeat = $urandom_range(3, 1);
    h1_replay_resend_h0 = 1'b0;
    cancel_h0 = AOU_CANCEL_NONE;
    cancel_h1 = AOU_CANCEL_NONE;
    case (shape)
      0: cancel_h0 = k0;
      1: cancel_h1 = k1;
      2: begin
        cancel_h0 = k0;
        cancel_h1 = k1;
        cancel_repeat = 1;
      end
      default: begin
        cancel_h1 = k1;
        h1_replay_resend_h0 = 1'b1;
        cancel_repeat = 1;
      end
    endcase
  endfunction

  function bit has_cancel();
    return cancel_h0 != AOU_CANCEL_NONE || cancel_h1 != AOU_CANCEL_NONE;
  endfunction

  function string convert2string();
    string s;
    s = $sformatf({"%s phy%0d plan(c0=%s c1=%s rs=%0b x%0d gap=%0d) ",
                   "seen(c0=%0d c1=%0d cv=%0d stall=%0d) "},
                  dir.name(), phy, cancel_h0.name(), cancel_h1.name(), h1_replay_resend_h0,
                  cancel_repeat, pre_gap, n_cancel_h0, n_cancel_h1, n_cancel_valid, n_stall_cycles);
    for (int i = 0; i < 16; i++) s = {s, $sformatf("%02h", data[i])};
    return {s, "..."};
  endfunction
endclass
