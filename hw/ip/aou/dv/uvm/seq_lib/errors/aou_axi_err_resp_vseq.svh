// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI error responses on both sides and the R/B response error debug FIFO
// (plan 9.1, 9.2, 9.13, 9.14; MAS software-operation 7.2.4).
//
// fifo (every RP at once): software enables remote access to each RP's FIFO
// at its own debug address before activation. The remote die's writes and
// reads into local SLVERR/DECERR regions come back with that response
// (scoreboard) and each pushes {ID, ADDR, RESP} per M-port error response
// (one per R beat, so a remote beat wider than the RP pushes once per RP
// beat); the remote die reads the head entry at the debug address and pops
// it with a write there (aou_t1_dbg_fifo_chk checks every read and pop):
//   - one B error, then one R error;
//   - six errors in a row, four pops, one more error: the fifth and sixth
//     (earlier on an RP narrower than the remote die) meet a full FIFO;
//   - a B error and an R error issued 0..7 cycles apart, so some land in the
//     same cycle (two pushes at once).
// resp (every RP, both directions): single and burst writes and reads into
// SLVERR/DECERR regions, bursts that run from one region into the other or
// into OKAY memory; every beat's response must reach the requester unchanged.
// split (plan 15.11, 15.13; run with the limits below under 15): the remote
// die's 16-beat bursts into local memory, which the RP splits, each touching
// 32-byte error regions that fall in one M-port beat and so one sub-burst
// (first, middle or last; two, SLVERR and DECERR, in the fourth). The merged
// BRESP must be the worst of the sub-burst responses and each remote R beat
// the worst of the M-port beats it is built from (AXI4 A3.4.4 and MAS 3.6),
// which is what the scoreboard expects from the error regions.
// Then ordinary traffic must still complete.
// Knobs:
//   +part=all|fifo|resp|split
//   +max_awburstlen=N +max_arburstlen=N  MAX_AxBURSTLEN (AxLEN, 2^n-1)
//                   programmed on every RP before activation; with +part=fifo
//                   debug accesses longer than N+1 RP beats meet the splitter,
//                   which must not cut them.
//   +dbg_len=N|max  AxLEN of every debug-window read and pop (default 0, the
//                   single beat software issues; max: the longest burst inside
//                   the 4 KB window; the window answers any length).
//   +dbg_cache=N    AxCACHE of every debug-window read and pop (default 0).
//   +agg_en=0|1     RPn_AXI_AGGREGATOR_EN on every RP before activation. With
//                   +dbg_cache=2, +dbg_len above 0 and a remote die narrower
//                   than the RP (+remote_bytes), a debug pop is a write the
//                   aggregator would otherwise merge; the window must still
//                   answer it (MAS 3.8.2 condition 4).
//   +err_len=N +err_cache=N +err_off=N  AxLEN, AxCACHE and an address offset
//                   of the fifo part's failing transactions (default 0). With
//                   +agg_en=1, +err_len=1 and a remote die narrower than the
//                   RP, each failing read is one aggregated M-port beat that
//                   pushes one entry per remote beat; +err_off=32 with a
//                   remote die wider than the RP is an unaligned write whose
//                   entry carries the address aligned down to AWSIZE. With
//                   +max_arburstlen below +err_len the failing reads are
//                   split as well: each sub-burst is aggregated on its own.
//   +rdata_crd=N +crd_delay=T +flood=F +flood_len=L +pair_gap=G  the remote
//                   die grants N ReadData credits and returns each T ticks
//                   after use, F OKAY reads of L+1 beats are issued just
//                   ahead of each of the fifo part's B/R error pairs and the
//                   pair's write waits G cycles, so the read's data is
//                   accepted at the M port but backs up behind the flood on
//                   its way to the remote die while the later B flows: the R
//                   entries enter the FIFO after the B although the M port
//                   saw them first (a short flood; a long one holds the
//                   read's data back before the M port). +pair_writes=W
//                   issues W failing writes per pair (W B errors, default 1).
//                   With +err_len=7 and an RP four times the remote die's
//                   width, a failing read is two M-port error beats, each
//                   re-expanded into four entries.
//   +take_overlap=G +take_flood=L  each debug pop is issued G cycles after
//                   the debug read without waiting for the read's data
//                   (default: after it), and an OKAY read of L+1 beats just
//                   ahead of the debug read (default: none): the read's data
//                   queues behind the flood's, the pop completes first and the
//                   read returns the entry the pop removed, sampled when the
//                   read became active.
//   +read_after_pop=1  with +take_overlap: once the pop has completed, a
//                   second debug read with another ID, issued while the first
//                   still waits behind the take_flood read's data. It was
//                   issued after the pop, so it returns the entry behind the
//                   popped one and tells the checker the head, although the
//                   first read, which the pop overlapped, is still in flight.
//                   A section before the pairs pushes a B and an R error
//                   together and a third error well after them, then takes
//                   all three: the second read of the first take shows which
//                   of the pair is left, and that of the second take must not
//                   return the entry its pop removed.
//   +take_pair=1    two takes at once wherever the fifo part takes two or
//                   more entries in a row: two debug reads one cycle apart
//                   (both return the head; the second request is accepted
//                   while the first burst is still being returned), then two
//                   pops one cycle apart (the second's address and data
//                   arrive while the first pop's response may still wait).
//                   +take_wflood=N issues N single-beat OKAY writes on the
//                   RP just ahead of each pair; with few WriteResp credits
//                   (+wresp_crd, +crd_delay) their responses back up behind
//                   the credit, so the first pop's response waits at the
//                   window while the second pop's address and data arrive.
//   +pop_lead=G +wresp_crd=N  each take is an OKAY write on the RP, then the
//                   debug pop and, G cycles after it, the debug read, then a
//                   second debug read once both have completed. The remote
//                   die grants N WriteResp credits and returns each crd_delay
//                   ticks after use: with N = 1 the write's B uses the credit,
//                   so the pop's B waits for its return while the read, which
//                   became active after the pop, completes first with the
//                   entry behind the popped one. The second read, with nothing
//                   in flight, returns the same entry.
class aou_axi_err_resp_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_axi_err_resp_vseq)

  int unsigned n_pairs = 8;
  int unsigned flood = 0;         // fifo part: OKAY reads ahead of each B/R pair
  int unsigned pair_gap = 0;      // fifo part: cycles the pair's write waits
  int unsigned pair_writes = 1;   // fifo part: failing writes per pair
  int unsigned flood_len = 15;    // fifo part: AxLEN of the flood's reads
  int          take_overlap = -1; // fifo part: cycles from debug read to pop (-1: after the data)
  int          take_flood = -1;   // fifo part: AxLEN of an OKAY read before a debug read (-1: none)
  int          pop_lead = -1;     // fifo part: cycles from debug pop to read (-1: read first)
  bit          read_after_pop;    // fifo part: a second debug read once the pop has completed
  bit          take_pair;         // fifo part: two takes at once where two or more are due
  int unsigned take_wflood = 0;   // fifo part: OKAY writes ahead of each take_pair pair
  int unsigned err_len = 0;       // fifo part: AxLEN of the failing transactions
  bit [3:0]    err_cache = 4'd0;  // fifo part: their AxCACHE
  bit [63:0]   err_off = 64'd0;   // fifo part: added to their addresses
  static const int unsigned N_SPLIT = 4;     // split part: bursts per RP and direction
  static const int unsigned SPLIT_LEN = 15;  // their AxLEN

  function new(string name = "aou_axi_err_resp_vseq");
    super.new(name);
  endfunction

  // Error regions, per RP and memory: [b, b+FF] SLVERR, [b+100, b+1FF] DECERR.
  static function bit [63:0] err_base(bit remote_mem, int unsigned rp);
    return (remote_mem ? 64'h0000_0063_0000_0000 : 64'h0000_0062_0000_0000) +
           64'(rp) * 64'h0100_0000;
  endfunction

  // Called by the test before the scoreboard copies the memories.
  static function void add_regions(aou_t1_env_cfg c);
    for (int unsigned r = 0; r < c.n_rp; r++) begin
      for (int m = 0; m < 2; m++) begin
        bit [63:0] b = err_base(m[0], r);
        aou_mem mem = m[0] ? c.remote_cfg.mem : c.local_mem;
        mem.add_error_region(b, b + 64'hFF, AOU_AXI_SLVERR);
        mem.add_error_region(b + 64'h100, b + 64'h1FF, AOU_AXI_DECERR);
      end
      for (int unsigned k = 0; k < N_SPLIT; k++) begin
        int unsigned bb = c.remote_bytes_of(r);
        bit [63:0] p = split_page(r, k);
        if (k != 1) c.local_mem.add_error_region(p + split_err_off(k, bb, 1'b0),
                                                 p + split_err_off(k, bb, 1'b0) + 64'h1F,
                                                 AOU_AXI_SLVERR);
        if (k == 1 || k == 3) c.local_mem.add_error_region(p + split_err_off(k, bb, 1'b1),
                                                           p + split_err_off(k, bb, 1'b1) + 64'h1F,
                                                           AOU_AXI_DECERR);
      end
    end
  endfunction

  // split part: one 4KB page of local memory per burst, after the regions above.
  static function bit [63:0] split_page(int unsigned rp, int unsigned k);
    return err_base(1'b0, rp) + 64'h1_0000 + 64'(k) * 64'h1000;
  endfunction

  // Offset in page k of its 32-byte SLVERR (dec = 0) or DECERR (dec = 1)
  // region, for bb-byte remote beats: page 0 the upper half of beat 0, page 1
  // the top of beat 7, page 2 the last 32 bytes, page 3 SLVERR as in page 0
  // and DECERR at the start of beat 12.
  static function bit [63:0] split_err_off(int unsigned k, int unsigned bb, bit dec);
    case (k)
      0: return 64'h20;
      1: return 64'(bb) * 64'd8 - 64'h20;
      2: return 64'(bb) * 64'(SPLIT_LEN + 32'd1) - 64'h20;
      default: return dec ? 64'(bb) * 64'd12 : 64'h20;
    endcase
  endfunction

  // Splitter limits and aggregator enable from the knobs, if any.
  task program_feat();
    int aw = arg_int("max_awburstlen", -1);
    int ar = arg_int("max_arburstlen", -1);
    int agg = arg_int("agg_en", -1);
    aou_t1_feature_cfg f;
    if (aw < 0 && ar < 0 && agg < 0) return;
    f = aou_t1_feature_cfg::type_id::create("f");
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      f.split_aw[r] = aw;
      f.split_ar[r] = ar;
      f.aggregator[r] = agg;
    end
    program_cfg(f);
  endtask

  task body();
    string part = arg_str("part", "all");
    string dl = arg_str("dbg_len", "0");
    dbg_len = dl == "max" ? 255 : dl.atoi();
    dbg_cache = 4'(arg_int("dbg_cache", 0));
    err_len = arg_int("err_len", 0);
    err_cache = 4'(arg_int("err_cache", 0));
    err_off = 64'(arg_int("err_off", 0));
    flood = arg_int("flood", 0);
    pair_gap = arg_int("pair_gap", 0);
    pair_writes = arg_int("pair_writes", 1);
    take_overlap = arg_int("take_overlap", -1);
    take_flood = arg_int("take_flood", -1);
    pop_lead = arg_int("pop_lead", -1);
    read_after_pop = arg_int("read_after_pop", 0) != 0;
    take_pair = arg_int("take_pair", 0) != 0;
    take_wflood = arg_int("take_wflood", 0);
    if (take_wflood > 16)
      `uvm_fatal(get_type_name(), $sformatf("+take_wflood=%0d: 0 to 16", take_wflood))
    if (pair_writes < 1 || pair_writes > 8)
      `uvm_fatal(get_type_name(), $sformatf("+pair_writes=%0d: 1 to 8", pair_writes))
    flood_len = arg_int("flood_len", 15);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      program_dbg(r);
      `uvm_info(get_type_name(), $sformatf("RP%0d: debug reads and pops of %0d beats", r,
                                           dbg_len_of(r) + 1), UVM_LOW)
    end
    program_feat();
    link_up();
    check_crd_knobs();
    if (arg_int("rdata_crd", -1) >= 0 || arg_int("wresp_crd", -1) >= 0) begin
      if (arg_int("rdata_crd", -1) >= 0) begin
        cfg.l3_cfg.rx_depth[AOU_CC_RDATA] = arg_int("rdata_crd", 0);
        cfg.l3_cfg.ret_policy[AOU_CC_RDATA] = AOU_RET_DELAYED;
      end
      if (arg_int("wresp_crd", -1) >= 0) begin
        cfg.l3_cfg.rx_depth[AOU_CC_WRESP] = arg_int("wresp_crd", 0);
        cfg.l3_cfg.ret_policy[AOU_CC_WRESP] = AOU_RET_DELAYED;
      end
      cfg.l3_cfg.ret_delay = arg_int("crd_delay", 64);
      env.l3.model.crd.reset_link();
    end
    sw_activate();
    if (part inside {"all", "fifo"}) begin
      for (int unsigned r = 0; r < cfg.n_rp; r++) begin
        fork
          automatic int unsigned rr = r;
          fifo_part(rr);
        join_none
      end
      wait fork;
    end
    if (part inside {"all", "resp"}) resp_part();
    if (part == "split") split_part();
    check_traffic(num_txns);
    sw_deactivate();
  endtask

  // +rdata_crd and +wresp_crd size the remote die's receive buffer, so each
  // must hold at least one whole message of its kind. Credits are consumed in
  // full at a message's start (AoU v0.8 flow control), so with fewer the DUT
  // can never send one and every read or write on the RP hangs. A ReadData
  // message is as wide as the remote die's beat on that RP: 8, 14 or 27
  // granules for 256, 512 or 1024 bits; a WriteResp is one granule.
  function void check_crd_knobs();
    int rd = arg_int("rdata_crd", -1);
    int wr = arg_int("wresp_crd", -1);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      int unsigned bb = cfg.remote_bytes_of(r);
      bit [1:0] dl = (bb <= 32) ? 2'd0 : (bb == 64) ? 2'd1 : 2'd2;
      int unsigned need = aou_data_len(AOU_MT_RDATA, dl);
      if (rd >= 0 && rd < int'(need))
        `uvm_fatal(get_type_name(), $sformatf(
            {"+rdata_crd=%0d is less than one ReadData message on RP%0d (%0d granules ",
             "for a %0d-byte remote beat): the DUT could never send read data"},
            rd, r, need, bb))
    end
    if (wr == 0)
      `uvm_fatal(get_type_name(),
                 "+wresp_crd=0 grants no WriteResp credit: the DUT could never send a B")
  endfunction

  // ---------------------------------------------------------------------
  // A failing remote transaction of the fifo part (err_len, err_cache, err_off).
  function aou_axi_txn err(int unsigned rp, aou_axi_dir_e dir, bit [9:0] id, bit [63:0] addr);
    return mk(1'b1, rp, dir, id, addr + err_off, err_len, err_cache);
  endfunction

  task fifo_part(int unsigned rp);
    bit [63:0] b = err_base(1'b0, rp);
    aou_axi_txn e[$];
    `uvm_info(get_type_name(), $sformatf("RP%0d: debug FIFO at %0h", rp, dbg_addr(rp)), UVM_LOW)
    // One of each kind.
    run_one(1'b1, rp, err(rp, AOU_AXI_WR, 10'h011, b + 64'h40));
    fifo_take(rp);
    run_one(1'b1, rp, err(rp, AOU_AXI_RD, 10'h022, b + 64'h140));
    fifo_take(rp);
    // Six errors into a four-entry FIFO, four pops, then one more error.
    for (int unsigned i = 0; i < 7; i++) begin
      bit dec = i[0];
      e.push_back(err(rp, i[1] ? AOU_AXI_RD : AOU_AXI_WR, 10'h100 + 10'(i),
                      b + (dec ? 64'h100 : 64'h0) + (64'(i) * 64'h40) % 64'hC0));
    end
    for (int unsigned i = 0; i < 6; i++) run_one(1'b1, rp, e[i]);
    fifo_takes(rp, 4);
    run_one(1'b1, rp, e[6]);
    fifo_take(rp);
    if (read_after_pop) begin
      // Two errors together (either may enter first), a third well after.
      fork
        run_one(1'b1, rp, err(rp, AOU_AXI_WR, 10'h0A0, b + 64'h40));
        run_one(1'b1, rp, err(rp, AOU_AXI_RD, 10'h0A1, b + 64'h140));
      join
      wait_cycles(64);
      run_one(1'b1, rp, err(rp, AOU_AXI_WR, 10'h0A2, b + 64'h80));
      for (int unsigned i = 0; i < 3; i++) fifo_take(rp);
    end
    // B and R errors close together (behind a flood of read data, if asked).
    for (int unsigned d = 0; d < n_pairs; d++) begin
      if (flood != 0) begin
        aou_txn_list_seq fl = aou_txn_list_seq::type_id::create("flood");
        for (int unsigned i = 0; i < flood; i++)
          fl.items.push_back(mk(1'b1, rp, AOU_AXI_RD, 10'h300 + 10'(i),
                                b + 64'h2_0000 + 64'(i) * 64'h1000, flood_len));
        fork
          run(fl, 1'b1, rp);
        join_none
        wait_cycles(16);
      end
      fork
        begin
          wait_cycles(pair_gap);
          for (int unsigned w = 0; w < pair_writes; w++)
            run_one(1'b1, rp, err(rp, AOU_AXI_WR, 10'h200 + 10'(d) + 10'(w) * 10'h10, b + 64'h80));
        end
        begin
          wait_cycles(d);
          run_one(1'b1, rp, err(rp, AOU_AXI_RD, 10'h280 + 10'(d), b + 64'h180));
        end
      join
      wait fork;  // the flood, before the debug reads queue behind its data
      fifo_takes(rp, pair_writes + 1);
    end
  endtask

  // n takes in a row; with take_pair two at a time.
  task fifo_takes(int unsigned rp, int unsigned n);
    while (n != 0) begin
      if (take_pair && n >= 2) begin
        fifo_take_pair(rp);
        n -= 2;
      end else begin
        fifo_take(rp);
        n--;
      end
    end
  endtask

  // Two reads of the head one cycle apart, then two pops one cycle apart, all
  // without waiting for the earlier one's response (legal AXI: different IDs).
  task fifo_take_pair(int unsigned rp);
    if (take_wflood != 0) begin
      aou_txn_list_seq fl = aou_txn_list_seq::type_id::create("take_wflood");
      for (int unsigned i = 0; i < take_wflood; i++)
        fl.items.push_back(mk(1'b1, rp, AOU_AXI_WR, 10'h340 + 10'(i),
                              err_base(1'b0, rp) + 64'h4_0000 + 64'(i) * 64'h40));
      fork
        run(fl, 1'b1, rp);
      join_none
      wait_cycles(16);
    end
    fork
      fifo_read(rp);
      begin
        wait_cycles(1);
        fifo_read(rp, 10'h3D0);
      end
    join
    fork
      fifo_pop(rp);
      begin
        wait_cycles(1);
        fifo_pop(rp, 10'h3D8);
      end
    join
    wait fork;  // the write flood
  endtask

  // With take_overlap at or above 0 the pop is issued that many cycles after
  // the debug read without waiting for the read's data: the window has
  // sampled the head for the read by then. A take_flood read just ahead
  // holds the debug read's data back behind its own while the pop's B flows,
  // so the pop completes first. With read_after_pop a second debug read
  // follows the pop's B while the first may still be in flight.
  virtual task fifo_take(int unsigned rp);
    if (pop_lead >= 0) begin
      pop_then_read(rp);
      return;
    end
    if (take_overlap < 0) begin
      super.fifo_take(rp);
      return;
    end
    if (take_flood >= 0) begin
      aou_txn_list_seq fl = aou_txn_list_seq::type_id::create("take_flood");
      fl.items.push_back(mk(1'b1, rp, AOU_AXI_RD, 10'h3E0 + 10'(rp),
                            err_base(1'b0, rp) + 64'h3_0000, take_flood));
      fork
        run(fl, 1'b1, rp);
      join_none
      wait_cycles(2);
    end
    fork
      fifo_read(rp);
      begin
        wait_cycles(take_overlap);
        fifo_pop(rp);
        if (read_after_pop) fifo_read(rp, 10'h3D0);
      end
    join
    wait fork;
  endtask

  // The pop first, the read pop_lead cycles later, behind an OKAY write
  // whose B holds the WriteResp credit (+wresp_crd=1): the pop takes the head
  // before the read becomes active, and its B completes after the read's
  // data. Then the head is read again with nothing in flight.
  task pop_then_read(int unsigned rp);
    run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_WR, 10'h3E8 + 10'(rp),
                         err_base(1'b0, rp) + 64'h3_0000));
    fork
      fifo_pop(rp);
      begin
        wait_cycles(pop_lead);
        fifo_read(rp);
      end
    join
    fifo_read(rp);
  endtask

  // ---------------------------------------------------------------------
  task resp_part();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      for (int m = 0; m < 2; m++) begin
        fork
          automatic int unsigned rr = r;
          automatic bit remote = m[0];
          resp_one(remote, rr);
        join_none
      end
    end
    wait fork;
  endtask

  // remote = 1: the remote die into local memory; 0: a local manager into
  // remote memory. Writes first, then reads of the same bytes.
  task resp_one(bit remote, int unsigned rp);
    bit [63:0] b = err_base(!remote, rp);
    aou_txn_list_seq w = aou_txn_list_seq::type_id::create("err_wr");
    aou_txn_list_seq rd = aou_txn_list_seq::type_id::create("err_rd");
    // The writes run concurrently with different IDs, so they must not share
    // writable bytes: four 128-byte beats from b+100 would reach the OKAY
    // bytes the next write puts at b+200.
    int unsigned dec_len = ((remote ? cfg.remote_bytes : cfg.rp_bytes[rp]) > 64) ? 1 : 3;
    w.items.push_back(mk(remote, rp, AOU_AXI_WR, 10'h031, b + 64'h00));          // SLVERR
    w.items.push_back(mk(remote, rp, AOU_AXI_WR, 10'h032, b + 64'h100, dec_len)); // DECERR
    w.items.push_back(mk(remote, rp, AOU_AXI_WR, 10'h033, b + 64'h1C0, 3));      // DEC, OKAY
    w.items.push_back(mk(remote, rp, AOU_AXI_WR, 10'h034, b + 64'hC0, 1));       // SLVERR, DECERR
    run(w, remote, rp);
    rd.items.push_back(mk(remote, rp, AOU_AXI_RD, 10'h041, b + 64'h40));         // SLVERR
    rd.items.push_back(mk(remote, rp, AOU_AXI_RD, 10'h042, b + 64'hC0, 3));      // SLV, DEC x3
    rd.items.push_back(mk(remote, rp, AOU_AXI_RD, 10'h043, b + 64'h1C0, 3));     // DEC, OKAY x3
    rd.items.push_back(mk(remote, rp, AOU_AXI_RD, 10'h044, b + 64'h180));        // DECERR
    run(rd, remote, rp);
  endtask

  // ---------------------------------------------------------------------
  task split_part();
    int aw = arg_int("max_awburstlen", -1);
    int ar = arg_int("max_arburstlen", -1);
    if (aw < 0 || ar < 0 || aw >= int'(SPLIT_LEN) || ar >= int'(SPLIT_LEN) ||
        !aou_reg_burstlen_cb::is_legal(uvm_reg_data_t'(aw)) ||
        !aou_reg_burstlen_cb::is_legal(uvm_reg_data_t'(ar)))
      `uvm_fatal(get_type_name(), $sformatf(
          "+part=split needs legal +max_awburstlen and +max_arburstlen below %0d (got %0d, %0d)",
          SPLIT_LEN, aw, ar))
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      fork
        automatic int unsigned rr = r;
        split_one(rr);
      join_none
    end
    wait fork;
  endtask

  task split_one(int unsigned rp);
    aou_txn_list_seq w = aou_txn_list_seq::type_id::create("split_wr");
    aou_txn_list_seq rd = aou_txn_list_seq::type_id::create("split_rd");
    for (int unsigned k = 0; k < N_SPLIT; k++)
      w.items.push_back(mk(1'b1, rp, AOU_AXI_WR, 10'h050 + 10'(k), split_page(rp, k), SPLIT_LEN));
    run(w, 1'b1, rp);
    for (int unsigned k = 0; k < N_SPLIT; k++)
      rd.items.push_back(mk(1'b1, rp, AOU_AXI_RD, 10'h058 + 10'(k), split_page(rp, k), SPLIT_LEN));
    run(rd, 1'b1, rp);
    foreach (w.done_q[i])
      `uvm_info(get_type_name(), $sformatf("RP%0d split write %0h: BRESP %0d", rp,
                                           w.done_q[i].addr, w.done_q[i].bresp), UVM_LOW)
    foreach (rd.done_q[i])
      `uvm_info(get_type_name(), $sformatf("RP%0d split read %0h: RRESP %p", rp,
                                           rd.done_q[i].addr, rd.done_q[i].rresp), UVM_LOW)
  endtask
endclass
