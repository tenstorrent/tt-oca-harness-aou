// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Loopback with a non-identity DEST_RP (MAS 3.10): die A maps its planes
// through a random derangement, die B through the inverse. Every request
// travels on the peer's plane and its response returns on the sender's own
// plane, so each model must close its outstanding requests and ARSIZE
// bookkeeping (AOU-R13) by plane, not by the RP a response arrives on.
class aou_l3_dest_rp_test extends aou_l3_loopback_test;
  `uvm_component_utils(aou_l3_dest_rp_test)

  bit [1:0] perm[4];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    bit [1:0] q[$] = '{2'd0, 2'd1, 2'd2, 2'd3};
    bit fixed;
    super.build_phase(phase);
    do begin
      q.shuffle();
      fixed = 1'b0;
      foreach (q[p]) if (q[p] == 2'(p)) fixed = 1'b1;
    end while (fixed);
    foreach (perm[p]) begin
      perm[p] = q[p];
      cfg_a.dest_rp[p] = perm[p];
      cfg_b.dest_rp[perm[p]] = 2'(p);
    end
    `uvm_info(get_type_name(), $sformatf("DEST_RP A=%p B=%p", cfg_a.dest_rp, cfg_b.dest_rp),
              UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    uvif.drv_cb.dest_rp <= {perm[3], perm[2], perm[1], perm[0]};
    super.run_phase(phase);
  endtask

  function void check_phase(uvm_phase phase);
    int unsigned left = 0;
    super.check_phase(phase);
    for (int r = 0; r < AOU_RP_MAX; r++)
      left += a.model.our_wr_out[r] + a.model.our_rd_out[r] + a.model.dut_wr_out[r] +
              a.model.dut_rd_out[r] + b.model.our_wr_out[r] + b.model.our_rd_out[r] +
              b.model.dut_wr_out[r] + b.model.dut_rd_out[r];
    expect_true(left == 0, $sformatf("outstanding counters drained (%0d left)", left));
  endfunction
endclass
