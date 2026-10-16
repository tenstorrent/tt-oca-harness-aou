// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// [NEG] Duplicate DEST_RP values (plan 12.12, MAS 3.10.3): RP1 is mapped to
// the same remote plane as RP0, the remote die's map is the identity. The MAS
// says nothing detects it: no interrupt or error is flagged, and credits for a
// remote plane no local RP maps to fall to RP0's view (silent credit
// accounting errors). Traffic both ways on RP0, RP2 and RP3 (RP1 idle: its
// responses could not reach it). Checked: AXI messages carry the programmed
// DEST_RP (FEAT-R09, so RP0 and RP1 share a plane), data end to end, no
// interrupt; a DUT message beyond its credit (AOU-R16) is allowed, as the MAS
// describes. Needs 4 RPs.
class aou_dest_rp_dup_test extends aou_dest_rp_test;
  `uvm_component_utils(aou_dest_rp_dup_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    super.set_knobs();
    if (AOU_T1_RP_COUNT < 4) `uvm_fatal(get_type_name(), "needs a 4-RP build")
    perm = '{0, 0, 2, 3};
    foreach (perm[r]) k.feat.dest_rp[r] = perm[r];
    k.rp_mask = 4'b1101;
  endfunction

  function void configure_test();
    for (int unsigned r = 0; r < 4; r++) cfg.l3_cfg.dest_rp[r] = 2'(r);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    env.expects.add("AOU-R16", 0, 0);
  endfunction
endclass
