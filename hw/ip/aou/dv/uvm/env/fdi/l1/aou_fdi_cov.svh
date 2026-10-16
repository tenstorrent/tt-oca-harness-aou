// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L1 functional coverage, sampled by aou_fdi_monitor. Values are clamped
// before sampling so every bin is a plain value or range.
class aou_fdi_cov extends uvm_object;
  `uvm_object_utils(aou_fdi_cov)

  // cg_fdi_xfer
  bit          x_rx;            // 0: DUT TX, 1: DUT RX
  int unsigned x_beat_bytes;
  int unsigned x_stall;         // trdy-low cycles (TX) or bubbles (RX) inside the flit
  int unsigned x_gap;           // idle cycles before the flit
  // cg_fdi_cancel
  int unsigned c_half;
  bit          c_valid;         // pl_valid high in the cancel cycle
  int unsigned c_count;         // cancels so far on this flit
  bit          c_stalled;       // the TX side was stalled (pl_stallreq or lp_stallack high)
  // cg_fdi_stall
  int unsigned s_lat;           // cycles from pl_stallreq rise to lp_stallack rise
  int unsigned s_hold;          // cycles lp_stallack stayed high
  bit          s_mid;           // pl_stallreq rose inside a TX flit
  bit          s_trdy0;         // ... in a cycle with pl_trdy low (UCIe r1.1 8.3.2 rule 7)
  // cg_fdi_abandon: a partial flit abandoned when the Adapter left Active mid-flit
  bit          a_rx;

  covergroup cg_fdi_xfer;
    cp_dir: coverpoint x_rx {
      `AOU_FC_DIR_BINS(AOU_FC_CG)
    }
    cp_width: coverpoint x_beat_bytes {
      `AOU_FDI_FC_WIDTH(AOU_FC_CG)
    }
    cp_stall: coverpoint x_stall {
      `AOU_FDI_FC_STALL(AOU_FC_CG)
    }
    cp_gap: coverpoint x_gap {
      `AOU_FDI_FC_GAP(AOU_FC_CG)
    }
    x_dir_stall: cross cp_dir, cp_stall;
    x_dir_gap:   cross cp_dir, cp_gap;
  endgroup

  covergroup cg_fdi_cancel;
    cp_half: coverpoint c_half {
      `AOU_FDI_FC_HALF(AOU_FC_CG)
    }
    cp_kind: coverpoint c_valid {
      `AOU_FDI_FC_CANCEL_KIND(AOU_FC_CG)
    }
    cp_repeat: coverpoint c_count {
      `AOU_FDI_FC_REPEAT(AOU_FC_CG)
    }
    cp_stalled: coverpoint c_stalled {
      `AOU_FDI_FC_TX_STALLED(AOU_FC_CG)
    }
    x_half_kind: cross cp_half, cp_kind;
  endgroup

  covergroup cg_fdi_stall;
    cp_lat: coverpoint s_lat {
      `AOU_FDI_FC_LAT(AOU_FC_CG)
    }
    cp_hold: coverpoint s_hold {
      `AOU_FDI_FC_HOLD(AOU_FC_CG)
    }
    cp_where: coverpoint s_mid {
      `AOU_FDI_FC_WHERE(AOU_FC_CG)
    }
    cp_trdy_at_req: coverpoint s_trdy0 {
      `AOU_FDI_FC_TRDY_AT_REQ(AOU_FC_CG)
    }
    x_where_lat: cross cp_where, cp_lat;
    x_where_trdy: cross cp_where, cp_trdy_at_req;
  endgroup

  covergroup cg_fdi_abandon;
    cp_dir: coverpoint a_rx {
      `AOU_FDI_FC_ABANDON(AOU_FC_CG)
    }
  endgroup

  aou_fc_group fc_fdi_xfer;
  aou_fc_group fc_fdi_cancel;
  aou_fc_group fc_fdi_stall;
  aou_fc_group fc_fdi_abandon;

  function new(string name = "aou_fdi_cov");
    super.new(name);
    cg_fdi_xfer = new();
    cg_fdi_cancel = new();
    cg_fdi_stall = new();
    cg_fdi_abandon = new();
    fc_declare();
  endfunction

  local function void fc_declare();
    aou_fc_db db = aou_fc_db::get();
    aou_fc_point p;
    bit fresh;
    fc_fdi_xfer = db.group("l1.cg_fdi_xfer", fresh);
    if (fresh) begin
      p = fc_fdi_xfer.cp("cp_dir"); `AOU_FC_DIR_BINS(AOU_FC_REG)
      p = fc_fdi_xfer.cp("cp_width"); `AOU_FDI_FC_WIDTH(AOU_FC_REG)
      p = fc_fdi_xfer.cp("cp_stall"); `AOU_FDI_FC_STALL(AOU_FC_REG)
      p = fc_fdi_xfer.cp("cp_gap"); `AOU_FDI_FC_GAP(AOU_FC_REG)
      void'(fc_fdi_xfer.add_cross("x_dir_stall", "cp_dir cp_stall"));
      void'(fc_fdi_xfer.add_cross("x_dir_gap", "cp_dir cp_gap"));
    end
    fc_fdi_cancel = db.group("l1.cg_fdi_cancel", fresh);
    if (fresh) begin
      p = fc_fdi_cancel.cp("cp_half"); `AOU_FDI_FC_HALF(AOU_FC_REG)
      p = fc_fdi_cancel.cp("cp_kind"); `AOU_FDI_FC_CANCEL_KIND(AOU_FC_REG)
      p = fc_fdi_cancel.cp("cp_repeat"); `AOU_FDI_FC_REPEAT(AOU_FC_REG)
      p = fc_fdi_cancel.cp("cp_stalled"); `AOU_FDI_FC_TX_STALLED(AOU_FC_REG)
      void'(fc_fdi_cancel.add_cross("x_half_kind", "cp_half cp_kind"));
    end
    fc_fdi_stall = db.group("l1.cg_fdi_stall", fresh);
    if (fresh) begin
      p = fc_fdi_stall.cp("cp_lat"); `AOU_FDI_FC_LAT(AOU_FC_REG)
      p = fc_fdi_stall.cp("cp_hold"); `AOU_FDI_FC_HOLD(AOU_FC_REG)
      p = fc_fdi_stall.cp("cp_where"); `AOU_FDI_FC_WHERE(AOU_FC_REG)
      p = fc_fdi_stall.cp("cp_trdy_at_req"); `AOU_FDI_FC_TRDY_AT_REQ(AOU_FC_REG)
      void'(fc_fdi_stall.add_cross("x_where_lat", "cp_where cp_lat"));
      void'(fc_fdi_stall.add_cross("x_where_trdy", "cp_where cp_trdy_at_req"));
    end
    fc_fdi_abandon = db.group("l1.cg_fdi_abandon", fresh);
    if (fresh) begin
      p = fc_fdi_abandon.cp("cp_dir"); `AOU_FDI_FC_ABANDON(AOU_FC_REG)
    end
  endfunction

  function void sample_xfer(aou_fdi_dir_e dir, int unsigned beat_bytes, int unsigned stall,
                            int unsigned gap);
    x_rx = dir == AOU_FDI_RX;
    x_beat_bytes = beat_bytes;
    x_stall = stall > 5 ? 5 : stall;
    x_gap = gap > 4 ? 4 : gap;
    cg_fdi_xfer.sample();
    fc_fdi_xfer.sample(int'(x_rx), int'(x_beat_bytes), int'(x_stall), int'(x_gap));
  endfunction

  function void sample_cancel(int unsigned half, bit with_valid, int unsigned count,
                             bit stalled);
    c_half = half;
    c_valid = with_valid;
    c_count = count > 3 ? 3 : count;
    c_stalled = stalled;
    cg_fdi_cancel.sample();
    fc_fdi_cancel.sample(int'(c_half), int'(c_valid), int'(c_count), int'(c_stalled));
  endfunction

  function void sample_stall(int unsigned lat, int unsigned hold, bit mid, bit trdy0);
    s_lat = lat > 7 ? 7 : lat;
    s_hold = hold > 5 ? 5 : hold;
    s_mid = mid;
    s_trdy0 = trdy0;
    cg_fdi_stall.sample();
    fc_fdi_stall.sample(int'(s_lat), int'(s_hold), int'(s_mid), int'(s_trdy0));
  endfunction

  function void sample_abandon(bit rx);
    a_rx = rx;
    cg_fdi_abandon.sample();
    fc_fdi_abandon.sample(int'(a_rx));
  endfunction
endclass
