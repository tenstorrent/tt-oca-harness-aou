// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L2 functional coverage. Transitions are (previous, current) pairs packed
// as prev*16 + cur, with one explicit bin per transition of interest.
class aou_lsm_cov extends uvm_object;
  `uvm_object_utils(aou_lsm_cov)

  int unsigned l_tr;    // aou_lsm_state_e pair
  int unsigned l_sts;
  int unsigned l_req;
  int unsigned l_enc;   // aou_fdi_enc_e
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
    // Informational: which encoding the run used, so a merge shows it includes
    // SPEC-encoded runs. The rtl bin (the DUT's private codes, BUGS/001) is to be
    // dropped when the RTL fix lands and SPEC becomes the default.
    cp_fdi_enc: coverpoint l_enc {
      `AOU_LSM_FC_ENC(AOU_FC_CG)
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
      p = fc_link_state.cp("cp_fdi_enc"); `AOU_LSM_FC_ENC(AOU_FC_REG)
      p = fc_link_state.add_cross("x_sts_req", "cp_sts cp_req");
      `AOU_LSM_FC_X_STS_REQ(AOU_FC_REG)
    end
    fc_bringup_fsm = db.group("l2.cg_bringup_fsm", fresh);
    if (fresh) begin
      p = fc_bringup_fsm.cp("cp_tr"); `AOU_LSM_FC_BRG_TR(AOU_FC_REG)
    end
  endfunction

  function void sample_link(aou_lsm_state_e prev, aou_lsm_state_e cur, aou_lsm_req_e req,
                            aou_fdi_enc_e enc);
    l_tr = int'(prev) * 16 + int'(cur);
    l_sts = int'(cur);
    l_req = int'(req);
    l_enc = int'(enc);
    cg_link_state.sample();
    fc_link_state.sample(int'(l_tr), int'(l_sts), int'(l_req), int'(l_enc));
  endfunction

  function void sample_brg(aou_brg_state_e prev, aou_brg_state_e cur);
    b_tr = int'(prev) * 16 + int'(cur);
    cg_bringup_fsm.sample();
    fc_bringup_fsm.sample(int'(b_tr));
  endfunction
endclass
