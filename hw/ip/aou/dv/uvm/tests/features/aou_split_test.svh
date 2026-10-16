// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Splitter (plan 15.1-15.10, 15.12, 15.16, 15.17, 20.9; old F2). +split_aw/+split_ar
// take a value (AxLEN), "sweep" (a random legal 2^n-1), "illegal" (a random
// value that is not 2^n-1, stored as 0xF) or "per_rp" (a different random
// legal value on each RP, 15.16). Remote-originated 64-byte-beat bursts of
// +dp_len lengths; aou_split_chk checks the M-port bursts against each RP's
// limit, counting the beats after the downsizer on RPs narrower than 512 bits
// (15.17), and the scoreboard the reassembled data, RLAST and merged BRESP at
// the remote side.
class aou_split_test extends aou_dp_base_test;
  `uvm_component_utils(aou_split_test)

  aou_split_chk chk;
  int           aw[4] = '{15, 15, 15, 15};
  int           ar[4] = '{15, 15, 15, 15};

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_split_vseq";
  endfunction

  static function int pick(string s);
    int legal[9] = '{0, 1, 3, 7, 15, 31, 63, 127, 255};
    int v;
    case (s)
      "sweep": return legal[$urandom_range(8)];
      "illegal": begin
        do v = $urandom_range(254, 2); while (aou_reg_burstlen_cb::is_legal(uvm_reg_data_t'(v)));
        return v;
      end
      default: return s.atoi();
    endcase
  endfunction

  // per_rp: legal values, all different when there are enough RPs to tell.
  static function void pick_rps(string s, ref int v[4]);
    if (s == "per_rp") begin
      int legal[$] = '{0, 1, 3, 7, 15, 31, 63, 127, 255};
      legal.shuffle();
      foreach (v[r]) v[r] = legal[r];
    end else begin
      int x = pick(s);
      foreach (v[r]) v[r] = x;
    end
  endfunction

  function void set_knobs();
    string s;
    if ($value$plusargs("split_aw=%s", s)) pick_rps(s, aw);
    if ($value$plusargs("split_ar=%s", s)) pick_rps(s, ar);
    k.feat = aou_t1_feature_cfg::type_id::create("feat");
    for (int unsigned r = 0; r < AOU_T1_RP_COUNT; r++) begin
      k.feat.split_aw[r] = aw[r];
      k.feat.split_ar[r] = ar[r];
    end
    k.dir = AOU_T1_R2L;
    k.full_size = 1'b1;
    k.lens = '{15, 31, 63};
    k.align = aou_dp_knobs::DP_ALIGN_ALIGNED;
    k.loopback = 1'b1;
    k.batch = 4;
    k.wr_pct = 100;
    k.n = 32;
  endfunction

  // aou_split_chk counts M-port bursts without width conversion, so each RP's
  // remote side matches its local width unless +remote_bytes says otherwise.
  function void configure_test();
    string rb;
    if ($value$plusargs("remote_bytes=%s", rb)) return;
    foreach (cfg.rp_remote_bytes[r]) cfg.rp_remote_bytes[r] = cfg.rp_bytes[r];
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chk = aou_split_chk::type_id::create("chk", this);
    foreach (aw[r]) begin
      chk.max_awlen[r] = aou_split_vseq::stored(aw[r]);
      chk.max_arlen[r] = aou_split_vseq::stored(ar[r]);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    chk.rp_bytes = cfg.rp_bytes;
    env.rmgr.ap.connect(chk.orig_fifo.analysis_export);
    foreach (env.m_sub[r]) env.m_sub[r].ap.connect(chk.mport_fifo.analysis_export);
  endfunction
endclass
