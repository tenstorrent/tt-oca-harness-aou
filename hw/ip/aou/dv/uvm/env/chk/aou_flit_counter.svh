// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Records when the DUT started each flit it sent on FDI (L1 monitor ap_tx),
// so a sequence can count flits inside a time window (LP mode tests).
class aou_flit_counter extends uvm_subscriber #(aou_flit_item);
  `uvm_component_utils(aou_flit_counter)

  protected time t_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void write(aou_flit_item t);
    t_q.push_back(t.t_start);
  endfunction

  // Flits that started in [t0, t1).
  function int unsigned count(time t0, time t1);
    int unsigned n = 0;
    foreach (t_q[i]) if (t_q[i] >= t0 && t_q[i] < t1) n++;
    return n;
  endfunction

  function int unsigned total();
    return t_q.size();
  endfunction
endclass
