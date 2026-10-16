// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Splitter (MAS 3.6): program MAX_AWBURSTLEN/MAX_ARBURSTLEN before activation,
// read them back (an illegal value is stored as 0xF), then remote-originated
// bursts the DUT splits on its M port (aou_split_chk).
class aou_split_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_split_vseq)

  function new(string name = "aou_split_vseq");
    super.new(name);
  endfunction

  static function int unsigned stored(int v);
    return aou_reg_burstlen_cb::is_legal(uvm_reg_data_t'(v)) ? v : 'hF;
  endfunction

  task configure_dut();
    super.configure_dut();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("axi_split_tr_rp%0d", r));
      if (k.feat.split_aw[r] >= 0)
        expect_field(rg.get_field_by_name("max_awburstlen"),
                     uvm_reg_data_t'(stored(k.feat.split_aw[r])), "FEAT-R01");
      if (k.feat.split_ar[r] >= 0)
        expect_field(rg.get_field_by_name("max_arburstlen"),
                     uvm_reg_data_t'(stored(k.feat.split_ar[r])), "FEAT-R01");
    end
  endtask
endclass
