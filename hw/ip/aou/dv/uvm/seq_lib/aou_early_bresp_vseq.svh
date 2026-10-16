// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Early write response (MAS 3.7). Local writes, bufferable or not, with
// EARLY_BRESP_EN programmed before activation (aou_early_bresp_chk checks the
// B timing). With err_rounds > 0 it then sends, per round, one bufferable write
// into a remote error region (set up by the test) and checks the capture
// registers and their W1C clear (FEAT-R07). With early_full the remote die
// answers every write early_lat cycles late, so the early table fills, and
// once drained every RP's WRITE_RESP_DONE must read 1 (FEAT-R16). With
// early_toggle, between the two traffic phases every write is drained,
// WRITE_RESP_DONE must read 1 on every RP, and each RP's EARLY_BRESP_EN is
// inverted (MAS 3.7.8); the checker judges the second phase by the new value.
class aou_early_bresp_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_early_bresp_vseq)

  // Round i writes to ERR_BASE + i * 4KB (+ RP stride), which the test makes a
  // remote error region answering resp(i). It sits past RP0's random-traffic
  // window and repeats per RP stride, so no RP's ordinary writes land in it.
  static const bit [63:0] ERR_BASE = 64'h0000_0001_0080_0000;
  int unsigned err_rounds;
  int          early_full;
  int          early_toggle;

  static function bit [1:0] resp(int unsigned i);
    return (i % 2 == 0) ? AOU_AXI_SLVERR : AOU_AXI_DECERR;
  endfunction

  function new(string name = "aou_early_bresp_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    void'(uvm_config_db#(int unsigned)::get(null, "*", "early_err_rounds", err_rounds));
    void'(uvm_config_db#(int)::get(null, "*", "early_full", early_full));
    void'(uvm_config_db#(int)::get(null, "*", "early_toggle", early_toggle));
  endtask

  task toggle_en();
    aou_early_bresp_chk chk;
    aou_t1_feature_cfg f = aou_t1_feature_cfg::type_id::create("toggle");
    if (!uvm_config_db#(aou_early_bresp_chk)::get(null, "*", "early_chk", chk))
      `uvm_fatal(get_type_name(), "no early_chk")
    drain();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
      expect_field(rg.get_field_by_name("write_resp_done"), 1, "FEAT-R16");
      f.early_resp[r] = (k.feat.early_resp[r] == 0) ? 1 : 0;
    end
    program_cfg(f);
    wait_cycles(4);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      `uvm_info(get_type_name(), $sformatf("RP%0d EARLY_BRESP_EN %0d -> %0d", r,
                                           k.feat.early_resp[r], f.early_resp[r]), UVM_LOW)
      chk.set_en(r, f.early_resp[r][0]);
    end
  endtask

  task scenario();
    if (early_full != 0) begin
      int unsigned lat = 2000;
      void'($value$plusargs("early_lat=%d", lat));
      cfg.remote_cfg.timing.b_lat.set_fixed(lat);
    end
    if (early_toggle != 0) begin
      traffic(k.dir, num_txns, make_profile());
      toggle_en();
      traffic(k.dir, num_txns, make_profile());
    end else begin
      super.scenario();
    end
    if (early_full != 0) begin
      cfg.remote_cfg.timing.b_lat.set_range(0, cfg.remote_lat_max);
      drain();
      for (int unsigned r = 0; r < cfg.n_rp; r++) begin
        uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
        expect_field(rg.get_field_by_name("write_resp_done"), 1, "FEAT-R16");
      end
    end
    for (int unsigned i = 0; i < err_rounds; i++) err_round(i);
  endtask

  // One bufferable write per RP lands in the error region; every RP's capture
  // register is checked and cleared, so INT_EARLY_RESP_ERR (any RP's error)
  // falls before the next round.
  task err_round(int unsigned i);
    aou_t1_traffic_cfg p = make_profile();
    bit [9:0] id = 10'($urandom_range(10'h3FF));
    drain();
    k.ids = aou_dp_knobs::DP_ID_SAME;
    k.id_value = id;
    k.bufferable_pct = 100;
    k.lens = '{0};
    p.wr_pct = 100;
    p.num_slots = 1;
    p.base = ERR_BASE + 64'(i) * 64'h1000;
    p.span = 64'h1000;
    traffic(AOU_T1_L2R, 1, p);
    drain();
    wait_cycles(20);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
      expect_field(rg.get_field_by_name("write_resp_err"), 1, "FEAT-R07");
      expect_field(rg.get_field_by_name("write_resp_err_id_info"), uvm_reg_data_t'(id), "FEAT-R07");
      expect_field(rg.get_field_by_name("write_resp_err_type_info"), uvm_reg_data_t'(resp(i)),
                   "FEAT-R07");
      write_field(rg.get_field_by_name("write_resp_err"), 1);
      expect_field(rg.get_field_by_name("write_resp_err"), 0, "FEAT-R07");
      expect_field(rg.get_field_by_name("write_resp_err_id_info"), 0, "FEAT-R07");
      expect_field(rg.get_field_by_name("write_resp_err_type_info"), 0, "FEAT-R07");
      expect_field(rg.get_field_by_name("write_resp_done"), 1, "FEAT-R07");
    end
  endtask
endclass
