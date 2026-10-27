// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Tenstorrent USA Inc
//*************************************************************************
//
// AXI4 functional coverage monitor for AoU (AXI-over-UCIe) RTL.
//
//   Standalone signal-level monitor; no VIP / BFM / UVM dependency.
//   Registers the AXI payload on each channel handshake (VALID && READY)
//   and samples covergroups one cycle later.
//
//   One instance per AXI interface, attached per resource plane and
//   direction (s_axi_tx_* / m_axi_rx_*) by dv/cov/aou_axi4_cov_bind.sv.
//
//   Covered: rd/wr commands; AxADDR (range, alignment vs AxSIZE, 4KB
//   boundary - crossing flagged illegal); AxSIZE; AxLEN; AxBURST (INCR
//   only); AxCACHE; AxPROT; AxQOS; AxLOCK; AxID buckets; WSTRB patterns
//   incl. first-beat lead mask; WLAST/RLAST; BRESP/RRESP; outstanding
//   counts up to MAX_OUTSTANDING; R/B backpressure stall run-lengths.
//   WDATA values are not binned.
//
//*************************************************************************

`ifndef AOU_AXI4_COVERAGE_MOD_SV
`define AOU_AXI4_COVERAGE_MOD_SV

module aou_axi4_coverage_mod #(
  parameter string INST_NAME       = "u_axi4_cov",
  parameter int    ADDR_WIDTH      = 64,
  parameter int    DATA_WIDTH      = 512,
  parameter int    ID_WIDTH        = 10,
  parameter int    MAX_OUTSTANDING = 32
) (
  input logic                    clk,
  input logic                    rst_n,

  //--------------------------------------------------------------------------
  // Write Address channel (AW)
  //--------------------------------------------------------------------------
  input logic                    aw_valid,
  input logic                    aw_ready,
  input logic [ADDR_WIDTH-1:0]   aw_addr,
  input logic [ID_WIDTH-1:0]     aw_id,
  input logic [7:0]              aw_len,
  input logic [2:0]              aw_size,
  input logic [1:0]              aw_burst,
  input logic                    aw_lock,
  input logic [3:0]              aw_cache,
  input logic [2:0]              aw_prot,
  input logic [3:0]              aw_qos,

  //--------------------------------------------------------------------------
  // Write Data channel (W)
  //--------------------------------------------------------------------------
  input logic                    w_valid,
  input logic                    w_ready,
  input logic [DATA_WIDTH/8-1:0] w_strb,
  input logic                    w_last,

  //--------------------------------------------------------------------------
  // Write Response channel (B)
  //--------------------------------------------------------------------------
  input logic                    b_valid,
  input logic                    b_ready,
  input logic [1:0]              b_resp,

  //--------------------------------------------------------------------------
  // Read Address channel (AR)
  //--------------------------------------------------------------------------
  input logic                    ar_valid,
  input logic                    ar_ready,
  input logic [ADDR_WIDTH-1:0]   ar_addr,
  input logic [ID_WIDTH-1:0]     ar_id,
  input logic [7:0]              ar_len,
  input logic [2:0]              ar_size,
  input logic [1:0]              ar_burst,
  input logic                    ar_lock,
  input logic [3:0]              ar_cache,
  input logic [2:0]              ar_prot,
  input logic [3:0]              ar_qos,

  //--------------------------------------------------------------------------
  // Read Data channel (R)
  //--------------------------------------------------------------------------
  input logic                    r_valid,
  input logic                    r_ready,
  input logic [1:0]              r_resp,
  input logic                    r_last
);

  //==========================================================================
  // Derived constants
  //==========================================================================
  localparam int STRB_WIDTH    = DATA_WIDTH/8;
  localparam int MAX_SIZE_CODE = $clog2(STRB_WIDTH);          // 512b->6(64B)
  localparam int OS_CNT_W      = $clog2(MAX_OUTSTANDING+1);   // hold 0..MAX_OUTSTANDING
  localparam longint ID_MAX    = (longint'(1) << ID_WIDTH)   - 1;
  localparam logic [ADDR_WIDTH-1:0] ADDR_LOW_LIMIT = (ADDR_WIDTH)'(1) << (ADDR_WIDTH/2);

  //==========================================================================
  // Handshake qualifiers
  //==========================================================================
  logic aw_hs, w_hs, b_hs, ar_hs, r_hs;
  logic r_last_hs;

  assign aw_hs     = aw_valid && aw_ready;
  assign w_hs      = w_valid  && w_ready;
  assign b_hs      = b_valid  && b_ready;
  assign ar_hs     = ar_valid && ar_ready;
  assign r_hs      = r_valid  && r_ready;
  assign r_last_hs = r_hs     && r_last;

  //==========================================================================
  // Address alignment classifier (relative to AxSIZE)
  //   2 = bus-width aligned (lowest MAX_SIZE_CODE bits are 0)
  //   1 = aligned to its own AxSIZE (but not full bus width)
  //   0 = UNALIGNED w.r.t. AxSIZE  (start address breaks size alignment)
  //==========================================================================
  function automatic logic [1:0] addr_align(input logic [ADDR_WIDTH-1:0] addr,
                                             input logic [2:0]            size);
    logic [ADDR_WIDTH-1:0] size_mask;
    logic [ADDR_WIDTH-1:0] bus_mask;
    size_mask = ((ADDR_WIDTH)'(1) << size) - 1;
    bus_mask  = ((ADDR_WIDTH)'(1) << MAX_SIZE_CODE) - 1;
    if ((addr & bus_mask) == '0)
      return 2'd2;
    else if ((addr & size_mask) == '0)
      return 2'd1;
    else
      return 2'd0;
  endfunction

  //==========================================================================
  // 4KB page-boundary classifier (INCR burst footprint)
  //   0 = burst ends inside the page
  //   1 = burst ends EXACTLY at the 4KB boundary (last byte at offset 4095)
  //   2 = burst crosses the 4KB boundary  -> AXI4 protocol violation
  //==========================================================================
  function automatic logic [1:0] boundary_4k(input logic [ADDR_WIDTH-1:0] addr,
                                              input logic [7:0]            len,
                                              input logic [2:0]            size);
    logic [11:0] size_mask;
    logic [31:0] end_off;   // page offset one past the burst's last byte
    size_mask = (12'd1 << size) - 12'd1;
    end_off   = 32'(addr[11:0] & ~size_mask) + ((32'(len) + 32'd1) << size);
    if      (end_off >  32'd4096) return 2'd2;
    else if (end_off == 32'd4096) return 2'd1;
    else                          return 2'd0;
  endfunction

  //==========================================================================
  // Registered per-channel payloads (sampled on handshake, used 1 cycle later)
  //==========================================================================
  // AW
  logic                  aw_vld_r;
  logic [ID_WIDTH-1:0]   aw_id_r;
  logic [7:0]            aw_len_r;
  logic [2:0]            aw_size_r;
  logic [1:0]            aw_burst_r;
  logic                  aw_lock_r;
  logic [3:0]            aw_cache_r;
  logic [2:0]            aw_prot_r;
  logic [3:0]            aw_qos_r;
  logic [1:0]            aw_align_r;
  logic [1:0]            aw_b4k_r;
  logic [ADDR_WIDTH-1:0] aw_addr_r;

  // AR
  logic                  ar_vld_r;
  logic [ID_WIDTH-1:0]   ar_id_r;
  logic [7:0]            ar_len_r;
  logic [2:0]            ar_size_r;
  logic [1:0]            ar_burst_r;
  logic                  ar_lock_r;
  logic [3:0]            ar_cache_r;
  logic [2:0]            ar_prot_r;
  logic [3:0]            ar_qos_r;
  logic [1:0]            ar_align_r;
  logic [1:0]            ar_b4k_r;
  logic [ADDR_WIDTH-1:0] ar_addr_r;

  // W
  logic                  w_vld_r;
  logic                  w_first_r;       // this registered beat was the first of a burst
  logic [STRB_WIDTH-1:0] w_strb_r;
  logic                  w_last_r;
  logic [6:0]            w_strb_lead0_r;  // # of contiguous zero LSB byte-lanes

  // B / R responses
  logic       b_vld_r;
  logic [1:0] b_resp_r;
  logic       r_vld_r;
  logic [1:0] r_resp_r;
  logic       r_last_r;

  // Command activity (one-cycle pulses)
  logic rd_cmd_r;
  logic wr_cmd_r;

  // W-channel first-beat tracking
  logic w_is_first;

  // Count trailing (LSB-side) zero byte lanes in a strobe -> "leading mask"
  function automatic logic [6:0] strb_lead_zeros(input logic [STRB_WIDTH-1:0] strb);
    logic [6:0] cnt;
    cnt = '0;
    for (int i = 0; i < STRB_WIDTH; i++) begin
      if (strb[i]) break;
      cnt = cnt + 1'b1;
    end
    return cnt;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_vld_r   <= 1'b0;
      ar_vld_r   <= 1'b0;
      w_vld_r    <= 1'b0;
      b_vld_r    <= 1'b0;
      r_vld_r    <= 1'b0;
      rd_cmd_r   <= 1'b0;
      wr_cmd_r   <= 1'b0;
      w_is_first <= 1'b1;
    end else begin
      // default: clear one-cycle pulses
      aw_vld_r <= 1'b0;
      ar_vld_r <= 1'b0;
      w_vld_r  <= 1'b0;
      b_vld_r  <= 1'b0;
      r_vld_r  <= 1'b0;
      rd_cmd_r <= 1'b0;
      wr_cmd_r <= 1'b0;

      //-- AW --
      if (aw_hs) begin
        aw_vld_r   <= 1'b1;
        wr_cmd_r   <= 1'b1;
        aw_id_r    <= aw_id;
        aw_len_r   <= aw_len;
        aw_size_r  <= aw_size;
        aw_burst_r <= aw_burst;
        aw_lock_r  <= aw_lock;
        aw_cache_r <= aw_cache;
        aw_prot_r  <= aw_prot;
        aw_qos_r   <= aw_qos;
        aw_addr_r  <= aw_addr;
        aw_align_r <= addr_align(aw_addr, aw_size);
        aw_b4k_r   <= boundary_4k(aw_addr, aw_len, aw_size);
      end

      //-- AR --
      if (ar_hs) begin
        ar_vld_r   <= 1'b1;
        rd_cmd_r   <= 1'b1;
        ar_id_r    <= ar_id;
        ar_len_r   <= ar_len;
        ar_size_r  <= ar_size;
        ar_burst_r <= ar_burst;
        ar_lock_r  <= ar_lock;
        ar_cache_r <= ar_cache;
        ar_prot_r  <= ar_prot;
        ar_qos_r   <= ar_qos;
        ar_addr_r  <= ar_addr;
        ar_align_r <= addr_align(ar_addr, ar_size);
        ar_b4k_r   <= boundary_4k(ar_addr, ar_len, ar_size);
      end

      //-- W (track first beat of each burst) --
      if (w_hs) begin
        w_vld_r        <= 1'b1;
        w_first_r      <= w_is_first;
        w_strb_r       <= w_strb;
        w_last_r       <= w_last;
        w_strb_lead0_r <= strb_lead_zeros(w_strb);
        w_is_first     <= w_last;  // next beat is "first" if this beat was last
      end

      //-- B --
      if (b_hs) begin
        b_vld_r  <= 1'b1;
        b_resp_r <= b_resp;
      end

      //-- R --
      if (r_hs) begin
        r_vld_r  <= 1'b1;
        r_resp_r <= r_resp;
        r_last_r <= r_last;
      end
    end
  end

  //==========================================================================
  // Outstanding transaction counters
  //==========================================================================
  logic [OS_CNT_W-1:0] rd_os_cnt, wr_os_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_os_cnt <= '0;
    end else begin
      case ({ar_hs, r_last_hs})
        2'b10:   rd_os_cnt <= rd_os_cnt + 1'b1;
        2'b01:   if (rd_os_cnt != 0) rd_os_cnt <= rd_os_cnt - 1'b1;
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_os_cnt <= '0;
    end else begin
      case ({aw_hs, b_hs})
        2'b10:   wr_os_cnt <= wr_os_cnt + 1'b1;
        2'b01:   if (wr_os_cnt != 0) wr_os_cnt <= wr_os_cnt - 1'b1;
        default: ;
      endcase
    end
  end

  // sample outstanding only when it changes
  logic [OS_CNT_W-1:0] rd_os_prev, wr_os_prev;
  logic                rd_os_chg,  wr_os_chg;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_os_prev <= '0;
      wr_os_prev <= '0;
    end else begin
      rd_os_prev <= rd_os_cnt;
      wr_os_prev <= wr_os_cnt;
    end
  end
  assign rd_os_chg = (rd_os_cnt != rd_os_prev);
  assign wr_os_chg = (wr_os_cnt != wr_os_prev);

  //==========================================================================
  // Lightweight running statistics (for the end-of-sim text report only)
  //==========================================================================
  longint unsigned total_wr_cmds, total_rd_cmds;
  longint unsigned max_wr_os_seen, max_rd_os_seen;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      total_wr_cmds  <= '0;
      total_rd_cmds  <= '0;
      max_wr_os_seen <= '0;
      max_rd_os_seen <= '0;
    end else begin
      if (aw_hs) total_wr_cmds <= total_wr_cmds + 1;
      if (ar_hs) total_rd_cmds <= total_rd_cmds + 1;
      if (wr_os_cnt > max_wr_os_seen) max_wr_os_seen <= wr_os_cnt;
      if (rd_os_cnt > max_rd_os_seen) max_rd_os_seen <= rd_os_cnt;
    end
  end

  //==========================================================================
  // Backpressure: response-channel ready-low run-length tracking
  //   Count consecutive cycles where VALID is held but READY is low; when the
  //   stall ends, latch the run length and pulse a sample event.
  //==========================================================================
  localparam int STALL_W = 16;

  logic [STALL_W-1:0] r_stall_cnt, b_stall_cnt;
  logic [STALL_W-1:0] r_stall_len_r, b_stall_len_r;
  logic               r_stall_done, b_stall_done;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_stall_cnt  <= '0;
      r_stall_done <= 1'b0;
    end else begin
      r_stall_done <= 1'b0;
      if (r_valid && !r_ready) begin
        r_stall_cnt <= (r_stall_cnt == '1) ? r_stall_cnt : r_stall_cnt + 1'b1;
      end else begin
        if (r_stall_cnt != 0) begin
          r_stall_len_r <= r_stall_cnt;
          r_stall_done  <= 1'b1;
        end
        r_stall_cnt <= '0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_stall_cnt  <= '0;
      b_stall_done <= 1'b0;
    end else begin
      b_stall_done <= 1'b0;
      if (b_valid && !b_ready) begin
        b_stall_cnt <= (b_stall_cnt == '1) ? b_stall_cnt : b_stall_cnt + 1'b1;
      end else begin
        if (b_stall_cnt != 0) begin
          b_stall_len_r <= b_stall_cnt;
          b_stall_done  <= 1'b1;
        end
        b_stall_cnt <= '0;
      end
    end
  end

  //==========================================================================
  // Covergroup 1: Write Address channel (AW)
  //==========================================================================
  covergroup cg_aw_channel @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_aw_channel"};

    // One bin per legal size code (1B..bus width); larger is illegal. Four
    // bits, so the illegal range is never reversed (a 1024-bit bus has none).
    cp_aw_size: coverpoint 4'(aw_size_r) iff (aw_vld_r) {
      bins bytes[]          = {[0:MAX_SIZE_CODE]};
      illegal_bins oversize = {[MAX_SIZE_CODE+1:15]};
    }

    cp_aw_len: coverpoint aw_len_r iff (aw_vld_r) {
      bins beat_1   = {0};
      bins beat_2   = {1};
      bins beat_4   = {3};
      bins beat_8   = {7};
      bins beat_16  = {15};
      bins beat_32  = {31};
      bins beat_64  = {63};
      bins beat_128 = {127};
      bins beat_256 = {255};
      bins other    = default;
    }

    // AoU supports INCR only; FIXED/WRAP are unsupported by the adapter.
    cp_aw_burst: coverpoint aw_burst_r iff (aw_vld_r) {
      bins incr = {2'b01};
      ignore_bins unsupported = {2'b00, 2'b10};
      illegal_bins rsvd = {2'b11};
    }

    // AXI4 A4.4: an allocate bit (AxCACHE[3:2]) needs Modifiable (AxCACHE[1]).
    cp_aw_cache: coverpoint aw_cache_r iff (aw_vld_r) {
      bins val[] = {[0:15]};
      ignore_bins axi4_illegal = {4'd4, 4'd5, 4'd8, 4'd9, 4'd12, 4'd13};
    }

    cp_aw_prot: coverpoint aw_prot_r iff (aw_vld_r);

    cp_aw_qos: coverpoint aw_qos_r iff (aw_vld_r) {
      bins val[] = {[0:15]};
    }

    cp_aw_lock: coverpoint aw_lock_r iff (aw_vld_r) {
      bins normal    = {1'b0};
      bins exclusive = {1'b1};
    }

    cp_aw_id: coverpoint aw_id_r iff (aw_vld_r) {
      bins id_zero = {0};
      bins id_low  = {[1 : ID_MAX/4]};
      bins id_mid  = {[ID_MAX/4 + 1 : (3*ID_MAX)/4]};
      bins id_high = {[(3*ID_MAX)/4 + 1 : ID_MAX-1]};
      bins id_max  = {ID_MAX};
    }

    cp_aw_addr_align: coverpoint aw_align_r iff (aw_vld_r) {
      bins bus_aligned  = {2};
      bins size_aligned = {1};
      bins unaligned    = {0};
    }

    cp_aw_addr_range: coverpoint aw_addr_r iff (aw_vld_r) {
      bins low  = {[0 : ADDR_LOW_LIMIT - 1]};
      bins high = {[ADDR_LOW_LIMIT : {ADDR_WIDTH{1'b1}}]};
    }

    // 4KB page boundary: crossing is an AXI4 violation -> illegal bin doubles
    // as a lightweight protocol check.
    cp_aw_4k_boundary: coverpoint aw_b4k_r iff (aw_vld_r) {
      bins within_page = {2'd0};
      bins ends_at_4k  = {2'd1};
      illegal_bins crosses_4k = {2'd2};
    }

    // Legal field combinations (burst is INCR-only, so size x len is the
    // interesting payload-shape cross).
    // A burst of more than 4KB can't avoid crossing a 4KB boundary (A3.4.1).
    cx_aw_size_x_len:   cross cp_aw_size, cp_aw_len {
      ignore_bins over_4k =
          (binsof(cp_aw_size) intersect {7} &&
           (binsof(cp_aw_len.beat_64) || binsof(cp_aw_len.beat_128) || binsof(cp_aw_len.beat_256))) ||
          (binsof(cp_aw_size) intersect {6} &&
           (binsof(cp_aw_len.beat_128) || binsof(cp_aw_len.beat_256))) ||
          (binsof(cp_aw_size) intersect {5} && binsof(cp_aw_len.beat_256));
    }
    cx_aw_size_x_align: cross cp_aw_size, cp_aw_addr_align {
      // 1-byte size is never unaligned; full-bus size is never size-aligned-only.
      ignore_bins sz_min_unaligned = binsof(cp_aw_size) intersect {0} && binsof(cp_aw_addr_align.unaligned);
      ignore_bins sz_max_sizeonly  = binsof(cp_aw_size) intersect {MAX_SIZE_CODE} && binsof(cp_aw_addr_align.size_aligned);
    }
  endgroup

  //==========================================================================
  // Covergroup 2: Read Address channel (AR)
  //==========================================================================
  covergroup cg_ar_channel @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_ar_channel"};

    // One bin per legal size code (1B..bus width); larger is illegal. Four
    // bits, so the illegal range is never reversed (a 1024-bit bus has none).
    cp_ar_size: coverpoint 4'(ar_size_r) iff (ar_vld_r) {
      bins bytes[]          = {[0:MAX_SIZE_CODE]};
      illegal_bins oversize = {[MAX_SIZE_CODE+1:15]};
    }

    cp_ar_len: coverpoint ar_len_r iff (ar_vld_r) {
      bins beat_1   = {0};
      bins beat_2   = {1};
      bins beat_4   = {3};
      bins beat_8   = {7};
      bins beat_16  = {15};
      bins beat_32  = {31};
      bins beat_64  = {63};
      bins beat_128 = {127};
      bins beat_256 = {255};
      bins other    = default;
    }

    // AoU supports INCR only; FIXED/WRAP are unsupported by the adapter.
    cp_ar_burst: coverpoint ar_burst_r iff (ar_vld_r) {
      bins incr = {2'b01};
      ignore_bins unsupported = {2'b00, 2'b10};
      illegal_bins rsvd = {2'b11};
    }

    // AXI4 A4.4: an allocate bit (AxCACHE[3:2]) needs Modifiable (AxCACHE[1]).
    cp_ar_cache: coverpoint ar_cache_r iff (ar_vld_r) {
      bins val[] = {[0:15]};
      ignore_bins axi4_illegal = {4'd4, 4'd5, 4'd8, 4'd9, 4'd12, 4'd13};
    }

    cp_ar_prot: coverpoint ar_prot_r iff (ar_vld_r);

    cp_ar_qos: coverpoint ar_qos_r iff (ar_vld_r) {
      bins val[] = {[0:15]};
    }

    cp_ar_lock: coverpoint ar_lock_r iff (ar_vld_r) {
      bins normal    = {1'b0};
      bins exclusive = {1'b1};
    }

    cp_ar_id: coverpoint ar_id_r iff (ar_vld_r) {
      bins id_zero = {0};
      bins id_low  = {[1 : ID_MAX/4]};
      bins id_mid  = {[ID_MAX/4 + 1 : (3*ID_MAX)/4]};
      bins id_high = {[(3*ID_MAX)/4 + 1 : ID_MAX-1]};
      bins id_max  = {ID_MAX};
    }

    cp_ar_addr_align: coverpoint ar_align_r iff (ar_vld_r) {
      bins bus_aligned  = {2};
      bins size_aligned = {1};
      bins unaligned    = {0};
    }

    cp_ar_addr_range: coverpoint ar_addr_r iff (ar_vld_r) {
      bins low  = {[0 : ADDR_LOW_LIMIT - 1]};
      bins high = {[ADDR_LOW_LIMIT : {ADDR_WIDTH{1'b1}}]};
    }

    cp_ar_4k_boundary: coverpoint ar_b4k_r iff (ar_vld_r) {
      bins within_page = {2'd0};
      bins ends_at_4k  = {2'd1};
      illegal_bins crosses_4k = {2'd2};
    }

    // A burst of more than 4KB can't avoid crossing a 4KB boundary (A3.4.1).
    cx_ar_size_x_len:   cross cp_ar_size, cp_ar_len {
      ignore_bins over_4k =
          (binsof(cp_ar_size) intersect {7} &&
           (binsof(cp_ar_len.beat_64) || binsof(cp_ar_len.beat_128) || binsof(cp_ar_len.beat_256))) ||
          (binsof(cp_ar_size) intersect {6} &&
           (binsof(cp_ar_len.beat_128) || binsof(cp_ar_len.beat_256))) ||
          (binsof(cp_ar_size) intersect {5} && binsof(cp_ar_len.beat_256));
    }
    cx_ar_size_x_align: cross cp_ar_size, cp_ar_addr_align {
      // 1-byte size is never unaligned; full-bus size is never size-aligned-only.
      ignore_bins sz_min_unaligned = binsof(cp_ar_size) intersect {0} && binsof(cp_ar_addr_align.unaligned);
      ignore_bins sz_max_sizeonly  = binsof(cp_ar_size) intersect {MAX_SIZE_CODE} && binsof(cp_ar_addr_align.size_aligned);
    }
  endgroup

  //==========================================================================
  // Covergroup 3: Write Data channel (W) - WSTRB incl. unaligned first beat
  //==========================================================================
  covergroup cg_w_channel @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_w_channel"};

    // 0 = none asserted, 1 = partial, 2 = all asserted
    cp_w_strb_pattern: coverpoint (
      (&w_strb_r) ? 2'd2 : ((|w_strb_r) ? 2'd1 : 2'd0)
    ) iff (w_vld_r) {
      bins none_set = {0};
      bins partial  = {1};
      bins all_set  = {2};
    }

    cp_w_last: coverpoint w_last_r iff (w_vld_r) {
      bins not_last = {1'b0};
      bins last     = {1'b1};
    }

    // First-beat leading byte mask: # of masked (zero) LSB byte lanes.
    // Non-zero on the first beat => unaligned start address (low bytes disabled).
    cp_w_first_lead_mask: coverpoint w_strb_lead0_r iff (w_vld_r && w_first_r) {
      bins aligned_b0  = {0};                              // aligned start (byte 0 enabled)
      bins masked_low  = {[1 : STRB_WIDTH/2]};             // small unaligned offset
      bins masked_high = {[STRB_WIDTH/2 + 1 : STRB_WIDTH]};// large unaligned offset
    }
  endgroup

  //==========================================================================
  // Covergroup 4: Read Data channel (R)
  //==========================================================================
  covergroup cg_r_channel @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_r_channel"};

    cp_r_resp: coverpoint r_resp_r iff (r_vld_r) {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }

    cp_r_last: coverpoint r_last_r iff (r_vld_r) {
      bins not_last = {1'b0};
      bins last     = {1'b1};
    }
  endgroup

  //==========================================================================
  // Covergroup 5: Write Response channel (B)
  //==========================================================================
  covergroup cg_b_channel @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_b_channel"};

    cp_b_resp: coverpoint b_resp_r iff (b_vld_r) {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
  endgroup

  //==========================================================================
  // Covergroup 6: Command activity (CMD_READ / CMD_WRITE)
  //==========================================================================
  covergroup cg_cmd @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_cmd"};

    cp_cmd_read:  coverpoint rd_cmd_r { bins issued = {1'b1}; }
    cp_cmd_write: coverpoint wr_cmd_r { bins issued = {1'b1}; }
  endgroup

  //==========================================================================
  // Covergroup 7: Outstanding transactions (up to MAX_OUTSTANDING)
  //==========================================================================
  covergroup cg_outstanding @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_outstanding"};

    cp_rd_outstanding: coverpoint rd_os_cnt iff (rd_os_chg) {
      bins os_1   = {1};
      bins os_few = {[2:15]};
      bins os_mid = {[16:MAX_OUTSTANDING/2]};
      bins os_hi  = {[MAX_OUTSTANDING/2 + 1 : MAX_OUTSTANDING-1]};
      bins os_max = {MAX_OUTSTANDING};
    }

    cp_wr_outstanding: coverpoint wr_os_cnt iff (wr_os_chg) {
      bins os_1   = {1};
      bins os_few = {[2:15]};
      bins os_mid = {[16:MAX_OUTSTANDING/2]};
      bins os_hi  = {[MAX_OUTSTANDING/2 + 1 : MAX_OUTSTANDING-1]};
      bins os_max = {MAX_OUTSTANDING};
    }
  endgroup

  //==========================================================================
  // Covergroup 8: Backpressure - response-channel stall run-length buckets
  //==========================================================================
  covergroup cg_backpressure @(posedge clk);
    option.per_instance = 1;
    option.name = {INST_NAME, "_cg_backpressure"};

    cp_r_stall_len: coverpoint r_stall_len_r iff (r_stall_done) {
      bins cyc_1       = {1};
      bins cyc_2_10    = {[2:10]};
      bins cyc_11_100  = {[11:100]};
      bins cyc_101_1k  = {[101:1000]};
      bins cyc_gt_1k   = {[1001:$]};
    }

    cp_b_stall_len: coverpoint b_stall_len_r iff (b_stall_done) {
      bins cyc_1       = {1};
      bins cyc_2_10    = {[2:10]};
      bins cyc_11_100  = {[11:100]};
      bins cyc_101_1k  = {[101:1000]};
      bins cyc_gt_1k   = {[1001:$]};
    }

    // FIFO-full proxy: response stall observed while outstanding is at max
    cp_r_stall_at_max_os: coverpoint (r_stall_done && (rd_os_cnt == MAX_OUTSTANDING)) {
      bins hit = {1'b1};
    }
    cp_b_stall_at_max_os: coverpoint (b_stall_done && (wr_os_cnt == MAX_OUTSTANDING)) {
      bins hit = {1'b1};
    }
  endgroup

  //==========================================================================
  // Covergroup instantiation
  //==========================================================================
  cg_aw_channel   cg_aw_channel_i   = new();
  cg_ar_channel   cg_ar_channel_i   = new();
  cg_w_channel    cg_w_channel_i    = new();
  cg_r_channel    cg_r_channel_i    = new();
  cg_b_channel    cg_b_channel_i    = new();
  cg_cmd          cg_cmd_i          = new();
  cg_outstanding  cg_outstanding_i  = new();
  cg_backpressure cg_backpressure_i = new();

  //==========================================================================
  // Per-bin hit tracking mirrors the covergroups so the text reports can be
  // union-merged across runs.
  //==========================================================================
`ifndef AOU_AXI4_FC_NO_TXT_RPT
  `include "aou_axi4_fc_bins.svh"
`endif

  //==========================================================================
  // End-of-sim text coverage report (get_inst_coverage() + $fwrite ->
  // human-readable .txt, no urg/VDB post-processing required).
  //   Each instance registers its section into the shared collector; the
  //   collector emits ONE combined file per run:
  //     <dir>/aou_axi4_fc.<run>.txt
  //   Output dir defaults to the run directory; override +AXI4_FC_RPT_DIR=<path>.
  //   Disable entirely with +define+AOU_AXI4_FC_NO_TXT_RPT.
  //==========================================================================
`ifndef AOU_AXI4_FC_NO_TXT_RPT
  final begin
    string section;
    real   c_aw, c_ar, c_w, c_r, c_b, c_cmd, c_os, c_bp, c_tot;

    c_aw  = cg_aw_channel_i.get_inst_coverage();
    c_ar  = cg_ar_channel_i.get_inst_coverage();
    c_w   = cg_w_channel_i.get_inst_coverage();
    c_r   = cg_r_channel_i.get_inst_coverage();
    c_b   = cg_b_channel_i.get_inst_coverage();
    c_cmd = cg_cmd_i.get_inst_coverage();
    c_os  = cg_outstanding_i.get_inst_coverage();
    c_bp  = cg_backpressure_i.get_inst_coverage();
    c_tot = (c_aw + c_ar + c_w + c_r + c_b + c_cmd + c_os + c_bp) / 8.0;

    section = {
      "--------------------------------------------------------------------------------\n",
      $sformatf("INTERFACE          : %s\n", INST_NAME),
      $sformatf("DATA_WIDTH         : %0d  (max AxSIZE = %0d bytes)\n", DATA_WIDTH, STRB_WIDTH),
      $sformatf("ADDR_WIDTH/ID_WIDTH: %0d / %0d\n", ADDR_WIDTH, ID_WIDTH),
      $sformatf("MAX_OUTSTANDING    : %0d\n", MAX_OUTSTANDING),
      "  --- Transaction statistics ---\n",
      $sformatf("  %-30s %0d\n", "Total Write Commands (AW):", total_wr_cmds),
      $sformatf("  %-30s %0d\n", "Total Read  Commands (AR):", total_rd_cmds),
      $sformatf("  %-30s %0d\n", "Max Outstanding Writes:",    max_wr_os_seen),
      $sformatf("  %-30s %0d\n", "Max Outstanding Reads:",     max_rd_os_seen),
      "  --- Coverage results (per covergroup) ---\n",
      $sformatf("  %-30s %6.2f%%\n", "Write Address (AW):", c_aw),
      $sformatf("  %-30s %6.2f%%\n", "Read  Address (AR):", c_ar),
      $sformatf("  %-30s %6.2f%%\n", "Write Data    (W):",  c_w),
      $sformatf("  %-30s %6.2f%%\n", "Read  Data    (R):",  c_r),
      $sformatf("  %-30s %6.2f%%\n", "Write Response(B):",  c_b),
      $sformatf("  %-30s %6.2f%%\n", "Command (RD/WR):",    c_cmd),
      $sformatf("  %-30s %6.2f%%\n", "Outstanding:",        c_os),
      $sformatf("  %-30s %6.2f%%\n", "Backpressure:",       c_bp),
      $sformatf("  >>> TOTAL: %6.2f%%\n", c_tot)
    };

    aou_axi4_fc_pkg::aou_axi4_fc_collector::add(INST_NAME, c_tot, section, fc_build_bin_section());
    aou_axi4_fc_pkg::aou_axi4_fc_collector::flush();
    $display("[AXI4_FC] %-28s total %0.2f%% (registered to combined report)", INST_NAME, c_tot);
  end
`endif

endmodule : aou_axi4_coverage_mod

`endif // AOU_AXI4_COVERAGE_MOD_SV
