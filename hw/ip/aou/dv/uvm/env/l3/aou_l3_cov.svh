// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3 functional coverage. Coverpoints and crosses only, FSM transitions as
// explicit (previous, current) bins. The sample_*() functions set the s_*
// members and sample the covergroup that reads them and its aou_fc_group.
class aou_l3_cov extends uvm_object;
  `uvm_object_utils(aou_l3_cov)

  localparam int EV_HDR_GRANT  = 0;
  localparam int EV_CRDT_GRANT = 1;
  localparam int EV_BOTH       = 2;   // header and CrdtGrant in one flit (6.4)
  localparam int EV_CONSUME    = 3;
  localparam int EV_ZERO_STALL = 4;
  localparam int EV_SATURATE   = 5;
  localparam int EV_OVERFLOW   = 6;
  // DUT-side events: the DUT sent a message as soon as our grant ended its
  // zero credit; we advertised more than our buffer holds; we sent without
  // credit (injection).
  localparam int EV_DUT_ZERO_STALL = 7;
  localparam int EV_DUT_SATURATE   = 8;
  localparam int EV_INJ_OVERFLOW   = 9;

  // Sampled values; each covergroup samples the members it names.
  int unsigned s_prev, s_cur, s_op, s_dir, s_kind, s_rp, s_start, s_size, s_nmsgs;
  int unsigned s_misc0, s_misc1, s_carry, s_ev, s_cls;
  bit          s_legal, s_span, s_credit_only;

  covergroup cg_act_fsm;
    cp_trans: coverpoint (s_prev * 8 + s_cur) {
      `AOU_L3_FC_ACT_TRANS(AOU_FC_CG)
    }
  endgroup

  covergroup cg_act_op;
    cp_op: coverpoint s_op {
      `AOU_L3_FC_ACT_OP(AOU_FC_CG)
    }
    cp_dir: coverpoint s_dir {
      `AOU_FC_DIR_BINS(AOU_FC_CG)
    }
    cp_legal: coverpoint s_legal {
      `AOU_L3_FC_LEGAL(AOU_FC_CG)
    }
    x_op_dir_legal: cross cp_op, cp_dir, cp_legal;
  endgroup

  covergroup cg_msg;
    cp_kind: coverpoint s_kind {
      `AOU_L3_FC_MSG_KIND(AOU_FC_CG)
    }
    cp_rp: coverpoint s_rp {
      `AOU_L3_FC_RP(AOU_FC_CG)
    }
    cp_dir: coverpoint s_dir {
      `AOU_FC_DIR_BINS(AOU_FC_CG)
    }
    x_kind_rp_dir: cross cp_kind, cp_rp, cp_dir;
  endgroup

  covergroup cg_flit_layout;
    cp_start: coverpoint s_start {
      `AOU_L3_FC_START(AOU_FC_CG)
    }
    cp_size: coverpoint s_size {
      `AOU_L3_FC_SIZE(AOU_FC_CG)
    }
    cp_span: coverpoint s_span {
      `AOU_L3_FC_SPAN(AOU_FC_CG)
    }
    cp_dir: coverpoint s_dir {
      `AOU_FC_DIR_BINS(AOU_FC_CG)
    }
    x_start_size: cross cp_start, cp_size;
    x_size_span: cross cp_size, cp_span;
  endgroup

  covergroup cg_flit_occ;
    cp_nmsgs: coverpoint s_nmsgs {
      `AOU_L3_FC_NMSGS(AOU_FC_CG)
    }
    cp_misc_half0: coverpoint s_misc0 {
      `AOU_L3_FC_MISC(AOU_FC_CG)
    }
    cp_misc_half1: coverpoint s_misc1 {
      `AOU_L3_FC_MISC(AOU_FC_CG)
    }
    cp_carry: coverpoint s_carry {
      `AOU_L3_FC_CARRY(AOU_FC_CG)
    }
    cp_credit_only: coverpoint s_credit_only {
      `AOU_L3_FC_CREDIT_ONLY(AOU_FC_CG)
    }
    cp_dir: coverpoint s_dir {
      `AOU_FC_DIR_BINS(AOU_FC_CG)
    }
    x_nmsgs_dir: cross cp_nmsgs, cp_dir;
  endgroup

  covergroup cg_credit;
    cp_ev: coverpoint s_ev {
      `AOU_L3_FC_CREDIT_EV(AOU_FC_CG)
    }
    cp_cls: coverpoint s_cls {
      `AOU_L3_FC_CLS(AOU_FC_CG)
    }
    cp_dir: coverpoint s_dir {
      `AOU_FC_DIR_BINS(AOU_FC_CG)
    }
    x_ev_cls_dir: cross cp_ev, cp_cls, cp_dir;
  endgroup

  // The service's copies of the covergroups above.
  aou_fc_group fc_act_fsm;
  aou_fc_group fc_act_op;
  aou_fc_group fc_msg;
  aou_fc_group fc_flit_layout;
  aou_fc_group fc_flit_occ;
  aou_fc_group fc_credit;

  function new(string name = "aou_l3_cov");
    super.new(name);
    cg_act_fsm = new();
    cg_act_op = new();
    cg_msg = new();
    cg_flit_layout = new();
    cg_flit_occ = new();
    cg_credit = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_act_fsm = db.group("l3.cg_act_fsm", fresh);
    if (fresh) begin
      p = fc_act_fsm.cp("cp_trans"); `AOU_L3_FC_ACT_TRANS(AOU_FC_REG)
    end
    fc_act_op = db.group("l3.cg_act_op", fresh);
    if (fresh) begin
      p = fc_act_op.cp("cp_op"); `AOU_L3_FC_ACT_OP(AOU_FC_REG)
      p = fc_act_op.cp("cp_dir"); `AOU_FC_DIR_BINS(AOU_FC_REG)
      p = fc_act_op.cp("cp_legal"); `AOU_L3_FC_LEGAL(AOU_FC_REG)
      p = fc_act_op.add_cross("x_op_dir_legal", "cp_op cp_dir cp_legal");
      `AOU_L3_FC_X_ACT_OP(AOU_FC_REG)
    end
    fc_msg = db.group("l3.cg_msg", fresh);
    if (fresh) begin
      p = fc_msg.cp("cp_kind"); `AOU_L3_FC_MSG_KIND(AOU_FC_REG)
      p = fc_msg.cp("cp_rp"); `AOU_L3_FC_RP(AOU_FC_REG)
      p = fc_msg.cp("cp_dir"); `AOU_FC_DIR_BINS(AOU_FC_REG)
      p = fc_msg.add_cross("x_kind_rp_dir", "cp_kind cp_rp cp_dir");
      `AOU_L3_FC_X_KIND_RP(AOU_FC_REG)
    end
    fc_flit_layout = db.group("l3.cg_flit_layout", fresh);
    if (fresh) begin
      p = fc_flit_layout.cp("cp_start"); `AOU_L3_FC_START(AOU_FC_REG)
      p = fc_flit_layout.cp("cp_size"); `AOU_L3_FC_SIZE(AOU_FC_REG)
      p = fc_flit_layout.cp("cp_span"); `AOU_L3_FC_SPAN(AOU_FC_REG)
      p = fc_flit_layout.cp("cp_dir"); `AOU_FC_DIR_BINS(AOU_FC_REG)
      p = fc_flit_layout.add_cross("x_start_size", "cp_start cp_size");
      `AOU_L3_FC_X_START_SIZE(AOU_FC_REG)
      p = fc_flit_layout.add_cross("x_size_span", "cp_size cp_span");
      `AOU_L3_FC_X_SIZE_SPAN(AOU_FC_REG)
    end
    fc_flit_occ = db.group("l3.cg_flit_occ", fresh);
    if (fresh) begin
      p = fc_flit_occ.cp("cp_nmsgs"); `AOU_L3_FC_NMSGS(AOU_FC_REG)
      p = fc_flit_occ.cp("cp_misc_half0"); `AOU_L3_FC_MISC(AOU_FC_REG)
      p = fc_flit_occ.cp("cp_misc_half1"); `AOU_L3_FC_MISC(AOU_FC_REG)
      p = fc_flit_occ.cp("cp_carry"); `AOU_L3_FC_CARRY(AOU_FC_REG)
      p = fc_flit_occ.cp("cp_credit_only"); `AOU_L3_FC_CREDIT_ONLY(AOU_FC_REG)
      p = fc_flit_occ.cp("cp_dir"); `AOU_FC_DIR_BINS(AOU_FC_REG)
      void'(fc_flit_occ.add_cross("x_nmsgs_dir", "cp_nmsgs cp_dir"));
    end
    fc_credit = db.group("l3.cg_credit", fresh);
    if (fresh) begin
      p = fc_credit.cp("cp_ev"); `AOU_L3_FC_CREDIT_EV(AOU_FC_REG)
      p = fc_credit.cp("cp_cls"); `AOU_L3_FC_CLS(AOU_FC_REG)
      p = fc_credit.cp("cp_dir"); `AOU_FC_DIR_BINS(AOU_FC_REG)
      p = fc_credit.add_cross("x_ev_cls_dir", "cp_ev cp_cls cp_dir");
      `AOU_L3_FC_X_CREDIT(AOU_FC_REG)
    end
  endfunction

  static function int unsigned msg_kind(aou_msg m);
    aou_msg_wdata w;
    aou_msg_rdata r;
    aou_msg_crdtgrant c;
    case (m.msg_type)
      AOU_MT_WREQ:  return 0;
      AOU_MT_RREQ:  return 1;
      AOU_MT_WDATA, AOU_MT_WDATAF: begin
        if (!$cast(w, m)) return 15;
        return (w.full() ? 5 : 2) + int'(w.dlength);
      end
      AOU_MT_RDATA: begin
        if (!$cast(r, m)) return 15;
        return 8 + int'(r.dlength);
      end
      AOU_MT_WRESP: return 11;
      default:      return $cast(c, m) ? 13 : 12;
    endcase
  endfunction

  // lost: the link was lost under the model (LinkReset, link down).
  function void sample_fsm(aou_link_state_e prev, aou_link_state_e cur, bit lost = 1'b0);
    s_prev = int'(prev) + (lost ? 8 : 0);
    s_cur = int'(cur);
    cg_act_fsm.sample();
    fc_act_fsm.sample(int'(s_prev * 8 + s_cur));
  endfunction

  function void sample_act_op(bit [3:0] op, aou_l3_dir_e dir, bit legal);
    s_op = int'(op);
    s_dir = int'(dir);
    s_legal = legal;
    cg_act_op.sample();
    fc_act_op.sample(int'(s_op), int'(s_dir), int'(s_legal));
  endfunction

  function void sample_msg(aou_msg m);
    s_kind = msg_kind(m);
    s_rp = (s_kind >= 12) ? 0 : int'(m.rp);
    s_dir = int'(m.dir);
    cg_msg.sample();
    fc_msg.sample(int'(s_kind), int'(s_rp), int'(s_dir));
    if (m.start_granule >= 0) begin
      s_start = m.start_granule;
      s_size = m.num_granules();
      s_span = m.span_flits > 1;
      cg_flit_layout.sample();
      fc_flit_layout.sample(int'(s_start), int'(s_size), int'(s_span), int'(s_dir));
    end
  endfunction

  function void sample_flit(aou_flit f, int unsigned misc0, int unsigned misc1);
    s_credit_only = f.msg_credit != 0 && f.msg_start == 0 && f.carry_in == 0;
    s_nmsgs = f.num_starts();
    s_misc0 = misc0;
    s_misc1 = misc1;
    s_carry = f.carry_in;
    s_dir = int'(f.dir);
    cg_flit_occ.sample();
    fc_flit_occ.sample(int'(s_nmsgs), int'(s_misc0), int'(s_misc1), int'(s_carry),
                       int'(s_credit_only), int'(s_dir));
  endfunction

  function void sample_credit(int unsigned ev, aou_cred_class_e cls, aou_l3_dir_e dir);
    s_ev = ev;
    s_cls = int'(cls);
    s_dir = int'(dir);
    cg_credit.sample();
    fc_credit.sample(int'(s_ev), int'(s_cls), int'(s_dir));
  endfunction
endclass
