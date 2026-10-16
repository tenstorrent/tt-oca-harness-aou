// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Connects two L3 agents the way L1 would: pulls each one's next flit,
// drives it as four 64-byte beats (A on LP, B on PL), then delivers it to
// the other agent.
class aou_l3_unit_link extends uvm_component;
  `uvm_component_utils(aou_l3_unit_link)

  virtual aou_l3_unit_if vif;
  aou_l3_agent           a;
  aou_l3_agent           b;
  int unsigned           max_gap = 2;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual aou_l3_unit_if)::get(this, "", "l3_unit", vif))
      `uvm_fatal(get_type_name(), "no aou_l3_unit_if under key l3_unit")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.lp_valid <= 1'b0;
    vif.drv_cb.pl_valid <= 1'b0;
    while (vif.mon_cb.rst_n !== 1'b1) @(vif.mon_cb);
    fork
      pump(a, b, 1'b0);
      pump(b, a, 1'b1);
    join
  endtask

  task pump(aou_l3_agent src, aou_l3_agent dst, bit pl);
    forever begin
      aou_l3_flit_item it;
      aou_flit_vec_t v;
      src.get(it);
      v = it.flit.to_vec();
      for (int k = 0; k < 4; k++) begin
        @(vif.drv_cb);
        if (pl) begin
          vif.drv_cb.pl_valid <= 1'b1;
          vif.drv_cb.pl_data <= v[512*k +: 512];
        end else begin
          vif.drv_cb.lp_valid <= 1'b1;
          vif.drv_cb.lp_data <= v[512*k +: 512];
        end
      end
      @(vif.drv_cb);
      if (pl) vif.drv_cb.pl_valid <= 1'b0;
      else vif.drv_cb.lp_valid <= 1'b0;
      dst.write(it);
      repeat ($urandom_range(0, max_gap)) @(vif.drv_cb);
    end
  endtask
endclass
