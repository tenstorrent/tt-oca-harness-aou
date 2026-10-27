// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// T1-E20: while an M-port ID mismatch is reported and not yet cleared, the DUT
// sends no credited message (WriteReq, WriteData, ReadReq, ReadData,
// WriteResp). MAS software-operation 7.2.2 describes the detection (ERROR_INFO_RPn
// SPLIT_BID/RID_MISMATCH_ERR, INT_MI0_ID_MISMATCH, write-1 clear) but not this
// containment; the expectation is taken from the RTL, where the owners block
// credited TX traffic until software clears the error (PR #26).
//
// The checker knows the error is set from what software can see: the
// INT_MI0_ID_MISMATCH pin rising, or an APB read of ERROR_INFO_RPn returning a
// mismatch bit set. A write of 1 to the bit (the clear) ends it; a reset ends
// everything. The pin is the OR of every RP's errors, so if it is still high
// rearm_cycles after a clear, another RP's error remains and the hold resumes.
// With the interrupt masked the pin stays low and only a read reveals the error. Messages already on their way when the block began may still
// leave: up to slack_granules of credited messages (a few flits of TX
// pipeline) after the block is known, nothing after that.
`uvm_analysis_imp_decl(_apb)

class aou_t1_crd_block_chk extends uvm_component;
  `uvm_component_utils(aou_t1_crd_block_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_crd_block_chk) rx_msg_imp;
  uvm_analysis_imp_apb #(aou_apb_item, aou_t1_crd_block_chk) apb_imp;

  aou_core           rm;
  aou_t1_env_cfg     cfg;
  virtual aou_irq_if vif;
  bit                enable = 1'b1;
  int unsigned       slack_granules = 240;
  // Core cycles for a clear to reach the pin: the APB crossing, with margin.
  int unsigned       rearm_cycles = 256;

  // Per RP, the mismatch bits software has seen set (bit 0 BID, bit 1 RID).
  protected bit [1:0]    seen[AOU_RP_MAX];
  // The pin rose and no clear has been written since.
  protected bit          pin_set;
  protected bit          pin_prev;
  protected bit          in_force;
  protected int unsigned since;     // granules of credited messages since the block began
  protected bit          reported;
  protected int unsigned rearm_wait;  // cycles until a still-high pin re-arms the hold
  protected uvm_reg      err_reg[AOU_RP_MAX];
  protected uvm_reg_field f_bid[AOU_RP_MAX];
  protected uvm_reg_field f_rid[AOU_RP_MAX];

  int unsigned n_blocks;
  int unsigned n_late;     // messages inside the slack
  int unsigned n_fires;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_msg_imp = new("rx_msg_imp", this);
    apb_imp = new("apb_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("crd_block_slack=%d", slack_granules));
    if (vif == null && !uvm_config_db #(virtual aou_irq_if)::get(this, "", "irq", vif))
      `uvm_fatal(get_type_name(), "no aou_irq_if under config_db key irq")
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    if (rm == null) return;
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      err_reg[r] = rm.get_reg_by_name($sformatf("error_info_rp%0d", r));
      if (err_reg[r] == null) continue;
      f_bid[r] = err_reg[r].get_field_by_name("split_bid_mismatch_err");
      f_rid[r] = err_reg[r].get_field_by_name("split_rid_mismatch_err");
    end
  endfunction

  function void reset_flush();
    foreach (seen[r]) seen[r] = '0;
    pin_set = 1'b0;
    pin_prev = 1'b0;
    rearm_wait = 0;
    update();
  endfunction

  protected function void update();
    bit now = pin_set;
    foreach (seen[r]) if (seen[r] != 0) now = 1'b1;
    if (now && !in_force) begin
      // Each window is one check, whether or not traffic was waiting in it.
      aou_rule_log::check("T1-E20", get_type_name());
      n_blocks++;
      since = 0;
      reported = 1'b0;
    end
    in_force = now;
  endfunction

  // The DUT is holding credited traffic because of a reported mismatch.
  function bit blocked();
    return enable && in_force;
  endfunction

  protected function bit bit_of(uvm_reg_field f, bit [31:0] d);
    return f != null && d[f.get_lsb_pos()];
  endfunction

  function void write_apb(aou_apb_item it);
    if (!enable || rm == null) return;
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      if (err_reg[r] == null || uvm_reg_addr_t'(it.addr) != err_reg[r].get_address()) continue;
      if (it.dir == AOU_APB_WRITE) begin
        // Write 1 clears: the block ends with it.
        if (bit_of(f_bid[r], it.data)) seen[r][0] = 1'b0;
        if (bit_of(f_rid[r], it.data)) seen[r][1] = 1'b0;
        if (bit_of(f_bid[r], it.data) || bit_of(f_rid[r], it.data)) begin
          pin_set = 1'b0;
          rearm_wait = rearm_cycles;
        end
      end else if (!it.slverr) begin
        seen[r][0] = bit_of(f_bid[r], it.data);
        seen[r][1] = bit_of(f_rid[r], it.data);
      end
    end
    update();
  endfunction

  function void write(aou_msg m);
    if (!enable || m.cred_class() == AOU_CC_NONE || !in_force) return;
    since += m.num_granules();
    if (since <= slack_granules) begin
      n_late++;
      return;
    end
    if (reported) return;
    reported = 1'b1;
    n_fires++;
    aou_rule_log::fire("T1-E20", get_type_name());
    `uvm_error(get_type_name(), $sformatf(
        {"T1-E20: the DUT sent %s on RP%0d while an M-port ID mismatch was reported and not ",
         "cleared (%0d granules of credited messages since the error was seen, %0d allowed ",
         "for the TX pipeline; the RTL holds credited TX traffic until the write-1 clear)"},
        m.kind(), m.rp, since, slack_granules))
  endfunction

  task run_phase(uvm_phase phase);
    if (!enable || vif == null) return;
    forever begin
      bit p;
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) begin
        pin_prev = 1'b0;
        rearm_wait = 0;
        continue;
      end
      p = vif.mon_cb.int_mi0_id_mismatch === 1'b1;
      if (rearm_wait > 0) rearm_wait--;
      if (p && !pin_set && (!pin_prev || rearm_wait == 0)) begin
        pin_set = 1'b1;
        update();
      end
      pin_prev = p;
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf(
              "%0d ID-mismatch blocks seen, %0d credited messages within the slack, T1-E20 %0d",
              n_blocks, n_late, n_fires), UVM_LOW)
  endfunction
endclass
