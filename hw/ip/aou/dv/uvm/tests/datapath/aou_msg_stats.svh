// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Message placement statistics in both directions (L3 ap_rx_msg: sent by the
// DUT; ap_tx_msg: sent to the DUT). A packing test names the layouts it aims for
// (req_*); report_phase lists those that never occurred. That is stimulus
// quality, not a DUT check: a missed layout is a coverage hole, never an error.
// The aou_l3_cov groups count them: WriteResp sharing a flit in
// l3.cg_wresp_flit, flit-spanning messages in l3.cg_span, message sizes in
// granules in l3.cg_flit_layout (cp_size) and, by kind and direction, l3.cg_msg.
// On the DUT TX side the layout is the DUT's own packing choice, which AoU
// leaves open (granules may go empty; a message may, not must, span flits).
class aou_msg_stats extends uvm_component;
  `uvm_component_utils(aou_msg_stats)

  uvm_tlm_analysis_fifo #(aou_msg) dut_fifo;   // DUT -> model
  uvm_tlm_analysis_fifo #(aou_msg) tb_fifo;    // model -> DUT

  // Targets, per direction index 0 = DUT TX, 1 = DUT RX.
  int unsigned req_wresp_per_flit[2] = '{0, 0};  // some flit carries at least this many WriteResp
  int unsigned req_span[2] = '{0, 0};            // at least this many messages span flits
  int unsigned req_granules[2][$];      // message sizes (granules) aimed for

  int unsigned max_wresp_in_flit[2];
  int unsigned n_span[2];
  int unsigned n_msgs[2];
  protected int unsigned wresp_in_flit[2][int];
  protected int unsigned by_granules[2][int unsigned];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dut_fifo = new("dut_fifo", this);
    tb_fifo  = new("tb_fifo", this);
  endfunction

  function void take(aou_msg m, int d);
    int unsigned g = m.num_granules();
    n_msgs[d]++;
    if (by_granules[d].exists(g)) by_granules[d][g]++;
    else by_granules[d][g] = 1;
    if (m.span_flits > 1) n_span[d]++;
    if (m.msg_type == AOU_MT_WRESP && m.start_flit >= 0) begin
      if (wresp_in_flit[d].exists(m.start_flit)) wresp_in_flit[d][m.start_flit]++;
      else wresp_in_flit[d][m.start_flit] = 1;
      if (wresp_in_flit[d][m.start_flit] > max_wresp_in_flit[d])
        max_wresp_in_flit[d] = wresp_in_flit[d][m.start_flit];
    end
  endfunction

  task run_phase(uvm_phase phase);
    aou_msg m;
    fork
      forever begin dut_fifo.get(m); take(m, 0); end
      forever begin tb_fifo.get(m); take(m, 1); end
    join
  endtask

  function string dname(int d);
    return d == 0 ? "DUT TX" : "DUT RX";
  endfunction

  function void check_phase(uvm_phase phase);
    aou_msg m;
    while (dut_fifo.try_get(m)) take(m, 0);
    while (tb_fifo.try_get(m)) take(m, 1);
  endfunction

  function void report_phase(uvm_phase phase);
    for (int d = 0; d < 2; d++) begin
      if (max_wresp_in_flit[d] < req_wresp_per_flit[d])
        `uvm_info(get_type_name(), $sformatf(
            "not reached: %s: at most %0d WriteResp shared a flit, scenario aims for %0d",
            dname(d), max_wresp_in_flit[d], req_wresp_per_flit[d]), UVM_LOW)
      if (n_span[d] < req_span[d])
        `uvm_info(get_type_name(), $sformatf(
            "not reached: %s: %0d messages spanned flits, scenario aims for %0d", dname(d),
            n_span[d], req_span[d]), UVM_LOW)
      foreach (req_granules[d][i])
        if (!by_granules[d].exists(req_granules[d][i]))
          `uvm_info(get_type_name(), $sformatf(
              "not reached: %s: no %0d-granule message, scenario aims for one", dname(d),
              req_granules[d][i]), UVM_LOW)
    end
    for (int d = 0; d < 2; d++)
      `uvm_info(get_type_name(), $sformatf(
          "%s: %0d msgs, %0d spanning, max %0d WriteResp/flit, by granules %p", dname(d),
          n_msgs[d], n_span[d], max_wresp_in_flit[d], by_granules[d]), UVM_LOW)
  endfunction
endclass
