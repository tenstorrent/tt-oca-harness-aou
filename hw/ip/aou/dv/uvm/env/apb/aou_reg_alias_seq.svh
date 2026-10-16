// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Address decode above the register window. The documents give a 32-bit APB
// address but no decode width or behaviour for addresses above the map; this
// sequence takes the window as decode_bits wide (16: offsets repeat every
// 64 KiB) and checks it.
//  REG-R08: a write to offset + k * 2^decode_bits updates the register at offset.
//  REG-R09: a read from offset + k * 2^decode_bits returns that register.
class aou_reg_alias_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_alias_seq)

  int unsigned decode_bits = 16;
  int unsigned iterations = 2;

  function new(string name = "aou_reg_alias_seq");
    super.new(name);
  endfunction

  function bit [31:0] alias_of(uvm_reg rg);
    bit [31:0] k = $urandom_range((32'h1 << (32 - decode_bits)) - 1, 1);
    return (k << decode_bits) | 32'(rg.get_address());
  endfunction

  task body();
    uvm_reg regs[$];
    get_regs(regs);
    repeat (iterations) begin
      regs.shuffle();
      foreach (regs[i]) begin
        bit [31:0] a, d;
        bit err;
        uvm_reg_data_t smask = aou_reg_policy::storage_mask(regs[i]);
        if (smask != 0) begin
          a = alias_of(regs[i]);
          d = $urandom() & 32'(smask);
          raw(AOU_APB_WRITE, a, d, err);
          if (err)
            `uvm_error(get_type_name(), $sformatf("REG-R10: write to 0x%08h returned PSLVERR", a))
          // The predictor only maps the base window, so predict the aliased write here.
          void'(regs[i].predict(uvm_reg_data_t'(d), .kind(UVM_PREDICT_WRITE)));
          check_reg(regs[i], "REG-R08", $sformatf("after writing 0x%08h at alias 0x%08h", d, a));
        end
        a = alias_of(regs[i]);
        d = 0;
        raw(AOU_APB_READ, a, d, err);
        check_alias_read(regs[i], a, d, err);
      end
    end
  endtask

  function void check_alias_read(uvm_reg rg, bit [31:0] a, bit [31:0] d, bit err);
    uvm_reg_field fields[$];
    if (err) `uvm_error(get_type_name(), $sformatf("REG-R10: read of 0x%08h returned PSLVERR", a))
    rg.get_fields(fields);
    foreach (fields[i]) begin
      uvm_reg_data_t got, exp;
      if (fields[i].get_compare() == UVM_NO_CHECK || fields[i].get_access() == "WO") continue;
      got = (uvm_reg_data_t'(d) & aou_reg_policy::field_mask(fields[i])) >> fields[i].get_lsb_pos();
      exp = fields[i].get_mirrored_value();
      if (got != exp)
        `uvm_error(get_type_name(), $sformatf(
                   "REG-R09: %s read 0x%0h at alias 0x%08h, expected 0x%0h",
                   fields[i].get_full_name(), got, a, exp))
    end
  endfunction
endclass
