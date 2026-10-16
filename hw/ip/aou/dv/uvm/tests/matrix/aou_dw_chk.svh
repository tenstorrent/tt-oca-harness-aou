// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Data width conversion (plan 2.14, MAS 3.3 and 3.5) beyond the scoreboard's
// byte checks, per RP (identity DEST_RP: wire RP = local RP).
// DP-R02: an S-port read beat whose ReadData is narrower than the RP (DLENGTH
//   from ARSIZE) carries that ReadData replicated across the bus (MAS 3.3).
// DP-R03: WriteData the DUT sends carries the DLENGTH of its RP's AXI data
//   width (MAS 3.5.2: DLEN gives the original data width).
// DP-R04: the run produced the conversions it targets, per RP: remote writes
//   at the remote width, remote reads with ARSIZE at the remote width,
//   single- and multi-beat writes at the M port, and (RP wider than 256 bits)
//   narrow S-port reads; otherwise the test proves nothing.
class aou_dw_chk extends uvm_component;
  `uvm_component_utils(aou_dw_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) loc_fifo;   // S-port managers
  uvm_tlm_analysis_fifo #(aou_axi_txn) sub_fifo;   // M-port subordinates
  uvm_tlm_analysis_fifo #(aou_msg)     dut_fifo;   // DUT -> remote die
  uvm_tlm_analysis_fifo #(aou_msg)     tb_fifo;    // remote die -> DUT

  int unsigned n_rp = 1;
  int unsigned rp_bytes[4] = '{default: 64};
  int unsigned remote_bytes[4] = '{default: 64};
  bit          req_r2l = 1'b1;
  bit          req_l2r = 1'b1;

  int unsigned n_rem_wdata[4][3];   // remote WriteData per DLENGTH
  int unsigned n_rem_rreq[4][3];    // remote ReadReq per ReadData DLENGTH (ARSIZE)
  int unsigned n_dut_wdata[4];
  int unsigned n_m_single[4];       // M-port writes of one beat
  int unsigned n_m_multi[4];
  int unsigned n_narrow_rd[4];      // S-port read beats checked for replication

  function new(string name, uvm_component parent);
    super.new(name, parent);
    loc_fifo = new("loc_fifo", this);
    sub_fifo = new("sub_fifo", this);
    dut_fifo = new("dut_fifo", this);
    tb_fifo  = new("tb_fifo", this);
  endfunction

  static function int unsigned dl_idx(int unsigned bytes);
    return (bytes <= 32) ? 0 : (bytes == 64) ? 1 : 2;
  endfunction

  function void take_loc(aou_axi_txn t);
    int unsigned dlb;
    if (t.dir != AOU_AXI_RD || t.aborted || t.rp > 3) return;
    dlb = aou_dl_bits(aou_dl_for_size(t.size)) / 8;
    if (dlb >= t.data_bytes) return;
    foreach (t.data[i]) begin
      if (t.rresp[i] != 2'b00) continue;
      n_narrow_rd[t.rp]++;
      for (int unsigned b = dlb; b < t.data_bytes; b++) begin
        if (t.data[i][8*b +: 8] != t.data[i][8*(b % dlb) +: 8]) begin
          `uvm_error(get_type_name(), $sformatf(
                     {"DP-R02: RP%0d read beat %0d (ARSIZE %0d, ReadData%0d on a %0d-bit bus): ",
                      "byte lane %0d is %02h, its ReadData lane %0d is %02h: %s"}, t.rp, i, t.size,
                     8 * dlb, 8 * t.data_bytes, b, t.data[i][8*b +: 8], b % dlb,
                     t.data[i][8*(b % dlb) +: 8], t.convert2string()))
          break;
        end
      end
    end
  endfunction

  function void take_sub(aou_axi_txn t);
    if (t.dir != AOU_AXI_WR || t.rp > 3) return;
    if (t.len == 0) n_m_single[t.rp]++;
    else n_m_multi[t.rp]++;
  endfunction

  function void take_dut(aou_msg m);
    aou_msg_wdata w;
    if (!(m.msg_type inside {AOU_MT_WDATA, AOU_MT_WDATAF}) || !$cast(w, m)) return;
    n_dut_wdata[m.rp]++;
    if (32'(m.rp) < n_rp && aou_dl_bits(w.dlength) != 8 * rp_bytes[m.rp])
      `uvm_error(get_type_name(), $sformatf(
                 "DP-R03: DUT WriteData on RP%0d has DLENGTH %0d bits, the RP is %0d bits", m.rp,
                 aou_dl_bits(w.dlength), 8 * rp_bytes[m.rp]))
  endfunction

  function void take_tb(aou_msg m);
    aou_msg_wdata w;
    aou_msg_rreq q;
    if ($cast(w, m) && m.msg_type inside {AOU_MT_WDATA, AOU_MT_WDATAF})
      n_rem_wdata[m.rp][dl_idx(aou_dl_bits(w.dlength) / 8)]++;
    else if ($cast(q, m) && m.msg_type == AOU_MT_RREQ)
      n_rem_rreq[m.rp][dl_idx(aou_dl_bits(aou_dl_for_size(q.size)) / 8)]++;
  endfunction

  function void flush();
    aou_axi_txn t;
    aou_msg m;
    while (loc_fifo.try_get(t)) take_loc(t);
    while (sub_fifo.try_get(t)) take_sub(t);
    while (dut_fifo.try_get(m)) take_dut(m);
    while (tb_fifo.try_get(m)) take_tb(m);
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_txn t;
    aou_axi_txn u;
    aou_msg m;
    aou_msg q;
    fork
      forever begin loc_fifo.get(t); take_loc(t); end
      forever begin sub_fifo.get(u); take_sub(u); end
      forever begin dut_fifo.get(m); take_dut(m); end
      forever begin tb_fifo.get(q); take_tb(q); end
    join
  endtask

  function void need(bit ok, int unsigned r, string what);
    if (!ok)
      `uvm_error(get_type_name(), $sformatf(
                 "DP-R04: RP%0d (%0d-bit, remote %0d-bit): no %s", r, 8 * rp_bytes[r],
                 8 * remote_bytes[r], what))
  endfunction

  function void check_phase(uvm_phase phase);
    flush();
    for (int unsigned r = 0; r < n_rp; r++) begin
      int unsigned d = dl_idx(remote_bytes[r]);
      if (req_r2l) begin
        need(n_rem_wdata[r][d] > 0, r, "remote WriteData at the remote width");
        need(n_rem_rreq[r][d] > 0, r, "remote ReadReq with ARSIZE at the remote width");
        need(n_m_single[r] > 0, r, "single-beat write at the M port");
        need(n_m_multi[r] > 0, r, "multi-beat write at the M port");
      end
      if (req_l2r) begin
        need(n_dut_wdata[r] > 0, r, "WriteData from the DUT");
        if (rp_bytes[r] > 32) need(n_narrow_rd[r] > 0, r, "narrow S-port read");
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    for (int unsigned r = 0; r < n_rp; r++)
      `uvm_info(get_type_name(), $sformatf(
                {"RP%0d %0d-bit, remote %0d-bit: remote WriteData by DLENGTH 256/512/1024 %p, ",
                 "remote ReadReq by ReadData width %p, M-port writes single/multi %0d/%0d, DUT ",
                 "WriteData %0d, narrow S-port read beats %0d"}, r, 8 * rp_bytes[r],
                8 * remote_bytes[r], n_rem_wdata[r], n_rem_rreq[r], n_m_single[r], n_m_multi[r],
                n_dut_wdata[r], n_narrow_rd[r]), UVM_LOW)
  endfunction
endclass
