// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// aou_dp_seq with fixed write-data patterns (+dp_pattern=): walk1 / walk0 (a
// single 1 or 0 that moves one bit per beat across each beat's active lanes,
// so every bit of the data path carries it in turn), ones, zeros, checker
// (0x55/0xAA alternating by beat) and addr (every 8-byte word holds its own
// byte address). With loopback each pattern is read back.
class aou_pattern_seq extends aou_dp_seq;
  `uvm_object_utils(aou_pattern_seq)

  string       pattern = "walk1";
  protected int unsigned walk;

  function new(string name = "aou_pattern_seq");
    super.new(name);
    void'($value$plusargs("dp_pattern=%s", pattern));
  endfunction

  protected virtual function void shape_txn(aou_axi_txn t, bit [63:0] base);
    super.shape_txn(t, base);
    if (t.dir != AOU_AXI_WR) return;
    foreach (t.data[i]) begin
      int unsigned lo = 8 * t.lane_lo(i);
      int unsigned nbits = 8 * (t.lane_hi(i) - t.lane_lo(i) + 1);
      bit [1023:0] one = 1024'd1;
      case (pattern)
        "walk1": t.data[i] = one << (lo + walk % nbits);
        "walk0": t.data[i] = ~(one << (lo + walk % nbits));
        "ones": t.data[i] = '1;
        "zeros": t.data[i] = '0;
        "checker": t.data[i] = {128{(walk % 2 == 0) ? 8'h55 : 8'hAA}};
        "addr": begin
          bit [63:0] a = t.beat_addr(i) & ~(64'(t.data_bytes) - 64'd1);
          for (int unsigned w = 0; w < 16; w++) t.data[i][64*w +: 64] = a + 64'(8 * w);
        end
        default: `uvm_fatal(get_type_name(), {"bad +dp_pattern=", pattern})
      endcase
      walk++;
    end
  endfunction
endclass
