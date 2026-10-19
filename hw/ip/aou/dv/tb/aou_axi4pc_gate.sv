// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// ARESETn for one Axi4PC instance (tb/tb_top.sv): the port's own reset, with two
// additions.
// - A port reset the bench's agents do not see (AOU_SW_RESET; bus_rst_n, I_RESETN,
//   resets both sides) ends only at the first cycle with no VALID on the port and no
//   transaction in flight on it. The bench legally finishes its side across the DUT's
//   reset, and the DUT's port reset is partial: AOU_FIFO_RP (on I_RESETN) still
//   delivers pre-reset R data and W bursts. Axi4PC would read those handshakes as
//   *VALID_RESET violations and as traffic of transactions it never saw. A transaction
//   that never ends (lost with the link) keeps the checker in reset.
// - off_set (a link event, aou_t1_axi4pc_ctl) holds the checker in reset until the
//   port's next reset, then as above. Without a port reset it stays held.
module aou_axi4pc_gate (
  input  logic clk,
  input  logic bus_rst_n,
  input  logic port_rst_n,
  input  logic off_set,
  input  logic awvalid, awready,
  input  logic wvalid, wready, wlast,
  input  logic bvalid, bready,
  input  logic arvalid, arready,
  input  logic rvalid, rready, rlast,
  output logic chk_rst_n,
  output logic off
);
  int unsigned n_aw, n_wl, n_b, n_ar, n_rl;
  logic        w_mid;
  logic        off_q;
  logic        held_q;

  wire aw_hs = awvalid === 1'b1 && awready === 1'b1;
  wire w_hs  = wvalid === 1'b1 && wready === 1'b1;
  wire b_hs  = bvalid === 1'b1 && bready === 1'b1;
  wire ar_hs = arvalid === 1'b1 && arready === 1'b1;
  wire r_hs  = rvalid === 1'b1 && rready === 1'b1;
  wire any_valid = awvalid !== 1'b0 || wvalid !== 1'b0 || bvalid !== 1'b0 ||
                   arvalid !== 1'b0 || rvalid !== 1'b0;
  wire [31:0] n_wr = (n_aw < n_wl) ? n_aw : n_wl;
  wire busy = n_aw != n_wl || w_mid || n_wr != n_b || n_ar != n_rl;
  wire quiet = !any_valid && !busy;

  always_ff @(posedge clk or negedge bus_rst_n) begin
    if (!bus_rst_n) begin
      n_aw <= 0;
      n_wl <= 0;
      n_b <= 0;
      n_ar <= 0;
      n_rl <= 0;
      w_mid <= 1'b0;
    end else begin
      if (aw_hs) n_aw <= n_aw + 1;
      if (w_hs) begin
        if (wlast === 1'b1) n_wl <= n_wl + 1;
        w_mid <= wlast !== 1'b1;
      end
      if (b_hs) n_b <= n_b + 1;
      if (ar_hs) n_ar <= n_ar + 1;
      if (r_hs && rlast === 1'b1) n_rl <= n_rl + 1;
    end
  end

  // AOU_SW_RESET holds the core reset low for whole clock cycles, so sampling
  // port_rst_n on the clock sees it.
  always_ff @(posedge clk or negedge bus_rst_n) begin
    if (!bus_rst_n) off_q <= 1'b0;
    else if (!port_rst_n) off_q <= 1'b0;
    else if (off_set) off_q <= 1'b1;
  end

  always_ff @(posedge clk or negedge bus_rst_n) begin
    if (!bus_rst_n) held_q <= 1'b0;
    else held_q <= off_q || !port_rst_n || (held_q && !quiet);
  end

  // quiet is combinational so the first edge Axi4PC samples out of reset is one
  // with every VALID low.
  assign chk_rst_n = port_rst_n && !off_q && !(held_q && !quiet);
  assign off = off_q || held_q;
endmodule
