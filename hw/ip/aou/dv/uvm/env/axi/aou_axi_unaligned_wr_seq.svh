// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Issue #56: single-beat writes of every size at every byte offset within the
// bus word, each in its own bus word, then the same accesses as reads.
class aou_axi_unaligned_wr_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_axi_unaligned_wr_seq)

  bit [63:0] base = 64'h0000_0040_0010_0000;
  bit        read_back = 1'b1;

  function new(string name = "aou_axi_unaligned_wr_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned db  = p_sequencer.cfg.data_bytes;
    int unsigned msz = p_sequencer.cfg.max_size();
    aou_axi_dir_e dirs[$] = '{AOU_AXI_WR, AOU_AXI_RD};
    aou_axi_txn t;
    foreach (dirs[d]) begin
      if (dirs[d] == AOU_AXI_RD && !read_back) break;
      for (int unsigned s = 0; s <= msz; s++) begin
        for (int unsigned off = 0; off < db; off++) begin
          t       = new_txn($sformatf("unal_s%0d_o%0d", s, off));
          t.dir   = dirs[d];
          t.id    = 10'(off % 16);
          t.addr  = base + 64'(s * db * db + off * db + off);
          t.len   = 8'd0;
          t.size  = 3'(s);
          t.burst = (off % 2 == 1 && !p_sequencer.cfg.incr_only) ? AOU_AXI_FIXED : AOU_AXI_INCR;
          t.lock  = 1'b0;
          t.cache = 4'(off);
          t.prot  = 3'(s);
          t.qos   = 4'(off >> 2);
          if (t.dir == AOU_AXI_WR) t.fill_wdata(AOU_AXI_STRB_FULL);
          send(t);
        end
      end
      wait_all();
    end
  endtask
endclass
