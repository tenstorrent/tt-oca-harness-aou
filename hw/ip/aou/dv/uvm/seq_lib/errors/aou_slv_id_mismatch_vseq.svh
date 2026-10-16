// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Subordinate-side AXI ID mismatch on every RP (plan 9.11, 9.12; main #76).
// The remote die answers a request the DUT never sent: a WriteResp (BID) or
// a ReadData (RID) whose ID has nothing pending on that RP. Per RP and kind:
//   T1-E16  AXI_SLV_ID_MISMATCH_ERR_RPn sets the error bit of that kind with
//           the ID in its INFO field; no other RP or kind is set;
//   T1-E17  INT_SI0_ID_MISMATCH rises (MAS 7.2.2) and falls after the W1C;
//   T1-E18  white-box: of AOU_CORE's two aggregates that AOU_CORE_TOP ORs
//           into INT_SI0_ID_MISMATCH, only the one of that kind is set. At
//           the DUT's ports the two are indistinguishable, so this is the
//           only place #76 (RP1-RP3 crossed) shows.
// The checker is enabled through bit 22 of AXI_SLV_ID_MISMATCH_ERR_RPn, which
// the RDL calls reserved and the MAS says is tied off (BUGS/003 interim:
// the bit enables the checker; the #76 commit describes the per-RP bits and
// aggregates).
// Knobs: +kind=b|r|both (default both) +id=<hex>.
class aou_slv_id_mismatch_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_slv_id_mismatch_vseq)

  localparam bit [31:0] ENABLE = 32'h0040_0000;
  localparam int unsigned SETTLE = 200;

  function new(string name = "aou_slv_id_mismatch_vseq");
    super.new(name);
  endfunction

  function uvm_reg slv_reg(int unsigned r);
    uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("axi_slv_id_mismatch_err_rp%0d", r));
    if (rg == null) `uvm_fatal(get_type_name(), $sformatf("no AXI_SLV_ID_MISMATCH_ERR_RP%0d", r))
    return rg;
  endfunction

  task raw_wr(bit [31:0] addr, bit [31:0] data);
    aou_reg_base_seq s = aou_reg_base_seq::type_id::create("s");
    bit slverr;
    prep_reg(s);
    s.raw(aou_apb_pkg::AOU_APB_WRITE, addr, data, slverr);
  endtask

  task raw_rd(bit [31:0] addr, output bit [31:0] data);
    aou_reg_base_seq s = aou_reg_base_seq::type_id::create("s");
    bit slverr;
    prep_reg(s);
    data = '0;
    s.raw(aou_apb_pkg::AOU_APB_READ, addr, data, slverr);
  endtask

  task body();
    string kind = arg_str("kind", "both");
    bit [9:0] id = 10'(arg_int("id", $urandom_range(1023)));
    int unsigned n = cfg.n_rp * ((kind == "both") ? 2 : 1);
    expect_event("INT_SI0_ID_MISMATCH", n, n);
    link_up();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    for (int unsigned r = 0; r < cfg.n_rp; r++)
      raw_wr(32'(slv_reg(r).get_address()), ENABLE);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (kind != "r") inject_one(r, 1'b1, id);
      if (kind != "b") inject_one(r, 1'b0, id);
    end
  endtask

  // One unsolicited response on RP r (b: WriteResp, else ReadData).
  task inject_one(int unsigned r, bit b, bit [9:0] id);
    bit [31:0] v;
    bit [31:0] exp = ENABLE | (b ? (32'(id) << 12) | 32'h2 : (32'(id) << 2) | 32'h1);
    string what = $sformatf("RP%0d %s ID %0h", r, b ? "BID" : "RID", id);
    `uvm_info(get_type_name(), {"unsolicited response: ", what}, UVM_LOW)
    if (b) begin
      aou_msg_wresp m = aou_msg_wresp::type_id::create("bad_b");
      m.rp = 2'(cfg.l3_cfg.dest_rp[r]);
      m.id = id;
      env.l3.send(m);
    end else begin
      aou_msg_rdata m = aou_msg_rdata::type_id::create("bad_r");
      m.rp = 2'(cfg.l3_cfg.dest_rp[r]);
      m.id = id;
      m.last = 1'b1;
      m.dlength = 2'd0;
      env.l3.send(m);
    end
    wait_cycles(SETTLE);
    for (int unsigned q = 0; q < cfg.n_rp; q++) begin
      raw_rd(32'(slv_reg(q).get_address()), v);
      if (v != ((q == r) ? exp : ENABLE))
        `uvm_error(get_type_name(), $sformatf("T1-E16: %s: ERR_RP%0d=%08h, expected %08h", what,
                                              q, v, (q == r) ? exp : ENABLE))
    end
    if (env.status.vif.mon_cb.int_si0_id_mismatch !== 1'b1)
      `uvm_error(get_type_name(), {"T1-E17: INT_SI0_ID_MISMATCH low after ", what})
    if (env.status.vif.mon_cb.slv_bid_agg !== b || env.status.vif.mon_cb.slv_rid_agg !== !b)
      `uvm_error(get_type_name(), $sformatf({"T1-E18: %s: AOU_CORE aggregates RID=%0b BID=%0b, ",
                                             "expected only the %s one"}, what,
                                            env.status.vif.mon_cb.slv_rid_agg,
                                            env.status.vif.mon_cb.slv_bid_agg, b ? "BID" : "RID"))
    raw_wr(32'(slv_reg(r).get_address()), ENABLE | 32'h3);
    wait_cycles(SETTLE);
    raw_rd(32'(slv_reg(r).get_address()), v);
    if (v != ENABLE)
      `uvm_error(get_type_name(), $sformatf("T1-E16: %s: RP%0d reads %08h after W1C", what, r, v))
    if (env.status.vif.mon_cb.int_si0_id_mismatch !== 1'b0)
      `uvm_error(get_type_name(), {"T1-E17: INT_SI0_ID_MISMATCH still high after clearing ", what})
  endtask
endclass
