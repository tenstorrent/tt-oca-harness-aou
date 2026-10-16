// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One raw APB transfer, outside the register model (e.g. to unmapped or
// aliased addresses). After start(), data and slverr hold the response.
class aou_apb_rw_seq extends uvm_sequence #(aou_apb_item);
  `uvm_object_utils(aou_apb_rw_seq)

  aou_apb_dir_e dir = AOU_APB_READ;
  bit [31:0]    addr = '0;
  bit [31:0]    data;
  bit           slverr;

  function new(string name = "aou_apb_rw_seq");
    super.new(name);
  endfunction

  task body();
    aou_apb_item it = aou_apb_item::type_id::create("it");
    start_item(it);
    it.dir  = dir;
    it.addr = addr;
    it.data = (dir == AOU_APB_WRITE) ? data : '0;
    finish_item(it);
    data   = it.data;
    slverr = it.slverr;
  endtask
endclass
