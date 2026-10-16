// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base for manager sequences. send() queues a transaction without waiting for
// it; completions arrive through response_handler() and on_done(), and
// wait_all() blocks until every sent transaction has completed.
class aou_axi_base_seq extends uvm_sequence #(aou_axi_txn);
  `uvm_object_utils(aou_axi_base_seq)
  `uvm_declare_p_sequencer(aou_axi_sequencer)

  int unsigned n_sent;
  int unsigned n_done;

  protected semaphore done_sem;
  protected int unsigned n_waited;

  function new(string name = "aou_axi_base_seq");
    super.new(name);
    done_sem = new(0);
    use_response_handler(1);
  endfunction

  function aou_axi_txn new_txn(string name = "txn");
    aou_axi_txn t = aou_axi_txn::type_id::create(name);
    t.data_bytes = p_sequencer.cfg.data_bytes;
    t.rp         = p_sequencer.cfg.rp;
    return t;
  endfunction

  // Queue t; t must be fully formed (randomized, or with data/strb for a write).
  task send(aou_axi_txn t);
    start_item(t);
    finish_item(t);
    n_sent++;
  endtask

  virtual function void response_handler(uvm_sequence_item response);
    aou_axi_txn t;
    if (!$cast(t, response)) `uvm_fatal(get_type_name(), "response is not an aou_axi_txn")
    n_done++;
    on_done(t);
    done_sem.put(1);
  endfunction

  // Hook for subclasses: called once per completed transaction.
  virtual function void on_done(aou_axi_txn t);
  endfunction

  task wait_all();
    if (n_sent > n_waited) done_sem.get(n_sent - n_waited);
    n_waited = n_sent;
  endtask
endclass
