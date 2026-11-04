// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// Top of the UCIe FDI model's self-test: one FDI and the link-state
// interface, driven by the model on the Adapter side and by the Protocol
// Layer stub (ucie_pl_stub) on the other.

module ucie_fdi_selftest_top;
  import uvm_pkg::*;
  import ucie_fdi_pkg::*;
  import ucie_fdi_selftest_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  always #1 clk = ~clk;

  initial begin
    repeat (20) @(posedge clk);
    rst_n <= 1'b1;
  end

  ucie_fdi_mb_if #(.DATA_W(BUS_W)) fdi_mb0 (.clk(clk), .rst_n(rst_n));
  ucie_fdi_lsm_if                   fdi_lsm (.clk(clk), .rst_n(rst_n));

  // The Receiver is Active when both rx_active signals are 1 (UCIe r1.1 §8.2.7).
  assign fdi_mb0.rx_active = fdi_lsm.pl_rx_active_req && fdi_lsm.lp_rx_active_sts;

  initial begin
    uvm_config_db #(virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)))::set(null, "*", "fdi_mb0", fdi_mb0);
    uvm_config_db #(virtual ucie_fdi_lsm_if)::set(null, "*", "fdi_lsm", fdi_lsm);
    run_test();
  end
endmodule
