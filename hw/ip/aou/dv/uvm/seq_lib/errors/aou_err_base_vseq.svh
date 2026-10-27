// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Shared base of the AXI error, ID-mismatch and interrupt sequences: directed
// transactions from either side, per-RP register fields, interrupt pins and
// the R/B response error debug FIFO (MAS software-operation 7.2.4).
//
// Debug-window accesses: the remote die reads and pops with dbg_len+1 beats
// (AxLEN dbg_len, cut per RP to the 4 KB a burst may span, AXI4 A3.4.1).
// aou_t1_dbg_fifo_chk predicts each FIFO and checks every read and pop
// (T1-E02, T1-E03, T1-E19); the sequence only issues them.
class aou_err_base_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_err_base_vseq)

  static const bit [63:0] DBG_BASE = 64'h0000_0071_0000_0000;
  int unsigned dbg_wait = 5000;   // cycles a debug-window access may take
  int unsigned dbg_len = 0;       // AxLEN of a debug-window read or pop, before dbg_len_of()
  bit [3:0] dbg_cache = 4'd0;     // AxCACHE of a debug-window read or pop (bit 1: modifiable)

  function new(string name = "aou_err_base_vseq");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------
  // A single INCR transaction of len+1 full-width beats, from the remote die
  // (remote = 1) or a local manager.
  function aou_axi_txn mk(bit remote, int unsigned rp, aou_axi_dir_e dir, bit [9:0] id,
                          bit [63:0] addr, int unsigned len = 0, bit [3:0] cache = 4'd0);
    aou_axi_txn t = aou_axi_txn::type_id::create("t");
    t.data_bytes = remote ? cfg.remote_bytes_of(rp) : cfg.rp_bytes[rp];
    t.rp = rp;
    t.local_side = !remote;
    t.dir = dir;
    t.id = id;
    t.addr = addr;
    t.len = 8'(len);
    t.size = 3'($clog2(t.data_bytes));
    t.burst = AOU_AXI_INCR;
    t.lock = 1'b0;
    t.cache = cache;
    t.prot = 3'd0;
    t.qos = 4'd0;
    if (dir == AOU_AXI_WR) t.fill_wdata(AOU_AXI_STRB_FULL);
    return t;
  endfunction

  // Runs s (items already queued) on the local or remote manager of rp.
  task run(aou_txn_list_seq s, bit remote, int unsigned rp);
    s.start(remote ? p_sequencer.r_mgr_sqr[rp] : p_sequencer.s_mgr_sqr[rp]);
  endtask

  task run_one(bit remote, int unsigned rp, aou_axi_txn t);
    aou_txn_list_seq s = aou_txn_list_seq::type_id::create("one");
    s.items.push_back(t);
    run(s, remote, rp);
  endtask

  // ---------------------------------------------------------------------
  // Registers and pins
  // ---------------------------------------------------------------------
  function uvm_reg_field rpf(string base, int unsigned rp, string field);
    uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("%s_rp%0d", base, rp));
    if (rg == null) `uvm_fatal(get_type_name(), $sformatf("no register %s_rp%0d", base, rp))
    rpf = rg.get_field_by_name(field);
    if (rpf == null) `uvm_fatal(get_type_name(), {"no field ", field, " in ", rg.get_name()})
  endfunction

  function bit pin(string name);
    bit [aou_t1_status::N_INT-1:0] v = env.status.sample();
    for (int unsigned i = 0; i < aou_t1_status::N_INT; i++)
      if (aou_t1_status::int_name(i) == name) return v[i];
    `uvm_fatal(get_type_name(), {"unknown interrupt ", name})
    return 1'b0;
  endfunction

  // The interrupt output follows its status bit within a few core cycles.
  task check_pin(string name, bit exp, string rule, string why = "");
    wait_cycles(4);
    if (pin(name) != exp)
      `uvm_error(get_type_name(), $sformatf("%s: %s is %0b, expected %0b%s", rule, name, !exp,
                                            exp, why == "" ? "" : {" (", why, ")"}))
  endtask

  // AXI_SLV_ID_MISMATCH_ERR_RPn.AXI_SLV_ID_MISMATCH_EN (MAS 7.2.2). Software
  // writes it only while the activation FSM is DISABLED and no AXI traffic
  // is outstanding on that RP.
  task enable_slv_id_check();
    for (int unsigned r = 0; r < cfg.n_rp; r++)
      wr(rpf("axi_slv_id_mismatch_err", r, "axi_slv_id_mismatch_en"), 1);
  endtask

  // ---------------------------------------------------------------------
  // R/B response error debug FIFO (MAS 7.2.4)
  // ---------------------------------------------------------------------
  // Aligned to 4 KB: DEBUG_LOWER_ADDR holds bits [31:7] only (MAS 7.2.4).
  function bit [63:0] dbg_addr(int unsigned rp);
    return DBG_BASE + 64'(rp) * 64'h1000;
  endfunction

  // dbg_len, cut so the burst stays inside the 4 KB window at rp's remote width.
  function int unsigned dbg_len_of(int unsigned rp);
    int unsigned lim = 4096 / cfg.remote_bytes_of(rp) - 1;
    if (lim > 255) lim = 255;
    return dbg_len < lim ? dbg_len : lim;
  endfunction

  // Software enables remote access to RP rp's FIFO at dbg_addr(rp). The
  // window is not memory, so the scoreboard leaves it alone.
  task program_dbg(int unsigned rp);
    bit [63:0] a = dbg_addr(rp);
    aou_core rm = p_sequencer.regs;
    if (a[6:0] != 7'd0)
      `uvm_fatal(get_type_name(), $sformatf(
          "RP%0d debug address %0h is not 128-byte aligned: DEBUG_LOWER_ADDR cannot hold it", rp,
          a))
    write_field(rm.aou_con0.get_field_by_name($sformatf("rp%0d_error_info_access_en", rp)), 1);
    write_field(rpf("axi_error_info0", rp, "debug_upper_addr"), uvm_reg_data_t'(a[63:32]));
    write_field(rpf("axi_error_info1", rp, "debug_lower_addr"), uvm_reg_data_t'(a[31:7]));
    env.sb.add_unchecked(a, a + 64'(cfg.remote_bytes) - 64'd1);
  endtask

  // Runs one debug-window access. The window must answer it however the RP
  // converts or splits it (MAS 7.2.4); a stuck access ends the test with its
  // own ID instead of the phase timeout.
  task run_dbg(aou_txn_list_seq s, int unsigned rp, string what);
    bit done = 1'b0;
    fork
      begin
        run(s, 1'b1, rp);
        done = 1'b1;
      end
    join_none
    for (int unsigned n = 0; !done && n < dbg_wait; n++) wait_cycles(1);
    if (!done) begin
      `uvm_fatal(get_type_name(), $sformatf(
          {"T1-E14: RP%0d debug FIFO %s not answered in %0d cycles ",
           "(%0d-byte remote beat, %0d-byte RP)"},
          rp, what, dbg_wait, cfg.remote_bytes_of(rp), cfg.rp_bytes[rp]))
      // Simulators that finish the time step after $finish would go on to
      // read the missing response.
      wait (done);
    end
  endtask

  // The remote die reads the head entry (ID id_base + rp).
  task fifo_read(int unsigned rp, bit [9:0] id_base = 10'h3F0);
    aou_txn_list_seq s = aou_txn_list_seq::type_id::create("dbg_rd");
    s.items.push_back(mk(1'b1, rp, AOU_AXI_RD, id_base + 10'(rp), dbg_addr(rp), dbg_len_of(rp),
                         dbg_cache));
    run_dbg(s, rp, "read");
  endtask

  // The remote die pops the head entry with a write to the window (ID
  // id_base + rp).
  task fifo_pop(int unsigned rp, bit [9:0] id_base = 10'h3F8);
    aou_txn_list_seq s = aou_txn_list_seq::type_id::create("dbg_pop");
    s.items.push_back(mk(1'b1, rp, AOU_AXI_WR, id_base + 10'(rp), dbg_addr(rp), dbg_len_of(rp),
                         dbg_cache));
    run_dbg(s, rp, "pop");
  endtask

  // Software reads the head, then pops it.
  virtual task fifo_take(int unsigned rp);
    fifo_read(rp);
    fifo_pop(rp);
  endtask
endclass
