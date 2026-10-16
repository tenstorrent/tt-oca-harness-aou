// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L1 -> L3: every flit the DUT sent (L1 monitor ap_tx, after cancel rollback)
// becomes an aou_l3_flit_item by a byte copy (docs/ARCHITECTURE.md, "L1 <-> L3").
class aou_t1_flit_bridge extends uvm_component;
  `uvm_component_utils(aou_t1_flit_bridge)

  uvm_analysis_imp #(aou_flit_item, aou_t1_flit_bridge) l1_imp;
  uvm_analysis_port #(aou_l3_flit_item)                 ap;
  int unsigned                                          n_flits;
  bit                                                   enable = 1'b1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    l1_imp = new("l1_imp", this);
    ap = new("ap", this);
  endfunction

  function void write(aou_flit_item f);
    aou_l3_flit_item it;
    if (!enable) return;
    it = aou_l3_flit_item::type_id::create("it");
    foreach (it.bytes[i]) it.bytes[i] = f.data[i];
    it.phy = f.phy;
    it.t_start = f.t_start;
    n_flits++;
    ap.write(it);
  endfunction
endclass
