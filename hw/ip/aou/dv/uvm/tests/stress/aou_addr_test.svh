// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Address corners in both directions at once (plan 7.12-7.15): +dp_addr=
// zero|top|sweep|4k runs aou_addr_seq on the local manager (to the remote
// memory) and the remote manager (to the local memory) of RP0. A burst
// across 4KB is illegal AXI4 and is not sent; what the DUT does with one
// from the remote die is unspecified (BUGS/026 draft).
class aou_addr_test extends aou_dp_base_test;
  `uvm_component_utils(aou_addr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_addr_vseq";
    use_dp_seq = 1'b0;
  endfunction
endclass
