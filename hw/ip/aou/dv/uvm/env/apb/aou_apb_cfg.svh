// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Configuration of one APB agent.
class aou_apb_cfg extends uvm_object;
  virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)) vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  // config_db key of the interface (see docs/ARCHITECTURE.md).
  string vif_key = "apb";
  // Idle PCLK cycles between transfers, drawn per transfer from [min, max].
  int unsigned min_idle_cycles = 0;
  int unsigned max_idle_cycles = 2;
  // Go straight from the completing ACCESS cycle to the next SETUP when the
  // sequencer already holds another transfer (APB3 allows it).
  bit back_to_back = 1'b0;
  // PREADY may stay low this many ACCESS cycles before APB-R14 fires. The DUT's
  // asynchronous bridge inserts waits while it crosses into the core clock.
  int unsigned max_wait_cycles = 64;
  // While set the driver finishes a transfer already started but begins no new
  // one, leaving PSEL low (the reset agent's quiesce_apb()).
  bit hold = 1'b0;

  `uvm_object_utils(aou_apb_cfg)

  function new(string name = "aou_apb_cfg");
    super.new(name);
  endfunction
endclass
