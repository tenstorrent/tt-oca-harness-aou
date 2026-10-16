// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// MAS 3.10 RP remapping, on the messages the DUT sends (L3 ap_rx_msg) and the
// requests the remote die sends it (L3 ap_tx_msg).
// FEAT-R09: a request or WriteData the DUT sends carries a configured
// DEST_RP; a ReadData or WriteResp answering a remote request that arrived on
// local RP x carries DEST_RP[x] (paired by ID with the oldest such request).
// FEAT-R10: a CrdtGrant carries credits only in the slots of local RPs (the
// source RP, not DEST_RP).
class aou_dest_rp_chk extends uvm_component;
  `uvm_component_utils(aou_dest_rp_chk)

  uvm_tlm_analysis_fifo #(aou_msg) dut_fifo;   // DUT -> remote
  uvm_tlm_analysis_fifo #(aou_msg) tb_fifo;    // remote -> DUT

  int unsigned local_rp_count = 1;
  bit [1:0]    dest_rp[4] = '{2'd0, 2'd1, 2'd2, 2'd3};

  int unsigned n_axi[4];   // AXI messages per wire RP
  int unsigned n_rsp_ok;
  int unsigned n_grant;

  // Remote requests outstanding at the DUT, per kind (0 write, 1 read), local
  // RP and ID, in order.
  protected int unsigned pend[2][4][bit [9:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dut_fifo = new("dut_fifo", this);
    tb_fifo  = new("tb_fifo", this);
  endfunction

  function bit is_dest(bit [1:0] rp);
    for (int unsigned r = 0; r < local_rp_count; r++) if (dest_rp[r] == rp) return 1'b1;
    return 1'b0;
  endfunction

  function void take_tb(aou_msg t);
    aou_msg_req q;
    int k;
    if (!(t.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ}) || !$cast(q, t)) return;
    k = (t.msg_type == AOU_MT_RREQ) ? 1 : 0;
    if (pend[k][t.rp].exists(q.id)) pend[k][t.rp][q.id]++;
    else pend[k][t.rp][q.id] = 1;
  endfunction

  // A response on wire RP y for ID id: the request it answers arrived on local
  // RP x with DEST_RP[x] == y.
  function void take_rsp(int k, bit [1:0] y, bit [9:0] id, string what);
    int x = -1;
    int other = -1;
    for (int r = 0; r < int'(local_rp_count); r++) begin
      if (!pend[k][r].exists(id) || pend[k][r][id] == 0) continue;
      if (dest_rp[r] == y) x = r;
      else if (other < 0) other = r;
    end
    if (x >= 0) begin
      pend[k][x][id]--;
      n_rsp_ok++;
    end else if (other >= 0) begin
      pend[k][other][id]--;
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R09: %s ID %0h on RP %0d answers a request on local RP %0d, DEST_RP=%0d", what,
          id, y, other, dest_rp[other]))
    end else begin
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R09: %s ID %0h on RP %0d answers no outstanding remote request", what, id, y))
    end
  endfunction

  function void take_dut(aou_msg t);
    aou_msg_crdtgrant g;
    aou_msg_rdata d;
    aou_msg_wresp b;
    if (t.msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ, AOU_MT_WDATA, AOU_MT_WDATAF}) begin
      n_axi[t.rp]++;
      if (!is_dest(t.rp))
        `uvm_error(get_type_name(), $sformatf(
            "FEAT-R09: DUT sent msg_type %0d on RP %0d, DEST_RP of local RPs 0..%0d is %p",
            t.msg_type, t.rp, local_rp_count - 1, dest_rp))
    end else if ($cast(d, t)) begin
      n_axi[t.rp]++;
      if (d.last) take_rsp(1, t.rp, d.id, "ReadData");
    end else if ($cast(b, t)) begin
      n_axi[t.rp]++;
      take_rsp(0, t.rp, b.id, "WriteResp");
    end else if ($cast(g, t)) begin
      n_grant++;
      for (int unsigned r = local_rp_count; r < 4; r++) begin
        for (int c = 0; c < int'(AOU_CC_NUM); c++) begin
          if (g.get_cred(r, aou_cred_class_e'(c)) != 0)
            `uvm_error(get_type_name(), $sformatf(
                "FEAT-R10: CrdtGrant grants credit in slot %0d, local RP_COUNT=%0d: %s", r,
                local_rp_count, g.convert2string()))
        end
      end
    end
  endfunction

  // Requests reach the DUT before it can answer them, so draining the remote
  // side first keeps the pairing in order.
  task run_phase(uvm_phase phase);
    aou_msg m;
    aou_msg q;
    forever begin
      dut_fifo.get(m);
      while (tb_fifo.try_get(q)) take_tb(q);
      take_dut(m);
    end
  endtask

  function void check_phase(uvm_phase phase);
    aou_msg m;
    int unsigned n = 0;
    while (tb_fifo.try_get(m)) take_tb(m);
    while (dut_fifo.try_get(m)) take_dut(m);
    foreach (n_axi[r]) n += n_axi[r];
    if (n == 0) `uvm_error(get_type_name(), "FEAT-R09: the DUT sent no AXI message")
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        "DEST_RP=%p: AXI messages per wire RP %p, %0d responses on the right RP, %0d CrdtGrants",
        dest_rp, n_axi, n_rsp_ok, n_grant), UVM_LOW)
  endfunction
endclass
