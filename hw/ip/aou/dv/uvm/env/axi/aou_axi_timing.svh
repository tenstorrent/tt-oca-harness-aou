// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Per-channel timing policy of one agent. The manager uses the *_valid delays
// (cycles before presenting each AW, W beat or AR) and b_ready/r_ready (cycles
// ready stays low after each B/R handshake). The subordinate uses the *_ready
// delays (cycles ready stays low after each handshake), b_lat (cycles from the
// write's last AW/W handshake to BVALID), r_lat (cycles from the AR handshake
// to the first RVALID) and r_beat (cycles between R beats). A delay of 0 means
// back to back: ready held high, or B/R valid in the cycle after the handshake.
class aou_axi_timing extends uvm_object;
  `uvm_object_utils(aou_axi_timing)

  aou_axi_delay aw_valid, w_valid, ar_valid, b_ready, r_ready;
  aou_axi_delay aw_ready, w_ready, ar_ready, b_lat, r_lat, r_beat;

  function new(string name = "aou_axi_timing");
    super.new(name);
    aw_valid = aou_axi_delay::type_id::create("aw_valid");
    w_valid  = aou_axi_delay::type_id::create("w_valid");
    ar_valid = aou_axi_delay::type_id::create("ar_valid");
    b_ready  = aou_axi_delay::type_id::create("b_ready");
    r_ready  = aou_axi_delay::type_id::create("r_ready");
    aw_ready = aou_axi_delay::type_id::create("aw_ready");
    w_ready  = aou_axi_delay::type_id::create("w_ready");
    ar_ready = aou_axi_delay::type_id::create("ar_ready");
    b_lat    = aou_axi_delay::type_id::create("b_lat");
    r_lat    = aou_axi_delay::type_id::create("r_lat");
    r_beat   = aou_axi_delay::type_id::create("r_beat");
  endfunction

  function void apply(aou_axi_timing_e profile);
    aou_axi_delay all[$] = '{aw_valid, w_valid, ar_valid, b_ready, r_ready,
                              aw_ready, w_ready, ar_ready, b_lat, r_lat, r_beat};
    foreach (all[i]) all[i].set_zero();
    case (profile)
      AOU_AXI_TIMING_ZERO: ;
      AOU_AXI_TIMING_RANDOM: foreach (all[i]) all[i].set_range(0, 3);
      AOU_AXI_TIMING_STALL:  foreach (all[i]) all[i].set_bursty(0, 1, 4, 10, 60);
      AOU_AXI_TIMING_SLOW_SUB: begin
        aw_ready.set_range(0, 6);
        w_ready.set_range(0, 6);
        ar_ready.set_range(0, 6);
        b_lat.set_range(5, 40);
        r_lat.set_range(5, 40);
        r_beat.set_range(0, 4);
      end
      default: begin
        aw_valid.set_range(0, 8);
        w_valid.set_range(0, 6);
        ar_valid.set_range(0, 8);
        b_ready.set_range(0, 10);
        r_ready.set_range(0, 6);
      end
    endcase
  endfunction
endclass
