// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// TX_LP_MODE switched on at the edge where the lower half of a flit's first
// chunk goes out on a half-width FDI path (BUGS/034; MAS software-operation
// 7.1 "Low Power mode": once a flit is started it always finishes). On
// SP_32B, and on PHY0 of the two-PHY builds, a 64- or 128-byte packing chunk
// leaves as two FDI beats, so the DUT has to keep the flit going between
// them even when the write makes it idle, and must not let a new message into
// that chunk.
//
// Each step, with pl_trdy high on every cycle the Adapter allows it:
//   1. TX_LP_MODE=0, so the DUT sends empty flits back to back;
//   2. pl_trdy is held low at a flit boundary, so the DUT waits on beat 0
//      (chunk 0, lower half) of an empty flit;
//   3. a local write to remote memory is started; it waits in the DUT behind
//      the held TX, ready to enter the very next chunk;
//   4. an APB read ends on a pclk edge, then TX_LP_MODE=1 with threshold 0 is
//      written while pl_trdy returns `off` core cycles later, so beat 0
//      transfers on one fixed edge relative to the register write;
//   5. the write must complete and the link must drain.
// `off` sweeps a range that holds the edge where the register takes effect,
// so one step makes LP mode engage on exactly the beat-0 edge with the
// write's message waiting for the next cycle. Any bubble inside the flit is
// FDI-R02; a message that enters the half-sent chunk corrupts the flit (L3
// and AOU_FDI_CHECKER), or the write is lost (T1-V06) or wrong (scoreboard).
// The sweep stops at the first error.
// Knobs: +align_min=N +align_max=N (core cycles, default 0..63).
class aou_lp_mode_align_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_lp_mode_align_vseq)

  static const bit [63:0] WR_BASE = 64'h0000_0001_0002_0000;

  function new(string name = "aou_lp_mode_align_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned lo = arg_int("align_min", 0);
    int unsigned hi = arg_int("align_max", 63);
    uvm_report_server srv = uvm_report_server::get_server();
    int unsigned n_err = srv.get_severity_count(UVM_ERROR);
    int unsigned n = 0;
    link_up();
    sw_activate();
    check_traffic(num_txns);
    drain();
    for (int unsigned off = lo; off <= hi; off++) begin
      step(off, n++);
      if (srv.get_severity_count(UVM_ERROR) != n_err) begin
        `uvm_info(get_type_name(), $sformatf("stopping the sweep at offset %0d after an error",
                                             off), UVM_LOW)
        break;
      end
    end
    `uvm_info(get_type_name(), $sformatf("%0d alignment steps (offsets %0d..%0d)", n, lo, hi),
              UVM_LOW)
    lp_mode(1'b0, 0);
    check_traffic(num_txns);
    sw_deactivate();
  endtask

  task step(int unsigned off, int unsigned idx);
    aou_txn_list_seq w = aou_txn_list_seq::type_id::create("parked");
    uvm_reg_data_t v;
    lp_mode(1'b0, 0);
    wait_cycles(64);
    hold_tx();
    w.items.push_back(wr_txn(idx));
    fork
      w.start(p_sequencer.s_mgr_sqr[0]);
    join_none
    wait_cycles(64);
    rd(p_sequencer.regs.aou_con0.tx_lp_mode, v);
    fork
      lp_mode(1'b1, 0);
      begin
        wait_cycles(off);
        release_tx();
      end
    join
    drain(5000);
  endtask

  // One full-width write of RP0 to remote memory, a new address each step.
  function aou_axi_txn wr_txn(int unsigned idx);
    aou_axi_txn t = aou_axi_txn::type_id::create("t");
    t.data_bytes = cfg.rp_bytes[0];
    t.rp = 0;
    t.local_side = 1'b1;
    t.dir = AOU_AXI_WR;
    t.id = 10'(idx % 8);
    t.addr = WR_BASE + 64'(idx) * 64'h100;
    t.len = 8'd0;
    t.size = 3'($clog2(t.data_bytes));
    t.burst = AOU_AXI_INCR;
    t.lock = 1'b0;
    t.cache = 4'd0;
    t.prot = 3'd0;
    t.qos = 4'd0;
    t.fill_wdata(AOU_AXI_STRB_FULL);
    return t;
  endfunction
endclass
