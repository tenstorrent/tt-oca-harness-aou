// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Multi-RP accounting, arbitration and independence (plan 2.12), on the local
// managers' and remote managers' completed transactions and the messages L3
// decodes from the DUT (identity DEST_RP: wire RP = local RP).
// T1-M01: per RP, the DUT sends one WriteReq/ReadReq per S-port transaction of
//   that RP and one WriteResp / last ReadData per remote-die transaction of
//   that RP; an RP the scenario left idle carries no AXI message.
// T1-M02: in an arbitration window (every busy RP backlogged), by the time the
//   first RP has sent all of its requests every other busy RP has sent at
//   least min_share_pct of its own (round-robin, MAS 3.2.1: no RP starves).
// T1-M03: in an independence window, every busy RP other than slow_rp
//   completes all of its transactions while slow_rp still has some to finish.
class aou_mrp_chk extends uvm_component;
  `uvm_component_utils(aou_mrp_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) loc_fifo;   // S-port managers
  uvm_tlm_analysis_fifo #(aou_axi_txn) rem_fifo;   // remote-die managers
  uvm_tlm_analysis_fifo #(aou_msg)     dut_fifo;   // DUT -> remote die

  int unsigned min_share_pct = 25;
  int          slow_rp = -1;

  // Per-RP statistics (plan 12.19), whole test.
  int unsigned n_loc[4];       // S-port transactions completed
  int unsigned n_rem[4];       // remote-die transactions completed
  int unsigned n_req[4];       // WriteReq + ReadReq the DUT sent
  int unsigned n_rsp[4];       // WriteResp + last ReadData the DUT sent
  int unsigned n_wdata[4];     // WriteData(Full) the DUT sent
  int unsigned n_rdata[4];     // ReadData beats the DUT sent

  // Window state
  protected bit          arb_open;
  protected bit          ind_open;
  protected int unsigned arb_seq[$];         // wire RP of each DUT request in the window
  protected time         ind_last[4];        // last completion per RP in the window
  protected int unsigned ind_n[4];
  protected int unsigned n_arb_windows;
  protected int unsigned n_ind_windows;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    loc_fifo = new("loc_fifo", this);
    rem_fifo = new("rem_fifo", this);
    dut_fifo = new("dut_fifo", this);
  endfunction

  function void take_txn(aou_axi_txn t, bit loc);
    if (t.aborted || t.rp > 3) return;
    if (loc) n_loc[t.rp]++;
    else n_rem[t.rp]++;
    if (ind_open) begin
      ind_n[t.rp]++;
      if (t.t_done > ind_last[t.rp]) ind_last[t.rp] = t.t_done;
    end
  endfunction

  function void take_msg(aou_msg m);
    aou_msg_rdata d;
    case (m.msg_type)
      AOU_MT_WREQ, AOU_MT_RREQ: begin
        n_req[m.rp]++;
        if (arb_open) arb_seq.push_back(32'(m.rp));
      end
      AOU_MT_WDATA, AOU_MT_WDATAF: n_wdata[m.rp]++;
      AOU_MT_WRESP: n_rsp[m.rp]++;
      AOU_MT_RDATA: begin
        n_rdata[m.rp]++;
        if ($cast(d, m) && d.last) n_rsp[m.rp]++;
      end
      default: ;
    endcase
  endfunction

  function void flush();
    aou_axi_txn t;
    aou_msg m;
    while (loc_fifo.try_get(t)) take_txn(t, 1'b1);
    while (rem_fifo.try_get(t)) take_txn(t, 1'b0);
    while (dut_fifo.try_get(m)) take_msg(m);
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_txn t;
    aou_axi_txn u;
    aou_msg m;
    fork
      forever begin loc_fifo.get(t); take_txn(t, 1'b1); end
      forever begin rem_fifo.get(u); take_txn(u, 1'b0); end
      forever begin dut_fifo.get(m); take_msg(m); end
    join
  endtask

  function void arb_start();
    flush();
    arb_seq.delete();
    arb_open = 1'b1;
  endfunction

  function void arb_stop();
    int unsigned total[4];
    int unsigned cnt[4];
    int          first = -1;
    int unsigned k;
    flush();
    arb_open = 1'b0;
    n_arb_windows++;
    foreach (arb_seq[i]) total[arb_seq[i]]++;
    for (k = 0; k < arb_seq.size(); k++) begin
      cnt[arb_seq[k]]++;
      if (cnt[arb_seq[k]] == total[arb_seq[k]]) begin
        first = int'(arb_seq[k]);
        break;
      end
    end
    `uvm_info(get_type_name(), $sformatf(
              "arbitration window: requests per RP %p; when RP%0d sent its last, others had %p",
              total, first, cnt), UVM_LOW)
    if (first < 0) begin
      `uvm_error(get_type_name(), "T1-M02: no DUT request in the arbitration window")
      return;
    end
    for (int r = 0; r < 4; r++) begin
      if (r == first || total[r] == 0) continue;
      if (cnt[r] * 100 < total[r] * min_share_pct)
        `uvm_error(get_type_name(), $sformatf(
                   {"T1-M02: RP%0d had sent %0d of its %0d requests when RP%0d had sent all ",
                    "%0d (needs %0d%%)"}, r, cnt[r], total[r], first, total[first],
                   min_share_pct))
    end
  endfunction

  function void ind_start(int unsigned slow);
    flush();
    slow_rp = int'(slow);
    foreach (ind_last[r]) begin
      ind_last[r] = 0;
      ind_n[r] = 0;
    end
    ind_open = 1'b1;
  endfunction

  function void ind_stop();
    flush();
    ind_open = 1'b0;
    n_ind_windows++;
    `uvm_info(get_type_name(), $sformatf(
              "independence window, slow RP%0d: completions per RP %p, last at %p", slow_rp,
              ind_n, ind_last), UVM_LOW)
    if (ind_n[slow_rp] == 0) begin
      `uvm_error(get_type_name(), $sformatf("T1-M03: slow RP%0d completed nothing", slow_rp))
      return;
    end
    for (int r = 0; r < 4; r++) begin
      if (r == slow_rp || ind_n[r] == 0) continue;
      if (ind_last[r] >= ind_last[slow_rp])
        `uvm_error(get_type_name(), $sformatf(
                   "T1-M03: RP%0d finished at %0t, not before slowed RP%0d (%0t)", r,
                   ind_last[r], slow_rp, ind_last[slow_rp]))
    end
  endfunction

  function void check_phase(uvm_phase phase);
    flush();
    for (int r = 0; r < 4; r++) begin
      if (n_req[r] != n_loc[r])
        `uvm_error(get_type_name(), $sformatf(
                   "T1-M01: RP%0d: DUT sent %0d requests for %0d S-port transactions", r,
                   n_req[r], n_loc[r]))
      if (n_rsp[r] != n_rem[r])
        `uvm_error(get_type_name(), $sformatf(
                   "T1-M01: RP%0d: DUT sent %0d responses for %0d remote-die transactions", r,
                   n_rsp[r], n_rem[r]))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    for (int r = 0; r < 4; r++)
      `uvm_info(get_type_name(), $sformatf(
                {"RP%0d statistics: S-port txns %0d, remote txns %0d; DUT sent %0d requests, ",
                 "%0d WriteData, %0d ReadData, %0d responses"}, r, n_loc[r], n_rem[r], n_req[r],
                n_wdata[r], n_rdata[r], n_rsp[r]), UVM_LOW)
  endfunction
endclass
