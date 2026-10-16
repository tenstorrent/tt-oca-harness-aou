// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Sends the prepared transactions in `items` back to back, then waits for
// all of them; `done_q` holds them in completion order, with responses.
class aou_txn_list_seq extends aou_axi_base_seq;
  `uvm_object_utils(aou_txn_list_seq)

  aou_axi_txn items[$];
  aou_axi_txn done_q[$];

  function new(string name = "aou_txn_list_seq");
    super.new(name);
  endfunction

  task body();
    foreach (items[i]) send(items[i]);
    wait_all();
  endtask

  function void on_done(aou_axi_txn t);
    done_q.push_back(t);
  endfunction
endclass
