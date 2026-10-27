// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Turns AOU_FDI_CHECKER's status ports into rule reports. Each violation
// class that newly appears is reported once through aou_l3_rule_chk under
// the AoU rule it enforces, with the frozen capture record when it names the
// class; the adapter then pulses I_ERR_CLEAR so the next finding gets a
// fresh capture. LP is the observed die's stream (the DUT), PL its peer's.
class aou_fdi_chk_adapter extends uvm_component;
  `uvm_component_utils(aou_fdi_chk_adapter)

  localparam int NCLS = aou_fdi_checker_pkg::VIOL_CLASS_CNT;

  virtual aou_fdi_checker_if vif;
  aou_l3_rule_chk            chk;
  bit                        clear_after_report = 1'b1;
  bit [NCLS-1:0]             expect_enabled = NCLS'(aou_fdi_checker_pkg::CHK_CLASSES_ALL);
  bit                        expect_lp_traffic = 1'b1;
  bit                        expect_pl_traffic = 1'b1;
  int unsigned               reports[NCLS];
  // The DEACTIVATE_FORCE window (aou_l3_cfg::force_deact_window); null: none.
  aou_l3_cfg                 l3_cfg;
  int unsigned               forced_skips;   // forced DeactivateReqs not reported

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  static function string class_name(int unsigned c);
    case (c)
      aou_fdi_checker_pkg::VIOL_MSGTYPE:        return "VIOL_MSGTYPE";
      aou_fdi_checker_pkg::VIOL_MISCOP:         return "VIOL_MISCOP";
      aou_fdi_checker_pkg::VIOL_ACTIVATIONOP:   return "VIOL_ACTIVATIONOP";
      aou_fdi_checker_pkg::VIOL_DLENGTH:        return "VIOL_DLENGTH";
      aou_fdi_checker_pkg::VIOL_RSVD_NONZERO:   return "VIOL_RSVD_NONZERO";
      aou_fdi_checker_pkg::VIOL_MSGSTART:       return "VIOL_MSGSTART";
      aou_fdi_checker_pkg::VIOL_ACT_SEQ:        return "VIOL_ACT_SEQ";
      aou_fdi_checker_pkg::VIOL_MSG_ORDER:      return "VIOL_MSG_ORDER";
      aou_fdi_checker_pkg::VIOL_CRD_UNDERFLOW:  return "VIOL_CRD_UNDERFLOW";
      aou_fdi_checker_pkg::VIOL_MISC_PLACEMENT: return "VIOL_MISC_PLACEMENT";
      aou_fdi_checker_pkg::VIOL_ADV_ORDER:      return "VIOL_ADV_ORDER";
      aou_fdi_checker_pkg::VIOL_RP_RANGE:       return "VIOL_RP_RANGE";
      aou_fdi_checker_pkg::VIOL_FDID:           return "VIOL_FDID";
      aou_fdi_checker_pkg::VIOL_CRD_OVERFLOW:   return "VIOL_CRD_OVERFLOW";
      aou_fdi_checker_pkg::VIOL_RP_MAP:         return "VIOL_RP_MAP";
      default:                                  return $sformatf("VIOL_%0d", c);
    endcase
  endfunction

  // The AoU rule (checkers/rules.csv) each checker class enforces.
  static function string rule_of(int unsigned c);
    case (c)
      aou_fdi_checker_pkg::VIOL_MSGTYPE,
      aou_fdi_checker_pkg::VIOL_MISCOP,
      aou_fdi_checker_pkg::VIOL_ACTIVATIONOP,
      aou_fdi_checker_pkg::VIOL_DLENGTH:        return "AOU-R3";
      aou_fdi_checker_pkg::VIOL_RSVD_NONZERO:   return "AOU-R11";
      aou_fdi_checker_pkg::VIOL_MSGSTART:       return "AOU-R4";
      aou_fdi_checker_pkg::VIOL_ACT_SEQ:        return "AOU-R40";
      aou_fdi_checker_pkg::VIOL_MSG_ORDER:      return "AOU-R30";
      aou_fdi_checker_pkg::VIOL_CRD_UNDERFLOW:  return "AOU-R16";
      aou_fdi_checker_pkg::VIOL_MISC_PLACEMENT: return "AOU-R6";
      aou_fdi_checker_pkg::VIOL_ADV_ORDER:      return "AOU-R29";
      aou_fdi_checker_pkg::VIOL_RP_RANGE:       return "AOU-R14";
      aou_fdi_checker_pkg::VIOL_FDID:           return "AOU-R9";
      aou_fdi_checker_pkg::VIOL_CRD_OVERFLOW:   return "AOU-R21";
      default:                                  return "AOU-R45";
    endcase
  endfunction

  static function string dir_name(bit d);
    return d ? "PL(peer->DUT)" : "LP(DUT->peer)";
  endfunction

  // The captured reserved-field finding is the DUT's forced DeactivateReq:
  // PropertyReq=1 is the RTL's mark of a DEACTIVATE_FORCE deactivation and is
  // accepted within the force window, when it is the only reserved bit set
  // (the same rule as aou_unpacker's AOU-R11).
  function bit forced_deact(bit cap_dir);
    aou_granule_t g[$];
    aou_msg_act a;
    if (l3_cfg == null || cap_dir != 1'b0 || !l3_cfg.force_deact_window()) return 1'b0;
    // The capture holds the granule in wire byte order; the codec takes it
    // with its first byte on top.
    g.push_back(aou_granule_t'({<<8{vif.mon_cb.capture_granule}}));
    if (!$cast(a, aou_msg_codec::decode(g, l3_cfg.spec_rev))) return 1'b0;
    return a.forced_deact_mark();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual aou_fdi_checker_if)::get(this, "", "fdi_chk", vif))
      `uvm_fatal(get_type_name(), "no aou_fdi_checker_if under config_db key fdi_chk")
    if (chk == null && !uvm_config_db#(aou_l3_rule_chk)::get(this, "", "chk", chk))
      chk = aou_l3_rule_chk::type_id::create("chk");
  endfunction

  task run_phase(uvm_phase phase);
    bit [NCLS-1:0] reported = '0;
    vif.drv_cb.err_clear <= 1'b0;
    forever begin
      bit [NCLS-1:0] fresh;
      @(vif.mon_cb);
      if (vif.mon_cb.rst_n !== 1'b1) continue;
      fresh = vif.mon_cb.violation & ~reported;
      if (fresh == 0) continue;
      for (int unsigned c = 0; c < NCLS; c++) begin
        if (fresh[c]) begin
          bit cap_dir;
          bit [1:0] done;
          done = '0;
          reports[c]++;
          if (vif.mon_cb.capture_valid && int'(vif.mon_cb.capture_code) == c) begin
            cap_dir = vif.mon_cb.capture_dir;
            done[cap_dir] = 1'b1;
            if (c == aou_fdi_checker_pkg::VIOL_RSVD_NONZERO && forced_deact(cap_dir)) begin
              forced_skips++;
              reports[c]--;
              `uvm_info(get_type_name(), $sformatf(
                  "AOU_FDI_CHECKER VIOL_RSVD_NONZERO: forced DeactivateReq, flit#%0d (accepted)",
                  vif.mon_cb.capture_flit_seq), UVM_MEDIUM)
            end else begin
              chk.violation(rule_of(c), get_type_name(),
                            $sformatf("AOU_FDI_CHECKER %s %s flit#%0d G%0d granule=%010h",
                                      class_name(c), dir_name(cap_dir),
                                      vif.mon_cb.capture_flit_seq,
                                      vif.mon_cb.capture_granule_idx,
                                      vif.mon_cb.capture_granule));
            end
          end
          // Classes the capture record doesn't describe get their direction
          // from the per-direction tap, one report per direction.
          for (int unsigned d = 0; d < 2; d++) begin
            if (!done[d] && vif.mon_cb.dir_violation[d][c] === 1'b1) begin
              done[d] = 1'b1;
              chk.violation(rule_of(c), get_type_name(),
                            $sformatf("AOU_FDI_CHECKER %s %s from flit#%0d", class_name(c),
                                      dir_name(1'(d)), vif.mon_cb.dir_flit_seq[d]));
            end
          end
          if (!done[0] && !done[1])
            chk.violation(rule_of(c), get_type_name(),
                          $sformatf("AOU_FDI_CHECKER %s", class_name(c)));
        end
      end
      reported |= fresh;
      if (clear_after_report) begin
        vif.drv_cb.err_clear <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.err_clear <= 1'b0;
        @(vif.mon_cb);
        reported = '0;
      end
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (vif.check_enabled !== expect_enabled)
      `uvm_error(get_type_name(), $sformatf("checker enabled classes %0h, expected %0h",
                                            vif.check_enabled, expect_enabled))
    if (expect_lp_traffic && vif.lp_flit_seq == 0)
      `uvm_error(get_type_name(), "checker saw no flit on the LP (DUT) stream")
    if (expect_pl_traffic && vif.pl_flit_seq == 0)
      `uvm_error(get_type_name(), "checker saw no flit on the PL (peer) stream")
  endfunction

  // Every flit either way is judged by every enabled violation class.
  function void ledger();
    bit seen[string];
    int unsigned n = vif.lp_flit_seq + vif.pl_flit_seq;
    for (int unsigned c = 0; c < NCLS; c++) begin
      string r = rule_of(c);
      if (seen.exists(r) || !vif.check_enabled[c]) continue;
      seen[r] = 1'b1;
      aou_rule_log::check(r, get_type_name(), n);
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    ledger();
    `uvm_info(get_type_name(), $sformatf("AOU_FDI_CHECKER: LP flits=%0d PL flits=%0d reports=%p",
                                         vif.lp_flit_seq, vif.pl_flit_seq, reports), UVM_LOW)
  endfunction
endclass
