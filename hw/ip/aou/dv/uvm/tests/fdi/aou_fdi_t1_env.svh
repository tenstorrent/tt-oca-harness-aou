// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// FDI agents of each PHY plus the link-state agent, with the L1 gates and
// TX responders handed to L2. When the top connects the AXI agents
// (AOU_T1_AXI_AGENTS), idle AXI agents keep the S ports quiet and answer the
// M ports. The DUT's RX flit framing is checked as in the T1 env
// (aou_t1_rx_align_chk, when the top provides "rst").
class aou_fdi_t1_env extends uvm_env;
  `uvm_component_utils(aou_fdi_t1_env)

  aou_fdi_cfg   fdi_cfg[N_PHY];
  aou_fdi_agent fdi[N_PHY];
  aou_lsm_cfg   lsm_cfg;
  aou_lsm_agent lsm;
  aou_t1_rx_align_chk rx_align;
`ifdef AOU_T1_AXI_AGENTS
  aou_axi_mgr_agent s_mgr[FDI_T1_RP_COUNT];
  aou_axi_sub_agent m_sub[FDI_T1_RP_COUNT];
`endif

  function new(string name, uvm_component parent);
    super.new(name, parent);
    lsm_cfg = aou_lsm_cfg::type_id::create("lsm_cfg");
    lsm_cfg.n_phy = N_PHY;
    foreach (fdi_cfg[p]) begin
      fdi_cfg[p] = aou_fdi_cfg::type_id::create($sformatf("fdi_cfg%0d", p));
      fdi_cfg[p].phy = p;
      fdi_cfg[p].beat_bytes = p == 0 ? BEAT0 : BEAT1;
    end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (fdi[p]) begin
      fdi[p] = aou_fdi_agent::type_id::create($sformatf("fdi%0d", p), this);
      fdi[p].cfg = fdi_cfg[p];
      lsm_cfg.gate.push_back(fdi_cfg[p].gate);
    end
    lsm = aou_lsm_agent::type_id::create("lsm", this);
    lsm.cfg = lsm_cfg;
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
    foreach (fdi[p]) if (fdi_cfg[p].is_active) lsm_cfg.rsp.push_back(fdi[p].rsp);
    fdi[lsm_cfg.active_phy].mon.ap_rx.connect(rx_align.rx_flit_imp);
    rx_align.mb_vif = fdi[lsm_cfg.active_phy].vif;
  endfunction
endclass
