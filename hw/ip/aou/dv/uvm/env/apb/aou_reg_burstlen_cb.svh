// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// MAS (architecture.adoc, splitter): MAX_AWBURSTLEN/MAX_ARBURSTLEN accept only
// 2^n - 1; any other written value is stored as 0xF. The RDL describes the fields
// as plain RW, so the model gets this rule as a prediction callback. The path
// argument's type is uvm_path_e in UVM 1.2 and uvm_door_e from 1800.2-2017 on
// (uvm-core keeps the old name as an alias, the simulator-shipped IEEE libraries
// do not), so it is chosen by the library's version macro.
class aou_reg_burstlen_cb extends uvm_reg_cbs;
  `uvm_object_utils(aou_reg_burstlen_cb)

  function new(string name = "aou_reg_burstlen_cb");
    super.new(name);
  endfunction

  static function bit is_legal(uvm_reg_data_t v);
    return v inside {0, 1, 3, 7, 15, 31, 63, 127, 255};
  endfunction

  virtual function void post_predict(input uvm_reg_field fld, input uvm_reg_data_t previous,
                                     inout uvm_reg_data_t value, input uvm_predict_e kind,
`ifdef UVM_VERSION_POST_2017
                                     input uvm_door_e path, input uvm_reg_map map);
`else
                                     input uvm_path_e path, input uvm_reg_map map);
`endif
    if (kind == UVM_PREDICT_WRITE && !is_legal(value)) value = 'hF;
  endfunction
endclass
