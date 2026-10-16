// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

`timescale 1ns/1ps

// AXI L4 self-test bench, no DUT: a manager agent and a subordinate agent on one
// aou_axi_bus_if, checked by the manager's monitor and the scoreboard.
module aou_axi_selftest_top;
  import uvm_pkg::*;
  import aou_axi_selftest_pkg::*;

  logic clk;
  logic resetn;

  initial clk = 1'b0;
  always #0.5 clk = ~clk;

  initial begin
    resetn = 1'b0;
    repeat (10) @(posedge clk);
    resetn <= 1'b1;
  end

  aou_axi_bus_if #(.DATA_W(1024)) axi0 (.clk(clk), .resetn(resetn));

  initial begin
    uvm_config_db#(virtual aou_axi_bus_if #(.DATA_W(1024)))::set(null, "*", "axi0", axi0);
    run_test("aou_axi_selftest_test");
  end
endmodule
