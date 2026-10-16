// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI error responses on both sides and the R/B response error debug FIFO
// (plan 9.1, 9.2, 9.13, 9.14; MAS software-operation 7.2.4).
//
// fifo (every RP at once): software enables remote access to each RP's FIFO
// at its own debug address before activation. The remote die's writes and
// reads into local SLVERR/DECERR regions come back with that response
// (scoreboard) and each pushes {ID, ADDR, RESP}; the remote die reads the
// head entry at the debug address and pops it with a write there
// (aou_t1_dbg_fifo_chk checks every read and pop):
//   - one B error, then one R error;
//   - six errors in a row, four pops, one more error: the fifth and sixth
//     meet a full FIFO;
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
//                   debug accesses longer than N+1 RP beats meet the splitter
//                   (BUGS/043).
//   +dbg_len=N|max  AxLEN of every debug-window read and pop (default 0, one
//                   beat; max: the longest burst inside the 4 KB window).
class aou_axi_err_resp_vseq extends aou_err_base_vseq;
  `uvm_object_utils(aou_axi_err_resp_vseq)

  int unsigned n_pairs = 8;
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

  task program_split();
    int aw = arg_int("max_awburstlen", -1);
    int ar = arg_int("max_arburstlen", -1);
    aou_t1_feature_cfg f;
    if (aw < 0 && ar < 0) return;
    f = aou_t1_feature_cfg::type_id::create("f");
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      f.split_aw[r] = aw;
      f.split_ar[r] = ar;
    end
    program_cfg(f);
  endtask

  task body();
    string part = arg_str("part", "all");
    string dl = arg_str("dbg_len", "0");
    dbg_len = dl == "max" ? 255 : dl.atoi();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      program_dbg(r);
      `uvm_info(get_type_name(), $sformatf("RP%0d: debug reads and pops of %0d beats", r,
                                           dbg_len_of(r) + 1), UVM_LOW)
    end
    program_split();
    link_up();
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

  // ---------------------------------------------------------------------
  task fifo_part(int unsigned rp);
    bit [63:0] b = err_base(1'b0, rp);
    aou_axi_txn e[$];
    `uvm_info(get_type_name(), $sformatf("RP%0d: debug FIFO at %0h", rp, dbg_addr(rp)), UVM_LOW)
    // One of each kind.
    run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_WR, 10'h011, b + 64'h40));
    fifo_take(rp);
    run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_RD, 10'h022, b + 64'h140));
    fifo_take(rp);
    // Six errors into a four-entry FIFO, four pops, then one more error.
    for (int unsigned i = 0; i < 7; i++) begin
      bit dec = i[0];
      e.push_back(mk(1'b1, rp, i[1] ? AOU_AXI_RD : AOU_AXI_WR, 10'h100 + 10'(i),
                     b + (dec ? 64'h100 : 64'h0) + (64'(i) * 64'h40) % 64'hC0));
    end
    for (int unsigned i = 0; i < 6; i++) run_one(1'b1, rp, e[i]);
    for (int unsigned i = 0; i < 4; i++) fifo_take(rp);
    run_one(1'b1, rp, e[6]);
    fifo_take(rp);
    // B and R errors close together.
    for (int unsigned d = 0; d < n_pairs; d++) begin
      fork
        run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_WR, 10'h200 + 10'(d), b + 64'h80));
        begin
          wait_cycles(d);
          run_one(1'b1, rp, mk(1'b1, rp, AOU_AXI_RD, 10'h280 + 10'(d), b + 64'h180));
        end
      join
      fifo_take(rp);
      fifo_take(rp);
    end
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
