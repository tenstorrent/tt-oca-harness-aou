// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Delay policy for one channel: how many cycles to wait before the next valid,
// ready or response.
class aou_axi_delay extends uvm_object;
  `uvm_object_utils(aou_axi_delay)

  aou_axi_dly_mode_e mode = AOU_AXI_DLY_ZERO;
  int unsigned fixed_cycles;
  int unsigned min_cycles;
  int unsigned max_cycles = 3;
  int unsigned stall_pct  = 5;
  int unsigned stall_min  = 16;
  int unsigned stall_max  = 64;

  function new(string name = "aou_axi_delay");
    super.new(name);
  endfunction

  function int unsigned next();
    case (mode)
      AOU_AXI_DLY_ZERO:  return 0;
      AOU_AXI_DLY_FIXED: return fixed_cycles;
      AOU_AXI_DLY_RANGE: return $urandom_range(max_cycles, min_cycles);
      default: begin
        if ($urandom_range(99) < stall_pct) return $urandom_range(stall_max, stall_min);
        return $urandom_range(max_cycles, min_cycles);
      end
    endcase
  endfunction

  function void set_zero();
    mode = AOU_AXI_DLY_ZERO;
  endfunction

  function void set_fixed(int unsigned n);
    mode         = AOU_AXI_DLY_FIXED;
    fixed_cycles = n;
  endfunction

  function void set_range(int unsigned lo, int unsigned hi);
    mode       = AOU_AXI_DLY_RANGE;
    min_cycles = lo;
    max_cycles = hi;
  endfunction

  function void set_bursty(int unsigned lo, int unsigned hi, int unsigned pct,
                           int unsigned slo, int unsigned shi);
    mode       = AOU_AXI_DLY_BURSTY;
    min_cycles = lo;
    max_cycles = hi;
    stall_pct  = pct;
    stall_min  = slo;
    stall_max  = shi;
  endfunction

  function string convert2string();
    return $sformatf("%s fixed=%0d range=[%0d:%0d] stall=%0d%%[%0d:%0d]", mode.name(),
                     fixed_cycles, min_cycles, max_cycles, stall_pct, stall_min, stall_max);
  endfunction
endclass
