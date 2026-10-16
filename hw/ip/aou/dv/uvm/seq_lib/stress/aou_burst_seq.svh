// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// n transactions of one shape at consecutive 4KB pages from base, sent
// without waiting (send_all), then waited for (wait_all). Completed
// transactions, with their address-handshake time, collect in done_q.
class aou_burst_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_burst_seq)

  int unsigned  n = 8;
  aou_axi_dir_e dir = AOU_AXI_RD;
  bit [63:0]    base = 64'h0;
  bit [7:0]     len = 8'd0;
  bit [3:0]     qos = 4'd0;
  bit [9:0]     id = 10'd0;
  bit           same_id = 1'b0;
  aou_axi_txn   done_q[$];

  function new(string name = "aou_burst_seq");
    super.new(name);
  endfunction

  task body();
    for (int unsigned i = 0; i < n; i++) begin
      aou_axi_txn t = new_txn($sformatf("b%0d", i));
      t.dir   = dir;
      t.id    = same_id ? id : id + 10'(i);
      t.addr  = base + 64'(i) * 64'h1000;
      t.len   = len;
      t.size  = 3'($clog2(t.data_bytes));
      t.burst = AOU_AXI_INCR;
      t.qos   = qos;
      if (dir == AOU_AXI_WR) t.fill_wdata(AOU_AXI_STRB_FULL);
      send(t);
    end
    wait_all();
  endtask

  virtual function void on_done(aou_axi_txn t);
    done_q.push_back(t);
  endfunction
endclass
