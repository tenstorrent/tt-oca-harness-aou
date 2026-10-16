// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One transaction, sent and waited for; `done` holds it with its response.
// The request fields are set before start(); a write carries full strobes.
class aou_attr_one_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_attr_one_seq)

  aou_axi_dir_e dir = AOU_AXI_RD;
  bit [9:0]     id = '0;
  bit [63:0]    addr = '0;
  bit [7:0]     len = '0;
  bit [2:0]     size = '0;
  bit           lock = 1'b0;
  bit [3:0]     cache = '0;
  bit [2:0]     prot = '0;
  bit [3:0]     qos = '0;
  aou_axi_txn   done;

  function new(string name = "aou_attr_one_seq");
    super.new(name);
  endfunction

  task body();
    aou_axi_txn t = new_txn("one");
    t.dir   = dir;
    t.id    = id;
    t.addr  = addr;
    t.len   = len;
    t.size  = size;
    t.burst = AOU_AXI_INCR;
    t.lock  = lock;
    t.cache = cache;
    t.prot  = prot;
    t.qos   = qos;
    if (dir == AOU_AXI_WR) t.fill_wdata(AOU_AXI_STRB_FULL);
    send(t);
    wait_all();
  endtask

  function void on_done(aou_axi_txn t);
    done = t;
  endfunction
endclass
