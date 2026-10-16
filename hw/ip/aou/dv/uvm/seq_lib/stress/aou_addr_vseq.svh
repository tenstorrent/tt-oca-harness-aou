// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Runs aou_addr_seq (+dp_addr=) in both directions on RP0 (aou_addr_test).
class aou_addr_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_addr_vseq)

  function new(string name = "aou_addr_vseq");
    super.new(name);
  endfunction

  task scenario();
    string mode = "zero";
    void'($value$plusargs("dp_addr=%s", mode));
    fork
      begin
        aou_addr_seq s = aou_addr_seq::type_id::create("l2r");
        s.mode = mode;
        s.start(p_sequencer.s_mgr_sqr[0]);
      end
      begin
        aou_addr_seq s = aou_addr_seq::type_id::create("r2l");
        s.mode = mode;
        s.start(p_sequencer.r_mgr_sqr[0]);
      end
    join
  endtask
endclass
