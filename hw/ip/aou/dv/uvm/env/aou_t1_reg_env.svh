// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// aou_reg_env with the register block also reachable as `model`, the name
// the test layer API uses. Hardware changes registers while traffic runs, so
// the env is not quiet.
class aou_t1_reg_env extends aou_reg_env;
  `uvm_component_utils(aou_t1_reg_env)

  aou_core model;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    quiet = 1'b0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    model = regmodel;
    // The mirror starts at zero until reset(); a partial write (want/commit)
    // builds the register value from it and would zero every field it leaves
    // alone, e.g. AXI_QOS_TO_HP/NP when only ARB_MODE is programmed.
    model.reset();
  endfunction
endclass
