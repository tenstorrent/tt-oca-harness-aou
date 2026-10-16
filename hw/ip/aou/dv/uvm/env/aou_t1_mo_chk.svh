// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// M-port outstanding limit, always on (MAS software-operation 7.2.2;
// integration guide M_RD_MO_CNT/M_WR_MO_CNT, default 32 and not overridden by
// the bench). The pending-ID tables hold one entry per M-port read or write
// burst from its AR/AW handshake until its last R beat or its B; when they
// are full the DUT stops issuing, which is back-pressure, never an error.
// FEAT-R22: per RP, at most rd_mo reads and wr_mo writes are outstanding on
// the M port. cg_mo records how full each table got (bin full: the limit was
// reached, plan 9.20). A bus reset or AOU_SW_RESET clears the count.
class aou_t1_mo_chk extends uvm_component;
  `uvm_component_utils(aou_t1_mo_chk)

  aou_axi_vif_t vif[];
  int unsigned  rd_mo = 32;
  int unsigned  wr_mo = 32;

  protected int unsigned out[][2];     // [rp][0 write, 1 read]
  protected int unsigned peak[][2];
  protected int unsigned n_over[][2];
  protected bit [1:0]    cv_dir;
  protected int unsigned cv_occ;
  protected aou_fc_group fc_mo;

  covergroup cg_mo;
    cp_dir: coverpoint cv_dir {
      `AOU_T1_MO_FC_DIR(AOU_FC_CG)
    }
    cp_occ: coverpoint cv_occ {
      `AOU_T1_MO_FC_OCC(AOU_FC_CG)
    }
    x_mo: cross cp_dir, cp_occ;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_mo = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_mo = db.group("t1.mo_cg", fresh);
    if (fresh) begin
      p = fc_mo.cp("cp_dir"); `AOU_T1_MO_FC_DIR(AOU_FC_REG)
      p = fc_mo.cp("cp_occ"); `AOU_T1_MO_FC_OCC(AOU_FC_REG)
      void'(fc_mo.add_cross("x_mo", "cp_dir cp_occ"));
    end
  endfunction

  static function string kind(int d);
    if (d == 0) return "writes";
    return "reads";
  endfunction

  function int unsigned limit(int d);
    return d == 0 ? wr_mo : rd_mo;
  endfunction

  function void clear();
    foreach (out[r, d]) out[r][d] = 0;
  endfunction

  protected function void issued(int unsigned r, int d);
    out[r][d]++;
    if (out[r][d] > peak[r][d]) peak[r][d] = out[r][d];
    cv_dir = 2'(d);
    cv_occ = out[r][d];
    cg_mo.sample();
    fc_mo.sample(d, int'(out[r][d]));
    aou_rule_pkg::aou_rule_log::check("FEAT-R22", get_type_name());
    if (out[r][d] > limit(d) && n_over[r][d]++ == 0) begin
      aou_rule_pkg::aou_rule_log::fire("FEAT-R22", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R22: RP%0d M port has %0d %s outstanding, limit %0d", r, out[r][d],
          kind(d), limit(d)))
    end
  endfunction

  task watch(int unsigned r);
    forever begin
      @(vif[r].mon_cb);
      if (vif[r].mon_cb.resetn !== 1'b1) begin
        out[r][0] = 0;
        out[r][1] = 0;
        continue;
      end
      if (vif[r].mon_cb.bvalid === 1'b1 && vif[r].mon_cb.bready === 1'b1 && out[r][0] > 0)
        out[r][0]--;
      if (vif[r].mon_cb.rvalid === 1'b1 && vif[r].mon_cb.rready === 1'b1 &&
          vif[r].mon_cb.rlast === 1'b1 && out[r][1] > 0)
        out[r][1]--;
      if (vif[r].mon_cb.awvalid === 1'b1 && vif[r].mon_cb.awready === 1'b1) issued(r, 0);
      if (vif[r].mon_cb.arvalid === 1'b1 && vif[r].mon_cb.arready === 1'b1) issued(r, 1);
    end
  endtask

  task run_phase(uvm_phase phase);
    out = new[vif.size()];
    peak = new[vif.size()];
    n_over = new[vif.size()];
    foreach (vif[r]) begin
      fork
        automatic int unsigned rr = r;
        watch(rr);
      join_none
    end
  endtask

  function void report_phase(uvm_phase phase);
    foreach (peak[r])
      `uvm_info(get_type_name(), $sformatf(
          "RP%0d M port: at most %0d of %0d writes and %0d of %0d reads outstanding", r,
          peak[r][0], wr_mo, peak[r][1], rd_mo), UVM_LOW)
  endfunction
endclass
