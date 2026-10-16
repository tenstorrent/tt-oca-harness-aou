// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Round-robin credit advertisement across RPs (MAS 3.9: with several RPs the
// DUT advertises credit only in the header MsgCredit field, for one RP per
// header, round robin over the RPs with credit to return; plan 3.19).
// T1-C03: in a window a test opens with window_start(), stating that every
// RP the DUT owes credit to can have it back (it has held the DUT's TX until
// the DUT dequeued everything it received), the first non-zero header
// MsgCredits name each owed RP exactly once, and all arrive within
// window_cycles; the checker closes the window itself. The DUT owes an RP
// what the remote model has consumed of the DUT's credit and not had back:
// per class, the most it held since activation minus what it holds now.
// How many RPs a window owed is coverage (env.cg_crd_rr).
class aou_t1_crd_rr_chk extends uvm_component;
  `uvm_component_utils(aou_t1_crd_rr_chk)

  uvm_analysis_imp #(aou_l3_flit_item, aou_t1_crd_rr_chk) dut_flit_imp;

  aou_credit_mgr crd;
  int unsigned   n_rp = 1;
  aou_axi_vif_t  clk_vif;
  int unsigned   window_cycles = 4000;

  int unsigned s_owed;
  covergroup cg_crd_rr;
    cp_owed: coverpoint s_owed {
      `AOU_T1_RR_FC_OWED(AOU_FC_CG)
    }
  endgroup
  aou_fc_group fc_crd_rr;

  protected bit          open;
  protected bit          owed[AOU_RP_MAX];
  protected int unsigned n_owed;
  protected int unsigned waited;
  protected int unsigned seq[$];
  protected int unsigned n_windows;
  protected int unsigned n_grants[AOU_RP_MAX];

  function new(string name, uvm_component parent);
    aou_fc_db db;
    aou_fc_point p;
    bit fresh;
    super.new(name, parent);
    dut_flit_imp = new("dut_flit_imp", this);
    cg_crd_rr = new();
    db = aou_fc_db::get();
    fc_crd_rr = db.group("env.cg_crd_rr", fresh);
    if (fresh) begin
      p = fc_crd_rr.cp("cp_owed"); `AOU_T1_RR_FC_OWED(AOU_FC_REG)
    end
  endfunction

  function int unsigned owed_by_dut(int unsigned r);
    int unsigned n = 0;
    for (int unsigned c = 0; c < AOU_CC_NUM; c++)
      if (crd.tx_full[r][c] > crd.tx_cred[r][c]) n += crd.tx_full[r][c] - crd.tx_cred[r][c];
    return n;
  endfunction

  // Test intent: every owed credit can be returned now. Returns the number of
  // RPs the DUT owes credit to; with fewer than two there is nothing to order.
  function int unsigned window_start();
    string s = "";
    seq.delete();
    n_owed = 0;
    waited = 0;
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      owed[r] = (r < n_rp) && owed_by_dut(r) != 0;
      if (owed[r]) begin
        n_owed++;
        s = {s, $sformatf(" RP%0d=%0d", r, owed_by_dut(r))};
      end
    end
    `uvm_info(get_type_name(), {"credit window: DUT owes", s}, UVM_LOW)
    s_owed = n_owed;
    cg_crd_rr.sample();
    fc_crd_rr.sample(int'(n_owed));
    open = n_owed >= 2;
    return n_owed;
  endfunction

  function bit window_done();
    return !open;
  endfunction

  protected function void window_stop();
    bit seen[AOU_RP_MAX];
    open = 1'b0;
    n_windows++;
    aou_rule_log::check("T1-C03", get_type_name());
    `uvm_info(get_type_name(), $sformatf("credit window: MsgCredit RP order %p", seq), UVM_LOW)
    if (seq.size() < n_owed) begin
      aou_rule_log::fire("T1-C03", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "T1-C03: %0d of %0d owed RPs advertised by header MsgCredit in %0d cycles (order %p)",
          seq.size(), n_owed, waited, seq))
      return;
    end
    foreach (seq[i]) begin
      if (!owed[seq[i]] || seen[seq[i]]) begin
        aou_rule_log::fire("T1-C03", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            "T1-C03: MsgCredit order %p is not round robin over the owed RPs (RP%0d %s)", seq,
            seq[i], seen[seq[i]] ? "twice" : "owed nothing"))
        return;
      end
      seen[seq[i]] = 1'b1;
    end
  endfunction

  function void write(aou_l3_flit_item it);
    bit [15:0] mc = {it.bytes[AOU_PH_BYTE[5]], it.bytes[AOU_PH_BYTE[4]]};
    int unsigned r;
    int unsigned n[AOU_CC_NUM];
    bit any = 1'b0;
    aou_credit_mgr::hdr_decode(mc, r, n);
    foreach (n[c]) if (n[c] != 0) any = 1'b1;
    if (!any || r >= n_rp) return;
    n_grants[r]++;
    if (open) begin
      seq.push_back(r);
      if (seq.size() >= n_owed) window_stop();
    end
  endfunction

  task run_phase(uvm_phase phase);
    if (clk_vif == null) return;
    forever begin
      @(clk_vif.mon_cb);
      if (!open) continue;
      waited++;
      if (waited >= window_cycles) window_stop();
    end
  endtask

  function void check_phase(uvm_phase phase);
    if (open) window_stop();
  endfunction

  function void report_phase(uvm_phase phase);
    if (n_windows != 0)
      `uvm_info(get_type_name(), $sformatf("%0d credit windows; header MsgCredits per RP %p",
                                           n_windows, n_grants), UVM_LOW)
  endfunction
endclass
