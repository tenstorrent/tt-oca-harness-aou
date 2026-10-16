// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Exclusive accesses end to end (plan 4.25, 5.23), then the data-path traffic
// of aou_dp_vseq. With `excl` set, every RP runs, from the local S port and
// from the remote die at once, these rounds for each exclusive shape the
// narrower of the two buses allows (AXI4 A7.2.4: 2^n bytes up to 128, at most
// 16 beats, aligned to the total size). Both subordinates (the remote model
// and the local memory) keep an exclusive monitor, so the DUT only has to
// carry AxLOCK and EXOKAY:
//   exclusive read A, exclusive write A (same ID)           -> EXOKAY, EXOKAY
//   exclusive read B, plain write into B, exclusive write B -> EXOKAY, OKAY
//   exclusive write C with no exclusive read                -> OKAY
// aou_t1_attr_chk checks that the requester gets the subordinate's answer
// (DP-R07) and xfer_cov counts both outcomes; the scoreboard checks that only
// the EXOKAY write changed memory.
class aou_attr_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_attr_vseq)

  bit       excl;
  bit [3:0] excl_cache = 4'b0010;   // Normal Non-cacheable Non-bufferable

  // A window no traffic profile uses (aou_t1_traffic_cfg bases).
  localparam bit [63:0] EXCL_BASE = 64'h0000_0020_0000_0000;

  function new(string name = "aou_attr_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    void'(uvm_config_db#(bit)::get(null, "*", "attr_excl", excl));
    void'(uvm_config_db#(bit [3:0])::get(null, "*", "attr_excl_cache", excl_cache));
  endtask

  task scenario();
    if (excl) begin
      fork
        begin
          for (int unsigned r = 0; r < cfg.n_rp; r++) begin
            fork
              automatic int unsigned rr = r;
              begin
                if (k.dir != AOU_T1_R2L) excl_rounds(1'b1, rr);
              end
              begin
                if (k.dir != AOU_T1_L2R) excl_rounds(1'b0, rr);
              end
            join_none
          end
          wait fork;
        end
      join
    end
    super.scenario();
  endtask

  task excl_rounds(bit l2r, int unsigned r);
    aou_axi_sequencer sqr = l2r ? p_sequencer.s_mgr_sqr[r] : p_sequencer.r_mgr_sqr[r];
    int unsigned bus = (cfg.rp_bytes[r] < cfg.remote_bytes_of(r)) ? cfg.rp_bytes[r] :
                                                                    cfg.remote_bytes_of(r);
    // (AxSIZE, AxLEN) pairs; those wider than the bus are skipped.
    int unsigned shapes[9][2] = '{'{0, 0}, '{2, 3}, '{3, 15}, '{4, 7}, '{5, 3}, '{6, 1},
                                  '{7, 0}, '{3, 0}, '{5, 0}};
    bit [9:0] idb = 10'(10'h100 + 16 * r);
    bit [63:0] base = EXCL_BASE + 64'(r) * 64'h1_0000 + (l2r ? 64'h0 : 64'h8000);
    string who = $sformatf("RP%0d %s", r, l2r ? "local->remote" : "remote->local");
    int unsigned n = 0;
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
