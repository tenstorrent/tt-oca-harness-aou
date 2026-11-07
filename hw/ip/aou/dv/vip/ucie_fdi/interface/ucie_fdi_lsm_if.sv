// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// FDI link state of one FDI (UCIe r3.0 §10.2, Table 10-3): the handshakes,
// the negotiated protocol and format, the link's speed and width, and the
// error and power-state indications. UCIe has one FDI, and so one of these,
// per protocol stack; in the model's mirrored mode (ucie_lsm_cfg::n_phy 2)
// two FDIs share it. pl_state_sts lives on ucie_fdi_mb_if. Signals of the
// Protocol Layer under test that are not FDI (software pins, status outputs)
// belong on an interface of the bench's own. The sideband configuration
// channel (pl_cfg, lp_cfg) is not on it.

interface ucie_fdi_lsm_if (
    input logic clk,
    input logic rst_n
);

  // Adapter to Protocol Layer: handshakes
  logic       pl_inband_pres;
  logic       pl_clk_req;
  logic       pl_wake_ack;
  logic       pl_rx_active_req;
  // Adapter to Protocol Layer: what was negotiated (ucie_lsm_cfg)
  logic [3:0] pl_protocol;
  logic [3:0] pl_protocol_flitfmt;
  logic       pl_protocol_vld;
  logic [2:0] pl_speedmode;
  logic       pl_max_speedmode;       // UCIe r3.0 only
  logic [2:0] pl_lnk_cfg;
  // Adapter to Protocol Layer: training and power state of the Physical Layer
  logic       pl_phyinrecenter;
  logic       pl_phyinl1;
  logic       pl_phyinl2;
  // Adapter to Protocol Layer: errors (not modelled, held 0)
  logic       pl_cerror;
  logic       pl_nferror;
  logic       pl_trainerror;

  // Protocol Layer to Adapter
  logic [3:0] lp_state_req;
  logic       lp_wake_req;
  logic       lp_clk_ack;
  logic       lp_rx_active_sts;
  logic       lp_linkerror;           // tie 0 when the Protocol Layer has none

  clocking drv_cb @(posedge clk);
    output pl_inband_pres, pl_clk_req, pl_wake_ack, pl_rx_active_req, pl_protocol,
           pl_protocol_flitfmt, pl_protocol_vld, pl_speedmode, pl_max_speedmode, pl_lnk_cfg,
           pl_phyinrecenter, pl_phyinl1, pl_phyinl2, pl_cerror, pl_nferror, pl_trainerror;
    input  lp_state_req, lp_wake_req, lp_clk_ack, lp_rx_active_sts, lp_linkerror, rst_n;
  endclocking

  clocking mon_cb @(posedge clk);
    input pl_inband_pres, pl_clk_req, pl_wake_ack, pl_rx_active_req, pl_protocol,
          pl_protocol_flitfmt, pl_protocol_vld, pl_phyinrecenter, pl_phyinl1, pl_phyinl2,
          lp_state_req, lp_wake_req, lp_clk_ack, lp_rx_active_sts, lp_linkerror, rst_n;
  endclocking

endinterface
