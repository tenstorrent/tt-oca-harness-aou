// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// A traffic profile: which AXI sequence runs, its knobs, and the timing
// policies applied to the agents while it runs. named() returns the profiles
// the run lists use.
class aou_t1_traffic_cfg extends uvm_object;
  `uvm_object_utils(aou_t1_traffic_cfg)

  aou_t1_seq_kind_e kind = AOU_T1_SEQ_RAND;
  // aou_axi_rand_seq knobs. The AoU wire has no AxBURST and the DUT sends
  // every burst as INCR (spec §2.5), so FIXED and WRAP stay off by default.
  int unsigned   wr_pct    = 50;
  int unsigned   lock_pct  = 0;
  int unsigned   fixed_pct = 0;
  int unsigned   wrap_pct  = 0;
  int unsigned   num_slots = 16;
  bit [9:0]      max_id    = 10'd7;
  bit [7:0]      max_len   = 8'd63;
  bit [7:0]      min_len   = 8'd0;
  aou_axi_strb_e strb_mode = AOU_AXI_STRB_MIXED;
  // Address window per RP and direction: base + rp * rp_stride, span bytes.
  bit [63:0]     base      = 64'h0000_0001_0000_0000;
  bit [63:0]     span      = 64'h0000_0000_0004_0000;
  bit [63:0]     rp_stride = 64'h0000_0001_0000_0000;
  // RPs that carry this traffic (bit r: RP r)
  bit [3:0]      rp_mask   = 4'hF;
  // Timing of the local agents and the remote model; keep_timing leaves the
  // agents as configured.
  bit              keep_timing = 1'b1;
  aou_axi_timing_e timing = AOU_AXI_TIMING_RANDOM;

  function new(string name = "aou_t1_traffic_cfg");
    super.new(name);
  endfunction

  static function aou_t1_traffic_cfg named(string profile);
    aou_t1_traffic_cfg c = aou_t1_traffic_cfg::type_id::create(profile);
    case (profile)
      "unaligned": begin
        c.kind = AOU_T1_SEQ_UNALIGNED;
        c.base = 64'h0000_0040_0010_0000;
      end
      "b_zero": begin
        c.kind = AOU_T1_SEQ_B_ZERO;
        c.base = 64'h0000_0040_0080_0000;
        c.keep_timing = 1'b0;
        c.timing = AOU_AXI_TIMING_ZERO;
      end
      "long": c.max_len = 8'd255;
      "short": c.max_len = 8'd3;
      "narrow": c.strb_mode = AOU_AXI_STRB_RANDOM;
      "stall": begin
        c.keep_timing = 1'b0;
        c.timing = AOU_AXI_TIMING_STALL;
      end
      "rand": ;
      default: `uvm_fatal("aou_t1_traffic_cfg", {"unknown traffic profile ", profile})
    endcase
    return c;
  endfunction

  function string convert2string();
    return $sformatf("%s wr=%0d%% lock=%0d%% len=%0d..%0d max_id=%0d base=%0h rps=%4b timing=%s",
                     kind.name(), wr_pct, lock_pct, min_len, max_len, max_id, base, rp_mask,
                     keep_timing ? "kept" : timing.name());
  endfunction
endclass
