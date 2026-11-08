// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// FDI mainband of one PHY, seen from the Adapter (PL) side: every signal of
// UCIe r3.0 Table 10-3 that travels with the data. The bus is always DATA_W
// wide, by default ucie_fdi_pkg::BUS_W (the widest FDI the model supports), so
// every PHY shares one virtual-interface type; the agent config holds the
// real beat width and the top slices the bus. Compile ucie_fdi_pkg first. A
// Protocol Layer without some of these pins leaves the pl_* ones open and
// ties its lp_* ones to their idle values (README "Top").

interface ucie_fdi_mb_if #(
    parameter int DATA_W = ucie_fdi_pkg::BUS_W
) (
    input logic clk,
    input logic rst_n
);

  // Adapter to Protocol Layer (RX)
  logic              pl_valid;
  logic [DATA_W-1:0] pl_data;
  logic              pl_flit_cancel;
  logic              pl_error;        // framing error, pipeline-matched with pl_data
  logic [7:0]        pl_stream;       // stream ID of pl_data (tied: ucie_fdi_cfg::stream)
  logic [31:0]       pl_dllp;         // DLLP transfer; not modelled, tied 0
  logic              pl_dllp_valid;
  logic              pl_dllp_ofc;
  logic              pl_retimer_crd;  // Retimer credit return; no Retimer, tied 0

  // Protocol Layer to Adapter (TX)
  logic              pl_trdy;
  logic [DATA_W-1:0] lp_data;
  logic              lp_valid;
  logic              lp_irdy;
  logic              lp_corrupt_crc;  // corrupt the CRC of the flit half (CXL.cachemem)
  logic [7:0]        lp_stream;
  logic [31:0]       lp_dllp;         // NDLLP = 32 (r3.0 10.3.1 for wide FDIs)
  logic              lp_dllp_valid;
  logic              lp_dllp_ofc;
  logic              lp_retimer_crd;

  logic              pl_stallreq;
  logic              lp_stallack;
  logic [3:0]        pl_state_sts;
  // pl_rx_active_req and lp_rx_active_sts both 1 (UCIe r3.0 §10.2.7 rule 3:
  // the Receiver is Active), from the FDI's link-state interface; the top
  // drives it.
  logic              rx_active;

  // L1: mainband stimulus and TX responder (which reads pl_state_sts back for
  // the drain in LinkError).
  clocking drv_cb @(posedge clk);
    output pl_valid, pl_data, pl_flit_cancel, pl_error, pl_stream, pl_dllp, pl_dllp_valid,
           pl_dllp_ofc, pl_retimer_crd, pl_trdy, pl_stallreq;
    input  lp_valid, lp_irdy, lp_stallack, pl_state_sts, rst_n;
  endclocking

  // L2: link state of this PHY.
  clocking lsm_cb @(posedge clk);
    output pl_state_sts;
  endclocking

  clocking mon_cb @(posedge clk);
    input pl_valid, pl_data, pl_flit_cancel, pl_error, pl_stream, pl_trdy, pl_stallreq,
          pl_state_sts, rx_active, lp_data, lp_valid, lp_irdy, lp_corrupt_crc, lp_stream,
          lp_dllp_valid, lp_retimer_crd, lp_stallack, rst_n;
  endclocking

endinterface
