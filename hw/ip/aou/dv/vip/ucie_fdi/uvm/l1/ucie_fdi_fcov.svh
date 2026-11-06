// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The model's own mainband coverage: plain SystemVerilog covergroups, one
// collector per FDI, built by the agent when cfg.fcov_en is set and sampled by
// its monitor next to a bench's ucie_fdi_cov collector. It implements
// ucie_fdi_cov for the events every collector sees, and takes the rest
// (wide-FDI lanes, pl_trdy outcomes) through methods of its own. Bins that
// only some FDI widths can reach (a TX stall inside a flit, a half cancel, a
// NOP lane) are reached by the runs at those widths: the number that counts
// is the coverage merged over the self-test's widths.
class ucie_fdi_fcov extends uvm_object implements ucie_fdi_cov;
  `uvm_object_utils(ucie_fdi_fcov)

  int unsigned fdi_bytes = 64;  // the FDI width (the agent sets it)

  // cg_xfer: a completed flit
  bit          x_rx;
  int unsigned x_width;
  int unsigned x_stall;   // pl_trdy-low cycles (TX) or bubbles (RX) inside the flit
  int unsigned x_gap;     // idle cycles before it
  // cg_cancel: an RX cancel. Unit: 0, 1 a 128B half; 2 the flit (256 B);
  // 3 every flit of a 512 or 1024 B transfer.
  int unsigned c_unit;
  bit          c_valid;   // the replay's first beat rode in the cancel cycle
  int unsigned c_count;   // cancels so far on this flit
  bit          c_stalled; // the TX side was stalled at the time
  // cg_stall: a completed stall handshake. Where: 0 at a flit boundary, 1
  // inside a TX flit with pl_trdy high, 2 inside one with pl_trdy low.
  int unsigned s_where;
  int unsigned s_lat;
  int unsigned s_hold;
  // cg_abandon
  bit          a_rx;
  // cg_lanes: an RX transfer of a 512 or 1024 B FDI, as flits carried:
  // 512 B: 1 or 2, 1024 B: 1 to 4 (the rest NOP lanes); code width/256 * 8 + n.
  int unsigned l_code;
  // cg_trdy: a run of pl_trdy low in Active, ended. Outcome: the policy
  // (ucie_fdi_trdy_e: 1 RANDOM, 2 BURSTY, 3 HOLES) times 2, plus 1 when the run
  // started inside a TX flit; length in cycles.
  int unsigned t_outcome;
  int unsigned t_len;
  // cg_error: a pl_error, by the cancel unit (0, 1 a 128B half; 2 the flit at
  // 256 B; 3 every flit of a wider transfer) times 4 plus the transfer of the
  // unit it rode on (0 first, 1 inside, 2 last, 3 the only one).
  int unsigned e_code;
  // cg_corrupt: a TX transfer of flits with lp_corrupt_crc: 0 on the second
  // 128B half only, 1 on both, 2 on the flit (256 B), 3 on every flit of a
  // wider transfer.
  int unsigned k_kind;

  covergroup cg_xfer;
    cp_dir: coverpoint x_rx {
      bins tx = {0};
      bins rx = {1};
    }
    cp_width: coverpoint x_width {
      bins w32 = {32};
      bins w64 = {64};
      bins w128 = {128};
      bins w256 = {256};
      bins w512 = {512};
      bins w1024 = {1024};
    }
    cp_stall: coverpoint x_stall {
      bins none = {0};
      bins one = {1};
      bins few = {[2:7]};
      bins many = {[8:$]};
    }
    cp_gap: coverpoint x_gap {
      bins back_to_back = {0};
      bins one = {1};
      bins few = {[2:7]};
      bins long = {[8:$]};
    }
    x_dir_width: cross cp_dir, cp_width;
    x_dir_stall: cross cp_dir, cp_stall;
    x_dir_gap: cross cp_dir, cp_gap;
  endgroup

  covergroup cg_cancel;
    cp_unit: coverpoint c_unit {
      bins half0 = {0};
      bins half1 = {1};
      bins flit = {2};
      bins transfer = {3};
    }
    cp_kind: coverpoint c_valid {
      bins idle = {0};
      bins with_replay = {1};
    }
    cp_repeat: coverpoint c_count {
      bins first = {1};
      bins second = {2};
      bins more = {[3:$]};
    }
    cp_stalled: coverpoint c_stalled {
      bins no = {0};
      bins yes = {1};
    }
    x_unit_kind: cross cp_unit, cp_kind;
  endgroup

  covergroup cg_stall;
    cp_where: coverpoint s_where {
      bins boundary = {0};
      bins mid_trdy_high = {1};
      bins mid_trdy_low = {2};
    }
    cp_lat: coverpoint s_lat {
      bins one = {1};
      bins few = {[2:7]};
      bins long = {[8:$]};
    }
    // lp_stallack lasts at least 2 cycles: it may not fall while pl_stallreq is
    // high (FDI-R09), and pl_stallreq falls only after it saw lp_stallack
    // (FDI-R08). The shortest the model makes (stall_hold_min 0) is 2 or 3.
    cp_hold: coverpoint s_hold {
      bins short = {[2:3]};
      bins few = {[4:7]};
      bins long = {[8:$]};
    }
  endgroup

  covergroup cg_abandon;
    cp_dir: coverpoint a_rx {
      bins tx = {0};
      bins rx = {1};
    }
  endgroup

  covergroup cg_lanes;
    cp_flits: coverpoint l_code {
      bins w512_one = {17};
      bins w512_full = {18};
      bins w1024_one = {33};
      bins w1024_two = {34};
      bins w1024_three = {35};
      bins w1024_full = {36};
    }
  endgroup

  covergroup cg_trdy;
    cp_outcome: coverpoint t_outcome {
      bins random_at_boundary = {2};
      bins random_inside_flit = {3};
      bins bursty_at_boundary = {4};
      bins bursty_inside_flit = {5};
      bins holes_inside_flit = {7};
    }
    cp_len: coverpoint t_len {
      bins one = {1};
      bins few = {[2:3]};
      bins some = {[4:7]};
      bins long = {[8:$]};
    }
  endgroup

  covergroup cg_error;
    cp_where: coverpoint e_code {
      bins half0_first = {0};
      bins half0_inside = {1};
      bins half0_last = {2};
      bins half1_first = {4};
      bins half1_inside = {5};
      bins half1_last = {6};
      bins flit = {11};
      bins transfer = {15};
    }
  endgroup

  covergroup cg_corrupt;
    cp_kind: coverpoint k_kind {
      bins second_half = {0};
      bins both_halves = {1};
      bins flit = {2};
      bins transfer = {3};
    }
  endgroup

  function new(string name = "ucie_fdi_fcov");
    super.new(name);
    cg_xfer = new();
    cg_cancel = new();
    cg_stall = new();
    cg_abandon = new();
    cg_lanes = new();
    cg_trdy = new();
    cg_error = new();
    cg_corrupt = new();
  endfunction

  virtual function void sample_xfer(ucie_fdi_dir_e dir, int unsigned beat_bytes,
                                    int unsigned stall, int unsigned gap);
    x_rx = dir == UCIE_FDI_RX;
    x_width = beat_bytes;
    x_stall = stall;
    x_gap = gap;
    cg_xfer.sample();
  endfunction

  // From the monitor: half is 0, 1 or 2 (ucie_fdi_cov); a whole-transfer cancel
  // wider than a flit is told apart here by the width.
  virtual function void sample_cancel(int unsigned half, bit with_valid, int unsigned count,
                                      bit stalled);
    c_unit = (half == 2 && fdi_bytes > FLIT_BYTES) ? 3 : half;
    c_valid = with_valid;
    c_count = count;
    c_stalled = stalled;
    cg_cancel.sample();
  endfunction

  virtual function void sample_stall(int unsigned lat, int unsigned hold, bit mid, bit trdy0);
    s_where = !mid ? 0 : trdy0 ? 2 : 1;
    s_lat = lat;
    s_hold = hold;
    cg_stall.sample();
  endfunction

  virtual function void sample_abandon(bit rx);
    a_rx = rx;
    cg_abandon.sample();
  endfunction

  // An RX transfer of a 512 or 1024 B FDI carrying n flits.
  function void sample_lanes(int unsigned n);
    l_code = fdi_bytes / FLIT_BYTES * 8 + n;
    cg_lanes.sample();
  endfunction

  // A run of pl_trdy low in Active that ended after len cycles; in_flit: it
  // started inside a TX flit.
  function void sample_trdy(ucie_fdi_trdy_e policy, bit in_flit, int unsigned len);
    t_outcome = int'(policy) * 2 + int'(in_flit);
    t_len = len;
    cg_trdy.sample();
  endfunction

  // A pl_error on transfer pos (0 first, 1 inside, 2 last, 3 the only one) of
  // cancel unit `unit` (see e_code).
  function void sample_error(int unsigned unit, int unsigned pos);
    e_code = unit * 4 + pos;
    cg_error.sample();
  endfunction

  // A TX transfer of flits with lp_corrupt_crc; h0: also on the first half.
  function void sample_corrupt(bit h0);
    k_kind = fdi_bytes > FLIT_BYTES ? 3 : fdi_bytes == FLIT_BYTES ? 2 : int'(h0);
    cg_corrupt.sample();
  endfunction

  // Each covergroup's coverage, for the end-of-test report (type scores).
  // Not asked of Verilator: 5.052 does not score covergroups, and asking it
  // leaves internal variables undriven (lint).
  function string convert2string();
`ifdef VERILATOR
    return "not scored by this simulator";
`else
    return $sformatf({"xfer %0.1f%% cancel %0.1f%% stall %0.1f%% abandon %0.1f%% lanes %0.1f%% ",
                      "trdy %0.1f%% error %0.1f%% corrupt %0.1f%%"}, cg_xfer.get_coverage(),
                     cg_cancel.get_coverage(), cg_stall.get_coverage(),
                     cg_abandon.get_coverage(), cg_lanes.get_coverage(),
                     cg_trdy.get_coverage(), cg_error.get_coverage(),
                     cg_corrupt.get_coverage());
`endif
  endfunction
endclass
