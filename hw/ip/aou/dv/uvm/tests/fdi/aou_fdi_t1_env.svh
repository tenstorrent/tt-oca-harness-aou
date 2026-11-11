// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// FDI agents of each PHY plus the link-state agent (the UCIe model), which
// takes the FDI agents, and the bench's layer on it (aou_fdi_layer). When the top connects the AXI agents
// (AOU_T1_AXI_AGENTS), idle AXI agents keep the S ports quiet and answer the
// M ports. The DUT's RX flit framing is checked as in the T1 env
// (aou_t1_rx_align_chk, when the top provides "rst").
class aou_fdi_t1_env extends uvm_env;
  `uvm_component_utils(aou_fdi_t1_env)

  ucie_fdi_cfg   fdi_cfg[N_PHY];
  ucie_fdi_agent fdi[N_PHY];
  ucie_lsm_cfg   lsm_cfg;
  ucie_lsm_agent lsm;
  aou_fdi_layer  fdi_layer;
  aou_t1_rx_align_chk rx_align;
`ifdef AOU_T1_AXI_AGENTS
  aou_axi_mgr_agent s_mgr[FDI_T1_RP_COUNT];
  aou_axi_sub_agent m_sub[FDI_T1_RP_COUNT];
`endif

  function new(string name, uvm_component parent);
    super.new(name, parent);
    lsm_cfg = ucie_lsm_cfg::type_id::create("lsm_cfg");
    lsm_cfg.n_phy = N_PHY;
    // Software restarts the link this many cycles after a link-down, drawn
    // per run so a DUT that asks anything of the link meanwhile is caught at
    // many delays; +ucie_sw_restart_delay=N (or +sw_restart_delay=N) fixes it.
    lsm_cfg.sw_restart_delay = $urandom_range(1500, 50);
    foreach (fdi_cfg[p]) begin
      fdi_cfg[p] = ucie_fdi_cfg::type_id::create($sformatf("fdi_cfg%0d", p));
      fdi_cfg[p].phy = p;
      fdi_cfg[p].beat_bytes = p == 0 ? BEAT0 : BEAT1;
    end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (fdi[p]) begin
      fdi[p] = ucie_fdi_agent::type_id::create($sformatf("fdi%0d", p), this);
      fdi[p].cfg = fdi_cfg[p];
    end
    lsm = ucie_lsm_agent::type_id::create("lsm", this);
    lsm.cfg = lsm_cfg;
    foreach (fdi[p]) lsm.phy.push_back(fdi[p]);
    fdi_layer = aou_fdi_layer::type_id::create("fdi_layer", this);
    rx_align = aou_t1_rx_align_chk::type_id::create("rx_align", this);
    void'(uvm_config_db #(virtual aou_rst_if)::get(this, "", "rst", rx_align.rst_vif));
`ifdef AOU_T1_AXI_AGENTS
    foreach (s_mgr[r]) begin
      aou_axi_cfg mc = aou_axi_cfg::type_id::create($sformatf("s_mgr_cfg%0d", r));
      aou_axi_cfg sc = aou_axi_cfg::type_id::create($sformatf("m_sub_cfg%0d", r));
      mc.vif_key = $sformatf("s_axi%0d", r);
      sc.vif_key = $sformatf("m_axi%0d", r);
      s_mgr[r] = aou_axi_mgr_agent::type_id::create($sformatf("s_mgr%0d", r), this);
      m_sub[r] = aou_axi_sub_agent::type_id::create($sformatf("m_sub%0d", r), this);
      s_mgr[r].cfg = mc;
      m_sub[r].cfg = sc;
    end
`endif
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    fdi_layer.attach(lsm);
    fdi[lsm_cfg.active_phy].mon.ap_rx.connect(rx_align.rx_flit_imp);
    rx_align.mb_vif = fdi[lsm_cfg.active_phy].vif;
  endfunction
endclass
