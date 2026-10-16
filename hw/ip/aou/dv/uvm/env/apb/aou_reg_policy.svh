// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Which register fields the testbench compares, and which it may write freely.
//
// PeakRDL-uvm marks every field volatile (the RDL leaves `hw` at its default),
// which turns off every mirror comparison. apply() restores comparison for the
// fields that only software changes, using the RDL's own descriptions:
//   - status fields with no reset value in the RDL (driven by module inputs);
//   - self-clearing controls (RDL: "Self-clears when ..."): activate_start,
//     deactivate_start, deactivate_force;
//   - when traffic can run (quiet = 0), fields hardware sets on events: the W1C
//     error/interrupt flags and invalid_actmsg_info.
// Self-clearing controls start activation or deactivation, and AOU_SW_RESET
// resets the core, so generic tests write them as 0 (side_effect_mask).
// MAX_AxBURSTLEN gets the MAS's legal-value rule (aou_reg_burstlen_cb).
class aou_reg_policy extends uvm_object;
  `uvm_object_utils(aou_reg_policy)

  function new(string name = "aou_reg_policy");
    super.new(name);
  endfunction

  static function bit is_self_clearing(uvm_reg_field f);
    string n = f.get_name();
    return n inside {"activate_start", "deactivate_start", "deactivate_force"};
  endfunction

  static function bit is_hw_status(uvm_reg_field f);
    return !f.has_reset();
  endfunction

  static function bit is_hw_set(uvm_reg_field f);
    return f.get_access() == "W1C" || f.get_name() == "invalid_actmsg_info";
  endfunction

  static function bit is_reserved(uvm_reg_field f);
    string n = f.get_name();
    return n.len() >= 8 && n.substr(0, 7) == "reserved";
  endfunction

  static function bit is_checked(uvm_reg_field f, bit quiet);
    return !(is_hw_status(f) || is_self_clearing(f) || (!quiet && is_hw_set(f)));
  endfunction

  // quiet: no traffic or link activity can set hardware status during the test.
  static function void apply(uvm_reg_block blk, bit quiet);
    uvm_reg_field fields[$];
    aou_reg_burstlen_cb burstlen_cb = aou_reg_burstlen_cb::type_id::create("burstlen_cb");
    blk.get_fields(fields);
    foreach (fields[i]) begin
      bit chk = is_checked(fields[i], quiet);
      if (fields[i].get_name() inside {"max_arburstlen", "max_awburstlen"})
        uvm_reg_field_cb::add(fields[i], burstlen_cb);
      fields[i].set_compare(chk ? UVM_CHECK : UVM_NO_CHECK);
      // Volatility only feeds update() and a warning on every mirror read;
      // comparison is what decides, so all fields are made non-volatile.
      fields[i].set_volatility(1'b0);
    end
  endfunction

  static function uvm_reg_data_t field_mask(uvm_reg_field f);
    return ((uvm_reg_data_t'(1) << f.get_n_bits()) - 1) << f.get_lsb_pos();
  endfunction

  // Bits generic tests must write as 0.
  static function uvm_reg_data_t side_effect_mask(uvm_reg rg);
    uvm_reg_field fields[$];
    uvm_reg_data_t m = 0;
    rg.get_fields(fields);
    foreach (fields[i])
      if (is_self_clearing(fields[i]) || fields[i].get_name() == "aou_sw_reset")
        m |= field_mask(fields[i]);
    return m;
  endfunction

  static function uvm_reg_data_t reserved_mask(uvm_reg rg);
    uvm_reg_field fields[$];
    uvm_reg_data_t m = 0;
    rg.get_fields(fields);
    foreach (fields[i]) if (is_reserved(fields[i])) m |= field_mask(fields[i]);
    return m;
  endfunction

  // Fields whose written value is stored and read back (RW).
  static function uvm_reg_data_t storage_mask(uvm_reg rg);
    uvm_reg_field fields[$];
    uvm_reg_data_t m = 0;
    rg.get_fields(fields);
    foreach (fields[i])
      if (fields[i].get_access() == "RW" && !is_self_clearing(fields[i]) &&
          fields[i].get_name() != "aou_sw_reset")
        m |= field_mask(fields[i]);
    return m;
  endfunction
endclass
