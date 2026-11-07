// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_tx)

// End-to-end check of the self-test: every flit the test sends reaches the
// Protocol Layer intact (ap_rx, after the cancels), and every delivered flit
// comes back in order on the Protocol Layer's TX side (ap_tx). The model's
// own monitors check the FDI rules on the way. An RX flit may be lost only
// to a LinkError the Adapter entered mid-flit (UCIe r3.0 §10.3.3.7), so the
// RX check skips ahead only after a link-down, which the scoreboard sees as an
// observer of the link-state monitor. TX flits with an all-zero payload are
// the stub's fillers of a wide transfer, or its NOP flits, and are skipped.
// Every delivered flit must be a protocol flit (no NOP, Flit Type 00b).
class ucie_fdi_selftest_sb extends uvm_component implements ucie_lsm_observer;
  `uvm_component_utils(ucie_fdi_selftest_sb)

  uvm_analysis_imp_rx #(ucie_flit_item, ucie_fdi_selftest_sb)  rx_imp;
  uvm_analysis_imp_tx #(ucie_flit_item, ucie_fdi_selftest_sb)  tx_imp;

  ucie_flit_item rx_exp[$];   // sent by the test, not yet delivered
  ucie_flit_item lb_exp[$];   // delivered, not yet looped back
  int unsigned   n_rx, n_tx, n_rx_lost, n_link_down, n_tx_fill;
  local bit      rx_resync;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_imp = new("rx_imp", this);
    tx_imp = new("tx_imp", this);
  endfunction

  function void expect_rx(ucie_flit_item t);
    rx_exp.push_back(t);
  endfunction

  function void write_rx(ucie_flit_item t);
    int unsigned skipped;
    // The model hands the Protocol Layer protocol flits only: no NOP, and a
    // Flit Type of 00b even with random Adapter bytes (r3.0 Table 3-5).
    if (t.is_nop() || t.data[1][7:6] != 2'b00)
      `uvm_error(get_type_name(), $sformatf("RX flit with Protocol ID %02b, Flit Type %02b: %s",
                                            t.data[0][7:6], t.data[1][7:6], t.convert2string()))
    lb_exp.push_back(t);
    while (rx_exp.size() != 0 && rx_resync && !rx_exp[0].same_payload(t)) begin
      void'(rx_exp.pop_front());
      skipped++;
    end
    if (rx_exp.size() == 0 || !rx_exp[0].same_payload(t)) begin
      `uvm_error(get_type_name(), {"RX flit not the next one sent: ", t.convert2string()})
      if (rx_exp.size() != 0) void'(rx_exp.pop_front());
      return;
    end
    void'(rx_exp.pop_front());
    n_rx++;
    n_rx_lost += skipped;
    rx_resync = 1'b0;
  endfunction

  function void write_tx(ucie_flit_item t);
    if (empty_payload(t)) begin
      n_tx_fill++;
      return;
    end
    if (lb_exp.size() == 0 || !lb_exp[0].same_payload(t)) begin
      `uvm_error(get_type_name(), {"TX flit not the next one delivered: ", t.convert2string()})
      if (lb_exp.size() != 0) void'(lb_exp.pop_front());
      return;
    end
    void'(lb_exp.pop_front());
    n_tx++;
  endfunction

  local static function bit empty_payload(ucie_flit_item t);
    foreach (t.data[i]) if (!is_adapter_byte(i) && t.data[i] != 8'h00) return 1'b0;
    return 1'b1;
  endfunction

  virtual function void observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev);
    if (cur.sts != prev.sts && cur.sts inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED} &&
        !rx_resync) begin
      rx_resync = 1'b1;
      n_link_down++;
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (rx_exp.size() != 0)
      `uvm_error(get_type_name(), $sformatf("%0d flits sent but never delivered", rx_exp.size()))
    if (lb_exp.size() != 0)
      `uvm_error(get_type_name(), $sformatf("%0d flits delivered but never looped back",
                                            lb_exp.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
              "%0d flits delivered, %0d looped back (and %0d fillers), %0d lost to %0d link-downs",
              n_rx, n_tx, n_tx_fill, n_rx_lost, n_link_down), UVM_LOW)
  endfunction
endclass

// One FDI (UCIe model mainband agent), the link-state agent, the Protocol
// Layer stub and the scoreboard. This is the wiring every user of the model
// repeats: the link-state agent takes the mainband agents at build, and
// observers register with its monitor at connect.
class ucie_fdi_selftest_env extends uvm_env;
  `uvm_component_utils(ucie_fdi_selftest_env)

  ucie_fdi_cfg         fdi_cfg;
  ucie_lsm_cfg         lsm_cfg;
  ucie_fdi_agent       fdi;
  ucie_lsm_agent       lsm;
  ucie_pl_stub         pl;
  ucie_fdi_selftest_sb sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    fdi_cfg = ucie_fdi_cfg::type_id::create("fdi_cfg");
    lsm_cfg = ucie_lsm_cfg::type_id::create("lsm_cfg");
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    fdi = ucie_fdi_agent::type_id::create($sformatf("fdi%0d", fdi_cfg.phy), this);
    fdi.cfg = fdi_cfg;
    lsm = ucie_lsm_agent::type_id::create("lsm", this);
    lsm.cfg = lsm_cfg;
    lsm.phy.push_back(fdi);
    pl = ucie_pl_stub::type_id::create("pl", this);
    pl.beat_bytes = fdi_cfg.beat_bytes;
    pl.stream = fdi_cfg.stream;
    if (!uvm_config_db #(virtual ucie_fdi_lsm_if)::get(this, "", "fdi_lsm", pl.lsm))
      `uvm_fatal(get_type_name(), "no fdi_lsm in config_db")
    sb = ucie_fdi_selftest_sb::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    pl.mb = fdi.vif;
    fdi.mon.ap_rx.connect(pl.rx_imp);
    fdi.mon.ap_rx.connect(sb.rx_imp);
    fdi.mon.ap_tx.connect(sb.tx_imp);
    lsm.mon.add_observer(sb);
  endfunction
endclass
