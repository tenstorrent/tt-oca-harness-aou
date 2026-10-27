// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Early-response table backpressure (MAS 3.7.5/3.7.6, plan 16.11/16.12), on
// every RP whose EARLY_BRESP_EN is set (register mirror), in every test. Every
// write, bufferable or not, holds a table entry from its WLAST until the
// DUT has the remote die's actual B; with wr_mo_cnt entries held the DUT
// accepts no AW. The checker counts an entry from the S-port WLAST handshake
// until the remote die sends the WriteResp, a lower bound of the occupancy
// (the WriteResp is still on its way to the DUT).
//   FEAT-R15: no S-port AW is accepted while wr_mo_cnt entries are held.
//   FEAT-R16: an AW held while the table was full is accepted within
//             free_bound cycles of the WriteResp that frees an entry.
//   FEAT-R21 (plan 16.17) is not checked: PR #89 removed the
//             O_PENDING_CNT_OVER it observed (MAS 3.7.5) for a write-transaction
//             watchdog (INT_EARLY_WDT_ERR), which aou_t1_wdt_chk checks. With
//             over_chk (+early_over) the watchdog pin is counted while an AW
//             waits at the limit, for the report.
// Whether a run filled the table and saw a stall end is coverage
// (env.cg_early_tbl), not a check.
class aou_t1_early_tbl_chk extends uvm_component;
  `uvm_component_utils(aou_t1_early_tbl_chk)

  uvm_analysis_imp #(aou_msg, aou_t1_early_tbl_chk) rem_msg_imp;   // L3 ap_tx_msg

  aou_t1_env_cfg cfg;
  aou_core       rm;
  aou_axi_vif_t  vif[];
  int unsigned   wr_mo_cnt = AOU_T1_S_MO_CNT;   // S_WR_MO_CNT
  int unsigned   free_bound = 1000;
  bit            over_chk = 1'b0;

  int unsigned s_ev;
  covergroup cg_early_tbl;
    cp_ev: coverpoint s_ev {
      `AOU_T1_EARLY_FC_EV(AOU_FC_CG)
    }
  endgroup
  aou_fc_group fc_early_tbl;

  protected int unsigned wlast[AOU_RP_MAX];
  protected int unsigned freed[AOU_RP_MAX];
  protected int unsigned occ_max[AOU_RP_MAX];
  protected int unsigned n_full[AOU_RP_MAX];
  protected int unsigned n_resumed[AOU_RP_MAX];
  protected virtual aou_irq_if irq_vif;
  protected int unsigned n_wdt[AOU_RP_MAX];       // INT_EARLY_WDT_ERR cycles, AW at the limit
  protected int unsigned n_attempt[AOU_RP_MAX];   // cycles an AW waited at the limit

  function new(string name, uvm_component parent);
    aou_fc_db db;
    aou_fc_point p;
    bit fresh;
    super.new(name, parent);
    rem_msg_imp = new("rem_msg_imp", this);
    cg_early_tbl = new();
    db = aou_fc_db::get();
    fc_early_tbl = db.group("env.cg_early_tbl", fresh);
    if (fresh) begin
      p = fc_early_tbl.cp("cp_ev"); `AOU_T1_EARLY_FC_EV(AOU_FC_REG)
    end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("early_free_bound=%d", free_bound));
  endfunction

  function bit early_en(int unsigned r);
    uvm_reg rg;
    if (rm == null) return 1'b0;
    rg = rm.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
    return rg != null && rg.get_field_by_name("early_bresp_en").get_mirrored_value() != 0;
  endfunction

  function void write(aou_msg m);
    if (m.msg_type == AOU_MT_WRESP && int'(m.rp) < AOU_RP_MAX) freed[m.rp]++;
  endfunction

  // Reset contract: the table empties with the core.
  function void reset_flush();
    foreach (wlast[r]) begin
      wlast[r] = 0;
      freed[r] = 0;
    end
  endfunction

  protected function void sample(int unsigned ev);
    s_ev = ev;
    cg_early_tbl.sample();
    fc_early_tbl.sample(int'(ev));
  endfunction

  task run_phase(uvm_phase phase);
    if (over_chk && !uvm_config_db#(virtual aou_irq_if)::get(this, "", "irq", irq_vif))
      `uvm_fatal(get_type_name(), "no aou_irq_if under config_db key irq")
    foreach (vif[r]) begin
      automatic int unsigned rr = r;
      fork
        watch(rr);
      join_none
    end
  endtask

  protected task watch(int unsigned r);
    bit          stalled = 1'b0;
    bit          freed_since = 1'b0;
    int unsigned since_free = 0;
    int unsigned last_freed = 0;
    forever begin
      int unsigned occ;
      @(vif[r].mon_cb);
      if (vif[r].mon_cb.resetn !== 1'b1 || !early_en(r)) begin
        stalled = 1'b0;
        continue;
      end
      occ = (wlast[r] > freed[r]) ? wlast[r] - freed[r] : 0;
      if (occ > occ_max[r]) occ_max[r] = occ;
      if (freed[r] != last_freed) begin
        last_freed = freed[r];
        freed_since = 1'b1;
        since_free = 0;
      end
      if (vif[r].mon_cb.wvalid === 1'b1 && vif[r].mon_cb.wready === 1'b1 &&
          vif[r].mon_cb.wlast === 1'b1)
        wlast[r]++;
      if (vif[r].mon_cb.awvalid !== 1'b1) begin
        stalled = 1'b0;
        continue;
      end
      if (vif[r].mon_cb.awready === 1'b1) begin
        aou_rule_log::check("FEAT-R15", get_type_name());
        if (occ >= wr_mo_cnt) begin
          aou_rule_log::fire("FEAT-R15", get_type_name());
          `uvm_error(get_type_name(), $sformatf(
              "FEAT-R15: RP%0d accepted an AW with %0d writes pending (early table holds %0d)",
              r, occ, wr_mo_cnt))
        end
        if (stalled) begin
          n_resumed[r]++;
          sample(1);
        end
        stalled = 1'b0;
      end else if (occ >= wr_mo_cnt) begin
        n_attempt[r]++;
        if (over_chk && irq_vif.mon_cb.int_early_wdt_err === 1'b1) n_wdt[r]++;
        if (!stalled) begin
          n_full[r]++;
          sample(0);
          aou_rule_log::check("FEAT-R16", get_type_name());
        end
        stalled = 1'b1;
        freed_since = 1'b0;
      end else if (stalled && freed_since) begin
        since_free++;
        if (since_free == free_bound) begin
          aou_rule_log::fire("FEAT-R16", get_type_name());
          `uvm_error(get_type_name(), $sformatf(
              "FEAT-R16: RP%0d AW held %0d cycles after a WriteResp freed an entry (%0d left)", r,
              free_bound, occ))
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    foreach (vif[r])
      if (n_full[r] != 0 || occ_max[r] != 0)
        `uvm_info(get_type_name(), $sformatf(
            {"RP%0d early table: %0d writes, at most %0d held, %0d full stalls, %0d resumed, ",
             "%0d AW cycles waited at the limit (INT_EARLY_WDT_ERR high for %0d of them)"}, r,
            wlast[r], occ_max[r], n_full[r], n_resumed[r], n_attempt[r], n_wdt[r]), UVM_LOW)
  endfunction
endclass
