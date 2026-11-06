// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Asymmetric RP mapping (ASYMMETRIC_RP_PROC_CON, MAS 3.10.4): the whole
// register in one write, bit 0 ASYMMETRIC_RP_EN and two bits per RP from bit 1
// (RPn_TX_RP_SEL, the local TX lane RP n's requests go on).
class aou_reg_rp_map_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_rp_map_seq)

  bit [8:0] value = '0;

  function new(string name = "aou_reg_rp_map_seq");
    super.new(name);
  endfunction

  task body();
    want_value(field(rm.asymmetric_rp_proc_con, "asymmetric_rp_en"), uvm_reg_data_t'(value[0]));
    for (int unsigned r = 0; r < 4; r++)
      want_value(field(rm.asymmetric_rp_proc_con, $sformatf("rp%0d_tx_rp_sel", r)),
                 uvm_reg_data_t'(value[1 + 2 * r +: 2]));
    commit();
  endtask
endclass
