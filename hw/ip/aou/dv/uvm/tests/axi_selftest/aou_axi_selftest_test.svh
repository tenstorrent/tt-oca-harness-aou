// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Loopback self-test: random traffic, then the #56 and #64 directed sequences,
// from a manager agent to a subordinate agent, with the scoreboard treating the
// subordinate's memory as the remote memory. In parallel, random requests go
// straight to the L4a remote AXI model, whose responses feed the scoreboard's
// remote_imp against the model's memory as the local memory.
// Plusargs: +AXI_DATA_BYTES=<8..128> (default: random per seed), +AXI_TIMING=<profile name,
// e.g. AOU_AXI_TIMING_STALL> (default: random per seed), +AXI_NUM_TXNS=<n>.
class aou_axi_selftest_test extends uvm_test;
  `uvm_component_utils(aou_axi_selftest_test)

  aou_axi_cfg       mcfg;
  aou_axi_cfg       scfg;
  aou_axi_mgr_agent mgr;
  aou_axi_sub_agent sub;
  aou_scoreboard    sb;
  aou_axi_cfg          rcfg;
  aou_remote_axi_model l4a;

  aou_axi_timing_e profile;
  int unsigned     num_txns = 600;
  int unsigned     l4a_batches = 12;
  bit [63:0]       rand_lo  = 64'h0000_0001_0000_0000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    int unsigned db;
    string pname;
    aou_axi_timing_e p;
    super.build_phase(phase);
    randcase
      1: db = 8;
      1: db = 16;
      1: db = 32;
      3: db = 64;
      2: db = 128;
    endcase
    void'($value$plusargs("AXI_DATA_BYTES=%d", db));
    void'($value$plusargs("AXI_NUM_TXNS=%d", num_txns));
    profile = aou_axi_timing_e'($urandom_range(4));
    if ($value$plusargs("AXI_TIMING=%s", pname)) begin
      p = p.first();
      do begin
        if (p.name() == pname) profile = p;
        p = p.next();
      end while (p != p.first());
    end

    mcfg = aou_axi_cfg::type_id::create("mcfg");
    mcfg.vif_key            = "axi0";
    mcfg.data_bytes         = db;
    mcfg.max_wr_outstanding = $urandom_range(16, 1);
    mcfg.max_rd_outstanding = $urandom_range(16, 1);
    mcfg.w_before_aw_en     = 1'($urandom_range(1));
    mcfg.timing.apply(profile);

    scfg = aou_axi_cfg::type_id::create("scfg");
    scfg.vif_key         = "axi0";
    scfg.data_bytes      = db;
    scfg.has_monitor     = 1'b0;
    scfg.r_interleave_en = 1'($urandom_range(1));
    scfg.timing.apply(profile);
    scfg.mem = aou_mem::type_id::create("mem");
    scfg.mem.add_error_region(rand_lo + 64'h1_0800, rand_lo + 64'h1_0fff, AOU_AXI_SLVERR);
    scfg.mem.add_error_region(rand_lo + 64'h2_0000, rand_lo + 64'h2_03ff, AOU_AXI_DECERR);

    `uvm_info(get_type_name(), $sformatf(
        "data_bytes=%0d timing=%s outstanding wr/rd=%0d/%0d w_before_aw=%0b r_interleave=%0b",
        db, profile.name(), mcfg.max_wr_outstanding, mcfg.max_rd_outstanding,
        mcfg.w_before_aw_en, scfg.r_interleave_en), UVM_LOW)

    rcfg = aou_axi_cfg::type_id::create("rcfg");
    rcfg.vif_key    = "axi0";
    rcfg.data_bytes = db;
    rcfg.timing.b_lat.set_range(0, 20);
    rcfg.timing.r_lat.set_range(0, 20);
    rcfg.mem = aou_mem::type_id::create("rmem");
    rcfg.mem.add_error_region(rand_lo + 64'h3800, rand_lo + 64'h38ff, AOU_AXI_SLVERR);

    uvm_config_db#(aou_axi_cfg)::set(this, "l4a", "cfg", rcfg);
    uvm_config_db#(aou_axi_cfg)::set(this, "mgr", "cfg", mcfg);
    uvm_config_db#(aou_axi_cfg)::set(this, "sub", "cfg", scfg);
    mgr = aou_axi_mgr_agent::type_id::create("mgr", this);
    sub = aou_axi_sub_agent::type_id::create("sub", this);
    sb  = aou_scoreboard::type_id::create("sb", this);
    l4a = aou_remote_axi_model::type_id::create("l4a", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    mgr.ap.connect(sb.local_mgr_imp);
    sb.remote_mem = scfg.mem;
    l4a.ap.connect(sb.remote_imp);
    sb.local_mem = rcfg.mem;
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_rand_seq         rs;
    aou_axi_unaligned_wr_seq us;
    aou_axi_b_zero_seq       zs;
    phase.raise_objection(this);
    fork
      run_l4a();
    join_none

    rs = aou_axi_rand_seq::type_id::create("rs");
    rs.num_txns = num_txns;
    rs.addr_lo  = rand_lo;
    rs.addr_hi  = rand_lo + 64'h3_ffff;
    rs.start(mgr.sqr);

    us = aou_axi_unaligned_wr_seq::type_id::create("us");
    us.start(mgr.sqr);

    // #64 needs zero delays end to end.
    mcfg.timing.apply(AOU_AXI_TIMING_ZERO);
    scfg.timing.apply(AOU_AXI_TIMING_ZERO);
    zs = aou_axi_b_zero_seq::type_id::create("zs");
    zs.start(mgr.sqr);

    l4a_done.get(1);
    phase.drop_objection(this);
  endtask

  protected semaphore l4a_done = new(0);
  // Members, not task locals: a forked block writing a task-local associative
  // array fails to compile on Verilator 5.052.
  protected int unsigned issued[bit [10:0]];
  protected int unsigned retired[bit [10:0]];

  // Batches of 16 overlapping requests, one 4KB page each; pages repeat across
  // batches so reads see earlier writes. IDs are shared within a batch, and
  // each ID's responses must come back in call order (reads and writes apart).
  protected task run_l4a();
    semaphore    done = new(0);
    for (int unsigned b = 0; b < l4a_batches; b++) begin
      for (int unsigned k = 0; k < 16; k++) begin
        aou_axi_txn  t = aou_axi_txn::type_id::create($sformatf("l4a%0d_%0d", b, k));
        bit [63:0]   base = rand_lo + 64'(k) * 64'h1000;
        int unsigned order;
        bit [10:0]   key;
        t.data_bytes = rcfg.data_bytes;
        `AOU_RANDOMIZE_WITH(t, {id < 10'd4; addr >= base; addr <= base + 64'hfff;})
        if (t.dir == AOU_AXI_WR) t.fill_wdata(AOU_AXI_STRB_MIXED);
        key = {t.dir == AOU_AXI_RD, t.id};
        if (!issued.exists(key)) begin
          issued[key]  = 0;
          retired[key] = 0;
        end
        order = issued[key]++;
        fork
          automatic aou_axi_txn req = t;
          automatic int unsigned ord = order;
          automatic bit [10:0] k2 = key;
          begin
            aou_axi_txn rsp;
            l4a.execute(req, rsp);
            if (retired[k2] != ord)
              `uvm_error(get_type_name(), $sformatf("L4a ID %0h response %0d came back as %0d",
                                                    req.id, ord, retired[k2]))
            retired[k2]++;
            done.put(1);
          end
        join_none
      end
      done.get(16);
    end
    l4a_done.put(1);
  endtask

  function void check_phase(uvm_phase phase);
    if (mgr.mon.n_b_zero == 0) `uvm_error(get_type_name(), "no B in the cycle after AW/W (#64)")
    if (mgr.mon.n_r_zero == 0) `uvm_error(get_type_name(), "no R in the cycle after AR")
    if (sb.n_l2r_wr == 0 || sb.n_l2r_rd == 0)
      `uvm_error(get_type_name(), "scoreboard checked no writes or no reads")
    if (sb.n_r2l_wr + sb.n_r2l_rd != l4a_batches * 16)
      `uvm_error(get_type_name(), "scoreboard did not check every L4a response")
    if (sb.n_l2r_wr + sb.n_l2r_rd != mgr.mon.n_wr + mgr.mon.n_rd)
      `uvm_error(get_type_name(), "scoreboard and monitor counts differ")
  endfunction
endclass
