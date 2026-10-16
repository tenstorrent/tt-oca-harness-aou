// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Transfer shapes for aou_dp_seq: which sizes, lengths, alignments, strobe
// patterns, IDs and attributes the data-path and feature tests generate. A
// test puts one in uvm_config_db (key "dp_knobs", scope "*"); the sequence
// reads it when it starts. Plusargs (+dp_size=, +dp_len=, ...) override it so
// one test class serves several run-list entries.
class aou_dp_knobs extends uvm_object;
  `uvm_object_utils(aou_dp_knobs)

  typedef enum {DP_ALIGN_ANY, DP_ALIGN_ALIGNED, DP_ALIGN_UNALIGNED} align_e;
  typedef enum {DP_STRB_FULL, DP_STRB_RANDOM, DP_STRB_MIXED, DP_STRB_PARTIAL, DP_STRB_SPARSE,
                DP_STRB_ZERO} strb_e;
  typedef enum {DP_ID_RANDOM, DP_ID_SAME, DP_ID_UNIQUE, DP_ID_HIGH} id_e;

  // Empty lists mean "any legal value". Lengths are AxLEN (beats - 1).
  int unsigned sizes[$];
  int unsigned lens[$];
  align_e      align = DP_ALIGN_ANY;
  bit          full_size = 1'b0;   // every transfer at the bus width (ignores sizes)
  strb_e       strb  = DP_STRB_FULL;
  id_e         ids   = DP_ID_RANDOM;
  bit [9:0]    id_value = 10'h3;   // DP_ID_SAME
  int unsigned max_id   = 15;      // DP_ID_RANDOM / DP_ID_UNIQUE wrap
  // Write then read the same bytes back, batch by batch.
  bit          loopback = 1'b0;
  // Transactions issued before waiting for all of them (0: no batching).
  int unsigned batch = 0;
  // Attributes: AWCACHE/ARCACHE[0] set with this probability; QoS from the list.
  int unsigned bufferable_pct = 0;
  int unsigned qos[$];
  bit [2:0]    prot = 3'd0;
  // Every transfer steps AxQOS through 0-15, AxPROT through 0-7 and AxCACHE
  // through the legal AXI4 encodings, separately for writes and reads, which
  // alternate (overrides bufferable_pct, qos and prot).
  bit          attr_sweep = 1'b0;

  // Scenario (read by aou_dp_vseq): direction, base profile and its overrides,
  // traffic phases, transactions per phase (0: the test's T1_TXN), features.
  aou_t1_dir_e       dir = AOU_T1_BOTH_DIRS;
  string             profile = "rand";
  int                wr_pct = -1;
  int                num_slots = -1;
  int unsigned       phases = 1;
  int unsigned       n = 0;
  bit [3:0]          rp_mask = 4'hF;   // RPs that carry the traffic
  aou_t1_feature_cfg feat;

  function new(string name = "aou_dp_knobs");
    super.new(name);
  endfunction

  static function int unsigned parse_list(string s, ref int unsigned q[$]);
    int start = 0;
    q.delete();
    for (int i = 0; i <= s.len(); i++) begin
      if (i == s.len() || s[i] == ",") begin
        if (i > start) q.push_back(s.substr(start, i - 1).atoi());
        start = i + 1;
      end
    end
    return q.size();
  endfunction

  // +dp_size=0,2,7 +dp_len=0,15 +dp_align=aligned|unaligned|any
  // +dp_strb=full|random|mixed|partial|sparse|zero +dp_ids=random|same|unique|high
  // +dp_batch=N +dp_loopback=0|1 +dp_buf_pct=N +dp_qos=0,5,10,15 +dp_attr_sweep=0|1
  function void apply_plusargs();
    string s;
    int unsigned v;
    if ($value$plusargs("dp_size=%s", s)) void'(parse_list(s, sizes));
    if ($value$plusargs("dp_len=%s", s)) void'(parse_list(s, lens));
    if ($value$plusargs("dp_qos=%s", s)) void'(parse_list(s, qos));
    if ($value$plusargs("dp_align=%s", s)) begin
      case (s)
        "aligned":   align = DP_ALIGN_ALIGNED;
        "unaligned": align = DP_ALIGN_UNALIGNED;
        "any":       align = DP_ALIGN_ANY;
        default: `uvm_fatal(get_type_name(), {"bad +dp_align=", s})
      endcase
    end
    if ($value$plusargs("dp_strb=%s", s)) begin
      case (s)
        "full":    strb = DP_STRB_FULL;
        "random":  strb = DP_STRB_RANDOM;
        "mixed":   strb = DP_STRB_MIXED;
        "partial": strb = DP_STRB_PARTIAL;
        "sparse":  strb = DP_STRB_SPARSE;
        "zero":    strb = DP_STRB_ZERO;
        default: `uvm_fatal(get_type_name(), {"bad +dp_strb=", s})
      endcase
    end
    if ($value$plusargs("dp_ids=%s", s)) begin
      case (s)
        "random": ids = DP_ID_RANDOM;
        "same":   ids = DP_ID_SAME;
        "unique": ids = DP_ID_UNIQUE;
        "high":   ids = DP_ID_HIGH;
        default: `uvm_fatal(get_type_name(), {"bad +dp_ids=", s})
      endcase
    end
    if ($value$plusargs("dp_batch=%d", v)) batch = v;
    if ($value$plusargs("dp_loopback=%d", v)) loopback = (v != 0);
    if ($value$plusargs("dp_buf_pct=%d", v)) bufferable_pct = v;
    if ($value$plusargs("dp_attr_sweep=%d", v)) attr_sweep = (v != 0);
    if ($value$plusargs("dp_wr_pct=%d", v)) wr_pct = v;
    if ($value$plusargs("dp_n=%d", v)) n = v;
    if ($value$plusargs("dp_phases=%d", v)) phases = v;
    if ($value$plusargs("dp_profile=%s", s)) profile = s;
    if ($value$plusargs("dp_dir=%s", s)) begin
      case (s)
        "l2r":  dir = AOU_T1_L2R;
        "r2l":  dir = AOU_T1_R2L;
        "both": dir = AOU_T1_BOTH_DIRS;
        default: `uvm_fatal(get_type_name(), {"bad +dp_dir=", s})
      endcase
    end
  endfunction

  function string convert2string();
    return $sformatf({"%s %s x%0d n=%0d wr=%0d sizes=%p lens=%p align=%s strb=%s ids=%s ",
                      "batch=%0d loopback=%0b buf=%0d%% qos=%p attr_sweep=%0b"},
                     dir.name(), profile, phases, n, wr_pct, sizes, lens, align.name(),
                     strb.name(), ids.name(), batch, loopback, bufferable_pct, qos, attr_sweep);
  endfunction
endclass
