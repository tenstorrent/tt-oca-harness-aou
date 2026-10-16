// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Destination RP on the remote die for traffic from one local RP (DEST_RP.RPn_DEST).
class aou_reg_dest_rp_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_dest_rp_seq)

  int unsigned rp = 0;
  int unsigned dest = 0;

  function new(string name = "aou_reg_dest_rp_seq");
    super.new(name);
  endfunction

  task body();
    want(field(rm.dest_rp, $sformatf("rp%0d_dest", rp)), int'(dest));
    commit();
  endtask
endclass
