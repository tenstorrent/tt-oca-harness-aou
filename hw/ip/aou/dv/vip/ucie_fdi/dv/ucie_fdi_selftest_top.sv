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

  // The Receiver is Active when both rx_active signals are 1 (UCIe r3.0 §10.2.7).
  assign fdi_mb0.rx_active = fdi_lsm.pl_rx_active_req && fdi_lsm.lp_rx_active_sts;

  // ucie_fdi_neg_test: Adapter faults the model never makes. The model drives
  // pl_state_sts and pl_rx_active_req only when they change, so each force
  // ends on the value the model drove, which the signal keeps once released.
  //  - xfer: pl_trdy high for one clock while the stub presents a flit in
  //    Retrain, so a transfer happens outside Active (FDI-R43).
  //  - le_exit: Reset for one clock while the stub holds lp_linkerror in
  //    LinkError (FDI-R49; r3.0 Table 10-3: the Adapter stays in LinkError "as
  //    long as lp_linkerror=1").
  //  - rx_inactive: pl_rx_active_req low in Active, held until a flit has gone
  //    out without it and lp_rx_active_sts has followed it down (FDI-R35; r3.0
  //    §10.2.7 rule 6: no flits to the Protocol Layer then).
  //  - clk_exit: in LinkReset, pl_clk_req low (and lp_clk_ack high, so the
  //    model goes on) from the clock it rises until the status has left, so
  //    LinkReset -> Reset happens without it (FDI-R22; r3.0 §10.2.3.2 rule 7).
  //  - le_after: a LinkError entered from Reset before its pl_clk_req is cut
  //    short by Reset for a clock, before lp_clk_ack (FDI-R21; rule 6).
  //  - level: pl_phyinrecenter high for 40 clocks in Reset after a LinkReset,
  //    with no pl_clk_req (FDI-R20; rule 5).
  initial begin
    string neg;
    void'($value$plusargs("neg=%s", neg));
    case (neg)
      "xfer": begin
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'hB && fdi_mb0.lp_valid === 1'b1 &&
                           fdi_mb0.lp_irdy === 1'b1));
        force fdi_mb0.pl_trdy = 1'b1;
        @(posedge clk);
        release fdi_mb0.pl_trdy;
      end
      "le_exit": begin
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'hA && fdi_lsm.lp_linkerror === 1'b1));
        repeat (4) @(posedge clk);
        force fdi_mb0.pl_state_sts = 4'h0;
        @(posedge clk);
        force fdi_mb0.pl_state_sts = 4'hA;
        release fdi_mb0.pl_state_sts;
      end
      "rx_inactive": begin
        int unsigned n;
        bit          sent;
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'h1 && fdi_mb0.rx_active === 1'b1 &&
                           fdi_mb0.pl_valid === 1'b1));
        force fdi_lsm.pl_rx_active_req = 1'b0;
        do begin
          @(posedge clk);
          n++;
          sent |= fdi_mb0.pl_valid === 1'b1;
        end while ((n < 2 || !sent || fdi_lsm.lp_rx_active_sts !== 1'b0) && n < 1000);
        force fdi_lsm.pl_rx_active_req = 1'b1;
        release fdi_lsm.pl_rx_active_req;
      end
      "clk_exit": begin
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'h9 && fdi_lsm.pl_clk_req === 1'b1));
        force fdi_lsm.pl_clk_req = 1'b0;
        force fdi_lsm.lp_clk_ack = 1'b1;
        @(posedge clk iff (fdi_mb0.pl_state_sts != 4'h9));
        release fdi_lsm.pl_clk_req;
        release fdi_lsm.lp_clk_ack;
      end
      "le_after": begin
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'hA && fdi_lsm.pl_clk_req === 1'b1 &&
                           fdi_lsm.lp_clk_ack !== 1'b1));
        force fdi_mb0.pl_state_sts = 4'h0;
        @(posedge clk);
        force fdi_mb0.pl_state_sts = 4'hA;
        release fdi_mb0.pl_state_sts;
      end
      "level": begin
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'h9));
        @(posedge clk iff (fdi_mb0.pl_state_sts == 4'h0 && fdi_lsm.pl_clk_req === 1'b0 &&
                           fdi_lsm.lp_clk_ack === 1'b0));
        repeat (5) @(posedge clk);
        force fdi_lsm.pl_phyinrecenter = 1'b1;
        repeat (40) @(posedge clk);
        force fdi_lsm.pl_phyinrecenter = 1'b0;
        release fdi_lsm.pl_phyinrecenter;
      end
      default: ;
    endcase
  end

  initial begin
    uvm_config_db #(virtual ucie_fdi_mb_if #(.DATA_W(BUS_W)))::set(null, "*", "fdi_mb0", fdi_mb0);
    uvm_config_db #(virtual ucie_fdi_lsm_if)::set(null, "*", "fdi_lsm", fdi_lsm);
    run_test();
  end
endmodule
