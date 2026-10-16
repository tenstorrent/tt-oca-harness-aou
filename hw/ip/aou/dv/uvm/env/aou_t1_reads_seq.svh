// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// n single-beat full-width reads of consecutive bus words from base, all sent
// before any completes; waits for every response (or abort).
class aou_t1_reads_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_t1_reads_seq)

  int unsigned n = 1;
  bit [63:0]   base = 64'h0000_0050_0000_0000;

  function new(string name = "aou_t1_reads_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned db = p_sequencer.cfg.data_bytes;
    for (int unsigned i = 0; i < n; i++) begin
      aou_axi_txn t = new_txn($sformatf("rd%0d", i));
      t.dir   = AOU_AXI_RD;
      t.id    = 10'(i % 8);
      t.addr  = base + 64'(i * db);
      t.len   = 8'd0;
      t.size  = 3'(p_sequencer.cfg.max_size());
      t.burst = AOU_AXI_INCR;
      t.lock  = 1'b0;
      t.cache = 4'd0;
      t.prot  = 3'd0;
      t.qos   = 4'd0;
      send(t);
    end
    wait_all();
  endtask
endclass
