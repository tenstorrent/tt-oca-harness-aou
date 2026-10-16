// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Issue #56: every size at every byte offset of the bus word (single beats,
// written then read), then unaligned narrow bursts with random strobes, each
// read back. Both directions.
class aou_dp_unaligned_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_dp_unaligned_vseq)

  function new(string name = "aou_dp_unaligned_vseq");
    super.new(name);
  endfunction

  task scenario();
    traffic(k.dir, 0, aou_t1_traffic_cfg::named("unaligned"));
    traffic(k.dir, num_txns, make_profile());
  endtask
endclass
