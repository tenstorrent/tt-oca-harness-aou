// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Access-policy check: random full-register writes, each followed by a readback
// compared field by field against the RDL access policy as predicted by the
// register model (REG-R02 RW stores, REG-R03 RO ignores writes, REG-R04 W1C,
// REG-R06 reserved). Self-clearing controls stay 0 here; REG-R05 checks the
// write-only DEACTIVATE_FORCE reads back as 0, and REG-R11 that AOU_SW_RESET (RW
// in the RDL and MAS) reads back as written.
class aou_reg_access_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_access_seq)

  int unsigned iterations = 4;

  function new(string name = "aou_reg_access_seq");
    super.new(name);
  endfunction

  task body();
    uvm_reg regs[$];
    uvm_reg_data_t got;
    get_regs(regs);
    repeat (iterations) begin
      regs.shuffle();
      foreach (regs[i]) begin
        uvm_reg_data_t val = uvm_reg_data_t'($urandom());
        val &= ~aou_reg_policy::side_effect_mask(regs[i]);
        wr_reg(regs[i], val);
        check_reg(regs[i], "", $sformatf("after writing 0x%08h", val));
      end
    end
    // Write-only: with the protocol already DISABLED the force has nothing to do.
    wr_reg(rm.aou_con0, base_value(rm.aou_con0) | 1);
    rd_field(rm.aou_con0.deactivate_force, got);
    if (got != 0)
      `uvm_error(get_type_name(), $sformatf("REG-R05: %s (WO) read 0x%0h, expected 0",
                                            rm.aou_con0.deactivate_force.get_full_name(), got))
    want(rm.aou_con0.aou_sw_reset, 1);
    commit();
    rd_field(rm.aou_con0.aou_sw_reset, got);
    if (got != 1)
      `uvm_error(get_type_name(), $sformatf("REG-R11: %s (RW) read 0x%0h after writing 1",
                                            rm.aou_con0.aou_sw_reset.get_full_name(), got))
    // Which registers a software reset clears is not documented: report, and let
    // the readbacks resynchronise the mirror.
    foreach (regs[i]) begin
      uvm_reg_data_t v;
      rd_reg(regs[i], v);
      `uvm_info(get_type_name(), $sformatf("after AOU_SW_RESET: %s = 0x%08h",
                                           regs[i].get_name(), v), UVM_MEDIUM)
    end
    want(rm.aou_con0.aou_sw_reset, 0);
    commit();
  endtask
endclass
