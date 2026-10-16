// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Reserved bits and unmapped offsets.
//  REG-R06: writing 1s to a register's reserved bits leaves them reading 0 and
//           changes no other field.
//  REG-R07: writes to unmapped offsets in the decoded window change no register.
class aou_reg_reserved_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_reserved_seq)

  int unsigned n_holes = 32;
  // Decoded window in bytes; the register map ends below it.
  bit [31:0] window = 32'h0001_0000;

  function new(string name = "aou_reg_reserved_seq");
    super.new(name);
  endfunction

  task body();
    uvm_reg regs[$];
    bit [31:0] holes[$];
    bit [31:0] map_end = 0;
    get_regs(regs);
    foreach (regs[i]) begin
      uvm_reg_data_t rmask = aou_reg_policy::reserved_mask(regs[i]);
      if (32'(regs[i].get_address()) + 4 > map_end) map_end = 32'(regs[i].get_address()) + 4;
      if (rmask == 0) continue;
      wr_reg(regs[i], base_value(regs[i]) | rmask);
      check_reg(regs[i], "", "after writing 1s to the reserved bits");
      wr_reg(regs[i], base_value(regs[i]));
      check_reg(regs[i], "", "after clearing the reserved bits");
    end

    holes.push_back(map_end);
    holes.push_back(window - 4);
    repeat (n_holes) holes.push_back($urandom_range(window - 4, map_end) & ~32'h3);
    foreach (holes[h]) begin
      bit [31:0] d = $urandom();
      bit err;
      raw(AOU_APB_WRITE, holes[h], d, err);
      raw(AOU_APB_READ, holes[h], d, err);
      `uvm_info(get_type_name(), $sformatf("unmapped 0x%08h reads 0x%08h, PSLVERR=%0b",
                                           holes[h], d, err), UVM_MEDIUM)
    end
    foreach (regs[i])
      check_reg(regs[i], "REG-R07", "after writes to unmapped offsets");
  endtask
endclass
