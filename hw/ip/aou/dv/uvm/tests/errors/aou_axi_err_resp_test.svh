// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI error responses both ways and the response error debug FIFO
// (aou_axi_err_resp_vseq).
class aou_axi_err_resp_test extends aou_base_test;
  `uvm_component_utils(aou_axi_err_resp_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = "aou_axi_err_resp_vseq";
    num_txns = 10;
  endfunction

  function void configure();
    aou_axi_err_resp_vseq::add_regions(cfg);
  endfunction
endclass
