// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Issue #64 pattern: back-to-back single-beat full-width writes. With zero
// valid delays on the manager and zero B latency on the subordinate, AW and W
// handshake together and B is presented in the next cycle. Reads of the same
// words follow, for R in the cycle after AR.
class aou_axi_b_zero_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_axi_b_zero_seq)

  int unsigned num_txns = 64;
  bit [63:0]   base     = 64'h0000_0040_0080_0000;

  function new(string name = "aou_axi_b_zero_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned db = p_sequencer.cfg.data_bytes;
    aou_axi_txn t;
    for (int unsigned pass = 0; pass < 2; pass++) begin
      for (int unsigned n = 0; n < num_txns; n++) begin
        t       = new_txn($sformatf("bzero%0d_%0d", pass, n));
        t.dir   = pass == 0 ? AOU_AXI_WR : AOU_AXI_RD;
        t.id    = 10'(n % 4);
        t.addr  = base + 64'(n * db);
        t.len   = 8'd0;
        t.size  = 3'(p_sequencer.cfg.max_size());
        t.burst = AOU_AXI_INCR;
        t.lock  = 1'b0;
        t.cache = 4'd0;
        t.prot  = 3'd0;
        t.qos   = 4'd0;
        if (t.dir == AOU_AXI_WR) t.fill_wdata(AOU_AXI_STRB_FULL);
        send(t);
      end
      wait_all();
    end
  endtask
endclass
