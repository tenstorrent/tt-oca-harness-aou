// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of the register sequences: field writes that never re-trigger
// self-clearing controls or W1C flags, and readback checks against the mirror.
// Start with start(null) after setting rm (and apb_sqr for raw transfers).
class aou_reg_base_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(aou_reg_base_seq)

  aou_core          rm;
  aou_apb_sequencer apb_sqr;

  local uvm_reg_field  pend_f[$];
  local uvm_reg_data_t pend_v[$];

  function new(string name = "aou_reg_base_seq");
    super.new(name);
  endfunction

  task pre_body();
    if (rm == null) `uvm_fatal(get_type_name(), "rm (register model) not set")
  endtask

  // Value to write to rg so that only the intended fields change: stored fields
  // keep their mirrored values; self-clearing, W1C, write-only and reserved
  // fields are 0.
  function uvm_reg_data_t base_value(uvm_reg rg);
    uvm_reg_field fields[$];
    uvm_reg_data_t v = 0;
    rg.get_fields(fields);
    foreach (fields[i])
      if ((aou_reg_policy::field_mask(fields[i]) & aou_reg_policy::storage_mask(rg)) != 0)
        v |= fields[i].get_mirrored_value() << fields[i].get_lsb_pos();
    return v;
  endfunction

  // Queues a field update; a negative value leaves the field alone.
  function void want(uvm_reg_field f, int v);
    if (v < 0) return;
    want_value(f, uvm_reg_data_t'(v));
  endfunction

  // Queues a field update with any value; no sentinel, so a 32-bit field with
  // bit 31 set is written rather than skipped.
  function void want_value(uvm_reg_field f, uvm_reg_data_t v);
    if (f == null) `uvm_fatal(get_type_name(), "want: null field")
    pend_f.push_back(f);
    pend_v.push_back(v);
  endfunction

  function uvm_reg_field field(uvm_reg rg, string name);
    field = rg.get_field_by_name(name);
    if (field == null) `uvm_fatal(get_type_name(), {"no field ", name, " in ", rg.get_name()})
  endfunction

  // Writes the queued fields, one register write per register touched.
  task commit();
    uvm_reg regs[$];
    foreach (pend_f[i]) begin
      uvm_reg rg = pend_f[i].get_parent();
      bit seen = 1'b0;
      foreach (regs[r]) if (regs[r] == rg) seen = 1'b1;
      if (!seen) regs.push_back(rg);
    end
    foreach (regs[r]) begin
      uvm_reg_data_t val = base_value(regs[r]);
      foreach (pend_f[i]) begin
        if (pend_f[i].get_parent() != regs[r]) continue;
        val &= ~aou_reg_policy::field_mask(pend_f[i]);
        val |= (pend_v[i] << pend_f[i].get_lsb_pos()) & aou_reg_policy::field_mask(pend_f[i]);
      end
      wr_reg(regs[r], val);
    end
    pend_f.delete();
    pend_v.delete();
  endtask

  task wr_reg(uvm_reg rg, uvm_reg_data_t val);
    uvm_status_e status;
    rg.write(.status(status), .value(val), .path(UVM_FRONTDOOR), .parent(this));
    if (status != UVM_IS_OK)
      `uvm_error(get_type_name(), $sformatf("REG-R10: write of 0x%08h to %s returned %s",
                                            val, rg.get_full_name(), status.name()))
  endtask

  task rd_reg(uvm_reg rg, output uvm_reg_data_t val);
    uvm_status_e status;
    rg.read(.status(status), .value(val), .path(UVM_FRONTDOOR), .parent(this));
    if (status != UVM_IS_OK)
      `uvm_error(get_type_name(), $sformatf("REG-R10: read of %s returned %s",
                                            rg.get_full_name(), status.name()))
  endtask

  task rd_field(uvm_reg_field f, output uvm_reg_data_t val);
    uvm_reg_data_t r;
    rd_reg(f.get_parent(), r);
    val = (r & aou_reg_policy::field_mask(f)) >> f.get_lsb_pos();
  endtask

  // Reads rg and compares every compared field with its mirrored value. With no
  // rule given, the rule follows the field's access policy.
  task check_reg(uvm_reg rg, string rule = "", string why = "");
    uvm_reg_field fields[$];
    uvm_reg_data_t exp[$];
    uvm_reg_data_t act;
    rg.get_fields(fields);
    foreach (fields[i])
      exp.push_back(fields[i].get_compare() == UVM_NO_CHECK ? 0 : fields[i].get_mirrored_value());
    rd_reg(rg, act);
    foreach (fields[i]) begin
      uvm_reg_data_t got;
      string r = rule;
      if (fields[i].get_compare() == UVM_NO_CHECK || fields[i].get_access() == "WO") continue;
      got = (act & aou_reg_policy::field_mask(fields[i])) >> fields[i].get_lsb_pos();
      if (got == exp[i]) continue;
      if (r == "") r = rule_for(fields[i]);
      `uvm_error(get_type_name(), $sformatf("%s: %s (%s) read 0x%0h, expected 0x%0h%s",
                 r, fields[i].get_full_name(), fields[i].get_access(), got, exp[i],
                 why == "" ? "" : {" ", why}))
    end
    // Reserved bits are always expected to read 0, whatever was read just now.
    foreach (fields[i])
      if (aou_reg_policy::is_reserved(fields[i])) void'(fields[i].predict(0));
  endtask

  static function string rule_for(uvm_reg_field f);
    if (aou_reg_policy::is_reserved(f)) return "REG-R06";
    case (f.get_access())
      "RW":    return "REG-R02";
      "W1C":   return "REG-R04";
      default: return "REG-R03";
    endcase
  endfunction

  // Raw APB transfer outside the register map.
  task raw(aou_apb_dir_e dir, bit [31:0] addr, inout bit [31:0] data, output bit slverr);
    aou_apb_rw_seq s = aou_apb_rw_seq::type_id::create("raw");
    if (apb_sqr == null) `uvm_fatal(get_type_name(), "apb_sqr not set; raw transfers need it")
    s.dir  = dir;
    s.addr = addr;
    s.data = data;
    s.start(apb_sqr, this);
    data   = s.data;
    slverr = s.slverr;
  endtask

  function void get_regs(output uvm_reg regs[$]);
    rm.get_registers(regs);
  endfunction
endclass
