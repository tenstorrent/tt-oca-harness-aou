// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Tenstorrent USA Inc
//*************************************************************************
//
// Per-bin hit tracking that mirrors the covergroups. Included inside the
// coverage module scope (uses the module's params and registered payload).
//
//   A per-covergroup percentage cannot be unioned across runs, so an explicit
//   per-bin hit-count is kept to make the per-run text file union-mergeable.
//
//   Bin boundaries here must stay in sync with the covergroup bins in
//   aou_axi4_coverage_mod.sv.
//   Bin key format: "<cg>|<cp>|<bin>" ; cross key bin is "A_X_B".
//
//*************************************************************************

  // Hit-count database for this interface instance (key -> count).
  int unsigned cov_hit[string];

  // ---- bin-name lists (denominator enumeration) ----
  localparam string LEN_BINS[9]   = '{"beat_1","beat_2","beat_4","beat_8","beat_16",
                                       "beat_32","beat_64","beat_128","beat_256"};
  localparam string ALIGN_BINS[3] = '{"bus_aligned","size_aligned","unaligned"};
  localparam string ID_BINS[5]    = '{"id_zero","id_low","id_mid","id_high","id_max"};
  localparam string RESP_BINS[4]  = '{"okay","exokay","slverr","decerr"};
  localparam string LAST_BINS[2]  = '{"not_last","last"};
  localparam string LOCK_BINS[2]  = '{"normal","exclusive"};
  localparam string WPAT_BINS[3]  = '{"none_set","partial","all_set"};
  localparam string LEAD_BINS[3]  = '{"aligned_b0","masked_low","masked_high"};
  localparam string OS_BINS[5]    = '{"os_1","os_few","os_mid","os_hi","os_max"};
  localparam string STALL_BINS[5] = '{"cyc_1","cyc_2_10","cyc_11_100","cyc_101_1k","cyc_gt_1k"};
  localparam string ADDR_BINS[2]  = '{"low","high"};
  localparam string B4K_BINS[2]   = '{"within_page","ends_at_4k"};

  // ---- value -> bin-name classifiers ("" => value falls in no counted bin) ----
  function automatic string fc_sz_name(input logic [2:0] s);
    return (s <= MAX_SIZE_CODE) ? $sformatf("bytes_%0d", s) : "";
  endfunction
  function automatic string fc_len_name(input logic [7:0] l);
    case (l)
      8'd0:    return "beat_1";   8'd1:   return "beat_2";   8'd3:   return "beat_4";
      8'd7:    return "beat_8";   8'd15:  return "beat_16";  8'd31:  return "beat_32";
      8'd63:   return "beat_64";  8'd127: return "beat_128"; 8'd255: return "beat_256";
      default: return "";
    endcase
  endfunction
  // AoU: only INCR is a counted bin (FIXED/WRAP unsupported, RSVD illegal).
  function automatic string fc_burst_name(input logic [1:0] b);
    return (b == 2'b01) ? "incr" : "";
  endfunction
  // AxCACHE: AXI4 A4.4 (Table A4-5) allows an allocate bit (AxCACHE[3:2]) only on a
  // modifiable transaction (AxCACHE[1]), so 4, 5, 8, 9, 12 and 13 are never legal.
  function automatic bit fc_cache_legal(input int c);
    return (c[3:2] == 2'b00) || c[1];
  endfunction
  function automatic string fc_cache_name(input logic [3:0] c);
    return fc_cache_legal(c) ? $sformatf("val_%0d", c) : "";
  endfunction
  function automatic string fc_lock_name(input logic l);  return l ? "exclusive" : "normal"; endfunction
  function automatic string fc_last_name(input logic l);  return l ? "last" : "not_last"; endfunction
  function automatic string fc_align_name(input logic [1:0] a);
    case (a) 2'd2: return "bus_aligned"; 2'd1: return "size_aligned"; 2'd0: return "unaligned"; default: return ""; endcase
  endfunction
  function automatic string fc_b4k_name(input logic [1:0] v);
    case (v) 2'd0: return "within_page"; 2'd1: return "ends_at_4k"; default: return ""; endcase
  endfunction
  function automatic string fc_id_name(input longint v);
    if      (v == 0)             return "id_zero";
    else if (v <= ID_MAX/4)      return "id_low";
    else if (v <= (3*ID_MAX)/4)  return "id_mid";
    else if (v <= ID_MAX-1)      return "id_high";
    else                         return "id_max";
  endfunction
  function automatic string fc_resp_name(input logic [1:0] r);
    case (r) 2'b00: return "okay"; 2'b01: return "exokay"; 2'b10: return "slverr"; default: return "decerr"; endcase
  endfunction
  function automatic string fc_wpat_name(input logic [STRB_WIDTH-1:0] s);
    if (&s) return "all_set"; else if (|s) return "partial"; else return "none_set";
  endfunction
  function automatic string fc_lead_name(input logic [6:0] n);
    if      (n == 0)              return "aligned_b0";
    else if (n <= STRB_WIDTH/2)   return "masked_low";
    else                          return "masked_high";
  endfunction
  function automatic string fc_os_name(input logic [OS_CNT_W-1:0] c);
    if      (c == 0)                 return "";           // 0 outstanding is not a counted bin
    else if (c == 1)                 return "os_1";
    else if (c <= 15)                return "os_few";
    else if (c <= MAX_OUTSTANDING/2) return "os_mid";
    else if (c <= MAX_OUTSTANDING-1) return "os_hi";
    else                             return "os_max";
  endfunction
  function automatic string fc_stall_name(input logic [STALL_W-1:0] n);
    if      (n == 0)        return "";
    else if (n == 1)        return "cyc_1";
    else if (n <= 10)       return "cyc_2_10";
    else if (n <= 100)      return "cyc_11_100";
    else if (n <= 1000)     return "cyc_101_1k";
    else                    return "cyc_gt_1k";
  endfunction
  function automatic string fc_addr_name(input logic [ADDR_WIDTH-1:0] a);
    return (a < ADDR_LOW_LIMIT) ? "low" : "high";
  endfunction
  // (size-code, len-bin) combinations of at most 4KB (matches cross ignore_bins);
  // LEN_BINS[i] is 2**i beats.
  function automatic bit fc_size_len_legal(input int s, input string ln);
    foreach (LEN_BINS[i]) if (LEN_BINS[i] == ln) return (s + i) <= 12;
    return 1'b0;
  endfunction
  // Reachable (size-code, align-bin) combinations (matches cross ignore_bins).
  function automatic bit fc_size_align_legal(input int s, input string an);
    if (an == "unaligned")    return (s != 0);
    if (an == "size_aligned") return (s != MAX_SIZE_CODE);
    return 1'b1;
  endfunction

  // ---- count / pre-register helpers ----
  // Keys ending in "|" mean the classifier returned no counted bin -> skip.
  function automatic void fc_bump(input string key);
    if (key.len() != 0 && key.substr(key.len()-1, key.len()-1) != "|") begin
      if (cov_hit.exists(key)) cov_hit[key] = cov_hit[key] + 1;
      else                     cov_hit[key] = 1;
    end
  endfunction
  function automatic void fc_reg(input string key);   // register a denominator bin at 0
    if (key.len() != 0 && !cov_hit.exists(key)) cov_hit[key] = 0;
  endfunction

  // Register every legal bin of one address channel (cg="cg_aw"/"cg_ar", cpp="cp_aw_"/"cp_ar_").
  function automatic void fc_reg_addr_chan(input string cg, input string cpp);
    for (int s = 0; s <= MAX_SIZE_CODE; s++) fc_reg($sformatf("%s|%ssize|bytes_%0d", cg, cpp, s));
    foreach (LEN_BINS[i])   fc_reg($sformatf("%s|%slen|%s",        cg, cpp, LEN_BINS[i]));
    fc_reg($sformatf("%s|%sburst|incr", cg, cpp));
    for (int c = 0; c < 16; c++)
      if (fc_cache_legal(c)) fc_reg($sformatf("%s|%scache|val_%0d", cg, cpp, c));
    for (int p = 0; p < 8;  p++) fc_reg($sformatf("%s|%sprot|prot_%0d", cg, cpp, p));
    for (int q = 0; q < 16; q++) fc_reg($sformatf("%s|%sqos|val_%0d",   cg, cpp, q));
    foreach (LOCK_BINS[i])  fc_reg($sformatf("%s|%slock|%s",        cg, cpp, LOCK_BINS[i]));
    foreach (ID_BINS[i])    fc_reg($sformatf("%s|%sid|%s",          cg, cpp, ID_BINS[i]));
    foreach (ALIGN_BINS[i]) fc_reg($sformatf("%s|%saddr_align|%s",  cg, cpp, ALIGN_BINS[i]));
    foreach (ADDR_BINS[i])  fc_reg($sformatf("%s|%saddr_range|%s",  cg, cpp, ADDR_BINS[i]));
    foreach (B4K_BINS[i])   fc_reg($sformatf("%s|%s4k_boundary|%s", cg, cpp, B4K_BINS[i]));
    // crosses
    for (int s = 0; s <= MAX_SIZE_CODE; s++) foreach (LEN_BINS[l])
      if (fc_size_len_legal(s, LEN_BINS[l]))
        fc_reg($sformatf("%s|cx_size_x_len|bytes_%0d_X_%s", cg, s, LEN_BINS[l]));
    for (int s = 0; s <= MAX_SIZE_CODE; s++) foreach (ALIGN_BINS[a])
      if (fc_size_align_legal(s, ALIGN_BINS[a]))
        fc_reg($sformatf("%s|cx_size_x_align|bytes_%0d_X_%s", cg, s, ALIGN_BINS[a]));
  endfunction

  // Pre-register the full denominator so every per-run file lists all bins (even 0-hit).
  initial begin
    fc_reg_addr_chan("cg_aw", "cp_aw_");
    fc_reg_addr_chan("cg_ar", "cp_ar_");
    foreach (WPAT_BINS[i]) fc_reg($sformatf("cg_w|cp_w_strb_pattern|%s",     WPAT_BINS[i]));
    foreach (LAST_BINS[i]) fc_reg($sformatf("cg_w|cp_w_last|%s",             LAST_BINS[i]));
    foreach (LEAD_BINS[i]) fc_reg($sformatf("cg_w|cp_w_first_lead_mask|%s",  LEAD_BINS[i]));
    foreach (RESP_BINS[i]) fc_reg($sformatf("cg_r|cp_r_resp|%s",            RESP_BINS[i]));
    foreach (LAST_BINS[i]) fc_reg($sformatf("cg_r|cp_r_last|%s",            LAST_BINS[i]));
    foreach (RESP_BINS[i]) fc_reg($sformatf("cg_b|cp_b_resp|%s",            RESP_BINS[i]));
    fc_reg("cg_cmd|cp_cmd_read|issued");
    fc_reg("cg_cmd|cp_cmd_write|issued");
    foreach (OS_BINS[i])    fc_reg($sformatf("cg_os|cp_rd_outstanding|%s", OS_BINS[i]));
    foreach (OS_BINS[i])    fc_reg($sformatf("cg_os|cp_wr_outstanding|%s", OS_BINS[i]));
    foreach (STALL_BINS[i]) fc_reg($sformatf("cg_bp|cp_r_stall_len|%s",    STALL_BINS[i]));
    foreach (STALL_BINS[i]) fc_reg($sformatf("cg_bp|cp_b_stall_len|%s",    STALL_BINS[i]));
    fc_reg("cg_bp|cp_r_stall_at_max_os|hit");
    fc_reg("cg_bp|cp_b_stall_at_max_os|hit");
  end

  // Per-cycle counting (same timing/guards as the covergroups).
  always_ff @(posedge clk) begin
    string sb, lb, bb, ab;
    if (aw_vld_r) begin
      sb = fc_sz_name(aw_size_r); lb = fc_len_name(aw_len_r);
      bb = fc_burst_name(aw_burst_r); ab = fc_align_name(aw_align_r);
      fc_bump($sformatf("cg_aw|cp_aw_size|%s",        sb));
      fc_bump($sformatf("cg_aw|cp_aw_len|%s",         lb));
      fc_bump($sformatf("cg_aw|cp_aw_burst|%s",       bb));
      fc_bump($sformatf("cg_aw|cp_aw_cache|%s",       fc_cache_name(aw_cache_r)));
      fc_bump($sformatf("cg_aw|cp_aw_prot|prot_%0d",  aw_prot_r));
      fc_bump($sformatf("cg_aw|cp_aw_qos|val_%0d",    aw_qos_r));
      fc_bump($sformatf("cg_aw|cp_aw_lock|%s",        fc_lock_name(aw_lock_r)));
      fc_bump($sformatf("cg_aw|cp_aw_id|%s",          fc_id_name(aw_id_r)));
      fc_bump($sformatf("cg_aw|cp_aw_addr_align|%s",  ab));
      fc_bump($sformatf("cg_aw|cp_aw_addr_range|%s",  fc_addr_name(aw_addr_r)));
      fc_bump($sformatf("cg_aw|cp_aw_4k_boundary|%s", fc_b4k_name(aw_b4k_r)));
      if (sb != "" && lb != "" && fc_size_len_legal(aw_size_r, lb))
        fc_bump($sformatf("cg_aw|cx_size_x_len|%s_X_%s", sb, lb));
      if (sb != "" && ab != "" && fc_size_align_legal(aw_size_r, ab))
        fc_bump($sformatf("cg_aw|cx_size_x_align|%s_X_%s", sb, ab));
    end
    if (ar_vld_r) begin
      sb = fc_sz_name(ar_size_r); lb = fc_len_name(ar_len_r);
      bb = fc_burst_name(ar_burst_r); ab = fc_align_name(ar_align_r);
      fc_bump($sformatf("cg_ar|cp_ar_size|%s",        sb));
      fc_bump($sformatf("cg_ar|cp_ar_len|%s",         lb));
      fc_bump($sformatf("cg_ar|cp_ar_burst|%s",       bb));
      fc_bump($sformatf("cg_ar|cp_ar_cache|%s",       fc_cache_name(ar_cache_r)));
      fc_bump($sformatf("cg_ar|cp_ar_prot|prot_%0d",  ar_prot_r));
      fc_bump($sformatf("cg_ar|cp_ar_qos|val_%0d",    ar_qos_r));
      fc_bump($sformatf("cg_ar|cp_ar_lock|%s",        fc_lock_name(ar_lock_r)));
      fc_bump($sformatf("cg_ar|cp_ar_id|%s",          fc_id_name(ar_id_r)));
      fc_bump($sformatf("cg_ar|cp_ar_addr_align|%s",  ab));
      fc_bump($sformatf("cg_ar|cp_ar_addr_range|%s",  fc_addr_name(ar_addr_r)));
      fc_bump($sformatf("cg_ar|cp_ar_4k_boundary|%s", fc_b4k_name(ar_b4k_r)));
      if (sb != "" && lb != "" && fc_size_len_legal(ar_size_r, lb))
        fc_bump($sformatf("cg_ar|cx_size_x_len|%s_X_%s", sb, lb));
      if (sb != "" && ab != "" && fc_size_align_legal(ar_size_r, ab))
        fc_bump($sformatf("cg_ar|cx_size_x_align|%s_X_%s", sb, ab));
    end
    if (w_vld_r) begin
      fc_bump($sformatf("cg_w|cp_w_strb_pattern|%s", fc_wpat_name(w_strb_r)));
      fc_bump($sformatf("cg_w|cp_w_last|%s",         fc_last_name(w_last_r)));
      if (w_first_r) fc_bump($sformatf("cg_w|cp_w_first_lead_mask|%s", fc_lead_name(w_strb_lead0_r)));
    end
    if (r_vld_r) begin
      fc_bump($sformatf("cg_r|cp_r_resp|%s", fc_resp_name(r_resp_r)));
      fc_bump($sformatf("cg_r|cp_r_last|%s", fc_last_name(r_last_r)));
    end
    if (b_vld_r) fc_bump($sformatf("cg_b|cp_b_resp|%s", fc_resp_name(b_resp_r)));
    if (wr_cmd_r) fc_bump("cg_cmd|cp_cmd_write|issued");
    if (rd_cmd_r) fc_bump("cg_cmd|cp_cmd_read|issued");
    if (rd_os_chg) fc_bump($sformatf("cg_os|cp_rd_outstanding|%s", fc_os_name(rd_os_cnt)));
    if (wr_os_chg) fc_bump($sformatf("cg_os|cp_wr_outstanding|%s", fc_os_name(wr_os_cnt)));
    if (r_stall_done) begin
      fc_bump($sformatf("cg_bp|cp_r_stall_len|%s", fc_stall_name(r_stall_len_r)));
      if (rd_os_cnt == MAX_OUTSTANDING) fc_bump("cg_bp|cp_r_stall_at_max_os|hit");
    end
    if (b_stall_done) begin
      fc_bump($sformatf("cg_bp|cp_b_stall_len|%s", fc_stall_name(b_stall_len_r)));
      if (wr_os_cnt == MAX_OUTSTANDING) fc_bump("cg_bp|cp_b_stall_at_max_os|hit");
    end
  end

  // Build the machine-readable bin-data section consumed by the union-merge step.
  function automatic string fc_build_bin_section();
    string s;
    s = $sformatf("#IFACE %s\n", INST_NAME);
    s = {s, $sformatf("#META data_width=%0d addr_width=%0d id_width=%0d max_os=%0d\n",
                      DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, MAX_OUTSTANDING)};
    s = {s, $sformatf("#STAT total_wr=%0d total_rd=%0d max_wr_os=%0d max_rd_os=%0d\n",
                      total_wr_cmds, total_rd_cmds, max_wr_os_seen, max_rd_os_seen)};
    foreach (cov_hit[k]) s = {s, $sformatf("BIN %s %0d\n", k, cov_hit[k])};
    s = {s, "#ENDIFACE\n"};
    return s;
  endfunction
