// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One 256B Format 6 flit. For driving it carries a cancel plan per 128B half
// and idle gaps; the monitor fills in what it observed.
//
// Cancel plan (UCIe r3.0 §10.2.5):
//   cancel_h0 only        H0 (cancelled), H0, H1
//   cancel_h0 and h1      H0 (cancelled), H1 (cancelled), H0, H1
//   cancel_h1 only        H0, H1 (cancelled), then either
//                         h1_replay_resend_h0=1: H0 (cancelled again), H1
//                         h1_replay_resend_h0=0: H1
// The kind of each cancel (IDLE or VALID) is the kind given for that half.
// cancel_repeat > 1 cancels the first cancelled half that many times in a row
// before it goes through (cancel_h0 only, or cancel_h1 without the resend).
// From 256 B up the flit is one beat and the cancel unit is the transfer: any
// plan with a cancel becomes cancel_repeat cancels of the first cancelled
// half's kind, then the flit; the monitor counts them in n_cancel_h0. On a 512
// or 1024 B FDI several flits share a transfer, and the plan of the transfer's
// first flit is the plan of all of them (a cancel applies to every flit in
// its clock, UCIe r3.0 10.3.1).
class ucie_flit_item extends uvm_sequence_item;
  `uvm_object_utils(ucie_flit_item)

  bit [7:0]             data[FLIT_BYTES];
  int unsigned          phy = 0;
  ucie_fdi_dir_e         dir = UCIE_FDI_RX;

  rand ucie_fdi_cancel_e cancel_h0;
  rand ucie_fdi_cancel_e cancel_h1;
  rand bit              h1_replay_resend_h0;
  rand int unsigned     cancel_repeat;
  rand int unsigned     pre_gap;       // idle cycles before the first beat
  rand int unsigned     beat_gap_pct;  // chance of idle cycles before each later beat
  rand int unsigned     max_beat_gap;  // longest such gap

  // The solver behind Verilator's randomize() can pick enum values that have
  // no name unless they are excluded.
  constraint c_plan {
    cancel_h0 inside {UCIE_CANCEL_NONE, UCIE_CANCEL_IDLE, UCIE_CANCEL_VALID};
    cancel_h1 inside {UCIE_CANCEL_NONE, UCIE_CANCEL_IDLE, UCIE_CANCEL_VALID};
    soft cancel_h0 == UCIE_CANCEL_NONE;
    soft cancel_h1 == UCIE_CANCEL_NONE;
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
  time                  t_beat[MAX_BEATS_PER_FLIT];  // when each beat was collected (index: beat)

  function new(string name = "ucie_flit_item");
    super.new(name);
  endfunction

  // Beat idx of this flit on an FDI of beat_bytes, in lane `lane` of the
  // transfer (bytes 256*lane up; lane 0 below 512 B), other bytes zero.
  function ucie_fdi_beat_t get_beat(int unsigned beat_bytes, int unsigned idx,
                                    int unsigned lane = 0);
    ucie_fdi_beat_t b = '0;
    int unsigned n = flit_chunk_bytes(beat_bytes);
    for (int unsigned i = 0; i < n; i++) b[8*(lane*FLIT_BYTES + i) +: 8] = data[idx*n + i];
    return b;
  endfunction

  function void put_beat(int unsigned beat_bytes, int unsigned idx, ucie_fdi_beat_t b,
                         int unsigned lane = 0);
    int unsigned n = flit_chunk_bytes(beat_bytes);
    for (int unsigned i = 0; i < n; i++) data[idx*n + i] = b[8*(lane*FLIT_BYTES + i) +: 8];
    if (idx < MAX_BEATS_PER_FLIT) t_beat[idx] = $time;
  endfunction

  // A NOP flit: Protocol ID (Byte 0 [7:6]) 00b, whatever the sequence number
  // and Ack/Nak bits in the rest of the Flit Header (UCIe r3.0 Table 3-5). The
  // zero lanes of a wide transfer (Flit Header 0000h, §10.3.1) are a case of
  // it. The Protocol Layer discards a NOP that arrives uncancelled (Table 10-3
  // pl_flit_cancel).
  function bit is_nop();
    return data[0][7:6] == 2'b00;
  endfunction

  // A D2D Adapter NOP flit as an Adapter may forward it: Protocol ID and Flit
  // Type (Byte 1 [7:6]) 00b, a random sequence number (Byte 0 [3:0], Byte 1
  // [3:0]), Ack/Nak field (Byte 1 [5:4]: 00b, 01b or 10b, as 11b is
  // reserved; r3.0 Table 3-5) and CRC, and a body of all zeros (r3.0 §3.1:
  // "the body of the Flit is filled with all 0 data").
  function void make_nop();
    clear();
    data[0] = {4'h0, 4'($urandom)};
    data[1] = {2'b00, 6'($urandom)};
    // Ack/Nak 11b is reserved: make it Ack or Nak, with no extra random draw.
    if (data[1][5:4] == 2'b11) data[1][5:4] = {data[1][0], ~data[1][0]};
    data[126] = 8'($urandom); data[127] = 8'($urandom);
    data[254] = 8'($urandom); data[255] = 8'($urandom);
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

  // The Protocol ID (Byte 0 [7:6]) stays: 00b would make the flit a NOP. So
  // does the Flit Type (Byte 1 [7:6], 00b for a protocol flit; r3.0 Table
  // 3-5): the Adapter hands the Protocol Layer protocol flits, never Test
  // (01b) or, on a modelled stream, Management (10b) flits.
  function void randomize_adapter_bytes();
    data[0] = {data[0][7:6], 6'($urandom)}; data[1] = {data[1][7:6], 6'($urandom)};
    data[126] = 8'($urandom); data[127] = 8'($urandom);
    data[254] = 8'($urandom); data[255] = 8'($urandom);
  endfunction

  // Format 6 TX rule of the modelled layout (r3.0 §3.3.4, Table 3-5): every
  // Adapter-owned bit zero, Byte 1 included (its [7:6], the Flit Type, is 00b
  // for a protocol flit), and a Protocol ID (Byte 0 [7:6]) other than 00b
  // unless nop_legal: a Streaming Protocol Layer must never send 00b, a NOP
  // (stream_tx_nop_legal).
  function bit tx_adapter_bytes_legal(bit nop_legal = 1'b0);
    return (nop_legal || data[0][7:6] != 2'b00) && data[0][5:0] == 6'h00 && data[1] == 8'h00 &&
           data[126] == 8'h00 && data[127] == 8'h00 && data[254] == 8'h00 && data[255] == 8'h00;
  endfunction

  // Payload comparison; Adapter-owned bytes never take part.
  function bit same_payload(ucie_flit_item rhs);
    foreach (data[i]) if (!is_adapter_byte(i) && data[i] != rhs.data[i]) return 1'b0;
    return 1'b1;
  endfunction

  function void copy_data(ucie_flit_item rhs);
    data = rhs.data;
  endfunction

  // A cancel plan drawn evenly over the four shapes above (first half,
  // second half, both, second half with the first resent), each cancel IDLE
  // or VALID, and a single-half cancel repeated 1-3 times (UCIe r3.0
  // Table 10-3 pl_flit_cancel: the Adapter replays a half until it goes
  // through uncancelled).
  function void mix_cancel_plan();
    ucie_fdi_cancel_e k0 = $urandom_range(1) != 0 ? UCIE_CANCEL_VALID : UCIE_CANCEL_IDLE;
    ucie_fdi_cancel_e k1 = $urandom_range(1) != 0 ? UCIE_CANCEL_VALID : UCIE_CANCEL_IDLE;
    int unsigned shape = $urandom_range(3);
    cancel_repeat = $urandom_range(3, 1);
    h1_replay_resend_h0 = 1'b0;
    cancel_h0 = UCIE_CANCEL_NONE;
    cancel_h1 = UCIE_CANCEL_NONE;
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
    return cancel_h0 != UCIE_CANCEL_NONE || cancel_h1 != UCIE_CANCEL_NONE;
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
