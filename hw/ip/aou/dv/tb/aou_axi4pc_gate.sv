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
// - resync (aou_t1_axi4pc_ctl, a one-cycle request) is kept pending (sync_wait) until a
//   quiet cycle, and the checker's reset is pulsed in the high half of that cycle
//   only: its CAMs clear (asynchronous reset), but no clock edge samples ARESETn low,
//   so no handshake is missed and the *VALID_RESET rules (VALID low at the first edge
//   after reset) don't apply; the checker is never held while the port is active.
//   A request still pending at the end of the test is reported by aou_t1_axi4pc_ctl;
//   until then the checker runs on with the stale entry, so it errs towards false
//   failures, never silence. A response handshake with nothing
//   outstanding (an injected orphan the DUT accepted) leaves Axi4PC's tracking wrong
//   until its next reset: an unmatched B sets BRespCam on the free entry, so the next
//   write stored there never matches its B; an RLAST beat pops the empty read CAM
//   (RIndex 0, AUX_RCAM_UNDERFLOW on every cycle). The counters below never count a
//   response with nothing outstanding, so the same handshake doesn't keep busy set.
module aou_axi4pc_gate (
  input  logic clk,
  input  logic bus_rst_n,
  input  logic port_rst_n,
  input  logic off_set,
  input  logic resync,
  input  logic awvalid, awready,
  input  logic wvalid, wready, wlast,
  input  logic bvalid, bready,
  input  logic arvalid, arready,
  input  logic rvalid, rready, rlast,
  output logic chk_rst_n,
  output logic off,
  output logic sync_wait
);
  int unsigned n_aw, n_wl, n_b, n_ar, n_rl;
  logic        w_mid;
  logic        off_q;
  logic        held_q;
  logic        sync_q;

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
      if (b_hs && n_b < n_wr) n_b <= n_b + 1;
      if (ar_hs) n_ar <= n_ar + 1;
      if (r_hs && rlast === 1'b1 && n_rl < n_ar) n_rl <= n_rl + 1;
    end
  end

  // AOU_SW_RESET holds the core reset low for whole clock cycles, so sampling
  // port_rst_n on the clock sees it.
  always_ff @(posedge clk or negedge bus_rst_n) begin
    if (!bus_rst_n) off_q <= 1'b0;
    else if (!port_rst_n) off_q <= 1'b0;
    else if (off_set) off_q <= 1'b1;
  end

  // Pending until the end of a cycle that was quiet (the reset below covered it).
  always_ff @(posedge clk or negedge bus_rst_n) begin
    if (!bus_rst_n) sync_q <= 1'b0;
    else if (resync === 1'b1) sync_q <= 1'b1;
    else if (quiet) sync_q <= 1'b0;
  end

  always_ff @(posedge clk or negedge bus_rst_n) begin
    if (!bus_rst_n) held_q <= 1'b0;
    else held_q <= off_q || !port_rst_n || (held_q && !quiet);
  end

  // quiet is combinational so the first edge Axi4PC samples out of reset is one
  // with every VALID low.
  // The resync pulse: within a quiet cycle, while clk is high (between edges).
  assign chk_rst_n = port_rst_n && !off_q && !(held_q && !quiet) &&
                     !(sync_q && quiet && clk === 1'b1);
  assign off = off_q || held_q;
  assign sync_wait = sync_q;
endmodule
