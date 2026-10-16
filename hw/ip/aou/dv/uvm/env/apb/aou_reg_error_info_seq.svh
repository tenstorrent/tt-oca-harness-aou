// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Error information of one RP: optionally sets AOU_CON0.RPn_ERROR_INFO_ACCESS_EN,
// reads ERROR_INFO_RPn, WRITE_EARLY_RESPONSE_RPn, AXI_ERROR_INFO0/1_RPn and
// AXI_SLV_ID_MISMATCH_ERR_RPn plus LP_LINKRESET, and with clear set writes 1 to
// every W1C flag that read 1.
class aou_reg_error_info_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_error_info_seq)

  int unsigned rp = 0;
  int          access_en = -1;
  bit          clear = 1'b0;

  // Results (raw register values).
  uvm_reg_data_t error_info;
  uvm_reg_data_t write_early_response;
  uvm_reg_data_t axi_error_info0;
  uvm_reg_data_t axi_error_info1;
  uvm_reg_data_t slv_id_mismatch_err;
  uvm_reg_data_t lp_linkreset;

  function new(string name = "aou_reg_error_info_seq");
    super.new(name);
  endfunction

  function uvm_reg rp_reg(string base);
    return rm.get_reg_by_name($sformatf("%s_rp%0d", base, rp));
  endfunction

  task body();
    uvm_reg rgs[$];
    uvm_reg_data_t vals[$];
    want(field(rm.aou_con0, $sformatf("rp%0d_error_info_access_en", rp)), access_en);
    commit();
    rd_reg(rp_reg("error_info"), error_info);
    rd_reg(rp_reg("write_early_response"), write_early_response);
    rd_reg(rp_reg("axi_error_info0"), axi_error_info0);
    rd_reg(rp_reg("axi_error_info1"), axi_error_info1);
    rd_reg(rp_reg("axi_slv_id_mismatch_err"), slv_id_mismatch_err);
    rd_reg(rm.lp_linkreset, lp_linkreset);
    `uvm_info(get_type_name(), $sformatf(
              {"RP%0d error_info=0x%08h early_resp=0x%08h info0=0x%08h info1=0x%08h",
               " slv_id=0x%08h lp_linkreset=0x%08h"},
              rp, error_info, write_early_response, axi_error_info0, axi_error_info1,
              slv_id_mismatch_err, lp_linkreset), UVM_MEDIUM)
    if (!clear) return;
    rgs = '{rp_reg("error_info"), rp_reg("write_early_response"),
            rp_reg("axi_slv_id_mismatch_err"), rm.lp_linkreset};
    vals = '{error_info, write_early_response, slv_id_mismatch_err, lp_linkreset};
    foreach (rgs[r]) begin
      uvm_reg_field fields[$];
      rgs[r].get_fields(fields);
      foreach (fields[i])
        if (fields[i].get_access() == "W1C" &&
            (vals[r] & aou_reg_policy::field_mask(fields[i])) != 0)
          want(fields[i], 1);
    end
    commit();
  endtask
endclass
