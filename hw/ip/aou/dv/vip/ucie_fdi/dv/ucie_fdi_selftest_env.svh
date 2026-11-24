// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_tx)

// End-to-end check of the self-test: every flit the test sends reaches the
// Protocol Layer intact (ap_rx, after the cancels), and every delivered flit
// comes back in order on the Protocol Layer's TX side (ap_tx). The model's
// own monitors check the FDI rules on the way. The model leaves Active at a
// flit boundary on every exit but a LinkError it enters mid-flit, so an RX
// flit may be lost only there: the PL driver abandons the transfer under way
// (UCIe r3.0 §10.3.3.7) and counts its flits, NOPs not included, in
// gate.n_abandoned. The RX check skips an expected flit only when the next
// delivered flit shows it missing and an abandoned flit is still unaccounted
// for, never more than that, and at the end of the test the flits skipped
// must equal the flits abandoned. A link-down alone allows no skip: LinkReset,
// Disabled, Retrain and a LinkError at a flit boundary lose nothing. TX flits
// with an all-zero payload are the stub's fillers of a wide transfer, or its
// NOP flits, and are skipped. Every delivered flit must be a protocol flit
// (no NOP, Flit Type 00b). The scoreboard also follows the link state as an
// observer of the link-state monitor, to count the link-downs it reports.
class ucie_fdi_selftest_sb extends uvm_component implements ucie_lsm_observer;
  `uvm_component_utils(ucie_fdi_selftest_sb)

  uvm_analysis_imp_rx #(ucie_flit_item, ucie_fdi_selftest_sb)  rx_imp;
  uvm_analysis_imp_tx #(ucie_flit_item, ucie_fdi_selftest_sb)  tx_imp;

  ucie_flit_item rx_exp[$];   // sent by the test, not yet delivered
  ucie_flit_item lb_exp[$];   // delivered, not yet looped back
  int unsigned   n_rx, n_tx, n_rx_lost, n_link_down, n_tx_fill;
  ucie_fdi_gate  gate;  // this FDI's gate: n_abandoned, the RX flits the PL driver abandoned

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_imp = new("rx_imp", this);
    tx_imp = new("tx_imp", this);
  endfunction

  function void expect_rx(ucie_flit_item t);
    rx_exp.push_back(t);
  endfunction

  function void write_rx(ucie_flit_item t);
    int pos = -1;
    // The model hands the Protocol Layer protocol flits only: no NOP, and a
    // Flit Type of 00b even with random Adapter bytes (r3.0 Table 3-5).
    if (t.is_nop() || t.data[1][7:6] != 2'b00)
      `uvm_error(get_type_name(), $sformatf("RX flit with Protocol ID %02b, Flit Type %02b: %s",
                                            t.data[0][7:6], t.data[1][7:6], t.convert2string()))
    lb_exp.push_back(t);
    // Where the flit is among those sent and not yet delivered: normally at
    // the head; further down only on the error path, so the search is rare.
    if (rx_exp.size() != 0 && rx_exp[0].same_payload(t)) pos = 0;
    else
      foreach (rx_exp[i])
        if (rx_exp[i].same_payload(t)) begin
          pos = i;
          break;
        end
    if (pos < 0) begin
      `uvm_error(get_type_name(), {"RX flit not the next one sent (never sent, or delivered ",
                                   "twice): ", t.convert2string()})
      return;
    end
    // The flits before it were sent and never delivered: legal only as flits
    // a mid-flit LinkError abandoned and no earlier flit has accounted for.
    if (pos > gate.n_abandoned - n_rx_lost)
      `uvm_error(get_type_name(), $sformatf({"RX flit not the next one sent (%0d sent before it ",
                 "never delivered, %0d abandoned flits unaccounted for): %s"},
                 pos, gate.n_abandoned - n_rx_lost, t.convert2string()))
    else
      n_rx_lost += pos;
    // Realign on the delivered flit either way, so one gap is one error.
    repeat (pos + 1) void'(rx_exp.pop_front());
    n_rx++;
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
    if (cur.sts != prev.sts && cur.sts inside {LSM_LINKERROR, LSM_LINKRESET, LSM_DISABLED})
      n_link_down++;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // An abandoned flit that was delivered after all, or one never followed
    // by a delivery, leaves the two counts apart.
    if (n_rx_lost != gate.n_abandoned)
      `uvm_error(get_type_name(), $sformatf({"%0d RX flits skipped as abandoned, but the model ",
                 "abandoned %0d on mid-flit LinkErrors"}, n_rx_lost, gate.n_abandoned))
    if (rx_exp.size() != 0)
      `uvm_error(get_type_name(), $sformatf("%0d flits sent but never delivered", rx_exp.size()))
    if (lb_exp.size() != 0)
      `uvm_error(get_type_name(), $sformatf("%0d flits delivered but never looped back",
                                            lb_exp.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({"%0d flits delivered, %0d looped back (and %0d ",
              "fillers), %0d lost to mid-flit LinkErrors (%0d abandoned), %0d link-downs"},
              n_rx, n_tx, n_tx_fill, n_rx_lost, gate.n_abandoned, n_link_down), UVM_LOW)
  endfunction
endclass

// One FDI (UCIe model mainband agent), the link-state agent, the Protocol
// Layer stub and the scoreboard. This is the wiring every user of the model
// repeats: the link-state agent takes the mainband agents and its interface
// at build, and observers register with its monitor at connect. A second
// link (ucie_fdi_reuse_test) is a second env with its own FDI (fdi_cfg.phy)
// and link-state interface (lsm_key). With lsm_cfg.n_phy 2 (the mirrored
// mode) a second mainband agent, fdi1, shares the link state; the stub and
// the traffic stay on the first FDI.
class ucie_fdi_selftest_env extends uvm_env;
  `uvm_component_utils(ucie_fdi_selftest_env)

  ucie_fdi_cfg         fdi_cfg;
  ucie_fdi_cfg         fdi1_cfg;   // mirrored mode: the second FDI
  ucie_lsm_cfg         lsm_cfg;
  string               lsm_key = "fdi_lsm";  // config_db key of the link-state interface
  ucie_fdi_agent       fdi;
  ucie_fdi_agent       fdi1;
  ucie_lsm_agent       lsm;
  ucie_pl_stub         pl;
  ucie_fdi_selftest_sb sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    fdi_cfg = ucie_fdi_cfg::type_id::create("fdi_cfg");
    fdi1_cfg = ucie_fdi_cfg::type_id::create("fdi1_cfg");
    fdi1_cfg.phy = 1;
    lsm_cfg = ucie_lsm_cfg::type_id::create("lsm_cfg");
    // Software's restart delay after a link-down, drawn per run (tests may
    // set their own in configure()).
    lsm_cfg.sw_restart_delay = $urandom_range(1500, 50);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual ucie_fdi_lsm_if lsm_vif;
    super.build_phase(phase);
    if (!uvm_config_db #(virtual ucie_fdi_lsm_if)::get(this, "", lsm_key, lsm_vif))
      `uvm_fatal(get_type_name(), {"no ", lsm_key, " in config_db"})
    fdi = ucie_fdi_agent::type_id::create($sformatf("fdi%0d", fdi_cfg.phy), this);
    fdi.cfg = fdi_cfg;
    lsm = ucie_lsm_agent::type_id::create("lsm", this);
    lsm.cfg = lsm_cfg;
    lsm.lsm_vif = lsm_vif;
    lsm.phy.push_back(fdi);
    if (lsm_cfg.n_phy > 1) begin
      fdi1 = ucie_fdi_agent::type_id::create("fdi1", this);
      fdi1.cfg = fdi1_cfg;
      lsm.phy.push_back(fdi1);
    end
    pl = ucie_pl_stub::type_id::create("pl", this);
    pl.beat_bytes = fdi_cfg.beat_bytes;
    pl.stream = fdi_cfg.stream;
    pl.protocol = lsm_cfg.protocol;
    pl.lsm = lsm_vif;
    sb = ucie_fdi_selftest_sb::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    pl.mb = fdi.vif;
    sb.gate = fdi_cfg.gate;
    fdi.mon.ap_rx.connect(pl.rx_imp);
    fdi.mon.ap_rx.connect(sb.rx_imp);
    fdi.mon.ap_tx.connect(sb.tx_imp);
    lsm.mon.add_observer(sb);
  endfunction
endclass
