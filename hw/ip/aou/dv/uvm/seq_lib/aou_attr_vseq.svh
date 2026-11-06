// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Exclusive accesses end to end (plan 4.25, 5.23), then the data-path traffic
// of aou_dp_vseq. With `excl` set, every RP runs, from the local S port and
// from the remote die at once, these rounds for each exclusive shape the
// narrower of the two buses allows (AXI4 A7.2.4 allows 2^n bytes up to 128,
// at most 16 beats, aligned to the total size; this bench models exclusives
// of at most 64 bytes, the project's limit). Both subordinates (the remote model
// and the local memory) keep an exclusive monitor, so the DUT only has to
// carry AxLOCK and EXOKAY:
//   exclusive read A, exclusive write A (same ID)           -> EXOKAY, EXOKAY
//   exclusive read B, plain write into B, exclusive write B -> EXOKAY, OKAY
//   exclusive write C with no exclusive read                -> OKAY
// A round that lands on a page without an exclusive monitor (aou_mem
// no_excl_pct) gets OKAY throughout, and its exclusive writes land like
// normal ones (AXI4 A7.2.4).
// aou_t1_attr_chk checks that the requester gets the subordinate's answer
// (DP-R07) and xfer_cov counts both outcomes; the scoreboard checks that only
// the EXOKAY writes, and the writes where there is no monitor, changed memory.
// With `user` set (aou_attr_test +attr_user=1), every RP first runs, from each
// side, the AXI USER rounds: with the agents' USER pattern set to all ones,
// then a walking bit, then random (per beat, cfg.user_mode), then USER held
// at 0, a one-beat write at the bus width (no split, one WriteData, one B), a
// 16-beat write and read at the bus width (split into MAX_AxBURSTLEN
// sub-bursts on the M port when the test lowered it, so the DUT merges
// several B into one WriteResp, and
// downsized when the DUT's port is narrower than the remote's, so several
// local R beats merge into one ReadData whose FLEX is the first beat's), eight
// 4-byte beats, and a one-beat read. aou_t1_attr_chk compares the FLEX of
// every DUT message with the USER value (DP-R08) and the USER the DUT's ports
// present for the remote die's messages with their FLEX (DP-R12).
class aou_attr_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_attr_vseq)

  bit       excl;
  bit       user;
  bit [3:0] excl_cache = 4'b0010;   // Normal Non-cacheable Non-bufferable

  // Windows no traffic profile uses (aou_t1_traffic_cfg bases).
  localparam bit [63:0] EXCL_BASE = 64'h0000_0020_0000_0000;
  localparam bit [63:0] USER_BASE = 64'h0000_0021_0000_0000;

  function new(string name = "aou_attr_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    void'(uvm_config_db#(bit)::get(null, "*", "attr_excl", excl));
    void'(uvm_config_db#(bit)::get(null, "*", "attr_user", user));
    void'(uvm_config_db#(bit [3:0])::get(null, "*", "attr_excl_cache", excl_cache));
  endtask

  task scenario();
    if (user) rounds(1'b1);
    if (excl) rounds(1'b0);
    super.scenario();
  endtask

  // Every RP, from the local S port and from the remote die at once.
  task rounds(bit is_user);
    fork
      begin
        for (int unsigned r = 0; r < cfg.n_rp; r++) begin
          fork
            automatic int unsigned rr = r;
            begin
              if (k.dir != AOU_T1_R2L) begin
                if (is_user) user_rounds(1'b1, rr);
                else excl_rounds(1'b1, rr);
              end
            end
            begin
              if (k.dir != AOU_T1_L2R) begin
                if (is_user) user_rounds(1'b0, rr);
                else excl_rounds(1'b0, rr);
              end
            end
          join_none
        end
        wait fork;
      end
    join
  endtask

  // The agent whose USER the DUT forwards for requests from this side: the
  // S-port manager of RP r (AWUSER/ARUSER/WUSER), or the M-port subordinate
  // of the DUT RP the remote die's plane r reaches (BUSER/RUSER).
  function aou_axi_cfg user_cfg(bit l2r, int unsigned r);
    int unsigned m = r;
    if (l2r) return cfg.s_mgr_cfg[r];
    if (r < 4) m = int'(cfg.l3_cfg.dest_rp[r]);
    return cfg.m_sub_cfg[m];
  endfunction

  task user_rounds(bit l2r, int unsigned r);
    aou_axi_sequencer sqr = l2r ? p_sequencer.s_mgr_sqr[r] : p_sequencer.r_mgr_sqr[r];
    aou_axi_cfg ac = user_cfg(l2r, r);
    int unsigned bus = l2r ? cfg.rp_bytes[r] : cfg.remote_bytes_of(r);   // the requester's
    bit [2:0] sz = 3'($clog2(bus));
    bit [9:0] idb = 10'(10'h140 + 16 * r);
    bit [63:0] base = USER_BASE + 64'(r) * 64'h1_0000 + (l2r ? 64'h0 : 64'h8000);
    aou_axi_user_pat_e pats[3] = '{AOU_AXI_USER_PAT_ONES, AOU_AXI_USER_PAT_WALK,
                                   AOU_AXI_USER_PAT_RANDOM};
    string who = $sformatf("RP%0d %s", r, l2r ? "local->remote" : "remote->local");
    aou_axi_user_mode_e mode = ac.user_mode;
    // Three patterns in the test's user mode, then the same set with USER held
    // at 0 (a requester without USER): FLEX 0 in every message kind.
    for (int i = 0; i < 4; i++) begin
      bit [63:0] a = base + 64'(i) * 64'h2000;
      if (i < 3) ac.user_pat = pats[i];
      else ac.user_mode = AOU_AXI_USER_ZERO;
      user_one(sqr, AOU_AXI_WR, idb, a, sz, 8'd0, i);
      user_one(sqr, AOU_AXI_WR, idb + 10'd1, a + 64'h400, sz, 8'd15, i);
      user_one(sqr, AOU_AXI_RD, idb + 10'd1, a + 64'h400, sz, 8'd15, i);
      user_one(sqr, AOU_AXI_WR, idb + 10'd2, a + 64'h800, 3'd2, 8'd7, i);
      user_one(sqr, AOU_AXI_RD, idb + 10'd2, a + 64'h800, 3'd2, 8'd7, i);
      user_one(sqr, AOU_AXI_RD, idb + 10'd3, a + 64'hC00, sz, 8'd0, i);
    end
    ac.user_mode = mode;
    ac.user_pat = AOU_AXI_USER_PAT_RANDOM;
    `uvm_info(get_type_name(), $sformatf("%s: USER rounds done on a %0d-byte bus (%s)", who, bus,
                                         aou_axi_cfg::user_mode_name(ac.user_mode)), UVM_LOW)
  endtask

  task user_one(aou_axi_sequencer sqr, aou_axi_dir_e dir, bit [9:0] id, bit [63:0] a,
                bit [2:0] sz, bit [7:0] ln, int i);
    aou_attr_one_seq s = aou_attr_one_seq::type_id::create("user");
    s.dir = dir;
    s.id = id;
    s.addr = a;
    s.size = sz;
    s.len = ln;
    s.cache = 4'b0010;
    s.prot = 3'(i);
    s.qos = 4'(i);
    s.start(sqr);
  endtask

  task excl_rounds(bit l2r, int unsigned r);
    aou_axi_sequencer sqr = l2r ? p_sequencer.s_mgr_sqr[r] : p_sequencer.r_mgr_sqr[r];
    int unsigned bus = (cfg.rp_bytes[r] < cfg.remote_bytes_of(r)) ? cfg.rp_bytes[r] :
                                                                    cfg.remote_bytes_of(r);
    // (AxSIZE, AxLEN) pairs; those wider than the bus are skipped.
    int unsigned shapes[8][2] = '{'{0, 0}, '{2, 3}, '{3, 7}, '{4, 3}, '{5, 1}, '{6, 0},
                                  '{3, 0}, '{5, 0}};
    bit [9:0] idb = 10'(10'h100 + 16 * r);
    bit [63:0] base = EXCL_BASE + 64'(r) * 64'h1_0000 + (l2r ? 64'h0 : 64'h8000);
    string who = $sformatf("RP%0d %s", r, l2r ? "local->remote" : "remote->local");
    int unsigned n = 0;
    // A local port that shares its lane with another under the seed's RP
    // mapping issues no exclusive access: its reads and writes may reach the
    // remote die under different IDs (MAS 3.10.5, overview 2.2). The env
    // config makes that decision once, as the port's lock_en. The remote
    // die's requests are not remapped, so its rounds always run.
    if (l2r && !cfg.s_mgr_cfg[r].lock_en) begin
      `uvm_info(get_type_name(), $sformatf("%s: no exclusive rounds, the port's lane is merged",
                                           who), UVM_LOW)
      return;
    end
    foreach (shapes[i]) begin
      bit [2:0] sz = 3'(shapes[i][0]);
      bit [7:0] ln = 8'(shapes[i][1]);
      bit [63:0] a = base + 64'(n) * 64'h400;
      if ((32'd1 << sz) > bus) continue;
      n++;
      excl_one(sqr, AOU_AXI_RD, idb, a, sz, ln, 1'b1, i);
      excl_one(sqr, AOU_AXI_WR, idb, a, sz, ln, 1'b1, i);
      excl_one(sqr, AOU_AXI_RD, idb + 10'd1, a + 64'h100, sz, ln, 1'b1, i);
      excl_one(sqr, AOU_AXI_WR, idb + 10'd2, a + 64'h100, 3'd0, 8'd0, 1'b0, i);
      excl_one(sqr, AOU_AXI_WR, idb + 10'd1, a + 64'h100, sz, ln, 1'b1, i);
      excl_one(sqr, AOU_AXI_WR, idb + 10'd3, a + 64'h200, sz, ln, 1'b1, i);
    end
    `uvm_info(get_type_name(), $sformatf("%s: %0d exclusive shapes on a %0d-byte bus", who, n,
                                         bus), UVM_LOW)
  endtask

  task excl_one(aou_axi_sequencer sqr, aou_axi_dir_e dir, bit [9:0] id,
                bit [63:0] a, bit [2:0] sz, bit [7:0] ln, bit lock, int i);
    aou_attr_one_seq s = aou_attr_one_seq::type_id::create("excl");
    s.dir = dir;
    s.id = id;
    s.addr = a;
    s.size = sz;
    s.len = ln;
    s.lock = lock;
    s.cache = excl_cache;
    s.prot = 3'(i);
    s.qos = 4'(i);
    s.start(sqr);
  endtask
endclass
