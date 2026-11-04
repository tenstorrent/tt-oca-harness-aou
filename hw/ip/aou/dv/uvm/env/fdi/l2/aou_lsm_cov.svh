// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L2 functional coverage. Transitions are (previous, current) pairs packed
// as prev*16 + cur, with one explicit bin per transition of interest.
class aou_lsm_cov extends uvm_object;
  `uvm_object_utils(aou_lsm_cov)

  int unsigned l_tr;    // ucie_lsm_state_e pair
  int unsigned l_sts;
  int unsigned l_req;
  int unsigned b_tr;    // aou_brg_state_e pair

  covergroup cg_link_state;
    cp_tr: coverpoint l_tr {
      `AOU_LSM_FC_LINK_TR(AOU_FC_CG)
    }
    cp_sts: coverpoint l_sts {
      `AOU_LSM_FC_STS(AOU_FC_CG)
    }
    cp_req: coverpoint l_req {
      `AOU_LSM_FC_REQ(AOU_FC_CG)
    }
    x_sts_req: cross cp_sts, cp_req;
  endgroup

  covergroup cg_bringup_fsm;
    cp_tr: coverpoint b_tr {
      `AOU_LSM_FC_BRG_TR(AOU_FC_CG)
    }
  endgroup

  aou_fc_group fc_link_state;
  aou_fc_group fc_bringup_fsm;

  function new(string name = "aou_lsm_cov");
    super.new(name);
    cg_link_state = new();
    cg_bringup_fsm = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_link_state = db.group("l2.cg_link_state", fresh);
    if (fresh) begin
      p = fc_link_state.cp("cp_tr"); `AOU_LSM_FC_LINK_TR(AOU_FC_REG)
      p = fc_link_state.cp("cp_sts"); `AOU_LSM_FC_STS(AOU_FC_REG)
      p = fc_link_state.cp("cp_req"); `AOU_LSM_FC_REQ(AOU_FC_REG)
      p = fc_link_state.add_cross("x_sts_req", "cp_sts cp_req");
      `AOU_LSM_FC_X_STS_REQ(AOU_FC_REG)
      fc_link_state.plan("22.2", "cp_tr", "reset_active");
      fc_link_state.plan("18.13", "cp_tr", "active_retrain|retrain_active");
      fc_link_state.plan("18.14", "cp_tr", "*linkerror*");
      fc_link_state.plan("18.15", "cp_tr", "active_l1|l1_retrain");
      fc_link_state.plan("18.17", "cp_tr", "*linkreset*");
      fc_link_state.plan("18.18", "cp_tr", "*disabled*");
      fc_link_state.plan("22.2", "cp_sts", "reset|active");
      fc_link_state.plan("18.13", "cp_sts", "retrain");
      fc_link_state.plan("18.14", "cp_sts", "linkerror");
      fc_link_state.plan("18.15", "cp_sts", "l1");
      fc_link_state.plan("18.17", "cp_sts", "linkreset");
      fc_link_state.plan("18.18", "cp_sts", "disabled");
      fc_link_state.plan("22.2", "cp_req", "active");
      fc_link_state.plan("18.15", "cp_req", "l1");
      fc_link_state.plan("22.2", "x_sts_req", "reset,active");
      fc_link_state.plan("18.13", "x_sts_req", "retrain,*");
      fc_link_state.plan("18.15", "x_sts_req", "l1,*");
      fc_link_state.plan("22.7", "x_sts_req", "reset|linkerror|linkreset|disabled,nop");
    end
    fc_bringup_fsm = db.group("l2.cg_bringup_fsm", fresh);
    if (fresh) begin
      p = fc_bringup_fsm.cp("cp_tr"); `AOU_LSM_FC_BRG_TR(AOU_FC_REG)
      fc_bringup_fsm.plan("22.1 22.6");
      fc_bringup_fsm.plan("22.2", "cp_tr",
                          "reset_wait|wait_wake|wake_waitack|waitack_req|req_active");
      fc_bringup_fsm.plan("18.20", "cp_tr",
                          "wait_wake|wake_waitack|waitack_req|l1_wake|clkwake_wake");
      fc_bringup_fsm.plan("18.21", "cp_tr", "wait_reset");
      fc_bringup_fsm.plan("18.15", "cp_tr", "active_l1|l1_clkwake|l1_wake|clkwake_wake");
      fc_bringup_fsm.plan("22.4", "cp_tr", "*linkerr*|*linkdown*");
    end
  endfunction

  function void sample_link(ucie_lsm_state_e prev, ucie_lsm_state_e cur, ucie_lsm_req_e req);
    l_tr = int'(prev) * 16 + int'(cur);
    l_sts = int'(cur);
    l_req = int'(req);
    cg_link_state.sample();
    fc_link_state.sample(int'(l_tr), int'(l_sts), int'(l_req));
  endfunction

  function void sample_brg(aou_brg_state_e prev, aou_brg_state_e cur);
    b_tr = int'(prev) * 16 + int'(cur);
    cg_bringup_fsm.sample();
    fc_bringup_fsm.sample(int'(b_tr));
  endfunction
endclass
